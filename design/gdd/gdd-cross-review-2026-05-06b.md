# Cross-GDD Review Report (Second Pass)

> **Date**: 2026-05-06
> **Skill**: /review-all-gdds (full)
> **Prior Review**: gdd-cross-review-2026-05-06.md (Verdict: FAIL)
> **This Review Verdict**: ⚠️ CONCERNS — 0 blocking, 4 warnings (prior 2 blockers confirmed fixed)

---

## Scope

| Item | Detail |
|------|--------|
| GDDs reviewed | 3 (SaveSystem, ProfileManager, VocabStore) |
| Reference documents | game-concept.md, systems-index.md |
| Entity registry | 6 constants |
| Mode | Full (consistency + design theory) |

---

## Prior Fix Verification

All 4 issues from the first review have been correctly implemented.

| Fix ID | Description | Verified In |
|--------|-------------|-------------|
| C-1 ✅ | profile-manager.md 信号表增加 VocabStore 为 profile_switch_requested / profile_switched 订阅者；Open Questions 第 415 行改为「三个订阅者」 | profile-manager.md §信号接口 l.270–271; l.415 |
| C-2 ✅ | save-system.md E8 调用方职责改为 GameRoot 通过 profile_exists(0)=false 直接路由至 HatchScene；ProfileManager 不触发场景切换 | save-system.md §Edge Cases l.139 |
| W-1 ✅ | profile-manager.md SaveSystem GDD 修正声明旧文字加删除线，追加「✅ 已完成 2026-05-06」 | profile-manager.md §SaveSystem GDD 修正声明 l.276–278 |
| W-2 ✅ | vocab-store.md STAR_RATIO_THRESHOLD 追加「权威定义在 game-concept.md；VocabStore 引用，不拥有」 | vocab-store.md §Tuning Knobs l.186 |

---

## Consistency Issues

### Blocking (must resolve before architecture begins)

**无。**

---

### Warnings (should resolve, won't block)

#### ⚠️ W-NEW-1 — vocab-store.md `VOCAB_WORD_IDS_CH1` 缺权威来源注释

**涉及文档**: `vocab-store.md` § Tuning Knobs ↔ `entities.yaml` constants

`VOCAB_WORD_IDS_CH1` Tuning Knob 目前只写"5词 / 修改需同步更新 SaveSystem"，但 entities.yaml 注册的 source = `save-system.md`，VocabStore 是引用方。与 W-2 修复后的 STAR_RATIO_THRESHOLD 归属注释模式不一致。

**需修复** (`vocab-store.md` Tuning Knobs `VOCAB_WORD_IDS_CH1` 行):
追加：`「权威定义在 save-system.md（entities.yaml 注册常量）；VocabStore 引用，不拥有」`

---

#### ⚠️ W-NEW-2 — VoiceRecorder 与 VocabStore 共享 `vocab_progress` section 未作字段分工说明

**涉及文档**: `profile-manager.md` § Downstream Dependencies l.261

profile-manager.md 列出 VoiceRecorder 调用 `get_section("vocab_progress")`，与 VocabStore 操作同一 section。vocab-store.md Core Rule 8 说明 recording_path 写权归 VoiceRecorder，但 profile-manager.md 的 Dependencies 表没有解释字段级分工，可能令实现者误判为并发写冲突。

**需修复** (`profile-manager.md` Downstream Dependencies VoiceRecorder 行, 「依赖性质」列):
追加说明：`「词段级字段分工：VocabStore 写 is_learned/gold_star_count/first_star_at；VoiceRecorder 仅写 recording_path；两者字段无交叠」`

---

## Game Design Theory Issues

### Blocking

**无。**

---

### Warnings

#### ⚠️ D-1 — 词汇可达性风险（金星经济约束缺失）

**涉及文档**: `vocab-store.md` § Formulas ↔ 尚未设计的 StoryManager / TagDispatcher

`is_learned` 依赖 3 颗金星；金星只能来自 `SELECTED_CORRECT` 事件。Chapter 1 共 3 个二选一分支、5 个词汇。若某词在所有可达路径中始终作为"错误选项"出现，该词的 `SELECTED_CORRECT` 事件永远无法触发，`is_learned` 对该词结构性不可达，金星经济破裂。

此风险由 Ink 剧本结构决定，不在现有 3 个 GDD 内。但必须在 StoryManager 或 TagDispatcher GDD 中明确约束：**5 个词汇均须在至少一条玩家可达的路径中作为正确选项出现**，且须纳入该 GDD 的验收标准。

