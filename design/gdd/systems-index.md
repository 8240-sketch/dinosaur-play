# Systems Index: 恐龙叙事英语启蒙游戏

> **Status**: Under Review
> **Created**: 2026-05-06
> **Last Updated**: 2026-05-06
> **Source Concept**: design/gdd/game-concept.md
> **TD-SYSTEM-BOUNDARY Review**: CONCERNS (accepted) 2026-05-06 — 5 items to resolve in GDDs
> **PR-SCOPE Review**: OPTIMISTIC 2026-05-06 — 3 adjustments accepted (see design order notes)

---

## Overview

面向 4–6 岁中文母语孩子的恐龙主题英语叙事游戏。孩子通过触屏选择英文单词图标推进剧情（inkgd Ink 运行时驱动），T-Rex 做出对应动画反应和 TTS 发音。核心循环：30 秒选词 → NPC 即时反应 → 可选录音邀请 → 5 分钟通关 → 词汇金星 + 恐龙明信片。系统设计围绕 4 根设计柱展开：「看不见的学习」「失败是另一条好玩的路」「声音是成长日记」「家长是骄傲见证者」。

4 周 MVP，18 个系统，分 4 个依赖层。Foundation（1 个）→ Core（4 个）→ Feature（4 个）→ Presentation（6 个）→ Polish/Output（3 个）。

---

## Systems Enumeration

| # | System Name | Category | Priority | Status | Design Doc | Depends On |
|---|-------------|----------|----------|--------|------------|------------|
| 1 | SaveSystem | Persistence | MVP | Approved | design/gdd/save-system.md | — |
| 2 | ProfileManager | Persistence | MVP | Approved | design/gdd/profile-manager.md | SaveSystem |
| 3 | VocabStore | Gameplay | MVP | Approved | design/gdd/vocab-store.md | SaveSystem, ProfileManager |
| 4 | AnimationHandler | Core | MVP | Approved | design/gdd/animation-handler.md | (Godot AnimationPlayer) |
| 5 | TtsBridge | Core | MVP | Approved | design/gdd/tts-bridge.md | (Godot DisplayServer) |
| 6 | StoryManager | Narrative | MVP | Approved | design/gdd/story-manager.md | VocabStore, ProfileManager, TtsBridge |
| 7 | TagDispatcher | Narrative | MVP | Approved | design/gdd/tag-dispatcher.md | StoryManager, AnimationHandler, TtsBridge, VocabStore |
| 8 | VoiceRecorder | Core | Vertical Slice | Approved | design/gdd/voice-recorder.md | ProfileManager, SaveSystem |
| 9 | InterruptHandler (inferred) | Core | Vertical Slice | Approved | design/gdd/interrupt-handler.md | StoryManager, SaveSystem, VocabStore, VoiceRecorder（软依赖） |
| 10 | ChoiceUI | UI | MVP | Approved | design/gdd/choice-ui.md | StoryManager, TtsBridge |
| 11 | MainMenu | UI | MVP | Approved | design/gdd/main-menu.md | ProfileManager, StoryManager |
| 12 | HatchScene | UI | Vertical Slice | Approved | design/gdd/hatch-scene.md | ProfileManager, AnimationHandler |
| 13 | NameInputScreen (inferred) | UI | Vertical Slice | Approved | design/gdd/name-input-screen.md | ProfileManager || 14 | RecordingInviteUI (inferred) | UI | Vertical Slice | Approved | design/gdd/recording-invite-ui.md | VoiceRecorder *(signal from TagDispatcher)* |
| 15 | VocabPrimingLoader (inferred) | UI | Vertical Slice | Approved | design/gdd/vocab-priming-loader.md | VocabStore |
| 16 | PostcardGenerator | Meta | Vertical Slice | Approved | design/gdd/postcard-generator.md | VocabStore, ProfileManager |
| 17 | ParentVocabMap | Meta | Vertical Slice | Approved with Conditions | design/gdd/parent-vocab-map.md | VocabStore, VoiceRecorder, ProfileManager |
| 18 | Chapter2Teaser | Meta | Vertical Slice | Not Started | — | (none) |

