# StoryManager

> **Status**: Approved — CD-GDD-ALIGN APPROVED 2026-05-06; end_chapter_session() / TtsBridge dependency declared; inkgd API corrections applied 2026-05-06 (ADR-0001); IH interface patch applied 2026-05-07 (Rule 13/14, current_state, OQ-4 resolved); /design-review RF-1~RF-7 applied 2026-05-07; RF-cross-6 applied 2026-05-07 (TagDispatcher set_vocab_text_map() added to Rule 3c + Interactions table); ChoiceUI patch applied 2026-05-07 (Rule 3b vocab_ch1.json zh field + Rule 5 chinese_text + choices_ready payload); **BLOCK-3f-2 applied 2026-05-08** (GameScene tts_fallback_to_highlight subscriber); **BLOCK-3g-1 applied 2026-05-08** (Rule 15: Ink content authoring constraint)
> **Last Updated**: 2026-05-08
> **Implements Pillar**: P1 (看不见的学习), P2 (失败是另一条好玩的路)

> **架构决策参考**: inkgd vs 自建 JSON 状态机 → ADR-0001-INKGD-RUNTIME (`docs/architecture/adr-0001-inkgd-runtime.md`, Status: Proposed)

## Overview

StoryManager 是游戏叙事引擎的 AutoLoad 单例，封装 inkgd `InkStory` 运行时，将 `.ink` 脚本驱动的章节剧情转化为 GDScript 信号与数据流。它管理章节完整生命周期：`begin_chapter()` 加载故事文件并重置词汇统计，逐帧 `continue_story()` 推进叙事，解析 `current_choices` 供 ChoiceUI 渲染，识别 Ink 故事标签（`#tag`）并通过 TagDispatcher 触发 NPC 动画与 TTS 发音，最终在章节完结（`!story.can_continue && story.current_choices.is_empty()`）时调用 `VocabStore.end_chapter_session()` 结算本局词汇金星。每次 `begin_chapter()` 前，StoryManager 必须先调用 `VocabStore.begin_chapter_session()` 重置本局统计——这是 VocabStore 的强前置约束。

从孩子的视角，不存在"故事系统"——只有他们的点击让 T-Rex 做出好玩的事。无论选对词还是选错词，叙事都继续向前：选对词触发 HAPPY 动画与庆祝 TTS，选错词触发 CONFUSED 动画与同样温暖的 TTS，没有失败画面、没有红叉，只有另一条有趣的路。这是 P2（失败是另一条好玩的路）的技术实现核心。P1（看不见的学习）体现于此：孩子以为自己在推进恐龙冒险，每次选词都是一次词汇接触。

> **架构决策参考**: inkgd vs 自建 JSON 状态机 → ADR-0001-INKGD-RUNTIME (`docs/architecture/adr-0001-inkgd-runtime.md`, Status: Proposed)

## Player Fantasy

T-Rex 停下来，转头，眼睛盯着孩子——它在等一个只有眼前这个孩子才能给的答案。孩子的手指碰下那个词，T-Rex 立刻有动静：庆祝的跳跃，或者歪头蒙圈的夸张表情。蒙圈的动作不是惩罚——是 T-Rex 专为这个孩子上演的小喜剧，孩子会主动想看「如果我点另一个，T-Rex 会演什么？」

这就是这款游戏的核心魔法：不同的词让 T-Rex 做出完全不同的事，两个选项各自控制着一段专属表演。孩子不在意哪个词是「对的」——他们在意的是「我按下去之后，T-Rex 会演什么？」每一次点击后，T-Rex 的眼神都会再次落回孩子身上，准备好迎接下一个触发。

学习发生在这两件事的缝隙里——孩子以为自己在发现 T-Rex 的魔法，实际上他们在用英文词汇驾驭一段叙事。他们不知道这是学习，他们只知道：按下去，有趣的事就发生。

## Detailed Design

### Core Rules

**Rule 1 — AutoLoad 单例身份**
StoryManager 是 GDScript AutoLoad 单例（全局名 `StoryManager`），跨场景持有唯一 `_ink_story` 引用和唯一状态机。同一时刻只能有一个章节处于活跃状态。章节运行时状态不持久化——`story_progress` section 的持久化由 SaveSystem 通过 ProfileManager 负责；StoryManager 在内存中只维护章节进行中的瞬态。

**Rule 2 — `_ready()` 初始化**
- 同步连接 `ProfileManager.profile_switch_requested` 和 `ProfileManager.profile_switched` 信号（严禁 `await`）；持久订阅 `TagDispatcher.tts_not_required` 信号（处理器通过内部 `_waiting_for_advance: bool` 标志判断是否处于等待推进状态，仅在标志为 `true` 时执行 `call_deferred("_advance_step")`）
- 若 ProfileManager 当前已有活跃档案：`_story_data = ProfileManager.get_section("story_progress")`；否则 `_story_data = {}`
- `_ink_story = null`；`_current_chapter_id = ""`；`_vocab_word_texts = {}`；`_vocab_zh_texts = {}`；状态设为 `IDLE`

**Rule 3 — `begin_chapter(chapter_id: String, ink_json_path: String)` — 章节启动入口（四步顺序约束）**

四步执行顺序不可调换：

- a. **前置守卫**：若当前状态不是 `IDLE`，`push_error`，立即返回。若 ProfileManager 无活跃档案（`has_active_profile() == false`），`push_error`，立即返回。

- b. **词汇文字映射加载**：从 `res://assets/data/vocab_ch1.json` 加载词汇数据（格式：`{"ch1_trex": {"en": "T-Rex", "zh": "霸王龙"}, ...}`）。加载成功后派生两个字典：
  - `_vocab_word_texts: Dictionary` = `{word_id: "en_text"}`（英文，供 `warm_cache()` 和 `TagDispatcher.set_vocab_text_map()` 使用）
  - `_vocab_zh_texts: Dictionary` = `{word_id: "zh_text"}`（中文，供 `choices_ready` 的 `chinese_text` 字段使用）
  加载失败 → `push_error`，状态 `ERROR`，立即转 `IDLE` 返回。此文件是 `warm_cache()` 和中文显示的必要前置。

