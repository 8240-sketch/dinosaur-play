# ADR-0012: InterruptHandler Platform Interrupt Protocol

## Status
Accepted (2026-05-09)

## Date
2026-05-09

## Engine Compatibility

| Field | Value |
|-------|-------|
| **Engine** | Godot 4.6 |
| **Domain** | Input / Core |
| **Knowledge Risk** | HIGH — `NOTIFICATION_WM_GO_BACK_REQUEST` (Android 10+ gesture navigation) does NOT produce KEY_BACK InputEvent; `ui_cancel` Input Map must manually include KEY_BACK; `process_mode` must be PROCESS_MODE_ALWAYS for AutoLoad notifications when SceneTree paused |
| **References Consulted** | `docs/engine-reference/godot/VERSION.md`; `docs/engine-reference/godot/modules/input.md`; `docs/engine-reference/godot/breaking-changes.md` |
| **Post-Cutoff APIs Used** | `NOTIFICATION_WM_GO_BACK_REQUEST` — Android 10+ gesture navigation notification; behavior may differ from LLM training data assumptions |
| **Verification Required** | (1) `NOTIFICATION_WM_GO_BACK_REQUEST` fires on Android 10+ gesture navigation; (2) KEY_BACK and `ui_cancel` detection work on both gesture and physical-button devices; (3) `process_mode = PROCESS_MODE_ALWAYS` enables notification receipt during SceneTree pause |

## ADR Dependencies

| Field | Value |
|-------|-------|
| **Depends On** | ADR-0005 (ProfileManager switch protocol — flush() used in interrupt paths); ADR-0009 (VoiceRecorder — interrupt_and_commit() called before SM interrupt); ADR-0010 (StoryManager — request_chapter_interrupt / confirm_navigation_complete API) |
| **Enables** | No downstream ADRs — InterruptHandler is terminal infrastructure |
| **Blocks** | Full gameplay loop (any chapter playthrough requires interrupt safety); GameScene (subscribes to chapter_interrupted for recovery UI) |
| **Ordering Note** | Must be Accepted after ADR-0009 and ADR-0010. Final P0 ADR — completes the Foundation+Core architecture layer. |

## Context

### Problem Statement

Android may kill or pause the app at any time — incoming calls, Home button, screen lock, gesture navigation back. Without an interrupt handler, any uncommitted progress (vocab gold stars, recording paths, story position) would be lost. InterruptHandler is the safety net: it detects platform events, orchestrates a shutdown sequence (VoiceRecorder commit → StoryManager interrupt → ProfileManager flush), and handles recovery when the user returns.

### Constraints

- **AutoLoad singleton**: Must survive scene transitions; process_mode = PROCESS_MODE_ALWAYS
- **Dual notification capture**: FOCUS_OUT + PAUSED for background; WM_GO_BACK_REQUEST for gesture navigation
- **Complementary input**: KEY_BACK via _unhandled_input (physical buttons) + WM_GO_BACK_REQUEST (gesture)
- **VoiceRecorder first**: P3 data contract requires interrupt_and_commit() BEFORE request_chapter_interrupt()
- **Flush always**: Both background and back-button paths must flush via ProfileManager.flush()
- **No navigation on background**: User returns to same scene; GameScene handles recovery UI
- **Navigation on back-button**: Navigate to MainMenu; call confirm_navigation_complete() to reset SM

### Requirements

- Detect FOCUS_OUT, PAUSED, WM_GO_BACK_REQUEST, FOCUS_IN, RESUMED notifications
- Intercept KEY_BACK via _unhandled_input when is_story_active
- Three anti-reentry flags: _background_flush_pending, _back_button_pending, _ih_triggered_stop
- BACK_BUTTON_GUARD_TIMEOUT_MS timer for stuck back_button recovery
- change_scene_to_file() error handling (E9 recovery path)
- VoiceRecorder soft dependency via is_instance_valid() guard

## Decision

### Architecture

