# ADR-0005: ProfileManager Profile Switch Synchronous Protocol

## Status
Accepted (2026-05-09)

## Date
2026-05-08

## Engine Compatibility

| Field | Value |
|-------|-------|
| **Engine** | Godot 4.6 |
| **Domain** | Core (Scripting / State Management) |
| **Knowledge Risk** | LOW — No post-cutoff API changes affect signal dispatch or state machine patterns |
| **References Consulted** | `docs/engine-reference/godot/VERSION.md`; `docs/engine-reference/godot/current-best-practices.md` |
| **Post-Cutoff APIs Used** | None — signal dispatch and state machine patterns are stable across all Godot 4.x versions |
| **Verification Required** | GUT test: verify all `profile_switch_requested` subscribers execute synchronously (no await); test 4-state machine transitions under normal and error conditions |

## ADR Dependencies

| Field | Value |
|-------|-------|
| **Depends On** | ADR-0004 (SaveSystem atomic write — flush/load used in switch sequence) |
| **Enables** | ADR-0006 (VocabStore session counters reset depends on profile_switch_requested); all systems that subscribe to profile_switch_requested |
| **Blocks** | ProfileManager implementation; any system subscribing to profile_switch_requested or profile_switched |
| **Ordering Note** | ADR-0004 must be Accepted before this ADR. This ADR must be Accepted before ADR-0006. |

## Context

### Problem Statement

ProfileManager holds a single `_active_data` Dictionary as the authoritative in-memory representation of the current profile. When the player switches profiles (via MainMenu profile cards), the system must:

1. Flush the old profile's data to disk (via SaveSystem)
2. Load the new profile's data from disk
3. Replace `_active_data` with the new data

During steps 1–3, multiple AutoLoad subscribers hold stale references or pending state that must be cleaned up **before** the flush-load-replace window. If any subscriber uses `await` during cleanup, the flush may execute before cleanup completes, persisting stale data from the old profile into the new profile's save file.

This is a data corruption risk that cannot be caught by type checking or unit tests — it requires architectural enforcement.

### Constraints
- GDScript is single-threaded (no concurrent access), but `await` yields control to the SceneTree
- `profile_switch_requested` is emitted synchronously; any subscriber using `await` causes the signal handler chain to yield mid-switch
- 8 systems depend on ProfileManager (highest fan-out of any system)
- Profile switch can be triggered from MainMenu, InterruptHandler (profile_switch reason), or future家长模式

### Requirements
- `profile_switch_requested` handlers MUST execute synchronously (no `await`)
- Old profile data MUST be flushed to disk before new profile data is loaded
- New profile data MUST be fully loaded before any subscriber reads from it
- Profile switch MUST be atomic from the subscriber's perspective — either fully complete or fully reverted
- 4-state machine transitions MUST be well-defined with no illegal transitions

## Decision

Adopt **Synchronous Signal Dispatch with State Machine Gate** for profile switching.

### 4-State Machine

```
                    ┌──────────────────────────┐
                    │      UNINITIALIZED        │
                    │  (before first load)      │
                    └─────────┬────────────────┘
                              │ load_profile(0)
                              ▼
                    ┌──────────────────────────┐
              ┌─────│    NO_ACTIVE_PROFILE      │
              │     │  (all profiles empty)     │
              │     └─────────┬────────────────┘
              │               │ create_profile() + switch_to_profile()
              │               ▼
              │     ┌──────────────────────────┐
              │     │         ACTIVE            │◄──────────────┐
              │     │  (profile loaded)         │               │
              │     └─────────┬────────────────┘               │
              │               │ switch_to_profile()             │
              │               ▼                                │
              │     ┌──────────────────────────┐               │
              └────►│       SWITCHING           │───────────────┘
                    │  (flush → load → replace)  │  success
                    └──────────────────────────┘
                              │
                              │ flush or load fails
                              ▼
                    ┌──────────────────────────┐
                    │    (error path: state      │
                    │     reverts to previous)   │
                    └──────────────────────────┘
```

**Transition rules:**
- `UNINITIALIZED → NO_ACTIVE_PROFILE`: on first `load_profile()` returning empty default
- `NO_ACTIVE_PROFILE → ACTIVE`: on `create_profile()` + `switch_to_profile()`
- `ACTIVE → SWITCHING → ACTIVE`: normal profile switch
- `SWITCHING → ACTIVE`: flush + load success
- `SWITCHING → ACTIVE (error revert)`: flush or load failure — state reverts to previous profile, `active_profile_cleared("load_failed")` emitted

### 7-Step switch_to_profile() Sequence

