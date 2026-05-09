# Interaction Pattern Library: 恐龙叙事英语启蒙游戏

> **Status**: Draft
> **Author**: gate-check
> **Last Updated**: 2026-05-09
> **Version**: 1.0
> **Engine**: Godot 4.6
> **UI Framework**: Godot Control nodes
> **Related Documents**:
> - `design/art/art-bible.md` — visual standards (colors, typography, iconography)
> - `design/accessibility-requirements.md` — accessibility commitments per feature

> **Why this document exists**: 每个屏幕 spec 应该能说"使用 VocabularyTap 模式"而不是重新定义悬停状态、按下动画和触控反馈。本库是所有可复用交互行为的唯一真相来源。

---

## Pattern Catalog Index

| Pattern Name | Category | Description | Used In (Screens) | Status |
|-------------|----------|-------------|------------------|--------|
| VocabularyTap | Input | 词汇图标点击选择——游戏核心交互 | ChoiceUI | Draft |
| LongPress | Input | 长按 5 秒进入家长模式 | MainMenu | Draft |
| HoldToRecord | Input | 按住录音，松开停止 | RecordingInviteUI | Draft |
| ButtonPrimary | Input | 主要操作按钮——大、圆、暖橙 | 全局 | Draft |
| ModalDialog | Layout | 阻塞式弹窗——需明确操作才能继续 | ParentVocabMap | Draft |
| ToastFeedback | Feedback | 非阻塞临时反馈——自动消失 | 全局 | Draft |
| SceneTransition | Navigation | 场景切换过渡动画 | 全局 | Draft |
| LoadingState | Feedback | 加载状态指示 | 全局 | Draft |

---

## Standard Patterns

---

#### VocabularyTap

**Category**: Input
**Status**: Draft
**When to Use**: 游戏核心交互——孩子在两个词汇图标中选择一个来推进剧情。每次最多 2 个选项，视觉二选一。
**When NOT to Use**: 非词汇选择场景（如导航按钮、家长地图操作）。

**Interaction Specification**:

| State | Visual | Input | Response | Duration | Audio |
|-------|--------|-------|----------|----------|-------|
| Default | 选项卡片：圆角矩形，暖橙边框，图标占 60% 面积，英文单词 28sp 加粗，中文翻译 14sp 灰色 | — | — | — | — |
| Pressed | 卡片弹性缩小至 0.95x，背景轻微变暗 | 触屏 tap | — | 60ms ease-in | [UI click sound] |
| Released | 卡片回弹至 1.05x → 1.0x（弹性过冲） | 手指抬起 | 选择确认 → TTS 播放 + NPC 反应 | 80ms ease-out | [UI confirm sound] |
| Selected (另一个) | 未被选的卡片淡出至 30% 透明度 | — | 视觉反馈：你的选择是这个 | 200ms | — |
| Correct | 卡片背景短暂变为 `--feedback-success` 暖绿 → 恢复 | — | 金星动效 | 300ms | [success chime] |
| Incorrect | 卡片不消失——T-Rex confused 动画播放，然后鼓励重试 | — | confused 动画 + 鼓励文字 | 1.5s | [confused sound] |

**Accessibility**:
- 触摸目标：≥ 96dp × 屏幕宽度 44-46%（art-bible 定义）
- 间距：两个选项之间 ≥ 16dp
- 非颜色指示：图标 + 形状（圆角矩形）+ 按下弹性动画
- TTS：选择后播放英文发音
- 无惩罚：选错不扣分，confused 动画是彩蛋

**Implementation Notes**:
[Godot: 每个选项是 `PanelContainer` + `VBoxContainer`（图标 + 英文 Label + 中文 Label）。`_gui_input()` 处理 tap 事件。弹性动画用 Tween on `scale` 属性。选中后 emit signal `word_selected(word_id)` 给 StoryManager。]

---

#### LongPress

**Category**: Input
**Status**: Draft
**When to Use**: 进入家长模式——长按 5 秒。仅在 MainMenu 使用。
**When NOT to Use**: 其他场景。

**Interaction Specification**:

| State | Visual | Input | Response | Duration | Audio |
|-------|--------|-------|----------|----------|-------|
| Idle | 隐藏触发区域（无视觉提示） | — | — | — | — |
| Pressing | 圆环进度指示器从 0% → 100% 填充（暖橙色） | 手指按住不放 | 进度填充 | 5 秒 | [progress tick sound, subtle] |
| Completed | 圆环满 → 短暂脉冲 → 导航到家长地图 | 手指保持 5 秒 | 导航 | 200ms pulse | [success chime] |
| Released Early | 圆环回退至 0% 并消失 | 手指抬起 < 5 秒 | 取消——不执行任何操作 | 300ms fade | — |

**Accessibility**:
- 触觉反馈：长按期间设备轻微震动（如果设备支持）
- 视觉反馈：圆环填充明确显示进度
- 可取消：任何时候抬起手指即取消
- 可配置：3-8 秒范围可调（tuning knob）

**Implementation Notes**:
[Godot: 使用 `_input()` 检测 `InputEventScreenTouch`。按住时启动 Tween 填充圆环 `TextureProgress`。释放时检查 elapsed time。导航用 `get_tree().change_scene_to_file()`。]

---

#### HoldToRecord

**Category**: Input
**Status**: Draft
**When to Use**: 录音功能——按住按钮录音，松开停止。仅在 RecordingInviteUI 使用。
**When NOT to Use**: 其他场景。

**Interaction Specification**:

| State | Visual | Input | Response | Duration | Audio |
|-------|--------|-------|----------|----------|-------|
| Idle | 大圆形按钮（96dp+），暖橙色 `--accent-dino`，麦克风图标 | — | — | — | — |
| Pressed | 按钮脉冲动画（呼吸灯效果），颜色变为录音中状态 | 手指按住 | 开始录音 | 即时 | [recording start sound] |
| Recording | 脉冲持续，按钮周围声波动画 | 手指保持 | 录音中 | 最长 3 秒 | — |
| Released | 按钮恢复 Idle 状态，短暂 ✓ 图标 | 手指抬起 | 停止录音 + 保存 | 即时 | [recording stop sound] |
| Max Duration | 自动停止，按钮恢复 Idle | 3 秒到达 | 停止 + 保存 | — | [recording stop sound] |
| Permission Denied | 按钮灰显，无脉冲 | — | 静默禁用——不阻断剧情 | — | — |

**Accessibility**:
- 触摸目标：≥ 96dp（art-bible 定义）
- 视觉状态：脉冲动画明确指示"正在录音"
- 权限拒绝：静默降级——按钮灰显，剧情继续
- 时长限制：最长 3 秒（防止幼儿录太长）

**Implementation Notes**:
[Godot: `AudioStreamMicrophone` + `AudioEffectCapture`。`_input()` 检测 press/release。录音数据通过 `AudioEffectCapture.get_buffer()` 累积 PCM，最终写 WAV 文件到 `user://recordings/`。]

---

#### ButtonPrimary

**Category**: Input
**Status**: Draft
**When to Use**: 主要操作按钮——"出发冒险！"、"开始游戏"、确认操作。每个屏幕最多 1 个。
**When NOT to Use**: 次要操作、取消、导航回退。

**Interaction Specification**:

| State | Visual | Input | Response | Duration | Audio |
|-------|--------|-------|----------|----------|-------|
| Default | 圆角矩形（≥16dp 圆角），暖橙填充 `--accent-dino`，白色文字 22sp 加粗 | — | — | — | — |
| Pressed | 弹性缩小 0.95x，亮度 -10% | 触屏 tap | — | 60ms | [UI click sound] |
| Released | 回弹 1.05x → 1.0x | 手指抬起 | 执行操作 | 80ms | [UI confirm sound] |
| Disabled | 40% 透明度，无交互 | — | — | — | — |

**Accessibility**:
- 触摸目标：≥ 96dp 高度
- 非颜色指示：形状（圆角矩形）+ 文字标签
- 焦点：屏幕打开时自动聚焦到 Primary 按钮

---

#### ModalDialog

**Category**: Layout
**Status**: Draft
**When to Use**: 需要明确操作才能继续的阻塞式弹窗——家长地图退出确认、删除存档确认。
**When NOT to Use**: 非阻塞通知（用 Toast）。

**Interaction Specification**:

| State | Visual | Input | Response | Duration | Audio |
|-------|--------|-------|----------|----------|-------|
| Opening | 背景遮罩 0→60% 黑色，弹窗从 0.9x → 1.0x | 触发代码 | 焦点移到确认按钮 | 200ms | [modal open sound] |
| Active | 背景不可交互，弹窗有全部输入焦点 | 触屏 tap 仅限弹窗内 | — | — | — |
| Dismissed | 弹窗 1.0x → 0.9x + 淡出，遮罩淡出 | 确认/取消按钮 | 执行操作或取消 | 150ms | [modal close sound] |

**Implementation Notes**:
[Godot: `CanvasLayer` (layer 100+) + `ColorRect` 遮罩 + `PanelContainer` 弹窗。`popup()` / `hide()` 控制显隐。]

---

#### ToastFeedback

**Category**: Feedback
**Status**: Draft
**When to Use**: 非阻塞临时反馈——"词汇已收藏"、"录音已保存"、"设置已更新"。
**When NOT to Use**: 需要决策的信息（用 ModalDialog）。

**Interaction Specification**:

| State | Visual | Input | Response | Duration | Audio |
|-------|--------|-------|----------|----------|-------|
| Entering | 从底部滑入 + 淡入，圆角卡片 | 触发代码 | — | 200ms | [subtle chime] |
| Displayed | 完整显示，图标 + 文字 | — | — | — | — |
| Auto-dismiss | 淡出 + 向下滑出 | 3 秒后自动 | 从队列移除 | 200ms | — |

**Implementation Notes**:
[Godot: `VBoxContainer` 在 `CanvasLayer` (layer 50+)。每个 toast 是 `PanelContainer` 实例，Tween 动画 `modulate.a` 和 `position.y`。队列管理：最多 3 个同时显示。]

---

#### SceneTransition

**Category**: Navigation
**Status**: Draft
**When to Use**: 所有场景切换——Main Menu → ChoiceUI, HatchScene → NameInputScreen 等。
**When NOT to Use**: 同屏幕内状态变化。

**Interaction Specification**:

| Pattern | Trigger | Animation | Duration |
|---------|---------|-----------|----------|
| Push (进入游戏) | 点击"出发冒险" | 当前场景淡出 → 新场景淡入 | 300ms fade out + 300ms fade in |
| Replace (场景替换) | 场景间导航 | 淡出当前 → 淡入新场景 | 200ms + 200ms |
| Pop (返回) | 返回按钮/Android 返回键 | 当前场景淡出 → 上一场景淡入 | 200ms + 200ms |

**Accessibility**:
- 过渡动画简洁——无旋转、无复杂特效
- 加载时间 < 2 秒（目标 1 秒内）

**Implementation Notes**:
[Godot: `SceneTree.change_scene_to_file()` 配合 `CanvasLayer` 淡入淡出动画。Transition 用 `ColorRect` 全屏遮罩 Tween `modulate.a`。]

---

#### LoadingState

**Category**: Feedback
**Status**: Draft
**When to Use**: 场景加载时间超过 1 秒时显示。
**When NOT to Use**: 加载时间 < 1 秒（不显示任何指示）。

**Interaction Specification**:

| State | Visual | Notes |
|-------|--------|-------|
| Loading (< 1s) | 无指示 | 瞬间完成，不需要加载指示 |
| Loading (1-3s) | T-Rex 走路小动画 + "加载中..." 文字 | 给孩子看的东西——不是无聊的转圈 |
| Loading (> 3s) | T-Rex 走路动画 + 进度提示 | 可能需要优化加载时间 |

**Accessibility**:
- 动画频率 < 3Hz
- 文字提示使用 Nunito 字体

---

## Open Questions

| 问题 | Owner | 截止 | 解决方案 |
|------|-------|------|---------|
| VocabularyTap 的"选错"反馈——T-Rex confused 动画时长多少合适？1 秒太短，3 秒太长？ | ux-designer | 第 2 周 | 用户测试验证 |
| LongPress 的 5 秒时长对 4 岁孩子是否太长？3 秒可能更合适？ | ux-designer | 第 4 周 | 用户测试验证 |
| LoadingState 的 T-Rex 走路动画是否需要单独的 sprite sheet？ | technical-artist | 第 2 周 | 确认资源需求 |
