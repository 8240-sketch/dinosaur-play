# VocabStore

> **Status**: Approved — cross-review fixes applied 2026-05-06; `end_chapter_session()` added 2026-05-06 (StoryManager GDD requirement)
> **Author**: Zhang Shaocong + agents
> **Last Updated**: 2026-05-06
> **Implements Pillar**: P3 (声音是成长日记), P4 (家长是骄傲见证者)

## Overview

VocabStore 是游戏的词汇进度数据管理层，持有并更新当前活跃档案中 `vocab_progress` section 的所有字段。它位于 ProfileManager（内存访问入口）与上层系统（TagDispatcher、StoryManager、ParentVocabMap）之间：TagDispatcher 在孩子选词或故事推进时通知 VocabStore 记录词汇事件；VocabStore 执行金星判定逻辑，更新 `gold_star_count`、`is_learned`、`first_star_at`，并通过 `ProfileManager.flush()` 持久化变更。VocabStore 不直接操作 SaveSystem，也不拥有 `recording_path` 字段（该字段由 VoiceRecorder 负责）。Chapter 1 共 5 个词汇键（`VOCAB_WORD_IDS_CH1`），每键记录一个独立进度结构；词汇键集合当前在 VocabStore 内硬编码，待 VocabStore GDD 完成后与 SaveSystem 迁移函数统一评估。VocabStore 通过 `get_section("vocab_progress")` 持有对 `_active_data` 的直接引用，在收到 `profile_switch_requested` 信号时同步清除此引用。

## Player Fantasy

孩子第一次选对「Triceratops」，词汇地图上那颗星悄然亮起——这是孩子不会描述但会记住的一刻。家长六个月后点开那颗星，听见的是孩子当时细小清亮的声音——这是家长不会忘记的一刻。这两个时刻都由 VocabStore 撑起：金星的出现依赖 `gold_star_count` 与 `is_learned` 的精确维护，录音回放与词汇的对应依赖 `first_star_at` 时间戳将那次朗读永久绑定到那颗星上。VocabStore 本身没有玩家幻想；它是幻想得以成立的前提。

## Detailed Design

### Core Rules

1. **内存状态（两层）**：
   - `_vocab_data: Dictionary` — `ProfileManager.get_section("vocab_progress")` 的直接引用；profile 切换时置为 `{}`，profile 加载后重新获取。
   - `_session_counters: Dictionary` — 每词每局的会话内计数：`{ word_id: { "seen": int, "correct": int, "star_awarded": bool } }`；在 `profile_switch_requested` 和 `begin_chapter_session()` 时重置为零值。**不持久化。**

2. **`_ready()` 初始化**：同步连接 `ProfileManager.profile_switch_requested` 和 `profile_switched` 信号（无 `await`）；若 ProfileManager 已有活跃档案则立即获取 `_vocab_data` 引用并重置计数器。

3. **`begin_chapter_session() -> void`（StoryManager 调用）**：重置 `_session_counters`（所有词汇键初始化为 `{seen: 0, correct: 0, star_awarded: false}`）。不接触 `_vocab_data`（持久字段不受影响）。

3.1 **`end_chapter_session() -> void`（StoryManager 调用）**：
   - 若 `_vocab_data == {}`：`push_warning`，立即返回
   - 执行 `ProfileManager.flush()`（防御性落盘，确保最后一次金星结果持久化；失败仅 `push_error`，不回退内存）
   - 重置 `_session_counters`（所有词汇键清零，等同于 `begin_chapter_session()` 初始化）
   - **调用时机约束**：仅在章节正常完结时调用（`!story.can_continue && story.current_choices.is_empty()`）；章节中途被 `profile_switch_requested` 打断时不调用——此时由 InterruptHandler 负责紧急写盘，`_session_counters` 将在下次 `begin_chapter_session()` 时重置

