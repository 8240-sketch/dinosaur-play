# ADR-0018: VocabPrimingLoader Pre-Chapter Vocabulary Preview

## Status
Accepted (2026-05-09)

## Date
2026-05-09

## Engine Compatibility

| Field | Value |
|-------|-------|
| **Engine** | Godot 4.6 |
| **Domain** | UI / Animation |
| **Knowledge Risk** | LOW — VocabPrimingLoader uses standard Tween, Control nodes, and modulate property; no post-cutoff APIs |
| **References Consulted** | `docs/engine-reference/godot/VERSION.md` |
| **Post-Cutoff APIs Used** | None — Tween, modulate, CanvasLayer are stable across all Godot 4.x versions |
| **Verification Required** | (1) Tween pauses correctly with SceneTree.paused; (2) modulate.a fade works on CanvasLayer children; (3) queue_free() during tween callback doesn't crash |

## ADR Dependencies

| Field | Value |
|-------|-------|
| **Depends On** | ADR-0006 (VocabStore — get_gold_star_count API) |
| **Enables** | GameScene (subscribes priming_complete to trigger begin_chapter) |
| **Blocks** | Chapter start flow (VocabPrimingLoader must complete before begin_chapter) |
| **Ordering Note** | ADR-0006 must be Accepted. VocabPrimingLoader is a leaf Presentation layer node — no downstream ADRs depend on it. |

## Context

### Problem Statement

Before each chapter begins, the child should see a brief vocabulary preview — the 5 English words they'll encounter, with gold star indicators showing their learning progress. This serves two purposes: (1) the child gets a "ready" ritual before the story (P1 — learning invisible in ceremony), and (2) the parent gets a quick overview of which words are new vs. already mastered (P4). The preview must be non-interactive (auto-play, no skip), complete in 5–8 seconds, and self-destruct after completion. It must tolerate app backgrounding (SceneTree.paused) without losing state.

### Constraints

- **Non-interactive**: No buttons, no touch response, no skip — mouse_filter = MOUSE_FILTER_STOP
- **Auto-lifecycle**: Instantiated by GameScene via add_child(); _ready() auto-starts; queue_free() on completion
- **Static snapshot**: VocabStore queried once in _ready(); no runtime re-query during animation
- **Interrupt tolerance**: Relies on SceneTree.paused (strategy A) — Tween pauses/resumes automatically
- **Duration constraint**: Total sequence must be 5–8 seconds
- **Signal contract**: priming_complete emitted before queue_free(); ONE_SHOT connection

### Requirements

- 4-state linear sequence: INITIALIZING → CARD_SEQUENCE → ASSEMBLED → FADING_OUT
- Single Tween chain (no await) drives all card animations
- Cards accumulate (stay visible), not sequential show/hide
- Three-tier gold star visual: FRESH (0 stars), PROGRESSING (1-2), MASTERED (3+)
- IS_LEARNED_THRESHOLD = 3 from entities.yaml (VocabPrimingLoader references, does not own)
- Total duration formula: CARD_COUNT × (CARD_APPEAR + CARD_HOLD) + ASSEMBLED_HOLD + FULL_FADE

## Decision

### Architecture

VocabPrimingLoader is a one-shot Presentation layer scene node (non-AutoLoad) instantiated by GameScene before calling StoryManager.begin_chapter(). It queries VocabStore for gold star counts, builds 5 VocabCard children, drives a single Tween chain for the card sequence, and self-destructs via queue_free() after emitting priming_complete.

```
GameScene
    │
    ├─ add_child(VocabPrimingLoader)  ← _ready() auto-starts
    │     │
    │     ├─ INITIALIZING: query VocabStore × 5, build VocabCards
    │     ├─ CARD_SEQUENCE: Tween chain — 5 cards fade in sequentially
    │     ├─ ASSEMBLED: all 5 visible, hold ASSEMBLED_HOLD_SEC
    │     ├─ FADING_OUT: modulate.a → 0
    │     └─ priming_complete.emit() → queue_free()
    │
    └─ on priming_complete → StoryManager.begin_chapter()
```

### Key Interfaces

