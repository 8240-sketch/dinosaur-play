# ADR-0017: NameInputScreen First-Launch Naming Ceremony

## Status
Accepted (2026-05-09)

## Date
2026-05-09

## Engine Compatibility

| Field | Value |
|-------|-------|
| **Engine** | Godot 4.6 |
| **Domain** | UI |
| **Knowledge Risk** | MEDIUM — `DisplayServer.virtual_keyboard_get_height()` and `virtual_keyboard_hide()` behavior may differ across Android versions; Godot 4.6 dual-focus system affects LineEdit focus handling |
| **References Consulted** | `docs/engine-reference/godot/VERSION.md`; `docs/engine-reference/godot/modules/ui.md` |
| **Post-Cutoff APIs Used** | `DisplayServer.virtual_keyboard_get_height()` — stable but exact behavior on Android 10+ soft keyboard needs device verification |
| **Verification Required** | (1) `virtual_keyboard_get_height()` returns correct pixel height on target Android device; (2) `virtual_keyboard_hide()` dismisses keyboard without crash; (3) LineEdit `max_length` enforcement works with CJK input methods; (4) `strip_edges()` correctly handles full-width spaces (U+3000) |

## ADR Dependencies

| Field | Value |
|-------|-------|
| **Depends On** | ADR-0005 (ProfileManager — create_profile, switch_to_profile, profile_switched signal); ADR-0008 (AudioManager — play_bgm for BGM introduction) |
| **Enables** | MainMenu (navigation target after naming); HatchScene (navigation source — NameInputScreen is the ceremony endpoint) |
| **Blocks** | First-launch flow completion; Profile 0 creation |
| **Ordering Note** | ADR-0005 and ADR-0008 must be Accepted before this ADR. NameInputScreen is a leaf Presentation layer node — no downstream ADRs depend on it. |

## Context

### Problem Statement

NameInputScreen is the final stop in the first-launch chain — it appears after HatchScene's hatching ceremony and before MainMenu, executing exactly once per device lifetime. The screen serves two simultaneous purposes: (1) the parent enters the child's name via a text input, and (2) the child selects a T-Rex avatar from 5 options. This is the only point in the entire game that calls `ProfileManager.create_profile()`, making it the sole profile creation gateway. The screen must handle Android soft keyboard adaptation, input validation with full-width space support, a strict 6-step creation+activation+navigation sequence, and graceful error recovery — all while maintaining the "naming ceremony" emotional tone (P1, P4).

### Constraints

- **One-time only**: GameRoot routes here when `profile_exists(0) == false`; never returns
- **Single caller**: NameInputScreen is the ONLY legitimate caller of `ProfileManager.create_profile()` (TR-name-input-010)
- **No game-system dependencies**: Does not use StoryManager, VocabStore, TtsBridge, or AnimationHandler
- **Android keyboard**: Must adapt layout when soft keyboard appears; keyboard height varies across devices
- **P2 Anti-Pillar**: Error toast uses warm amber (`--feedback-gentle`), never red; no punishment for skip
- **Anti-retry**: SUBMITTING state prevents double submission; GDScript single-threaded guarantee
- **BGM introduction**: NameInputScreen is the first scene to play BGM (via AudioManager.play_bgm)

### Requirements

- 2-state machine: IDLE (waiting for input), SUBMITTING (creation sequence in progress)
- Entry guard: `profile_exists(0)` check in `_ready()` — abort if true
- Input validation: `strip_edges()` + full-width space (U+3000) removal; confirm button disabled when empty
- Avatar selection: 5 options in 3+2 grid, bounce animation (1.0→1.12→1.0, 180ms), single selection
- Creation sequence: 6 strict steps (disable buttons → normalize → create_profile → switch_to_profile → wait signal → navigate)
- Soft keyboard: ContentContainer Y-offset = keyboard height; T-Rex independent fade-out
- Android back key: dismiss keyboard if visible; consume event if keyboard hidden
- Error recovery: `create_profile` returns false → toast + re-enable buttons, no state loss

