# 恐龙叙事英语启蒙游戏 — Master Architecture

## Document Status

| Field | Value |
|-------|-------|
| **Version** | 2 |
| **Last Updated** | 2026-05-09 |
| **Engine** | Godot 4.6 Standard (non-Mono) |
| **Language** | GDScript (static typing) |
| **Platform** | Android API 24+ |
| **GDDs Covered** | 18/18 — SaveSystem, ProfileManager, VocabStore, AnimationHandler, TtsBridge, StoryManager, TagDispatcher, VoiceRecorder, InterruptHandler, ChoiceUI, MainMenu, HatchScene, NameInputScreen, RecordingInviteUI, VocabPrimingLoader, PostcardGenerator, ParentVocabMap, Chapter2Teaser |
| **ADRs Referenced** | ADR-0001 (inkgd Runtime), ADR-0002 (TTS Provider Interface), ADR-0003 (Android Gallery Save), ADR-0004 (SaveSystem Atomic Write), ADR-0005 (ProfileManager Switch Protocol), ADR-0006 (VocabStore Formula), ADR-0007 (AutoLoad Init Order), ADR-0008 (AudioManager BGM), ADR-0009 (VoiceRecorder Android), ADR-0010 (StoryManager Narrative Engine), ADR-0011 (AnimationHandler State Machine), ADR-0012 (InterruptHandler Platform), ADR-0013 (TagDispatcher Protocol), ADR-0014 (MainMenu Launch Sequence), ADR-0015 (RecordingInviteUI Interaction), ADR-0016 (HatchScene Ceremony), ADR-0017 (NameInputScreen), ADR-0018 (VocabPrimingLoader), ADR-0019 (Chapter2Teaser), ADR-0020 (ChoiceUI), ADR-0021 (ParentVocabMap), ADR-0022 (PostcardGenerator), ADR-0023 (ProfileManager Details), ADR-0024 (TtsBridge Details) |
| **Technical Requirements** | 176 TRs across 18 GDDs |
| **Review Mode** | full |
| **Technical Director Sign-Off** | 2026-05-08 — APPROVED |
| **Lead Programmer Feasibility** | CONCERNS ACCEPTED — 6 items addressed in API Boundaries + Open Questions |

---

## Engine Knowledge Gap Summary

| Engine | Godot 4.6 |
|--------|-----------|
| LLM Training Covers | up to ~4.3 |
| Post-Cutoff Versions | 4.4 (MEDIUM), 4.5 (HIGH), 4.6 (HIGH) |

### HIGH RISK Domains

| Domain | Key Changes | Affected Systems |
|--------|-------------|-----------------|
| **GDScript 4.5+** | `@abstract` decorator, variadic args | TtsBridge (ADR-0002) |
| **Rendering 4.6** | Glow before tonemapping, D3D12 default | HatchScene (egg glow shader) |
| **UI 4.6** | Dual-focus system (mouse/touch vs keyboard) | ChoiceUI, MainMenu, NameInputScreen, RecordingInviteUI |
| **Platform 4.6** | Android 16KB page support, edge-to-edge | All Android-specific behavior |

### MEDIUM RISK Domains

| Domain | Key Changes | Affected Systems |
|--------|-------------|-----------------|
| **Core 4.4** | `FileAccess.store_*` returns `bool` (was void) | SaveSystem (TR-save-system-005) |
| **Core 4.4** | `DirAccess.rename()` return value semantics | SaveSystem (TR-save-system-006) |
| **Animation 4.3** | `AnimationMixer` base class for AnimationPlayer | AnimationHandler |
| **Physics 4.6** | Jolt default for 3D (no impact — 2D only) | None |

### LOW RISK Domains

| Domain | Status |
|--------|--------|
| **Audio** | No breaking changes in 4.4–4.6 |
| **Input (touch)** | Core touch API stable |
| **Physics 2D** | Godot Physics 2D unchanged |

---

## System Layer Map

```
┌─────────────────────────────────────────────────────────────┐
│  PRESENTATION LAYER                                         │
│  ChoiceUI · MainMenu · HatchScene · NameInputScreen         │
│  RecordingInviteUI · VocabPrimingLoader                     │
├─────────────────────────────────────────────────────────────┤
│  FEATURE LAYER                                              │
│  StoryManager · TagDispatcher · VoiceRecorder               │
│  PostcardGenerator · ParentVocabMap · Chapter2Teaser        │
├─────────────────────────────────────────────────────────────┤
│  CORE LAYER                                                 │
│  AnimationHandler · TtsBridge · AudioManager ·              │
│  InterruptHandler                                          │
├─────────────────────────────────────────────────────────────┤
│  FOUNDATION LAYER                                           │
│  SaveSystem · ProfileManager · VocabStore                   │
├─────────────────────────────────────────────────────────────┤
│  PLATFORM LAYER                                             │
│  Godot 4.6 Engine · Android OS · DisplayServer · File I/O   │
└─────────────────────────────────────────────────────────────┘
```

### Layer Assignments

