# RecordingInviteUI

> **Status**: Approved — CD-GDD-ALIGN APPROVED WITH NOTES 2026-05-08; CD-1 applied (TTS P1 constraint); D-1 applied (SAVING T-Rex pose); D-2 applied (signal semantics); D-3 applied (game-concept.md 80dp→96dp)
> **Author**: user + agents
> **Last Updated**: 2026-05-08
> **Implements Pillar**: P3（声音是成长日记）、P2（失败是另一条好玩的路）

## Overview

RecordingInviteUI 是一个模态叠加界面，当 Ink 叙事触发 `record:invite` 标签时出现，引导孩子完成可选的录音邀请仪式。数据层：订阅 `TagDispatcher.recording_invite_triggered(word_id, word_text)`，协调 `VoiceRecorder.start_recording()` 和 `stop_recording()`，并通过视觉反馈反映录音状态（等待 → 录音中 → 完成）。玩家层：界面把一次 API 调用转化为温馨邀请——孩子看到英文单词、听到 T-Rex 的鼓励（TTS），然后自主选择是否跟读。孩子长按橙色按钮完成录音，声音被永久保存进成长日记（P3）。录音完全可选，跳过无摩擦；录音失败静默恢复，孩子不会感知到错误（P2）。

## Player Fantasy

孩子在整个游戏里都是做出选择的那一方——但录音邀请的瞬间方向倒转了：T-Rex 来等孩子。

音乐柔和一点，T-Rex 举起一只小爪子，用耐心而非要求的眼神看着孩子。橙色圆钮在英文单词下方缓慢脉冲。什么也不是在追着孩子跑。游戏在等这个孩子，只有眼前这一个孩子。

孩子可以选择按住圆钮，用自己的声音大声说出那个词——T-Rex 听见了，孩子的声音被永远收进成长日记（P3）。孩子也可以什么都不做，轻轻滑走；T-Rex 温柔地放下爪子，剧情继续，没有任何惩罚或失落感（P2）。

这是全局唯一一次孩子的声音本身成为游戏内容的时刻。正确与否不重要，漂不漂亮不重要——是不是你的声音，才重要。

## Detailed Design

### Core Rules

1. **非 AutoLoad，场景级叠加层**。RecordingInviteUI 作为 GameScene 的子节点实例化，每场景一份。不挂为 AutoLoad，不跨场景持久。

2. **信号订阅**（在 `_ready()` 完成）：
   - 连接 `TagDispatcher.recording_invite_triggered(word_id, word_text)` → `_on_invite_triggered()`
   - 连接 `VoiceRecorder.recording_saved` → `_on_recording_saved()`
   - 连接 `VoiceRecorder.recording_failed` → `_on_recording_failed()`
   - 连接 `VoiceRecorder.recording_unavailable` → `_on_recording_unavailable()`
   - `_exit_tree()` 时全部断开（Callable 绑定即可防止悬挂引用）

3. **出现守卫**：`_on_invite_triggered()` 首先调用 `VoiceRecorder.is_recording_available()`。若返回 `false` → 直接 `return`，UI 不出现，孩子不感知。

4. **重入守卫**：若当前状态为 APPEARING / IDLE / RECORDING / SAVING / DISMISSING，则忽略新的 `recording_invite_triggered` 信号（一次只处理一个邀请）。

5. **word_text 容错**：若 `word_text == ""`，单词展示区留空（不显示 Label）；录音仍以 `word_id` 为键正常进行。

6. **hold-to-record 通过 `_input()` 实现**（非 `gui_input()`），防止 UI 事件层吞掉手指抬起事件：
   - `InputEventScreenTouch.pressed == true` 且触点在按钮区域内 → `VoiceRecorder.start_recording(word_id)`，转入 RECORDING
   - `InputEventScreenTouch.pressed == false`（任意位置）且当前为 RECORDING → `VoiceRecorder.stop_recording()`，转入 SAVING

