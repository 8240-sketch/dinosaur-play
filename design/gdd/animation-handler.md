# AnimationHandler

> **Status**: Approved — CD-GDD-ALIGN 2026-05-06 (APPROVE); /design-review fixes applied 2026-05-07 (RF-1~RF-8: emit ordering fix, HATCH_CELEBRATE non-interruptible, custom_blend API, typed Dictionaries, AC-13~16 added); RF-cross-1 applied 2026-05-07 (Interactions table: play_happy/confused trigger timing corrected to anim: Ink tags, not SELECTED_CORRECT/NOT_CORRECT events)
> **Author**: Zhang Shaocong + agents
> **Last Updated**: 2026-05-07
> **Implements Pillar**: P1 (看不见的学习), P2 (失败是另一条好玩的路)

> **CD-GDD-ALIGN Review**: APPROVED 2026-05-06 — 零阻断。边界观察：RecordingInviteUI GDD 需声明超时为静默后台限制，不渲染倒计时视觉，符合 P2 Anti-Pillar。

## Overview

AnimationHandler 是 NPC 动画的执行层：它持有对 AnimationPlayer 节点的引用，将来自 TagDispatcher 的词汇事件（`SELECTED_CORRECT`、`NOT_CORRECT`）以及来自 StoryManager 的剧情推进事件转换为具体的 AnimationPlayer 状态切换。系统维护 16 个命名动画状态，涵盖 idle、happy（3 种随机）、confused（3 种随机）、录音邀请、孵化彩蛋等场景，并通过 GDScript 状态包装层管理合法转换规则和过渡 blend 时间——AnimationPlayer 本身只负责播放 clip，状态机逻辑全部在 GDScript 层。AnimationHandler 对上层系统（TagDispatcher、StoryManager、HatchScene）仅暴露语义化方法（如 `play_happy()`、`play_confused()`），屏蔽所有 AnimationPlayer 细节。这个系统不产生业务数据，也不影响任何存档字段；但它的每一帧输出——恐龙的欢呼、搔头、猛扑——是孩子感知到"我做对了"或"换一条路也很好玩"的直接载体，是 P1（Invisible Learning）和 P2（Failure is Another Fun Path）落地的视觉锚点。

## Player Fantasy

孩子的手指刚抬起，T-Rex 就已经跳起来了。那一秒不是"我答对了"——是"我让它高兴了"。这个差别很小，但对 4 岁的孩子来说是整个世界：前者是测验，后者是友谊。这是 P1（Invisible Learning）在动画层的落地：happy 动画让选词变成互动，而不是答题。

孩子第一次触发 confused 动画时，通常楞一秒，然后大笑——不是因为"哦我错了"，而是"哇这个动作太搞笑了！"于是孩子很可能故意再选那个图标，想看 T-Rex 还会不会这样。confused 动画不是失败的标志，它是孩子在游戏里发现的第一个"秘密彩蛋"。这是 P2（Failure is Another Fun Path）的视觉实体：失败路径必须好笑到值得故意走一次。

没有孩子碰屏幕的时候，T-Rex 的 idle 动画在呼吸、在用眼睛找孩子。孩子按下去的瞬间，T-Rex 立刻转过来——孩子感知到的不是"我触发了动画"，是"它注意到我了"。AnimationHandler 的全部价值，是让 T-Rex 成为一个有反应的小生命，而不是一个会播放视频的图标。

## Detailed Design

### Core Rules

1. **实例模型**：AnimationHandler 是挂在 NPC Character 节点上的 GDScript 组件脚本，每个包含 NPC 的场景（主故事场景、HatchScene、MainMenu）拥有自己独立的实例，不作为 AutoLoad。节点引用通过 `@onready var _animation_player: AnimationPlayer = %AnimationPlayer` 获取（不使用 `@export`）。