4. **`record_event(word_id: String, event_type: EventType) -> void`（TagDispatcher 调用）**：
   - 若 `_vocab_data` 为空：`push_warning`，返回（无活跃档案时静默忽略）
   - 若 `word_id` 不在 `VOCAB_WORD_IDS_CH1`：`push_error`，返回
   - `PRESENTED`：`_session_counters[word_id].seen += 1`
   - `SELECTED_CORRECT`：
     - a. `seen += 1`（选中即已展示）；`correct += 1`
     - b. 若 `star_awarded == false` 且 `seen > 0` 且 `correct / seen >= STAR_RATIO_THRESHOLD`：
       - `_vocab_data[word_id].gold_star_count += 1`
       - 若 `first_star_at == null`：设 `first_star_at = Time.get_datetime_string_from_system(true) + "Z"`
       - `star_awarded = true`（本局此词不再重复颁星）
       - 若 `is_learned == false` 且 `gold_star_count >= IS_LEARNED_THRESHOLD`：`is_learned = true`；`emit("word_learned", word_id)`
       - `emit("gold_star_awarded", word_id, gold_star_count)`
       - `ProfileManager.flush()`（失败仅 `push_error`，不回退内存）
   - `NOT_CORRECT`：不更新任何计数（保留供遥测扩展，MVP 无业务逻辑）。**⚠️ NOT_CORRECT 永远不得连接至计分、家长视图错误计数或任何负面视觉反馈——连接此事件违反 Anti-Pillar P2，无论实现上下文如何。**

5. **`profile_switch_requested` 处理器（同步，无 `await`）**：
   ```gdscript
   func _on_profile_switch_requested(_new_index: int) -> void:
       _vocab_data = {}
       _session_counters = {}
   ```

6. **`profile_switched` 处理器**：
   ```gdscript
   func _on_profile_switched(_new_index: int) -> void:
       _vocab_data = ProfileManager.get_section("vocab_progress")
       _reset_session_counters()
   ```

7. **`is_learned` 单调性**：`is_learned` 一旦为 `true` 永不回退（重播不会降级已学词汇）。`gold_star_count` 继续累积（无上限）。

8. **`recording_path` 只读**：VocabStore 读取 `recording_path`（供 ParentVocabMap 使用），但不写入。写权限归 VoiceRecorder。

9. **防护：无活跃档案**：所有公开方法在 `_vocab_data == {}` 时返回安全默认值（`is_word_learned → false`，`get_gold_star_count → 0`，`get_first_star_at → ""`）并 `push_warning`。

### States and Transitions

VocabStore 无独立状态机——其可用性由 `_vocab_data` 是否非空决定，镜像 ProfileManager 的 ACTIVE/NO_ACTIVE_PROFILE 状态。

| `_vocab_data` 状态 | 触发条件 | record_event() 行为 |
|-------------------|---------|-------------------|
| `{}` (不可用) | profile_switch_requested / 启动前 | push_warning, 返回 |
| 非空引用 (可用) | profile_switched 后 | 正常执行判定逻辑 |

会话计数器独立于档案状态，在以下情况重置：
- `profile_switch_requested` 信号（丢弃进行中局面）
- `begin_chapter_session()` 调用（新局开始）

### Interactions with Other Systems

| 调用方 / 信号源 | 交互 | 时机 |
|---------------|------|------|
| **TagDispatcher** | 调用 `record_event(word_id, event_type)` | 词汇展示或孩子选词时 |
| **StoryManager** | 调用 `begin_chapter_session()` | 每局章节开始前 |
| **StoryManager** | 调用 `end_chapter_session()` | 章节正常完结（`!story.can_continue && story.current_choices.is_empty()`）后；中断场景不调用 |
| **ProfileManager** | 发出 `profile_switch_requested(new_index)` | VocabStore 同步清除引用和计数 |
| **ProfileManager** | 发出 `profile_switched(new_index)` | VocabStore 重新获取 `_vocab_data` 引用 |
| **VocabStore** | 调用 `ProfileManager.flush()` | 每次金星颁发后 |
| **ParentVocabMap** | 调用 `get_gold_star_count(word_id)`、`get_first_star_at(word_id)` | 家长视图渲染 |
| **PostcardGenerator** | 调用 `is_word_learned(word_id)` | 明信片生成时筛选已学词汇 |
| **VocabPrimingLoader** | 调用 `get_gold_star_count(word_id)` | 章节开始前预加载词汇状态显示 |

## Formulas

### 金星判定公式（Gold Star Award）

```
star_awarded_this_play(word_id) =
    NOT session_star_awarded[word_id]
    AND session_seen[word_id] > 0
    AND (session_correct[word_id] / session_seen[word_id]) >= STAR_RATIO_THRESHOLD
```

| 变量 | 类型 | 范围 | 描述 |
|------|------|------|------|
| `session_correct[word_id]` | int | 0 – seen | 本局该词被正确选择次数 |
| `session_seen[word_id]` | int | 0 – N | 本局该词被展示次数 |
| `session_star_awarded[word_id]` | bool | {false, true} | 本局此词是否已颁星（单局上限） |
| `STAR_RATIO_THRESHOLD` | float | 0.0–1.0（当前 0.8） | 最低正确率阈值 |