- c. **TtsBridge 预热 + VocabStore 重置 + TagDispatcher 注入**（同帧完成）：
  - 调用 `VocabStore.begin_chapter_session()`（强前置约束：在任何 `continue_story()` 或 `tags_dispatched` 发出之前调用）
  - 对 `VOCAB_WORD_IDS_CH1` 全部 5 词调用 `TtsBridge.warm_cache(word_id, _vocab_word_texts[word_id])`（静默预热，不阻断后续流程）
  - 调用 `TagDispatcher.set_vocab_text_map(_vocab_word_texts)`（为 `record:invite:<word_id>` 标签的 word_text 查询提供映射；步骤 b 成功加载后立即注入）

- d. **InkStory 加载**：状态转为 `LOADING`；保存 `_current_chapter_id = chapter_id`；从 `ink_json_path` 加载已编译的 `.ink.json` 文件（加载模式见 ADR-INKGD-RUNTIME）：
  - 成功 → 状态转为 `RUNNING`；emit `chapter_started(chapter_id: String)`；立即调用 `_advance_step()`
  - 失败 → 状态转为 `ERROR`；emit `chapter_load_failed(chapter_id: String)`；状态立即自动转回 `IDLE`；降级路径由 ADR-INKGD-RUNTIME 定义

**Rule 4 — 单步推进模型（`_advance_step()` 内部方法）**

- a. **守卫**：若当前状态不是 `RUNNING`，忽略调用。

- b. **推进**：调用 `_ink_story.continue_story()`。

- c. **文本发出**：读取 `_ink_story.current_text`（去首尾空白）→ emit `narration_text_ready(text: String)`。

- d. **标签发出**：读取 `_ink_story.current_tags` → emit `tags_dispatched(tags: Array)`。TagDispatcher 订阅此信号并调用 TtsBridge.speak()（若有 vocab 标签）。

- e. **等待推进许可**：`_advance_step()` 在 emit `tags_dispatched` 后挂起，等待下列三个许可信号之一触发，再继续步骤 f（三者竞争，任意一个触发后取消另外两侧等待）：
  - `TtsBridge.speech_completed`（TagDispatcher 已调用 `speak()` 并发音完成）
  - `TagDispatcher.tts_not_required`（本行无 `vocab:` 标签，TagDispatcher 跳过 TTS 直接 emit 此信号）
  - 超时计时器（`NARRATION_WAIT_TIMEOUT_MS`，默认 5000ms）—— 安全兜底，防止故事永久卡住

  **实现约束：**
  - 超时计时器须用 `Timer` 子节点（不用 `get_tree().create_timer()`——后者无 `.stop()` 方法，无法取消）
  - `tts_not_required` 处理器内的 `_advance_step()` 调用须用 `call_deferred("_advance_step")`，防止 GDScript 同步递归栈溢出（多行无 vocab 标签时：tags_dispatched → tts_not_required → _advance_step → tags_dispatched → … 形成同步递归链）
  - 步骤 f 执行前插入 `POST_TTS_PAUSE_MS`（默认 150ms）停顿（见 Tuning Knobs），给孩子处理词汇的感知时间；0 = 无停顿

- f. **分支判断**（在推进许可触发后执行）：优先级为 if / elif / elif，顺序不可调换（choices 优先于 chapter_complete，防止在有选项时误触发章节完成序列）：
  - `if _ink_story.current_choices.size() > 0` → 执行 Rule 5（进入 `CHOICE_PENDING`）
  - `elif !_ink_story.can_continue && _ink_story.current_choices.is_empty()` → 执行 Rule 8（进入 `COMPLETING`）
  - `elif _ink_story.can_continue` → `call_deferred("_advance_step")`（推进下一行；同样用 `call_deferred` 防递归）

**Rule 5 — 选项检测与 CHOICE_PENDING 转换**

- 若 `current_choices.size() > MAX_CHOICES`（MVP = 2）：`push_warning`，仅保留前 `MAX_CHOICES` 个
- 构建 choice 字典列表：`[{index: int, text: String, word_id: String, chinese_text: String}, ...]`（`word_id` 的推导映射见 TagDispatcher GDD；`chinese_text` 来自 `_vocab_zh_texts.get(word_id, "")`，空字符串时 ChoiceUI 隐藏中文 Label）
- emit `choices_ready(choices: Array[Dictionary])`
- 状态转为 `CHOICE_PENDING`；自动推进终止，等待 `submit_choice()`

**Rule 6 — 标签提取与路由**

`current_tags` 原始字符串数组（如 `["anim:HAPPY", "vocab:ch1_trex"]`）通过 `tags_dispatched` 信号整体传递给 TagDispatcher。**StoryManager 不解析标签语义**——解析、分发、调用 AnimationHandler 和 TtsBridge 的职责属于 TagDispatcher。标签格式约定（供 TagDispatcher GDD 参考）：`"<prefix>:<value>"`。

**Rule 7 — `submit_choice(index: int)` — 孩子选词处理**

- 仅在 `CHOICE_PENDING` 状态合法；其他状态 `push_error` 并返回
- 验证 `0 ≤ index < _ink_story.current_choices.size()`；越界 `push_error` 并返回
- 调用 `_ink_story.choose_choice_index(index)`；状态转为 `RUNNING`；立即调用 `_advance_step()`

**Rule 8 — 章节完成序列（RUNNING → COMPLETING → IDLE）**

当 `_advance_step()` 检测到章节结束（`can_continue == false` 且无选项）：

- a. 状态转为 `COMPLETING`
- b. 调用 `VocabStore.end_chapter_session()`（防御性落盘，清零本局计数器）
- c. 更新 `_story_data` 章节完成标记；调用 `ProfileManager.flush()`；emit `chapter_completed(chapter_id: String)`
- d. `_ink_story = null`；`_current_chapter_id = ""`；状态转为 `IDLE`

**Rule 9 — `profile_switch_requested` 同步处理器（严禁 `await`）**

