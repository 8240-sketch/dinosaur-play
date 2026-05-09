# ADR-0019: Chapter2Teaser Post-Chapter Teaser Sequence

## Status
Accepted (2026-05-09)

## Date
2026-05-09

## Engine Compatibility

| Field | Value |
|-------|-------|
| **Engine** | Godot 4.6 |
| **Domain** | UI / Animation |
| **Knowledge Risk** | LOW — Chapter2Teaser uses standard Tween, CanvasLayer, ColorRect, Sprite2D, and change_scene_to_file(); no post-cutoff APIs |
| **References Consulted** | `docs/engine-reference/godot/VERSION.md` |
| **Post-Cutoff APIs Used** | None — all APIs are stable across Godot 4.x |
| **Verification Required** | (1) Tween pauses correctly with SceneTree.paused; (2) change_scene_to_file() return value check; (3) AudioStreamPlayer volume_db tween works independently of CanvasLayer modulate |

## ADR Dependencies

| Field | Value |
|-------|-------|
| **Depends On** | None — Chapter2Teaser has zero game-system dependencies |
| **Enables** | MainMenu (navigation target after teaser) |
| **Blocks** | None — Chapter2Teaser is a leaf node in the chapter completion sequence |
| **Ordering Note** | No ADR dependencies. Can be implemented at any time. |

## Context

### Problem Statement

After the child completes a chapter and the PostcardGenerator saves the postcard, a brief teaser should appear — animal silhouettes hinting at Chapter 2's theme, with the text "还有更多冒险……". This 3-second sequence creates anticipation for future content without any interactive elements. The teaser must be completely self-contained: zero data dependencies, all content hardcoded in the scene file, auto-destroying after completion.

### Constraints

- **Zero dependencies**: Does not query VocabStore, ProfileManager, or any AutoLoad
- **Static content**: All visuals and text hardcoded in scene file; @export for art assets only
- **No interaction**: No _input(), no _unhandled_input(), no buttons — mouse_filter = IGNORE
- **Auto-lifecycle**: Instantiated by GameScene after PostcardGenerator; self-destructs via scene change
- **Timeout safety**: If Tween fails silently, a 5s timeout forces scene transition
- **Interrupt tolerance**: SceneTree.paused handles app backgrounding transparently

### Requirements

- 2-phase animation: HOLDING (0.5s static) → FADING (2.5s Tween fade-out)
- Total display: 3.0s (HOLD_DURATION + FADE_OUT_DURATION)
- change_scene_to_file() to MainMenu on Tween.finished or timeout
- _transitioning bool guard prevents double scene change
- AudioStreamPlayer sting fades independently (volume_db tween, not affected by CanvasLayer modulate)
- CanvasLayer layer=10 to overlay all GameScene UI

## Decision

### Architecture

Chapter2Teaser is a Polish layer CanvasLayer node (non-AutoLoad) instantiated by GameScene after PostcardGenerator completes. It holds all content statically, drives a 2-phase animation (hold + fade), and transitions to MainMenu on completion.

```
GameScene
    │
    ├─ PostcardGenerator.postcard_saved/failed → add_child(Chapter2Teaser)
    │     │
    │     ├─ HOLDING (0.5s): static display, modulate.a = 1.0
    │     ├─ FADING (2.5s): Tween modulate.a 1.0 → 0.0 (SINE/EASE_IN)
    │     ├─ Tween.finished → change_scene_to_file(MainMenu)
    │     └─ TWEEN_TIMEOUT (5.0s) → fallback change_scene_to_file(MainMenu)
    │
    └─ Chapter2Teaser destroyed with scene change
```

### Key Interfaces