```gdscript
class_name VocabPrimingLoader extends Control

signal priming_complete()

const CARD_COUNT: int = 5
const CARD_APPEAR_SEC: float = 0.30
const CARD_HOLD_SEC: float = 0.60
const ASSEMBLED_HOLD_SEC: float = 1.00
const FULL_FADE_SEC: float = 0.50

var _star_counts: Dictionary = {}  # word_id -> int

func _ready() -> void:
    mouse_filter = Control.MOUSE_FILTER_STOP
    _query_vocab_store()
    _build_cards()
    _start_sequence()

func _query_vocab_store() -> void:
    for word_id in VOCAB_WORD_IDS_CH1:
        _star_counts[word_id] = VocabStore.get_gold_star_count(word_id)

func _build_cards() -> void:
    for i in range(CARD_COUNT):
        var card := VocabCard.new()
        card.setup(VOCAB_WORD_IDS_CH1[i], _star_counts[VOCAB_WORD_IDS_CH1[i]])
        card.modulate.a = 0.0
        $CardContainer.add_child(card)

func _start_sequence() -> void:
    var tween := create_tween()
    for card in $CardContainer.get_children():
        tween.tween_property(card, "modulate:a", 1.0, CARD_APPEAR_SEC)
        tween.tween_interval(CARD_HOLD_SEC)
    tween.tween_interval(ASSEMBLED_HOLD_SEC)
    tween.tween_property(self, "modulate:a", 0.0, FULL_FADE_SEC)
    tween.tween_callback(_on_sequence_complete)

func _on_sequence_complete() -> void:
    priming_complete.emit()
    queue_free()
```

### VocabCard Gold Star Visual Tiers

```
VocabCard.setup(word_id: String, star_count: int) -> void:
    match star_count:
        0:  # FRESH — no stars, no glow, neutral text
        1..2:  # PROGRESSING — semi-transparent stars, light gold glow
        _:  # MASTERED (≥3) — full stars, strong gold glow, warm gold text
```

IS_LEARNED_THRESHOLD (= 3) is referenced from entities.yaml, not owned by VocabPrimingLoader.

### Duration Formula

```
total_duration = CARD_COUNT × (CARD_APPEAR_SEC + CARD_HOLD_SEC)
               + ASSEMBLED_HOLD_SEC + FULL_FADE_SEC

Default: 5 × (0.30 + 0.60) + 1.00 + 0.50 = 6.0s ∈ [5.0, 8.0] ✓
```

### Interrupt Tolerance (Strategy A)

VocabPrimingLoader does NOT participate in InterruptHandler's interrupt protocol. When InterruptHandler sets `SceneTree.paused = true`, the Tween automatically pauses. On resume, the Tween continues from where it stopped. priming_complete is emitted normally after the full sequence completes.

No timeout, no watchdog, no interrupt signal subscription required.

## Alternatives Considered

### Alternative 1: Separate start() method

- **Description**: Provide a public start() method that GameScene calls explicitly after add_child()
- **Pros**: Explicit control over timing
- **Cons**: Adds API surface; _ready() → start() is a two-step init pattern that can be forgotten
- **Rejection Reason**: GDD Rule 1 specifies "add child = start". Single-step lifecycle is simpler and matches the one-shot pattern.

### Alternative 2: Per-card Tween instances

- **Description**: Create a separate Tween per card, chained via signals
- **Pros**: Each card's animation is independent
- **Cons**: Complex coordination; must ensure sequential ordering manually; harder to pause/resume as a unit
- **Rejection Reason**: Single Tween chain is simpler, naturally sequential, and pauses/resumes as one unit with SceneTree.paused.

### Alternative 3: SceneTree.paused NOT used — custom pause logic

- **Description**: VocabPrimingLoader subscribes to InterruptHandler signals and manages its own pause/resume
- **Pros**: Explicit control over pause behavior
- **Cons**: Duplicates InterruptHandler's SceneTree.paused mechanism; adds coupling to InterruptHandler
- **Rejection Reason**: Strategy A (rely on SceneTree.paused) is the simplest approach. Tween already respects SceneTree.paused natively. No need for custom logic.

## Consequences

### Positive

- **Zero coupling**: Only depends on VocabStore (read-only query). No dependency on StoryManager, InterruptHandler, or AnimationHandler.
- **Self-cleaning**: queue_free() after completion — no manual lifecycle management needed
- **Interrupt-safe**: SceneTree.paused handles app backgrounding transparently
- **Testable**: priming_complete signal can be asserted in GUT tests; VocabStore can be mocked
- **Deterministic**: Static snapshot + single Tween chain = same animation every time for same data

### Negative