**MVP 实际值**：Chapter 1 每词每局仅展示一次，故 `correct/seen ∈ {0.0, 1.0}`；公式等效为"这词选对了就颁星"。

**输出**：`bool`。为 `true` 时执行 `gold_star_count += 1`。

---

### `is_learned` 判定公式

```
is_learned(word_id) = gold_star_count[word_id] >= IS_LEARNED_THRESHOLD
```

| 变量 | 类型 | 范围 | 描述 |
|------|------|------|------|
| `gold_star_count[word_id]` | int | 0 – ∞ | 该词在所有章节重播中累积的金星数 |
| `IS_LEARNED_THRESHOLD` | int | 1–5（当前 3） | 触发 `is_learned = true` 的最低金星数 |

**输出**：`bool`，单调递增（一旦为 `true` 不回退）。

**设计依据**：孩子须在 3 次不同章节重播中正确选词，随机猜中概率 = 0.5³ = 12.5%，足以区分认识与猜测；同时对愿意重播的 4–6 岁孩子完全可达。跨日期限制作为 `first_star_at` 的补充信息开放给家长，不由 VocabStore 强制执行（v2 backlog）。

---

### `first_star_at` 写入规则

```
if gold_star_count == 1 and first_star_at == null:
    first_star_at = UTC_ISO8601_timestamp
```

**单调写入**：仅在首次颁星时写入；后续所有星不覆盖此字段。格式与 SaveSystem 统一：`Time.get_datetime_string_from_system(true) + "Z"`。

## Edge Cases

| # | 边界情况 | VocabStore 行为 | 调用方职责 |
|---|---------|----------------|-----------|
| E1 | **`record_event()` 在无活跃档案时调用** | `_vocab_data == {}`：`push_warning`，立即返回；不修改任何数据 | TagDispatcher / StoryManager 在调用前可先检查 `ProfileManager.has_active_profile()` |
| E2 | **未知 `word_id`**（不在 `VOCAB_WORD_IDS_CH1`） | `push_error`，立即返回；不修改任何数据 | TagDispatcher 在构造事件时使用 `VOCAB_WORD_IDS_CH1` 常量，不硬编码字符串 |
| E3 | **同一词在同一局被颁星两次**（例如 TagDispatcher 发出两次 `SELECTED_CORRECT`） | `session_star_awarded[word_id] == true`：跳过颁星逻辑；`gold_star_count` 不重复递增 | TagDispatcher 应保证每局每词至多发出一次 `SELECTED_CORRECT` |
| E4 | **`ProfileManager.flush()` 在金星颁发后失败** | 内存中 `gold_star_count`、`is_learned`、`first_star_at` 已更新；信号已发出；磁盘未写入。`push_error`。下次 flush（如 `InterruptHandler` 触发）会持久化内存状态 | 无需额外处理；内存数据不丢失，下次 flush 自动重试 |
| E5 | **`is_learned` 已为 `true`，`gold_star_count` 继续增加** | `is_learned` 不变（单调）；`gold_star_count` 继续 `+= 1`；仅重复发出 `gold_star_awarded`，不再发出 `word_learned` | ParentVocabMap 读取 `gold_star_count` 显示「认出了 N 次」，与 `is_learned` 状态独立显示 |
| E6 | **章节中途 profile 切换**（`profile_switch_requested` 打断进行中的章节） | `_vocab_data = {}`；`_session_counters = {}`；进行中的局面计数全部丢弃；ProfileManager 切换流程继续 | StoryManager 在 `profile_switch_requested` 处理器中停止故事推进；UI 回到档案选择界面 |
| E7 | **`begin_chapter_session()` 未被调用就开始发 `record_event`** | `_session_counters` 可能残留上一局数据；`star_awarded` 可能已为 `true` 导致本局无法颁星 | **StoryManager 必须在每局开始前调用 `begin_chapter_session()`**；VocabStore 不做自动检测 |
| E8 | **`SELECTED_CORRECT` 在 `PRESENTED` 之前到达**（TagDispatcher 事件顺序错误） | 规则 4.a：`SELECTED_CORRECT` 同时递增 `seen` 和 `correct`；`seen = 1, correct = 1`；公式仍成立（1/1=1.0 >= 0.8）；正常颁星 | TagDispatcher 应按展示→选择顺序发事件；但 VocabStore 设计可容忍乱序 |
| E9 | **`_vocab_data` 中某词缺少字段**（schema 不完整） | 按 GDScript `dict.get(key, default)` 读取；缺失字段视为默认值（`gold_star_count: 0`，`first_star_at: null`，`is_learned: false`）；写入时补填缺失字段 | SaveSystem 迁移（`_migrate_to_v2`）负责在 load 时补填所有字段；此为二次防护 |
| E10 | **首次安装，词汇数据全为默认值** | `_vocab_data["ch1_trex"]["gold_star_count"] = 0`；所有公开查询返回安全默认值；`begin_chapter_session()` 正常重置计数器 | 无需特殊处理；与已有档案流程相同 |

