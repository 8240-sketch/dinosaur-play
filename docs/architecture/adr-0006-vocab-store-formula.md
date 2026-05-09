# ADR-0006: VocabStore Gold Star Formula and Cross-System Write Contract

## Status
Accepted (2026-05-09)

## Date
2026-05-08

## Engine Compatibility

| Field | Value |
|-------|-------|
| **Engine** | Godot 4.6 |
| **Domain** | Core (Scripting / Data Management) |
| **Knowledge Risk** | LOW — GDScript int division behavior and Dictionary reference semantics are stable across all 4.x versions |
| **References Consulted** | `docs/engine-reference/godot/VERSION.md` |
| **Post-Cutoff APIs Used** | None — GDScript arithmetic and Dictionary operations are stable |
| **Verification Required** | GUT test: verify `float(correct) / float(seen)` produces correct ratio (not truncated int division); verify cross-system writes to shared Dictionary don't corrupt |

## ADR Dependencies

| Field | Value |
|-------|-------|
| **Depends On** | ADR-0004 (SaveSystem — flush used for persistence); ADR-0005 (ProfileManager switch — session counter reset uses profile_switch_requested) |
| **Enables** | TagDispatcher (calls record_event); ParentVocabMap (reads gold star counts); PostcardGenerator (reads gold star counts); ChoiceUI (reads vocab data) |
| **Blocks** | VocabStore implementation; TagDispatcher implementation; any system reading vocab_progress |
| **Ordering Note** | ADR-0004 and ADR-0005 must be Accepted before this ADR. |

## Context

### Problem Statement

VocabStore manages vocabulary learning progress for 5 words across 3 save profiles. Two architectural decisions must be formalized:

1. **Gold star formula**: The ratio `correct/seen >= 0.8` must be computed correctly in GDScript, which performs integer division by default (`4/5 = 0`, not `0.8`). A float cast is mandatory but easy to forget.

2. **Cross-system write contracts**: VocabStore and VoiceRecorder both mutate fields within the same `vocab_progress` Dictionary (obtained via `ProfileManager.get_section()`). Without explicit ownership rules, one system could accidentally overwrite another's fields.

### Constraints
- GDScript integer division: `int / int` returns `int` (truncated)
- `get_section()` returns a direct reference (not copy) — all mutations are visible to all holders
- Profile switch clears the reference atomically (ADR-0005)
- 5 vocabulary words × 3 profiles = 15 vocab entries to manage
- Gold star threshold is configurable (`STAR_RATIO_THRESHOLD = 0.8`, range 0.6–0.9)

### Requirements
- Gold star formula must be mathematically correct (no int truncation)
- `is_learned` must be monotonically non-decreasing (once true, never reverts)
- `first_star_at` must be write-once (null → timestamp, never overwritten)
- `NOT_CORRECT` events must never connect to scoring, parent view, or negative feedback (Anti-Pillar P2)
- VocabStore must own `gold_star_count`, `is_learned`, `first_star_at`, `seen`, `correct`
- VoiceRecorder must own `recording_paths` (not VocabStore)
- Session counters must not persist to disk

## Decision

Adopt **Float Cast Formula + Explicit Field Ownership Partition** for vocab_progress management.

### Gold Star Formula

```gdscript
# MANDATORY: float cast before division
# GDScript: int / int = int (truncated), e.g. 4/5 = 0
#           float / int = float, e.g. float(4)/float(5) = 0.8

func _check_gold_star(word_id: String) -> void:
    var correct: int = _session_counters[word_id]["correct"]
    var seen: int = _session_counters[word_id]["seen"]
    if seen <= 0:
        return  # division by zero guard
    var ratio: float = float(correct) / float(seen)  # ⚠️ float cast mandatory
    if ratio >= STAR_RATIO_THRESHOLD:
        _award_star(word_id)

func _award_star(word_id: String) -> void:
    var data: Dictionary = _vocab_data[word_id]
    data["gold_star_count"] += 1
    if data["first_star_at"] == null:
        data["first_star_at"] = Time.get_datetime_string_from_system(true) + "Z"
    _session_counters[word_id]["star_awarded"] = true  # one star per session per word
    if not data["is_learned"] and data["gold_star_count"] >= IS_LEARNED_THRESHOLD:
        data["is_learned"] = true
        word_learned.emit(word_id)
    gold_star_awarded.emit(word_id, data["gold_star_count"])
    ProfileManager.flush()  # persist immediately; failure = push_error only
```

### Field Ownership Partition

```
vocab_progress[word_id] = {
    ┌─────────────────────────────────┐
    │  VocabStore owns:               │
    │    gold_star_count  (int)       │
    │    is_learned       (bool)      │
    │    first_star_at    (String|null)│
    │    seen             (int)       │  ← session only, not persisted
    │    correct          (int)       │  ← session only, not persisted
    ├─────────────────────────────────┤
    │  VoiceRecorder owns:            │
    │    recording_paths  (Array)     │
    ├─────────────────────────────────┤
    │  SaveSystem owns (metadata):    │
    │    schema_version   (int)       │
    │    last_saved_timestamp (String)│
    └─────────────────────────────────┘
```