**需修复** (`vocab-store.md` § Open Questions): 追加第 4 条：
`「词汇全覆盖约束（待 StoryManager/TagDispatcher GDD 承接）：5 个词汇均须在至少一条可达路径中可被 SELECTED_CORRECT 触发；否则 is_learned 对该词永不可达。此约束必须成为 Ink 剧本的验收标准之一。」`

---

#### ⚠️ D-2 — `NOT_CORRECT` 事件缺乏 Anti-Pillar P2 防护注释

**涉及文档**: `vocab-store.md` Core Rule 4 ↔ `game-concept.md` § Anti-Pillars

`NOT_CORRECT` 是显式开放的扩展点（"保留供遥测扩展，MVP 无业务逻辑"）。任何后续系统若将其连接至计分、家长可见错误计数或负面视觉反馈，将直接违反 Anti-Pillar P2（无测验式界面、无红色错误反馈）。目前 GDD 没有任何守护说明。

**需修复** (`vocab-store.md` Core Rule 4 `NOT_CORRECT` 处理段旁): 追加约束注释：
`「⚠️ NOT_CORRECT 永远不得连接至：计分、家长视图错误计数、任何负面视觉反馈。连接此事件违反 Anti-Pillar P2，无论实现上下文如何。」`

---

### Info (不阻断，供参考)

#### ℹ️ D-3 — 通关后参与度悬崖

5 词均达 `is_learned` 后 MVP 无新里程碑。`gold_star_count` 继续累积但无新显示变化。建议在 Vertical Slice 范围讨论时评估是否需要"全部已学"庆祝状态或 ParentVocabMap 持续性反馈设计。

#### ℹ️ D-4 — 章节内难度曲线未文档化为有意设计

Chapter 1 词汇排列（T-Rex/Triceratops → eat/run → big）呈降序难度；高潮分支使用最简单词汇。若为有意设计（轻松收尾、保证孩子以成功感结束），应在 StoryManager GDD 中声明为设计决策，避免 Ink 创作时被无意改变。

---

## Cross-System Scenario Walkthrough

| 场景 | 涉及系统 | 结论 |
|------|---------|------|
| 首次启动路由 | GameRoot → SaveSystem → HatchScene | ✅ E8 修复后正确；GameRoot 通过 profile_exists(0)=false 直接路由 |
| 金星颁发后立即切换档案 | VocabStore → ProfileManager → SaveSystem | ✅ 引用直写 _active_data，ProfileManager flush 步骤 e 持久化；无数据丢失 |
| profile_switch_requested 打断进行中章节 | ProfileManager → VocabStore（信号）→ StoryManager | ✅ 信号表已含三个订阅者；VocabStore 同步清除双层状态 |

---

## GDDs Flagged for Revision

| GDD | 原因 | 类型 | 优先级 |
|-----|------|------|--------|
| `vocab-store.md` | VOCAB_WORD_IDS_CH1 缺 source 归属注释（W-NEW-1） | 一致性 | 警告 |
| `vocab-store.md` | NOT_CORRECT 缺 Anti-Pillar P2 守护注释（D-2） | 设计理论 | 警告 |
| `vocab-store.md` | 词汇可达性约束备忘缺失（D-1，Open Questions） | 设计理论 | 警告 |
| `profile-manager.md` | VoiceRecorder/VocabStore 共享 section 字段分工未说明（W-NEW-2） | 一致性 | 警告 |

---

## Verdict: ⚠️ CONCERNS

**0 个阻断冲突**。先前 2 个阻断冲突（C-1、C-2）已全部解决。4 个警告应在 Feature 层 GDD（StoryManager、TagDispatcher）设计前处理，但不阻断 `/create-architecture` 执行。

### 快速修复（本次审核后立即应用）

| # | 文件 | 修复内容 | 预计工作量 |
|---|------|---------|----------|
| 1 | vocab-store.md | VOCAB_WORD_IDS_CH1 追加 source 注释 | 1 行 |
| 2 | vocab-store.md | NOT_CORRECT 追加 Anti-Pillar P2 守护注释 | 1 行 |
| 3 | vocab-store.md | Open Questions 追加词汇可达性约束备忘 | 3–4 行 |
| 4 | profile-manager.md | VoiceRecorder 行追加字段分工说明 | 1 行 |
