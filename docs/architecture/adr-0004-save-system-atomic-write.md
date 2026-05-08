# ADR-0004: SaveSystem Atomic Write Protocol and Schema Migration

## Status
Proposed

## Date
2026-05-08

## Engine Compatibility

| Field | Value |
|-------|-------|
| **Engine** | Godot 4.6 |
| **Domain** | Core (File I/O) |
| **Knowledge Risk** | MEDIUM — `FileAccess.store_*` returns `bool` since 4.4 (was void); `DirAccess.rename()` returns `Error` enum with `OK = 0` (falsy); Android Scoped Storage affects `DirAccess` behavior on API 29+ |
| **References Consulted** | `docs/engine-reference/godot/VERSION.md`; `docs/engine-reference/godot/breaking-changes.md` (4.3→4.4 section); `docs/engine-reference/godot/deprecated-apis.md` |
| **Post-Cutoff APIs Used** | `FileAccess.store_string()` return type change (4.4); `DirAccess.rename()` return value semantics (4.4); `Time.get_datetime_string_from_system(true)` for UTC timestamps |
| **Verification Required** | Week 1 real device: (1) `DirAccess.rename()` atomic-over-existing on target Android API 24–33; (2) `.tmp` recovery scan correctness; (3) `store_string()` bool return value check |

## ADR Dependencies

| Field | Value |
|-------|-------|
| **Depends On** | None (Foundation layer — first ADR) |
| **Enables** | ADR-0005 (ProfileManager switch protocol uses flush/load); all downstream systems that persist state |
| **Blocks** | ProfileManager implementation; VocabStore end_chapter_session flush; VoiceRecorder recording persistence |
| **Ordering Note** | Must be Accepted before any Foundation layer coding begins. Week 1 real device verification is the acceptance trigger. |

## Context

### Problem Statement

SaveSystem is the sole persistence I/O layer for all game state. On Android, apps can be killed by the OS at any time (low memory, user swipe, system update). If a save operation is interrupted mid-write, the player's vocabulary progress, recording paths, and story state could be lost. Additionally, the save schema will evolve across versions (v1 → v2 during development, future v3+), and old save files must be automatically migrated without data loss.

This ADR formalizes two foundational decisions that all other systems depend on:
1. **Atomic write protocol**: How to write data to disk safely despite potential OS-level interruption
2. **Schema migration pipeline**: How to evolve the save format across versions without losing existing player data

### Constraints
- Engine: Godot 4.6, GDScript only
- Platform: Android API 24+, multiple OEM filesystem behaviors
- 256 MB memory ceiling; save files <1 KB each
- Single-threaded execution (no concurrent write conflicts)
- 4-week MVP; this ADR blocks all Foundation layer implementation

### Requirements
- Write must be atomic — either fully committed or fully absent (no partial writes)
- Crash recovery must be automatic on next App launch
- Schema migration must be idempotent (safe to re-run)
- Future schema versions must not overwrite newer-format files (downgrade protection)
- `store_string()` return value must be checked (Godot 4.4+ breaking change)
- `DirAccess.rename()` return value must use `!= OK` comparison (Error.OK = 0 is falsy)

## Decision

Adopt **Pattern A: .tmp + DirAccess.rename() atomic replacement** with automatic `.tmp` recovery on startup.

### Write Sequence (flush_profile)

```
flush_profile(index, data):
  ① deep_copy(data)
  ② data.schema_version = CURRENT_SCHEMA_VERSION
  ③ data.last_saved_timestamp = Time.get_datetime_string_from_system(true) + "Z"
  ④ json = JSON.stringify(data, SAVE_INDENT)
  ⑤ tmp_path = "user://save_profile_{index}.tmp"
  ⑥ final_path = "user://save_profile_{index}.json"
  ⑦ fh = FileAccess.open(tmp_path, WRITE)
     → if null: cleanup .tmp, push_error, return false
  ⑧ ok = fh.store_string(json)          # ⚠️ returns bool (4.4+)
     → if not ok: cleanup .tmp, push_error, return false
  ⑨ fh.close()
  ⑩ dir = DirAccess.open("user://")
     → if null: cleanup .tmp, push_error, return false
  ⑪ err = dir.rename(tmp_path, final_path)
     → if err != OK: cleanup .tmp, push_error, return false   # ⚠️ Error.OK = 0
  ⑫ emit profile_saved(index)
  ⑬ return true
```