- **No skip**: Child cannot skip the preview — 5-8 second wait every chapter start. Acceptable because the preview is short and serves a ritual purpose.
- **Static data**: If VocabStore data changes during animation (unlikely), the preview won't update. Acceptable because the preview is a snapshot, not a live dashboard.
- **Small screen risk**: 5 cards × 48dp + 4 × 8dp spacing = 272dp minimum. On 360×640dp devices, only ~250dp remains for background — may need layout tuning (OQ-3).

### Risks

| Risk | Severity | Mitigation |
|------|:--------:|------------|
| 5 cards don't fit on small screen (360×640dp) | MEDIUM | OQ-3: verify layout on target device; fallback to smaller card height or 2×3 grid |
| Tween callback fires after queue_free() | LOW | Godot defers callback to next frame if node is freed during callback — safe. Verified from engine docs. |
| VocabStore not ready when _ready() fires | LOW | VocabStore is AutoLoad (position ③), always ready before any scene loads. get_gold_star_count() returns 0 if no active profile. |

## GDD Requirements Addressed

| GDD System | Requirement | How This ADR Addresses It |
|------------|-------------|--------------------------|
| vocab-priming-loader.md TR-vocab-priming-001 | Lifecycle: add_child auto-starts | _ready() calls _start_sequence() |
| vocab-priming-loader.md TR-vocab-priming-002 | _ready() static snapshot | _query_vocab_store() batch queries once |
| vocab-priming-loader.md TR-vocab-priming-003 | Single Tween chain, no await | create_tween() with sequential tween_property/tween_interval |
| vocab-priming-loader.md TR-vocab-priming-004 | Cards accumulate (stay visible) | Cards fade in and remain; no per-card fade-out |
| vocab-priming-loader.md TR-vocab-priming-005 | No interaction: MOUSE_FILTER_STOP | mouse_filter set in _ready(); no buttons or input handlers |
| vocab-priming-loader.md TR-vocab-priming-006 | Three-tier gold star visual | VocabCard.setup() with FRESH/PROGRESSING/MASTERED tiers |
| vocab-priming-loader.md TR-vocab-priming-007 | Interrupt tolerance via SceneTree.paused | Strategy A: Tween pauses/resumes automatically |
| vocab-priming-loader.md TR-vocab-priming-008 | priming_complete before queue_free | _on_sequence_complete: emit then free |
| vocab-priming-loader.md TR-vocab-priming-009 | Duration [5.0, 8.0] seconds | Formula: 5×(0.30+0.60)+1.00+0.50 = 6.0s |

## Performance Implications

- **CPU**: Tween interpolation: <0.1ms/frame. VocabStore queries: 5 × <0.01ms = <0.05ms total in _ready().
- **Memory**: 5 VocabCard nodes + 1 Tween: ~10KB. Freed after completion via queue_free().
- **Load Time**: Scene instantiation: <50ms. No asset loading (cards are procedurally built).
- **Network**: N/A — all local.

## Migration Plan

This ADR creates a new scene (VocabPrimingLoader.tscn or inline node). No migration needed.

**VocabStore GDD update required**: Add VocabPrimingLoader as a caller of get_gold_star_count() in Interactions table (OQ-1 from vocab-priming-loader.md).

## Validation Criteria

1. AC-1: add_child() auto-starts animation (no external start() call)
2. AC-2: 5 cards fade in sequentially in VOCAB_WORD_IDS_CH1 order
3. AC-3: ASSEMBLED state — all 5 visible, hold ASSEMBLED_HOLD_SEC
4. AC-4: priming_complete emitted, then queue_free()
5. AC-5: Total duration 6.0s ∈ [5.0, 8.0]
6. AC-6/7/8: Gold star visual tiers correct for 0, 1-2, 3+ stars
7. AC-9: Touch during animation — no effect, no buttons
8. AC-10: Touch doesn't penetrate to GameScene
9. AC-11: No active profile — all FRESH, sequence completes
10. AC-12: SceneTree.paused — Tween pauses, resumes, completes normally
11. AC-13: priming_complete before queue_free() ordering
12. AC-14: priming_complete fires exactly once

## Related Decisions

- ADR-0006: VocabStore Formula (get_gold_star_count API)
- ADR-0012: InterruptHandler (SceneTree.paused integration — indirect)
- design/gdd/vocab-priming-loader.md — VocabPrimingLoader GDD (full specification)
- design/gdd/vocab-store.md — VocabStore GDD (get_gold_star_count interface)
