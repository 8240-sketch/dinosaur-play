# Cross-GDD Review Report

> **Date**: 2026-05-06
> **Skill**: /review-all-gdds (full)
> **Verdict**: ❌ FAIL — 2 blocking conflicts must be resolved before architecture begins

---

## Scope

| Item | Detail |
|------|--------|
| GDDs reviewed | 3 (SaveSystem, ProfileManager, VocabStore) |
| Reference documents | game-concept.md, systems-index.md |
| Entity registry | 6 constants (pre-verified by /consistency-check — PASS) |
| Mode | Full (consistency + design theory) |

---

## Consistency Issues

### Blocking (must resolve before architecture begins)

#### 🔴 C-1 — VocabStore 缺失于 ProfileManager 信号订阅者列表

**涉及文档**: `profile-manager.md` § 信号接口（第 270–271 行）↔ `vocab-store.md` Core Rules 5–6

**冲突详情**:

ProfileManager 信号接口表只列出 StoryManager、VoiceRecorder 为 `profile_switch_requested` 的订阅者，只列出 GameRoot 为 `profile_switched` 的订阅者。但 VocabStore 明确订阅两者（Core Rule 5、Core Rule 6、AC-9、AC-10），且实现中必须连接这两个信号才能正确清除/重新获取 `_vocab_data` 引用。

同一 GDD 的 Open Questions 第 413 行还称"当前 MVP 只有 StoryManager 和 VoiceRecorder **两个**订阅者"——与 VocabStore GDD 直接矛盾。

**运行时后果**: 若开发者按 ProfileManager 信号表实现，VocabStore 不会连接 `profile_switch_requested`，切换档案后 `_vocab_data` 继续指向旧档案对象，新档案将被旧档案词汇数据污染。

**需修复** (`profile-manager.md`):
- 信号接口 `profile_switch_requested` 订阅者一行：增加「VocabStore（同步清除 `_vocab_data` 和 `_session_counters` 引用）」
- 信号接口 `profile_switched` 订阅者一行：增加「VocabStore（重新获取 `_vocab_data` 引用）」
- Open Questions 第 413 行：「两个订阅者」改为「三个订阅者」

---

#### 🔴 C-2 — SaveSystem E8 与 ProfileManager Core Rule 7 矛盾（HatchScene 触发权归属）

**涉及文档**: `save-system.md` § Edge Cases E8 调用方职责列 ↔ `profile-manager.md` Core Rule 7

**冲突详情**:

| 文档 | 表述 |
|------|------|
| SaveSystem E8 调用方职责 | 「**ProfileManager 触发 HatchScene**（times_played == 0 且 name == ""）」|
| ProfileManager Core Rule 7 | 「ProfileManager 只暴露查询；**跳转至 HatchScene 是 GameRoot 的职责，不在 ProfileManager 内部触发**」|

两个已批准 GDD 对同一职责给出相反的归属。

**附加逻辑缺陷**: 首次启动时 `profile_exists(0)=false`，`switch_to_profile(0)` 在步骤 b 因验证失败返回。ProfileManager 永远不进入 ACTIVE 状态，`is_first_launch()` 因 EC-5 守卫返回 false。"ProfileManager 触发 HatchScene"的路径不存在。GameRoot 必须直接检查 `profile_exists(0)=false` 来决定路由，不依赖 `is_first_launch()`。

**需修复** (`save-system.md`):
- E8 调用方职责列改为：「GameRoot 通过 `profile_exists(0)=false` 检测，直接路由至 HatchScene；ProfileManager 不触发任何场景切换（Core Rule 7）」

---

### Warnings (should resolve, won't block architecture)

#### ⚠️ W-1 — ProfileManager "SaveSystem GDD 修正声明"已过时

**涉及文档**: `profile-manager.md` § SaveSystem GDD 修正声明（第 274–277 行）

声明称"SaveSystem GDD 的 Interactions 表需在 ProfileManager GDD 批准后做一次勘误更新（更新**两行**调用方）"。但 `save-system.md` 第 75–77 行已通过删除线 + 括号注释完成修正（含 InterruptHandler，实为**三行**）。该声明应标注为已解决或删除。

**修复**: 末尾追加「~~已完成 2026-05-06~~」或整段删除。

---

