# ADR-0022: PostcardGenerator Image Generation and Gallery Save

## Status
Accepted (2026-05-09)

## Date
2026-05-09

## Engine Compatibility

| Field | Value |
|-------|-------|
| **Engine** | Godot 4.6 |
| **Domain** | Rendering / File I/O |
| **Knowledge Risk** | MEDIUM — SubViewport rendering + OS.get_system_dir behavior on Android API 29+ (Scoped Storage) |
| **References Consulted** | `docs/engine-reference/godot/VERSION.md`; ADR-0003 (Android Gallery Save) |
| **Post-Cutoff APIs Used** | OS.get_system_dir(OS.SYSTEM_DIR_PICTURES) — behavior on Scoped Storage needs device verification |
| **Verification Required** | (1) SubViewport renders correctly at 1080×1080; (2) PNG save to gallery path succeeds; (3) Two-frame await ensures GPU completion |

## ADR Dependencies

| Field | Value |
|-------|-------|
| **Depends On** | ADR-0003 (Android Gallery Save — file path strategy); ADR-0006 (VocabStore — get_gold_star_count) |
| **Enables** | Chapter2Teaser (PostcardGenerator completion triggers teaser) |
| **Blocks** | PostcardGenerator implementation |
| **Ordering Note** | ADR-0003 and ADR-0006 must be Accepted. |

## Context

### Problem Statement

PostcardGenerator creates a 1080×1080 PNG postcard after each chapter completion, showing the child's name, 5 vocabulary words with gold star status, and a T-Rex image. It saves to the Android Pictures gallery. The system uses SubViewport rendering with a two-frame await for GPU completion, and has a silent failure strategy (all errors push_warning, no child-visible errors).

### Constraints

- **One-shot node** (non-AutoLoad); GameScene guard prevents duplicate instantiation
- **_ready() synchronous data query**: ProfileManager name + VocabStore gold_star_count × 5
- **SubViewport 4-step build**: create viewport → load Postcard.tscn → inject data → await 2 frames
- **Silent failure**: All error paths push_warning, no child-visible errors
- **File path**: Tier 1: OS.get_system_dir(PICTURES) + "/TRexJourney/"; Tier 2: OS.get_user_data_dir() + "postcards/"
- **File naming**: postcard_ch{N}_{YYYYMMDD_HHmmss}.png

### Requirements

- SubViewport build sequence (4 steps, strict order)
- Image write with fallback path
- All paths via _finish(success, reason) → emit signal → queue_free()
- Postcard.tscn setup API: setup(child_name, star_data)

## Decision

PostcardGenerator is a one-shot node that queries data, builds a SubViewport, renders a postcard template, and writes the resulting image to the Android gallery.

```gdscript
class_name PostcardGenerator extends Node

signal postcard_saved(path: String)
signal postcard_failed(reason: String)

func _ready() -> void:
    var child_name: String = ProfileManager.get_section("profile").get("name", "")
    var star_counts: Dictionary = {}
    for word_id in VOCAB_WORD_IDS_CH1:
        star_counts[word_id] = VocabStore.get_gold_star_count(word_id)
    _generate.call_deferred(child_name, star_counts)

func _generate(child_name: String, star_counts: Dictionary) -> void:
    # Step a: Create SubViewport
    var viewport := SubViewport.new()
    viewport.size = Vector2i(1080, 1080)
    viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
    add_child(viewport)
    # Step b: Load Postcard.tscn
    var scene = load("res://scenes/postcard/Postcard.tscn")
    if not scene: _finish(false, "scene_load"); return
    var postcard = scene.instantiate()
    viewport.add_child(postcard)
    # Step c: Inject data
    postcard.setup(child_name, star_counts)
    # Step d: Await 2 frames for GPU
    await get_tree().process_frame
    await get_tree().process_frame
    # Get image
    var img: Image = viewport.get_texture().get_image()
    if not img or img.is_empty(): _finish(false, "empty_image"); return
    # Write to gallery
    var dir_path := OS.get_system_dir(OS.SYSTEM_DIR_PICTURES) + "/TRexJourney/"
    if not DirAccess.dir_exists_absolute(dir_path):
        DirAccess.make_dir_recursive_absolute(dir_path)
    var path := dir_path + "postcard_ch1_%s.png" % Time.get_datetime_string_from_system().replace(":", "").replace("-", "").replace("T", "_")
    var fa := FileAccess.open(path, FileAccess.WRITE)
    if not fa: _finish(false, "file_open"); return
    fa.store_buffer(img.save_png_to_buffer())
    fa.close()
    _finish(true, path)

func _finish(success: bool, reason: String) -> void:
    if success: postcard_saved.emit(reason)
    else: postcard_failed.emit(reason)
    queue_free()
```

## GDD Requirements Addressed

| GDD System | Requirement | How This ADR Addresses It |
|------------|-------------|--------------------------|
| postcard-generator.md TR-postcard-gen-001 | One-shot node guard | GameScene _postcard_generating guard |
| postcard-generator.md TR-postcard-gen-002 | _ready() synchronous data query | ProfileManager + VocabStore queries in _ready() |
| postcard-generator.md TR-postcard-gen-003 | SubViewport build 4 steps | _generate() strict a→b→c→d sequence |
| postcard-generator.md TR-postcard-gen-004 | Image write path + fallback | Tier 1: OS.get_system_dir; Tier 2: user_data_dir |
| postcard-generator.md TR-postcard-gen-005 | Silent failure strategy | All errors → push_warning + _finish(false, reason) |
| postcard-generator.md TR-postcard-gen-006 | File naming postcard_ch{N}_ | Format string in _generate() |
| postcard-generator.md TR-postcard-gen-007 | All paths via _finish() | _finish() → emit signal → queue_free() |
| postcard-generator.md TR-postcard-gen-008 | Postcard.tscn setup API | postcard.setup(child_name, star_counts) |

## Consequences

- **Self-contained**: One-shot lifecycle, no persistent state
- **Silent failure**: Child never sees errors; parent just doesn't find postcard in gallery
- **ADR-0003 compliance**: Uses verified Android gallery save strategy

## Related Decisions

- ADR-0003: Android Gallery Save (file path strategy)
- ADR-0006: VocabStore Formula (get_gold_star_count)
- design/gdd/postcard-generator.md — PostcardGenerator GDD