## Dependencies

### 上游依赖（VocabStore 依赖的系统）

| 系统 | 依赖内容 | 契约 |
|------|---------|------|
| **ProfileManager** | `get_section("vocab_progress")` 返回直接引用；`flush()` 持久化；`profile_switch_requested` / `profile_switched` 信号 | 引用在 `profile_switch_requested` 时失效；VocabStore 必须在信号处理器中同步清除引用（无 `await`） |
| **SaveSystem**（间接） | Schema v2 `vocab_progress` 结构（5 词汇键，每键 4 字段） | VocabStore 只通过 ProfileManager 访问；不直接调用 SaveSystem |

### 下游依赖（依赖 VocabStore 的系统）

| 系统 | 调用的 API | 依赖的接口契约 |
|------|-----------|--------------|
| **TagDispatcher** | `record_event(word_id, event_type)` | `EventType` enum 可用；word_id 校验在 VocabStore 内部 |
| **StoryManager** | `begin_chapter_session()` | 每局开始前必须调用；VocabStore 不会自动调用 |
| **InterruptHandler** | `ProfileManager.flush()` → 间接持久化 VocabStore 数据 | 不直接调用 VocabStore；通过 ProfileManager 路由 |
| **ParentVocabMap** | `get_gold_star_count(word_id)`、`get_first_star_at(word_id)`、`is_word_learned(word_id)` | 返回值在无活跃档案时为安全默认值 |
| **PostcardGenerator** | `is_word_learned(word_id)` | 查询只读，不修改状态 |
| **VocabPrimingLoader** | `get_gold_star_count(word_id)` | 查询只读 |

### 信号契约（VocabStore 发出）

| 信号 | 签名 | 接收方 |
|------|------|--------|
| `gold_star_awarded` | `(word_id: String, new_star_count: int)` | ParentVocabMap、HUD 星星动效 |
| `word_learned` | `(word_id: String)` | ParentVocabMap（标记「已认识」徽章） |

## Tuning Knobs

| 旋钮名 | 当前值 | 安全范围 | 影响 |
|--------|--------|---------|------|
| `IS_LEARNED_THRESHOLD` | 3 | 1–5 | 触发 `is_learned = true` 的最低金星数；降低→词汇更容易被标记为已学；升高→更严格但对非高频重播玩家可能永不触发 |
| `STAR_RATIO_THRESHOLD` | 0.8 | 0.5–1.0 | 单局内 correct/seen 最低正确率阈值；MVP 中每词每局仅出现一次，此值实际无意义（等效于必须选对）；未来多次出现场景生效。**权威定义在 `game-concept.md`（entities.yaml 注册常量）；VocabStore 引用，不拥有。** |
| `VOCAB_WORD_IDS_CH1` | 5 词 | 只增不减 | Chapter 1 词汇键集合；修改需同步更新 SaveSystem 迁移函数（`_migrate_to_v2`）和 `_get_default_v2()`。**权威定义在 `save-system.md`（entities.yaml 注册常量）；VocabStore 引用，不拥有。** |

## Visual/Audio Requirements

N/A — VocabStore 是纯后端系统，不直接输出视觉或音频。金星动效由订阅 `gold_star_awarded` 信号的 UI 系统（ParentVocabMap、HUD）负责。

## UI Requirements

N/A — VocabStore 不直接驱动任何 UI 节点。父母词汇地图的渲染（`is_learned` 状态、`gold_star_count` 显示、`first_star_at` 时间戳）由 ParentVocabMap 通过 VocabStore 公开查询接口自行完成。

## Acceptance Criteria

以下所有条目均为可测试的 Pass/Fail 标准，用 GUT 单元测试验证。测试文件位置：`tests/unit/vocab_store/test_vocab_store.gd`

