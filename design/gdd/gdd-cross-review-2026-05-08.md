# Cross-GDD Review Report — 2026-05-08

> **Verdict**: CONCERNS (⚠️ — 6 blockers documented, 0 architecture failures requiring GDD rewrites)
> **Scope**: All 18 system GDDs (full pass — consistency + design theory + scenario walkthrough)
> **Previous reviews**: 2026-05-06a (3 GDDs), 2026-05-06b (3 GDDs)
> **Report generated**: 2026-05-08

---

## Summary

18/18 系统 GDD 通过一致性与设计理论双重审查。6 项 BLOCKER 均为**文档空白**（缺少常量、缺少 signal、缺少 navigation 规则），不是架构失败，修复工作量均在 1–2 个文档段落级别。12 项 WARNING 为可接受的设计风险，建议在实现前记录缓解方案。

---

## Phase 2: Cross-GDD Consistency

### 🔴 Blockers

| # | 来源 | 问题 | 修复文件 |
|---|------|------|---------|
| **B-1** | SaveSystem ↔ ParentVocabMap | SaveSystem schema v2 JSON 示例、`_migrate_to_v2()`、`_get_default_v2()` 三处均未包含 `parent_map_hint_dismissed: false`。ParentVocabMap GDD OQ-2（BLOCKING）要求此字段存在于 F-1 profile schema。 | save-system.md（3 处） |
| **B-2** | ProfileManager ↔ NameInputScreen | ProfileManager Interactions 表中仍列「MainMenu → create_profile()」为调用方。NameInputScreen GDD Rule 8 明确声明 NameInputScreen 是唯一合法 create_profile() 调用方；MainMenu 仅调用 begin_session()。 | profile-manager.md |
| **B-3** | RecordingInviteUI ↔ AnimationHandler | D-1 要求（SAVING 阶段保持 T-Rex 举爪姿势）无实现路径：RIUI Interactions 表不含 AnimationHandler 接口；stop_recording_listen() 调用时机在 SAVING/DISMISSING 边界两侧均有解读空间；两个 GDD 均无 AC 保障此约束。 | recording-invite-ui.md, animation-handler.md |

### ⚠️ Warnings

| # | 来源 | 问题 |
|---|------|------|
| **W-1** | VocabStore ↔ PostcardGenerator | VocabStore Dependencies 表将 PostcardGenerator 调用接口写为 `is_word_learned()` (bool)；PostcardGenerator 实际调用 `get_gold_star_count()` (int) 用于 D1 金星三级视觉映射。接口名错误。 |
| **W-2** | TagDispatcher ↔ AnimationHandler | TagDispatcher VALID_ANIM_STATES 列表（上次更新 2026-05-07）未包含 RECOGNIZE 和 SITTING（AnimationHandler 于 2026-05-08 增量补丁新增）。不一致的 VALID 列表会导致新状态的 anim: 标签被静默忽略。 |
| **W-3** | VoiceRecorder ↔ RecordingInviteUI | VoiceRecorder GDD 无 SAVE_TIMEOUT_MS 常量声明；RecordingInviteUI E6 明确依赖此常量。I/O stall 情况下 SAVING 状态无超时逃脱路径。 |
| **W-4** | MainMenu ↔ ParentVocabMap | PARENT_HOLD_DURATION_SEC（长按 5 秒入口）在 MainMenu 和 ParentVocabMap GDD 中各自本地声明，无共享权威常量。两处若分别调整将产生不一致 UX。 |
| **W-5** | RecordingInviteUI | 缺少两项 AC：(a)「SAVING 阶段 RECORDING_LISTEN 姿势保持可见」；(b)「stop_recording_listen() 在 recording_saved/failed 之后调用」。B-3 的可测试性需要这两项 AC。 |

### ℹ️ Info（已确认无问题）

