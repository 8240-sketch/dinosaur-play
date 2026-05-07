# /design-review Report — TagDispatcher

> **Date**: 2026-05-07
> **GDD**: `design/gdd/tag-dispatcher.md`
> **Verdict**: **NEEDS REVISION** — 3 阻断问题，4 重要问题，必须全部应用后重新评审
> **Prior Status**: Approved 2026-05-06 (CD-GDD-ALIGN)
> **Reviewers**: game-designer · systems-designer · qa-lead · creative-director (synthesis)

---

## Verdict Summary

TagDispatcher 的核心架构设计正确：AutoLoad 单例、Ink 标签驱动分发、与 AnimationHandler 的非 AutoLoad 实例注入机制、tts_not_required 信号解决 StoryManager OQ-3。

**但存在 3 个阻断性缺陷，必须在实现启动前修复**：

| 编号 | 严重程度 | 归属文件 | 问题摘要 |
|------|---------|---------|---------|
| C-1 | 🔴 阻断 | AnimationHandler GDD | Interactions 表将 play_happy/confused 触发时机写为 SELECTED_CORRECT/NOT_CORRECT，与 TagDispatcher Core Rule 8（P2 保护）直接矛盾 |
| C-2 | 🔴 阻断 | TagDispatcher GDD | VALID_ANIM_STATES 包含 `hatch_emerge` 和 `recording_listen`——AnimationHandler 无对应 `play_()` 方法→运行时崩溃 |
| C-3 | 🔴 阻断 | TagDispatcher GDD | `record:invite` 标签的 word_id 推导机制完全未定义——信号 `recording_invite_triggered(word_id, word_text)` 的 word_id 来源不明；AC-6/AC-7 无法编写为 GUT 测试 |

---

## 阻断问题详情

### C-1：AnimationHandler GDD Interactions 表违反 P2

**来源**：game-designer Issue 1 / creative-director CRITICAL-1

AnimationHandler GDD（当前批准状态）Interactions 表：

| 调用方 | 调用方法 | 时机 |
|--------|---------|------|
| TagDispatcher | `play_happy()` | **`SELECTED_CORRECT` 事件** |
| TagDispatcher | `play_confused()` | **`NOT_CORRECT` 事件** |

这与 TagDispatcher Core Rule 8（"不向展示层传播对/错，只执行 Ink 给出的 anim: 指令"）直接矛盾。开发者先实现 AnimationHandler 时会从 Interactions 表出发，在 AnimationHandler 内部建立 `SELECTED_CORRECT → play_happy()` 耦合，P2 在第一天就被破坏。

**修复（RF-1 归属 AnimationHandler GDD）**：将 Interactions 表时机列改为：
- `play_happy()` ← "TagDispatcher 收到 `anim:happy` Ink 标签时"
- `play_confused()` ← "TagDispatcher 收到 `anim:confused` Ink 标签时"

---

### C-2：VALID_ANIM_STATES 包含不存在的公开方法 → 运行时崩溃

**来源**：systems-designer Issue 1 / creative-director CRITICAL-2

当前 VALID_ANIM_STATES：
```
["happy", "confused", "story_advance", "idle", "hatch_crack", 
 "hatch_emerge", "recording_listen", "ending_wave"]
```

对照 AnimationHandler 公开 API：

| VALID_ANIM_STATES 值 | play_() 存在？ | 说明 |
|---|---|---|
| `hatch_emerge` | **不存在** | 由 hatch_crack 动画完成后自动触发，无公开方法 |
| `recording_listen` | **不存在** | 由 recording_invite 动画完成后自动进入，无公开方法 |
| `hatch_idle` | 存在但未列入 | `play_hatch_idle()` 有效 |
| `menu_idle` | 存在但未列入 | `play_menu_idle()` 有效 |
| `recording_invite` | 存在但未列入 | `play_recording_invite()` 有效 |

Ink 作者若写 `# anim:hatch_emerge`，TagDispatcher 调用 `_animation_handler.play_hatch_emerge()` → GDScript 运行时报错。

**修复（RF-2 归属 TagDispatcher GDD）**：重写 VALID_ANIM_STATES 为：
```
["happy", "confused", "story_advance", "idle", "hatch_crack", 
 "hatch_idle", "menu_idle", "recording_invite", "ending_wave"]
```

---

### C-3：`record:invite` word_id 推导机制未定义

**来源**：systems-designer Issues 2+3 / qa-lead Issue 1 / creative-director CRITICAL-3

- 标签格式：`record:invite`（2 段式，无 word_id 字段）
- 信号签名：`recording_invite_triggered(word_id: String, word_text: String)`
- GDD 仅在 E3 说"从 map 查词填充 payload"，但从未说明 word_id 的来源

这不是文档模糊，而是机制根本未定义。AC-6（record:invite 触发信号）和 AC-7（word_text 从 map 查找）在 word_id 来源不明时无法编写为 GUT 测试。