**Foundation (3 systems)** — No game-system dependencies; all upper layers depend on them.

| System | Owns | Layer Reason |
|--------|------|-------------|
| **SaveSystem** | JSON file I/O, schema v2, atomic write | 底层实现：所有持久化最终经过此模块 |
| **ProfileManager** | Active profile state, switch protocol, `_active_data` single authority | 唯一入口：档案数据的唯一权威 |
| **VocabStore** | Word counters, gold star formula, session counters | 唯一读写者：词汇数据的唯一所有者 |

**Core (4 systems)** — Engine-bridge layer; wrap Godot APIs for upper layers.

| System | Owns | Engine APIs |
|--------|------|------------|
| **AnimationHandler** ⚠️ | 14-state animation machine, play/interrupt logic | AnimationPlayer (4.3 base class change) |
| **TtsBridge** ⚠️ | TTS 3-tier fallback, AI HTTP, audio cache | DisplayServer TTS, HTTPRequest, @abstract (4.5) |
| **AudioManager** | BGM playback, cross-scene audio persistence, BGM bus management | AudioStreamPlayer, Tween (fades) |
| **InterruptHandler** ⚠️ | Background/back-button/call interrupt protocol | _notification(), PROCESS_MODE_ALWAYS, ui_cancel InputMap |

**Feature (6 systems)** — Gameplay logic; depends on Foundation + Core.

| System | Owns | Key Dependency |
|--------|------|---------------|
| **StoryManager** | Ink runtime wrapper, chapter state machine | VocabStore, ProfileManager, TtsBridge, inkgd |
| **TagDispatcher** | Ink tag parsing, event dispatch protocol | StoryManager, AnimationHandler, TtsBridge, VocabStore |
| **VoiceRecorder** ⚠️ | Recording state machine, WAV write, permission management | ProfileManager, SaveSystem, AudioStreamMicrophone |
| **PostcardGenerator** | SubViewport offscreen rendering, PNG storage | VocabStore, ProfileManager, ADR-0003 |
| **ParentVocabMap** | Vocabulary map UI + recording playback | VocabStore, VoiceRecorder, ProfileManager |
| **Chapter2Teaser** | Static silhouette + fade-out animation | None |

**Presentation (6 systems)** — Player-visible interaction screens.

| System | Owns | Signal Subscriber |
|--------|------|------------------|
| **ChoiceUI** | Vocabulary dual-option buttons, Tween fade | ← TagDispatcher (`choices_ready`) |
| **MainMenu** | T-Rex idle/recognition, profile switch, start adventure | — |
| **HatchScene** | Egg hatching ceremony (3 states) | AnimationHandler (`hatch_sequence_completed`) |
| **NameInputScreen** | Name input + avatar selection | — |
| **RecordingInviteUI** | Recording invite modal | ← TagDispatcher (`recording_invite_triggered`) |
| **VocabPrimingLoader** | Vocabulary priming animation (one-shot) | VocabStore (read-only) |

### Systems Touching HIGH/MEDIUM Risk Engine Domains

| System | Layer | Risk | Concern |
|--------|-------|------|---------|
| **AnimationHandler** | Core | MEDIUM | AnimationMixer base class (4.3); `custom_blend` param name |
| **TtsBridge** | Core | MEDIUM | `@abstract` (4.5); AudioStream API names |
| **InterruptHandler** | Core | HIGH | `NOTIFICATION_WM_GO_BACK_REQUEST` (4.6); `ui_cancel` InputMap needs manual `KEY_BACK` |
| **ChoiceUI** | Presentation | HIGH | `FOCUS_NONE` required (4.6 dual-focus) |
| **HatchScene** | Presentation | MEDIUM | Egg glow shader behavior may differ under 4.6 glow pipeline |

---

## Module Ownership

### Foundation Layer

| Module | Owns | Exposes | Consumes | Engine APIs |
|--------|------|---------|----------|-------------|
| **SaveSystem** | All `.json` file I/O; schema version; atomic write protocol | `load(index)`, `flush(index, data)`, `delete_profile(index)`, `get_save_path(index)` | None | `FileAccess`, `DirAccess`, `JSON`, `Time` |
| **ProfileManager** | `_active_data` single authority; 4-state machine | `switch_to_profile()`, `create_profile()`, `get_section()`, `begin_session()`, signals: `profile_switch_requested`, `profile_switched`, `active_profile_cleared` | SaveSystem | `Time` (UTC timestamps) |
| **VocabStore** | `_vocab_data` (ProfileManager section ref); `_session_counters` (session-only); gold star formula | `record_event(word_id, EventType)`, `get_gold_star_count()`, `get_session_count()`, `begin_chapter_session()`, `end_chapter_session()`, `reset_session()`, signals: `gold_star_awarded`, `word_learned` | ProfileManager (read section), SaveSystem (flush) | None |

### Core Layer