- 取消安全超时计时器（若存在）；断开 `TtsBridge.speech_completed` 的临时连接
- 清理：`_ink_story = null`；`_story_data = {}`；`_vocab_word_texts = {}`；`_vocab_zh_texts = {}`
- **不调用** `VocabStore.end_chapter_session()`——章节被中断，由 InterruptHandler 负责紧急写盘
- emit `chapter_interrupted("profile_switch")`；状态转为 `STOPPED`

**Rule 10 — `profile_switched` 处理器**

重新获取 `_story_data = ProfileManager.get_section("story_progress")`；若当前状态为 `STOPPED` → 转为 `IDLE`。

**Rule 11 — `story_progress` Section 生命周期**

StoryManager 拥有 `"story_progress"` section 写权限。`_story_data` 引用在 `profile_switch_requested` 时清除，在 `profile_switched` 时重新获取（与 VocabStore `_vocab_data` 完全对称）。章节运行期间对 `_story_data` 的写入仅发生在 Rule 8c（章节完成标记）。

**Rule 12 — Chapter 1 MVP 约束**

- 一个 `.ink.json` 文件 = 一个章节；`MAX_CHOICES = 2`（运行时超出时截断并 `push_warning`）
- 全部 5 个 Chapter 1 词汇须在至少一条可达正确答案路径中出现——此为 Ink 剧本创作约束，运行时不验证

**Rule 15 — Ink 内容创作约束（BLOCK-3g-1 修复）**

在 ChoiceUI 呈现目标词汇的选项按钮**之前**，Ink 叙事文本中 T-Rex **不得**流利发音或释义该词汇。即：在包含 `vocab:ch1_xxx` 标签的叙事行（TagDispatcher 会触发 TTS 发音）之前，同一词汇的英文原文不得出现在 `current_text` 中让 T-Rex 朗读，也不得通过旁白释义其含义。

**设计理由**：「我教 T-Rex 英语」是核心玩家幻想（P1）。若 T-Rex 在孩子选词之前已能正确说出目标词汇，教学关系即被颠覆——孩子从「老师」降级为「复述者」，核心幻想崩溃。

**约束边界**：
- T-Rex **可以**在选词前使用目标词汇的**中文**（如「这个动物叫什么？」），因为中文提示不破坏英文教学幻想
- T-Rex **可以**在选词后（`vocab:ch1_xxx:correct` 标签触发后）流利发音，这是教学成功的正向反馈
- 此约束为 Ink 剧本创作规则，**运行时不验证**；违反此约束不会导致程序崩溃，但会破坏核心设计意图

**验证方式**：Ink 脚本 code review checklist 必包含此项检查。

**Rule 13 — `request_chapter_interrupt(reason: String)` — InterruptHandler 调用的中断入口**

InterruptHandler 在检测到 `app_background`（Home 键 / 来电 / 锁屏）或 `user_back_button`（物理返回键 / Android 10+ 手势返回）中断后调用此方法，使 StoryManager 停止推进并发出 `chapter_interrupted` 信号。

- 仅在 `is_story_active == true` 时执行（即状态为 `RUNNING` 或 `CHOICE_PENDING`）；`LOADING` 和 `COMPLETING` 不视为活跃（IH GDD Rule 3 权威定义）——否则立即返回，不做任何处理
- 执行顺序（同帧同步完成，严禁 `await`）：
  1. 取消安全超时计时器（若存在）；断开 `TtsBridge.speech_completed` 临时连接；断开 `TagDispatcher.tts_not_required` 临时连接（若通过内部标志管理则清除标志）
  2. `_ink_story = null`；`_vocab_word_texts = {}`；`_vocab_zh_texts = {}`（**保留** `_story_data` 引用——紧急 flush 由 IH 触发 `ProfileManager.flush()` 完成，此时写盘需引用有效）
  3. 状态转为 `STOPPED`（**必须在 emit 之前**——防止 IH 在 `chapter_interrupted` 处理器内查询 `is_story_active` 时仍返回 `true`，导致重入中断逻辑）
  4. emit `chapter_interrupted(reason)`（IH 订阅此信号后执行紧急 flush）
- `_story_data` 在此不清除：防止信号处理链中 flush 时引用失效；清除在 `confirm_navigation_complete()` 或 `profile_switched` 处理时执行
- `VocabStore.end_chapter_session()` 不调用（与 Rule 9 行为一致——中断路径不结算词汇金星）

**Rule 14 — `confirm_navigation_complete()` — 中断后 SM 重置至 IDLE**

两种合法调用场景：

1. **`user_back_button` 导航完成后**：IH 在场景切换到 MainMenu 完成后调用，让 SM 从 `STOPPED` 转为 `IDLE`（以便下次 `begin_chapter()` 可正常进入）
2. **FOCUS_IN 恢复路径（进程存活）**：App 回前台时，IH 检测到 `!is_story_active && current_state == State.STOPPED`（说明此前中断了正在进行的章节但进程未被杀死），调用此方法重置 SM；GameScene 随后负责展示恢复 UI（如「章节已中断，重新开始？」）

执行逻辑：
- 若当前状态 != `STOPPED`：`push_warning` 并返回（防误调用）
- `_story_data = {}`；`_current_chapter_id = ""`（清除残留引用）
- `if ProfileManager.has_active_profile(): _story_data = ProfileManager.get_section("story_progress")`（若无活跃档案则保持 `{}`，防止 null 引用）
- 状态转为 `IDLE`

---

### States and Transitions