InterruptHandler is an AutoLoad singleton with process_mode = PROCESS_MODE_ALWAYS that captures Android platform events and orchestrates shutdown/recovery sequences.

```
┌─────────────────────────────────────────────────────────┐
│  InterruptHandler (AutoLoad Singleton, loading order 9)  │
│                                                          │
│  process_mode = PROCESS_MODE_ALWAYS                      │
│                                                          │
│  ┌────────────────────────────────────────────────────┐  │
│  │  _notification(what)                                │  │
│  │                                                     │  │
│  │  FOCUS_OUT / PAUSED:                                │  │
│  │    guard: _background_flush_pending → return        │  │
│  │    set _background_flush_pending = true              │  │
│  │    if is_story_active:                               │  │
│  │      [VR].interrupt_and_commit()  ← P3: first       │  │
│  │      _ih_triggered_stop = true                       │  │
│  │      SM.request_chapter_interrupt("app_background")  │  │
│  │      → chapter_interrupted → flush                   │  │
│  │    else:                                             │  │
│  │      PM.flush()  ← direct                           │  │
│  │                                                     │  │
│  │  WM_GO_BACK_REQUEST:                                │  │
│  │    guard: _back_button_pending → return              │  │
│  │    if is_story_active:                               │  │
│  │      _back_button_pending = true                     │  │
│  │      _ih_triggered_stop = true                       │  │
│  │      [VR].interrupt_and_commit()  ← P3: first       │  │
│  │      SM.request_chapter_interrupt("user_back_button")│  │
│  │      start guard timer                               │  │
│  │    else: → pass to OS (minimize)                     │  │
│  │                                                     │  │
│  │  FOCUS_IN / RESUMED:                                │  │
│  │    _background_flush_pending = false                 │  │
│  │    if SM.STOPPED and _ih_triggered_stop:             │  │
│  │      _ih_triggered_stop = false                      │  │
│  │      SM.confirm_navigation_complete()  → SM.IDLE     │  │
│  └────────────────────────────────────────────────────┘  │
│                                                          │
│  ┌────────────────────────────────────────────────────┐  │
│  │  _unhandled_input(event)                            │  │
│  │                                                     │  │
│  │  if ui_cancel (KEY_BACK) and is_story_active:       │  │
│  │    viewport.set_input_as_handled()  ← FIRST         │  │
│  │    [VR].interrupt_and_commit()                       │  │
│  │    _back_button_pending = true                       │  │
│  │    _ih_triggered_stop = true                         │  │
│  │    SM.request_chapter_interrupt("user_back_button")  │  │
│  │    start guard timer                                 │  │
│  │  else: → pass to scene/OS                            │  │
│  └────────────────────────────────────────────────────┘  │
│                                                          │
│  ┌────────────────────────────────────────────────────┐  │
│  │  _on_chapter_interrupted(reason: String)             │  │
│  │                                                     │  │
│  │  app_background:                                    │  │
│  │    PM.flush()  ← IH owns flush                      │  │
│  │    no navigation                                    │  │
│  │                                                     │  │
│  │  user_back_button:                                  │  │
│  │    _back_button_pending = false                      │  │
│  │    PM.flush()                                       │  │
│  │    change_scene_to_file(MAIN_MENU_PATH)              │  │
│  │    SM.confirm_navigation_complete()  ← SM.IDLE      │  │
│  │    _ih_triggered_stop = false                        │  │
│  │                                                     │  │
│  │  profile_switch:                                    │  │
│  │    _ih_triggered_stop = false                        │  │
│  │    no flush (PM.switch already flushed)              │  │
│  │    no navigation                                    │  │
│  └────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────┘
```

### Key Interfaces

```gdscript
# No public API — purely event-driven via _notification() and _unhandled_input()
class_name InterruptHandler extends Node
# process_mode = PROCESS_MODE_ALWAYS

# Internal flags
var _background_flush_pending: bool = false
var _back_button_pending: bool = false
var _ih_triggered_stop: bool = false
```

### Interrupt Sequence (4 paths)