---

## Categories

| Category | Description | Systems in This Game |
|----------|-------------|---------------------|
| **Persistence** | Save state and profile continuity | SaveSystem, ProfileManager |
| **Gameplay** | Mechanics that make the game function | VocabStore |
| **Core** | Engine-bridge wrappers and platform systems | AnimationHandler, TtsBridge, VoiceRecorder, InterruptHandler |
| **Narrative** | Story delivery and event dispatch | StoryManager, TagDispatcher |
| **UI** | Player-facing interaction and feedback screens | ChoiceUI, MainMenu, HatchScene, NameInputScreen, RecordingInviteUI, VocabPrimingLoader |
| **Meta** | Output and parent-facing systems outside core loop | PostcardGenerator, ParentVocabMap, Chapter2Teaser |

---

## Priority Tiers

| Tier | Definition | Systems Count |
|------|------------|--------------|
| **MVP** | Required for the 30-second core loop to function: choose a word → NPC reacts → repeat | 9 systems |
| **Vertical Slice** | Required for a complete 5-minute chapter experience including all P1 features | 9 systems |
| **Full Vision** | v1.1+ features (deferred): PIN parental lock, cloud sync, iOS, Chapter 2 | 0 systems in this index |

---

## Dependency Map

### Foundation Layer (no dependencies)

1. **SaveSystem** — JSON file I/O and schema v2 migration; all persistence depends on this

### Core Layer (depends on Foundation or Godot Engine only)

1. **ProfileManager** — depends on: SaveSystem
2. **VocabStore** — depends on: SaveSystem, ProfileManager
3. **AnimationHandler** — depends on: Godot AnimationPlayer (no game-system dependencies)
4. **TtsBridge** — depends on: Godot DisplayServer.tts_speak() (no game-system dependencies)

### Feature Layer (depends on Core)

1. **StoryManager** — depends on: VocabStore, ProfileManager
2. **TagDispatcher** — depends on: StoryManager, AnimationHandler, TtsBridge, VocabStore
3. **VoiceRecorder** — depends on: ProfileManager, SaveSystem
4. **InterruptHandler** — depends on: StoryManager, SaveSystem, VocabStore, VoiceRecorder（软依赖，is_instance_valid 守卫）

### Presentation Layer (depends on Features)

1. **ChoiceUI** — depends on: StoryManager; *subscribes to signal from TagDispatcher (not a call dependency)*
2. **MainMenu** — depends on: ProfileManager, StoryManager
3. **HatchScene** — depends on: ProfileManager, AnimationHandler
4. **NameInputScreen** — depends on: ProfileManager
5. **RecordingInviteUI** — depends on: VoiceRecorder; *subscribes to signal from TagDispatcher (not a call dependency)*
6. **VocabPrimingLoader** — depends on: VocabStore

### Polish / Output Layer

1. **PostcardGenerator** — depends on: VocabStore, ProfileManager
2. **ParentVocabMap** — depends on: VocabStore, VoiceRecorder
3. **Chapter2Teaser** — depends on: (none — static animation scene)

---

## Recommended Design Order

*Adjusted per PR-SCOPE review: TagDispatcher + AnimationHandler moved to Week 2 to ensure
playable loop demo by Week 2 end. PostcardGenerator scoped to save-to-gallery (not Android
Share Intent). VoiceRecorder go/no-go is Day 1 of Week 3, not after 3 days.*