| 状态 | 触发进入 | 此状态下的系统行为 | 合法下一状态 |
|------|---------|-----------------|------------|
| `IDLE` | 初始化 / 章节完成 / 档案切换完成 / 加载失败自恢复 | `_ink_story = null`；等待 `begin_chapter()` 调用 | `LOADING` |
| `LOADING` | `begin_chapter()` 从 IDLE 调用 | VocabStore + TtsBridge 预热已执行；InkStory 加载中 | `RUNNING`（成功）/ `ERROR`（失败）/ `STOPPED`（档案切换） |
| `RUNNING` | 加载成功 / `submit_choice()` 后 | `_advance_step()` 循环；每步 emit `narration_text_ready` + `tags_dispatched`；等待 `speech_completed` 后检测分支 | `CHOICE_PENDING`（有选项）/ `COMPLETING`（章节结束）/ `STOPPED`（档案切换） |
| `CHOICE_PENDING` | `_advance_step()` 检测到选项 | `choices_ready` 已发出；等待 `submit_choice()` | `RUNNING`（`submit_choice()` 成功）/ `STOPPED`（档案切换） |
| `COMPLETING` | 章节结束检测 | `end_chapter_session()` + flush + 信号序列（同步瞬态） | `IDLE`（同步完成即转） |
| `STOPPED` | `profile_switch_requested` 中断 / `request_chapter_interrupt()` 调用 | 推进已停止；ink 引用已清除；等待 `profile_switched` 或 `confirm_navigation_complete()` | `IDLE`（`profile_switched` 收到 / `confirm_navigation_complete()` 调用） |
| `ERROR` | InkStory 或 JSON 文件加载失败 | `chapter_load_failed` 信号发出；立即自动转回 | `IDLE`（自动，同帧） |

**状态转换图：**
```
IDLE ─── begin_chapter() ──► LOADING
LOADING ─── load_ok ──► RUNNING
LOADING ─── load_fail ──► ERROR ─── (auto) ──► IDLE
LOADING / RUNNING / CHOICE_PENDING ─── profile_switch_requested ──► STOPPED
RUNNING / CHOICE_PENDING ─── request_chapter_interrupt() ──► STOPPED
RUNNING ─── choices_detected ──► CHOICE_PENDING
RUNNING ─── chapter_end ──► COMPLETING ─── (sync) ──► IDLE
CHOICE_PENDING ─── submit_choice() ──► RUNNING
STOPPED ─── profile_switched ──► IDLE
STOPPED ─── confirm_navigation_complete() ──► IDLE
```

---

### Interactions with Other Systems

| 系统 | 方向 | 接口 | 数据 | 时机 |
|------|------|------|------|------|
| **VocabStore** | SM → 调用 | `begin_chapter_session()` | 无参数 | `begin_chapter()` 步骤 c，首次 `continue_story()` 之前 |
| **VocabStore** | SM → 调用 | `end_chapter_session()` | 无参数 | 章节正常完结（Rule 8b） |
| **TtsBridge** | SM → 调用 | `warm_cache(word_id, text)` | word_id + 英文文字（来自 `res://assets/data/vocab_ch1.json`） | `begin_chapter()` 步骤 c，5 词循环 |
| **TtsBridge** | (信号) → SM | `speech_completed(word_id: String)` | 已发音的 word_id | 每步推进后等待；SM 收到后继续 Rule 4f 分支判断 |
| **ProfileManager** | SM → 调用 | `get_section("story_progress")` | 返回 Dictionary 直接引用 | `_ready()` 初始化；`profile_switched` 后重新获取 |
| **ProfileManager** | SM → 调用 | `flush()` | 无参数 | 章节完结写盘（Rule 8c） |
| **ProfileManager** | (信号) → SM | `profile_switch_requested(new_index: int)` | 目标档案 index | 同步处理器：停止推进、清除引用、emit `chapter_interrupted` |
| **ProfileManager** | (信号) → SM | `profile_switched(new_index: int)` | 新档案 index | 重新获取 `_story_data` 引用，状态 STOPPED → IDLE |
| **TagDispatcher** | SM → 调用 | `set_vocab_text_map(map: Dictionary)` | `_vocab_word_texts`（词汇 ID→文字映射） | `begin_chapter()` 步骤 c，词汇文字映射加载（步骤 b）成功后立即注入 |
| **TagDispatcher** | SM → (信号) | `tags_dispatched(tags: Array)` | inkgd `current_tags` 原始数组 | 每次 `continue_story()` 后（Rule 4d） |
| **TagDispatcher** | (信号) → SM | `tts_not_required()` | 无参数 | 本叙事行无 `vocab:` 标签时，TagDispatcher 跳过 TTS 直接 emit；SM 订阅后 `call_deferred("_advance_step")` 继续推进（Rule 4e） |
| **ChoiceUI** | SM → (信号) | `choices_ready(choices: Array[Dictionary])` | `[{index, text, word_id, chinese_text}, ...]` | `_advance_step()` 检测到选项后（Rule 5） |
| **ChoiceUI** | ChoiceUI → SM 调用 | `submit_choice(index: int)` | 所选 choice index | 孩子点击词汇图标时 |
| **MainMenu** | MainMenu → SM 调用 | `begin_chapter(chapter_id, ink_json_path)` | 章节 ID + Ink 文件路径 | 孩子点击「出发冒险！」 |
| **InterruptHandler** | (信号) → IH | `chapter_interrupted(reason: String)` | `"profile_switch"` / `"app_background"` / `"user_back_button"` | 任何中断场景 |
| **InterruptHandler** | IH → SM 调用 | `request_chapter_interrupt(reason: String)` | `"app_background"` / `"user_back_button"` | IH 检测到平台中断事件后，主动触发 SM 停止推进并发出 `chapter_interrupted` |
| **InterruptHandler** | IH → SM 调用 | `confirm_navigation_complete()` | 无参数 | user_back_button 路径场景切换完成后；或 FOCUS_IN 时 SM 处于 STOPPED 状态（进程存活） |
| **InterruptHandler** | IH 查询 SM | `current_chapter_id: String`（只读属性） | 活跃章节 ID；无活跃时 `""` | App 后台时查询 |
| **InterruptHandler** | IH 查询 SM | `current_state: State`（只读属性） | 当前状态枚举值（`State.IDLE / RUNNING / STOPPED ...`） | FOCUS_IN 时判断是否需要调用 `confirm_navigation_complete()` |

## Formulas

### Chapter Completion Detection

```
chapter_complete =
    (_ink_story.can_continue == false)
    AND (_ink_story.current_choices.size() == 0)
```

