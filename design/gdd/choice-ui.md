# ChoiceUI

> **Status**: Complete — Awaiting /design-review
> **Author**: Zhang Shaocong + agents
> **Last Updated**: 2026-05-07
> **Implements Pillar**: P1 (Invisible Learning), P2 (Failure is Fun)

## Overview

ChoiceUI 是 MVP 核心循环中孩子唯一的主动输入界面。每当 StoryManager 发出 `choices_ready` 信号，ChoiceUI 在屏幕底部弹出两个并排的词汇卡片按钮；孩子点击任意一个，ChoiceUI 调用 `StoryManager.submit_choice(index)` 推进剧情。每张卡片展示一张图标（至少占按钮面积 60%）、粗体英文单词（20sp）和浅色中文译文（10sp）。按钮符合 80dp 最小高度、44–46% 屏幕宽度规范，确保 4–6 岁孩子可以可靠点击。ChoiceUI 同时订阅 `TtsBridge.tts_fallback_to_highlight`，在 AI TTS 降级时对匹配词汇按钮播放 600ms 脉冲高亮动画。本系统不携带任何「对/错」视觉判断——选择结果仅通过 T-Rex 动画和剧情推进传达，与 P2 Anti-Pillar 完全一致。

## Player Fantasy

孩子的手指悬在两张词汇卡片上方的那一刻，他们面对的不是一道题——他们握着两把咒文按钮，等待决定让 T-Rex 做什么。

**施法者的即时权能感**：按下卡片的瞬间不是「我选了正确答案」，而是「*是我让它动起来的*」。T-Rex 的 HAPPY 扑腾是这条咒文成功的视觉证明；CONFUSED 是「咒文没对上」的喜剧，孩子的本能反应是捂嘴笑而非沮丧——因为那不是失败，那是一个更好笑的结果。两条路都是孩子选的，两条路都在孩子掌握之中。

**P2 天然成立**：CONFUSED 路径在施法框架里是「效果不对，哈哈」，而不是「你错了」。孩子不需要被告知「失败没关系」，因为施法者从不认为自己失败——他们只是在测试不同的咒文。

六个月后的真实时刻：孩子拉着弟弟在 T-Rex 面前演示——「你按这个，它就跑！」他们记住的是那个单词和 T-Rex 奔跑之间的绑定，是身体动作记忆（*我按了，它动了*），而不是背诵。这是 P1「看不见的学习」的实体化：语言知识被孩子存储为「我做了一件有趣的事情」。

## Detailed Design

### Core Rules

**Rule 1 — 场景归属**：ChoiceUI 是 GameScene 持有的子节点场景，不是 AutoLoad。每次 GameScene 实例化时一同加载，生命周期跟随 GameScene。

**Rule 2 — 状态机**：ChoiceUI 维护内部 3 态枚举：
```gdscript
enum State { HIDDEN, WAITING, SUBMITTED }
var _state: State = State.HIDDEN
```
所有外部事件入口开头必须 guard 状态，防止乱序调用。

**Rule 3 — 信号连接**：在 `_ready()` 中连接（AutoLoad 保证先于普通节点就绪）：
- `StoryManager.choices_ready.connect(_on_choices_ready)`
- `TtsBridge.tts_fallback_to_highlight.connect(_on_tts_fallback)`
- `StoryManager.chapter_interrupted.connect(_on_chapter_interrupted)`

所有按钮的 `focus_mode = Control.FOCUS_NONE`（Godot 4.6 双焦点系统隔离）。

**Rule 4 — choices_ready 处理**：
1. Guard：`if _state != State.HIDDEN: push_warning(...); return`
2. Guard：`if choices.size() > 2: push_warning(...); choices = choices.slice(0, 2)`
3. 按 choices 数组顺序填充两个按钮：icon（word_id 对应图片），英文文字（text），中文译文（chinese_text）
4. 每个按钮的 `pivot_offset = btn.size / 2.0`（NOTIFICATION_RESIZED 时更新，保证缩放以中心为原点）
5. 淡入（modulate.a: 0 → 1，0.15s），`show()`
6. `_state = State.WAITING`

**Rule 5 — 按钮点击处理**：
1. Guard：`if _state != State.WAITING: return`
2. 若 `_pulse_tween` 正在播放：`_pulse_tween.kill()`
3. `StoryManager.submit_choice(choice.index)` — 调用上游；不等回调
4. `_state = State.SUBMITTED`
5. 淡出（modulate.a: 1 → 0，0.15s），完成后 `hide()`