**修复（RF-3 归属 TagDispatcher GDD）**：改为 3 段式格式 `record:invite:word_id`（推荐，creative-director 裁定）：
- parse_tag 算法：3 段 record 类型提取 `parts[2]` 为 word_id
- 更新 Core Rule 5（tag 词汇表）
- 更新 E3（edge case 描述）
- 更新 AC-6/AC-7（期望结果可明确验证）

---

## 重要问题（不阻断，同轮次修复）

### S-1：AC-13 的 P2 路径测试强度不足

**来源**：game-designer Issue 2 / qa-lead Issue 2 / creative-director SIGNIFICANT-4

现有 AC-13 验证"dispatch 逻辑无额外 if-branch"（对称性），但无法防止未来在 TagDispatcher 之外建立 correct/incorrect → animation 的耦合。

**修复（RF-4 归属 TagDispatcher GDD）**：新增 AC-13b：
> 给定批次 `[vocab:ch1_trex:not_correct, anim:happy]`，验证 `play_happy()` 被调用（not_correct 结果不抑制、不重定向 anim:happy 标签执行）。

---

### S-2：缺失关键测试场景 AC

**来源**：qa-lead Issues 4-7 / creative-director SIGNIFICANT-5

**修复（RF-5 归属 TagDispatcher GDD）**：新增 AC：

| AC 编号 | 测试场景 | 期望结果 |
|---------|---------|---------|
| AC-N1 | 混合 2+3 段 vocab 批次（PRESENTED + SELECTED_CORRECT 同批次）| 2 段触发 TTS；3 段触发 VocabStore.record_event(SELECTED_CORRECT)；两者均执行 |
| AC-N2 | `vocab:` 空 word_id 标签 | push_error；TtsBridge 不调用；VocabStore 不调用 |
| AC-N3 | `anim:` 非法 state（修复 C-2 后）| push_error；AnimationHandler 不调用；无崩溃 |
| AC-N4 | 4 段式标签（如 `vocab:ch1_trex:correct:extra`）| push_warning；走 UNKNOWN_TAG 降级路径 |

---

### S-3：StoryManager GDD 缺少 set_vocab_text_map() 文档

**来源**：review 分析阶段发现 / creative-director DEFERRED-7 (提前修复)

TagDispatcher Rule 6 指定 `StoryManager.begin_chapter()` 调用 `TagDispatcher.set_vocab_text_map(map)`，但 StoryManager GDD 的 Interactions 表和 begin_chapter() Core Rules 均未记录此调用。

**修复（RF-6 归属 StoryManager GDD）**：
- Interactions 表增加一行：`TagDispatcher | set_vocab_text_map(map) | begin_chapter() Step b 之后`
- begin_chapter() Core Rules（步骤 c）补充：`TagDispatcher.set_vocab_text_map(vocab_map)`

---

## 延后处理（可推至实现阶段）

| # | 问题 | 归属 |
|---|------|------|
| D-1 | 大写标签前缀（`Vocab:word_id`）被静默跳过，约束未文档化 | TagDispatcher GDD |
| D-2 | 4 段式标签暴露 word_id 不含冒号的隐式约束，未文档化 | TagDispatcher GDD |
| D-3 | TtsBridge.speak() 失败 → speech_completed 永不触发 → StoryManager 挂起 | StoryManager / TtsBridge GDD 范围，非 TagDispatcher |
| D-4 | TTS 与动画时序未同步（SM 等待 speech_completed 不等待 animation_completed）| StoryManager GDD 范围 |

---

## 跨 GDD 修复汇总

| RF | 修复内容 | 归属文件 |
|----|---------|---------|
| RF-1 | Interactions 表：play_happy/confused 触发时机改为 anim: Ink 标签 | animation-handler.md |
| RF-2 | VALID_ANIM_STATES 精确对应 AnimationHandler 公开 API | tag-dispatcher.md |
| RF-3 | record:invite 改为 3 段式 `record:invite:word_id`；更新 parse_tag、E3、AC-6/AC-7 | tag-dispatcher.md |
| RF-4 | 新增 AC-13b（P2 路径测试） | tag-dispatcher.md |
| RF-5 | 新增 AC-N1~N4（混合批次、空 word_id、非法 anim state、4 段式）| tag-dispatcher.md |
| RF-6 | begin_chapter() 文档补充 set_vocab_text_map() 调用 | story-manager.md |

---

## InterruptHandler 解锁状态

TagDispatcher ↔ InterruptHandler 无直接依赖。InterruptHandler GDD 可立即进入 `/design-review` 评审，TagDispatcher 修复工作并行进行。**InterruptHandler 评审不需要等待本次修复。**

---

## 修复验证标准

修复完成后，以下条件须全部满足：

1. VALID_ANIM_STATES 中每个 state 都能在 AnimationHandler GDD 找到对应的 `play_<state>()` 方法
2. `record:invite:word_id` 格式使 AC-6/AC-7 可独立写为 GUT 测试，无批次顺序依赖
3. AnimationHandler GDD Interactions 表：TagDispatcher 触发 play_happy/confused 的时机描述与 TagDispatcher Core Rule 8 完全一致
4. StoryManager GDD begin_chapter() 步骤包含 `set_vocab_text_map()` 调用记录