| Module | Owns | Exposes | Consumes | Engine APIs |
|--------|------|---------|----------|-------------|
| **AnimationHandler** ⚠️ | 14 states + 18 clips; `CLIP_MAP` / `VARIANT_MAP`; `NON_INTERRUPTIBLE_STATES` | `play(state)`, `stop_recording_listen()`, signals: `animation_completed`, `hatch_sequence_completed` | None | `AnimationPlayer` (⚠️ 4.3 AnimationMixer) |
| **TtsBridge** ⚠️ | TTS 3-tier fallback; `_audio_cache`; `_active_provider`; session health | `configure()`, `speak()`, `cancel()`, `warm_cache()`, signals: `speech_completed`, `speech_failed`, `tts_fallback_to_highlight` | ADR-0002 TtsProvider (RefCounted) | `HTTPRequest`, `AudioStreamPlayer`, `DisplayServer.tts_speak()`, `@abstract` (⚠️ 4.5) |
| **InterruptHandler** ⚠️ | Background/back-button/call interrupt protocol; re-entrance guards | `_notification()` captures platform events; internally calls VoiceRecorder + StoryManager | StoryManager, VoiceRecorder, SaveSystem | `_notification()`, `PROCESS_MODE_ALWAYS`, `ui_cancel` InputMap (⚠️ 4.6) |

### Feature Layer

| Module | Owns | Exposes | Consumes | Engine APIs |
|--------|------|---------|----------|-------------|
| **StoryManager** | Ink runtime wrapper; 6-state machine; chapter lifecycle | `begin_chapter()`, `confirm_navigation_complete()`, `request_chapter_interrupt()`, signals: `tags_dispatched`, `choices_ready`, `chapter_started`, `chapter_completed`, `chapter_interrupted` | VocabStore, ProfileManager, TtsBridge, TagDispatcher, inkgd | `InkStory`, `InkResource`, `InkRuntime`, `Timer` |
| **TagDispatcher** | Ink tag parsing (2/3 segment); event dispatch protocol | `dispatch(tags)`, `set_animation_handler()`, `set_vocab_text_map()`, signals: `tts_not_required` | StoryManager (signal), AnimationHandler, TtsBridge, VocabStore | None |
| **VoiceRecorder** ⚠️ | 6-state machine; WAV write; permission management; PCM accumulation | `start_recording()`, `stop_recording()`, `interrupt_and_commit()`, `get_recording_paths()`, `play_recording()`, signals: `recording_interrupted`, `recording_completed` | ProfileManager, SaveSystem | `AudioStreamMicrophone`, `AudioEffectCapture`, `AudioServer`, `OS.request_permission()` |
| **PostcardGenerator** | SubViewport offscreen rendering; PNG file storage | `generate()`, signals: `postcard_saved`, `postcard_failed` | VocabStore, ProfileManager, ADR-0003 | `SubViewport`, `Image`, `FileAccess`, `OS.get_system_dir()` |
| **ParentVocabMap** | Vocabulary map UI + recording playback + pause control | `open()`, `close()` | VocabStore, VoiceRecorder, ProfileManager, SaveSystem | `CanvasLayer`, `AudioStreamPlayer` |
| **Chapter2Teaser** | Static silhouette + fade-out animation | `play()` | None | `Tween`, `Timer` |

### Presentation Layer

| Module | Owns | Exposes | Consumes | Engine APIs |
|--------|------|---------|----------|-------------|
| **ChoiceUI** | Vocabulary dual-option buttons; Tween fade in/out | `show_choices()`, `hide()` | StoryManager (signal), TagDispatcher (signal) | `Control`, `HBoxContainer`, `TextureRect`, `Tween` |
| **MainMenu** | T-Rex idle/recognition; profile switch UI; start adventure launch sequence | Scene-level node | ProfileManager, StoryManager, AnimationHandler | `Control`, `AnimationPlayer`, `Timer` |
| **HatchScene** | Egg hatching ceremony (3 states) | Scene-level node | ProfileManager, AnimationHandler | `AnimationPlayer`, `CPUParticles2D`, `Tween`, `Timer` |
| **NameInputScreen** | Name input + avatar selection | Scene-level node | ProfileManager | `LineEdit`, `GridContainer`, `DisplayServer` |
| **RecordingInviteUI** | Recording invite modal (6 states) | Scene-level node | VoiceRecorder, TagDispatcher (signal), AnimationHandler | `CanvasLayer`, `_input()`, `Timer`, `Tween` |
| **VocabPrimingLoader** | Vocabulary priming animation (one-shot) | `priming_complete` signal | VocabStore (read-only) | `Tween`, `queue_free()` |

---

## Data Flow

### 1. Core Loop Flow

