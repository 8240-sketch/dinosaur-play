# ADR-0011: AnimationHandler State Machine Architecture

## Status
Accepted (2026-05-09)

## Date
2026-05-09

## Engine Compatibility

| Field | Value |
|-------|-------|
| **Engine** | Godot 4.6 |
| **Domain** | Animation |
| **Knowledge Risk** | MEDIUM — AnimationMixer base class changed in 4.3 (playback_active → active); custom_blend parameter naming; AnimationPlayer.play() API stable but signature changes must be verified |
| **References Consulted** | `docs/engine-reference/godot/VERSION.md`; `docs/engine-reference/godot/modules/animation.md`; `docs/engine-reference/godot/breaking-changes.md` (4.3 section) |
| **Post-Cutoff APIs Used** | `custom_blend` parameter in `AnimationPlayer.play()` — API name confirmed stable in 4.6 but behavior may differ from LLM training data assumptions |
| **Verification Required** | (1) `AnimationPlayer.play(clip_name, 0.0)` hard cut works as expected for 2D frame sprites; (2) `animation_finished` signal fires correctly for one-shot clips; (3) Loop clips do NOT emit `animation_finished`; (4) `%AnimationPlayer` unique name resolution in scene tree |

## ADR Dependencies

| Field | Value |
|-------|-------|
| **Depends On** | None — AnimationHandler is a self-contained component with no game-system dependencies |
| **Enables** | TagDispatcher (calls play_happy/play_confused); StoryManager (calls play_story_advance); HatchScene (calls play_hatch_idle/play_hatch_crack, subscribes hatch_sequence_completed); MainMenu (calls play_menu_idle/play_recognize/play_confused/play_sitting); RecordingInviteUI (calls play_recording_invite/stop_recording_listen) |
| **Blocks** | TagDispatcher implementation; HatchScene implementation; MainMenu implementation; RecordingInviteUI implementation; All NPC visual feedback |
| **Ordering Note** | Can be implemented independently of Foundation/Core ADRs. Per-scene instantiation means no AutoLoad ordering dependency. |

## Context

### Problem Statement

The game's core fantasy depends on T-Rex having reactive, personality-rich animations. When the child selects a word, T-Rex must immediately respond with either happy (correct) or confused (incorrect) animation — making the child feel like they're interacting with a living character, not a quiz machine. AnimationHandler is the execution layer that translates semantic commands (play_happy, play_confused) into AnimationPlayer state changes, managing 14 logical states, 18 clips, non-interruptible animation chains, and random variant selection.

### Constraints

- **Per-scene instance**: Not AutoLoad — each NPC scene owns its own AnimationHandler
- **2D frame sprites**: Hard cut transitions (custom_blend = 0.0), no blend/interpolation
- **P2 Anti-Pillar**: confused must be funny/curious, never sad/fearful; confused must NOT be in NON_INTERRUPTIBLE_STATES
- **Chain sequences**: Hatch crack → emerge → celebrate must complete without interruption
- **P4 requirement**: RECOGNIZE animation must complete fully (highest emotional quality moment)
- **No business data**: AnimationHandler produces no save data, no game state

### Requirements

- 14 logical states with 18 clips (HAPPY/CONFUSED each have 3 random variants)
- NON_INTERRUPTIBLE_STATES guard for critical animations
- `_transition()` as sole internal entry for all state changes
- `animation_finished` handler with chain routing (hatch chain, recognize → menu_idle)
- `stop_recording_listen()` bypass for RECORDING_LISTEN forced exit
- Two signals: `animation_completed(state: AnimState)` and `hatch_sequence_completed()`

## Decision

### Architecture

AnimationHandler is a per-scene GDScript component extending Node, attached to NPC Character nodes. It wraps AnimationPlayer with a state machine, exposing semantic methods to upstream systems.

```
┌───────────────────────────────────────────────────────┐
│  AnimationHandler (per-scene Node component)           │
│                                                        │
│  @onready %AnimationPlayer (unique name in scene)      │
│                                                        │
│  State Machine:                                        │
│  IDLE ←→ (any one-shot) → IDLE                         │
│  HATCH_IDLE → HATCH_CRACK → HATCH_EMERGE →             │
│    HATCH_CELEBRATE → IDLE (+ hatch_sequence_completed) │
│  RECORDING_INVITE → RECORDING_LISTEN (loop)             │
│    → IDLE (only via stop_recording_listen)              │
│  RECOGNIZE → MENU_IDLE (+ animation_completed)          │
│                                                        │
│  NON_INTERRUPTIBLE:                                    │
│    {HATCH_CRACK, HATCH_EMERGE, HATCH_CELEBRATE,        │
│     RECORDING_LISTEN, ENDING_WAVE, RECOGNIZE}           │
│                                                        │
│  CLIP_MAP: state → clip_name (StringName)              │
│  VARIANT_MAP: HAPPY/CONFUSED → [clip1, clip2, clip3]   │
│                                                        │
│  Signals:                                              │
│    animation_completed(state: AnimState)                │
│    hatch_sequence_completed()                           │
│                                                        │
│  Public API (semantic methods):                        │
│    play_idle()         → IDLE                          │
│    play_happy()        → HAPPY (random variant)        │
│    play_confused()     → CONFUSED (random variant)     │
│    play_recording_invite() → RECORDING_INVITE          │
│    stop_recording_listen() → IDLE (forced, bypasses)   │
│    play_hatch_idle()   → HATCH_IDLE                    │
│    play_hatch_crack()  → HATCH_CRACK (chain start)     │
│    play_story_advance() → STORY_ADVANCE                │
│    play_menu_idle()    → MENU_IDLE                     │
│    play_ending_wave()  → ENDING_WAVE                   │
│    play_recognize()    → RECOGNIZE (→ MENU_IDLE auto)  │
│    play_sitting()      → SITTING                       │
└───────────────────────────────────────────────────────┘
```