#### ⚠️ W-2 — VocabStore STAR_RATIO_THRESHOLD 缺权威来源注释

**涉及文档**: `vocab-store.md` § Tuning Knobs（第 186 行）

`STAR_RATIO_THRESHOLD` 的权威来源是 `game-concept.md`（entities.yaml `source: design/gdd/game-concept.md`），VocabStore 为引用方。Tuning Knobs 表中无归属说明，与 ProfileManager 处理 `MAX_SAVE_PROFILES` 时的规范不一致（profile-manager.md 第 287 行：「权威定义在 SaveSystem GDD；ProfileManager 只执行，不拥有」）。

**修复**: 追加「权威定义在 `game-concept.md`（entities.yaml 注册常量）；VocabStore 引用，不拥有」

---

## Game Design Theory Issues

### ✅ All Checks Pass

| 检查项 | 结果 | 说明 |
|--------|------|------|
| 3a 进度循环竞争 | ✅ PASS | 单一进度环（选词→金星→词汇地图），无竞争循环 |
| 3b 认知负荷 | ✅ PASS | 核心 30 秒最多 2 个主动决策（选词 + 可选录音），远低于 4–6 岁认知上限 |
| 3c 主导策略 | ✅ PASS | 二选一教育游戏；"选对单词"是设计意图，不适用传统主导策略分析 |
| 3d 经济循环 | ✅ PASS | 里程碑型经济（非水龙头/水槽型）；金星持续累积作为"认出了 N 次"展示，对复玩设计合理 |
| 3f 设计柱对齐 | ✅ PASS | 三份 GDD 均实现 P3（声音是成长日记）+ P4（家长是骄傲见证者）；无反柱违反 |
| 3g 玩家幻想连贯性 | ✅ PASS | 三份 GDD 幻想统一：「不会忘记的见证者」→「T-Rex 认识你」→「那颗星真实存在」，与核心身份高度一致 |

---

## Cross-System Scenario Issues

**走查场景数**: 2

### ✅ 场景 B：金星颁发后立即切换档案

金星通过直接引用写入 `_active_data["vocab_progress"]`。`_vocab_data = {}` 仅清空 VocabStore 的本地变量，底层数据在 `_active_data` 中完整保留。ProfileManager 步骤 e 的 `flush()` 正确持久化更新后的词汇数据。**无数据丢失风险** ✅

### ⚠️ 场景 A：首次启动路径（补充说明 C-2）

首次启动时 `profile_exists(0)=false` → `switch_to_profile(0)` 步骤 b 失败 → ProfileManager 保持 `NO_ACTIVE_PROFILE` → `is_first_launch()` 因 EC-5 返回 false。**GameRoot 必须基于 `profile_exists(0)=false` 直接路由至 HatchScene，而非依赖 `is_first_launch()`**。此路径未在任何已批准 GDD 中完整记录，需在未来的 GameRoot GDD 或架构 ADR 中明确。（与 C-2 同根）

---

## GDDs Flagged for Revision

| GDD | 原因 | 类型 | 优先级 |
|-----|------|------|--------|
| `save-system.md` | E8 调用方职责：ProfileManager 触发 HatchScene 与 PM Core Rule 7 矛盾 | 一致性 | **阻断** |
| `profile-manager.md` | 信号订阅者列表遗漏 VocabStore（两个信号）+ Open Questions 行数误差 + SaveSystem 修正声明悬挂 | 一致性 | **阻断**（订阅者列表）+ 警告（其余） |
| `vocab-store.md` | STAR_RATIO_THRESHOLD 缺权威来源注释 | 一致性 | 警告 |

---

## Verdict: ❌ FAIL

**2 个阻断冲突必须在 `/create-architecture` 开始前解决：**

1. **`profile-manager.md`** — 信号接口表加入 VocabStore 为 `profile_switch_requested` 和 `profile_switched` 的订阅者；修正 Open Questions 中"两个订阅者"为"三个"
2. **`save-system.md`** — E8 调用方职责列：将「ProfileManager 触发 HatchScene」改为「GameRoot 通过 `profile_exists(0)=false` 检测，直接路由至 HatchScene；ProfileManager 不触发任何场景切换」

**修复后**: 重新运行 `/review-all-gdds` 确认冲突已解决，再进入 `/create-architecture` 或 `/gate-check`。
