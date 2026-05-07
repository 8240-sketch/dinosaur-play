# TagDispatcher

> **Status**: Approved — CD-GDD-ALIGN APPROVED 2026-05-06; Core Rule 8 P2 Anti-Pillar 表述精确化; /design-review fixes applied 2026-05-07 (RF-1~RF-5: VALID_ANIM_STATES corrected, record:invite→3-segment format, AC-13b + AC-N1~N4 added)
> **Author**: Zhang Shaocong + agents
> **Last Updated**: 2026-05-07
> **Implements Pillar**: P1 (看不见的学习), P2 (失败是另一条好玩的路)

## Overview

TagDispatcher 是 Ink 叙事事件的翻译层和中央分发总线。它订阅 StoryManager 的 `tags_dispatched(tags: Array[String])` 信号，将 inkgd 原始标签字符串（格式：`"prefix:value"` 或 `"prefix:value:result"`）解析为具体系统调用：`anim:<state>` 标签触发 `AnimationHandler` 的语义方法（`play_happy()`、`play_confused()` 等）；2 段式 `vocab:<word_id>` 标签触发 `TtsBridge.speak()` 发音并调用 `VocabStore.record_event(PRESENTED)`；3 段式 `vocab:<word_id>:correct` / `vocab:<word_id>:not_correct` 标签（出现在孩子选词后的叙事继续中）调用 `VocabStore.record_event(SELECTED_CORRECT)` 或 `VocabStore.record_event(NOT_CORRECT)`；`record:invite:<word_id>` 标签通过 `recording_invite_triggered(word_id, word_text)` 信号通知 RecordingInviteUI。

choices_ready payload 中的 `word_id` 字段由 StoryManager 从 `InkChoice.tags` 直接提取，不经 TagDispatcher；ChoiceUI 直接订阅 `StoryManager.choices_ready`。

从玩家视角，TagDispatcher 是隐形的：孩子触碰一个词，T-Rex 立刻跳起来或者歪头蒙圈，那个词从 T-Rex 嘴里说出来——整个反应链发生在一帧之内，而 TagDispatcher 是把 Ink 故事标签变成这一切的枢纽。P1（看不见的学习）和 P2（失败是另一条好玩的路）的落地，依赖于 TagDispatcher 对 `anim:happy` 和 `anim:confused` 的无差别执行：它不判断哪条路是"对的"，只执行 Ink 脚本给出的指令——对/错的语义完全封装在 `.ink` 文件中，TagDispatcher 不感知也不传播这种区分。

TagDispatcher 还解决 StoryManager 的一个开放问题：当前叙事行无 2 段式 `vocab:` 标签时，emit `tts_not_required()` 信号通知 StoryManager 跳过 5000ms TTS 等待。TagDispatcher 是 AutoLoad 单例。

## Player Fantasy

孩子的指尖落下的那一帧：T-Rex 跳起来（或歪头蒙圈），那个词从 T-Rex 嘴里说出来，词汇进度悄然记录——整条反应链发生在一次点击之内，而 TagDispatcher 是让 Ink 标签变成这一切的枢纽。孩子感受不到它，感受到的是恐龙的欢呼或蒙圈。P1 和 P2 的成立，都依赖 TagDispatcher 的无差别执行：`anim:happy` 和 `anim:confused` 照单全收，它不判断选词是对是错，只执行 Ink 给出的指令。对/错的语义封装在 `.ink` 脚本里；让失败变好笑，是 Ink 作者的职责，不是 TagDispatcher 的判断。TagDispatcher 本身没有玩家幻想；它是让所有幻想同步发生的那一帧。

## Detailed Design

### Core Rules

1. **AutoLoad 单例**：`_ready()` 中连接 `StoryManager.tags_dispatched(tags: Array[String])` 信号。

2. **AnimationHandler 注册协议**：持有 `_animation_handler` 引用（初始 `null`）。场景 `_ready()` 调用 `TagDispatcher.set_animation_handler(self)`，`_exit_tree()` 调用 `TagDispatcher.set_animation_handler(null)`。每次调用前执行 `is_instance_valid(_animation_handler)` 防护；防护失败 `push_warning`，跳过但不中断批次。

3. **标签词汇表（Tag Vocabulary）**：

