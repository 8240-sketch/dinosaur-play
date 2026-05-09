# ADR-0021: ParentVocabMap Parent-Facing Progress View

## Status
Accepted (2026-05-09)

## Date
2026-05-09

## Engine Compatibility

| Field | Value |
|-------|-------|
| **Engine** | Godot 4.6 |
| **Domain** | UI |
| **Knowledge Risk** | LOW — ParentVocabMap uses CanvasLayer, PROCESS_MODE_ALWAYS, and standard Control nodes |
| **References Consulted** | `docs/engine-reference/godot/VERSION.md` |
| **Post-Cutoff APIs Used** | None |
| **Verification Required** | (1) CanvasLayer layer=128 overlays all game UI; (2) PROCESS_MODE_ALWAYS allows interaction during SceneTree.paused; (3) NOTIFICATION_WM_GO_BACK_REQUEST for Android back key |

## ADR Dependencies

| Field | Value |
|-------|-------|
| **Depends On** | ADR-0006 (VocabStore — get_gold_star_count, gold_star_awarded signal); ADR-0009 (VoiceRecorder — get_recording_paths, play_recording, playback signals) |
| **Enables** | None — ParentVocabMap is a leaf consumer |
| **Blocks** | ParentVocabMap implementation |
| **Ordering Note** | ADR-0006 and ADR-0009 must be Accepted. |

## Context

### Problem Statement

ParentVocabMap is a full-screen vocabulary progress view accessible only via long-press (5 seconds) from MainMenu or chapter completion screen. It shows gold star progress for all 5 Chapter 1 words and allows parents to play back their child's voice recordings. The system must work during SceneTree.paused (CanvasLayer with PROCESS_MODE_ALWAYS), handle VoiceRecorder optional gracefully (is_instance_valid guard), and update in real-time when new gold stars are awarded.

### Constraints

- **CanvasLayer layer=128** — overlays all game UI
- **SceneTree.paused**: _ready() pauses; queue_free() unpauses
- **PROCESS_MODE_ALWAYS**: All internal nodes must be pausable-resistant
- **VoiceRecorder optional**: is_instance_valid guard; missing → recording area hidden
- **Long-press detection**: Delegated to trigger scene (MainMenu/GameScene), not ParentVocabMap itself
- **Close**: × button, Android back key, ui_cancel — all trigger same close sequence

### Requirements

- _ready() synchronous queries: VocabStore × 3 methods × 5 words + VoiceRecorder recording_paths
- Real-time gold star updates via gold_star_awarded signal subscription
- Recording display: MAX_RECORDINGS_DISPLAYED entries; pin oldest recording
- One-at-a-time playback: new playback resets previous button state
- Close sequence: stop playback → write parent_map_hint_dismissed → unpause → queue_free()

## Decision

ParentVocabMap is a CanvasLayer overlay (layer=128) that pauses the game tree, queries VocabStore and VoiceRecorder synchronously, and presents a parent-only vocabulary progress view.

```gdscript
class_name ParentVocabMap extends CanvasLayer

func _ready() -> void:
    layer = 128
    get_tree().paused = true
    _query_data()
    VocabStore.gold_star_awarded.connect(_on_gold_star_awarded)

func _query_data() -> void:
    for word_id in VOCAB_WORD_IDS_CH1:
        var stars: int = VocabStore.get_gold_star_count(word_id)
        var first_at: String = VocabStore.get_first_star_at(word_id)
        var learned: bool = VocabStore.is_word_learned(word_id)
        var recordings: Array = []
        if is_instance_valid(VoiceRecorder):
            recordings = VoiceRecorder.get_recording_paths(word_id)
        $VocabEntries.get_node(word_id).setup(stars, first_at, learned, recordings)

func _on_gold_star_awarded(word_id: String, new_count: int) -> void:
    if is_queued_for_deletion(): return
    $VocabEntries.get_node(word_id).set_star_count(new_count)

func _close() -> void:
    if is_instance_valid(VoiceRecorder):
        VoiceRecorder.stop_playback()
    if not ProfileManager.get_section("profile").get("parent_map_hint_dismissed", false):
        ProfileManager.get_section("profile")["parent_map_hint_dismissed"] = true
        ProfileManager.flush()
    get_tree().paused = false
    queue_free()
```

### Recording Playback

- One recording plays at a time
- New play_recording() call must actively reset previous button state (don't rely on playback_completed signal)
- playback_failed("file_not_found") → grey out that entry

### Close Triggers

- × button (80dp min)
- Android back: NOTIFICATION_WM_GO_BACK_REQUEST in _notification()
- Desktop: ui_cancel in _unhandled_input()

## GDD Requirements Addressed

| GDD System | Requirement | How This ADR Addresses It |
|------------|-------------|--------------------------|
| parent-vocab-map.md TR-parent-vocab-map-001 | CanvasLayer layer=128, paused | layer=128 in _ready(); get_tree().paused = true |
| parent-vocab-map.md TR-parent-vocab-map-002 | Long-press delegated | ParentVocabMap doesn't handle long-press; trigger scene does |
| parent-vocab-map.md TR-parent-vocab-map-003 | 20dp drift tolerance | Delegated to trigger scene |
| parent-vocab-map.md TR-parent-vocab-map-004 | _ready() synchronous query | _query_data() batch queries VocabStore + VoiceRecorder |
| parent-vocab-map.md TR-parent-vocab-map-005 | VoiceRecorder optional guard | is_instance_valid check; missing → recordings = [] |
| parent-vocab-map.md TR-parent-vocab-map-006 | Recording display MAX | MAX_RECORDINGS_DISPLAYED; pin oldest |
| parent-vocab-map.md TR-parent-vocab-map-007 | Close sequence 4 steps | _close(): stop playback → hint dismiss → unpause → queue_free |
| parent-vocab-map.md TR-parent-vocab-map-008 | gold_star_awarded subscription | Connected in _ready(); is_queued_for_deletion guard |
| parent-vocab-map.md TR-parent-vocab-map-009 | One-at-a-time playback | Active reset of previous button before new play |

## Consequences

- **Parent-only access**: 5-second long-press ensures child cannot accidentally enter
- **Real-time updates**: gold_star_awarded signal keeps display current during ACTIVE state
- **VoiceRecorder graceful degradation**: Missing VoiceRecorder → recording area hidden, no crash
- **Game pause**: SceneTree.paused stops all gameplay while parent views progress

## Related Decisions

- ADR-0006: VocabStore Formula (get_gold_star_count, gold_star_awarded)
- ADR-0009: VoiceRecorder (get_recording_paths, play_recording, playback signals)
- ADR-0005: ProfileManager (parent_map_hint_dismissed field, flush)
- design/gdd/parent-vocab-map.md — ParentVocabMap GDD
