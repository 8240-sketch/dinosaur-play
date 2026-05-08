# ADR-0007: AutoLoad Initialization Order and Boot Protocol

## Status
Proposed

## Date
2026-05-08

## Engine Compatibility

| Field | Value |
|-------|-------|
| **Engine** | Godot 4.6 |
| **Domain** | Core (Initialization / Boot) |
| **Knowledge Risk** | LOW — AutoLoad loading order and `_ready()` execution are stable across all Godot 4.x versions |
| **References Consulted** | `docs/engine-reference/godot/VERSION.md` |
| **Post-Cutoff APIs Used** | None — AutoLoad mechanics are unchanged since Godot 4.0 |
| **Verification Required** | Boot test: verify all 8 AutoLoads initialize without errors; verify no `_ready()` calls upstream API before it's available |

## ADR Dependencies

| Field | Value |
|-------|-------|
| **Depends On** | ADR-0004 (SaveSystem); ADR-0005 (ProfileManager); ADR-0006 (VocabStore) — all define the systems whose init order this ADR governs |
| **Enables** | All system implementation — no system can _ready() before this ADR defines the boot sequence |
| **Blocks** | Any system's _ready() implementation; GameScene first-load routing |
| **Ordering Note** | ADR-0004–0006 must be Accepted to know which systems exist and their dependencies. This ADR must be Accepted before any system's _ready() is coded. |

## Context

### Problem Statement

Godot loads AutoLoad singletons sequentially in Project Settings order, calling `_ready()` on each before proceeding to the next. With 8 AutoLoads in this project, the loading order determines which APIs are available at `_ready()` time. If a downstream system's `_ready()` calls an upstream API that hasn't been initialized yet, the call crashes with a null reference.

This ADR formalizes the mandatory loading order and documents which systems must be connected before any scene loads.

### Constraints
- Godot AutoLoad loading order is set in Project Settings — cannot be changed at runtime
- 8 AutoLoads is near Godot's practical ceiling (LP-CONCERN-1 from architecture review)
- Some `_ready()` methods perform I/O (SaveSystem .tmp scan, VoiceRecorder permission request)
- Scene tree loads AFTER all AutoLoads have `_ready()`'d

### Requirements
- Every AutoLoad's `_ready()` must be able to call APIs of all AutoLoads loaded before it
- No AutoLoad's `_ready()` may call APIs of AutoLoads loaded after it
- InterruptHandler must load last (depends on StoryManager + VoiceRecorder signals)
- Total boot time should be profiled; if >500ms, consider merging InterruptHandler into StoryManager

## Decision

Adopt **Fixed Sequential Loading with Dependency-Ordered Project Settings** for AutoLoad initialization.

### Mandatory Loading Order

```
① SaveSystem          — Foundation: no game deps
     _ready(): .tmp recovery scan (<1ms)

② ProfileManager      — depends on: SaveSystem
     _ready(): load_profile(0) → set initial state

③ VocabStore          — depends on: ProfileManager
     _ready(): get_section("vocab_progress") → _reset_session_counters()

④ TtsBridge           — no game deps (configure() deferred to GameRoot)
     _ready(): add HTTPRequest + AudioStreamPlayer children

⑤ AudioManager        — no game deps (BGM AudioStreamPlayer)
     _ready(): add BGMPlayer child (<0.1ms)

⑥ StoryManager        — depends on: VocabStore, TtsBridge, TagDispatcher
     _ready(): assert InkRuntime.get_singleton() != null

⑦ TagDispatcher       — depends on: StoryManager, AnimationHandler (scene-local)
     _ready(): empty (registration deferred to begin_chapter)

⑧ VoiceRecorder       — depends on: ProfileManager, SaveSystem
     _ready(): OS.request_permission("RECORD_AUDIO")

⑨ InterruptHandler    — depends on: StoryManager, VoiceRecorder
     _ready(): connect to SM.chapter_interrupted + VR.recording_interrupted
```

### Boot Sequence Diagram

```
Godot Engine
    │
    ▼
AutoLoad ① SaveSystem._ready()
    │  ├─ scan .tmp files, recover if needed
    │  └─ ready
    ▼
AutoLoad ② ProfileManager._ready()
    │  ├─ SaveSystem.load_profile(0)
    │  ├─ set state (NO_ACTIVE_PROFILE or ACTIVE)
    │  └─ ready
    ▼
AutoLoad ③ VocabStore._ready()
    │  ├─ ProfileManager.get_section("vocab_progress")
    │  ├─ connect profile_switch_requested + profile_switched
    │  └─ ready
    ▼
AutoLoad ④ TtsBridge._ready()
    │  ├─ add HTTPRequest child
    │  ├─ add AudioStreamPlayer child
    │  └─ ready
    ▼
AutoLoad ⑤ AudioManager._ready()
    │  └─ add BGMPlayer child (<0.1ms)
    ▼
AutoLoad ⑥ StoryManager._ready()
    │  ├─ assert InkRuntime.get_singleton() != null
    │  └─ ready
    ▼
AutoLoad ⑦ TagDispatcher._ready()
    │  └─ ready (empty — registration deferred)
    ▼
AutoLoad ⑧ VoiceRecorder._ready()
    │  ├─ OS.request_permission("RECORD_AUDIO")
    │  └─ ready
    ▼
AutoLoad ⑨ InterruptHandler._ready()
    │  ├─ connect StoryManager.chapter_interrupted
    │  ├─ connect VoiceRecorder.recording_interrupted
    │  └─ ready
    ▼
Scene Tree loads first scene:
    ├─ times_played == 0 → HatchScene.tscn
    └─ times_played > 0 → MainMenu.tscn
```

### _ready() Contract