```
switch_to_profile(new_index: int):
  ① PRE-CHECK: new_index in [0, MAX_SAVE_PROFILES)
     → if invalid: push_error, return
  ② PRE-CHECK: profile file exists on disk
     → if not: push_error, return
  ③ SET STATE: state = SWITCHING
  ④ SIGNAL (SYNC): emit profile_switch_requested()
     → ALL subscribers MUST execute synchronously (no await)
     → VocabStore: reset_session() — clears session counters
     → VoiceRecorder: interrupt_and_commit() — stops recording, writes/discards WAV
     → StoryManager: request_chapter_interrupt("profile_switch") — cancels timer, clears ink ref
  ⑤ FLUSH OLD: SaveSystem.flush_profile(old_index, _active_data)
     → failure = push_error only, continue (old data may be partially stale)
  ⑥ LOAD NEW: SaveSystem.load_profile(new_index) → new_data
     → if error != NONE: state reverts, emit active_profile_cleared("load_failed"), return
  ⑦ REPLACE: _active_data = duplicate_deep(new_data)
     → state = ACTIVE
     → emit profile_switched(new_index)
```

**Critical invariant**: Steps ④–⑦ execute without yielding. No `await`, no `call_deferred`, no `yield`. The entire sequence is synchronous from emit to state=ACTIVE.

### Subscriber Contract

```gdscript
# MANDATORY: All profile_switch_requested subscribers
func _on_profile_switch_requested() -> void:
    # MUST be synchronous — no await, no yield
    # Clean up session state, release references, stop active operations
    # This handler runs BEFORE flush/load — data is still the OLD profile
```

### Key Interfaces

```gdscript
class_name ProfileManager extends Node

enum State { UNINITIALIZED, NO_ACTIVE_PROFILE, ACTIVE, SWITCHING }

signal profile_switch_requested()
signal profile_switched(new_index: int)
signal active_profile_cleared(reason: String)

func create_profile(index: int, name: String, avatar_id: int) -> bool:
    # Does NOT auto-activate

func switch_to_profile(index: int) -> void:
    # 7-step synchronous sequence (ADR-0005)

func get_section(key: String) -> Dictionary:
    # Returns DIRECT REFERENCE to _active_data[key]
    # Callers must not cache across profile switch boundaries

func get_profile_header(index: int) -> Dictionary:
    # Returns {name, avatar_id, times_played, is_valid}

func begin_session() -> void:
    # Sole write point for times_played

func is_first_launch() -> bool:

func flush() -> void:
    # Convenience: flush_profile(current_index, _active_data)

func get_profile_count() -> int:
```

### Architecture Diagram

```
MainMenu taps profile card
       │
       ▼
 ProfileManager.switch_to_profile(new_index)
       │
       ├─ ① validate index
       ├─ ② validate file exists
       ├─ ③ state = SWITCHING
       │
       ├─ ④ EMIT profile_switch_requested ──────► [SYNC handlers, no await]
       │       │                                      │
       │       │                               ┌──────┴──────┐
       │       │                               ▼             ▼
       │       │                        VocabStore      VoiceRecorder
       │       │                        .reset_session() .interrupt_and_commit()
       │       │                        (counters=0)    (stop+discard or flag)
       │       │
       ├─ ⑤ SaveSystem.flush_profile(old_index, old_data)
       ├─ ⑥ SaveSystem.load_profile(new_index) → new_data
       ├─ ⑦ _active_data = duplicate_deep(new_data)
       ├─ ⑧ state = ACTIVE
       │
       └─ ⑨ EMIT profile_switched(new_index) ──► [Async handlers OK]
```

## Alternatives Considered

### Alternative B: Pre-Registration Guard Pattern

- **Description**: Each subscriber registers a guard function before the switch. ProfileManager calls all guards first, then executes the switch if all guards pass.
- **Pros**: Subscribers can reject the switch (e.g., "unsaved recording in progress"); more explicit than signal dispatch
- **Cons**: Requires ProfileManager to know about all subscribers and their guard interfaces; adds a registration API; guard functions could themselves use `await`; complex error handling if a guard rejects mid-sequence
- **Rejection Reason**: The game has no scenario where a profile switch should be rejected — recording is interrupted (not rejected), story progress is saved (not abandoned). Pre-registration adds complexity without solving a real problem. The synchronous signal dispatch is simpler and sufficient.

### Alternative C: Two-Phase Commit

- **Description**: Phase 1: all subscribers prepare (save state). Phase 2: ProfileManager executes flush-load-replace. If Phase 2 fails, subscribers are notified to rollback.
- **Pros**: Stronger consistency guarantees; rollback on failure
- **Cons**: Doubles the signal complexity (prepare + commit signals); rollback logic is complex and error-prone; GDScript has no transactional filesystem — flush failure cannot be rolled back (data is already on disk)
- **Rejection Reason**: Over-engineering for a mobile game with 3 save slots. Flush failure is handled by continuing with stale data (no data loss — memory copy is intact). Rollback logic would require subscribers to save and restore their own state, which is more complex than the data loss it prevents.

## Consequences

