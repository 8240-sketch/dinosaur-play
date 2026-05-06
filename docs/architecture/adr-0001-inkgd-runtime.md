# ADR-0001: inkgd Runtime vs. Custom JSON State Machine

## Status
Proposed

## Date
2026-05-06

## Engine Compatibility

| Field | Value |
|-------|-------|
| **Engine** | Godot 4.6 |
| **Domain** | Scripting / Narrative |
| **Knowledge Risk** | HIGH — inkgd v0.6.0 (godot4 branch) is post-LLM-cutoff; loading API and completion detection verified against inkgd source code |
| **References Consulted** | `docs/engine-reference/godot/VERSION.md`; inkgd v0.6.0 godot4 branch source (github.com/ephread/inkgd) |
| **Post-Cutoff APIs Used** | `InkResource` (intermediary type for `load()`); `InkStory.new(json, runtime)` constructor; `can_continue` property for completion detection (not `is_story_complete` — does not exist) |
| **Verification Required** | Confirm `load()` → `InkResource` path on Android APK export; verify `InkChoice.tags` null safety on device; confirm `.ink.json` assets exported correctly by Godot |

## ADR Dependencies

| Field | Value |
|-------|-------|
| **Depends On** | None |
| **Enables** | StoryManager implementation; TagDispatcher implementation |
| **Blocks** | StoryManager implementation (was OQ-1); TagDispatcher implementation (was OQ-4) |
| **Ordering Note** | This ADR must be Accepted before StoryManager and TagDispatcher are implemented. Week 1 end gate on Android device is the acceptance trigger. |

## Context

### Problem Statement
The game requires a narrative branching runtime to drive Chapter 1's story script (`.ink` format). We must decide between (A) inkgd v0.6.0 — the GDScript-native Ink runtime — and (B) a custom JSON state machine (~150 GDScript lines) authored and parsed by StoryManager directly.

This decision affects story authoring toolchain, runtime memory cost on Android, Chapter 1 script maintainability, and the fallback path if inkgd has Android export issues.