| 变量 | 类型 | 含义 |
|------|------|------|
| `can_continue` | bool | inkgd：当前节点还有文本可以推进 |
| `current_choices.size()` | int | inkgd：当前节点的选项数量（0 = 无选项） |

**输出**：`bool`。为 `true` 时触发 Rule 8 章节完成序列。

---

### story_progress Section Schema（写入 ProfileManager）

```json
{
  "completed_chapters": ["chapter_1"],
  "last_played_chapter": "chapter_1",
  "last_played_at": "2026-05-06T10:00:00Z"
}
```

| 字段 | 类型 | 写入时机 | 说明 |
|------|------|---------|------|
| `completed_chapters` | `Array[String]` | Rule 8c，章节正常完结后 | 记录已完成的章节 ID；重复完结不重复追加 |
| `last_played_chapter` | `String` | Rule 8c，每次完结覆盖 | 供 MainMenu 展示「继续」入口 |
| `last_played_at` | `String`（UTC ISO 8601 + "Z"） | Rule 8c，每次完结覆盖 | 格式与 SaveSystem 统一：`Time.get_datetime_string_from_system(true) + "Z"` |

---

### vocab_ch1.json 文件格式（词汇文字映射）

StoryManager 在 `begin_chapter()` 步骤 b 加载此文件，派生出英文映射（供 `warm_cache()`）和中文映射（供 `choices_ready` 的 `chinese_text` 字段）：

```json
{
  "ch1_trex": {"en": "T-Rex", "zh": "霸王龙"},
  "ch1_triceratops": {"en": "Triceratops", "zh": "三角龙"},
  "ch1_eat": {"en": "Eat", "zh": "吃"},
  "ch1_run": {"en": "Run", "zh": "跑"},
  "ch1_big": {"en": "Big", "zh": "大"}
}
```

键集合必须与 `VOCAB_WORD_IDS_CH1` 常量一致；键增减需同步更新此文件。

## Edge Cases

| # | 边界情况 | StoryManager 行为 | 调用方职责 |
|---|---------|-----------------|-----------|
| E1 | **`begin_chapter()` 在非 IDLE 状态被调用**（如章节进行中再次调用） | `push_error`，立即返回；状态机不变；正在进行的章节继续 | MainMenu 调用前检查 `is_story_active()`（只读属性，等价于 `_state != IDLE`）；不应在非 IDLE 时调用 |
| E2 | **`vocab_ch1.json` 加载失败**（文件不存在或 JSON 解析错误） | `push_error`，状态转 `ERROR` 后立即自转 `IDLE`；emit `chapter_load_failed(chapter_id)`；VocabStore.begin_chapter_session() 未调用 | MainMenu 订阅 `chapter_load_failed` 信号处理 UI 提示；工程 CI 必须验证此文件存在 |
| E3 | **InkStory 加载失败**（`.ink.json` 文件不存在或格式错误） | `push_error`，状态转 `ERROR` 后立即自转 `IDLE`；emit `chapter_load_failed(chapter_id)`；降级路径见 ADR-INKGD-RUNTIME。**注**：`VocabStore.begin_chapter_session()` 已在步骤 c 调用（计数器已重置）；加载失败时不调用 `end_chapter_session()`（无词汇进度需结算）；下次 `begin_chapter()` 成功时 `begin_chapter_session()` 再次初始化，无数据损坏 | ADR-INKGD-RUNTIME 定义是否尝试 JSON 自建状态机降级；StoryManager 不内置降级逻辑 |
| E4 | **`submit_choice()` 在非 CHOICE_PENDING 状态调用**（如 ChoiceUI 双击） | `push_error`，立即返回；状态机不变 | ChoiceUI 在发出 `choices_ready` 后禁用按钮直到收到下一次 `choices_ready` 或 `chapter_completed` |
| E5 | **`submit_choice(index)` 越界**（index < 0 或 >= choices.size()） | `push_error`，立即返回；状态机不变；不调用 inkgd `choose_choice_index()` | ChoiceUI 按 `choices_ready` 提供的 index 值构建按钮，不应产生越界 index |
| E6 | **Ink 选项数超过 `MAX_CHOICES`（= 2）** | `push_warning`，截断至前 2 个选项；`choices_ready` 仅包含截断后的选项 | Ink 剧本创作约束：每个选择节点最多 2 个选项；验收测试须覆盖此约束 |
| E7 | **`TtsBridge.speech_completed` 永不触发**（TtsBridge 崩溃或 TagDispatcher 未调用 speak()） | `NARRATION_WAIT_TIMEOUT_MS` 计时器超时（默认 5000ms）→ 继续 Rule 4f 分支判断；叙事正常推进 | 超时为安全兜底，不应成为正常路径；TtsBridge 和 TagDispatcher GDD 须确保 speak() 调用覆盖所有有 vocab 标签的行 |
| E8 | **档案切换打断 CHOICE_PENDING 状态** | Rule 9 同步处理器：`_ink_story = null`；emit `chapter_interrupted("profile_switch")`；状态 → `STOPPED` | ChoiceUI 订阅 `chapter_interrupted` 信号以隐藏选词按钮；InterruptHandler 处理写盘 |
| E9 | **章节中途 App 后台**（screen-off、来电或系统通知遮挡） | InterruptHandler 检测到 `app_background` 事件后调用 `request_chapter_interrupt("app_background")`（Rule 13）；SM 同步停止推进（状态 → `STOPPED`）并 emit `chapter_interrupted("app_background")`；IH 订阅后执行 `ProfileManager.flush()` 紧急写盘；App 回前台时 IH 检测 `current_state == STOPPED` → 调用 `confirm_navigation_complete()`（Rule 14）→ SM 重置为 `IDLE`；GameScene 展示「章节已中断，重新开始？」UI | InterruptHandler GDD Rule 4/5 定义完整恢复策略；StoryManager 仅负责停止推进与状态重置；章节进度不保存（`end_chapter_session()` 不调用） |
| E10 | **inkgd 故事在加载后立即结束**（首次 continue_story() 后 can_continue == false） | `_advance_step()` 检测 → 立即触发 Rule 8 章节完成序列 | Ink 剧本须包含实质内容；验收测试须验证 Chapter 1 至少包含 5 个词汇选择节点 |
| E11 | **重复完成同一章节**（孩子重播再次完结） | Rule 8c：追加前检查 `completed_chapters` 是否已含该 ID，若已存在则跳过追加（幂等）；`last_played_at` 正常覆盖 | VocabStore 词汇金星计数继续累积；重播是有效玩法路径 |
| E12 | **ProfileManager 无活跃档案时调用 `begin_chapter()`** | Rule 3a 守卫：`push_error`，立即返回；不进入 LOADING 状态 | GameRoot 确保在有活跃档案后才路由到游戏场景；HatchScene + NameInputScreen 是前置条件 |