All paths follow: VR first → SM interrupt → flush. The ordering is critical.

| Path | Trigger | VR First? | SM Interrupt? | Flush? | Navigate? |
|------|---------|:---------:|:-------------:|:------:|:---------:|
| app_background | FOCUS_OUT / PAUSED | ✅ | ✅ | via signal | ❌ |
| user_back_button (notification) | WM_GO_BACK_REQUEST | ✅ | ✅ | via signal | ✅ → MainMenu |
| user_back_button (input) | KEY_BACK / ui_cancel | ✅ | ✅ | via signal | ✅ → MainMenu |
| profile_switch | PM signal | ❌ | ❌ | ❌ (PM handles) | ❌ |

### Anti-Reentry Flags

| Flag | Purpose | Set | Cleared |
|------|---------|-----|---------|
| `_background_flush_pending` | Prevent FOCUS_OUT + PAUSED dual-trigger | First background notification | FOCUS_IN / RESUMED |
| `_back_button_pending` | Prevent back button re-trigger during SM transition | Back button detected | _on_chapter_interrupted("user_back_button") or timeout |
| `_ih_triggered_stop` | Distinguish IH-caused STOPPED from profile_switch-caused STOPPED | IH calls request_chapter_interrupt | confirm_navigation_complete() or _on_chapter_interrupted("user_back_button") |

### FOCUS_IN Recovery

When app returns to foreground:
1. Reset `_background_flush_pending = false`
2. Check: `!is_story_active && SM.current_state == STOPPED && _ih_triggered_stop`
3. If true: `_ih_triggered_stop = false; SM.confirm_navigation_complete()` → SM.IDLE
4. No scene navigation — GameScene detects SM.IDLE and shows recovery UI

## Alternatives Considered

### Alternative 1: Singleton with scene tree node (not AutoLoad)
- **Description**: Create InterruptHandler as a persistent node in GameRoot scene
- **Pros**: Visible in scene tree; easier to debug
- **Cons**: Destroyed on scene change unless manually preserved; lifecycle management complexity; does not survive `change_scene_to_file()` without special handling
- **Rejection Reason**: AutoLoad is the standard Godot pattern for cross-scene persistent singletons. InterruptHandler must survive all scene transitions without manual lifecycle management.

### Alternative 2: Use _input() instead of _unhandled_input() for back button
- **Description**: Intercept KEY_BACK in `_input()` instead of `_unhandled_input()`
- **Pros**: Earlier interception; guaranteed to run before scene nodes
- **Cons**: Would consume back button even when scene nodes should handle it (e.g., closing a dialog); `_input()` runs before GUI processing, breaking dialog dismiss behavior
- **Rejection Reason**: `_unhandled_input()` is the correct phase for back button — it runs after GUI and scene node input processing, allowing dialogs to dismiss themselves first. IH only intercepts when no other node consumed the event.

### Alternative 3: Use get_tree().get_root().notification() directly
- **Description**: Manually propagate notifications instead of relying on `_notification()`
- **Pros**: More control over notification timing
- **Cons**: Godot's notification system is built into the engine; manual propagation is fragile and version-dependent
- **Rejection Reason**: `_notification()` is the standard Godot mechanism. The engine handles notification dispatch correctly; manual intervention adds fragility without benefit.

## Consequences

### Positive

- Comprehensive coverage: FOCUS_OUT + PAUSED + WM_GO_BACK_REQUEST + KEY_BACK covers all Android interrupt scenarios
- P3 data safety: VR.interrupt_and_commit() before SM interrupt ensures recording paths are committed before flush
- Anti-reentry flags prevent duplicate flushes and double navigation
- FOCUS_IN recovery path handles both successful and failed scene transitions (E9)
- Soft VoiceRecorder dependency (is_instance_valid) allows graceful degradation when permission denied

### Negative

- Three boolean flags add cognitive complexity; must be tested thoroughly across all state combinations
- BACK_BUTTON_GUARD_TIMEOUT_MS timer adds a safety net that masks SM bugs (SM should always emit chapter_interrupted)
- No child-visible feedback on interrupt — purely invisible infrastructure (by design, but means bugs are silent)

