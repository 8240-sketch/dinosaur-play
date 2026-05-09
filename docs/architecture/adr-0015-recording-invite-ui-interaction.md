# ADR-0015: RecordingInviteUI Recording Invite Interaction

## Status
Accepted (2026-05-09)

## Date
2026-05-09

## Engine Compatibility

| Field | Value |
|-------|-------|
| **Engine** | Godot 4.6 |
| **Domain** | UI |
| **Knowledge Risk** | LOW — RecordingInviteUI uses standard Control nodes, _input() for hold-to-record, Timer for timeout; no post-cutoff APIs |
| **References Consulted** | `docs/engine-reference/godot/VERSION.md`; `docs/engine-reference/godot/modules/ui.md` |
| **Post-Cutoff APIs Used** | None |
| **Verification Required** | (1) _input() hold-to-record works correctly (gui_input() swallows finger-up); (2) Timer pause during recording; (3) recording_interrupted signal handling during RECORDING state |

## ADR Dependencies

| Field | Value |
|-------|-------|
| **Depends On** | ADR-0009 (VoiceRecorder — start_recording, stop_recording, signals); ADR-0011 (AnimationHandler — play_recording_invite, stop_recording_listen); ADR-0013 (TagDispatcher — recording_invite_triggered signal) |
| **Enables** | No downstream ADRs — RecordingInviteUI is a leaf consumer |
| **Blocks** | RecordingInviteUI implementation; Recording feature UI |
| **Ordering Note** | Must be Accepted after ADR-0009 and ADR-0013. Can be implemented in parallel with ADR-0012 (InterruptHandler) and ADR-0014 (MainMenu). |

## Context

### Problem Statement

The game's core fantasy is "I teach T-Rex English words." RecordingInviteUI makes this tangible by inviting the child to record their voice. When an Ink tag triggers `record:invite`, a modal overlay appears with a large orange button and the target English word. The child can hold-to-record, and their voice is permanently saved as a keepsake (P3). The UI must be completely optional — skipping has zero penalty (P2 Anti-Pillar), and failures are silent.

### Constraints

- **GameScene child node**: Not AutoLoad; one instance per scene
- **P2 Anti-Pillar**: recording_failed → silent dismiss; no error text, no red elements
- **Hold-to-record**: Must use `_input()`, not `gui_input()` —后者 swallows finger-up events
- **AnimationHandler timing**: stop_recording_listen() in SAVING phase, NOT during RECORDING
- **recording_interrupted**: S5-B1 fix — unconditional emit from interrupt_and_commit(); RIUI must handle from RECORDING state
- **Fully optional**: Skip/timeout leads to story continuation with no penalty

### Requirements

- 7 states: INACTIVE, APPEARING, IDLE, RECORDING, SAVING, DISMISSING
- Signal subscriptions: recording_invite_triggered, recording_saved, recording_failed, recording_unavailable, recording_interrupted
- Hold-to-record via _input() with finger-down = start, finger-up = stop
- INVITE_TIMEOUT_SEC = 12.0s; timer pauses during recording
- Skip button in IDLE state
- recording_invite_dismissed(skipped: bool) signal for GameScene
- Button >= 96dp; SkipButton >= 48dp

## Decision

### Architecture

RecordingInviteUI is a GameScene child node with a 7-state machine that coordinates VoiceRecorder and AnimationHandler for the recording invite flow.

```
┌─────────────────────────────────────────────────────────┐
│  RecordingInviteUI (GameScene Child Node)                │
│                                                          │
│  States:                                                 │
│  INACTIVE → APPEARING → IDLE → RECORDING → SAVING        │
│                                        → DISMISSING      │
│                                                          │
│  ┌────────────────────────────────────────────────────┐  │
│  │  Signal Flow                                        │  │
│  │                                                     │  │
│  │  TagDispatcher ──recording_invite_triggered──► RIUI  │  │
│  │  RIUI ──start_recording()──► VoiceRecorder          │  │
│  │  RIUI ──stop_recording()──► VoiceRecorder           │  │
│  │  VoiceRecorder ──recording_saved──► RIUI             │  │
│  │  VoiceRecorder ──recording_failed──► RIUI            │  │
│  │  VoiceRecorder ──recording_unavailable──► RIUI       │  │
│  │  VoiceRecorder ──recording_interrupted──► RIUI       │  │
│  │  RIUI ──play_recording_invite()──► AnimationHandler  │  │
│  │  RIUI ──stop_recording_listen()──► AnimationHandler  │  │
│  │  RIUI ──recording_invite_dismissed(skipped)──► Scene │  │
│  └────────────────────────────────────────────────────┘  │
│                                                          │
│  Hold-to-record:                                         │
│    _input() → finger-down in button → start_recording()  │
│    _input() → finger-up (anywhere) → stop_recording()    │
│                                                          │
│  Timeout:                                                │
│    Timer (INVITE_TIMEOUT_SEC) → IDLE → DISMISSING        │
│    Pauses during RECORDING                               │
│                                                          │
│  Skip:                                                   │
│    SkipButton click → IDLE → DISMISSING (skipped=true)   │
│                                                          │
│  Animation:                                              │
│    APPEARING → play_recording_invite()                   │
│    SAVING (after saved/failed/interrupted) →             │
│      stop_recording_listen()                             │
└─────────────────────────────────────────────────────────┘
```