## Dependencies

### 上游依赖（StoryManager 依赖的系统）

| 系统 | 依赖内容 | 契约 |
|------|---------|------|
| **ProfileManager** | `get_section("story_progress")` 直接引用；`flush()`；`profile_switch_requested` / `profile_switched` 信号 | 引用在 `profile_switch_requested` 时失效；同步处理器严禁 `await`（ProfileManager Core Rule 8） |
| **VocabStore** | `begin_chapter_session()`；`end_chapter_session()` | `begin_chapter_session()` 在任何 `continue_story()` 之前调用（强前置约束）；`end_chapter_session()` 仅在章节正常完结时调用 |
| **TtsBridge** | `warm_cache(word_id, text)`；`speech_completed` 信号 | `warm_cache()` 不改变 TtsBridge 状态机；`speech_completed` 每步等待（Rule 4e），安全超时为兜底 |
| **TagDispatcher** | `tts_not_required()` 信号（持久订阅） | 无 `vocab:` 标签行时代替 `speech_completed` 作为推进许可；SM 处理器内须用 `call_deferred("_advance_step")` 防止同步递归 |
| **SaveSystem**（间接） | `story_progress` schema v2 兼容性 | StoryManager 不直接调用 SaveSystem；通过 ProfileManager 读写 `story_progress` section |
| **inkgd v0.6.0**（godot4 分支） | `InkStory` 运行时：`continue_story()`、`current_choices`、`choose_choice_index()`、`current_tags`、`can_continue` | 加载模式和 API 稳定性见 ADR-INKGD-RUNTIME；必须使用 `godot4` 分支（非 `main` 分支） |
| **Godot FileAccess** | `res://assets/data/vocab_ch1.json` 读取 | 文件必须在每次 `begin_chapter()` 调用时可访问；CI 须验证文件存在 |

### 下游依赖（依赖 StoryManager 的系统）

| 系统 | 调用的 API | 依赖的接口契约 |
|------|-----------|--------------|
| **TagDispatcher** | 订阅 `tags_dispatched(tags: Array)` | 收到原始标签数组后解析语义；StoryManager 不解析标签含义 |
| **ChoiceUI** | 订阅 `choices_ready(choices: Array[Dictionary])`；调用 `submit_choice(index: int)` | `choices_ready` 中的 `index` 字段必须原样传回 `submit_choice()`；ChoiceUI 须在收到 `choices_ready` 后禁用按钮直到下次信号 |
| **MainMenu** | 调用 `begin_chapter(chapter_id, ink_json_path)`；查询 `is_story_active: bool` | 仅在 `is_story_active == false` 时调用 `begin_chapter()` |
| **InterruptHandler** | 订阅 `chapter_interrupted(reason: String)`；调用 `request_chapter_interrupt(reason: String)`；调用 `confirm_navigation_complete()`；查询 `current_chapter_id: String`；查询 `current_state: State` | 收到信号后执行紧急 `ProfileManager.flush()`；主动触发中断序列；恢复时重置 SM 至 IDLE |
| **GameScene** | 订阅 `TtsBridge.tts_fallback_to_highlight(word_id: String, text: String)` | **BLOCK-3f-2 修复**：Tier 3 TTS 降级路径（无网络/无 API Key 的中国 Android 设备）必须有订阅者。GameScene 收到此信号后须对 ChoiceUI 中对应词汇按钮执行视觉高亮反馈，否则孩子在 Tier 3 降级时既无音频也无视觉反馈，体验静默降至零反馈 |

### 信号契约（StoryManager 发出）

| 信号 | 签名 | 接收方 |
|------|------|--------|
| `chapter_started` | `(chapter_id: String)` | MainMenu（隐藏入口 UI） |
| `chapter_completed` | `(chapter_id: String)` | MainMenu（展示完结画面 / 星星动效入口） |
| `chapter_interrupted` | `(reason: String)` | InterruptHandler、ChoiceUI |
| `chapter_load_failed` | `(chapter_id: String)` | MainMenu（显示错误提示） |
| `narration_text_ready` | `(text: String)` | 叙事文本 UI（当前 MVP 可无订阅者，预留） |
| `tags_dispatched` | `(tags: Array[String])` | TagDispatcher（必须订阅） |
| `choices_ready` | `(choices: Array[Dictionary])` — payload: `[{index: int, text: String, word_id: String, chinese_text: String}, ...]` | ChoiceUI（必须订阅） |

## Tuning Knobs

| 旋钮名 | 当前值 | 安全范围 | 影响 |
|--------|--------|---------|------|
| `MAX_CHOICES` | 2 | 1–5 | 每个选择节点最多显示的选项数；超出时截断并 `push_warning`。MVP = 2（正确词 / 错误词二选一）；扩展章节可调至 3–4 |
| `NARRATION_WAIT_TIMEOUT_MS` | 5000 | 2000–10000 | `TtsBridge.speech_completed` 未触发时的安全超时（毫秒）；超时后叙事继续推进，防止故事永久卡住。值过小导致 TTS 未完成就推进；值过大导致 TTS 故障时孩子长时间等待 |
| `POST_TTS_PAUSE_MS` | 150 | 0–500 | `speech_completed` 或 `tts_not_required` 触发后、执行 Rule 4f 分支判断前的额外停顿（毫秒）。0 = 无停顿（紧凑节奏）；100–200 = 轻微呼吸感，给 4 岁孩子词汇处理缓冲；原型测试后调整（见 Rule 4e） |