2. **状态枚举（内部）**：
   ```gdscript
   enum AnimState {
       IDLE, HAPPY, CONFUSED,
       RECORDING_INVITE, RECORDING_LISTEN,
       HATCH_IDLE, HATCH_CRACK, HATCH_EMERGE, HATCH_CELEBRATE,
       STORY_ADVANCE, MENU_IDLE, ENDING_WAVE,
   }
   ```
   HAPPY 和 CONFUSED 各对应 3 个随机 clip（12 logical states，合计 16 clips）。enum 定义在 AnimationHandler 类内部，不暴露为 global enum——调用方通过语义方法调用，无需感知 enum。

3. **CLIP_MAP / VARIANT_MAP**：
   - `const CLIP_MAP: Dictionary[int, StringName]` — 一对一状态到 clip 名映射（key 类型为 `int`，因 GDScript enum 底层为 int）
   - `const VARIANT_MAP: Dictionary[int, Array]` — 一对多；value 类型为 `Array[StringName]`（GDScript 4.x 不支持 `Dictionary[int, Array[StringName]]` 嵌套泛型，value 类型在运行时为 `Array[StringName]`，文档层标注，编译器不强制）：`{ AnimState.HAPPY: [&"happy_1", &"happy_2", &"happy_3"], AnimState.CONFUSED: [&"confused_1", &"confused_2", &"confused_3"] }`；`_transition()` 内用 `VARIANT_MAP.has(new_state)` 检查后再 `Array.pick_random()` 选取随机变体

4. **`_transition(new_state: AnimState) -> void`**：所有状态切换的唯一内部入口。流程：
   a. 若 `_current_state in NON_INTERRUPTIBLE_STATES`：直接 `return`（不可中断状态保护）
   b. 从 VARIANT_MAP（若存在）或 CLIP_MAP 取 clip 名
   c. `_animation_player.play(clip_name, 0.0)`（`custom_blend = 0.0`：2D 帧精灵强制硬切，不使用编辑器过渡设置；Godot 4.6 API 参数为 `custom_blend`，默认 `-1.0` 意为"使用编辑器配置"，此处必须显式传 `0.0`）
   d. `_current_state = new_state`

5. **不可中断状态集合**：
   ```
   NON_INTERRUPTIBLE_STATES = [HATCH_CRACK, HATCH_EMERGE, HATCH_CELEBRATE, RECORDING_LISTEN, ENDING_WAVE]
   ```
   `RECORDING_LISTEN` 只能通过 `stop_recording_listen()` 语义方法退出（不经过 `_transition()` guard）。`HATCH_CELEBRATE` 是孵化链最后一环，不可中断——被打断会导致 `hatch_sequence_completed` 永不发出，HatchScene 死锁。

6. **公开 API（语义方法）**：

   | 方法 | 触发状态 |
   |------|---------|
   | `play_idle() -> void` | IDLE |
   | `play_happy() -> void` | HAPPY（随机 happy_1/2/3） |
   | `play_confused() -> void` | CONFUSED（随机 confused_1/2/3） |
   | `play_recording_invite() -> void` | RECORDING_INVITE |
   | `stop_recording_listen() -> void` | RECORDING_LISTEN → IDLE（强制退出，绕过 guard） |
   | `play_hatch_idle() -> void` | HATCH_IDLE |
   | `play_hatch_crack() -> void` | HATCH_CRACK（启动孵化链式序列） |
   | `play_story_advance() -> void` | STORY_ADVANCE |
   | `play_menu_idle() -> void` | MENU_IDLE |
   | `play_ending_wave() -> void` | ENDING_WAVE |