| # | 检查项 | 状态 |
|---|--------|------|
| I-1 | word_learned 信号契约（VocabStore 声明但无订阅者） | 已记录为设计内意图；MVP 范围内可接受 |
| I-2 | VocabPrimingLoader 已列入 VocabStore Interactions 表 | ✓ |
| I-3 | Chapter2Teaser 自主调用 change_scene_to_file()（Path A）已在 OQ-1 标注为待 ADR | ✓ |
| I-4 | IS_LEARNED_THRESHOLD 权威定义在 entities.yaml，各 GDD 引用一致 | ✓ |

---

## Phase 3: Game Design Holism

### 🔴 Blockers

| # | 类型 | 问题 |
|---|------|------|
| **BLOCK-3f-2** | Tier 3 TTS 降级路径孤立信号 | `tts_fallback_to_highlight(word_id, text)` 信号在全部 18 个 GDD 中无任何订阅者。TtsBridge 的 600ms 内部计时器仍会发出 `speech_completed`（不阻断 StoryManager），但孩子既无音频也无视觉高亮词汇反馈。在无网络 / 无 API Key 的中国 Android 设备（**MVP 主要用户群**）上，这是最可能触发的路径，且静默降级至零反馈。此 blocker 等待 GameScene GDD 声明订阅者。 |
| **BLOCK-3g-1** | 无 Ink 内容创作约束 | 「我教 T-Rex 英语」核心玩家幻想要求：在 ChoiceUI 呈现目标词汇之前，T-Rex 不能流利地说出该词汇。当前没有任何 GDD 包含此创作规则。若 Ink 作者在选择节点之前的叙事旁白中让 T-Rex 正确发音目标词，核心幻想立即崩溃，且无运行时保护。 |

### ⚠️ Warnings

| # | 类型 | 问题 |
|---|------|------|
| **WARN-3b-1** | 章节时长边界 | 5–10 分钟章节长度对 4 岁幼儿处于可接受上界。无「自然断点」设计文档（若孩子因注意力分散中途离开，重入体验未设计）。 |
| **WARN-3d-1** | 金星经济耗尽 | 每个词汇 IS_LEARNED_THRESHOLD=3 颗金星，5 词约 3 次完整通关可全部满星（~15–30 分钟游戏时长）。v2 第二章需在大多数孩子完成 3 次游戏前上线，否则经济目标耗尽。 |
| **WARN-3f-1** | Tier 2 TTS 机械音质 | 中国 Android 设备内置英文 TTS 音质通常为机械音，与沉浸式叙事不符，可能破坏 P1（看不见的学习）。TtsBridge GDD 未记录此风险或缓解策略。 |
| **WARN-3f-3** | VocabPrimingLoader 视觉 P1 张力 | VocabPrimingLoader 显示词汇卡片（含金星状态），若视觉风格类似「闪卡测验」（白背景+星形评分），将破坏 P1。GDD N-1 注记已部分缓解，但缺少「禁止使用闪卡测验视觉风格」的明确美术禁令约束。 |
| **WARN-3g-2** | P3 情感高峰数据缺失 | P3（声音是成长日记）的核心体验依赖孩子实际完成录音的比率。当前无埋点设计追踪 invite_shown_count vs recording_saved_count，无法在测试阶段验证 P3 可达性。 |
| **WARN-3g-3** | P3「第一次录音永久保留」架构未保障 | VocabStore GDD OQ-5 未解决：第一次录音的永久保护模型未设计。若孩子多次录音，旧录音可能被覆盖，失去 P3 的核心情感资产。 |

---

## Phase 4: Cross-System Scenario Walkthroughs

### Scenario 1: 词汇选择 — 核心循环

**触发**：孩子看到 ChoiceUI，选择正确词汇。

**数据流**：ChoiceUI → StoryManager.submit_choice() → _advance_step() → tags_dispatched([anim:happy, vocab:ch1_trex:correct]) → TagDispatcher：anim:happy 先触发 AnimationHandler，3-segment vocab 路由至 VocabStore.record_event(SELECTED_CORRECT) → 批次无 2-segment vocab → tts_not_required → StoryManager 继续推进。