| Order | System | Priority | Layer | GDD Effort | TD/PR Notes |
|-------|--------|----------|-------|------------|-------------|
| 1 | SaveSystem | MVP | Foundation | S | Resolve: ProfileManager switch guard protocol — **Approved 2026-05-06** |
| 2 | ProfileManager | MVP | Core | M | Resolve: `times_played` owner declaration; pre_switch_checks contract — **Approved 2026-05-06** |
| 3 | VocabStore | MVP | Core | M | schema v2 multi-profile; gold star threshold — **Approved 2026-05-06** |
| 4 | AnimationHandler | MVP | Core | S | 14 logical states / 18 clips; NON_INTERRUPTIBLE includes RECOGNIZE — **Approved 2026-05-06**; incremental patch 2026-05-08 (RECOGNIZE+SITTING); /design-review RF-NEW-1~9 applied 2026-05-08 (CD D1/D2) |
| 5 | TtsBridge | MVP | Core | S | Godot 4.6 tts_speak() + text-highlight fallback — **Approved 2026-05-06** |
| 6 | StoryManager | MVP | Feature | M | inkgd wrapper; chapter state machine; TtsBridge dependency — **Approved 2026-05-06** |
| 7 | TagDispatcher | MVP | Feature | M | Resolve: VocabStore write contract; signal-based ChoiceUI/RecordingInviteUI — **Approved 2026-05-06**; /design-review RF-1~RF-6 applied 2026-05-07 (VALID_ANIM_STATES fix, record:invite 3-segment, P2 cross-doc anchor, AC-13b+N1~N4) |
| 8 | VoiceRecorder ⚠️ | VS | Feature | M | **Day 1 go/no-go**: 5-min smoke test; fallback = remove feature |
| 9 | InterruptHandler | VS | Feature | S | _notification() back key / phone call / screen-off |
| 10 | ChoiceUI | MVP | Presentation | S | 96dp buttons; signal subscriber (not TagDispatcher caller) — **Approved 2026-05-07**; SM patch applied (choices_ready chinese_text, vocab_ch1.json nested format); /design-review RF-1~RF-8 applied (P2 fix, B1/B2, N3, layout 96dp) |
| 11 | MainMenu | MVP | Presentation | S | T-Rex idle; profile indicator; 「出发冒险！」 — **Approved 2026-05-08**; /design-review RF-1~RF-13 + R1~R8 applied 2026-05-08 (B1~B13: transitions/dead-state/div-zero/begin_session/layout/P2/deferred_confused/missing-ACs/mock-spec) |
| 12 | HatchScene | VS | Presentation | S | times_played==0 gate; egg crack AnimationPlayer sequence |
| 13 | NameInputScreen | VS | Presentation | S | 20-char max (NAME_MAX_LENGTH constant); skippable; ProfileManager.create_profile |
| 14 | RecordingInviteUI | VS | Presentation | S | signal subscriber (not TagDispatcher caller); orange circle button |
| 15 | VocabPrimingLoader | VS | Presentation | S | tween await; queue_free pattern |
| 16 | PostcardGenerator | VS | Polish/Output | M | **Scope: save to Pictures gallery** (not Android Share Intent); 1080×1080 — **Approved 2026-05-08**; /design-system N-1~N-3 applied (FRESH 待探索意图, P3 分工, OQ-4 30s 标准) |
| 17 | ParentVocabMap | VS | Polish/Output | M | Gold star map; VoiceRecorder playback; long-press-5s entry |
| 18 | Chapter2Teaser | VS | Polish/Output | S | Static silhouette + 3s fade-out; no data deps |

*Effort: S = 1 design session, M = 2–3 sessions*

---

## Circular Dependencies

None found. Dependency graph is a clean DAG.

Signal subscriptions (ChoiceUI ⟵ TagDispatcher, RecordingInviteUI ⟵ TagDispatcher) run in
the reverse direction of the call dependencies — these are intentionally one-way and do not
create cycles.

---

## High-Risk Systems