### Recovery Sequence (_ready)

```
_ready():
  for index in MAX_SAVE_PROFILES:
    tmp = "user://save_profile_{index}.tmp"
    json = "user://save_profile_{index}.json"
    if FileAccess.file_exists(tmp):
      if not FileAccess.file_exists(json):
        # .tmp is the only copy — recover it
        dir.rename(tmp, json)
      else:
        # Both exist — .tmp is stale from successful prior rename
        dir.remove(tmp)
```

### Schema Migration Pipeline (load_profile)

```
load_profile(index):
  data = _read_json_file(index)          # returns {dict, error}
  if data.error != NONE: return {}, data.error
  if data.dict.schema_version > CURRENT: return {}, UNSUPPORTED  # downgrade guard
  if data.dict.schema_version < CURRENT:
    migrated = _migrate_to_v2(data.dict)  # in-memory, additive only
    flush_profile(index, migrated)         # persist (failure = push_error only)
    return migrated
  return data.dict
```

**Migration rules:**
- Additive only: never delete existing fields
- Idempotent: running twice produces identical output
- `first_star_at`: fill `null` if missing; never overwrite existing value
- `recording_paths`: fill `[]` if missing; if v1 `recording_path` (singular) exists, wrap as `[recording_path]`
- `parent_map_hint_dismissed`: fill `false` if missing; never overwrite existing value

### Architecture Diagram

```
ProfileManager.flush()
       │
       ▼
SaveSystem.flush_profile(index, data)
       │
  ①   ├─ deep_copy + stamp schema_version + timestamp
  ②   ├─ FileAccess.open(.tmp, WRITE) → store_string(json) → close
  ③   ├─ DirAccess.open("user://") → rename(.tmp → .json)
  ④   └─ return true/false
       │
       ▼
  user://save_profile_{index}.json  (atomic: .tmp → rename)
  user://save_profile_{index}.tmp   (deleted after successful rename)

Recovery on _ready():
  .tmp exists + .json missing  → rename .tmp → .json (data recovery)
  .tmp exists + .json exists   → delete .tmp (stale cleanup)
```

### Key Interfaces

```gdscript
class_name SaveSystem extends Node

enum LoadError {
    NONE = 0,
    FILE_NOT_FOUND = 1,
    FILE_READ_ERROR = 2,
    JSON_PARSE_ERROR = 3,
    SCHEMA_VERSION_UNSUPPORTED = 4,
    INVALID_INDEX = 5
}

func load_profile(index: int) -> Dictionary:
    # Returns clean Dictionary or {} on error
    # Sets _last_load_error for caller inspection

func flush_profile(index: int, data: Dictionary) -> bool:
    # Atomic write: .tmp → rename to .json
    # Returns true on success

func delete_profile(index: int) -> bool:
    # Idempotent: file not found returns true

func profile_exists(index: int) -> bool:

func get_save_path(index: int) -> String:
    # Pure function

func get_last_load_error() -> LoadError:
```

## Alternatives Considered

### Alternative B: Direct Write + Checksum Verification

- **Description**: Write directly to `.json`, then re-read and verify a CRC32 checksum stored in a sidecar file.
- **Pros**: Simpler code; no `.tmp` file management; single file per profile
- **Cons**: If App is killed during write, `.json` contains partial data and is unrecoverable. Sidecar checksum file adds a second write that can also be interrupted. On Android ext4/F2FS, direct overwrite of an existing file is NOT atomic — a crash during write leaves corrupted data.
- **Rejection Reason**: Non-atomic overwrite is unacceptable for a child-facing app where data loss means "my dinosaur friend forgot me." The `.tmp` + rename pattern guarantees atomicity at the filesystem level.