### Key Interfaces

```gdscript
# Signals
signal animation_completed(state: AnimState)
signal hatch_sequence_completed()

# Public API — all methods are void, fire-and-forget
func play_idle() -> void
func play_happy() -> void          # random from 3 variants
func play_confused() -> void       # random from 3 variants
func play_recording_invite() -> void
func stop_recording_listen() -> void  # forced exit, bypasses NON_INTERRUPTIBLE guard
func play_hatch_idle() -> void
func play_hatch_crack() -> void    # starts chain: crack → emerge → celebrate
func play_story_advance() -> void
func play_menu_idle() -> void
func play_ending_wave() -> void
func play_recognize() -> void      # one-shot → auto MENU_IDLE
func play_sitting() -> void        # loop

# Internal
func _transition(new_state: AnimState) -> void:
    # 1. Guard: if current in NON_INTERRUPTIBLE → return
    # 2. Pick clip: VARIANT_MAP[state].pick_random() or CLIP_MAP[state]
    # 3. play(clip_name, 0.0) — hard cut, no blend
    # 4. _current_state = new_state
```

### Transition Rules

1. **`_transition()`** is the sole internal entry for all state changes
2. **NON_INTERRUPTIBLE guard**: if `_current_state in NON_INTERRUPTIBLE_STATES` → return (silent rejection)
3. **Exception**: `stop_recording_listen()` bypasses the guard — RECORDING_LISTEN's only forced exit
4. **Chain routing**: `animation_finished` handler routes to next state in chain (hatch sequence)
5. **One-shot completion**: happy/confused/story_advance/ending_wave → IDLE + emit `animation_completed`
6. **RECOGNIZE completion**: → MENU_IDLE (not IDLE) + emit `animation_completed(RECOGNIZE)`
7. **Loop states**: IDLE, HATCH_IDLE, MENU_IDLE, RECORDING_LISTEN, SITTING — no `animation_finished`

### animation_finished Routing Table

| Finished Clip | Next State | Signal |
|--------------|-----------|--------|
| recording_invite | RECORDING_LISTEN | — |
| hatch_crack | HATCH_EMERGE | — |
| hatch_emerge | HATCH_CELEBRATE | — |
| hatch_celebrate | IDLE | hatch_sequence_completed() |
| recognize | MENU_IDLE | animation_completed(RECOGNIZE) |
| happy_* / confused_* / story_advance / ending_wave | IDLE | animation_completed(completed_state) |
| idle / hatch_idle / menu_idle / recording_listen / sitting | no-op (loop) | — |

**Critical**: For one-shot clips, capture `var _completed_state := _current_state` BEFORE calling `_transition(IDLE)` — otherwise the signal payload would always be IDLE.

## Alternatives Considered

### Alternative 1: AnimationTree with state machine
- **Description**: Use Godot's AnimationTree node with StateMachine playback
- **Pros**: Visual state machine in editor; built-in transitions; no GDScript FSM needed
- **Cons**: AnimationTree is designed for skeletal animation blending, not 2D frame sprite hard cuts; custom_blend = 0.0 negates AnimationTree's blending advantage; chain sequences (hatch) are harder to express in AnimationTree than GDScript routing
- **Rejection Reason**: 2D frame sprite animation needs hard cuts (custom_blend = 0.0), not blending. AnimationTree's value proposition is transition blending — without it, it's just overhead. GDScript state machine is simpler and more explicit for this use case.

### Alternative 2: AutoLoad singleton (shared across scenes)
- **Description**: Make AnimationHandler a global AutoLoad
- **Pros**: Single instance; shared state across scenes
- **Cons**: Each scene has its own NPC with different animation clips; shared state creates conflicts when switching scenes; HatchScene and MainMenu have different clip sets than the main game scene
- **Rejection Reason**: Different scenes have different NPC configurations and clip sets. Per-scene instantiation is the natural fit — each scene owns its own AnimationHandler with its own AnimationPlayer reference.

### Alternative 3: Direct AnimationPlayer calls from callers
- **Description**: Let TagDispatcher/StoryManager call AnimationPlayer.play() directly
- **Pros**: No intermediate layer; simplest code
- **Cons**: Exposes AnimationPlayer internals to all callers; no state machine enforcement; no NON_INTERRUPTIBLE guard; chain routing logic scattered across callers; impossible to change animation strategy without modifying all callers
- **Rejection Reason**: Violates encapsulation. 5+ systems would need to know clip names, state transitions, and guard logic. AnimationHandler provides a clean semantic API that isolates animation concerns.

