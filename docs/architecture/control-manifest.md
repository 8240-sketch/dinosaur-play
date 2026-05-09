# Control Manifest: 恐龙叙事英语启蒙游戏

> **Manifest Version**: 2026-05-09
> **Source ADRs**: ADR-0001 ~ ADR-0024 (all Accepted)
> **Owner**: lead-programmer
> **Status**: Draft

> **What this document is**: A flat programmer rules sheet. Each line says
> what code MUST do, MUST NOT do, or SHOULD guard against. Stories embed the
> manifest version; `/story-done` checks for staleness.

---

## Foundation Layer

### SaveSystem (`src/foundation/save_system.gd`)

| Rule | Type | Source |
|------|------|--------|
| All persistence I/O MUST go through SaveSystem — no system directly accesses `user://` JSON files | REQUIRED | ADR-0004, TR-save-system-001 |
| File naming: `save_profile_{index}.json` + `.tmp` | REQUIRED | ADR-0004, TR-save-system-002 |
| Atomic write: `.tmp` → `DirAccess.rename()` → `.json` | REQUIRED | ADR-0004, TR-save-system-003 |
| `store_string()` return value MUST be checked as `bool` (Godot 4.4+) | REQUIRED | ADR-0004, TR-save-system-005 |
| `DirAccess.rename()` return MUST use `!= OK` (Error.OK = 0 is falsy) | REQUIRED | ADR-0004, TR-save-system-006 |
| Schema migration: additive only, idempotent, never delete fields | REQUIRED | ADR-0004, TR-save-system-004 |
| `.tmp` recovery MUST run in `_ready()` before any profile load | REQUIRED | ADR-0004 |
| Max 3 save profiles (indices 0, 1, 2) | REQUIRED | ADR-0004 |
| Save files MUST be < 1 KB | GUARDRAIL | architecture.md |

### ProfileManager (`src/foundation/profile_manager.gd`)

| Rule | Type | Source |
|------|------|--------|
| `_active_data` is the single authority for current profile data | REQUIRED | ADR-0005 |
| 4-state machine: idle → switching → active → clearing | REQUIRED | ADR-0005 |
| `profile_switch_requested` signal MUST be emitted before data swap | REQUIRED | ADR-0005 |
| `profile_switched` signal MUST be emitted after data swap complete | REQUIRED | ADR-0005 |
| Flush MUST happen before switching away from a profile | REQUIRED | ADR-0005 |
| Create profile MUST go through SaveSystem.flush_profile() | REQUIRED | ADR-0023 |

### VocabStore (`src/foundation/vocab_store.gd`)

| Rule | Type | Source |
|------|------|--------|
| `_vocab_data` is a section reference from ProfileManager — NOT a copy | REQUIRED | ADR-0006 |
| `_session_counters` are session-only — reset on profile switch | REQUIRED | ADR-0006 |
| Gold star formula: `correct / seen >= 0.8` | REQUIRED | ADR-0006 |
| `record_event()` is the only mutator for vocabulary data | REQUIRED | ADR-0006 |
| Flush happens via ProfileManager.flush(), not directly | REQUIRED | ADR-0006 |

---

## Core Layer

### AnimationHandler (`src/core/animation_handler.gd`)

| Rule | Type | Source |
|------|------|--------|
| 14 states + 18 clips — `CLIP_MAP` / `VARIANT_MAP` are constants | REQUIRED | ADR-0011 |
| Per-scene instantiation (NOT AutoLoad) | REQUIRED | ADR-0011 |
| `NON_INTERRUPTIBLE_STATES` must be checked before `play()` | GUARDRAIL | ADR-0011 |
| `AnimationMixer` base class (4.3+) — use `callback_mode_method` not `method_call_mode` | REQUIRED | ADR-0011 |
| confused animations MUST be funny, never fearful | REQUIRED | P2 pillar |

### TtsBridge (`src/core/tts_bridge.gd`)

| Rule | Type | Source |
|------|------|--------|
| 3-tier fallback: system TTS → AI HTTP → text highlight | REQUIRED | ADR-0002 |
| `@abstract` decorator on TtsProvider base class (Godot 4.5+) | REQUIRED | ADR-0002 |
| TTS failure MUST NOT block gameplay — silent degradation | REQUIRED | ADR-0002, ADR-0024 |
| Text highlight uses `--highlight-pulse` yellow | REQUIRED | art-bible Section 2 |

### AudioManager (`src/autoload/audio_manager.gd`)

| Rule | Type | Source |
|------|------|--------|
| BGM persists across scene changes | REQUIRED | ADR-0008 |
| Cross-fade on BGM change (Tween, 500ms default) | REQUIRED | ADR-0008 |
| BGM bus volume persists to profile | REQUIRED | ADR-0008 |