### Alternative C: Append-Only Journal (WAL-style)

- **Description**: Append each change as a log entry to a journal file. On load, replay the journal to reconstruct current state. Periodically compact the journal into a snapshot.
- **Pros**: Extremely crash-safe (only the last append can be lost); natural audit trail
- **Cons**: Load time grows with journal length; compaction adds complexity; Godot's `FileAccess` has no atomic append guarantee on Android; journal replay adds ~50ms to boot time for 5 vocabulary words
- **Rejection Reason**: Massive over-engineering for 5 vocabulary words and <1 KB save files. The simplicity of `.tmp` + rename is appropriate for this data scale. Journaling is warranted for databases with thousands of concurrent writes, not a children's game with 3 save slots updated once per session.

### Alternative D: Godot ResourceSaver

- **Description**: Use Godot's built-in `ResourceSaver.save()` to persist game state as `.tres` or `.res` files.
- **Pros**: Native Godot API; handles serialization automatically
- **Cons**: `ResourceSaver` is not atomic (writes directly to target file); `.tres` format is text-based and human-readable (potential cheat vector); format changes between Godot versions could break save compatibility; no schema versioning support
- **Rejection Reason**: Non-atomic writes; format instability across engine versions; no built-in migration support. JSON + manual schema versioning gives full control.

## Consequences

### Positive
- **Atomicity guarantee**: POSIX `rename()` on ext4/F2FS (Android filesystems) is atomic — the file is never in a partially-written state
- **Automatic recovery**: `.tmp` recovery on `_ready()` handles all crash scenarios without user intervention
- **Schema flexibility**: Additive-only migration with idempotent re-runs allows safe iterative development
- **Godot 4.4 awareness**: `store_string()` bool return and `DirAccess.rename()` `!= OK` check are documented as architectural constraints, not implementation details
- **Simple mental model**: "Write to temp, rename to final" is a well-understood pattern with decades of production use