```
Child taps word icon
       │
       ▼
 ┌──────────┐  submit_choice({index, word_id})
 │ ChoiceUI │ ──────────────────────────────────► StoryManager.choose_choice()
 └──────────┘                                      │
                                                   ▼
                                          ┌─────────────────┐
                                          │  StoryManager    │
                                          │  (RUNNING state) │
                                          └────────┬────────┘
                                                   │
                                    story.continue_story()
                                                   │
                                          ┌────────┴────────┐
                                          │   current_text   │
                                          │   current_tags   │
                                          └────────┬────────┘
                                                   │
                              ┌─────────────────────┼─────────────────────┐
                              ▼                     ▼                     ▼
                   ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐
                   │  TtsBridge      │  │ TagDispatcher    │  │ (text display)  │
                   │  .speak()       │  │  .dispatch(tags) │  │                 │
                   └────────┬────────┘  └────────┬────────┘  └─────────────────┘
                            │                     │
                   AI HTTP / System TTS    ┌──────┼──────────┐
                            │              ▼      ▼          ▼
                            │        ┌────────┐ ┌────────┐ ┌──────────┐
                            │        │AnimHnd │ │VocabSt │ │TtsBridge │
                            │        │.play() │ │.correct│ │(already  │
                            │        └────────┘ └────────┘ │ speaking)│
                            │                              └──────────┘
                            ▼
                   speech_completed signal
                            │
                            ▼
                   StoryManager._advance_step()
                   (next text or CHOICE_PENDING)
```

**Data descriptions:**

| Data | Producer | Consumer | Transport |
|------|----------|----------|-----------|
| `submit_choice({index, word_id})` | ChoiceUI | StoryManager | Method call (sync) |
| `current_text` / `current_tags` | StoryManager (inkgd) | TtsBridge, TagDispatcher | Method parameters |
| `tags: Array` | StoryManager | TagDispatcher | signal `tags_dispatched` |
| `choices: Array[Dictionary]` | StoryManager | ChoiceUI | signal `choices_ready` |
| `speech_completed` | TtsBridge | StoryManager | signal (competing timeout) |
| `tts_not_required` | TagDispatcher | StoryManager | signal (skip TTS wait) |
| `audio: AudioStream` | TtsBridge | AudioStreamPlayer | Internal property |
| `vocab_data` writes | TagDispatcher → VocabStore | — | Method call (sync) |

### 2. Profile Switch Flow

```
MainMenu taps profile card
       │
       ▼
 ProfileManager.switch_to_profile(new_index)
       │
       ├─ ① validate index + exists
       ├─ ② state = SWITCHING
       │
       ├─ ③ EMIT profile_switch_requested ──────► [SYNC handlers, no await]
       │       │                                      │
       │       │                               ┌──────┴──────┐
       │       │                               ▼             ▼
       │       │                        VocabStore      VoiceRecorder
       │       │                        .reset_session() .interrupt_and_commit()
       │       │                        (counters=0)    (stop+discard or flag)
       │       │
       ├─ ④ SaveSystem.flush(old_index, old_data)
       ├─ ⑤ SaveSystem.load(new_index) → Dictionary
       ├─ ⑥ _active_data = duplicate_deep(loaded)
       ├─ ⑦ state = ACTIVE
       │
       └─ ⑧ EMIT profile_switched(new_index) ──► [Async handlers]
```

**Constraints:**
- Step ③ handlers MUST be synchronous (no `await`)
- Steps ④–⑥ are not yieldable (no data races allowed)
- VocabStore and VoiceRecorder session data reset/interrupt at step ③

### 3. Save/Load Path

```
              ┌─────────────────────────────────────┐
              │         _active_data: Dictionary     │
              │  { profile: {...},                   │
              │    vocab_progress: {...},             │
              │    story_progress: {...} }            │
              └──────────────────┬──────────────────┘
                                 │
                    ProfileManager.flush()
                                 │
                                 ▼
              ┌──────────────────────────────────────┐
              │      SaveSystem.flush(index, data)    │
              │                                       │
              │  ① JSON.stringify(data)               │
              │  ② FileAccess.open(.tmp, WRITE)       │
              │  ③ store_string(json) → check bool    │
              │  ④ close()                            │
              │  ⑤ DirAccess.rename(.tmp → .json)     │
              │  ⑥ check return != OK                 │
              └──────────────────────────────────────┘
                                 │
                                 ▼
              ┌──────────────────────────────────────┐
              │  user://saves/profile_{index}.json    │
              │  Atomic write: .tmp first, rename     │
              │  .tmp recovery: scan on _ready()      │
              └──────────────────────────────────────┘
```

**Data ownership (who writes which fields):**

| Field | Owner | Write Timing |
|-------|-------|-------------|
| `profile.name` | NameInputScreen | create_profile() |
| `profile.avatar_id` | NameInputScreen | create_profile() |
| `profile.times_played` | MainMenu | begin_session() (sole write point) |
| `profile.parent_map_hint_dismissed` | ParentVocabMap | close() |
| `vocab_progress.*.gold_star_count` | VocabStore | record_event() (gold star award) |
| `vocab_progress.*.is_learned` | VocabStore | record_event() (monotonic, never reverts) |
| `vocab_progress.*.first_star_at` | VocabStore | record_event() (write-once, null to timestamp) |
| `vocab_progress.*.seen` | VocabStore | record_event() (session-only, not persisted) |
| `vocab_progress.*.correct` | VocabStore | record_event() (session-only, not persisted) |
| `vocab_progress.*.recording_paths` | VoiceRecorder | stop_recording() (sole writer, append) |
| `story_progress.*` | StoryManager | chapter_completed() |