7. **超时倒计时**在进入 IDLE 时启动（`INVITE_TIMEOUT_SEC`，默认 12.0 秒）。录音开始时暂停计时器；SAVING 或 DISMISSING 时取消计时器。超时触发 → IDLE → DISMISSING（`skipped = true`）。

8. **跳过按钮**：IDLE 状态下屏幕底部显示轻量跳过入口（低视觉权重）。点击 → IDLE → DISMISSING（`skipped = true`）。

9. **recording_saved**（在 SAVING 中收到）→ T-Rex 短暂播放「听到了」动画（≤1.5 秒）→ DISMISSING（`skipped = false`）。

10. **recording_failed**（在 SAVING 中收到）→ 静默 → DISMISSING（`skipped = false`）。禁止显示任何错误提示，孩子不感知失败（P2 Anti-Pillar）。

11. **recording_unavailable**（任何时刻收到）→ 若处于 APPEARING / IDLE / RECORDING / SAVING → 立即转 DISMISSING（跳过正在进行的录音流程）。

12. **完成后 emit** `recording_invite_dismissed(skipped: bool)` 信号，供 GameScene / 父节点监听（可选；不影响 StoryManager 主流程）。**信号语义**：`skipped: false` 表示孩子曾尝试录音（不论是否成功保存）；`skipped: true` 表示孩子主动跳过或超时。下游 P4 系统（如 ParentVocabMap）判断录音是否实际存在时，须查询 VoiceRecorder 而非仅依赖本信号的 `skipped` 值。

---

### States and Transitions

| 状态 | 描述 | 进入条件 | 退出条件 |
|------|------|---------|---------|
| **INACTIVE** | 不可见；等待信号 | 初始 / DISMISSING 动画完成 | `recording_invite_triggered` + `is_recording_available()` |
| **APPEARING** | 淡入动画播放（≤0.3s） | INACTIVE | 动画完成 |
| **IDLE** | 圆钮脉冲；超时倒计时运行 | APPEARING | 手指按下（→ RECORDING）/ 跳过（→ DISMISSING）/ 超时（→ DISMISSING）/ `recording_unavailable`（→ DISMISSING） |
| **RECORDING** | 录音进行；环形指示器动画 | IDLE（手指按下） | 手指抬起（→ SAVING）/ `recording_unavailable`（→ DISMISSING） |
| **SAVING** | 等待 VoiceRecorder 写入完成 | RECORDING（手指抬起） | `recording_saved`（→ DISMISSING）/ `recording_failed`（→ DISMISSING）/ `recording_unavailable`（→ DISMISSING） |
| **DISMISSING** | 淡出动画播放（≤0.3s） | 多个来源（见上） | 动画完成 → INACTIVE；emit `recording_invite_dismissed` |

---

### Interactions with Other Systems

| 系统 | 方向 | 接口 | 说明 |
|------|------|------|------|
| **TagDispatcher**（AutoLoad） | 订阅 | `recording_invite_triggered(word_id, word_text)` | 触发 UI 出现；不向 TagDispatcher 回调 |
| **VoiceRecorder**（AutoLoad） | 调用 + 订阅 | 调用：`is_recording_available()`、`start_recording(word_id)`、`stop_recording()`；订阅：`recording_saved`、`recording_failed`、`recording_unavailable` | 全部录音逻辑委托给 VoiceRecorder；RecordingInviteUI 只管 UI 状态和信号路由 |
| **StoryManager** | 无直接依赖 | — | 录音邀请以「发射即忘」方式运行；StoryManager 独立推进叙事，不等待录音结果 |
| **GameScene**（父节点） | 上行信号 | `recording_invite_dismissed(skipped: bool)` | 可选监听；用于需要等待录音流程的场景编排（非必需） |

## Formulas

本系统无评分公式或游戏机制运算。所有时序参数均以常量形式定义，见 Tuning Knobs 节。