**Write rules:**
- VocabStore MUST NOT write to `recording_paths`
- VoiceRecorder MUST NOT write to `gold_star_count`, `is_learned`, `first_star_at`
- Both systems write to the SAME Dictionary reference (from `get_section()`)
- Both systems are safe to write concurrently (GDScript single-threaded)
- ProfileManager.flush() is called by whichever system writes last

### Anti-Pillar P2 Enforcement

```gdscript
# NOT_CORRECT events: data goes NOWHERE
# Do NOT increment any counter
# Do NOT emit any signal to presentation layer
# Do NOT update parent view
# The event is a no-op in MVP (reserved for future telemetry)

func _on_not_correct(word_id: String) -> void:
    # Intentionally empty — Anti-Pillar P2
    # NOT_CORRECT must never connect to scoring, parent view, or negative feedback
    pass
```

### Key Interfaces

```gdscript
class_name VocabStore extends Node

enum EventType { PRESENTED, SELECTED_CORRECT, NOT_CORRECT }

signal gold_star_awarded(word_id: String, new_star_count: int)
signal word_learned(word_id: String)

func record_event(word_id: String, event_type: EventType) -> void:
    # Facade: routes to correct_event() / not_correct_event() / _on_presented()
    # Called by TagDispatcher (both AutoLoad, direct call)

func correct_event(word_id: String) -> void:
    # Increments session correct; checks gold star formula

func not_correct_event(word_id: String) -> void:
    # NO-OP — Anti-Pillar P2

func get_gold_star_count(word_id: String) -> int:

func get_session_count(word_id: String, field: String) -> int:
    # field: "correct" or "seen"

func is_learned(word_id: String) -> bool:
    # correct_stars >= IS_LEARNED_THRESHOLD (3)

func begin_chapter_session() -> void:
    # Resets session counters

func end_chapter_session() -> void:
    # ProfileManager.flush() + reset counters

func reset_session() -> void:
    # Sync handler for profile_switch_requested
```

### Architecture Diagram

```
TagDispatcher.record_event(word_id, SELECTED_CORRECT)
       │
       ▼
VocabStore._check_gold_star(word_id)
       │
       ├─ ratio = float(correct) / float(seen)
       ├─ ratio >= 0.8?
       │     ├─ NO → return
       │     └─ YES → _award_star()
       │              ├─ gold_star_count += 1
       │              ├─ first_star_at = UTC (if null)
       │              ├─ is_learned = true (if threshold met)
       │              ├─ emit gold_star_awarded
       │              └─ ProfileManager.flush()
       │
       ▼
  _vocab_data[word_id] (direct reference to ProfileManager._active_data.vocab_progress)
       │
       ▼
  SaveSystem.flush_profile() → user://save_profile_{index}.json
```

## Alternatives Considered

### Alternative B: Unified Counter + Signal Notification

- **Description**: VocabStore computes gold stars but emits signals for ProfileManager to perform the actual Dictionary writes.
- **Pros**: Single write authority (ProfileManager); no direct reference mutation
- **Cons**: Adds signal indirection for a hot path (every word selection); ProfileManager must understand vocab semantics; flush must be coordinated between two systems
- **Rejection Reason**: The direct reference pattern is already established by ProfileManager.get_section() and is simpler for a single-threaded game. Signal indirection adds complexity without solving a real concurrency problem.

### Alternative C: Virtual Calculation (No Persistent Intermediate State)

