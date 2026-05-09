# ADR-0023: ProfileManager Profile Lifecycle Details

## Status
Accepted (2026-05-09)

## Date
2026-05-09

## Engine Compatibility

| Field | Value |
|-------|-------|
| **Engine** | Godot 4.6 |
| **Domain** | Core / Data Management |
| **Knowledge Risk** | LOW — ProfileManager uses standard GDScript Dictionary operations and signal dispatch |
| **References Consulted** | `docs/engine-reference/godot/VERSION.md` |
| **Post-Cutoff APIs Used** | None |
| **Verification Required** | GUT test: create_profile, delete_profile, profile_exists edge cases |

## ADR Dependencies

| Field | Value |
|-------|-------|
| **Depends On** | ADR-0004 (SaveSystem — flush_profile, load_profile); ADR-0005 (ProfileManager Switch Protocol) |
| **Enables** | NameInputScreen (create_profile caller) |
| **Blocks** | ProfileManager implementation details |
| **Ordering Note** | ADR-0004 and ADR-0005 must be Accepted. |

## Context

### Problem Statement

ADR-0005 covers the profile switch protocol, but several ProfileManager lifecycle operations lack formal documentation: create_profile() default structure, delete_profile() sequence, profile_exists() delegation, NAME_MAX_LENGTH constant, and parent_map_hint_dismissed field. These are implementation details that need to be formally specified to prevent inconsistencies across callers.

### Requirements

- create_profile() creates v2 default structure with all 5 vocab keys
- delete_profile() active profile: 5-step sequence (signal → clear memory → delete on disk → emit cleared → return)
- profile_exists() delegates to SaveSystem (no local cache)
- NAME_MAX_LENGTH = 20 (shared with NameInputScreen)
- parent_map_hint_dismissed: bool field in profile section

## Decision

### create_profile() Default Structure

```gdscript
func create_profile(index: int, name: String, avatar_id: String) -> bool:
    var data := {
        "schema_version": CURRENT_SCHEMA_VERSION,
        "profile": {
            "name": name,
            "avatar_id": avatar_id,
            "times_played": 0,
            "parent_map_hint_dismissed": false
        },
        "vocab_progress": {},
        "story_progress": {
            "completed_chapters": [],
            "last_played_chapter": "",
            "last_played_at": ""
        }
    }
    for word_id in VOCAB_WORD_IDS_CH1:
        data["vocab_progress"][word_id] = {
            "gold_star_count": 0,
            "is_learned": false,
            "first_star_at": null,
            "recording_paths": []
        }
    return SaveSystem.flush_profile(index, data)
```

### delete_profile() Sequence

```
a. emit profile_switch_requested("user_deleted") — sync handlers
b. _active_data = {} (clear memory)
c. SaveSystem.delete_profile(index) — remove file from disk
d. emit active_profile_cleared("user_deleted")
e. return
```

### profile_exists() Delegation

```gdscript
func profile_exists(index: int) -> bool:
    return SaveSystem.profile_exists(index)  # no local cache
```

### Constants

```gdscript
const NAME_MAX_LENGTH: int = 20  # shared with NameInputScreen
```

## GDD Requirements Addressed

| GDD System | Requirement | How This ADR Addresses It |
|------------|-------------|--------------------------|
| profile-manager.md TR-profile-manager-011 | delete_profile() 5-step | Documented sequence a→b→c→d→e |
| profile-manager.md TR-profile-manager-012 | create_profile() v2 default | Full default Dictionary structure |
| profile-manager.md TR-profile-manager-013 | profile_exists() delegates | Delegates to SaveSystem, no cache |
| profile-manager.md TR-profile-manager-014 | NAME_MAX_LENGTH = 20 | Constant definition |
| profile-manager.md TR-profile-manager-015 | parent_map_hint_dismissed | Field in profile section, default false |

## Consequences

- **Complete lifecycle coverage**: create, delete, exists all formally specified
- **Single source of truth**: NAME_MAX_LENGTH defined once in ProfileManager
- **OQ-1 resolved**: create_profile caller is NameInputScreen, not MainMenu

## Related Decisions

- ADR-0004: SaveSystem Atomic Write (flush_profile, load_profile)
- ADR-0005: ProfileManager Switch Protocol (switch_to_profile, signals)
- ADR-0017: NameInputScreen (sole caller of create_profile)
- design/gdd/profile-manager.md — ProfileManager GDD