7. **`animation_finished` 处理**：`_ready()` 中连接 `_animation_player.animation_finished`，handler 按动画名执行链式跳转或回 IDLE：
   - `&"recording_invite"` → `_transition(RECORDING_LISTEN)`
   - `&"hatch_crack"` → `_transition(HATCH_EMERGE)`
   - `&"hatch_emerge"` → `_transition(HATCH_CELEBRATE)`
   - `&"hatch_celebrate"` → `_transition(IDLE)`；`hatch_sequence_completed.emit()`
   - 所有 happy_*/confused_* clip、`story_advance`、`ending_wave` → **先捕获 `var _completed_state := _current_state`**，再 `_transition(IDLE)`；最后 `animation_completed.emit(_completed_state)`（捕获必须在 transition 之前——`_transition()` 会将 `_current_state` 覆写为 IDLE）
   - 循环状态（IDLE、HATCH_IDLE、MENU_IDLE、RECORDING_LISTEN）在 AnimationPlayer 中设为 Loop，不产生 `animation_finished`

8. **`_ready()` 初始化**：连接 `_animation_player.animation_finished`，将 `_current_state` 设为 IDLE，调用 `play_idle()`。场景可在自身 `_ready()` 后覆盖（如 HatchScene 调用 `play_hatch_idle()`）。

9. **`stop_recording_listen()` 特殊处理**：该方法绕过 NON_INTERRUPTIBLE_STATES 检查，直接调用 `_animation_player.play(CLIP_MAP[IDLE])`，并将 `_current_state` 强制置为 IDLE。这是 RECORDING_LISTEN 的唯一合法退出路径。

### States and Transitions

| 状态 | 循环/单次 | 入口 | 出口 |
|------|---------|------|------|
| `IDLE` | Loop | `play_idle()` / 单次动画结束后自动 | 任意状态 |
| `HAPPY` | One-shot | `play_happy()` | IDLE（auto） |
| `CONFUSED` | One-shot | `play_confused()` | IDLE（auto） |
| `RECORDING_INVITE` | One-shot | `play_recording_invite()` | RECORDING_LISTEN（auto） |
| `RECORDING_LISTEN` | Loop（不可中断） | RECORDING_INVITE 完成后自动 | IDLE（仅 `stop_recording_listen()`） |
| `HATCH_IDLE` | Loop | `play_hatch_idle()` | HATCH_CRACK（由 HatchScene 触发） |
| `HATCH_CRACK` | One-shot（不可中断） | `play_hatch_crack()` | HATCH_EMERGE（auto） |
| `HATCH_EMERGE` | One-shot（不可中断） | HATCH_CRACK 完成后自动 | HATCH_CELEBRATE（auto） |
| `HATCH_CELEBRATE` | One-shot（不可中断） | HATCH_EMERGE 完成后自动 | IDLE（auto）+ `hatch_sequence_completed` |
| `STORY_ADVANCE` | One-shot | `play_story_advance()` | IDLE（auto） |
| `MENU_IDLE` | Loop | `play_menu_idle()` | 任意状态 |
| `ENDING_WAVE` | One-shot（不可中断） | `play_ending_wave()` | IDLE（auto） |

### Interactions with Other Systems

| 调用方 | 调用方法 | 时机 |
|--------|---------|------|
| **TagDispatcher** | `play_happy()` | TagDispatcher 收到 `anim:happy` Ink 标签时（P2 保护：与选词结果无关，仅由 Ink 脚本指令驱动） |
| **TagDispatcher** | `play_confused()` | TagDispatcher 收到 `anim:confused` Ink 标签时（P2 保护：与选词结果无关，仅由 Ink 脚本指令驱动） |
| **StoryManager** | `play_story_advance()` | Ink 剧情节点推进时 |
| **RecordingInviteUI** | `play_recording_invite()` | 孩子点击"Say it!" |
| **RecordingInviteUI** | `stop_recording_listen()` | 录音结束（超时 / 用户停止） |
| **HatchScene** | `play_hatch_idle()` | HatchScene 进入，展示蛋 |
| **HatchScene** | `play_hatch_crack()` | 孵化触发（点击或计时器） |
| **HatchScene** | 订阅 `hatch_sequence_completed` 信号 | 孵化动画全部完成，跳转下一场景 |
| **MainMenu** | `play_menu_idle()` | MainMenu 进入 |