| System | Risk Type | Risk Description | Mitigation |
|--------|-----------|-----------------|------------|
| **VoiceRecorder** ⚠️ | Technical | `AudioStreamMicrophone` + `AudioEffectCapture` may fail silently on target Android device; `RECORD_AUDIO` permission UX is unpredictable across Android 7–14 | **Day 1 of Week 3**: 5-min smoke test on target device. If device can't initialize in 5 min → cut feature immediately. No data persists; InterruptHandler and ParentVocabMap still function (playback section silenced). |
| **inkgd Android APK** | Technical | inkgd v0.6.0 GDScript Ink runtime may have Android export issues unknown to LLM (post-4.3 knowledge cutoff) | **Week 1 end gate**: chapter1_minimal.ink.json P0 validation on real device. If fails → switch to custom JSON state machine (~150 GDScript lines), 1–2 days. **ADR-0001** (`docs/architecture/adr-0001-inkgd-runtime.md`, Proposed 2026-05-06) defines loading API and Android fallback. |
| **ProfileManager** | Design | 8 systems depend on it; `times_played` ownership and pre_switch_checks protocol must be declared before 6 downstream GDDs are written | Design first in the order. GDD must define the profile-switch guard contract explicitly. |
| **TagDispatcher** | Design | Central bus connecting Ink events to all game reactions; VocabStore write contract must be declared (Concern #1 from TD review) | GDD must define: which tags trigger vocab writes, whether TagDispatcher calls VocabStore directly or signals, and the full tag vocabulary |
| **PostcardGenerator** | Technical | Android Share Intent (`ACTION_SEND`) requires Java wrapper in Godot 4.6 — no direct GDScript API | **Scope reduced**: v1 saves 1080×1080 PNG to Android Pictures gallery via `DirAccess`/`FileAccess`. No Share Intent. User shares from gallery manually. |

---

## TD-SYSTEM-BOUNDARY Concerns (to resolve in GDDs)

These 5 items were raised by Technical Director review on 2026-05-06. Each must be
resolved in the specified GDD before that GDD is approved.

| # | Concern | Severity | Resolve In |
|---|---------|----------|-----------|
| 1 | TagDispatcher has undeclared VocabStore write dependency — which tags trigger writes, direct call vs signal? | ~~🔴 Significant~~ ✅ **Resolved in TagDispatcher GDD 2026-05-06** | TagDispatcher GDD |
| 2 | `times_played` has no declared owner — both HatchScene and StoryManager read it, who writes it? | ~~🔴 Significant~~ ✅ **Resolved in ProfileManager GDD 2026-05-06** | ProfileManager GDD |
| 3 | ChoiceUI → TagDispatcher dependency is likely inverted — should be signal subscription, not method call | ~~🟡 Moderate~~ ✅ **Resolved in ChoiceUI GDD 2026-05-07** | ChoiceUI GDD |
| 4 | RecordingInviteUI → TagDispatcher dependency is inverted — should subscribe to `recording_invite_triggered` signal | 🟡 Moderate | RecordingInviteUI GDD |
| 5 | VoiceRecorder GDD dual responsibility declared in Core Rule 2 | ~~🟢 Minor~~ ✅ **Resolved in VoiceRecorder GDD 2026-05-07** | VoiceRecorder GDD |
| — | ProfileManager pre_switch_checks guard unowned — in-flight VoiceRecorder or unsaved StoryManager progress could be lost on profile switch | ~~Structural note~~ ✅ **Resolved in ProfileManager GDD 2026-05-06** | ProfileManager GDD |

---

## Progress Tracker

| Metric | Count |
|--------|-------|
| Total systems identified | 18 |
| Design docs started | 17 |
| Design docs reviewed | 17 |
| Design docs approved | 17 |
| MVP systems designed | 9 / 9 |
| Vertical Slice systems designed | 7 / 9 |

---

## Next Steps

- [ ] `/design-system save-system` — first GDD (Foundation, unblocks all others) ✓ **APPROVED 2026-05-06**
- [ ] `/design-system profile-manager` — second (most downstream dependents, Concern #2 owner) ✓ **APPROVED 2026-05-06**
- [ ] `/design-system vocab-store` — third (unblocks StoryManager)
- [ ] Run `/design-review design/gdd/[system].md` after each GDD is complete
- [ ] Prototype VoiceRecorder in Week 3 Day 1 (go/no-go smoke test before writing GDD)
- [ ] Run `/gate-check systems-design` when all MVP GDDs (9 systems) are complete