## Decision

### Architecture

NameInputScreen is a Presentation layer scene node (non-AutoLoad) that owns the first-launch profile creation flow. It has a single hard dependency on ProfileManager and a soft dependency on AudioManager for BGM introduction.

```
GameRoot
    │
    ├─ profile_exists(0) == false → HatchScene.tscn
    │     └─ COMPLETED → change_scene_to_file("NameInputScreen.tscn")
    │
    └─ profile_exists(0) == true → MainMenu.tscn

NameInputScreen (scene node, not AutoLoad)
    │
    ├─ TRexLayer (independent container)
    │     └─ T-Rex Sprite2D (trex_idle loop, 160×160dp)
    │
    ├─ ContentContainer (moves with keyboard)
    │     ├─ Title Label ("给 T-Rex 起个名字吧！")
    │     ├─ LineEdit (max_length = NAME_MAX_LENGTH)
    │     ├─ Avatar Grid (3+2 layout, 88×88dp touch targets)
    │     ├─ Spacer (SIZE_EXPAND_FILL)
    │     ├─ Confirm Button ("完成！", 312×80dp)
    │     └─ Skip Link ("先不起名", 44dp touch height)
    │
    └─ State Machine: IDLE ↔ SUBMITTING
```

### Key Interfaces

```gdscript
class_name NameInputScreen extends Control

# State machine
enum State { IDLE, SUBMITTING }
var _state: State = State.IDLE
var _selected_avatar_index: int = 0

# ProfileManager calls (sole caller of create_profile)
func _ready() -> void:
    # Entry guard: if profile 0 exists, push_error + abort
    if ProfileManager.profile_exists(0):
        push_error("NameInputScreen: profile 0 already exists")
        _hide_all_interactive()
        return
    # Initialize avatar selection (index 0 auto-selected)
    # Connect LineEdit.text_changed for confirm button state
    # Start BGM: AudioManager.play_bgm("bgm_main", 0.6)

func _on_confirm_pressed() -> void:
    _submit(false)  # confirm path

func _on_skip_pressed() -> void:
    _submit(true)   # skip path

func _submit(is_skip: bool) -> void:
    _state = State.SUBMITTING
    _disable_all_buttons()
    DisplayServer.virtual_keyboard_hide()
    var final_name: String = "小朋友" if is_skip else _sanitize_name()
    var final_avatar_id: String = _avatar_options[0].id if is_skip else _avatar_options[_selected_avatar_index].id
    var success: bool = ProfileManager.create_profile(0, final_name, final_avatar_id)
    if not success:
        _show_error_toast()
        _state = State.IDLE
        _re_enable_buttons()
        return
    ProfileManager.profile_switched.connect(_on_profile_switched, CONNECT_ONE_SHOT)
    ProfileManager.switch_to_profile(0)

func _on_profile_switched(new_index: int) -> void:
    if new_index != 0:
        push_error("NameInputScreen: unexpected profile index %d" % new_index)
        return
    get_tree().change_scene_to_file(SCENE_MAIN_MENU)

func _sanitize_name() -> String:
    return line_edit.text.strip_edges().replace("　", "")

func _process(_delta: float) -> void:
    # Keyboard adaptation: ContentContainer.position.y = -keyboard_height
    var kb_height: float = DisplayServer.virtual_keyboard_get_height()
    # T-Rex independent fade when keyboard visible
```

### Input Normalization Contract (F-1, F-2)

```
F-1 (confirm_enabled predicate):
  sanitized_text  := strip_edges(raw_text).replace("　", "")
  confirm_enabled := NOT sanitized_text.is_empty()

F-2 (normalization output):
  [Confirm path]  final_name = sanitized_text (length 1–20)
                  final_avatar_id = _avatar_options[selected_index].id
  [Skip path]     final_name = "小朋友" (fixed)
                  final_avatar_id = _avatar_options[0].id (fixed)
```

### Creation Sequence (Rule 8 — strict 6 steps)