| 格式 | 示例 | 行为 |
|------|------|------|
| `vocab:<word_id>` | `vocab:ch1_trex` | `TtsBridge.speak(word_id)` + `VocabStore.record_event(word_id, PRESENTED)` |
| `vocab:<word_id>:correct` | `vocab:ch1_trex:correct` | `VocabStore.record_event(word_id, SELECTED_CORRECT)` |
| `vocab:<word_id>:not_correct` | `vocab:ch1_trex:not_correct` | `VocabStore.record_event(word_id, NOT_CORRECT)` |
| `anim:<state>` | `anim:happy` | `_animation_handler.play_<state>()` (is_instance_valid 防护) |
| `record:invite:<word_id>` | `record:invite:ch1_trex` | emit `recording_invite_triggered(word_id, word_text)`；word_id 直接从标签第三段提取，word_text 从 `_vocab_text_map[word_id]` 查询 |
| 其他格式 | — | `push_warning`，跳过；不中断批次 |

4. **批次处理与 tts_not_required**：按数组顺序处理所有标签。整个批次处理完毕后，若未发现任何 2 段式 `vocab:` 标签，emit `tts_not_required()` 通知 StoryManager 跳过 5000ms TTS 等待。

5. **word_id 推导（choices_ready）**：choices_ready payload 中的 word_id 由 StoryManager 从 `InkChoice.tags` 直接提取，TagDispatcher 不参与选项路由。ChoiceUI 直接订阅 `StoryManager.choices_ready`，不经 TagDispatcher。

6. **vocab_text_map**：StoryManager 在 `begin_chapter()` 调用 `TagDispatcher.set_vocab_text_map(map: Dictionary)` 注入词汇 ID→文字映射（来自 `assets/data/vocab_ch1.json`）。`record:invite` 处理时从此 map 查词填充 `recording_invite_triggered` payload。章节结束时 StoryManager 调用 `set_vocab_text_map({})` 清除。

7. **VocabStore 写入契约**：直接调用 `VocabStore.record_event(word_id, event_type)`（两者均 AutoLoad）。不通过信号路由。

8. **不向展示层传播对/错（P2 Anti-Pillar 保护）**：TagDispatcher 不向展示层（动画 / TTS / UI）传播对/错区分——`anim:happy` 和 `anim:confused` 照单全收，无条件分支。`vocab:correct` / `vocab:not_correct` 标签映射为 VocabStore 的中性学习数据（`SELECTED_CORRECT` / `NOT_CORRECT`）；Anti-P2-b（禁止负面计分统计）的执行责任在 VocabStore GDD，不在 TagDispatcher。**跨文档约束**：AnimationHandler GDD 的 Interactions 表须声明 `play_happy()` 和 `play_confused()` 由 `anim:happy` / `anim:confused` Ink 标签驱动，而非由选词结果（SELECTED_CORRECT / NOT_CORRECT）驱动——这是 P2 保护的文档锚点，防止开发者从 AnimationHandler GDD 出发实现时建立错误的 correct→happy 耦合。

### States and Transitions

TagDispatcher 无状态机，持有两个可变引用：

| 引用 | 初始值 | 变更时机 |
|------|--------|---------|
| `_animation_handler` | `null` | `set_animation_handler()` 注册/清除 |
| `_vocab_text_map` | `{}` | `set_vocab_text_map()` 注入/清除 |

| `_animation_handler` 状态 | `anim:` 标签行为 |
|--------------------------|----------------|
| `null` | `push_warning`，跳过 |
| 有效实例（`is_instance_valid == true`） | 正常调用语义方法 |
| 已失效（场景已卸载） | `is_instance_valid` 防护触发，同 null |

### Interactions with Other Systems

| 系统 | 方向 | 交互内容 | 时机 |
|------|------|---------|------|
| **StoryManager** | 接收信号 | 订阅 `tags_dispatched(tags: Array[String])` | 每次叙事行推进时 |
| **StoryManager** | 发出信号 | emit `tts_not_required()` | 批次无 2 段式 `vocab:` 标签时 |
| **AnimationHandler** | 直接方法调用（注册后） | `play_happy()` / `play_confused()` / `play_story_advance()` 等 | `anim:` 标签时 |
| **TtsBridge** | 直接方法调用 | `TtsBridge.speak(word_id)` | 2 段式 `vocab:<word_id>` 标签时 |
| **VocabStore** | 直接方法调用 | `VocabStore.record_event(word_id, event_type)` | 每个 `vocab:` 标签时 |
| **RecordingInviteUI** | 发出信号 | `recording_invite_triggered(word_id: String, word_text: String)` | `record:invite` 标签时 |
| **ChoiceUI** | 无直接交互 | ChoiceUI 订阅 StoryManager.choices_ready（不经 TagDispatcher） | — |