### 4. Initialization Order

> **LP-CONCERN-1**: 9 个 AutoLoad 接近 Godot 实用上限。启动时序受 `_ready()` 阻塞影响。
> **缓解措施**：(a) 首次 build 后立即 profiling 启动时间；(b) 若 >500ms，考虑将 InterruptHandler 合并入 StoryManager（它无公开 API，仅调用 SM + VR）。

```
App Launch
    │
    ▼
 Godot Engine boots
    │
    ▼
 AutoLoad singletons (Project Settings order — ADR-0007):
    │
    ├─ ① SaveSystem          ← Foundation, no deps
    │     └─ _ready(): .tmp recovery scan
    │
    ├─ ② ProfileManager      ← depends on SaveSystem
    │     └─ _ready(): load(0) → set initial state
    │
    ├─ ③ VocabStore          ← depends on ProfileManager
    │     └─ _ready(): get_section("vocab_progress")
    │
    ├─ ④ TtsBridge           ← no game deps (configure() deferred)
    │     └─ _ready(): add HTTPRequest child, AudioStreamPlayer child
    │
    ├─ ⑤ AudioManager        ← no game deps (ADR-0008)
    │     └─ _ready(): trivial (< 0.1ms)
    │
    ├─ ⑥ StoryManager        ← depends on VocabStore, TtsBridge, TagDispatcher
    │     └─ _ready(): assert InkRuntime != null
    │
    ├─ ⑦ TagDispatcher       ← depends on StoryManager, AnimationHandler
    │     └─ _ready(): empty (registration deferred to begin_chapter)
    │
    ├─ ⑧ VoiceRecorder       ← depends on ProfileManager, SaveSystem
    │     └─ _ready(): request RECORD_AUDIO permission
    │
    └─ ⑨ InterruptHandler    ← depends on StoryManager, VoiceRecorder
          └─ _ready(): connect to SM + VR signals
    │
    ▼
 Scene tree loads first scene:
    │
    ├─ times_played == 0 → HatchScene.tscn
    │     └─ AnimationHandler (scene-local) instantiated
    │
    └─ times_played > 0 → MainMenu.tscn
          ├─ AnimationHandler (scene-local) instantiated
          └─ ProfileManager.begin_session()
```

### 5. Interrupt Flow

```
 Android: back button / app background / phone call
       │
       ▼
 InterruptHandler._notification(NOTIFICATION_*)
       │
       ├─ ① VoiceRecorder.interrupt_and_commit()  ← must be first
       │     └─ RECORDING → stop + write WAV
       │     └─ SAVING → flag _discard_after_save
       │
       ├─ ② StoryManager.request_chapter_interrupt(reason)
       │     └─ cancel timer → disconnect signals → null ink → state=STOPPED
       │
       ├─ ③ SaveSystem.flush() (if reason != "profile_switch")
       │
       └─ ④ Navigation (if reason == "user_back_button")
             └─ change_scene_to_file("MainMenu.tscn")
```

---

## API Boundaries

### Foundation Layer

```gdscript
# ═══ SaveSystem — AutoLoad Singleton ═══
# Owns: all JSON file I/O, schema versioning, atomic write
# Invariant: callers never touch FileAccess/DirAccess directly

class_name SaveSystem extends Node

enum LoadError {
    NONE, FILE_NOT_FOUND, FILE_READ_ERROR,
    JSON_PARSE_ERROR, SCHEMA_VERSION_UNSUPPORTED, INVALID_INDEX
}

func load(index: int) -> Dictionary:
    # Returns {data: Dictionary, error: LoadError}
    # index must be in [0, MAX_SAVE_PROFILES)

func flush(index: int, data: Dictionary) -> bool:
    # Atomic write: .tmp → rename to .json

func delete_profile(index: int) -> bool:
    # Idempotent: file not found returns true

func get_save_path(index: int) -> String:
    # Pure function, no side effects
```

```gdscript
# ═══ ProfileManager — AutoLoad Singleton ═══
# Owns: _active_data (single authority), 4-state machine
# Invariant: exactly one profile active at any time (or none)

class_name ProfileManager extends Node

enum State { UNINITIALIZED, NO_ACTIVE_PROFILE, ACTIVE, SWITCHING }

signal profile_switch_requested()
signal profile_switched(new_index: int)
signal active_profile_cleared(reason: String)

func create_profile(index: int, name: String, avatar_id: int) -> bool:
    # Does NOT auto-activate

func switch_to_profile(index: int) -> void:
    # 7-step atomic sequence

func get_section(key: String) -> Dictionary:
    # Returns DIRECT REFERENCE (not copy)
    # DELIBERATE trade-off: VocabStore and VoiceRecorder need to mutate
    # vocab_progress fields in-place for performance (per-frame counters).
    # Safety: all mutations go through VocabStore/VoiceRecorder APIs, never
    # raw Dictionary manipulation. Profile switch boundary enforces reset.

func get_profile_header(index: int) -> Dictionary:
    # Returns {name, avatar_id, times_played, is_valid}

func begin_session() -> void:
    # Sole write point for times_played

func is_first_launch() -> bool:

func flush() -> void:

func get_profile_count() -> int:
```