## Consequences

### Positive

- Clean semantic API: callers say "play happy" without knowing clip names or state machine details
- NON_INTERRUPTIBLE guard protects critical animations (hatch chain, RECOGNIZE) from accidental interruption
- Per-scene instantiation means no AutoLoad ordering dependency; each scene configures independently
- Random variant selection (pick_random) adds personality without complexity
- Chain routing (hatch) is self-contained in animation_finished handler — callers don't manage multi-step sequences

### Negative

- Per-scene instantiation means AnimationHandler code is loaded per scene (no shared AutoLoad optimization)
- No cross-scene animation coordination (acceptable — only one scene active at a time)
- `animation_finished` routing table must be maintained manually — adding new chain states requires updating the handler

### Risks

| Risk | Severity | Mitigation |
|------|:--------:|------------|
| %AnimationPlayer name collision in scene tree | LOW | Godot unique name (%) enforces single match; E1 catches configuration errors immediately |
| custom_blend behavior differs from expected | LOW | AC-1 verifies all clip plays; 0.0 is well-documented as "no blend" |
| Chain sequence deadlock (hatch) if animation_finished not emitted | MEDIUM | HATCH_CELEBRATE must be in NON_INTERRUPTIBLE; watchdog in HatchScene (HATCH_SEQUENCE_WATCHDOG_MS) as safety net |
| RECOGNIZE interrupted by chapter_load_failed | MEDIUM | RECOGNIZE in NON_INTERRUPTIBLE; MainMenu subscribes to animation_completed(RECOGNIZE) for deferred confused (CD D1) |

## GDD Requirements Addressed

| GDD System | Requirement | How This ADR Addresses It |
|------------|-------------|--------------------------|
| animation-handler.md TR-AH-001 | Per-scene instance (not AutoLoad) | Decision: per-scene Node component |
| animation-handler.md TR-AH-002 | 14 logical states, 18 clips | Decision: state enum + CLIP_MAP + VARIANT_MAP |
| animation-handler.md TR-AH-003 | NON_INTERRUPTIBLE_STATES set | Decision: guard specification |
| animation-handler.md TR-AH-004 | _transition() sole entry, custom_blend = 0.0 | Decision: transition function spec |
| animation-handler.md TR-AH-005 | animation_finished chain routing | Decision: routing table |
| animation-handler.md TR-AH-006 | stop_recording_listen() bypass | Decision: forced exit spec |
| animation-handler.md TR-AH-007 | RECOGNIZE NON_INTERRUPTIBLE (CD D1) | Decision: guard + animation_completed signal |
| animation-handler.md TR-AH-008 | CLIP_MAP + VARIANT_MAP constants | Decision: data structure spec |
| animation-handler.md TR-AH-009 | %AnimationPlayer naming | Decision: unique name requirement |
| animation-handler.md TR-AH-010 | Confused = funny not fearful | Not addressed here — visual content constraint, not architecture |

## Performance Implications

- **CPU**: AnimationPlayer.play() is O(1); state machine check is O(1) array lookup; zero per-frame cost when idle
- **Memory**: AnimationHandler is lightweight (~100 bytes state + references); clips are stored in AnimationPlayer (shared resource)
- **Load Time**: No impact; per-scene instantiation loads with scene
- **Draw Calls**: Each AnimationHandler's AnimationPlayer contributes to draw calls; budget: <= 20 total for HatchScene (TR-hatch-scene-012)

## Validation Criteria

- AC-1 to AC-12: All 12 semantic methods work correctly (play + state transition)
- AC-4, AC-6, AC-10, AC-13, AC-18, AC-19, AC-20: NON_INTERRUPTIBLE guard blocks transitions correctly
- AC-5: Hatch chain sequence completes (CRACK → EMERGE → CELEBRATE → IDLE + signal)
- AC-7, AC-8, AC-16: Recording invite chain + forced exit
- AC-17, AC-23: RECOGNIZE → MENU_IDLE + animation_completed(RECOGNIZE)
- AC-2: Random variant selection produces diverse clips

## Related Decisions

- ADR-0010 (StoryManager narrative engine) — StoryManager calls play_story_advance() during narrative flow
- ADR-0008 (AudioManager BGM) — BGM persists across scene transitions; AnimationHandler is per-scene
- design/gdd/animation-handler.md — AnimationHandler GDD (defines all states, clips, transitions)
- design/gdd/hatch-scene.md — HatchScene subscribes to hatch_sequence_completed
- design/gdd/main-menu.md — MainMenu calls play_recognize/play_sitting, subscribes to animation_completed
- design/gdd/tag-dispatcher.md — TagDispatcher calls play_happy/play_confused based on Ink tags
- design/gdd/recording-invite-ui.md — RecordingInviteUI calls play_recording_invite/stop_recording_listen