## Formulas

TagDispatcher 无数值公式，但标签解析逻辑可形式化：

### 标签解析算法

```
parse_tag(raw: String) -> TagAction:
    parts = raw.split(":")
    match parts.size():
        2:
            if parts[0] == "vocab"  → VOCAB_PRESENT(word_id=parts[1])
            if parts[0] == "anim"   → ANIM(state=parts[1])
            else → UNKNOWN_TAG(push_warning)
        3:
            if parts[0] == "vocab" and parts[2] == "correct"     → VOCAB_CORRECT(word_id=parts[1])
            if parts[0] == "vocab" and parts[2] == "not_correct" → VOCAB_NOT_CORRECT(word_id=parts[1])
            if parts[0] == "record" and parts[1] == "invite"     → RECORD_INVITE(word_id=parts[2])
            else → UNKNOWN_TAG(push_warning)
        _ → UNKNOWN_TAG(push_warning)
```

### 批次 tts_not_required 判定

```
has_vocab_present(batch: Array[String]) -> bool:
    return batch.any(λ tag: tag.split(":").size() == 2 and tag.begins_with("vocab:"))

处理完整批次后：
if NOT has_vocab_present(tags_batch):
    emit tts_not_required()
```

## Edge Cases

| # | 边界情况 | TagDispatcher 行为 | 调用方职责 |
|---|---------|-------------------|-----------|
| E1 | **`_animation_handler` 为 null 时收到 `anim:` 标签** | `is_instance_valid` 防护：`push_warning`，跳过；不中断批次 | 场景须在 `_ready()` 注册 AnimationHandler；TagDispatcher 容错不崩溃 |
| E2 | **场景卸载后未调用 `set_animation_handler(null)`** | `is_instance_valid` 检查旧引用为 false → 同 E1 处理 | 场景须在 `_exit_tree()` 清除；即使忘记，TagDispatcher 也不会崩溃 |
| E3 | **`vocab_text_map` 为空或不含该 word_id 时收到 `record:invite:<word_id>`** | word_id 直接从标签提取（不受 map 影响）；`word_text = _vocab_text_map.get(word_id, "")`；emit `recording_invite_triggered(word_id, "")` — word_text 为空字符串；`push_warning` | StoryManager 须在 `begin_chapter()` 步骤 c 后调用 `set_vocab_text_map()`；RecordingInviteUI 须容忍空字符串 |
| E4 | **未知 `anim:` 状态**（如 `anim:fly`，AnimationHandler 不支持） | 调用 `_animation_handler.play_fly()`；若方法不存在 GDScript 报错；TagDispatcher 不额外处理 | AnimationHandler 须为所有词汇表内 state 定义 `play_<state>()` 方法；Ink 作者只使用已定义 state |
| E5 | **同一批次多个 2 段式 `vocab:` 标签**（理论上 Ink 作者失误） | 逐一处理：每个均触发 `TtsBridge.speak()` + PRESENTED；TtsBridge 新 speak() 中断前一个发音 | Ink 作者须保证每行至多一个 2 段式 vocab: 标签；TagDispatcher 不做重复检测 |
| E6 | **`vocab:<word_id>:correct` 在无 PRESENTED 之前到达** | 直接调用 `VocabStore.record_event(word_id, SELECTED_CORRECT)`；VocabStore 规则 4.a 可容忍乱序 | 正常 Ink 流程先出现 2 段式 PRESENTED 再出现 3 段式 SELECTED；TagDispatcher 容错不崩溃 |
| E7 | **`tags_dispatched` 空数组** | 遍历为空，无任何系统调用；仍触发 tts_not_required 判定（has_vocab_present == false → emit tts_not_required） | 纯文本叙事行无标签时 StoryManager 可能发出空数组，属正常情况 |
| E8 | **未知 word_id**（不在 `VOCAB_WORD_IDS_CH1`） | TagDispatcher 直接透传给 VocabStore；VocabStore 内部 `push_error` 并返回；TtsBridge.speak() 若无缓存则降级 | Ink 作者须只使用词汇表内的 word_id；TagDispatcher 不做前置校验 |

## Dependencies

### 上游依赖（TagDispatcher 依赖的系统）