| # | 测试场景 | 期望结果 | 测试类型 |
|---|---------|---------|---------|
| AC-1 | 发出 `PRESENTED` 事件 | `_session_counters[word_id].seen == 1`；`_vocab_data` 不变 | Unit |
| AC-2 | 发出 `SELECTED_CORRECT` 后 `correct/seen >= 0.8` | `gold_star_count += 1`；`gold_star_awarded` 信号发出；`star_awarded == true` | Unit |
| AC-3 | 同一词同一局发出两次 `SELECTED_CORRECT` | `gold_star_count` 只递增一次（`star_awarded` 防重复） | Unit |
| AC-4 | 首次颁星时 `first_star_at` | `first_star_at` 从 `null` 变为非空 UTC 字符串（格式含 "Z" 结尾） | Unit |
| AC-5 | 多次颁星后 `first_star_at` 不覆盖 | 第 2、3 颗星后 `first_star_at` 值与第 1 颗星时相同 | Unit |
| AC-6 | `gold_star_count` 达到 `IS_LEARNED_THRESHOLD`（=3） | `is_learned = true`；`word_learned(word_id)` 信号发出 | Unit |
| AC-7 | `is_learned` 单调性 | `is_learned` 设为 `true` 后，无论后续任何操作均不回退为 `false` | Unit |
| AC-8 | `begin_chapter_session()` 重置计数器 | 调用后 `seen == 0`，`correct == 0`，`star_awarded == false`；`_vocab_data` 不变 | Unit |
| AC-9 | `profile_switch_requested` 同步清除 | 信号发出后（emit 返回前）`_vocab_data == {}`，`_session_counters == {}` | Unit |
| AC-10 | `profile_switched` 重新获取引用 | 信号后 `_vocab_data` 非空；是 ProfileManager 新档案 `vocab_progress` 的直接引用 | Unit |
| AC-11 | 无活跃档案时 `record_event()` | 返回不崩溃；`push_warning` 记录；`_vocab_data` 保持 `{}` | Unit |
| AC-12 | 未知 `word_id` | `record_event("unknown_word", SELECTED_CORRECT)` 不崩溃；`push_error` 记录；无数据修改 | Unit |
| AC-13 | `get_gold_star_count` 无活跃档案 | 返回 `0`（安全默认值）；`push_warning` | Unit |
| AC-14 | `is_word_learned` 无活跃档案 | 返回 `false`（安全默认值）；`push_warning` | Unit |
| AC-15 | `flush` 失败后内存状态保留 | `ProfileManager.flush()` 返回 `false` 时，`gold_star_count` 已递增值保留在内存中 | Unit |
| AC-16 | `NOT_CORRECT` 不改变任何状态 | 发出 `NOT_CORRECT` 后 `seen`、`correct`、`gold_star_count` 均不变 | Unit |
| AC-17 | `end_chapter_session()` 清零计数器 | 调用后所有词汇键 `seen=0, correct=0, star_awarded=false`；`_vocab_data` 持久字段不变；`ProfileManager.flush()` 被调用一次 | Unit |

## Open Questions

1. **`VOCAB_WORD_IDS_CH1` 边界归属**：SaveSystem 迁移函数和 VocabStore 均硬编码 5 个词汇键。两者需保持同步——是否应由 VocabStore 作为词汇键的权威源、SaveSystem 从 VocabStore 读取？（涉及启动顺序问题：SaveSystem 在 `_ready()` 时运行迁移，此时 VocabStore 是否已就绪？）待 TagDispatcher GDD 完成后评估是否拆分此职责。

2. **`IS_LEARNED_THRESHOLD` 时间维度（v2 backlog）**：MVP 不强制跨日期规则。v2 可考虑增加 `learned_at` 字段（首次 `is_learned = true` 的时间戳）并要求第 N 颗星与第 1 颗星跨不同日历日，以更严格地对应艾宾浩斯曲线。需额外 schema 字段，列为 v3 计划。

3. **`begin_chapter_session()` 的幂等性**：若 StoryManager 在章节进行中因故再次调用 `begin_chapter_session()`（如章节重置），计数器将被清零，进行中的颁星资格丢失。是否需要防重调用的标志位？留待 StoryManager GDD 定义调用语义时确认。

4. **词汇全覆盖约束（待 StoryManager/TagDispatcher GDD 承接）**：`is_learned` 依赖 `SELECTED_CORRECT` 事件，若某词在所有可达 Ink 路径中始终只作为错误选项，该词的金星经济结构性不可达。**5 个词汇均须在至少一条玩家可达路径中可作为正确选项被触发**——此约束必须成为 Ink 剧本结构和 TagDispatcher GDD 的验收标准之一（参见 gdd-cross-review-2026-05-06b.md § D-1）。