## Formulas

### 随机变体选择（Random Variant Selection）

```
variant_clip(state) =
    VARIANT_MAP[state].pick_random()    if state ∈ {HAPPY, CONFUSED}
    CLIP_MAP[state]                      otherwise
```

| 变量 | 类型 | 值域 |
|------|------|------|
| `state` | AnimState | 12 个逻辑状态之一 |
| `VARIANT_MAP[HAPPY]` | Array[StringName] | `[&"happy_1", &"happy_2", &"happy_3"]` |
| `VARIANT_MAP[CONFUSED]` | Array[StringName] | `[&"confused_1", &"confused_2", &"confused_3"]` |

**输出**：StringName，传递给 `AnimationPlayer.play()`。每次调用独立随机（无防重复机制，允许连续两次相同变体）。

---

### 不可中断 Guard

```
can_transition(current, requested) =
    current ∉ NON_INTERRUPTIBLE_STATES
```

| 变量 | 值 |
|------|---|
| `NON_INTERRUPTIBLE_STATES` | `{HATCH_CRACK, HATCH_EMERGE, HATCH_CELEBRATE, RECORDING_LISTEN, ENDING_WAVE}` |

**输出**：bool。`false` 时 `_transition()` 立即返回，不播放新动画。例外：`stop_recording_listen()` 绕过此 guard（RECORDING_LISTEN 的唯一强制退出路径）。

---

### 链式序列完成路由（Animation Finished Routing）

```
next_state(finished_clip) =
    RECORDING_LISTEN                         if finished_clip == &"recording_invite"
    HATCH_EMERGE                             if finished_clip == &"hatch_crack"
    HATCH_CELEBRATE                          if finished_clip == &"hatch_emerge"
    IDLE + emit(hatch_sequence_completed)    if finished_clip == &"hatch_celebrate"
    IDLE + emit(animation_completed)         if finished_clip ∈ ONE_SHOT_CLIPS
    no-op                                    if finished_clip ∈ LOOP_CLIPS
```

其中：
- `ONE_SHOT_CLIPS` = `{happy_1, happy_2, happy_3, confused_1, confused_2, confused_3, story_advance, ending_wave}`
- `LOOP_CLIPS` = `{idle, hatch_idle, menu_idle, recording_listen}`（Loop 状态不产生 `animation_finished` 信号）

## Edge Cases