**确认无问题**：end_chapter_session() 顺序由 StoryManager Rule 8 保障 ✓；金星数据在 PostcardGenerator 查询前已落盘 ✓。

**S1-W1 · WARNING**: Tier 3 TTS fallback（tts_fallback_to_highlight）无订阅者，同 BLOCK-3f-2。

---

### Scenario 2: 录音邀请流程 — 多系统链条

**触发**：TagDispatcher 收到 record:invite 标签 → recording_invite_triggered → RIUI APPEARING → 孩子长按录音 → RECORDING → 释放 → SAVING → recording_saved → DISMISSING。

**S2-W1 · WARNING（近 BLOCKER）**: D-1（SAVING 保持举爪）无实现路径。RIUI Interactions 无 AnimationHandler 接口；RECORDING_LISTEN 完成后 AnimationHandler 自动转默认状态，RIUI 无法保持其姿势。

**S2-W2 · WARNING**: VoiceRecorder 无 SAVE_TIMEOUT_MS；SAVING 状态可无限阻塞（I/O stall）。

**S2-W3 · WARNING**: StoryManager 在录音邀请期间独立推进。后续 anim: 标签可在 RECORDING_LISTEN 完成后立即改变 AnimationHandler 姿势，破坏 D-1 视觉预期。

---

### Scenario 3: 章节完成级联 — 多节点级联

**触发**：chapter_completed → PostcardGenerator → postcard_saved/failed → Chapter2Teaser → MainMenu。

**确认无问题**：end_chapter_session() 先于 chapter_completed 保障 ✓；SceneTree.paused 期间 process_frame await 冻结后正确恢复 ✓；Chapter2Teaser TWEEN_TIMEOUT 不在 PostcardGenerator 阶段运行 ✓。

**S3-W1 · WARNING**: PostcardGenerator 无渲染超时。AWAITING_RENDER 或 WRITING 无限阻塞时，postcard_saved/failed 永不发出，Chapter2Teaser 永不实例化，玩家卡死在通关后 GameScene（唯一逃脱路径：强制档案切换或重启 App）。

---

### Scenario 4: 档案切换中途

**触发**：家长从 PVM 切换至全新档案（times_played==0）。

**确认无问题**：金星数据在切换前 flush 安全 ✓；StoryManager 使用 flag-based wait，无悬空 await，无竞争条件 ✓。

**S4-B1 · BLOCKER**: profile_switched 发出后，无任何系统检查新档案 times_played==0 并路由至 HatchScene。新档案孩子跳过孵化序列，遭遇未初始化故事状态。

**S4-W1 · WARNING**: StoryManager NARRATION_WAIT_TIMEOUT_MS Timer process_mode 未指定。若实现为 PROCESS_MODE_ALWAYS，PVM 打开期间（SceneTree.paused=true）计时器仍运行，可能在家长浏览时推进故事。

---

### Scenario 5: 录音中 App 切至后台

**触发**：孩子按住录音按钮（RIUI RECORDING 状态）→ NOTIFICATION_WM_FOCUS_OUT → InterruptHandler。

**前提修正（S5-I3）**: IH 在 FOCUS_OUT 时不调用 SceneTree.paused=true（该行为仅属于 PVM）。

**S5-B1 · BLOCKER**: RecordingInviteUI E10 声称 interrupt_and_commit() emit recording_unavailable；VoiceRecorder §8 明确此信号仅在硬件不可用时发出，interrupt_and_commit() 不发出此信号。短录音（帧数不足）路径下，IH 调用 interrupt_and_commit() 后 VoiceRecorder 静默丢弃 buffer，RIUI 停留 RECORDING 状态无任何退出路径，界面永久卡死。

**S5-B2 · BLOCKER**: FOCUS_IN 路径无 RIUI 卡死状态恢复机制。依赖 S5-B1 修复后自动消除。

---

## Consolidated Action Plan

### P0 立即修复（阻断实现前必须完成）