**时序边界（供实现参考）**：

| 参数 | 值 | 来源 |
|------|-----|------|
| 淡入 / 淡出动画时长 | ≤ 0.3 秒 | Core Rule 2 / 12（动画完成触发状态转换） |
| 录音后 T-Rex 动画时长 | ≤ 1.5 秒 | Core Rule 9（SAVING → DISMISSING 前等待） |
| 超时时长 | `INVITE_TIMEOUT_SEC`（默认 12.0 秒） | Tuning Knob（见下节） |
| hold-to-record 最短时长 | 无下限（任意时长均有效）；录音时长由 VoiceRecorder 实体约束 | VoiceRecorder GDD |

## Edge Cases

| # | 场景 | 处理方式 |
|---|------|---------|
| E1 | `recording_invite_triggered` 收到时 `is_recording_available()` 返回 `false` | 直接 return；UI 不出现；孩子不感知（Core Rule 3） |
| E2 | 录音邀请已显示时再次收到 `recording_invite_triggered` | 忽略新信号；完成当前流程后才接受下一个邀请（Core Rule 4） |
| E3 | `word_text == ""`（TagDispatcher map 缺失） | 单词展示区留空；以 `word_id` 为键正常录音；功能不受影响（Core Rule 5） |
| E4 | 手指在 RECORDING 状态下滑出按钮区域后抬起 | 仍触发 `stop_recording()`；短暂录音被正常保存；不作为错误处理（Core Rule 6 末句） |
| E5 | 手指在 RECORDING 状态下非常快速抬起（<100ms） | 仍触发 `stop_recording()`；极短录音由 VoiceRecorder 处理（可能 recording_failed）；RecordingInviteUI 静默 dismiss |
| E6 | VoiceRecorder 在 SAVING 状态未返回任何信号（VoiceRecorder 内部卡死） | RecordingInviteUI 依赖 VoiceRecorder GDD 的最大保存超时（SAVE_TIMEOUT_MS）；VoiceRecorder 应在超时后 emit recording_failed；本系统不设独立 SAVING 超时 |
| E7 | `recording_unavailable` 在 RECORDING 状态中收到 | 立即转 DISMISSING；不调用 `stop_recording()`（VoiceRecorder 已处于不可用状态，调用无效）（Core Rule 11） |
| E8 | 孩子按住圆钮但在 IDLE → RECORDING 转换期间松手（极快点击） | `pressed == false` 在 RECORDING 之前到达 `_input()`；此时尚未进入 RECORDING，`stop_recording()` 不调用；IDLE 超时或跳过正常退出 |
| E9 | 场景切换时 RecordingInviteUI 处于 RECORDING 状态 | `_exit_tree()` 断开所有信号；VoiceRecorder 会收到 recording_unavailable（InterruptHandler 已处理），自行清理；不额外调用 stop_recording() |
| E10 | InterruptHandler 触发（app 进入后台）时 RecordingInviteUI 处于 IDLE/RECORDING | `recording_unavailable` 信号已由 VoiceRecorder 在 InterruptHandler 流程中 emit；Core Rule 11 处理 |

## Dependencies

### 上游依赖（本系统依赖这些系统）

| 系统 | 依赖类型 | 具体接口 |
|------|---------|---------|
| **TagDispatcher**（AutoLoad） | 信号订阅 | `recording_invite_triggered(word_id: String, word_text: String)` |
| **VoiceRecorder**（AutoLoad） | 方法调用 + 信号订阅 | `is_recording_available()` → bool；`start_recording(word_id: String)`；`stop_recording()`；订阅：`recording_saved`、`recording_failed`、`recording_unavailable` |

### 下游依赖（依赖本系统的系统）

| 系统 | 依赖类型 | 具体接口 |
|------|---------|---------|
| **GameScene**（父节点） | 可选信号监听 | `recording_invite_dismissed(skipped: bool)` |