### Negative
- **Android Scoped Storage risk**: On API 29+ devices, `DirAccess.rename()` may not be atomic across all OEMs (Open Question #3 from architecture.md). ADR-0004 does NOT guarantee atomicity on all Android API 29+ devices — it guarantees the best available behavior with Godot's GDScript API.
- **Two filesystem operations per flush**: `.tmp` write + rename is slightly slower than direct write (negligible for <1 KB files)
- **Schema version coupling**: SaveSystem must know about schema versions and migration logic, creating a maintenance burden when the schema evolves

### Risks

| Risk | Severity | Mitigation |
|------|----------|------------|
| **R1: `DirAccess.rename()` not atomic on Android API 29+** | MEDIUM | Week 1 real device test. Fallback: if rename fails, read `.tmp` back and write directly to `.json` (accepts brief non-atomic window). ADR-0004 does NOT need revision — the fallback is a runtime behavior, not an architecture change. |
| **R2: `store_string()` silently fails (disk full)** | LOW | Check `bool` return value; cleanup `.tmp`; return `false`. Caller receives `false` and can retry. Data in memory is never lost. |
| **R3: Schema migration logic has bugs** | MEDIUM | Idempotency means re-running fixes corruption. AC-6 (migration idempotency test) validates this. Migration is additive-only — no data deletion possible. |
| **R4: Future schema version increases break existing saves** | LOW | `SCHEMA_VERSION_UNSUPPORTED` guard prevents overwrite. User sees "please update App" message. |
| **R5: `.tmp` recovery 误删有效数据** | LOW | Recovery logic: `.tmp` + no `.json` → recover; `.tmp` + `.json` → delete `.tmp`. The `.tmp` is always the WRITE copy, never the READ source. |

## GDD Requirements Addressed

| GDD System | Requirement | How This ADR Addresses It |
|------------|-------------|--------------------------|
| save-system.md | Rule 2: File naming convention (`save_profile_{index}.json` + `.tmp`) | Defines exact paths and lifecycle |
| save-system.md | Rule 3: `load_profile()` execution sequence (6 steps including migration) | Formalizes the load + migrate pipeline |
| save-system.md | Rule 4: `flush_profile()` atomic write sequence (5 steps) | Core of this ADR: .tmp + rename protocol |
| save-system.md | Rule 5: v1→v2 migration (additive, idempotent) | Migration rules documented in Decision section |
| save-system.md | Rule 6: `_get_default_v2()` structure | Default dictionary structure with all v2 fields |
| save-system.md | E1: `.tmp` recovery on `_ready()` | Recovery sequence formalized |
| save-system.md | E4: `dir.rename()` failure handling | Risk R1 documented with fallback |
| save-system.md | E5: Future schema version guard | `SCHEMA_VERSION_UNSUPPORTED` prevents overwrite |
| save-system.md | E10: Migration flush failure | Migration is in-memory; flush failure is non-blocking |
| save-system.md | AC-4: .tmp exists before .json during flush | Write sequence guarantees this order |
| save-system.md | AC-5: v1 auto-migration | `_migrate_to_v2()` called when `schema_version < CURRENT` |
| save-system.md | AC-6: Migration idempotency | Additive-only + no-overwrite semantics |
| save-system.md | AC-11a/b: .tmp recovery scenarios | Recovery sequence handles both cases |
| save-system.md | TR-save-system-005: `store_string()` returns bool | Documented as architectural constraint |
| save-system.md | TR-save-system-006: `DirAccess.rename()` return value | Documented: must use `!= OK` |

## Performance Implications
- **CPU**: `JSON.stringify()` for <1 KB dictionary: <0.1ms. `FileAccess.open()` + `store_string()`: <1ms. `DirAccess.rename()`: <1ms. Total flush: <2ms.
- **Memory**: Deep copy of `_active_data`: ~2 KB peak during flush. Well within budget.
- **Load Time**: `.tmp` recovery scan: 3 files checked, <1ms total. `JSON.parse_string()` for <1 KB: <0.1ms.
- **Network**: N/A — all operations local.

## Migration Plan

This ADR defines the initial architecture. No migration from prior code is needed — SaveSystem has not been implemented yet. The ADR serves as the implementation blueprint.

If a future ADR supersedes any part of this decision (e.g., R1 triggers and Android-specific fallback is formalized), the superseding ADR will reference this one.

## Validation Criteria
1. `flush_profile()` writes `.tmp` before `.json` (verified by GUT test AC-4)
2. `store_string()` return value is checked as `bool` (code review + GUT)
3. `DirAccess.rename()` return is compared with `!= OK` (code review + GUT)
4. `.tmp` recovery: `.tmp` exists + no `.json` → data recovered (GUT AC-11a)
5. `.tmp` recovery: `.tmp` exists + `.json` exists → `.tmp` deleted, `.json` unchanged (GUT AC-11b)
6. Migration idempotency: two consecutive loads produce identical output (GUT AC-6)
7. Downgrade protection: `schema_version: 99` → `SCHEMA_VERSION_UNSUPPORTED` (GUT AC-8)
8. Week 1 real device: full Chapter 1 playthrough → power kill → restart → data intact

## Related Decisions
- ADR-0001: inkgd Runtime (StoryManager writes `story_progress` via this SaveSystem)
- ADR-0003: Android Gallery Save (PostcardGenerator uses similar `FileAccess` patterns)
- design/gdd/save-system.md — SaveSystem GDD (this ADR formalizes its Core Rules 2–6)
- design/gdd/profile-manager.md — ProfileManager GDD (calls `flush_profile()` and `load_profile()`)
- design/gdd/vocab-store.md — VocabStore GDD (triggers flush via `ProfileManager.flush()`)