```gdscript
class_name Chapter2Teaser extends CanvasLayer

const HOLD_DURATION: float = 0.5
const FADE_OUT_DURATION: float = 2.5
const TWEEN_TIMEOUT_SEC: float = 5.0
const TEASER_FONT_SIZE: int = 48
const MAIN_MENU_SCENE_PATH: String = "res://scenes/ui/MainMenu.tscn"

@export var silhouette_textures: Array[Texture2D]  ## [猴子, 大象, 狮子, 长颈鹿, 河马]
@export var teaser_sound: AudioStream               ## CC0 音效

var _transitioning: bool = false

func _ready() -> void:
    layer = 10
    _start_timeout_timer()
    _start_hold_phase()

func _start_hold_phase() -> void:
    # HOLDING: modulate.a = 1.0, static display
    await get_tree().create_timer(HOLD_DURATION).timeout
    _start_fade_phase()

func _start_fade_phase() -> void:
    var tween := create_tween()
    tween.tween_property(self, "modulate:a", 0.0, FADE_OUT_DURATION) \
         .set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
    # Parallel: fade audio sting volume
    if $SoundPlayer.playing:
        tween.parallel().tween_property($SoundPlayer, "volume_db", -60.0, FADE_OUT_DURATION)
    tween.finished.connect(_do_scene_transition)

func _start_timeout_timer() -> void:
    var timer := get_tree().create_timer(TWEEN_TIMEOUT_SEC)
    timer.timeout.connect(_do_scene_transition)

func _do_scene_transition() -> void:
    if _transitioning:
        return  # guard: prevent double transition
    _transitioning = true
    get_tree().change_scene_to_file(MAIN_MENU_SCENE_PATH)
```

### Animation Curve

```
modulate_a(t) = ease_in_sine(1.0 - t / FADE_OUT_DURATION)
              ≈ 1.0 - sin((t / FADE_OUT_DURATION) × π/2)
```

EASE_IN chosen: starts slow (child sees silhouettes clearly), ends fast (disappears quickly). Matches the emotional descent after chapter completion.

### Timeout Safety

TWEEN_TIMEOUT_SEC (5.0s) > HOLD_DURATION + FADE_OUT_DURATION (3.0s) + δ (2.0s margin).

If Tween fires finished: timer is abandoned (scene change already triggered).
If timeout fires first: scene change forced, child is not stuck.

### Interrupt Tolerance

Chapter2Teaser uses PROCESS_MODE_PAUSABLE (default). When InterruptHandler sets SceneTree.paused = true:
- HOLD timer pauses
- Tween pauses (modulate.a freezes at current value)
- Timeout timer pauses
On resume: all continue from where they stopped. No data loss, no restart.

## Alternatives Considered

### Alternative 1: Signal-based scene change (Path B)

- **Description**: Chapter2Teaser emits a signal; GameScene handles change_scene_to_file()
- **Pros**: Chapter2Teaser doesn't need to know the target scene path
- **Cons**: Adds coupling — GameScene must subscribe and handle. Chapter2Teaser is a terminal node; direct scene change is simpler.
- **Rejection Reason**: GDD Rule 4 specifies Path A (self-transition). Chapter2Teaser is the end of the chapter completion sequence — there's no reason to defer the scene change to the parent.

### Alternative 2: Separate Tween for audio

- **Description**: AudioStreamPlayer has its own Tween for volume_db fade
- **Pros**: Independent control
- **Cons**: Must synchronize with the visual fade; two Tweens = two finish signals
- **Rejection Reason**: Using tween.parallel() on the same Tween keeps visual and audio fades synchronized with a single finished signal.

### Alternative 3: Timer-based fade (no Tween)

- **Description**: Use _process() delta to manually interpolate modulate.a
- **Pros**: No Tween dependency
- **Cons**: Must handle pause/resume manually; more code; less smooth than Tween
- **Rejection Reason**: Tween handles pause/resume automatically with SceneTree.paused. Less code, smoother animation, built-in easing functions.

## Consequences

### Positive

- **Zero coupling**: No dependencies on any game system — can be built and tested in complete isolation
- **Self-contained**: All content in scene file; no runtime data queries
- **Interrupt-safe**: SceneTree.paused handles all edge cases transparently
- **Timeout-proof**: 5s safety net ensures child is never stuck
- **Simple**: ~50 lines of GDScript; minimal risk of bugs