| # | 边界情况 | AnimationHandler 行为 | 调用方职责 |
|---|---------|---------------------|-----------|
| E1 | **`_animation_player` 为 null**（场景配置错误，`%AnimationPlayer` 节点不存在） | `_ready()` 中 `@onready` 赋值失败，Godot 在 `_ready()` 立即报错（null 节点引用）；后续任何方法调用均抛出 null 引用异常 | 场景必须包含 `%AnimationPlayer` 命名节点；缺失会在开发期立即暴露，不做静默处理 |
| E2 | **在不可中断状态中调用 `play_happy()` 等** | `_transition()` guard 检测到 `_current_state in NON_INTERRUPTIBLE_STATES`，直接返回；动画不切换；`push_warning` 记录被拒绝的请求 | TagDispatcher / StoryManager 可以直接调用；AnimationHandler 静默拒绝，调用方无需预检查 |
| E3 | **`play_hatch_crack()` 被连续调用两次**（如双击触发） | 第一次进入 HATCH_CRACK（不可中断）；第二次被 guard 拦截，返回；孵化序列不重启 | HatchScene 应在调用后禁用触发按钮；AnimationHandler 提供最后一道防护 |
| E4 | **`stop_recording_listen()` 在非 RECORDING_LISTEN 状态调用** | 直接播放 IDLE clip，`_current_state = IDLE`；若已是 IDLE 则无副作用（幂等） | 无需预检查；可安全作为录音流程的清理调用 |
| E5 | **CLIP_MAP / VARIANT_MAP 中 clip 名与 AnimationPlayer 实际 clip 名不匹配** | `AnimationPlayer.play()` 传入不存在的 StringName，Godot 输出错误并停止播放；`_current_state` 已更新但无动画可见 | 实现时 clip 名须严格对照 CLIP_MAP 定义；AC-1 单元测试覆盖所有 clip 名存在性 |
| E6 | **场景切换时 AnimationHandler 实例被销毁，RECORDING_LISTEN 仍在播放** | Godot `queue_free()` 直接销毁节点，`animation_finished` 不会触发；不产生 `hatch_sequence_completed` 等信号 | RecordingInviteUI / VoiceRecorder 在场景退出前应主动调用 `stop_recording_listen()` 再切换场景 |
| E7 | **`animation_finished` 收到未知 clip 名**（AnimationPlayer 被外部直接调用） | `_on_animation_finished` 未命中任何分支，走默认分支；`push_warning`；状态保持不变 | AnimationPlayer 的 clip 播放应全部经由 AnimationHandler；禁止外部代码直接调用 `AnimationPlayer.play()` |
| E8 | **`play_happy()` 在 `play_confused()` 动画播放中途被调用**（两系统同帧触发） | 均不在 NON_INTERRUPTIBLE_STATES 中；后调用者胜出，AnimationPlayer 立即切换；被中断状态不发出 `animation_completed` | TagDispatcher 应保证同一词汇事件在同帧只触发一次；AnimationHandler 不对此做额外防护 |
| E9 | **`play_happy()` 在 HATCH_CELEBRATE 动画播放中途被调用** | `HATCH_CELEBRATE` 在 `NON_INTERRUPTIBLE_STATES` 中；`_transition()` 守卫检测到后立即返回；`play_happy()` 被拒绝；孵化链正常完成；`hatch_sequence_completed` 正常发出 | 孵化场景中 TagDispatcher 可能仍活跃（若 NPC Character 节点已挂载）；AnimationHandler 守卫是最后一道防护 |

## Dependencies

### 上游依赖（AnimationHandler 依赖的系统）

| 系统 | 依赖内容 | 契约 |
|------|---------|------|
| **Godot AnimationPlayer**（引擎内置） | `play(clip_name)`、`animation_finished` 信号、Loop 模式配置 | AnimationPlayer 节点必须以 `%AnimationPlayer` 唯一名称存在于同一场景树；16 个 clip 名须与 CLIP_MAP / VARIANT_MAP 一致；不直接依赖任何游戏系统 |

### 下游依赖（依赖 AnimationHandler 的系统）

| 系统 | 调用的 API | 依赖的接口契约 |
|------|-----------|--------------|
| **TagDispatcher** | `play_happy()`、`play_confused()` | 每次词汇事件后立即调用；不可中断状态时静默拒绝，调用方无需预检查 |
| **StoryManager** | `play_story_advance()` | Ink 剧情节点推进时调用；调用方不需要等待动画完成（动画完成后自动回 IDLE） |
| **RecordingInviteUI** | `play_recording_invite()`、`stop_recording_listen()` | 录音邀请流程：先 `play_recording_invite()`（自动链到 RECORDING_LISTEN），结束时必须调用 `stop_recording_listen()` |
| **HatchScene** | `play_hatch_idle()`、`play_hatch_crack()`；订阅 `hatch_sequence_completed` 信号 | HatchScene 负责触发时机；AnimationHandler 负责完整的孵化链式序列；`hatch_sequence_completed` 为 HatchScene 的场景转换信号 |
| **MainMenu** | `play_menu_idle()` | MainMenu 进入时调用；AnimationHandler 实例由 MainMenu 场景内的 NPC 节点持有 |

### 信号契约（AnimationHandler 发出）