### Key Interfaces

```gdscript
# Signals consumed
signal recording_invite_triggered(word_id: String, word_text: String)  # from TagDispatcher
signal recording_saved(word_id: String, path: String)  # from VoiceRecorder
signal recording_failed(word_id: String, reason: String)  # from VoiceRecorder
signal recording_unavailable()  # from VoiceRecorder
signal recording_interrupted()  # from VoiceRecorder (S5-B1)

# Signal emitted
signal recording_invite_dismissed(skipped: bool)

# VoiceRecorder calls
func _start_recording(word_id: String) -> bool:
func _stop_recording() -> bool:

# AnimationHandler calls
func _play_recording_invite() -> void:
func _stop_recording_listen() -> void:  # called in SAVING, not RECORDING
```

### Hold-to-record via _input()

```gdscript
func _input(event: InputEvent) -> void:
    if event is InputEventScreenTouch:
        if event.pressed and _is_in_button_area(event.position):
            # finger down in button → start recording
            if _state == IDLE:
                VoiceRecorder.start_recording(_current_word_id)
                _state = RECORDING
                _timer.stop()  # pause timeout
        elif not event.pressed and _state == RECORDING:
            # finger up anywhere → stop recording
            VoiceRecorder.stop_recording()
            _state = SAVING
```

**Why _input() not gui_input()**: `gui_input()` is consumed by the GUI system before reaching `_unhandled_input()`. When a finger lifts outside the button bounds, `gui_input()` may not fire the release event on the button node. `_input()` receives all screen touch events regardless of GUI focus, ensuring finger-up is always detected.

### AnimationHandler Timing (B-3 Fix)

- **APPEARING**: Call `AnimationHandler.play_recording_invite()` — T-Rex raises paw
- **SAVING** (after recording_saved/failed/interrupted received): Call `AnimationHandler.stop_recording_listen()` — T-Rex lowers paw
- **Never during RECORDING**: stop_recording_listen() is NOT called during RECORDING — this ensures T-Rex maintains the raised-paw pose throughout the entire recording + save duration

### Signal Handling Matrix

| Signal | Current State | Action |
|--------|:------------:|--------|
| recording_saved | SAVING | T-Rex ack animation (≤1.5s) → DISMISSING |
| recording_failed | SAVING | Silent → DISMISSING (P2) |
| recording_interrupted | RECORDING | Immediate DISMISSING (S5-B1; no stop_recording call) |
| recording_interrupted | other | Ignore |
| recording_unavailable | APPEARING/IDLE/RECORDING/SAVING | Immediate DISMISSING |
| timeout | IDLE | DISMISSING (skipped=true) |
| skip button | IDLE | DISMISSING (skipped=true) |

## Alternatives Considered

### Alternative 1: gui_input() for hold-to-record
- **Description**: Use gui_input() signal on the button node for touch detection
- **Pros**: Standard Godot GUI pattern; button-area detection built-in
- **Cons**: gui_input() swallows finger-up events when finger moves outside button bounds; causes recording to never stop on fast finger movement
- **Rejection Reason**: _input() receives all screen touch events; gui_input() is filtered by GUI system. The hold-to-record pattern requires detecting finger-up at any screen position, not just within the button.

### Alternative 2: Separate RecordingInviteUI scene (instanced dynamically)
- **Description**: Create RecordingInviteUI as a separate .tscn scene, instanced by GameScene when needed
- **Pros**: Clean separation; reusable across scenes
- **Cons**: Dynamic instancing adds lifecycle complexity; signals must be connected after instancing; scene tree path changes
- **Rejection Reason**: RecordingInviteUI is tightly coupled to GameScene (AnimationHandler registration, VoiceRecorder signals). Embedding as a child node is simpler and avoids instancing lifecycle issues.

