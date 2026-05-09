# ADR-0008: AudioManager BGM Management Strategy

## Status
Accepted (2026-05-09)

## Date
2026-05-08

## Engine Compatibility

| Field | Value |
|-------|-------|
| **Engine** | Godot 4.6 |
| **Domain** | Audio |
| **Knowledge Risk** | LOW — No audio-specific breaking changes in 4.4–4.6; AudioStreamPlayer API stable |
| **References Consulted** | `docs/engine-reference/godot/VERSION.md`; `docs/engine-reference/godot/modules/audio.md` |
| **Post-Cutoff APIs Used** | None — AudioStreamPlayer, AudioServer, Tween are all stable |
| **Verification Required** | BGM persists across scene transitions (HatchScene → NameInputScreen → MainMenu → GameScene); fade-in/out timing correct |

## ADR Dependencies

| Field | Value |
|-------|-------|
| **Depends On** | ADR-0007 (AutoLoad loading order — AudioManager position in boot chain) |
| **Enables** | NameInputScreen BGM introduction; MainMenu BGM continuation; GameScene BGM |
| **Blocks** | Any scene that plays BGM |
| **Ordering Note** | ADR-0007 must be Accepted first. AudioManager is a NEW system not in systems-index.md — must be added. |

## Context

### Problem Statement

BGM must play continuously across scene transitions: HatchScene (no BGM) → NameInputScreen (BGM introduced with 600ms fade-in) → MainMenu (BGM continues) → GameScene (BGM continues or crossfades). In Godot, `AudioStreamPlayer` is a `Node` — when its parent scene is freed (during `change_scene_to_file()`), the player is destroyed and BGM stops.

The architecture needs a BGM holder that survives scene transitions. This is distinct from TtsBridge (which handles TTS and SFX with its own AudioStreamPlayer) — BGM has different lifecycle, volume, and crossfade requirements.

### Constraints
- Godot AudioStreamPlayer is scene-bound — destroyed with parent node
- HatchScene has NO BGM (TR-hatch-scene-014: "No BGM throughout hatch")
- NameInputScreen introduces BGM with 600ms fade-in (TR-name-input-009)
- BGM loop: ≥30s to avoid repetition perception (TR-name-input-009)
- BGM must not conflict with TtsBridge audio (separate Audio Bus)
- 4-week MVP: simple crossfade, not complex audio mixing

### Requirements
- BGM persists across all scene transitions after NameInputScreen
- Fade-in: 600ms when BGM first introduced
- Fade-out: 600ms on game exit or HatchScene (no BGM)
- Volume: configurable per-scene, default -12 dB
- BGM and TTS/SFX must use separate Audio Buses
- AudioManager is an AutoLoad singleton (lives outside scene tree)

## Decision

Adopt **AudioManager AutoLoad Singleton with Dedicated BGM AudioStreamPlayer** for cross-scene BGM management.

### Architecture

```
AutoLoad: AudioManager (lives outside scene tree — survives scene changes)
    │
    ├─ AudioStreamPlayer "BGMPlayer" (child node)
    │     ├─ bus = "BGM" (dedicated Audio Bus)
    │     └─ stream = current BGM AudioStream
    │
    └─ Signals:
          bgm_started(bgm_name: String)
          bgm_stopped()

Scene tree:
    HatchScene → (no BGM call)
    NameInputScreen → AudioManager.play_bgm("bgm_main") with 600ms fade
    MainMenu → BGM continues (no re-trigger)
    GameScene → BGM continues or crossfade to battle theme
```

### Audio Bus Layout

```
Master
  ├── BGM      (volume: -12 dB default)
  │     └─ AudioManager.BGMPlayer
  ├── SFX      (volume: 0 dB)
  │     └─ (future: sound effects)
  ├── Voice    (volume: -12 dB)
  │     └─ TtsBridge.AudioStreamPlayer
  └── TTS_Auto (volume: 0 dB)
        └─ (future: system TTS bus, if needed)
```

### Key Interfaces

```gdscript
class_name AudioManager extends Node

signal bgm_started(bgm_name: String)
signal bgm_stopped()

func play_bgm(bgm_name: String, fade_in_sec: float = 0.6) -> void:
    # Loads audio from res://assets/audio/bgm/{bgm_name}.ogg
    # Fades in over fade_in_sec seconds
    # If same BGM already playing → no-op (no restart)
    # If different BGM → sequential fade (old fades out, swap stream, new fades in)
    # NOTE: true simultaneous crossfade requires 2 AudioStreamPlayers — defer to v1.1

func stop_bgm(fade_out_sec: float = 0.6) -> void:
    # Fades out over fade_out_sec seconds, then stops

func set_bgm_volume(db: float) -> void:
    # Sets BGM bus volume

func is_bgm_playing() -> bool:
```

### Scene Integration Pattern

```gdscript
# NameInputScreen._ready() — BGM introduced here
func _ready() -> void:
    if not AudioManager.is_bgm_playing():
        AudioManager.play_bgm("bgm_main", 0.6)  # 600ms fade-in

# HatchScene — NO BGM (Anti-Pillar: hatch is silent ceremony)
# No AudioManager call needed.

# GameScene — BGM continues from MainMenu
# No AudioManager call needed (BGM persists via AutoLoad).
```

## Alternatives Considered