ChoiceUI 提交后立即消失；T-Rex 的动画反应由 TagDispatcher/AnimationHandler 处理，ChoiceUI 不持有「正确/错误」状态（P2 Anti-Pillar）。

**Rule 6 — tts_fallback_to_highlight 处理**：
1. Guard：`if _state != State.WAITING: return`
2. 遍历两个按钮找到 `word_id` 匹配项；未找到则 `push_warning` 并 return
3. 对匹配按钮：若 `_pulse_tween` 活跃则 kill；创建新 Tween：scale 1.0→1.10（0.15s）→ hold（0.15s）→ scale 1.10→1.0（0.30s），总计 600ms = HIGHLIGHT_DISPLAY_MS
4. 脉冲仅为视觉效果，不改变触摸热区，不禁用交互

**Rule 7 — chapter_interrupted 处理**：
1. Kill `_pulse_tween` 若活跃
2. `_state = State.HIDDEN`；`hide()` 无动画（立即）
3. 不调用 `submit_choice`——chapter_interrupted 的流程由 InterruptHandler 负责

**Rule 8 — P2 Anti-Pillar 合规**：
- 两个按钮在视觉上完全相同（形状、颜色、字体）；区别仅在内容
- ChoiceUI 不感知「哪个是正确选项」，不在提交后显示任何对/错反馈
- 禁止：红色高亮、✗ 图标、shake 动画、错误提示文字

### States and Transitions

| 状态 | 进入动作 | 退出条件 | 退出目标 |
|------|----------|----------|----------|
| HIDDEN | `hide()`；所有 tween kill | `choices_ready` 且 _state==HIDDEN | WAITING |
| WAITING | 淡入；按钮启用 | 玩家点击按钮 | SUBMITTED |
| WAITING | — | `chapter_interrupted` | HIDDEN（立即） |
| SUBMITTED | `submit_choice()` 已调用；淡出 | 淡出动画完成 | HIDDEN |

### Interactions with Other Systems

| 系统 | 方向 | 接口 |
|------|------|------|
| StoryManager | ChoiceUI 订阅 | `choices_ready(choices: Array[Dictionary])` — payload `[{index: int, text: String, word_id: String, chinese_text: String}]` |
| StoryManager | ChoiceUI 调用 | `submit_choice(index: int)` |
| StoryManager | ChoiceUI 订阅 | `chapter_interrupted(reason: String)` — 触发立即 hide |
| TtsBridge | ChoiceUI 订阅 | `tts_fallback_to_highlight(word_id: String)` — 触发匹配按钮脉冲 |
| GameScene | GameScene 持有 | GameScene 实例化 ChoiceUI；ChoiceUI 无反向引用 |
| TagDispatcher | 无直接交互 | ChoiceUI 不订阅 TagDispatcher 任何信号；recording_invite_triggered 由 RecordingInviteUI 订阅 |

## Formulas

### F-1 — 高亮脉冲时序约束

TtsBridge Tier 3 降级时触发高亮脉冲动画。三段时长之和**必须精确等于** `HIGHLIGHT_DISPLAY_MS`，保证 `speech_completed` 信号时序一致。

| 变量 | 默认值 | 含义 |
|------|--------|------|
| `PULSE_IN_MS` | 150 | scale 1.0 → 1.10 上升时间 |
| `PULSE_HOLD_MS` | 150 | scale 1.10 保持时间 |
| `PULSE_OUT_MS` | 300 | scale 1.10 → 1.0 下降时间 |
| `HIGHLIGHT_DISPLAY_MS` | 600 | 总时长（来源：TtsBridge GDD，registry） |

**约束**：
```
PULSE_IN_MS + PULSE_HOLD_MS + PULSE_OUT_MS == HIGHLIGHT_DISPLAY_MS
150 + 150 + 300 == 600  ✓
```

违反此约束将导致 ChoiceUI 脉冲视觉结束时刻与 TtsBridge 发出 `speech_completed` 时刻不同步。调整单个变量时必须同步调整其余变量以维持总和。

### F-2 — 按钮尺寸（参考分辨率 360×800）

项目使用 canvas_items 拉伸模式，设计稿分辨率 360×800，1px ≈ 1dp（基于 160 DPI 基准）。