### 双向声明要求

- **TagDispatcher GDD** 已声明：`recording_invite_triggered` 是 TagDispatcher 的发出信号，RecordingInviteUI 是其订阅者（TD-SYSTEM-BOUNDARY Concern #4 已在此 GDD 解决）
- **VoiceRecorder GDD** 已声明：RecordingInviteUI 为调用方；`is_recording_available()`、`start_recording()`、`stop_recording()` 均在 VoiceRecorder GDD 接口表中列出

## Tuning Knobs

| 常量 | 默认值 | 安全范围 | 影响的游戏体验 |
|------|--------|---------|-------------|
| `INVITE_TIMEOUT_SEC` | 12.0 秒 | 8.0 – 20.0 秒 | 孩子考虑是否录音的等待时长。过短（<8s）孩子来不及反应；过长（>20s）叙事节奏拖沓 |
| `APPEAR_DISMISS_DURATION_SEC` | 0.25 秒 | 0.15 – 0.40 秒 | 淡入/淡出动画时长。过快（<0.15s）突兀；过慢（>0.40s）产生等待感 |
| `TREX_ACK_DURATION_SEC` | 1.2 秒 | 0.8 – 1.5 秒 | recording_saved 后 T-Rex「听到了」动画时长。影响录音完成后的愉悦感；不得超过 SAVING → DISMISSING 转换前的等待时长 |
| `BUTTON_MIN_SIZE_DP` | 96 dp | 96 dp（下限锁定） | 录音按钮点击区最小尺寸。96dp 为触控最小规范，不可低于此值（design/gdd/game-concept.md P-Touch 约束） |

`BUTTON_MIN_SIZE_DP` 的 96dp 为触控规范下限，不可降低；其他三个常量可在安全范围内调整以适配不同年龄段节奏偏好。

## Visual/Audio Requirements

### 视觉

**录音按钮**
- 大圆形，直径 ≥ 96dp（触控下限）；颜色 `--accent-dino`（橙色，参照 game-concept.md）
- IDLE 状态：缓慢脉冲缩放（轻微，1.06–1.10 范围；由实现决定）
- RECORDING 状态：外围环形进度指示器（无时间限制，仅表示「正在录音」）；颜色同按钮橙色；中心点轻微放大以反馈「正在工作」
- 单词 Label：大字体、居中；`word_text == ""` 时不渲染

**T-Rex 姿态**
- IDLE：手臂抬起、等待姿势（「T-Rex 在等你」框架对应动画；由 AnimationHandler 驱动，具体状态名待 AnimationHandler GDD 确认）
- **SAVING**：保持 IDLE 举爪等待姿势不变（不提前回落）；直到 `recording_saved` 或 `recording_failed` 确认后再切换（保证孩子的录音瞬间在 app 承认前不中断）
- SAVING → DISMISSING：「听到了」短暂反馈动画（≤ `TREX_ACK_DURATION_SEC`，默认 1.2 秒）
- skip/timeout DISMISSING：T-Rex 温柔放下手臂，回到 IDLE 动画；不播放 CONFUSED（P2 Anti-Pillar：失败/放弃无惩罚表情）

**叠加层背景**
- 半透明深色遮罩（`--overlay-scrim`）覆盖游戏场景，聚焦孩子注意力在录音按钮和单词上
- 跳过按钮：底部，文字色 `--text-secondary`，无背景，低视觉权重

**淡入/淡出**
- 使用 AnimationPlayer 或 Tween；duration = `APPEAR_DISMISS_DURATION_SEC`（默认 0.25 秒）

### 音频