- **Description**: Gold stars are computed on-the-fly from `seen` and `correct` counts stored in session counters. No `gold_star_count` field exists — it's derived.
- **Pros**: No data duplication; impossible for gold_star_count to drift from actual ratio
- **Cons**: Requires recalculating on every read (ParentVocabMap, PostcardGenerator, MainMenu); session counters must persist (but they currently don't); is_learned threshold becomes harder to evaluate
- **Rejection Reason**: Gold star count must be visible in the parent vocabulary map and on the main menu — computing it on every read is wasteful. Persistent gold_star_count with immediate flush is simpler and faster.

## Consequences

### Positive
- **Mathematical correctness**: `float()` cast eliminates int division bug — ratio is always accurate
- **Data integrity**: Explicit field ownership prevents cross-system corruption
- **Anti-Pillar P2 enforcement**: NOT_CORRECT is a documented no-op, not an accidental data path
- **Immediate persistence**: Gold star awarded → flush → data on disk immediately (survives OS kill)
- **Session isolation**: seen/correct counters reset per session, never persist — prevents cross-session contamination

### Negative
- **Float precision**: `float(4)/float(5) = 0.8` is exact, but `float(3)/float(4) = 0.75` — no precision issue for this use case. However, `float(1)/float(3) = 0.333...` — threshold comparison with `>=` handles this correctly.
- **Direct reference mutation**: Both VocabStore and VoiceRecorder mutate the same Dictionary. GDScript single-threaded execution prevents race conditions, but a logic bug in either system could corrupt the shared Dictionary.
- **Immediate flush per star**: Each gold star award triggers a flush. For 5 words × 3 sessions = up to 15 flushes per play session. Flush is <2ms (ADR-0004), so total overhead is <30ms — acceptable.

### Risks

| Risk | Severity | Mitigation |
|------|----------|------------|
| **R1: Developer forgets `float()` cast** | HIGH | CI lint rule or code review. The formula `float(correct) / float(seen)` must appear in every gold star check. GUT test AC validates ratio correctness. |
| **R2: VoiceRecorder writes to VocabStore fields** | MEDIUM | ADR field ownership partition documents the boundary. Code review catches violations. VoiceRecorder GDD explicitly declares `recording_paths` ownership. |
| **R3: is_learned reverts on profile switch** | LOW | ADR-0005 ensures profile switch clears `_vocab_data` reference. New reference loaded from disk includes the persisted `is_learned = true`. Monotonicity is enforced by code: `if not data["is_learned"]` guard. |
| **R4: NOT_CORRECT accidentally connected to UI** | MEDIUM | GDD Anti-Pillar P2 rule + code review. TagDispatcher must not propagate NOT_CORRECT to presentation layer. VocabStore handler is intentionally empty. |

## GDD Requirements Addressed

| GDD System | Requirement | How This ADR Addresses It |
|------------|-------------|--------------------------|
| vocab-store.md | Rule 4: `float(correct) / float(seen) >= STAR_RATIO_THRESHOLD` | Float cast formula documented; int division bug explained |
| vocab-store.md | Rule 4: `is_learned` monotonicity | Guard: `if not data["is_learned"]` before setting true |
| vocab-store.md | Rule 4: `first_star_at` write-once | Guard: `if data["first_star_at"] == null` before setting |
| vocab-store.md | Rule 4: `NOT_CORRECT` no-op (Anti-Pillar P2) | Documented as intentional empty handler |
| vocab-store.md | Rule 5: `_session_counters` reset on profile_switch_requested | ADR-0005 sync guarantee ensures this runs before flush |
| vocab-store.md | Rule 3.1: `end_chapter_session()` flush + reset | Formalized in Key Interfaces |
| vocab-store.md | TR-vocab-store-002: Gold star formula float cast | Core of this ADR |
| vocab-store.md | TR-vocab-store-003: `is_learned` monotonicity | Documented in Decision section |
| vocab-store.md | TR-vocab-store-004: `first_star_at` write-once | Documented in Decision section |
| vocab-store.md | TR-vocab-store-006: NOT_CORRECT Anti-P2 enforcement | Explicit no-op handler documented |
| vocab-store.md | TR-vocab-store-007: VOCAB_WORD_IDS_CH1 sync with SaveSystem | Referenced as Open Question (cross-system constant) |
| parent-vocab-map.md | Reads `gold_star_count` via `get_gold_star_count()` | Interface defined in Key Interfaces |
| tag-dispatcher.md | Calls `record_event(word_id, EventType)` | Interface defined in Key Interfaces |

## Performance Implications
- **CPU**: Float division: <0.001ms. Dictionary mutation: <0.001ms. Total per-word evaluation: <0.01ms.
- **Memory**: 5 session counters × ~24 bytes = ~120 bytes per session. Negligible.
- **Load Time**: N/A — no disk I/O in formula calculation.
- **Network**: N/A.

## Migration Plan

This ADR defines the initial architecture. No migration from prior code is needed.

If future vocabulary sets (Chapter 2+) add more words, `VOCAB_WORD_IDS_CH1` constant must be extended or replaced with a dynamic registry. This is noted as a future ADR concern, not part of this decision.

## Validation Criteria
1. GUT test: `float(4)/float(5) >= 0.8` returns `true` (gold star awarded for 4/5 correct)
2. GUT test: `float(3)/float(5) >= 0.8` returns `false` (no star for 3/5 correct)
3. GUT test: `is_learned` monotonicity — setting true twice doesn't revert
4. GUT test: `first_star_at` write-once — second star doesn't overwrite timestamp
5. GUT test: `NOT_CORRECT` handler is no-op — no state changes, no signals emitted
6. GUT test: `profile_switch_requested` clears `_vocab_data` and `_session_counters`
7. Integration test: TagDispatcher → VocabStore → ProfileManager.flush() → SaveSystem → disk

## Related Decisions
- ADR-0004: SaveSystem Atomic Write (flush used for gold star persistence)
- ADR-0005: ProfileManager Switch Protocol (session counter reset depends on sync guarantee)
- design/gdd/vocab-store.md — VocabStore GDD (this ADR formalizes its Core Rules 3–5)
- design/gdd/tag-dispatcher.md — TagDispatcher GDD (calls record_event)
- design/gdd/parent-vocab-map.md — ParentVocabMap GDD (reads gold_star_count)
- design/gdd/postcard-generator.md — PostcardGenerator GDD (reads gold_star_count)
- design/game-concept.md — STAR_RATIO_THRESHOLD tuning knob (0.6–0.9 range)