| 信号 | 签名 | 接收方 |
|------|------|--------|
| `animation_completed` | `(state: AnimState)` | 关心动画完成时机的场景系统（如 StoryManager 等待 story_advance 完成再推进 Ink 节点） |
| `hatch_sequence_completed` | `()` | HatchScene（孵化四步全部完成后跳转到主游戏场景） |

## Tuning Knobs

| 旋钮名 | 当前值 | 安全范围 | 影响 |
|--------|--------|---------|------|
| `HAPPY_VARIANTS` | 3（happy_1/2/3） | 1–N（只增不减） | happy 随机池大小；增加新变体只需向 VARIANT_MAP 追加 clip 名，无逻辑改动 |
| `CONFUSED_VARIANTS` | 3（confused_1/2/3） | 1–N（只增不减） | confused 随机池大小；同上 |
| `NON_INTERRUPTIBLE_STATES` | `{HATCH_CRACK, HATCH_EMERGE, HATCH_CELEBRATE, RECORDING_LISTEN, ENDING_WAVE}` | 设计决定 | 修改此集合会改变哪些动画可被打断；⚠️ 将 CONFUSED 加入此集合将违反 P2（失败路径不应阻断后续交互）；⚠️ HATCH_CELEBRATE 必须保留在此集合——移除会导致孵化链死锁 |

AnimationHandler 无数值调节参数——它是执行层，不产生游戏数值。`custom_blend` 固定为 `0.0`（2D 帧精灵强制硬切），不作为可调旋钮暴露。`stop_recording_listen()` 内部同样使用 `play(CLIP_MAP[AnimState.IDLE], 0.0)` 显式指定。

## Visual/Audio Requirements

AnimationHandler 不直接定义视觉内容，但对美术输出有以下约束：

| 约束 | 来源 | 说明 |
|------|------|------|
| 16 个 clip 名须与 CLIP_MAP / VARIANT_MAP 精确匹配 | 工程约束 | 命名不一致在运行时立即报错（AC-1 覆盖此验证） |
| happy_*/confused_* clip 长度：0.5–2.0 秒 | 体验约束 | 过长会延误 TTS 发音和下一轮交互；建议 happy ≈ 1.0s，confused ≈ 1.5s |
| confused 动画情感基调：好奇/好笑（歪头、抓爪、挑眉） | P2 要求 | 禁止任何悲伤、恐惧、沮丧表情；"选错了"不应在 NPC 脸上看见 |
| Loop 状态（idle/hatch_idle/menu_idle）必须首尾无缝衔接 | 视觉质量 | 循环接缝在儿童长时间注视 NPC 时会被注意到 |
| story_advance clip 方向性明确（NPC 向前 / 向场景深处移动） | 叙事需要 | 无需语言，视觉传递"剧情推进了"的信号 |
| recording_invite clip：NPC 举爪/张嘴，朝向孩子 | P3 需要 | 视觉模拟"你说给我听"而非"我在录你" |

## UI Requirements

N/A — AnimationHandler 是纯动画执行层，不直接驱动任何 UI 节点。所有 UI 反馈（金星动效、字幕高亮、录音进度指示）由各自的 UI 系统监听 AnimationHandler 信号后自行渲染，不通过 AnimationHandler 路由。

## Acceptance Criteria

以下所有条目均为可测试的 Pass/Fail 标准，用 GUT 单元测试验证。测试文件位置：`tests/unit/animation_handler/test_animation_handler.gd`