## Visual/Audio Requirements

N/A — StoryManager 是纯后端叙事引擎，不直接输出视觉或音频。

- 视觉输出由 AnimationHandler（NPC 动画）和 ChoiceUI（选词按钮）负责，均通过 TagDispatcher 信号驱动
- 音频输出由 TtsBridge 负责，由 TagDispatcher 解析 `vocab:` 标签后触发
- `narration_text_ready(text)` 信号预留给叙事文本 UI（MVP 可不实现订阅方）

## UI Requirements

N/A — StoryManager 不直接驱动任何 UI 节点。

- ChoiceUI 通过订阅 `choices_ready` 信号渲染选词按钮（ChoiceUI GDD 定义 UI 规格）
- MainMenu 通过调用 `begin_chapter()` 和订阅 `chapter_completed` / `chapter_load_failed` 信号管理入口 UI（MainMenu GDD 定义 UI 规格）

## Acceptance Criteria

以下所有条目均为可测试的 Pass/Fail 标准，用 GUT 单元测试验证。
测试文件：`tests/unit/story_manager/test_story_manager.gd`
依赖 Mock：InkStory（inkgd）、VocabStore、TtsBridge、ProfileManager

### Group 1：状态机生命周期

| # | 测试场景 | 期望结果 | 类型 |
|---|---------|---------|------|
| AC-01 | `begin_chapter()` 且两个文件均加载成功 | 状态依次 `IDLE → LOADING → RUNNING`；emit `chapter_started(chapter_id)` | Unit |
| AC-02 | `vocab_ch1.json` 路径无效或解析失败 | 状态 `ERROR → IDLE`；emit `chapter_load_failed(chapter_id)`（含正确 chapter_id）；不 emit `chapter_started` | Unit |
| AC-03 | `.ink.json` 路径无效或 InkStory 构造失败 | 状态 `ERROR → IDLE`；emit `chapter_load_failed(chapter_id)` | Unit |
| AC-04 | Ink 故事正常走到末尾 | 状态依次 `RUNNING → COMPLETING → IDLE`；emit `chapter_completed(chapter_id)` | Unit |
| AC-05 | `_advance_step()` 时 Ink 节点检测到 choices | 状态 `RUNNING → CHOICE_PENDING`；emit `choices_ready(choices)` | Unit |
| AC-06 | `CHOICE_PENDING` 时调用 `submit_choice(valid_index)` | 状态 `CHOICE_PENDING → RUNNING`；`_ink_story.choose_choice_index(valid_index)` 被调用恰好一次；`_advance_step()` 随后被调用 | Unit |
| AC-07 | 非 IDLE 状态调用 `begin_chapter()` | 忽略调用；状态不变；不 emit 任何信号 | Unit |
| AC-08 | 查询 `is_story_active` | RUNNING / CHOICE_PENDING → `true`；IDLE / LOADING / COMPLETING / STOPPED / ERROR → `false` | Unit |

### Group 2：VocabStore 集成

| # | 测试场景 | 期望结果 | 类型 |
|---|---------|---------|------|
| AC-09 | `begin_chapter()` 触发加载流程 | `VocabStore.begin_chapter_session()` 在第一次 `continue_story()` 之前被调用恰好一次 | Unit |
| AC-10 | 章节正常完结（COMPLETING → IDLE） | `VocabStore.end_chapter_session()` 被调用恰好一次 | Unit |
| AC-11 | 章节中途 `profile_switch_requested` 触发 | `VocabStore.end_chapter_session()` 不被调用 | Unit |
| AC-12 | 章节开始阶段（LOADING → RUNNING） | `TtsBridge.warm_cache()` 对全部 5 个 `VOCAB_WORD_IDS_CH1` 词汇 ID 各调用一次，不多不少 | Unit |

### Group 3：TTS 等待行为

| # | 测试场景 | 期望结果 | 类型 |
|---|---------|---------|------|
| AC-13 | Mock TtsBridge 正常 emit `speech_completed` | `_advance_step()` 在 `tags_dispatched` 后暂停；`speech_completed` 触发后继续推进 | Unit |
| AC-14 | `speech_completed` 在 `NARRATION_WAIT_TIMEOUT_MS` 内始终未触发（Mock Timer 注入 timeout = 1ms） | 超时后 `_advance_step()` 被调用；状态不为 `ERROR`；测试在 2 帧内完成（无无限等待） | Unit |
| AC-15 | `speech_completed` 触发（`POST_TTS_PAUSE_MS = 0`） | 无额外延迟即推进下一步 | Unit |
| AC-16 | 每次 `continue_story()` 后信号发出顺序 | 先 emit `narration_text_ready`，再 emit `tags_dispatched`，均在进入 TTS 等待阶段之前完成 | Unit |

### Group 4：选项处理

| # | 测试场景 | 期望结果 | 类型 |
|---|---------|---------|------|
| AC-17 | `CHOICE_PENDING` 时调用 `submit_choice(0)` | `choose_choice_index(0)` 被调用；状态 → RUNNING；故事继续 | Unit |
| AC-18 | `submit_choice(index)` 越界（`>= choices.size()`） | `push_error()`；状态保持 CHOICE_PENDING；`choose_choice_index` 不被调用 | Unit |
| AC-19 | 非 CHOICE_PENDING 状态调用 `submit_choice()` | `push_error()`；状态不变；故事不推进 | Unit |
| AC-20 | Ink 节点返回 3 个选项（超过 `MAX_CHOICES = 2`） | `choices_ready` 的 `choices` 数组长度为 2；多余选项被截断 | Unit |

### Group 5：profile_switch_requested 处理