### Positive
- **Data consistency guarantee**: Synchronous dispatch ensures all subscribers clean up before flush, preventing stale data from being persisted
- **Simple mental model**: "Emit signal → everyone cleans up → flush → load → replace" is a linear, predictable sequence
- **State machine clarity**: 4 well-defined states with explicit transition guards prevent illegal state changes
- **No new engine APIs**: Uses standard Godot signals and state machines — no post-cutoff risk

### Negative
- **Subscriber discipline requirement**: Any future subscriber to `profile_switch_requested` that uses `await` will silently corrupt data. This cannot be detected at compile time or by GUT tests (requires code review).
- **Direct reference trade-off**: `get_section()` returns a direct reference (not copy) for performance — callers mutating the reference during profile switch will see stale data until step ⑦ completes.
- **No switch rejection**: Subscribers cannot reject or delay a profile switch. If a future feature requires this (e.g., "unsaved recording in progress"), the protocol must be extended.

### Risks

| Risk | Severity | Mitigation |
|------|----------|------------|
| **R1: Subscriber uses `await` in profile_switch_requested handler** | HIGH | CI static check: grep for `await` in signal handlers. Code review mandate. GDD explicitly documents the constraint (profile-manager.md EC-6). |
| **R2: get_section() reference stale during switch** | MEDIUM | All reads during SWITCHING state use `_active_data` (old profile). New reference available only after step ⑦. Documented in profile-manager.md Rule 2. |
| **R3: flush failure during switch** | LOW | Continue with new profile data in memory. Next flush will persist correctly. Old profile data may have been partially stale — acceptable for a children's game. |
| **R4: New subscriber forgets to handle profile_switch_requested** | MEDIUM | Systems-index.md dependency map requires all profile-aware systems to declare this dependency. Code review catches omissions. |

## GDD Requirements Addressed

| GDD System | Requirement | How This ADR Addresses It |
|------------|-------------|--------------------------|
| profile-manager.md | Rule 2: `get_section()` returns direct reference | Documented as intentional trade-off; callers must not cache across switch |
| profile-manager.md | Rule 3: `profile_switch_requested` sync constraint | Core of this ADR: mandatory synchronous dispatch |
| profile-manager.md | Rule 4: `switch_to_profile()` 7-step sequence | Formalized in Decision section with numbered steps |
| profile-manager.md | Rule 5: 4-state state machine | State diagram and transition rules documented |
| profile-manager.md | EC-6: await in subscriber detection | Risk R1 mitigation: CI grep + code review |
| vocab-store.md | `profile_switch_requested` handler: `reset_session()` | Depends on ADR-0005 sync guarantee |
| voice-recorder.md | `profile_switch_requested` handler: `interrupt_and_commit()` | Depends on ADR-0005 sync guarantee |
| interrupt-handler.md | `profile_switch` interrupt reason | Uses `request_chapter_interrupt("profile_switch")` in step ④ |
| architecture.md | Initialization order step ⑧: InterruptHandler loads after SM+VR | Ensures all subscribers are connected before any switch can occur |

## Performance Implications
- **CPU**: `duplicate_deep()` of ~2 KB Dictionary: <0.1ms. Signal dispatch to 3 subscribers: <0.1ms. Total switch overhead: <5ms (including SaveSystem flush + load).
- **Memory**: Peak during switch: 2× `_active_data` size (~4 KB) for old + new. Released after old reference goes out of scope.
- **Load Time**: `SaveSystem.load_profile()` + JSON parse: <1ms for <1 KB file.
- **Network**: N/A.

## Migration Plan

This ADR defines the initial architecture. No migration from prior code is needed.

If a future feature requires profile switch rejection (e.g., "save recording before switching"), extend the protocol with a pre-switch guard phase — but do not add `await` to the existing synchronous signal chain.

## Validation Criteria
1. All `profile_switch_requested` handlers execute without `await` (CI grep check)
2. GUT test: switch_to_profile() completes atomically — state transitions SWITCHING → ACTIVE without intermediate observable state
3. GUT test: flush failure during switch — state reverts, `active_profile_cleared("load_failed")` emitted
4. GUT test: get_section() returns old data during SWITCHING, new data after ACTIVE
5. GUT test: 4-state machine — no illegal transitions possible
6. Integration test: full switch sequence with VocabStore, VoiceRecorder, StoryManager subscribers

## Related Decisions
- ADR-0004: SaveSystem Atomic Write (flush/load used in steps ⑤–⑥)
- ADR-0006: VocabStore Gold Star Formula (depends on this ADR's sync guarantee for session counter reset)
- design/gdd/profile-manager.md — ProfileManager GDD (this ADR formalizes its Core Rules 2–5)
- design/gdd/vocab-store.md — VocabStore GDD (subscriber to profile_switch_requested)
- design/gdd/voice-recorder.md — VoiceRecorder GDD (subscriber to profile_switch_requested)
- design/gdd/interrupt-handler.md — InterruptHandler GDD (dispatches "profile_switch" reason)