| # | 测试场景 | 期望结果 | 测试类型 |
|---|---------|---------|---------|
| AC-1 | 调用每个公开语义方法 | `AnimationPlayer.play()` 被调用，传入 CLIP_MAP / VARIANT_MAP 中存在的 clip 名；无 Godot 错误输出 | Unit |
| AC-2 | 调用 `play_happy()` 5 次 | 播放的 clip 名分布在 `[happy_1, happy_2, happy_3]` 中（5 次中至少 2 种不同，以 99% 概率期望） | Unit |
| AC-3 | happy_1 动画完成后 | `_current_state == IDLE`；`animation_completed(AnimState.HAPPY)` 信号已发出 | Unit |
| AC-4 | 在 HATCH_CRACK 状态中调用 `play_happy()` | `_current_state` 保持 HATCH_CRACK；`push_warning` 被调用；AnimationPlayer.play() 不被再次调用 | Unit |
| AC-5 | 调用 `play_hatch_crack()`，等待完整链式序列 | 状态依次经历 HATCH_CRACK → HATCH_EMERGE → HATCH_CELEBRATE → IDLE；`hatch_sequence_completed` 在回到 IDLE 时发出 | Unit（mock animation_finished） |
| AC-6 | 在 HATCH_EMERGE 状态中调用任意语义方法 | `_current_state` 保持 HATCH_EMERGE；调用被静默拒绝 | Unit |
| AC-7 | 调用 `play_recording_invite()`，等待动画完成 | 状态从 RECORDING_INVITE 自动切至 RECORDING_LISTEN；AnimationPlayer 以 Loop 模式播放 recording_listen | Unit |
| AC-8 | 在 RECORDING_LISTEN 状态调用 `stop_recording_listen()` | `_current_state == IDLE`；AnimationPlayer 播放 idle | Unit |
| AC-9 | 在 IDLE 状态调用 `stop_recording_listen()` | 无异常；`_current_state` 保持（或切至）IDLE；幂等 | Unit |
| AC-10 | 在 ENDING_WAVE 状态调用 `play_confused()` | 被拒绝；`_current_state` 保持 ENDING_WAVE | Unit |
| AC-11 | ENDING_WAVE 动画完成后 | `_current_state == IDLE`；`animation_completed(AnimState.ENDING_WAVE)` 信号发出 | Unit |
| AC-12 | `_ready()` 后立即检查状态 | `_current_state == IDLE`；AnimationPlayer 正在播放 idle clip | Unit |
| AC-13 | `play_happy()` 在 HATCH_CELEBRATE 状态中调用 | `_current_state` 保持 HATCH_CELEBRATE；`push_warning` 被调用；`AnimationPlayer.play()` 不被再次调用；孵化链最终正常完成 | Unit |
| AC-14 | confused_1（或任意 confused_* clip）动画完成后 | `_current_state == IDLE`；`animation_completed(AnimState.CONFUSED)` 信号发出（非 IDLE） | Unit |
| AC-15 | story_advance 动画完成后 | `_current_state == IDLE`；`animation_completed(AnimState.STORY_ADVANCE)` 信号发出（非 IDLE） | Unit |
| AC-16 | `stop_recording_listen()` 执行完成后 | `animation_completed` 信号**未被发出**（强制退出路径不经过 Rule 7，不产生完成信号）；`_current_state == IDLE` | Unit |

## Open Questions

1. **StoryManager 是否等待 `story_advance` 动画完成**：StoryManager 推进 Ink 节点前是否需要等待 `animation_completed(STORY_ADVANCE)` 信号？若是，StoryManager GDD 须说明；若否，`animation_completed` 对本场景为信息性信号。待 StoryManager GDD 确认。

2. **HatchScene 触发机制**：孵化动画由孩子点击触发还是计时器自动触发？不影响 AnimationHandler 设计（HatchScene 负责时机决策），但影响 HatchScene UX 体验。待 HatchScene GDD 定义。

3. **多 NPC 类型可复用性**：当前 CLIP_MAP / VARIANT_MAP 的 clip 名隐含 T-Rex 命名惯例。Chapter 2 若引入新恐龙，是否复用同一 AnimationHandler 类（每个 NPC 实例配置自己的 CLIP_MAP），还是各 NPC 类型继承不同子类？待 Chapter 2 scope 确认。