### Alternative B: BGM on SceneTree Root

- **Description**: Attach BGM AudioStreamPlayer to the root `/root` node via `get_tree().root.add_child()`.
- **Pros**: No new AutoLoad needed; root node survives scene changes
- **Cons**: Root node is engine-managed; adding children to it is fragile; no clean API for volume/crossfade; harder to test in isolation
- **Rejection Reason**: AutoLoad is Godot's intended pattern for cross-scene singletons. Adding nodes to the root is an engine hack, not a design pattern.

### Alternative C: Per-Scene BGM Players

- **Description**: Each scene that plays BGM instantiates its own AudioStreamPlayer and manages fade in/out.
- **Pros**: Fully self-contained; no shared state
- **Cons**: BGM restarts on every scene change (jarring); no crossfade between scenes; complex fade coordination between scene exit/enter; violates P3 "声音是成长的日记" (BGM is part of the child's emotional journey)
- **Rejection Reason**: Per-scene BGM creates audible gaps during transitions. The child's emotional journey requires continuous BGM. Cross-scene persistence is a hard requirement.

## Consequences

### Positive
- **Continuous BGM**: AutoLoad survives all scene transitions — BGM never interrupts
- **Clean separation**: BGM (AudioManager) vs TTS/SFX (TtsBridge) — different lifecycles, different buses
- **Simple API**: `play_bgm()` / `stop_bgm()` — one call per scene transition
- **Crossfade support**: Can crossfade between BGM tracks for future chapter themes

### Negative
- **New AutoLoad (9th)**: AudioManager loads AFTER TtsBridge (④) but BEFORE StoryManager (⑥) — no dependency on game systems. Total AutoLoad count is 9.
- **Audio Bus setup**: Requires manual Audio Bus layout configuration in Godot Editor (not code-driven)
- **BGM asset management**: BGM files must be preloaded or loaded on first play; loading on first play may cause a brief silence

### Risks

| Risk | Severity | Mitigation |
|------|----------|------------|
| **R1: 9th AutoLoad pushes boot time over threshold** | LOW | AudioManager._ready() is trivial (<0.1ms — just adds AudioStreamPlayer child). Boot overhead negligible. |
| **R2: BGM file not found at runtime** | LOW | `load()` returns null → push_error, no BGM plays, game continues. No crash. |
| **R3: Crossfade timing jitter on low-end device** | LOW | Tween-based crossfade is frame-rate independent. Use `create_tween()` with `set_parallel(true)`. |

## GDD Requirements Addressed

| GDD System | Requirement | How This ADR Addresses It |
|------------|-------------|--------------------------|
| main-menu.md | TR-main-menu-011: BGM first introduced at NameInputScreen; AudioManager AutoLoad carries BGM across scene transitions | Core of this ADR: AudioManager AutoLoad design |
| name-input-screen.md | TR-name-input-009: BGM introduced here with 600ms fade-in; >=30s loop | `play_bgm("bgm_main", 0.6)` call pattern |
| hatch-scene.md | TR-hatch-scene-014: No BGM throughout hatch | HatchScene makes no AudioManager call |
| architecture.md | Open Question #6: AudioManager — is it a separate AutoLoad or part of an existing module? | Answered: separate AutoLoad singleton |
| architecture.md | LP-CONCERN-1: AutoLoad count | Addressed: AudioManager._ready() is trivial |

## Performance Implications
- **CPU**: Tween-based fade: <0.1ms/frame. Audio decoding (OGG Vorbis): handled by Godot audio thread, no main thread impact.
- **Memory**: One AudioStreamPlayer + one AudioStream buffer: ~200KB for a 30s OGG loop.
- **Load Time**: BGM file load on first play: <50ms (preloaded via `preload()` or loaded via `load()`).
- **Network**: N/A — all audio local.

## Migration Plan

This ADR creates a new system (AudioManager) not previously in systems-index.md.

**systems-index.md update required:**
- Add AudioManager to the systems enumeration (Category: Core, Priority: MVP)
- Add to the dependency map (Foundation layer, no game deps)
- Update Recommended Design Order (after TtsBridge, before StoryManager)

**Project Settings update required:**
- Add AudioManager to AutoLoad list at position ⑤ (after TtsBridge, before StoryManager)
- Create "BGM" Audio Bus in Godot Editor

## Validation Criteria
1. BGM persists across HatchScene → NameInputScreen → MainMenu → GameScene transitions
2. BGM not playing during HatchScene (TR-hatch-scene-014)
3. BGM fades in at NameInputScreen with 600ms duration (TR-name-input-009)
4. BGM loops for >=30s without audible repetition (TR-name-input-009)
5. BGM and TTS use separate Audio Buses (no volume interference)
6. AudioManager._ready() completes in <1ms

## Related Decisions
- ADR-0007: AutoLoad Initialization Order (AudioManager position in boot chain)
- ADR-0002: TtsProvider Interface (TtsBridge uses separate Audio Bus for TTS)
- design/gdd/main-menu.md — MainMenu GDD (TR-main-menu-011 references AudioManager)
- design/gdd/name-input-screen.md — NameInputScreen GDD (TR-name-input-009 BGM introduction)
- design/gdd/hatch-scene.md — HatchScene GDD (TR-hatch-scene-014 no BGM)
- design/gdd/systems-index.md — Must be updated to include AudioManager
