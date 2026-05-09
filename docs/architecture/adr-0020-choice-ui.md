# ADR-0020: ChoiceUI Choice Presentation Architecture

## Status
Accepted (2026-05-09)

## Date
2026-05-09

## Engine Compatibility

| Field | Value |
|-------|-------|
| **Engine** | Godot 4.6 |
| **Domain** | UI |
| **Knowledge Risk** | LOW — ChoiceUI uses standard Control nodes, Tween, and signals; no post-cutoff APIs |
| **References Consulted** | `docs/engine-reference/godot/VERSION.md`; `docs/engine-reference/godot/modules/ui.md` |
| **Post-Cutoff APIs Used** | None |
| **Verification Required** | (1) focus_mode = FOCUS_NONE prevents dual-focus issues on Android; (2) Multi-touch rapid tap handled by state machine guard |

## ADR Dependencies

| Field | Value |
|-------|-------|
| **Depends On** | ADR-0010 (StoryManager — choices_ready signal, submit_choice method) |
| **Enables** | None — ChoiceUI is a leaf consumer |
| **Blocks** | ChoiceUI implementation |
| **Ordering Note** | ADR-0010 must be Accepted. |

## Context

### Problem Statement

ChoiceUI is the child's only active input interface in the MVP core loop. When StoryManager emits choices_ready, ChoiceUI displays two side-by-side vocabulary card buttons. The child taps one, and StoryManager.submit_choice(index) advances the story. The UI must enforce P2 Anti-Pillar (both buttons visually identical — ChoiceUI does NOT know which is correct), handle multi-touch double-submit protection, and use FOCUS_NONE to avoid Godot 4.6 dual-focus issues.

### Constraints

- **GameScene child node** (not AutoLoad); lifecycle follows GameScene
- **3-state machine**: HIDDEN → WAITING → SUBMITTED
- **P2 Anti-Pillar**: Both buttons visually identical; no correct/incorrect indication
- **Rule 6**: Must NOT subscribe to tts_fallback_to_highlight
- **Multi-touch**: State machine prevents double submit
- **Focus**: All buttons use FOCUS_NONE (Godot 4.6 dual-focus)

### Requirements

- 3-state machine with guards on all external event entries
- choices_ready handler: guard state, guard choice count (max 2), fill buttons, fade in
- Button click: submit_choice(), fade out, state → HIDDEN
- chapter_interrupted: kill tween, immediate hide, no submit
- Button layout: 96dp min height, 44-46% screen width each
- Card structure: icon (≥60% area) + English word (20sp bold) + Chinese translation (10sp gray)

## Decision

ChoiceUI is a GameScene child node with a 3-state machine that responds to StoryManager signals.

```gdscript
class_name ChoiceUI extends Control

enum State { HIDDEN, WAITING, SUBMITTED }
var _state: State = State.HIDDEN
var _fade_tween: Tween

func _ready() -> void:
    StoryManager.choices_ready.connect(_on_choices_ready)
    StoryManager.chapter_interrupted.connect(_on_chapter_interrupted)
    for btn in [$ButtonLeft, $ButtonRight]:
        btn.focus_mode = Control.FOCUS_NONE

func _on_choices_ready(choices: Array) -> void:
    if _state != State.HIDDEN: return
    if choices.size() > 2: choices = choices.slice(0, 2)
    if choices.size() < 2: return
    # Fill buttons with icon, english text, chinese text
    _fade_tween = create_tween()
    _fade_tween.tween_property(self, "modulate:a", 1.0, 0.15)
    show()
    _state = State.WAITING

func _on_button_pressed(index: int) -> void:
    if _state != State.WAITING: return
    StoryManager.submit_choice(index)
    _state = State.SUBMITTED
    _fade_tween = create_tween()
    _fade_tween.tween_property(self, "modulate:a", 0.0, 0.15)
    _fade_tween.finished.connect(func(): hide(); _state = State.HIDDEN)

func _on_chapter_interrupted(_reason: String) -> void:
    if _fade_tween and _fade_tween.is_valid(): _fade_tween.kill()
    _state = State.HIDDEN
    hide()
```

## GDD Requirements Addressed

| GDD System | Requirement | How This ADR Addresses It |
|------------|-------------|--------------------------|
| choice-ui.md TR-choice-ui-002 | Three-state machine | State enum: HIDDEN, WAITING, SUBMITTED |
| choice-ui.md TR-choice-ui-003 | Button layout 96dp / 44-46% | custom_minimum_size.y = 96; width set in scene |
| choice-ui.md TR-choice-ui-004 | Card structure icon+word+translation | Button fill in _on_choices_ready |
| choice-ui.md TR-choice-ui-005 | P2 Anti-Pillar both identical | No correct/incorrect logic in ChoiceUI |
| choice-ui.md TR-choice-ui-006 | Rule 6 not subscribe highlight | Documented: no tts_fallback_to_highlight subscription |
| choice-ui.md TR-choice-ui-008 | FOCUS_NONE for all buttons | focus_mode set in _ready() |
| choice-ui.md TR-choice-ui-010 | Multi-touch double submit | State machine guard: WAITING check before submit |

## Consequences

- **P2 enforced by design**: ChoiceUI has no knowledge of which choice is correct
- **State machine prevents all race conditions**: Double-submit, rapid-fire, interrupt during animation
- **Simple**: ~50 lines of GDScript; minimal risk

## Related Decisions

- ADR-0010: StoryManager Narrative Engine (choices_ready, submit_choice)
- ADR-0011: AnimationHandler (T-Rex reaction after choice)
- design/gdd/choice-ui.md — ChoiceUI GDD