| 事件 | 音频行为 |
|------|---------|
| UI 出现（APPEARING） | 柔和呼唤音效（轻柔；非惊吓；与叙事 BGM 不冲突）+ TTS 播放 T-Rex 邀请文本（委托叙事脚本；P1 约束：T-Rex 向孩子说话，而非质问孩子——例如「T-Rex 想听你的声音！」而非「你能说出这个单词吗？」） |
| IDLE 脉冲 | 无背景音（保持游戏 BGM；脉冲为视觉反馈） |
| RECORDING 状态 | 可选：轻微「正在录音」ambient loop（≤-18dB）；不盖过 BGM |
| recording_saved → DISMISSING | T-Rex 「太好了」或「听到了」短音效 + 动画同步 |
| recording_failed / skip / timeout | 无音效（静默退出；P2 Anti-Pillar） |

## UI Requirements

### 节点层级（参考结构）

```
RecordingInviteUI (CanvasLayer / Control)
├── ScrimOverlay (ColorRect, --overlay-scrim)
├── WordLabel (Label, 大字体居中, word_text)
├── RecordButton (Control, ≥96dp圆形热区)
│   ├── ButtonCircle (ColorRect / Panel, --accent-dino)
│   └── RecordingRing (Control, 环形指示器, RECORDING状态显示)
├── SkipButton (Button, 底部, --text-secondary, 低权重)
└── TRexLayer (AnimationPlayer控制, 独立于内容层)
```

### 布局规则

1. CanvasLayer 层级高于 GameScene 主内容（确保遮罩正确覆盖）
2. `ScrimOverlay` 铺满全屏（AnchorPreset: Full Rect）
3. `WordLabel` 居中，距顶部约 30% 屏高（16dp 内边距）
4. `RecordButton` 居中，直径 ≥ 96dp；`RecordingRing` 叠在 `ButtonCircle` 外侧，IDLE 时隐藏，RECORDING 时显示
5. `SkipButton` 固定在底部，16dp margin；宽度自适应文字；高度 ≥ 48dp（保证可触达）
6. `TRexLayer` 独立定位（右下或右侧），不随 WordLabel 或 RecordButton 布局约束

### 状态可见性

| UI 元素 | INACTIVE | APPEARING | IDLE | RECORDING | SAVING | DISMISSING |
|---------|----------|-----------|------|-----------|--------|------------|
| ScrimOverlay | 隐 | 淡入 | 显 | 显 | 显 | 淡出 |
| WordLabel | 隐 | 淡入 | 显（word_text 非空） | 显 | 显 | 淡出 |
| RecordButton | 隐 | 淡入 | 显（脉冲） | 显（放大） | 显 | 淡出 |
| RecordingRing | 隐 | 隐 | 隐 | 显 | 隐 | 隐 |
| SkipButton | 隐 | 淡入 | 显 | 隐 | 隐 | 淡出 |

### 触控规范

- RecordButton 热区 ≥ 96×96 dp（强制最小触控规范）
- SkipButton 热区 ≥ 48dp 高（辅助入口，无需醒目）
- 所有可交互元素间距 ≥ 8dp（防误触）

## Acceptance Criteria

所有 BLOCKING 条件必须通过；ADVISORY 条件在发布前确认。

**录音核心流程**

| # | 条件 | 类型 |
|---|------|------|
| AC-1 | 当 TagDispatcher 发出 `recording_invite_triggered` 且 `is_recording_available()` 为 true，RecordingInviteUI 在 0.35 秒内进入 IDLE 状态（含 0.25s 淡入） | BLOCKING |
| AC-2 | 孩子按住录音按钮 ≥1 秒后松开，`VoiceRecorder.start_recording()` 和 `stop_recording()` 各调用一次 | BLOCKING |
| AC-3 | `recording_saved` 收到后，T-Rex 播放反馈动画（≤1.5s），之后 UI 淡出并在 INACTIVE 状态 emit `recording_invite_dismissed(skipped: false)` | BLOCKING |
| AC-4 | `recording_failed` 收到后，UI 静默淡出；屏幕上无错误文字、无红色元素 | BLOCKING |

**出现守卫**