| 变量 | 值 | 含义 |
|------|-----|------|
| `BUTTON_MIN_HEIGHT_DP` | 80 | 按钮最小高度（`custom_minimum_size.y`） |
| `BUTTON_WIDTH_RATIO_MIN` | 0.44 | 按钮宽度下限（占屏幕宽度比例） |
| `BUTTON_WIDTH_RATIO_MAX` | 0.46 | 按钮宽度上限（占屏幕宽度比例） |
| `BUTTON_SEPARATION_DP` | 16 | HBoxContainer 两按钮间距 |

实际宽度由 HBoxContainer `size_flags_horizontal = SIZE_EXPAND_FILL` 自动计算；`custom_minimum_size.x` 不设定（避免平板上失去比例）。80dp 最小高度 + 16dp 间距确保 4 岁孩子触摸目标符合 WCAG 2.1 标准（44×44dp 最小触摸目标）。

## Edge Cases

| # | 场景 | 处理方式 |
|---|------|----------|
| E1 | `choices_ready` 在 `WAITING` 时重复收到（SM 侧 bug）| guard 拦截：`push_warning`，忽略新信号；现有选项不被覆盖 |
| E2 | `choices` 数组为空（SM 异常）| `push_warning`，保持 HIDDEN；不弹出空选项面板 |
| E3 | `chapter_interrupted` 在 WAITING 状态 | Rule 7：立即 kill tween，hide，`_state = HIDDEN`；不调用 submit_choice |
| E4 | `chapter_interrupted` 在 SUBMITTED 状态（淡出中）| Rule 7 同样适用：kill 淡出 tween，立即 hide，`_state = HIDDEN` |
| E5 | word_id 对应图片资源不存在（`load()` 返回 null）| `push_warning`；使用占位符纹理（1×1 透明）；按钮仍可点击；不崩溃 |
| E6 | `tts_fallback_to_highlight` 收到无匹配 word_id | Rule 6：`push_warning`，不播放脉冲；不影响选择流程 |
| E7 | `chinese_text` 字段为空字符串 | 隐藏中文 Label 节点；`push_warning`；英文和图标正常显示 |
| E8 | 多点触控：两个按钮在同帧先后触发 | 状态机保护：第一个 `pressed` 将 `_state → SUBMITTED`；第二个 `_state != WAITING` guard 返回，只提交一次 |
| E9 | PULSE tween 正在播放时玩家点击按钮 | Rule 5：`_pulse_tween.kill()` → `submit_choice()` → 淡出；动画中断，流程正确推进 |
| E10 | `choices_ready` 在 SUBMITTED 淡出动画中收到 | guard `_state != HIDDEN` 拦截（SUBMITTED 不是 HIDDEN）；`push_warning`；淡出完成后 `_state = HIDDEN`，SM 此时已经在等 submit 而不会重发 |

## Dependencies

### 上游依赖（ChoiceUI 依赖这些系统）

| 系统 | 依赖类型 | 具体接口 |
|------|----------|----------|
| **StoryManager** | 信号订阅 + 方法调用 | 订阅 `choices_ready`、`chapter_interrupted`；调用 `submit_choice(index)` |
| **TtsBridge** | 信号订阅 | 订阅 `tts_fallback_to_highlight(word_id)` |

### 下游依赖（依赖 ChoiceUI 的系统）

无。ChoiceUI 是 Presentation 层叶节点，无下游系统调用它的接口。

### 跨 GDD 影响（本 GDD 引发的上游修改）

| 目标 GDD | 修改内容 |
|----------|----------|
| `story-manager.md` | Rule 3b：`vocab_ch1.json` 格式扩展为 `{word_id: {"en": "...", "zh": "..."}}` |
| `story-manager.md` | Rule 5：`choices_ready` payload 添加 `chinese_text: String` 字段 |
| `story-manager.md` | Interactions 表：ChoiceUI 行更新为含 `chinese_text` 的 payload 规格 |

### TD-SYSTEM-BOUNDARY 解决

本 GDD 确认解决 systems-index.md 关注点 #3：「ChoiceUI → TagDispatcher 依赖是否倒置」。**结论**：ChoiceUI 直接订阅 `StoryManager.choices_ready`，与 TagDispatcher 无直接交互。systems-index 注记 `*(signal from TagDispatcher)*` 应理解为历史背景，实际数据流为 StoryManager → ChoiceUI（直连）。

## Tuning Knobs