```
a. Disable Confirm + Skip + Clear buttons; dismiss keyboard
b. Normalize: final_name, final_avatar_id
c. ProfileManager.create_profile(0, final_name, final_avatar_id) -> bool
d. If false → error toast, re-enable buttons, return to IDLE
e. Connect profile_switched (ONE_SHOT); call switch_to_profile(0)
f. On signal: change_scene_to_file(SCENE_MAIN_MENU)
```

No timeout on step e — `create_profile(0)` success guarantees slot 0 exists, so `switch_to_profile(0)` will always emit `profile_switched(0)`.

### Android Back Key Handling

```
_unhandled_input(event):
    if event is InputEventKey and event.keycode == KEY_BACK:
        if DisplayServer.virtual_keyboard_get_height() > 0:
            pass  # OS default: dismiss keyboard
        else:
            accept_event()  # consume — no "back" target in first-launch chain
```

## Alternatives Considered

### Alternative 1: AutoLoad singleton

- **Description**: Make NameInputScreen an AutoLoad that survives scene transitions
- **Pros**: No scene lifecycle management
- **Cons**: NameInputScreen is a one-shot scene — AutoLoad would persist indefinitely, wasting memory. No cross-scene state to preserve.
- **Rejection Reason**: Violates the principle that one-shot UI scenes should be scene nodes, not singletons. NameInputScreen has zero need for cross-scene persistence.

### Alternative 2: ProfileManager.create_profile() called by GameRoot

- **Description**: GameRoot creates the profile before navigating to NameInputScreen; NameInputScreen only collects input
- **Pros**: Cleaner separation — GameRoot handles routing AND creation
- **Cons**: GameRoot would need to receive name/avatar from NameInputScreen somehow (signal? global var?). Adds coupling. ProfileManager GDD specifies NameInputScreen as the caller.
- **Rejection Reason**: NameInputScreen owns the complete creation flow (input → create → activate → navigate). Splitting creation to GameRoot adds complexity without benefit.

### Alternative 3: ScrollContainer for keyboard adaptation

- **Description**: Wrap ContentContainer in ScrollContainer; scroll to reveal hidden elements when keyboard appears
- **Pros**: Standard Android pattern for keyboard handling
- **Cons**: NameInputScreen content is intentionally designed for single-screen layout. ScrollContainer adds scroll indicators, overscroll effects, and touch interception complexity. EC-7 explicitly states that hiding the avatar grid during typing is design intent.
- **Rejection Reason**: GDD Rule 11 specifies direct Y-offset translation, not scrolling. The naming ceremony is designed as a two-phase flow (type name → dismiss keyboard → select avatar), not a scrollable form.

## Consequences

### Positive

- **Single creation gateway**: All profile creation goes through one code path — easy to audit and test
- **Clean state machine**: 2 states (IDLE, SUBMITTING) with clear transitions; no edge cases in state logic
- **BGM introduction**: NameInputScreen is the natural point to start continuous BGM via AudioManager
- **No game-system coupling**: Zero dependency on StoryManager, VocabStore, TtsBridge — can be implemented and tested in isolation
- **Error recovery**: create_profile failure returns to IDLE with all input preserved — no data loss

### Negative

- **Soft keyboard complexity**: `virtual_keyboard_get_height()` behavior varies across Android versions and OEM keyboards. The Y-offset approach may need per-device tuning.
- **One-shot lifecycle**: NameInputScreen loads once and never returns — any bug in the creation sequence is a permanent blocker for that device (mitigated by error recovery in Rule 9)
- **T-Rex independent animation**: The dual-container approach (TRexLayer independent of ContentContainer) adds layout complexity but is necessary for the keyboard adaptation UX

### Risks

| Risk | Severity | Mitigation |
|------|:--------:|------------|
| virtual_keyboard_get_height() returns 0 on some OEM keyboards | MEDIUM | Fallback: if height == 0 and LineEdit has focus, use estimated 280dp; test on target device Week 1 |
| create_profile() disk write fails (storage full) | LOW | Rule 9 error recovery: toast + return to IDLE; user can retry or skip |
| Full-width space (U+3000) bypasses empty check | LOW | F-1 predicate explicitly removes U+3000 after strip_edges(); AC-1 validates |
| profile_switched signal never fires (ProfileManager bug) | LOW | No timeout — but GDScript deterministic signal dispatch guarantees delivery if create_profile succeeded |