```gdscript
# ═══ VocabStore — AutoLoad Singleton ═══
# Owns: vocab_progress data, session counters, gold star formula
# Invariant: is_learned is monotonically non-decreasing

class_name VocabStore extends Node

signal gold_star_awarded(word_id: String, new_star_count: int)
signal word_learned(word_id: String)

func record_event(word_id: String, event_type: EventType) -> void:
    # EventType: PRESENTED, SELECTED_CORRECT, NOT_CORRECT
    # NOT_CORRECT: intentionally no-op — no counters, no signals, no feedback (Anti-P2)

func get_gold_star_count(word_id: String) -> int:

func get_session_count(word_id: String, field: String) -> int:

func is_learned(word_id: String) -> bool:

func begin_chapter_session() -> void:

func end_chapter_session() -> void:
    # Calls ProfileManager.flush() once, then resets counters

func reset_session() -> void:
    # Sync handler for profile_switch_requested
```

### Core Layer

```gdscript
# ═══ AnimationHandler — Scene-Local Component ═══

class_name AnimationHandler extends Node

signal animation_completed(state: AnimState)
signal hatch_sequence_completed()

func play(state: AnimState) -> void:
    # Hard cut: custom_blend = 0.0
    # NON_INTERRUPTIBLE guard

func stop_recording_listen() -> void:
    # Bypasses NON_INTERRUPTIBLE guard

func get_current_state() -> AnimState:
```

```gdscript
# ═══ TtsBridge — AutoLoad Singleton ═══

class_name TtsBridge extends Node

signal speech_completed
signal speech_failed
signal tts_fallback_to_highlight(word_id: String)

func configure(provider_id: String, api_key: String, endpoint: String) -> void:
    # Looks up provider_id in PROVIDER_REGISTRY (preloaded Dictionary)
    # Unknown ID → push_error, is_configured() → false

func speak(word_id: String, text: String) -> void:
    # Cancels warm_cache + in-flight HTTP

func cancel() -> void:

func warm_cache(word_id: String, text: String) -> void:
    # Sequential queue; speak() always wins

# Provider registration: static PROVIDER_REGISTRY const maps
# provider_id → class reference (preloaded at script load)
# Adding a provider = one new .gd + one registry entry; TtsBridge unchanged
```

```gdscript
# ═══ TtsProvider — Abstract Base (RefCounted) ═══
# Defined in ADR-0002. All providers implement this contract.

@abstract
class_name TtsProvider extends RefCounted

@abstract func configure_credentials(api_key: String, endpoint: String) -> void
@abstract func is_configured() -> bool
@abstract func build_request_params(text: String, instruction: String) -> Dictionary
@abstract func parse_response(body: PackedByteArray) -> AudioStream
@abstract func classify_error(http_code: int) -> int

enum ProviderError { CONFIGURATION_ERROR = 0, TRANSIENT_ERROR = 1 }
```

```gdscript
# ═══ InterruptHandler — AutoLoad Singleton ═══
# No public API — purely event-driven via _notification()

class_name InterruptHandler extends Node
# process_mode = PROCESS_MODE_ALWAYS
```

### Feature Layer

```gdscript
# ═══ StoryManager — AutoLoad Singleton ═══

class_name StoryManager extends Node

enum State { IDLE, LOADING, RUNNING, CHOICE_PENDING, COMPLETING, STOPPED, ERROR }

signal tags_dispatched(tags: Array)
signal choices_ready(choices: Array[Dictionary])
signal chapter_started(chapter_id: String)
signal chapter_completed(chapter_id: String)
signal chapter_interrupted(reason: String)

func begin_chapter(chapter_id: String, ink_json_path: String) -> void:

func confirm_navigation_complete() -> void:

func request_chapter_interrupt(reason: String) -> void:
```

```gdscript
# ═══ TagDispatcher — AutoLoad Singleton ═══

class_name TagDispatcher extends Node

signal tts_not_required()

func dispatch(tags: Array) -> void:

func set_animation_handler(handler: AnimationHandler) -> void:

func set_vocab_text_map(map: Dictionary) -> void:
```

```gdscript
# ═══ VoiceRecorder — AutoLoad Singleton ═══

class_name VoiceRecorder extends Node

enum State { UNINITIALIZED, PERMISSION_REQUESTING, READY, RECORDING, SAVING, DISABLED }

signal recording_interrupted
signal recording_completed(word_id: String, path: String)

func start_recording(word_id: String) -> void:

func stop_recording() -> void:

func interrupt_and_commit() -> void:
    # Sync contract (no await)

func get_recording_paths(word_id: String) -> Array[String]:

func play_recording(path: String) -> void:

func stop_playback() -> void:
```