| 名称 | 默认值 | 单位 | 安全范围 | 影响 |
|------|--------|------|----------|------|
| `BUTTON_MIN_HEIGHT_DP` | 80 | dp | 72–96 | 按钮触摸目标高度；< 72dp 违反 WCAG 最小触摸目标 |
| `BUTTON_SEPARATION_DP` | 16 | dp | 8–24 | 两按钮间距；过小影响误触率 |
| `FADE_IN_DURATION_S` | 0.15 | 秒 | 0.05–0.30 | choices 面板淡入时长；过长影响响应感 |
| `FADE_OUT_DURATION_S` | 0.15 | 秒 | 0.05–0.30 | 提交后面板淡出时长 |
| `PULSE_SCALE_MAX` | 1.10 | 倍率 | 1.05–1.20 | 高亮脉冲最大缩放；> 1.20 视觉干扰过强 |
| `PULSE_IN_MS` | 150 | ms | — | 脉冲上升时间（**约束：必须满足 F-1 总和**） |
| `PULSE_HOLD_MS` | 150 | ms | — | 脉冲保持时间（**约束：必须满足 F-1 总和**） |
| `PULSE_OUT_MS` | 300 | ms | — | 脉冲下降时间（**约束：必须满足 F-1 总和**） |
| `ICON_AREA_RATIO_MIN` | 0.60 | 比例 | 0.55–0.70 | 图标占按钮面积下限；game-concept.md 规范 ≥ 60% |

**不可调旋钮**（来源于其他 GDD，ChoiceUI 只引用）：
- `HIGHLIGHT_DISPLAY_MS = 600ms`（TtsBridge GDD 拥有，registry 登记）— PULSE_IN + HOLD + OUT 的总和约束锚点，修改此值必须通知 TtsBridge GDD 更新
- `MAX_CHOICES = 2`（StoryManager GDD 拥有）— 决定 ChoiceUI 始终只需两个按钮插槽

## Visual/Audio Requirements

### 视觉规格

**按钮卡片布局（每张）**：
- 卡片背景：圆角矩形（`StyleBoxFlat`，建议 12dp 圆角），颜色为中性暖色（米白/浅蓝）；**禁止红色或橙色**
- 上区（图标区）：占按钮总高度 ≥ 60%；`TextureRect` 模式 `KEEP_ASPECT_CENTERED`；图片来源 `res://assets/vocab/{word_id}.png`
- 中区（英文标签）：20sp 粗体，深色文字（#1A1A1A 或白底黑字），水平居中
- 下区（中文译文）：10sp 普通，浅灰文字（#808080），水平居中；无中文时隐藏该 Label
- 三区垂直排列；无水平滚动

**动画规格**：
- **淡入**：choices 面板整体 `modulate.a` 0→1，0.15s，linear
- **淡出**：`modulate.a` 1→0，0.15s，linear（提交后或 chapter_interrupted）
- **高亮脉冲**：目标按钮 `scale` 1.0→1.10（ease-in，150ms）→ hold（150ms）→ 1.10→1.0（ease-out，300ms）；`pivot_offset = size / 2.0`（中心缩放）
- **按下反馈**：Button `StyleBox:pressed` 轻微下沉（offset +2dp）；不额外播放动画

### 音频

ChoiceUI 不负责任何音频。TTS 发音由 TtsBridge 处理；`tts_fallback_to_highlight` 信号作为 ChoiceUI 的视觉同步触发器（无需 ChoiceUI 播放任何音效）。

## UI Requirements

| 要求 | 规格 | 来源 |
|------|------|------|
| 触摸目标高度 | ≥ 80dp（`custom_minimum_size.y = 80`） | game-concept.md §10 |
| 按钮宽度 | 各占屏幕宽度 44–46%（`SIZE_EXPAND_FILL`） | game-concept.md §10 |
| 排列方向 | 横排（竖屏 portrait，HBoxContainer） | game-concept.md §10 |
| 图标占比 | ≥ 60% 按钮面积 | game-concept.md §10 |
| 英文字号 | 20sp 粗体 | game-concept.md §10 |
| 中文字号 | 10sp 常规，灰色 | game-concept.md §10 |
| 焦点模式 | `FOCUS_NONE`（所有 Button） | Godot 4.6 双焦点系统 |
| P2 Anti-Pillar | 禁止红色、✗ 图标、shake 动画、错误提示 | game-concept.md P2 |
| 无计时器显示 | ChoiceUI 内不出现任何倒计时或进度条 | game-concept.md P2 |
| 输入类型 | 仅触屏点击；不响应滑动/拖拽 | technical-preferences.md |
| 平板适配 | 宽度比例（百分比布局）自动适配平板；最大宽度不设上限 | — |