### Negative

- **Static content**: Cannot vary teaser based on progress or profile. Acceptable — teaser is a fixed cinematic moment.
- **No skip**: Child watches full 3 seconds every time. Acceptable — duration is short and serves emotional purpose.
- **Art dependency**: @export textures must be assigned in editor; missing textures show placeholder. Mitigated by E5 (no crash, just ugly).

### Risks

| Risk | Severity | Mitigation |
|------|:--------:|------------|
| Tween silent failure (never fires finished) | LOW | TWEEN_TIMEOUT_SEC = 5.0s forces scene change |
| change_scene_to_file() fails (MainMenu missing) | LOW | assert(ResourceLoader.exists()) in _ready() for dev builds |
| Silhouette/contrast hard to see on dark background | LOW | GDD N-2: art team verifies on real device; adjust colors if needed |
| AudioStreamPlayer not affected by CanvasLayer modulate | LOW | Separate volume_db tween via tween.parallel() |

## GDD Requirements Addressed

| GDD System | Requirement | How This ADR Addresses It |
|------------|-------------|--------------------------|
| chapter2-teaser.md TR-chapter2-teaser-001 | One-shot lifecycle by GameScene | GameScene add_child after PostcardGenerator |
| chapter2-teaser.md TR-chapter2-teaser-002 | Two-phase: HOLDING → FADING | _start_hold_phase + _start_fade_phase |
| chapter2-teaser.md TR-chapter2-teaser-003 | TWEEN_TIMEOUT_SEC = 5.0s | _start_timeout_timer in _ready() |
| chapter2-teaser.md TR-chapter2-teaser-004 | No input response | No _input/_unhandled_input; mouse_filter IGNORE |
| chapter2-teaser.md TR-chapter2-teaser-005 | _transitioning guard | Bool flag in _do_scene_transition |
| chapter2-teaser.md TR-chapter2-teaser-006 | SceneTree.paused integration | PROCESS_MODE_PAUSABLE default; Tween/timer pause automatically |
| chapter2-teaser.md TR-chapter2-teaser-007 | All content hardcoded | @export for art; const for text; no data queries |

## Performance Implications

- **CPU**: Tween interpolation: <0.1ms/frame. Timer: negligible.
- **Memory**: CanvasLayer + 5 Sprite2D + ColorRect + Label + AudioStreamPlayer: ~100KB (mostly textures). Destroyed on scene change.
- **Load Time**: Scene instantiation: <50ms. No data loading.
- **Network**: N/A — all local.

## Migration Plan

This ADR creates a new scene (Chapter2Teaser.tscn). No migration needed.

**GameScene implementation note**: GameScene must implement the serial instantiation logic (PostcardGenerator signal → add_child Chapter2Teaser) with _teaser_shown guard.

## Validation Criteria

1. AC-1: PostcardGenerator signal → Chapter2Teaser instantiated
2. AC-2: HOLDING phase — modulate.a = 1.0, static 0.5s
3. AC-3: FADING phase — smooth 2.5s fade to 0.0
4. AC-4: Total time 3.0s ± 0.2s to MainMenu
5. AC-5: Timeout at 5.0s forces scene change if Tween fails
6. AC-6: No touch response during HOLDING/FADING
7. AC-7: _teaser_shown guard prevents duplicate instantiation
8. AC-8: SceneTree.paused freezes animation in background
9. AC-9: Resume continues from paused modulate.a value
10. AC-10: 5 animal silhouettes visible during HOLDING
11. AC-11: Text "还有更多冒险……" visible and readable
12. AC-12: Audio sting plays during HOLDING
13. AC-13: Node destroyed after scene change

## Related Decisions

- ADR-0016: HatchScene Ceremony (similar one-shot scene pattern)
- design/gdd/chapter2-teaser.md — Chapter2Teaser GDD (full specification)
- design/gdd/postcard-generator.md — PostcardGenerator GDD (predecessor in chapter completion sequence)