```gdscript
# ═══ PostcardGenerator — One-shot Node ═══

class_name PostcardGenerator extends Node

signal postcard_saved(path: String)
signal postcard_failed(reason: String)

func generate() -> void:
```

```gdscript
# ═══ ParentVocabMap — CanvasLayer Overlay ═══

class_name ParentVocabMap extends CanvasLayer

func open() -> void:
    # Pauses game tree

func close() -> void:
    # Resumes game tree
```

```gdscript
# ═══ Chapter2Teaser — One-shot Node ═══

func play() -> void:
```

### Presentation Layer — Signal Subscription Map

Presentation modules are scene-local. They communicate via signal subscription:

| Module | Subscribes To | Source |
|--------|--------------|--------|
| ChoiceUI | `choices_ready` | StoryManager |
| ChoiceUI | `chapter_interrupted` | StoryManager |
| RecordingInviteUI | `recording_invite_triggered` | TagDispatcher |
| RecordingInviteUI | `recording_interrupted` | VoiceRecorder |
| HatchScene | `animation_completed(RECOGNIZE)` | AnimationHandler |
| HatchScene | `hatch_sequence_completed` | AnimationHandler |
| VocabPrimingLoader | `gold_star_awarded` | VocabStore |
| MainMenu | `profile_switched` | ProfileManager |
| MainMenu | `chapter_completed` | StoryManager |

### Engine API Version Verification

| API | System | Risk | Verified Against | Status |
|-----|--------|------|-----------------|--------|
| `AnimationPlayer.play()` | AnimationHandler | MEDIUM (4.3) | `modules/animation.md` | ✅ Signature stable |
| `@abstract` decorator | TtsBridge (ADR-0002) | HIGH (4.5) | `current-best-practices.md` | ✅ Confirmed |
| `DisplayServer.tts_speak()` | TtsBridge | LOW | `modules/audio.md` | ✅ No breaking |
| `HTTPRequest` | TtsBridge | LOW | — | ✅ |
| `NOTIFICATION_WM_GO_BACK_REQUEST` | InterruptHandler | HIGH (4.6) | `breaking-changes.md` | ⚠️ Real device test needed |
| `ui_cancel` + `KEY_BACK` | InterruptHandler | HIGH (manual) | `modules/input.md` | ⚠️ Manual config required |
| `AudioStreamMicrophone` | VoiceRecorder | MEDIUM | `modules/audio.md` | ⚠️ Smoke test Week 3 |
| `SubViewport` + `UPDATE_ALWAYS` | PostcardGenerator | LOW | — | ✅ |
| `FileAccess.store_buffer()` → `bool` | SaveSystem, VoiceRecorder | MEDIUM (4.4) | `breaking-changes.md` | ✅ Documented |
| `DirAccess.rename()` return value | SaveSystem | MEDIUM (4.4) | `breaking-changes.md` | ✅ Error.OK=0 falsy |

---

## ADR Audit

### Existing ADR Quality

| ADR | Engine Compat | Version | GDD Linkage | Conflicts | Valid |
|-----|:---:|:---:|:---:|---------|:---:|
| ADR-0001: inkgd Runtime | ✅ Detailed | ✅ 4.6 | ✅ 7 GDD reqs | None | ✅ |
| ADR-0002: TTS Provider | ✅ Detailed | ✅ 4.6 | ✅ 6 GDD reqs | None | ✅ |
| ADR-0003: Android Gallery | ✅ Detailed | ✅ 4.6 | ✅ 5 GDD reqs | None | ⚠️ Week 1 verify |

### Traceability Coverage

| Req ID | Requirement | ADR | Status |
|--------|-------------|-----|:---:|
| TR-story-manager-001 | inkgd InkStory load path | ADR-0001 | ✅ |
| TR-story-manager-003 | begin_chapter 4-step order | ADR-0001 | ✅ |
| TR-story-manager-004 | _advance_step TTS wait gate | ADR-0001 | ✅ |
| TR-story-manager-012 | vocab_ch1.json format | ADR-0001 | ✅ |
| TR-story-manager-013 | NARRATION_WAIT_TIMEOUT | ADR-0001 | ✅ |
| TR-tag-dispatcher-001 | Ink tag parsing | ADR-0001 | ✅ |
| TR-vocab-store-007 | VOCAB_WORD_IDS_CH1 sync | ADR-0001 | ✅ |
| TR-tts-bridge-003 | TtsProvider interface | ADR-0002 | ✅ |
| TR-tts-bridge-005 | Lazy audio cache | ADR-0002 | ✅ |
| TR-tts-bridge-007 | warm_cache queue | ADR-0002 | ✅ |
| TR-tts-bridge-008 | HTTP timeout + format | ADR-0002 | ✅ |
| TR-tts-bridge-014 | configure() clears cache | ADR-0002 | ✅ |
| TR-story-manager-001 | TtsBridge narration | ADR-0002 | ✅ |
| TR-postcard-gen-003 | File write paths | ADR-0003 | ✅ |
| TR-postcard-gen-004 | PNG output format | ADR-0003 | ✅ |
| TR-postcard-gen-005 | Silent failure strategy | ADR-0003 | ✅ |
| TR-postcard-gen-006 | Data query in _ready | ADR-0003 | ✅ |