| 系统 | 依赖内容 | 契约 |
|------|---------|------|
| **StoryManager** | `tags_dispatched(tags: Array[String])` 信号 | TagDispatcher 在 `_ready()` 连接；StoryManager 是 AutoLoad，连接保证成功 |
| **AnimationHandler** | `play_happy()` / `play_confused()` 等语义方法 | 非 AutoLoad；须通过 `set_animation_handler()` 注册；调用前 `is_instance_valid` 防护 |
| **TtsBridge** | `speak(word_id: String)` | AutoLoad；直接调用 |
| **VocabStore** | `record_event(word_id: String, event_type: EventType)` | AutoLoad；直接调用；word_id 校验在 VocabStore 内部 |

### 下游依赖（依赖 TagDispatcher 的系统）

| 系统 | 依赖内容 | 依赖接口 |
|------|---------|---------|
| **StoryManager** | 订阅 `tts_not_required()` 信号 | TagDispatcher 在批次无 2 段式 vocab: 时 emit |
| **RecordingInviteUI** | 订阅 `recording_invite_triggered(word_id, word_text)` 信号 | TagDispatcher 在 `record:invite` 标签时 emit |
| **GameScene（NPC 所在场景）** | 注册/注销 AnimationHandler | 场景 `_ready()` 调用 `set_animation_handler(self)`；`_exit_tree()` 清除 |

*ChoiceUI 依赖 StoryManager（不依赖 TagDispatcher）。InterruptHandler 不直接依赖 TagDispatcher。*

### 信号契约（TagDispatcher 发出）

| 信号 | 签名 | 接收方 |
|------|------|--------|
| `tts_not_required` | `()` | StoryManager（跳过 5000ms TTS 等待） |
| `recording_invite_triggered` | `(word_id: String, word_text: String)` | RecordingInviteUI |

## Tuning Knobs

TagDispatcher 自身无数值旋钮，但持有两个可配置的词汇表常量：

| 旋钮名 | 当前值 | 安全范围 | 影响 |
|--------|--------|---------|------|
| `VALID_ANIM_STATES` | `["happy", "confused", "story_advance", "idle", "hatch_crack", "hatch_idle", "menu_idle", "recording_invite", "ending_wave"]` | 与 AnimationHandler `play_<state>()` 公开方法精确同步（`hatch_emerge` 和 `recording_listen` 由链式动画自动触发，无对应公开方法） | 可用于 `anim:` state 前置校验；不校验则由 AnimationHandler 方法缺失时报错 |
| **标签格式版本（隐式）** | 2 段式 `"prefix:value"` / 3 段式 `"prefix:value:result"` | 与 `.ink` 文件作者约定一致 | 格式变更须同步更新 parse_tag 算法和所有 `.ink` 脚本 |

*注：TtsBridge 的 speak() 行为旋钮、VocabStore 的阈值常量均属各自系统管辖。TagDispatcher 不拥有这些值。*

## Visual/Audio Requirements

N/A — TagDispatcher 是纯信号分发层，不直接输出视觉或音频。视觉反应由 AnimationHandler 负责；音频由 TtsBridge 负责。

## UI Requirements

N/A — TagDispatcher 不驱动任何 UI 节点。RecordingInviteUI 的显示由 RecordingInviteUI 自身响应 `recording_invite_triggered` 信号完成；TagDispatcher 不直接操作 UI。

## Acceptance Criteria

以下所有条目均为可测试的 Pass/Fail 标准，用 GUT 单元测试验证。测试文件位置：`tests/unit/tag_dispatcher/test_tag_dispatcher.gd`