### Alternative 3: State machine as separate node
- **Description**: Extract 7-state machine into a dedicated FSM node
- **Pros**: Reusable; testable in isolation
- **Cons**: RecordingInviteUI's states are trivial (7 states with linear flow); separating adds indirection for ~50 lines of state logic
- **Rejection Reason**: The state machine is simple and tightly coupled to the UI rendering. Separating would create two nodes that must stay synchronized for no benefit.

## Consequences

### Positive

- _input() hold-to-record reliably detects finger-up at any screen position
- S5-B1 recording_interrupted handling prevents UI stuck in RECORDING state during interrupts
- P2 Anti-Pillar: all failure paths lead to silent DISMISSING — child never sees error
- AnimationHandler timing (stop_recording_listen in SAVING) ensures T-Rex pose continuity
- Skip/timeout paths produce skipped=true signal for downstream P4 systems

### Negative

- _input() receives ALL screen touches — must filter by button area to avoid false triggers
- recording_interrupted handling adds state complexity (RECORDING → DISMISSING without stop_recording)
- Timer pause/resume during recording adds timing edge cases

### Risks

| Risk | Severity | Mitigation |
|------|:--------:|------------|
| _input() false trigger from touches outside button | MEDIUM | Area check in _input() handler; only respond to touches within button bounds |
| recording_interrupted arrives during SAVING (not RECORDING) | LOW | Core Rule 13: ignore from non-RECORDING states |
| VoiceRecorder SAVING timeout not defined | LOW | RecordingInviteUI does not set independent SAVING timeout; relies on VoiceRecorder |

## GDD Requirements Addressed

| GDD System | Requirement | How This ADR Addresses It |
|------------|-------------|--------------------------|
| recording-invite-ui.md TR-RI-001 | GameScene child node | Decision: per-scene instance spec |
| recording-invite-ui.md TR-RI-002 | Signal subscriptions | Decision: 5-signal subscription spec |
| recording-invite-ui.md TR-RI-003 | Appearance guard | Decision: is_recording_available() check |
| recording-invite-ui.md TR-RI-004 | Hold-to-record via _input() | Decision: _input() implementation spec |
| recording-invite-ui.md TR-RI-005 | INVITE_TIMEOUT_SEC | Decision: Timer pause/resume spec |
| recording-invite-ui.md TR-RI-006 | T-Rex ack animation | Decision: SAVING → animation → DISMISSING |
| recording-invite-ui.md TR-RI-007 | Silent failure P2 | Decision: recording_failed → silent DISMISSING |
| recording-invite-ui.md TR-RI-008 | recording_interrupted (S5-B1) | Decision: RECORDING → immediate DISMISSING |
| recording-invite-ui.md TR-RI-009 | stop_recording_listen timing | Decision: SAVING phase, not RECORDING |
| recording-invite-ui.md TR-RI-010 | Button >= 96dp | Not addressed here — UI spec |
| recording-invite-ui.md TR-RI-011 | dismissed signal semantics | Decision: skipped=true/false spec |

## Performance Implications

- **CPU**: _input() processes every screen touch; area check is O(1); negligible
- **Memory**: One scene instance; one Timer node; negligible
- **Load Time**: No impact; instantiated with GameScene
- **Network**: None

## Validation Criteria

- AC-01 to AC-06: Signal handling (saved, failed, unavailable, interrupted)
- AC-07 to AC-10: State machine transitions (INACTIVE → APPEARING → IDLE → RECORDING → SAVING → DISMISSING)
- AC-11 to AC-14: Hold-to-record behavior (finger-down start, finger-up stop)
- AC-15 to AC-18: AnimationHandler timing (play_recording_invite, stop_recording_listen in SAVING)
- AC-19 to AC-20: recording_interrupted handling (S5-B1)

## Related Decisions

- ADR-0009 (VoiceRecorder) — start_recording, stop_recording, signal contracts
- ADR-0011 (AnimationHandler state machine) — play_recording_invite, stop_recording_listen
- ADR-0013 (TagDispatcher) — recording_invite_triggered signal
- design/gdd/recording-invite-ui.md — RecordingInviteUI GDD (full specification)
- design/gdd/voice-recorder.md — VoiceRecorder recording side contract
- design/gdd/animation-handler.md — AnimationHandler recording states