### InterruptHandler (`src/core/interrupt_handler.gd`)

| Rule | Type | Source |
|------|------|--------|
| Capture `NOTIFICATION_WM_GO_BACK_REQUEST` (Android back button) | REQUIRED | ADR-0012 |
| `_notification()` captures platform events; internally calls VoiceRecorder + StoryManager | REQUIRED | ADR-0012 |
| Re-entrance guards prevent duplicate interrupt handling | GUARDRAIL | ADR-0012 |
| `PROCESS_MODE_ALWAYS` for background interrupt capture | REQUIRED | ADR-0012 |

---

## Feature Layer

### StoryManager (`src/feature/story_manager.gd`)

| Rule | Type | Source |
|------|------|--------|
| 6-state machine: idle → loading → playing → paused → completed → interrupted | REQUIRED | ADR-0010 |
| inkgd `InkStory` is the narrative runtime — NOT custom JSON | REQUIRED | ADR-0001 |
| `tags_dispatched` signal carries parsed tags to TagDispatcher | REQUIRED | ADR-0010 |
| `choices_ready` signal carries options to ChoiceUI | REQUIRED | ADR-0010 |
| Chapter completion MUST trigger VocabStore.end_chapter_session() | REQUIRED | ADR-0010 |

### TagDispatcher (`src/feature/tag_dispatcher.gd`)

| Rule | Type | Source |
|------|------|--------|
| 2/3 segment tag parsing: `[action] [target] [optional_data]` | REQUIRED | ADR-0013 |
| Event dispatch protocol: tag → handler lookup → signal emission | REQUIRED | ADR-0013 |
| Unknown tags MUST be logged (push_warning), not crash | GUARDRAIL | ADR-0013 |

### VoiceRecorder (`src/feature/voice_recorder.gd`)

| Rule | Type | Source |
|------|------|--------|
| 6-state machine: idle → requesting_permission → recording → stopping → saving → error | REQUIRED | ADR-0009 |
| Permission denial → silent disable (no crash, no blocking) | REQUIRED | ADR-0009, P2 pillar |
| WAV write to `user://recordings/` via ProfileManager.flush() | REQUIRED | ADR-0009 |
| Max recording duration: 3 seconds | GUARDRAIL | game-concept.md |

---

## Presentation Layer

### ChoiceUI (`src/presentation/choice_ui.gd`)

| Rule | Type | Source |
|------|------|--------|
| Visual 二选一 — max 2 options per screen | REQUIRED | ADR-0020 |
| 96dp minimum touch target (art-bible) | REQUIRED | ADR-0020 |
| `FOCUS_NONE` required (4.6 dual-focus) | REQUIRED | ADR-0020 |
| No red error feedback — use `--feedback-gentle` amber | FORBIDDEN | P2 pillar |

### MainMenu (`src/presentation/main_menu.gd`)

| Rule | Type | Source |
|------|------|--------|
| T-Rex idle/recognition animation | REQUIRED | ADR-0014 |
| Profile switch via ProfileManager signals | REQUIRED | ADR-0014 |
| "出发冒险" button triggers StoryManager.begin_chapter() | REQUIRED | ADR-0014 |
| Long-press 5s for parent entry (hidden trigger) | REQUIRED | ADR-0014 |

### HatchScene (`src/presentation/hatch_scene.tscn`)

| Rule | Type | Source |
|------|------|--------|
| 3-state ceremony: idle → cracking → emerged | REQUIRED | ADR-0016 |
| Egg glow shader (CPUParticles2D, <3 active) | REQUIRED | ADR-0016 |
| Navigation target: NameInputScreen after ceremony | REQUIRED | ADR-0016 |

---

## Global Rules

| Rule | Type | Source |
|------|------|--------|
| All screens MUST be portrait 360×800dp | REQUIRED | technical-preferences.md |
| All interactive elements MUST be ≥ 96dp | REQUIRED | art-bible, accessibility-requirements.md |
| No red error feedback anywhere in the game | FORBIDDEN | P2 pillar, art-bible |
| No countdown timers or time pressure | FORBIDDEN | P2 pillar |
| No forced recording — recording is an invitation | FORBIDDEN | P3 pillar |
| TTS failure → silent degradation (text highlight) | REQUIRED | ADR-0002 |
| Recording permission denial → silent disable | REQUIRED | ADR-0009 |
| All animations MUST be < 3Hz (no flicker) | GUARDRAIL | accessibility-requirements.md |
| AutoLoad order: SaveSystem → ProfileManager → VocabStore → ... | REQUIRED | ADR-0007 |