| # | 测试场景 | 期望结果 | 测试类型 |
|---|---------|---------|---------|
| AC-1 | 发出 `vocab:ch1_trex`（2 段式） | `TtsBridge.speak("ch1_trex")` 被调用；`VocabStore.record_event("ch1_trex", PRESENTED)` 被调用 | Unit |
| AC-2 | 发出 `vocab:ch1_trex:correct`（3 段式） | `VocabStore.record_event("ch1_trex", SELECTED_CORRECT)` 被调用；TtsBridge.speak 不被调用 | Unit |
| AC-3 | 发出 `vocab:ch1_trex:not_correct`（3 段式） | `VocabStore.record_event("ch1_trex", NOT_CORRECT)` 被调用；TtsBridge.speak 不被调用 | Unit |
| AC-4 | 发出 `anim:happy`，AnimationHandler 已注册 | `_animation_handler.play_happy()` 被调用 | Unit |
| AC-5 | 发出 `anim:confused`，AnimationHandler 未注册（null） | `push_warning` 记录；play_confused() 不被调用；无崩溃 | Unit |
| AC-6 | 发出 `record:invite:ch1_trex`，vocab_text_map 已注入 | `recording_invite_triggered("ch1_trex", "<词汇文字>")` 信号发出（word_id 直接来自标签第三段） | Unit |
| AC-7 | 发出 `record:invite:ch1_trex`，vocab_text_map 为空 | `recording_invite_triggered("ch1_trex", "")` 发出（word_id 仍正确提取）；`push_warning` 记录 | Unit |
| AC-8 | 批次含 1 个 2 段式 `vocab:` 标签 | 处理完毕后 `tts_not_required` 信号**不**发出 | Unit |
| AC-9 | 批次无任何 2 段式 `vocab:` 标签（含 3 段式或仅 `anim:`） | 处理完毕后 `tts_not_required` 信号发出 | Unit |
| AC-10 | 空数组批次 | `tts_not_required` 发出；无任何系统调用；无崩溃 | Unit |
| AC-11 | 未知标签格式（如 `"unknown_prefix:xyz"`） | `push_warning` 记录；不中断批次后续标签处理 | Unit |
| AC-12 | AnimationHandler 注册后场景卸载（引用失效） | `is_instance_valid` 防护触发：`push_warning`，不崩溃 | Unit |
| AC-13 | `anim:confused` 与 `anim:happy` 处理对称性 | 两者均执行对应 AnimationHandler 方法，无任何额外判断或拦截（P2 Anti-Pillar 验证） | Unit |
| AC-13b | 批次 `[vocab:ch1_trex:not_correct, anim:happy]` 处理 | `play_happy()` 被调用；NOT_CORRECT 结果不抑制、不重定向 `anim:happy` 标签执行（P2 运行时路径验证） | Unit |
| AC-14 | 同一批次多个不同标签 | 每个均独立执行，顺序与数组一致；无标签被跳过 | Unit |
| AC-N1 | 混合 2+3 段 vocab 批次：`[vocab:ch1_trex, vocab:ch1_trex:correct]` | `TtsBridge.speak("ch1_trex")` 被调用（2 段）；`VocabStore.record_event("ch1_trex", SELECTED_CORRECT)` 被调用（3 段）；两者均执行；`tts_not_required` 信号不发出 | Unit |
| AC-N2 | 2 段式 `vocab:` 空 word_id（即字面量 `"vocab:"`） | `push_error` 记录；`TtsBridge.speak()` 不被调用；`VocabStore.record_event()` 不被调用；批次继续处理后续标签 | Unit |
| AC-N3 | `anim:` 非法 state（不在 VALID_ANIM_STATES 中，如 `anim:hatch_emerge`） | `push_error` 记录；AnimationHandler 方法不被调用；无崩溃；批次继续处理后续标签 | Unit |
| AC-N4 | 4 段式标签（如 `vocab:ch1_trex:correct:extra`） | `push_warning` 记录；走 UNKNOWN_TAG 降级路径；`VocabStore.record_event()` 不被调用 | Unit |

## Open Questions

1. **StoryManager GDD word_id 协议补充**：TagDispatcher GDD 确认了 choices_ready word_id 由 StoryManager 从 `InkChoice.tags` 直接提取（方案 B），但 StoryManager GDD 的 OQ-2 标注为「待 TagDispatcher GDD 定义」。需在 StoryManager GDD 中补充 Ink choice 标签格式（`vocab:<word_id>:correct`）和提取逻辑（取 `choice.tags` 中第一个以 `vocab:` 开头的 3 段式标签的 parts[1]）。

2. **VALID_ANIM_STATES 前置校验**：当前设计不做前置校验（`anim:fly` 类未知 state 由 AnimationHandler 方法缺失时报错）。是否在 TagDispatcher 层加一次 `push_error` + 跳过以便更早捕获 Ink 作者笔误？留待实现时决定。

3. **词汇可达性（Ink 剧本结构约束）**：`VOCAB_WORD_IDS_CH1` 中每个词汇须在至少一条可达 Ink 路径中作为正确选项出现（否则该词的金星结构性不可达）。此约束须成为 Chapter 1 剧本定稿前的验收标准，由 TagDispatcher 实现者和 Ink 作者联合确认（参见 VocabStore OQ-4）。

4. **ADR-INKGD-RUNTIME（TagDispatcher 实现前必须创建）**：TagDispatcher 依赖 StoryManager 的 `tags_dispatched` 信号，而 StoryManager 依赖 inkgd InkStory 在 Android APK 下的稳定性。ADR 未创建前，TagDispatcher 实现不应开始。创建路径：`/architecture-decision`。