### Constraints
- Engine: Godot 4.6, GDScript only (no C#)
- Platform: Android API 24+, 256 MB memory ceiling
- Timeline: 4-week MVP; Chapter 1 must be testable on device by Week 1 end
- inkgd `main` branch is Godot 3 — **must use `godot4` branch (v0.6.0)**
- inklecate v1.2.0 is required as a **build-time** compiler to produce `.ink.json` from `.ink` source; it is **not** a runtime dependency
- Story authoring must be accessible to non-programmers (Inky IDE support)

### Requirements
- Must support branching choices (2 options per node, MVP `MAX_CHOICES = 2`)
- Must expose tags per narrative line (for `vocab:`, `anim:`, `record:` dispatch to TagDispatcher)
- Must expose per-choice tags (for `word_id` extraction in StoryManager Rule 5)
- Must run on Android API 24+ without JNI or native code
- Must integrate with Godot's `load()` resource pipeline

## Decision

Adopt **inkgd v0.6.0 (godot4 branch)** as the Ink runtime, wrapped by StoryManager as an AutoLoad singleton.

### Correct Loading Sequence (verified against inkgd source)

```gdscript
# load() returns InkResource, NOT InkStory — intermediary type required
var _res: InkResource = load("res://assets/data/chapter1.ink.json")
var _runtime = InkRuntime.get_singleton()
var story: InkStory = InkStory.new(_res.json, _runtime)
```

> ⚠️ **BLOCKING**: `load()` on a `.ink.json` asset returns `InkResource`, not `InkStory`.
> Any code that casts `load(path)` directly to `InkStory` will fail at runtime.

### Narrative Advancement

```gdscript
story.continue_story()
var text: String = story.current_text
# current_tags is untyped Array and CAN BE NULL — null-guard required
var raw_tags: Array = story.current_tags if story.current_tags != null else []
# Completion: is_story_complete does NOT exist — use this pattern instead
var is_done: bool = !story.can_continue and story.current_choices.is_empty()
```

> ⚠️ **BLOCKING**: `is_story_complete` property does **not** exist in inkgd v0.6.0.
> Use `!story.can_continue && story.current_choices.is_empty()` for completion detection.

> ⚠️ `current_tags` is an untyped `Array` and can be `null`. Always null-guard.

### Choice Handling

```gdscript
var choices: Array = story.current_choices  # untyped Array, may be empty
for i in choices.size():
    # InkChoice.tags is declared as `var tags = null` — NULLABLE
    var raw_choice_tags: Array = choices[i].tags if choices[i].tags != null else []
    var word_id: String = ""
    for tag in raw_choice_tags:
        if tag.begins_with("vocab:"):
            word_id = tag.split(":")[1]
            break
story.choose_choice_index(selected_index)
```

> ⚠️ `InkChoice.tags` is nullable (`var tags = null`). Null-guard is mandatory.

### Build-Time Dependency: inklecate

`.ink` source files are compiled to `.ink.json` by inklecate v1.2.0 at **authoring time**, not at runtime. The compiled `.ink.json` files are checked into the repository under `assets/data/` and exported with the Godot project as ordinary assets.

The Godot runtime and Android APK have zero dependency on inklecate. Story changes require a manual inklecate re-compile step before testing in-engine.

### Architecture Diagram

```
[Ink author] → .ink source → inklecate v1.2.0 → .ink.json
                                                      ↓  (checked into git)
StoryManager.begin_chapter()  load() → InkResource → InkStory.new(res.json, runtime)
                                                      ↓
                              story.continue_story()
                                   ↓           ↓
                           current_tags    current_choices
                                ↓                ↓
                    tags_dispatched(Array) → TagDispatcher
                    choices_ready(Array[Dictionary]) → ChoiceUI
```

### Key Interfaces

```gdscript
# Signal types (inkgd untyped — use Array, not Array[String])
signal tags_dispatched(tags: Array)         # can contain null; null-guard in TagDispatcher
signal choices_ready(choices: Array[Dictionary])  # [{index, text, word_id}]

# inkgd API surface consumed by StoryManager
story.continue_story() -> void
story.current_text: String
story.current_tags: Array                   # NULLABLE — null-guard required
story.current_choices: Array                # untyped Array of InkChoice objects
story.can_continue: bool
story.choose_choice_index(index: int) -> void

# InkChoice (per element of current_choices)
choice.text: String
choice.tags: var                            # NULLABLE — null-guard required
```

## Alternatives Considered

### Alternative A: Custom JSON State Machine (~150 GDScript lines)

- **Description**: Author Chapter 1 as a hand-crafted JSON file describing nodes, text, choices, and tags. StoryManager parses it directly; no external runtime.
- **Pros**: Zero external dependency; fully auditable; no build-time toolchain; Android risk = zero
- **Cons**: No standard authoring tool; no branching composition primitives; does not scale to Chapter 2+; locks out non-programmer story authors; combinatorial branching error-prone at scale
- **Rejection Reason**: Chapter 1 requires ~40–60 branching nodes across 5 vocabulary words and multiple story paths. Hand-editing JSON at that scale is unsustainable and prevents narrative iteration. inkgd provides Ink language + Inky IDE with live preview. **This remains the Week 1 gate fallback if inkgd fails on Android.**

### Alternative B: InkPlayer Node (inkgd built-in node pattern)

- **Description**: Use inkgd's `InkPlayer` scene node rather than managing `InkStory` directly.
- **Pros**: More encapsulated per scene; matches inkgd documentation examples
- **Cons**: Per-scene instantiation conflicts with StoryManager's AutoLoad singleton; chapter state tied to scene lifetime; profile switch mid-chapter requires scene-level coordination
- **Rejection Reason**: StoryManager must persist across scene transitions (profile switch, HatchScene routing). AutoLoad singleton with direct `InkStory` management matches this lifecycle requirement.

## Consequences

### Positive
- Standard Ink authoring: `.ink` → Inky IDE preview → `inklecate` compile → `.ink.json`
- Chapter 2+ content authored without touching GDScript
- inkgd is GDScript-native — no JNI, no C++ bridge, no Android-specific loading risk (pending Week 1 gate)
- Full Ink feature set available for narrative complexity (variables, knots, stitches)

### Negative
- inklecate must be installed on all developer machines; story changes require a manual compile step
- inkgd API surface is not fully documented; null-safety behaviors were inferred from source code, not official docs
- `InkRuntime` singleton must be initialized before `InkStory.new()` — initialization order must be verified

### Risks

| Risk | Severity | Mitigation |
|------|----------|------------|
| **R1: Android APK export instability** | HIGH | **Week 1 end gate**: load `chapter1_minimal.ink.json` (3 nodes, 1 choice) on real Android device. If load fails → switch to Alternative A, estimated 1–2 days. All StoryManager signals (`tags_dispatched`, `choices_ready`) remain unchanged. |
| **R2: inkgd branch API drift** | MEDIUM | Pin to v0.6.0 tag of `godot4` branch. Lock `addons/inkgd/` in git. Do not auto-update. |
| **R3: inklecate version mismatch** | LOW | Pin inklecate to v1.2.0. Document in `docs/engine-reference/godot/VERSION.md`. |
| **R4: null-safety runtime errors on Android** | MEDIUM | All `current_tags` and `InkChoice.tags` access must null-guard (see Key Interfaces). These are silent in-editor but crash on Android without guards. |
| **R5: `InkRuntime` initialization order** | LOW | In `StoryManager._ready()`, assert `InkRuntime.get_singleton() != null` before `InkStory.new()`. Add `push_error` guard and transition to `ERROR` state if null. |

## GDD Requirements Addressed

| GDD System | Requirement | How This ADR Addresses It |
|------------|-------------|--------------------------|
| story-manager.md | Rule 3d: "从 `ink_json_path` 加载已编译的 `.ink.json` 文件（加载模式见 ADR-INKGD-RUNTIME）" | Defines: `load()` → `InkResource` → `InkStory.new(res.json, runtime)` |
| story-manager.md | Rule 4b: `continue_story()` 推进 | Confirms `InkStory.continue_story()` exists in v0.6.0 |
| story-manager.md | Rule 4d: `current_tags` → `tags_dispatched` signal | Corrects signal type to `tags_dispatched(tags: Array)` (not `Array[String]`); mandates null-guard |
| story-manager.md | Rule 8: chapter completion detection | `is_story_complete` does NOT exist; use `!story.can_continue && story.current_choices.is_empty()` |
| story-manager.md | E3: `.ink.json` load failure fallback | Week 1 gate: Android failure → switch to Alternative A (custom JSON state machine) |
| tag-dispatcher.md | OQ-4: "TagDispatcher 实现前必须创建 ADR-INKGD-RUNTIME" | This ADR fulfills that prerequisite |
| vocab-store.md | Rule 3.1: "调用时机约束" references `InkStory.is_story_complete` | Corrects to `!story.can_continue && story.current_choices.is_empty()` |

## Performance Implications
- **CPU**: `InkStory.continue_story()` parses compiled Ink JSON incrementally; expected <1ms per step on mid-range Android (unverified — measure Week 1)
- **Memory**: Chapter 1 `.ink.json` estimated 10–30 KB; `InkStory` runtime state ~50–100 KB; well within 256 MB ceiling
- **Load Time**: `load()` is synchronous; expected <50ms on Android; occurs in `begin_chapter()` step d (non-blocking from player perspective due to prior warm-up)
- **Network**: N/A — all story assets local

## Migration Plan

If Week 1 Android gate fails (R1 triggered):
1. Remove `InkResource` / `InkStory` dependency from `StoryManager`
2. Replace `_load_ink_chapter()` with `_load_json_chapter(path)` (~150 lines)
3. All outward signals (`tags_dispatched`, `choices_ready`, `chapter_started`, etc.) remain unchanged — TagDispatcher and ChoiceUI are not affected
4. Estimated: 1–2 days including testing

## Validation Criteria
1. `chapter1_minimal.ink.json` (3 nodes, 1 choice, 2 vocab tags) loads without error on Android API 24+ device — **Week 1 end gate**
2. `current_tags` returns a non-null Array after `continue_story()` on a tagged node
3. `InkChoice.tags` returns a non-null Array for a choice with `vocab:word_id:correct` tags
4. `!story.can_continue && story.current_choices.is_empty()` correctly detects story end
5. Full Chapter 1 playthrough on Android device completes without `push_error` or crash (AC-01 through AC-28 in story-manager.md pass)

## Related Decisions
- design/gdd/story-manager.md — StoryManager GDD (wraps this runtime)
- design/gdd/tag-dispatcher.md — TagDispatcher GDD (consumes `tags_dispatched` signal)
- docs/engine-reference/godot/VERSION.md — Engine version and post-cutoff risk reference