```gdscript
# Every AutoLoad _ready() MUST:
# 1. Only call APIs of systems loaded BEFORE this one (lower number)
# 2. Use is_instance_valid() guard for scene-local dependencies
# 3. Complete synchronously (no await)
# 4. Not navigate scenes (scene navigation happens AFTER all AutoLoads ready)

# Example: VocabStore._ready()
func _ready() -> void:
    # Safe: ProfileManager (②) is already ready
    _vocab_data = ProfileManager.get_section("vocab_progress")
    # Safe: connect signals (deferred — handlers run after current _ready)
    ProfileManager.profile_switch_requested.connect(_on_profile_switch_requested)
    ProfileManager.profile_switched.connect(_on_profile_switched)
    _reset_session_counters()
```

### Key Interfaces

```gdscript
# No new public interfaces — this ADR governs boot ORDER, not API shape.
# Each system's _ready() follows the contract above.
# The loading order is configured in Project Settings → AutoLoad tab.
```

## Alternatives Considered

### Alternative B: Dynamic Loading + Deferred Init

- **Description**: AutoLoads load in arbitrary order; each system defers its `_ready()` logic until all dependencies signal readiness via a shared "boot complete" signal.
- **Pros**: No ordering constraint; systems can be added/removed without editing Project Settings
- **Cons**: Adds a boot-state machine (UNREADY/READY); every system must handle deferred init; increases code complexity significantly; debugging boot order failures becomes harder
- **Rejection Reason**: Over-engineering for 8 systems with a clear, static dependency graph. The fixed order is simple, verifiable, and matches Godot's native loading model.

### Alternative C: Dependency Injection Container

- **Description**: A central DI container manages system registration and resolution. Systems request dependencies from the container rather than referencing AutoLoads directly.
- **Pros**: Maximum flexibility; testable; no implicit ordering
- **Cons**: Godot has no built-in DI; requires a custom implementation (~200 lines GDScript); adds indirection that makes code harder to follow; AutoLoad singletons already serve as a DI mechanism
- **Rejection Reason**: AutoLoad singletons ARE the DI mechanism in Godot. Adding a container on top adds complexity without solving a real problem. The dependency graph is static and known at design time.

## Consequences

### Positive
- **Simplicity**: Fixed order is easy to understand, document, and verify
- **No new engine APIs**: Uses Godot's native AutoLoad mechanism
- **Debuggable**: If a system crashes at _ready(), the loading order immediately identifies the missing dependency
- **LP-CONCERN-1 addressed**: Boot profiling can determine if 8 AutoLoads are too many; merging option documented

### Negative
- **Loading order is a global constraint**: Adding a new AutoLoad requires checking where it fits in the dependency chain and editing Project Settings
- **8 AutoLoads near ceiling**: LP flagged this as aggressive; boot time may be an issue on low-end Android devices
- **No runtime flexibility**: Cannot defer or lazy-load AutoLoads based on scene needs

### Risks

| Risk | Severity | Mitigation |
|------|----------|------------|
| **R1: Boot time exceeds 500ms on low-end device** | MEDIUM | Profile on target device Week 1. If slow, merge InterruptHandler into StoryManager (it has no public API). |
| **R2: New developer adds AutoLoad in wrong order** | LOW | Document in CLAUDE.md. Code review checks Project Settings order matches ADR. |
| **R3: InkRuntime not available at StoryManager._ready()** | MEDIUM | `assert(InkRuntime.get_singleton() != null)` with push_error + state=ERROR if null. ADR-0001 R5 documents this. |

## GDD Requirements Addressed

| GDD System | Requirement | How This ADR Addresses It |
|------------|-------------|--------------------------|
| interrupt-handler.md | Rule: InterruptHandler loads AFTER StoryManager and VoiceRecorder | Loading order ⑧ documented |
| story-manager.md | Rule: begin_chapter() requires VocabStore + TtsBridge + TagDispatcher ready | Loading orders ③④⑥ before ⑤ |
| profile-manager.md | Rule: ProfileManager depends on SaveSystem | Loading order ② after ① |
| tts-bridge.md | Rule: TtsBridge configure() deferred to GameRoot | _ready() only adds children, no configure() call |
| architecture.md | Initialization Order section | This ADR formalizes that section |

## Performance Implications
- **CPU**: 8 × `_ready()` total: <50ms (SaveSystem .tmp scan ~1ms, ProfileManager load ~1ms, others <1ms each)
- **Memory**: 8 AutoLoad instances at boot: ~50KB total (Node overhead + script state)
- **Load Time**: Boot sequence total: <100ms on mid-range device; <200ms on low-end
- **Network**: N/A

## Migration Plan

This ADR defines the initial architecture. No migration needed.

If a future ADR adds a 9th AutoLoad (e.g., AudioManager), it must be inserted at the correct position in the dependency chain and Project Settings must be updated.

## Validation Criteria
1. All 8 AutoLoads initialize without null reference errors (boot test)
2. StoryManager._ready() can access VocabStore, TtsBridge (dependency chain verified)
3. InterruptHandler._ready() can connect to StoryManager and VoiceRecorder signals
4. Total boot time <200ms on target device (Week 1 profiling)
5. GUT test: mock AutoLoad initialization order matches ADR specification

## Related Decisions
- ADR-0001: inkgd Runtime (InkRuntime singleton availability at StoryManager._ready())
- ADR-0004: SaveSystem (loading order ①)
- ADR-0005: ProfileManager Switch (loading order ②)
- ADR-0006: VocabStore Formula (loading order ③)
- design/gdd/interrupt-handler.md — InterruptHandler GDD (must load last)
- design/gdd/story-manager.md — StoryManager GDD (depends on ③④⑥)