**Coverage: 17 covered, 15 gaps** (see Required ADRs below)

---

## Required ADRs

### Must Have Before Coding Starts

| # | Title | Covers | Priority |
|---|-------|--------|:---:|
| ADR-0004 | **SaveSystem 原子写入与 Schema 迁移** | TR-save-system-002~006, 009~012 | P0 |
| ADR-0005 | **ProfileManager 档案切换同步协议** | TR-profile-manager-003~005, 010 | P0 |
| ADR-0006 | **VocabStore 金星公式与跨系统写入契约** | TR-vocab-store-002~008 | P0 |
| ADR-0007 | **AutoLoad 启动顺序与初始化协议** | TR-interrupt-handler-009, TR-story-manager-001 | P0 |
| ADR-0008 | **AudioManager BGM 管理策略** | TR-main-menu-011, TR-name-input-009 | P0 |

### Should Have Before the Relevant System Is Built

| # | Title | Covers | Trigger |
|---|-------|--------|---------|
| ADR-0009 | **VoiceRecorder Android 录音可行性** | TR-voice-recorder-002~003, 006 | Week 3 Day 1 |
| ADR-0010 | **Android Back Button 检测策略** | TR-interrupt-handler-010, 002, 008 | Week 2 |
| ADR-0011 | **SubViewport 离屏渲染策略** | TR-postcard-gen-001~002, 007 | Week 3 |
| ADR-0012 | **Godot 4.6 Dual-Focus 隔离策略** | TR-choice-ui-006 | Week 2 |
| ADR-0013 | **Scene 切换与 cross-fade 过渡** | TR-hatch-scene-010, TR-chapter2-teaser-005 | Week 2 |

### Can Defer to Implementation

| # | Title | Covers |
|---|-------|--------|
| ADR-0014 | CPUParticles2D 性能预算 | TR-hatch-scene-013 |
| ADR-0015 | Egg Glow Shader 管线兼容 | TR-hatch-scene-012 |
| ADR-0016 | 录音 WAV 头构造与采样率 | TR-voice-recorder-005~006 |

---

## Architecture Principles

1. **Single Authority per Data Domain** — Every piece of mutable state has exactly one owner that writes it. SaveSystem owns file I/O. ProfileManager owns `_active_data`. VocabStore owns vocabulary counters. No module reads raw files or bypasses the authority chain.

2. **Sync or Nothing for Profile Switch** — `profile_switch_requested` handlers must be synchronous. Any `await` in a subscriber risks data corruption during the flush-load-replace window. This is a hard architectural constraint, not a guideline.

3. **Anti-Pillar P2 Enforcement at Data Layer** — `NOT_CORRECT` events flow to VocabStore for counting but MUST NEVER propagate to the presentation layer. No red elements, no error text, no shake animations. Confused animations are designed to be funny, not corrective.

4. **Silent Failure for Child-Facing Features** — Recording, postcard generation, and TTS degrade silently. Errors produce `push_warning` and signals, never crash, never interrupt the child's experience. The game must always feel like it's working.

5. **Foundation-First Build Order** — Systems are designed and built in dependency order: Foundation → Core → Feature → Presentation. No upper-layer code is written before its lower-layer dependencies are Approved. This eliminates circular dependency surprises.

---

## Open Questions

| # | Question | Owner | Blocking |
|---|----------|-------|:---:|
| 1 | `OS.request_permission("RECORD_AUDIO")` callback signature on Android — array-form or direct? | VoiceRecorder | Week 3 |
| 2 | `AudioStreamMicrophone` + `AudioEffectCapture` functional on target device? | VoiceRecorder | Week 3 Day 1 |
| 3 | `DirAccess.rename()` atomic-over-existing on Android API 24–33 devices? ADR-0004 必须含 fallback：rename 失败则读回 .tmp 直写 .json | SaveSystem | Week 1 |
| 4 | `OS.get_system_dir(SYSTEM_DIR_PICTURES)` writable on API 29+ without Scoped Storage? | PostcardGenerator | Week 1 |
| 5 | `NOTIFICATION_WM_GO_BACK_REQUEST` fires on Android 10+ gesture navigation? | InterruptHandler | Week 1 |
| 6 | AudioManager — is it a separate AutoLoad or part of an existing module? (TR-main-menu-011 implies new system not in systems-index) | GameRoot | Week 1 |
| 7 | `InkRuntime` singleton initialization timing — available before first scene _ready()? | StoryManager | Week 1 |
| 8 | `DisplayServer.tts_speak()` callback silence on OEM Android — watchdog timer accuracy? | TtsBridge | Week 2 |