### Risks

| Risk | Severity | Mitigation |
|------|:--------:|------------|
| NOTIFICATION_WM_GO_BACK_REQUEST doesn't fire on some Android devices | HIGH | KEY_BACK via _unhandled_input provides complementary coverage; verify on 2+ devices |
| ui_cancel missing KEY_BACK in InputMap → back button silently fails | HIGH | Manual Project Settings configuration required; documented in GDD OQ-5; verify on first device |
| change_scene_to_file() fails → SM locked in STOPPED | MEDIUM | E9 recovery: _ih_triggered_stop stays true; FOCUS_IN path calls confirm_navigation_complete() |
| COMPLETING state interrupt loses chapter completion mark | LOW | Known and accepted (GDD E10); gold stars preserved; completion mark lost only in rare timing window |

## GDD Requirements Addressed

| GDD System | Requirement | How This ADR Addresses It |
|------------|-------------|--------------------------|
| interrupt-handler.md TR-IH-001 | AutoLoad + PROCESS_MODE_ALWAYS | Decision: AutoLoad singleton spec |
| interrupt-handler.md TR-IH-002 | _notification events | Decision: dual notification capture |
| interrupt-handler.md TR-IH-003 | _background_flush_pending | Decision: anti-reentry flag spec |
| interrupt-handler.md TR-IH-004 | Back button dual coverage | Decision: _unhandled_input + WM_GO_BACK_REQUEST |
| interrupt-handler.md TR-IH-005 | VR interrupt_and_commit() first | Decision: P3 data contract ordering |
| interrupt-handler.md TR-IH-006 | _on_chapter_interrupted routing | Decision: reason-based branching table |
| interrupt-handler.md TR-IH-007 | FOCUS_IN recovery | Decision: confirm_navigation_complete() path |
| interrupt-handler.md TR-IH-008 | BACK_BUTTON_GUARD_TIMEOUT | Decision: timer safety net |
| interrupt-handler.md TR-IH-009 | _ih_triggered_stop flag | Decision: IH vs profile_switch STOPPED distinction |
| interrupt-handler.md TR-IH-010 | ui_cancel + KEY_BACK | Decision: Input Map configuration requirement |
| interrupt-handler.md TR-IH-011 | change_scene_to_file error | Decision: E9 recovery path |
| interrupt-handler.md TR-IH-012 | VoiceRecorder soft dependency | Decision: is_instance_valid guard |

## Performance Implications

- **CPU**: Zero per-frame cost when no interrupts; _notification callbacks are event-driven
- **Memory**: Three boolean flags + one Timer node; negligible
- **Load Time**: No impact; _ready() only connects signals and initializes flags
- **Network**: None

## Validation Criteria

- AC-1a/1b: Background interrupt triggers flush via correct path
- AC-3/4/6: Back button intercepted when active, passed through when inactive
- AC-7: profile_switch reason skips flush and navigation
- AC-8: Dual FOCUS_OUT produces single flush
- AC-11a/b/c: Guard timer prevents re-entry and recovers on timeout
- AC-14a/b: VR interrupt_and_commit() called BEFORE SM interrupt
- AC-15/16: WM_GO_BACK_REQUEST works on Android 10+ gesture devices
- AC-17/18: confirm_navigation_complete() resets SM; change_scene_to_file() failure recovery

## Related Decisions

- ADR-0005 (ProfileManager switch protocol) — flush() used in interrupt paths
- ADR-0009 (VoiceRecorder) — interrupt_and_commit() called before SM interrupt
- ADR-0010 (StoryManager narrative engine) — request_chapter_interrupt / confirm_navigation_complete API
- design/gdd/interrupt-handler.md — InterruptHandler GDD (full specification)
- design/gdd/story-manager.md — StoryManager Rule 13/14 (interrupt API)
- design/gdd/voice-recorder.md — VoiceRecorder interrupt_and_commit() contract