## Acceptance Criteria

| # | 类型 | 验收条件 |
|---|------|----------|
| AC-1 | 集成 | `choices_ready` 在 HIDDEN 状态 → 面板在一帧内开始淡入，两个按钮内容正确填充 |
| AC-2 | 单元 | `choices_ready` 在 WAITING 状态 → `push_warning` 被记录，面板内容不被替换 |
| AC-3 | 单元 | `choices` 数组长度 3 → 只渲染 2 个按钮，`push_warning` 被记录 |
| AC-4 | 视觉 | 每个按钮：图标位于上方（≥60% 面积）、英文（20sp 粗体）居中、中文（10sp 灰色）居中 |
| AC-5 | 集成 | 点击任意按钮 → `StoryManager.submit_choice(index)` 以正确 index 调用，面板在 `FADE_OUT_DURATION_S + 50ms` 内消失 |
| AC-6 | 视觉 | 两个按钮在点击前视觉完全相同（形状、颜色、字体均无区别） |
| AC-7 | 视觉 | ChoiceUI 场景中无红色元素、无 ✗ 图标、无 shake 动画节点 |
| AC-8 | 集成 | WAITING 状态收到 `chapter_interrupted` → 面板在 1 帧内立即隐藏（无淡出动画），`_state = HIDDEN` |
| AC-9 | 集成 | `tts_fallback_to_highlight(word_id)` 收到有效 word_id → 对应按钮播放 600ms 脉冲动画；另一按钮不受影响 |
| AC-10 | 单元 | `tts_fallback_to_highlight` 收到无匹配 word_id → `push_warning`，无脉冲，无崩溃 |
| AC-11 | 单元 | 两按钮在同帧先后触发 → `submit_choice` 精确调用一次 |
| AC-12 | 单元 | word_id 对应图片资源不存在（`load()` 返回 null） → 显示占位符纹理，按钮仍可点击，无崩溃 |
| AC-13 | 单元 | `PULSE_IN_MS + PULSE_HOLD_MS + PULSE_OUT_MS == 600`（编码为常量验证或注释断言） |
| AC-14 | 视觉 | 360×800 参考分辨率下：两按钮高度 ≥ 80px，各宽 ≥ 44% 屏幕宽度 |
| AC-15 | 视觉 | 脉冲动画以按钮中心为原点对称扩展（不从左上角扩展） |
| AC-16 | 视觉 | 触摸按钮后无焦点高亮环显示（`focus_mode = FOCUS_NONE`） |
| AC-17 | 单元 | `chinese_text` 为空字符串 → 中文 Label 隐藏，英文+图标正常显示，`push_warning` 被记录 |
| AC-18 | 单元 | SUBMITTED 状态（淡出动画中）收到 `chapter_interrupted` → 淡出 tween 被 kill，立即 hide，无视觉残留 |
| AC-19 | 集成 | `_ready()` 执行后 `StoryManager.choices_ready`、`StoryManager.chapter_interrupted`、`TtsBridge.tts_fallback_to_highlight` 三个信号均已连接（可通过信号发射验证） |

## Open Questions

| # | 状态 | 问题 |
|---|------|------|
| OQ-1 | ⏳ 待解决 | ChoiceUI 在 GameScene 节点树中的 NodePath？GameScene GDD 尚未设计；ChoiceUI 的具体挂载点（如 GameScene/UI/ChoiceUI）在 GameScene GDD 中声明 |
| OQ-2 | ⏳ 待解决 | 词汇图标资源路径约定：当前设计假设 `res://assets/vocab/{word_id}.png`，需要 art pipeline 确认图片格式（PNG）和分辨率规范（建议 512×512）；占位符路径待定 |
| OQ-3 | ⏳ 待解决 | IH OQ-9（back button 确认层）选方案 A 时，GameScene 需声明 `exit_confirmation_requested` 订阅契约；ChoiceUI 在 `chapter_interrupted` 时已处理，不直接受影响，但 GameScene GDD 设计顺序依赖此决策 |
| OQ-4 | ⏳ 待 patch | StoryManager GDD patch：`choices_ready` payload 加入 `chinese_text` 字段 + `vocab_ch1.json` 格式扩展。本 GDD 批准后立即应用（见 Dependencies 节） |