| # | 测试场景 | 期望结果 | 类型 |
|---|---------|---------|------|
| AC-21 | 章节进行中 `profile_switch_requested` 触发 | 处理函数同帧内同步完成（无 `await`）；GUT 验证：emit 信号后立即断言 `_current_state == State.STOPPED`（不经 `await get_tree().process_frame`），断言通过即证明同帧完成 | Unit |
| AC-22 | `profile_switch_requested` 处理函数执行后 | `_ink_story == null`；`_story_data` 已清空（`{}`) | Unit |
| AC-23 | `profile_switch_requested` 处理函数执行后 | emit `chapter_interrupted("profile_switch")`；状态 → STOPPED | Unit |
| AC-24 | STOPPED 状态下 `profile_switched` 触发后 | `VocabStore.end_chapter_session()` 不被调用；状态 → IDLE；`_story_data` 持有新档案引用 | Unit |

### Group 6：边界情形

| # | 测试场景 | 期望结果 | 类型 |
|---|---------|---------|------|
| AC-25 | 无活跃档案时调用 `begin_chapter()` | `push_error()`；状态保持 IDLE；不 emit 任何信号 | Unit |
| AC-26 | 同一 chapter_id 被连续完成两次 | `story_progress.completed_chapters` 中该 ID 只出现一条（幂等） | Integration |
| AC-27 | 章节正常完成后写入 `story_progress` | 包含 `completed_chapters`（Array）、`last_played_chapter`（String）、`last_played_at`（UTC 字符串）三个字段，值与章节匹配 | Integration |
| AC-28 | 章节正常走到末尾（未中断） | `chapter_interrupted` 信号不被 emit | Unit |

### Group 7：request_chapter_interrupt / confirm_navigation_complete（Rule 13/14）

| # | 测试场景 | 期望结果 | 类型 |
|---|---------|---------|------|
| AC-29 | `request_chapter_interrupt("app_background")` 在 `RUNNING` 状态调用 | 状态 → `STOPPED`；emit `chapter_interrupted("app_background")`；`_ink_story == null` | Unit |
| AC-30 | `request_chapter_interrupt("user_back_button")` 在 `CHOICE_PENDING` 状态调用 | 状态 → `STOPPED`；emit `chapter_interrupted("user_back_button")`；超时 Timer 已停止 | Unit |
| AC-31 | `request_chapter_interrupt()` 在 `IDLE` 状态调用 | 立即返回；状态保持 `IDLE`；无信号 emit；`is_story_active == false` | Unit |
| AC-32 | `request_chapter_interrupt()` 在 `LOADING` 状态调用 | 立即返回（`is_story_active == false`）；状态保持 `LOADING`；无信号 emit | Unit |
| AC-33 | `request_chapter_interrupt()` 步骤顺序：信号发出时状态已为 STOPPED | IH 的 `chapter_interrupted` 处理器内调用 `StoryManager.is_story_active` → 返回 `false`（状态已先于 emit 转为 STOPPED） | Unit |
| AC-34 | `confirm_navigation_complete()` 在 `STOPPED` 状态调用（ProfileManager 有活跃档案） | 状态 → `IDLE`；`_story_data` 重新获取（`!= {}`）；`_current_chapter_id == ""` | Unit |
| AC-35 | `confirm_navigation_complete()` 在非 `STOPPED` 状态调用 | `push_warning()` 被调用；状态不变 | Unit |
| AC-36 | `request_chapter_interrupt()` 执行后 `_story_data` 保留 | `_story_data` 引用未被清除（ProfileManager 有活跃档案时 `!= {}`）；`_ink_story == null`；`_vocab_word_texts` 已清空 | Unit |

## Open Questions

1. ~~**ADR-INKGD-RUNTIME（待创建）**：inkgd `InkStory` 加载 API 确认、Android APK 打包稳定性、JSON 降级状态机触发条件。~~ ✅ **RESOLVED 2026-05-06** — ADR-0001 已创建：`docs/architecture/adr-0001-inkgd-runtime.md`。加载序列：`load()` → `InkResource` → `InkStory.new(res.json, runtime)`；完成检测：`!story.can_continue && story.current_choices.is_empty()`；Week 1 Android 门控定义。

2. ~~**choices_ready word_id 推导方案**：Rule 5 构建 choice 字典时需要 `word_id`，来源未确定。~~ ✅ **RESOLVED 2026-05-06 (TagDispatcher GDD)** — 方案 B：StoryManager 从 `InkChoice.tags` 直接提取（取第一个以 `vocab:` 开头的 3 段式标签的 parts[1]，如 `"vocab:ch1_trex:correct"` → `"ch1_trex"`）。TagDispatcher 不参与选项路由。

3. ~~**非 vocab 叙事行的 TTS 行为**：当 Ink 叙事节点无 `vocab:` 标签时，`speech_completed` 不触发，StoryManager 将命中 5000ms 超时。~~ ✅ **RESOLVED 2026-05-06 (TagDispatcher GDD)** — TagDispatcher 在批次无 2 段式 `vocab:` 标签时 emit `tts_not_required()` 信号；StoryManager 订阅后跳过超时等待，立即继续 Rule 4f 分支判断。

4. ~~**`chapter_interrupted("app_background"/"user_back_button")` 触发者**：这两个 reason 目前在信号签名中声明，但发出者不明确。需在 InterruptHandler GDD 中确认：InterruptHandler 调用 StoryManager 某方法主动触发，还是 StoryManager 订阅 InterruptHandler 信号后自发出 `chapter_interrupted`？~~ ✅ **RESOLVED 2026-05-07 (InterruptHandler GDD)** — IH 调用 `StoryManager.request_chapter_interrupt(reason)` → SM 内部停止推进并 emit `chapter_interrupted(reason)` → IH 订阅该信号后执行 `ProfileManager.flush()`。由 SM 发出信号，IH 被动接收。

5. **`story_progress` schema v2 初始化**：SaveSystem `_migrate_to_v2` 是否预填 `story_progress` section 初始字段？若不预填，StoryManager 在写入 `completed_chapters` 等字段前需做缺失字段检查。需在 StoryManager 实现时确认 SaveSystem 迁移的 section 初始化行为。