| 优先级 | Blocker | 文件 | 修复内容 | 工作量 |
|--------|---------|------|---------|--------|
| P0 | B-1 | save-system.md | schema v2 三处添加 `parent_map_hint_dismissed: false` | XS |
| P0 | B-2 | profile-manager.md | Interactions 表：MainMenu → NameInputScreen 作为 create_profile() 唯一调用方 | XS |
| P0 | B-3 | recording-invite-ui.md | 明确 stop_recording_listen() 时机；新增 AC-X（SAVING 姿势）和 AC-Y（时序约束） | S |
| P0 | B-3 | animation-handler.md | Interactions 表补充与 RIUI 的时序约定 | XS |
| P0 | BLOCK-3f-2 | story-manager.md | 「依赖下游」列表标注「GameScene 必须订阅 tts_fallback_to_highlight」 | XS |
| P0 | BLOCK-3g-1 | story-manager.md | 新增 Ink 内容创作约束：目标词汇在 ChoiceUI 呈现前 T-Rex 不得流利发音或释义 | S |
| P0 | S4-B1 | profile-manager.md | profile_switched 订阅者列表新增：GameRoot 检查 times_played==0 路由至 HatchScene | S |
| P0 | S5-B1 | voice-recorder.md + recording-invite-ui.md | VR：新增 recording_interrupted 信号，interrupt_and_commit() 无条件 emit；RIUI：订阅此信号从 RECORDING 进入 DISMISSING；修正 E10 | S |

### P1 实现前完成（Warnings）

| Warning | 文件 | 修复内容 |
|---------|------|---------|
| W-1 | vocab-store.md | PostcardGenerator 调用接口：is_word_learned() → get_gold_star_count() |
| W-2 | tag-dispatcher.md | VALID_ANIM_STATES 添加 RECOGNIZE、SITTING |
| W-3 | voice-recorder.md | 新增 SAVE_TIMEOUT_MS 常量（推荐 3000ms）；SAVING 超时 → FAILED |
| W-4 | entities.yaml | 新增 PARENT_HOLD_DURATION_SEC: 5；两 GDD 引用并移除本地硬编码 |
| S4-W1 | story-manager.md | Rule 4e 明确 NARRATION_WAIT_TIMEOUT_MS Timer process_mode = PROCESS_MODE_INHERIT |
| S3-W1 | postcard-generator.md | 新增 POSTCARD_TIMEOUT_MS（推荐 8000ms）；超时 → postcard_failed("timeout") |

### Backlog（v1.1 / 设计迭代）

| 内容 |
|------|
| WARN-3b-1：章节自然断点 / 重入体验设计 |
| WARN-3d-1：金星经济扩展（第二章词汇） |
| WARN-3f-1：Tier 2 TTS 机械音质缓解策略 |
| WARN-3f-3：VocabPrimingLoader 美术禁令升级（禁止闪卡测验视觉风格） |
| WARN-3g-2：P3 录音率埋点（invite_shown / recording_saved 比率） |
| WARN-3g-3：VoiceRecorder OQ-5 — 第一次录音永久保护模型 |
| S2-W3：录音邀请期间 anim: 标签派发隔离（如 D-1 仍为强制要求） |

---

## 审核状态

| 指标 | 数量 |
|------|------|
| 审核范围 | 18 / 18 GDDs |
| P2 一致性 Blockers | 3 |
| P3 设计理论 Blockers | 2 |
| P4 场景演练 Blockers | 3（S5-B2 依赖 S5-B1） |
| 总独立 Blockers | **7**（均为文档空白，非架构失败） |
| Warnings | 12 |
| 已确认无问题项 | 17 |

**实现就绪条件**：全部 P0 修复应用后，18/18 GDD 可进入「实现就绪」状态，可启动 `/create-architecture`。

---

*Report generated by `/review-all-gdds` (full pass: P2 Consistency + P3 Design Theory + P4 Scenario Walkthrough)*