## GDD Requirements Addressed

| GDD System | Requirement | How This ADR Addresses It |
|------------|-------------|--------------------------|
| name-input-screen.md TR-name-input-001 | Entry guard: profile_exists(0) check | _ready() guard with push_error + abort |
| name-input-screen.md TR-name-input-002 | LineEdit max_length = NAME_MAX_LENGTH | LineEdit.max_length set from ProfileManager constant |
| name-input-screen.md TR-name-input-003 | Avatar selection 5 options, 3+2 grid, bounce | Avatar grid layout + Tween bounce (1.0→1.12→1.0, 180ms) |
| name-input-screen.md TR-name-input-004 | Confirm disabled when empty | F-1 predicate: strip_edges + U+3000 removal |
| name-input-screen.md TR-name-input-005 | Skip uses fixed default ("小朋友", avatar[0]) | _submit(true) ignores input, uses fixed values |
| name-input-screen.md TR-name-input-006 | Creation + activation 6-step sequence | _submit() strict 6-step implementation |
| name-input-screen.md TR-name-input-007 | Full-width space U+3000 handling | _sanitize_name() replaces U+3000 after strip_edges |
| name-input-screen.md TR-name-input-008 | Android back key behavior | _unhandled_input: dismiss keyboard or consume event |
| name-input-screen.md TR-name-input-009 | Soft keyboard Y-offset adaptation | _process(): ContentContainer.position.y = -kb_height |
| name-input-screen.md TR-name-input-010 | Only caller of create_profile() | Documented in Decision; sole creation gateway |

## Performance Implications

- **CPU**: _process() keyboard poll: <0.01ms/frame (single DisplayServer call). Avatar bounce Tween: <0.1ms/frame during animation.
- **Memory**: One scene node tree: ~50KB (Control nodes + textures). T-Rex idle animation: shared with MainMenu.
- **Load Time**: Scene load: <100ms. BGM first load via AudioManager: <50ms (OGG Vorbis).
- **Network**: N/A — all local.

## Migration Plan

This ADR creates a new scene (NameInputScreen.tscn). No migration from prior code is needed.

**ProfileManager GDD update required**: Interactions table row `MainMenu → ProfileManager: create_profile()` must be corrected to `NameInputScreen → ProfileManager: create_profile()` (OQ-1 from name-input-screen.md).

## Validation Criteria

1. AC-1: Confirm disabled when sanitized text empty; enabled when non-empty
2. AC-2: Confirm → MainMenu loads, profile 0 has correct name + avatar
3. AC-3: Skip → MainMenu loads, profile 0 has name="小朋友" + avatar[0]
4. AC-4: After navigation, has_active_profile() returns true
5. AC-7: Exactly one avatar selected at all times
6. AC-8: max_length = 20 enforced
7. AC-10: SUBMITTING state disables all interactive elements
8. AC-11: Double-tap → create_profile called exactly once
9. AC-12: Entry guard hides all elements when profile 0 exists
10. AC-13: create_profile failure → toast + re-enable + preserved input
11. Keyboard adaptation: ContentContainer moves correctly on target device
12. BGM: AudioManager.play_bgm called in _ready(); BGM persists to MainMenu

## Related Decisions

- ADR-0005: ProfileManager Switch Protocol (create_profile, switch_to_profile, profile_switched signal)
- ADR-0008: AudioManager BGM (play_bgm for BGM introduction)
- ADR-0016: HatchScene Ceremony (navigation source — HatchScene navigates to NameInputScreen)
- design/gdd/name-input-screen.md — NameInputScreen GDD (full specification)
- design/gdd/profile-manager.md — ProfileManager GDD (create_profile API, OQ-1 correction needed)