| # | 条件 | 类型 |
|---|------|------|
| AC-5 | `is_recording_available()` 返回 false 时，`recording_invite_triggered` 信号被忽略；UI 不出现 | BLOCKING |
| AC-6 | RecordingInviteUI 处于 IDLE 状态时收到第二个 `recording_invite_triggered`，忽略该信号；当前邀请流程不受干扰 | BLOCKING |

**超时与跳过**

| # | 条件 | 类型 |
|---|------|------|
| AC-7 | 孩子在 `INVITE_TIMEOUT_SEC`（12 秒）内不做任何操作，UI 自动淡出；无音效；emit `recording_invite_dismissed(skipped: true)` | BLOCKING |
| AC-8 | 孩子点击跳过按钮，UI 立即进入 DISMISSING；无音效；emit `recording_invite_dismissed(skipped: true)` | BLOCKING |

**word_text 容错**

| # | 条件 | 类型 |
|---|------|------|
| AC-9 | `word_text == ""` 时，UI 正常显示（无单词 Label）；录音流程以 `word_id` 为键正常进行 | BLOCKING |

**recording_unavailable**

| # | 条件 | 类型 |
|---|------|------|
| AC-10 | 收到 `recording_unavailable` 时，无论当前状态（APPEARING / IDLE / RECORDING / SAVING），UI 立即进入 DISMISSING；无错误提示 | BLOCKING |

**P2 Anti-Pillar 验证**

| # | 条件 | 类型 |
|---|------|------|
| AC-11 | 任何失败路径（recording_failed / recording_unavailable / timeout / skip）均不触发 CONFUSED 动画、红色元素或错误文字 | BLOCKING |
| AC-12 | skip/timeout DISMISSING 后，T-Rex 回到中性/IDLE 动画，无「失望」姿态 | ADVISORY |

**视觉与触控规范**

| # | 条件 | 类型 |
|---|------|------|
| AC-13 | 录音按钮渲染尺寸 ≥ 96dp；触控热区 ≥ 96×96dp（在目标 Android 设备上验证） | BLOCKING |
| AC-14 | SkipButton 文字颜色为 `--text-secondary`（无橙色、无红色） | ADVISORY |
| AC-15 | RECORDING 状态下，RecordingRing 可见且动画运行；IDLE/SAVING 状态下 RecordingRing 不可见 | ADVISORY |

**信号正确性**

| # | 条件 | 类型 |
|---|------|------|
| AC-16 | `recording_invite_dismissed(skipped: bool)` 仅在 DISMISSING → INACTIVE 时 emit 一次（不重复 emit） | BLOCKING |

## Open Questions

| # | 问题 | 优先级 | 解决时机 |
|---|------|--------|---------|
| OQ-1 | **AnimationHandler 等待姿势状态名**：IDLE 状态下 T-Rex「举爪等待」动画对应 AnimationHandler 的哪个 AnimState 枚举值？VoiceRecorder GDD 描述「T-Rex 举起一只爪子，等着」，但 AnimationHandler GDD 当前枚举未列出此状态。 | HIGH | AnimationHandler GDD 扩展时确认 |
| OQ-2 | **VoiceRecorder SAVE_TIMEOUT_MS**：E6 中 RecordingInviteUI 依赖 VoiceRecorder 在超时后 emit recording_failed，但 VoiceRecorder GDD 未明确声明此超时常量。需确认 VoiceRecorder GDD 是否包含此约束，或是否需要补充。 | MEDIUM | VoiceRecorder GDD 复核时确认 |
| OQ-3 | **TD-SYSTEM-BOUNDARY Concern #4 双向更新**：TagDispatcher GDD 中已声明 RecordingInviteUI 订阅 `recording_invite_triggered`，但 TagDispatcher GDD 的 Interactions 表是否已列出 RecordingInviteUI 为下游订阅者？需在本 GDD 批准后核查。 | LOW | 本 GDD 批准后验证 |
