# HatchScene

> **Status**: Approved — CD-GDD-ALIGN APPROVED WITH NOTES 2026-05-08; CD-1~CD-3 applied
> **Author**: Zhang Shaocong + agents
> **Last Updated**: 2026-05-08
> **Implements Pillar**: P1 (看不见的学习), P4 (家长是骄傲见证者)

## Overview

HatchScene 是整个游戏仅发生一次的入场仪式——由 GameRoot 在检测到 `SaveSystem.profile_exists(0) == false`（完全新安装，无任何档案）时路由至此，且每台设备终生仅执行一次。技术层面：场景通过 AnimationHandler 的 HATCH 状态链（`play_hatch_idle()` → 触屏后 `play_hatch_crack()` → 自动推进 HATCH_EMERGE → HATCH_CELEBRATE → `hatch_sequence_completed` 信号）驱动视觉；信号发出后导航至 NameInputScreen。HatchScene 不持有任何状态、不创建档案、不写入数据——它是纯视觉仪式，档案创建在后续的 NameInputScreen 中发生。体验层面：孩子第一次打开 App，看到一颗在屏幕中央轻轻颤抖的蛋。它在等待。等待孩子的手指。这一触，是游戏里孩子与 T-Rex 关系的起点——孩子不知道自己在「激活档案」，只知道是自己让那只恐龙破壳出来的。这次孵化是孩子在整个游戏中第一个「因为我做了什么，世界改变了」的时刻，是 P1（看不见的学习）的入场白，也是家长日后回忆「第一次」时的锚点。

## Player Fantasy

**孩子的幻想：我让它出来了。**

孩子第一次打开 App，屏幕中央有一颗蛋在颤抖。它不是在随机震动——它在等待。等待孩子的到来。这颗蛋只会这样颤抖一次，只在这台设备上，只在这个孩子面前。

孩子触碰的那一刻，世界发生了一件不可撤销的事：裂纹出现了。裂纹比手指期待的更大、更响、更深——小小的输入，巨大的后果。接下来的 crack → emerge → celebrate 序列不是对孩子的奖励，而是后果的必然展开：因为你做了那件事，这一切就发生了。

孩子不知道自己在"激活档案"。孩子只知道：是我让那只恐龙出来的。

这是整个游戏里孩子与世界的第一次真实接触，也是 P1（看不见的学习）在词汇出现之前就已经种下的第一粒种子：**我的行动改变了这个世界**。

**设计语言含义（开发者参考）：**
- idle trembling = 有意识的等待，不是无意识的震动（心理模型：蛋感知到了孩子的到来）
- crack 音效/视觉 = 放大一档，强化因果关系的"重量感"
- celebrate 序列 = 后果的完成，不是表演；T-Rex 的反应是"因为你触碰了我才发生了这一切"，不是"给你看个好东西"
- 全程 0 文字指导：孩子自发触屏，不需要任何提示

## Detailed Design

### Core Rules

**前置条件**

**Rule 1 — AnimationHandler 有效性守卫**
`_ready()` 时通过 `@onready var _animation_handler: AnimationHandler = %AnimationHandler` 获取引用。若引用为 `null`（场景配置错误）：`push_error`，中止初始化，屏幕保持空白。正常流程此条件永不触发（GameRoot 保证场景资源正确加载）。

**Rule 2 — 初始化序列（严格 3 步）**
守卫通过后：
  a. 进入 `WAITING_FOR_TAP` 状态
  b. 调用 `_animation_handler.play_hatch_idle()`（启动 HATCH_IDLE 颤抖循环）
  c. 启动 `_idle_min_timer`（one-shot Timer，时长 = `HATCH_IDLE_MIN_DISPLAY_MS`，默认 1500ms；到期时设 `_tap_accepted := true`）

**Rule 3 — 最短展示保护**
`_idle_min_timer` 到期前：所有 `InputEventScreenTouch` 静默忽略，不排队补触发。到期后：`_tap_accepted := true`，无可见变化，蛋继续颤抖。

**等待状态视觉召唤**

**Rule 4 — 三层叠加召唤信号（无文字）**
HATCH_IDLE 期间蛋维持三层叠加视觉信号：
  - **Layer 1（持续）**：轻微颤抖循环（`play_hatch_idle()` 实现）
  - **Layer 2（脉冲）**：柔和辐射光晕每 `EGG_GLOW_PERIOD`（默认 2.5s）脉冲一次；纯亮度变化，无色相依赖（无障碍合规）
  - **Layer 3（升级）**：超过 `IDLE_ESCALATION_TIMEOUT`（默认 8s）未触摸，颤抖幅度升至 1.5× 基础值；渐进邀请，不使用朝向屏幕中心的定向倾斜（避免孵化前提前人格化）

**Rule 5 — 全屏触摸目标**
WAITING_FOR_TAP 状态期间，整个屏幕（360×800dp）为单一触摸区域。不设独立蛋点击区。理由：场景内无其他可交互元素；精细运动能力不足的 4–6 岁孩子触屏精度不可靠；任意坐标落点在 ~200ms 内触发裂纹时，孩子体验为「我触碰了蛋」。

**触发孵化**

**Rule 6 — HATCH_IDLE 期间多次触摸处理**
有效触摸 = `InputEventScreenTouch`（`pressed == true`），任意屏幕坐标，在 `_tap_accepted == true` 之后：
  - **第一次有效触摸**：立即进入裂纹触发序列（Rule 7）
  - **第一次触摸之前的额外触摸**（`_tap_accepted == true` 后、裂纹触发前）：给蛋施加一次额外颤抖脉冲（不改变状态，不计数），确保乱按行为不被静默忽略，符合「每次触碰世界都有反应」的 P1 精神

**Rule 7 — 裂纹触发序列（WAITING_FOR_TAP → HATCHING）**
收到第一次有效触摸时，执行严格 4 步序列：
  a. 进入 `HATCHING` 状态（`_unhandled_input` 停止处理 `ScreenTouch`）
  b. `_tap_accepted := false`
  c. 连接 `_animation_handler.hatch_sequence_completed` → `_on_hatch_completed`（`CONNECT_ONE_SHOT`）
  d. 调用 `_animation_handler.play_hatch_crack()`

**Rule 8 — HATCHING 期间 tap 反馈（不可中断，但应答触摸）**
HATCH_CRACK / HATCH_EMERGE / HATCH_CELEBRATE 期间收到任意 tap：
  a. **触觉**：短促单次振动（~15ms）；无振动设备静默忽略；受 `HAPTIC_ENABLED` 全局开关控制（无障碍选项）
  b. **视觉**：在 tap 坐标（非蛋中心）生成粒子爆发（星光/光点，时长 ≤500ms，非循环）；空间锚定「我的触碰在这里」
  c. 孵化序列不受影响；AnimationHandler NON_INTERRUPTIBLE_STATES 守卫作为安全网

**Rule 9 — Android 返回键策略**
  - **WAITING_FOR_TAP**：透传给 OS（标准 Android 行为，退出至桌面）。GameRoot 下次启动时 `profile_exists(0)==false` 自动重路由，无状态损坏
  - **HATCHING 期间**：拦截返回键，执行 no-op。防止 `hatch_sequence_completed` 永不触发导致的导航死锁。实现：重写 `_input()` 检测 `KEY_BACK` / `ui_cancel`；仅 `_state == State.HATCHING` 时消费事件

**孵化完成**

**Rule 10 — 庆祝停顿与自动推进（HATCHING → COMPLETED）**
收到 `hatch_sequence_completed` 信号后：
  a. 进入 `COMPLETED` 状态
  b. 启动 `_celebrate_hold_timer`（one-shot Timer，时长 = `CELEBRATE_HOLD_DURATION`，默认 2.5s）
  b2. 同步启动 `_skip_lock_timer`（one-shot Timer，时长 = `CELEBRATE_SKIP_LOCK_MS / 1000.0`，默认 600ms；到期时设 `_skip_unlocked := true`）
  c. `_celebrate_hold_timer` 到期前若收到任意 tap **且 `_skip_unlocked == true`**：`.stop()` 计时器，立即进入步骤 d（提前跳过，保留孩子的主动感）。`_skip_unlocked == false` 期间 tap 静默忽略（P4：保证家长见证至少 600ms 完整 T-Rex）
  d. 调用 `get_tree().change_scene_to_file("res://scenes/ui/NameInputScreen.tscn")` 并渐变过渡（时长 ≥400ms，不用闪切）
  e. 若 `change_scene_to_file()` 返回非 `OK`：`push_error`，不崩溃（HatchScene 无 LOAD_ERROR UI，失败由家长重启 App 处理）
  f. `_celebrate_hold_timer` 和 `_skip_lock_timer` 在 `_exit_tree()` 时各调用 `.stop()`（防止 queue_free 后幽灵信号触发导航）

**数据边界**

**Rule 11 — HatchScene 不写入任何数据**
严格禁止调用：`ProfileManager.create_profile()`、`ProfileManager.begin_session()`、任何 SaveSystem 写入方法。HatchScene 是纯视觉仪式；档案创建在 NameInputScreen 发生。

---

### States and Transitions

| 状态 | 含义 | 触摸输入响应 | AnimationHandler 状态 |
|------|------|------------|----------------------|
| `WAITING_FOR_TAP` | 场景已加载；蛋颤抖；等待有效触摸 | `_tap_accepted==false`：静默忽略；`_tap_accepted==true`：额外 tap 加颤抖脉冲；首次有效 tap → HATCHING | `HATCH_IDLE`（循环） |
| `HATCHING` | 孵化序列进行中，等待 `hatch_sequence_completed` | 产生触觉+粒子反馈，不改变状态；返回键 no-op | `HATCH_CRACK` → `HATCH_EMERGE` → `HATCH_CELEBRATE`（AH 内部自动推进） |
| `COMPLETED` | 信号已收，庆祝停顿或场景切换中 | tap 提前结束停顿计时；返回键透传 OS | AH 自动回 `IDLE`（不影响 HatchScene） |

**合法转换**

| 从 | 到 | 触发条件 |
|----|----|---------|
| （初始化） | `WAITING_FOR_TAP` | `_ready()` + AnimationHandler 有效 |
| `WAITING_FOR_TAP` | `HATCHING` | `ScreenTouch pressed==true` + `_tap_accepted==true`（首次有效 tap） |
| `HATCHING` | `COMPLETED` | `hatch_sequence_completed` 信号（ONE_SHOT 连接） |
| `COMPLETED` | （NameInputScreen） | `CELEBRATE_HOLD_DURATION` 到期 或 tap 提前触发 |

无后退转换。状态单向推进，终生执行一次。

---

### Interactions with Other Systems

| 系统 | 流入 | 流出 | 接口所有者 |
|------|------|------|-----------|
| **GameRoot / SceneTree** | GameRoot 路由至此（HatchScene 不感知 `profile_exists` 判断） | `change_scene_to_file("res://scenes/ui/NameInputScreen.tscn")` | HatchScene 调用；路由逻辑由 GameRoot 拥有 |
| **AnimationHandler**（本地实例，非 AutoLoad） | 无（HatchScene 是调用方） | `play_hatch_idle()` — Rule 2；`play_hatch_crack()` — Rule 7 | HatchScene 调用语义方法 |
| **AnimationHandler 信号** | `hatch_sequence_completed()` — CELEBRATE 完成后由 AH 发出 | 无（ONE_SHOT 订阅，Rule 7c） | HatchScene 订阅 |
| **InputEvent（引擎）** | `InputEventScreenTouch`（孩子手指） | 无（纯消费） | HatchScene 唯一消费者 |
| **SaveSystem / ProfileManager** | 无 | 无（Rule 11 禁止） | NameInputScreen 拥有档案创建 |

## Formulas

HatchScene 不包含游戏进程数值公式。本节定义三个可实现的数学/决策表达式。

### F-1 — 颤抖强度分层（Trembling Intensity Layer Selection）

```
trembling_layer(t_elapsed) =
    LAYER_1    if t_elapsed < HATCH_IDLE_MIN_DISPLAY_MS / 1000.0
    LAYER_2    if HATCH_IDLE_MIN_DISPLAY_MS / 1000.0 ≤ t_elapsed < IDLE_ESCALATION_TIMEOUT
    LAYER_3    if t_elapsed ≥ IDLE_ESCALATION_TIMEOUT
```

| 变量 | 类型 | 范围 | 描述 |
|------|------|------|------|
| `t_elapsed` | float | 0.0 – ∞ s | 自 WAITING_FOR_TAP 起点的累计秒数 |
| `HATCH_IDLE_MIN_DISPLAY_MS` | int | 500–3000 ms | 最短展示时长；分层阈值 = 该值 ÷ 1000.0 |
| `IDLE_ESCALATION_TIMEOUT` | float | 5.0–15.0 s | Layer 3 升级触发阈值（默认 8.0s） |
| `trembling_layer` | int | {1, 2, 3} | 当前颤抖层级；驱动美术动画变体切换 |

**输出范围**：离散集合 {1, 2, 3}。LAYER_3 是终态。

**示例**（默认值：HATCH_IDLE_MIN_DISPLAY_MS=1500, IDLE_ESCALATION_TIMEOUT=8.0）：
- t=0.8s → 0.8 < 1.5 → **LAYER_1**
- t=3.0s → 1.5 ≤ 3.0 < 8.0 → **LAYER_2**
- t=10.0s → 10.0 ≥ 8.0 → **LAYER_3**

---

### F-2 — 蛋体辉光强度周期（Egg Glow Intensity Cycle）

```
glow_intensity(t) = 0.5 × (1 + sin(2π × t / EGG_GLOW_PERIOD))
```

| 变量 | 类型 | 范围 | 描述 |
|------|------|------|------|
| `t` | float | 0.0 – ∞ s | 自 `_ready()` 起累计秒数（连续推进，不重置） |
| `EGG_GLOW_PERIOD` | float | 1.5–4.0 s | 辉光完整周期（默认 2.5s） |
| `glow_intensity` | float | [0.0, 1.0] | 蛋体辉光 shader modulate 强度；驱动 emission 或 alpha |

**输出范围**：闭区间 [0.0, 1.0]，由正弦函数保证，无需额外 clamp。

**示例**（EGG_GLOW_PERIOD=2.5s）：

| t | glow_intensity |
|---|---------------|
| 0.0s | 0.50 |
| 0.625s | 1.00（峰值） |
| 1.25s | 0.50 |
| 1.875s | 0.00（谷值） |
| 2.5s | 0.50（回到起点） |

---

### F-3 — 提前触碰颤抖冲量衰减（Premature Tap Impulse Decay）

WAITING_FOR_TAP 期间每次额外触碰叠加一个线性衰减的位移冲量（Rule 6）：

```
impulse_offset(Δt) = EGG_IMPULSE_AMPLITUDE × max(0.0, 1.0 − Δt / EGG_IMPULSE_DURATION)

total_shake_offset(t) = base_layer_offset(layer) + Σᵢ impulse_offset(t − t_tap_i)
```

Σᵢ 仅对满足 `(t − t_tap_i) < EGG_IMPULSE_DURATION` 的触碰求和。

| 变量 | 类型 | 范围 | 描述 |
|------|------|------|------|
| `Δt` | float | 0.0 – EGG_IMPULSE_DURATION s | 自第 i 次触碰起的经过时间 |
| `EGG_IMPULSE_AMPLITUDE` | float | 4.0–16.0 px | 单次冲量最大位移幅度（默认 8.0px） |
| `EGG_IMPULSE_DURATION` | float | 0.15–0.5 s | 冲量线性衰减至零的持续时间（默认 0.3s） |
| `base_layer_offset` | float | — px | F-1 当前颤抖层基础振幅（美术定义） |
| `total_shake_offset` | float | — px | 蛋体当前帧总水平位移，驱动 Node2D position.x |

可选：将总偏移量 clamp 至 `2 × EGG_IMPULSE_AMPLITUDE` 防止极端叠加时视觉失真。

**示例**（EGG_IMPULSE_AMPLITUDE=8px, EGG_IMPULSE_DURATION=0.3s）：

| Δt | impulse_offset |
|----|---------------|
| 0.0s | 8.0 px |
| 0.15s | 4.0 px |
| 0.3s | 0.0 px（完全衰减） |

---

### 触碰点粒子生命周期

规则已指定 ≤500ms 上限（Rule 8b）。**无需额外公式**。`TAP_PARTICLE_LIFETIME` 为实现层常量（建议 400ms），选取属于美术调整事项。

## Edge Cases

| # | 边界情况 | HatchScene 行为 |
|---|---------|----------------|
| EC-1 | **WAITING_FOR_TAP 期间应用转入后台**（来电、Home 键） | InterruptHandler 检测 `is_story_active==false`，调用 `ProfileManager.flush()`（HatchScene 未写任何档案数据，flush 无副作用）。`_idle_min_timer` 继续计时。进程存活恢复：场景保持 WAITING_FOR_TAP，孩子正常继续。进程被 Android 杀死后冷启动：GameRoot 检测 `is_first_launch()==true`，重新路由至 HatchScene，无数据丢失（未写入任何数据）。 |
| EC-2 | **HATCHING 期间应用转入后台**（非可中断序列进行中） | 同 EC-1（flush 无 HatchScene 数据可保护）。进程存活恢复：AnimationHandler 从暂停帧继续，`hatch_sequence_completed` 正常发出，场景正常跳转。若恢复后信号永不发出：EC-5 看门狗兜底。进程被杀：冷启动 → `is_first_launch()==true` → HatchScene 重来（同 EC-1）。 |
| EC-3 | **AnimationHandler `_ready()` 竞态**（AH 节点存在但尚未初始化） | Godot 4 子节点 `_ready()` 早于父节点执行（自底向上），HatchScene._ready() 启动时 AH 已完成初始化。**不存在竞态风险**，为 Godot 树生命周期保证。实现约束：AnimationHandler 必须作为静态子节点存在于场景文件，禁止在 HatchScene._ready() 内动态实例化 AH；违反此约束在开发期立即暴露为引擎错误。 |
| EC-4 | **`_idle_min_timer` 在场景已卸载后触发** | `_exit_tree()` 调用 `_idle_min_timer.stop()`。Godot Timer 节点随父节点 queue_free() 自动断开所有信号。防御性实现：回调首行添加 `if not is_inside_tree(): return` 守卫。 |
| EC-5 | **`hatch_sequence_completed` 信号永不发出**（AnimationHandler 故障） | `play_hatch_crack()` 同帧启动 `_hatch_watchdog_timer`（time = `HATCH_SEQUENCE_WATCHDOG_MS`，默认 8000ms）。若信号在超时前到达：取消看门狗，正常推进。若看门狗触发：`push_error`，记录 `is_instance_valid(_animation_handler)` 结果，立即调用 `_advance_to_name_input()`。孩子不会被困在 HATCHING 状态。 |
| EC-6 | **Rule 10d 的 `change_scene_to_file()` 失败**（Error ≠ OK） | `push_error` 记录 err 和路径。重置 `_is_transitioning := false`。场景停留 COMPLETED（T-Rex 循环 IDLE）；孩子下次触碰屏幕重新尝试跳转。不向孩子展示错误 UI。此类失败通常为工程配置 bug（路径错误），由 AC 中路径验证测试覆盖。 |
| EC-7 | **CELEBRATE_HOLD 期间触碰与计时器在同一帧触发** | GDScript 单线程，两条路径均调用 `_advance_to_name_input()`。方法入口以 `_is_transitioning: bool` 标志保护：第一个调用者置 `true` 并执行跳转；后到达者发现标志为 `true` 立即返回（无操作）。结果：恰好一次 `change_scene_to_file()` 调用，与执行顺序无关。 |
| EC-8 | **设备无震动能力（`HAPTIC_ENABLED=true` 但硬件不支持）** | `Input.vibrate_handheld()` 在无振动马达设备上为 Godot 平台层静默 no-op，不抛异常，不影响任何后续逻辑。无需硬件能力探测，`HAPTIC_ENABLED=true` 可无差别部署。 |
| EC-9 | **HATCHING 期间 AnimationHandler 节点被释放** | 直接后果：`hatch_sequence_completed` 永不发出。EC-5 看门狗超时触发，`is_instance_valid(_animation_handler)` 返回 `false`，`push_error` + `_advance_to_name_input()` 强制跳转。预防契约：任何代码不得在 HATCHING 状态下释放 AH 节点或其上级父节点。 |

## Dependencies

### 上游依赖（HatchScene 依赖这些系统）

| 系统 | 依赖类型 | 具体内容 |
|------|---------|---------|
| **AnimationHandler** | 直接调用 + 信号订阅 | `play_hatch_idle()`、`play_hatch_crack()`；订阅 `hatch_sequence_completed()` 信号（ONE_SHOT）。AnimationHandler 作为场景本地实例，非 AutoLoad。 |
| **GameRoot / SceneTree** | 被动依赖（路由接收方）| GameRoot 调用 `SaveSystem.profile_exists(0)` 判断后路由至此；HatchScene 不感知此判断，不调用 SaveSystem。 |

### 下游依赖（这些系统依赖 HatchScene）

| 系统 | 依赖内容 |
|------|---------|
| **NameInputScreen** | 被导航目标。HatchScene 的 `change_scene_to_file()` 将控制权交给 NameInputScreen；NameInputScreen 不依赖 HatchScene 的任何状态或数据。 |

### 显式非依赖（Rule 11 边界声明）

| 系统 | 原因 |
|------|------|
| **SaveSystem** | HatchScene 不写入任何数据（Rule 11）。`profile_exists(0)` 由 GameRoot 调用，非 HatchScene。 |
| **ProfileManager** | HatchScene 不创建档案、不调用 `begin_session()`（Rule 11）。档案创建在 NameInputScreen 发生。 |
| **StoryManager / TagDispatcher** | HatchScene 不涉及故事机制，无叙事状态。 |
| **TtsBridge / VocabStore** | HatchScene 无 TTS 需求，无词汇学习状态。 |

## Tuning Knobs

| 旋钮名 | 默认值 | 安全范围 | 类型 | 影响 |
|--------|--------|---------|------|------|
| `HATCH_IDLE_MIN_DISPLAY_MS` | 1500 ms | 500–3000 ms | UX / 防护 | 触摸接受窗口开启前的最短展示时长；过短导致家长递手机时误触发，过长让孩子失去耐心 |
| `IDLE_ESCALATION_TIMEOUT` | 8.0 s | 5.0–15.0 s | UX | 颤抖幅度升级（LAYER_3, 1.5×）触发时间；过短令蛋"太急"，破坏「静静等待」诗意 |
| `EGG_GLOW_PERIOD` | 2.5 s | 1.5–4.0 s | UX / 视觉 | 辉光脉冲周期（F-2）；过快令人焦虑，过慢失去吸引力 |
| `CELEBRATE_HOLD_DURATION` | 2.5 s | 1.5–4.0 s | UX / P4 | 孵化完成后庆祝停顿时长；过短剥夺家长见证时刻（P4），过长让孩子失去方向感 |
| `HAPTIC_ENABLED` | `true` | `true / false` | 无障碍 | HATCHING 期间 tap 的触觉振动开关；无振动设备自动静默，无需条件分支 |
| `EGG_IMPULSE_AMPLITUDE` | 8.0 px | 4.0–16.0 px | 视觉 / F-3 | 单次提前触碰的最大位移冲量幅度；过小无法感知，过大视觉抖动令人不安 |
| `EGG_IMPULSE_DURATION` | 0.3 s | 0.15–0.5 s | 视觉 / F-3 | 单次冲量线性衰减至零的持续时间；过短失去弹性感，过长冲量叠加堆积 |
| `CELEBRATE_SKIP_LOCK_MS` | 600 ms | 300–1000 ms | UX / P4 | COMPLETED 进入后的不可跳过最短窗口（CD-2 修复）；保证家长至少看到 600ms 完整 T-Rex。到期后孩子 tap 才能提前跳过剩余 CELEBRATE_HOLD |
| `HATCH_SEQUENCE_WATCHDOG_MS` | 8000 ms | 5000–15000 ms | 容错 / EC-5 | 孵化链式序列超时看门狗；若 `hatch_sequence_completed` 在此时间内未发出则强制跳转（约 = 预估序列总时长 + 2000ms 缓冲） |

## Visual/Audio Requirements

### Visual Requirements

**背景（Background）**

| 属性 | 规格 |
|------|------|
| 色彩 | `--surface-bg`（暖米白）为基底；中心向外径向渐变，边缘压暗约 15–20%，将目光导向屏幕中央蛋体。禁止纯白（`#FFFFFF`）或冷色调背景。 |
| 内容密度 | 极简 + 轻微环境提示：蛋体居中，背景底部允许一圈极低调轮廓（草丛轮廓或巢穴边缘线条）建立「老巢」语境感。轮廓透明度 ≤ 30%，不与蛋体争抢视觉权重。 |
| 文字约束 | 全程**零文字**。场景树内不允许任何可见的 `Label`、`RichTextLabel` 节点。Release Build 必须关闭所有调试叠加层（P1 执行）。 |

**蛋体（Egg Design）**

| 属性 | 规格 |
|------|------|
| 渲染尺寸 | 宽 200dp，高 240dp（纵横比 5∶6）——约占屏幕宽度 55%，全场景视觉权重最高元素 |
| 位置 | 水平居中（`x center = 180dp`）；蛋体中心点 `y ≈ 350dp`（光学中心，略高于几何中心） |
| 色彩 | 暖米白底，不规则浅棕灰斑点（非轴对称）。整体色温偏暖，禁止冷灰、蓝绿色调 |
| 质感 | 手绘粗糙纹理，非光滑塑料感。目标联想：陶土或纸浆蛋，让 4 岁孩子想伸手摸 |
| HATCH_IDLE 裂纹 | 蛋壳表面允许极细微纹路走向（暗示内部张力），**不得出现可见裂缝**。实际裂纹仅在 HATCH_CRACK 帧动画中出现 |

**蛋体辉光（Egg Glow Shader）**

| 属性 | 规格 |
|------|------|
| Shader 类型 | 2D Unlit Shader（Compatibility 渲染器原生），无后处理 Pass，无 bloom |
| 色彩约束 | 纯亮度变化，零色相偏移：`final_color = base_color × (1.0 + emission_strength × glow_intensity)`；`glow_intensity` 由 F-2 每帧 GDScript uniform 推送 |
| 强度范围 | 峰值（glow=1.0）时 emission 叠加 +30% 于基础色；谷值（glow=0.0）时回到基础色 |
| 扩散范围 | 辉光限定在蛋体轮廓内及边缘溢出 ≤ 8dp；禁止向背景大面积扩散 |
| 无障碍 | 纯亮度变化，色盲用户可感知（F-2 合规） |

**T-Rex 可见性时序**

| AnimationHandler 状态 | T-Rex 可见性 | 实现建议 |
|----------------------|-------------|---------|
| `HATCH_IDLE` | **完全不可见** | T-Rex 节点 `visible = false` 或 `modulate.a = 0.0` |
| `HATCH_CRACK` | **隔裂纹隐约可见暗影轮廓**（色块轮廓，无细节，制造「里面有生命」期待感） | T-Rex 节点在蛋层之下；裂纹缝隙透出一线暗影 |
| `HATCH_EMERGE` | **渐进显现**：T-Rex 头部与上半身从蛋中央破碎区域拱出；蛋壳上半部碎片向外位移 | 蛋壳碎片作为独立帧序列；T-Rex 节点在蛋层之上，`modulate.a` 0.0 → 1.0 |
| `HATCH_CELEBRATE` | **完全可见**：T-Rex 全身居中；蛋壳碎片散落或离屏 | CELEBRATE_HOLD 2.5s 期间 T-Rex 维持庆祝静态或循环 |

**Tap-Point 粒子爆发（HATCHING 期间）**

| 属性 | 规格 |
|------|------|
| 生成锚点 | **tap 坐标**（`event.position`），非蛋中心。强化「我的触碰在这里」空间归因 |
| 粒子数量 | 每次 tap：8–15 个（CPUParticles2D，`one_shot = true`） |
| 颜色 | 主色 `--highlight-pulse`（亮黄），次色 `--accent-dino`（暖橙），各粒子随机分配约 1∶1 |
| 形状 | 小圆点或四角星，直径 4–8dp，无描边 |
| 运动 | 从 tap 点均匀向外放射，初速度 120–180dp/s，无重力偏移 |
| 生命周期 | 线性淡出至 alpha=0，总时长 **≤ 500ms**（Rule 8b 硬限制） |
| 并发上限 | 同时最多 3 个 burst 活跃；第 4 个 tap 时强制 `queue_free()` 最旧 burst |

**场景过渡视觉（COMPLETED → NameInputScreen）**

全屏渐入暖白（`#FFF8F0`）覆盖层 + NameInputScreen 从底部轻柔滑入。总时长 ≥ 400ms。禁止闪切和冷白/黑色淡出。

**性能约束（Android API 24+，Compatibility 渲染器）**

| 约束项 | 限制值 |
|--------|--------|
| Draw Calls 峰值 | ≤ 20 |
| 并发 CPUParticles2D | ≤ 3 个活跃实例，每个 `amount ≤ 15` |
| 纹理总预算（VRAM，压缩后）| ≤ 2 MB |
| 单张纹理尺寸 | ≤ 1024×1024px（绝对上限 2048px） |
| 辉光 Shader | ≤ 20 GPU 指令，零额外纹理采样 pass |
| 音频资产（压缩后，全部音效合计）| ≤ 1 MB，OGG Vorbis |

---

### Audio Requirements

**总体音频哲学**
全程无背景音乐（P1：静默放大 CRACK 冲击力；P4：孵化仪式不与音乐竞争情绪空间）。背景音乐从 NameInputScreen 起引入。

**音效规格**

| 触发来源 | 设计意图 | 音效构成 | 相对音量 | 时长 |
|---------|---------|---------|---------|------|
| **HATCH_IDLE 环境音** | 「蛋在等待」——传递内部生命感；与辉光脉冲节奏松散呼应 | 极低频脉冲（20–60Hz 正弦），重复周期约 2–3s | **−24 dB**（手机外放可感知但不抢注意力；如测试中分散孩子注意可降至 −30dB 或移除） | 循环，HATCH_CRACK 触发时停止 |
| **HATCH_CRACK** | 因果感锚点：一触，世界破裂 | 三层：① 高频清脆裂声（>2kHz）② 低频冲击（100–200Hz，<100ms）③ 窄幅立体声扩展（L/R 差异 ≤15%） | **0 dB（全场景峰值参考）**，比所有其他音效响 ≥ 12 dB，不压缩 | 400–600ms，含约 200ms 混响尾音 |
| **HATCH_EMERGE** | 期待转见证 | ① 轻柔壳片摩擦声（0.3–0.5s）② 可选幼龙软鸣（400–800Hz，原型测试后决定是否保留） | −10 dB | 匹配 HATCH_EMERGE 动画时长 |
| **HATCH_CELEBRATE** | 后果完成的情绪句号 | ① 幼龙快乐鸣叫（0.4–0.6s）② 上行 3–4 音符钢片琴 sting（1.5–2.5s）。**Sting 必须在 CELEBRATE_HOLD_DURATION 结束前 ≥ 500ms 衰减至零**（Rule 10：sting 在场景切换前自然播完）。`CELEBRATE_HOLD_DURATION` 调优时须将 sting 时长纳入约束。 | −6 dB（sting 峰值） | 2.0–3.0s |
| **HATCHING 期间额外 tap** | P1：每次触碰世界都有反应 | 单音金属钟鸣或水晶音叉，无延音；CRACK 触发后 200ms 内禁用（防音效冲突）；tap 间隔 < 80ms 时 debounce 为单次 | −14 dB | 80–150ms |
| **场景过渡** | 听觉缓冲 | 低频柔和气流声，单向消退；若 CELEBRATE sting 仍在播放则跳过（两者不叠加） | −18 dB | 400–500ms |

**场景切换后音频行为**
HatchScene 所有 AudioStreamPlayer 节点随场景树销毁自动停止。由于 sting 设计为在切换前自然播完（策略 A），无需跨场景音频保留机制。

## Acceptance Criteria

### 故事分类与测试证据要求

| 方面 | 故事类型 | 必要证据 | 门控级别 |
|------|----------|----------|---------|
| 状态机逻辑（Rules 2, 3, 6, 7, 9, 10, EC-7） | Logic | GUT 单元测试通过，位于 `tests/unit/hatch_scene/` | BLOCKING |
| 公式正确性（F-1, F-2, F-3） | Logic | 每个公式有对应 GUT 单元测试 | BLOCKING |
| AnimationHandler 集成（Rules 2, 7, 8, 10） | Integration | GUT 集成测试，使用真实 AnimationHandler 节点 | BLOCKING |
| SceneTree 导航（Rule 10d） | Integration | 集成测试 OR 有记录的 playtest，确认 NameInputScreen 正确加载 | BLOCKING |
| 视觉召唤信号（颤抖层、辉光、粒子）| Visual/Feel | t=0s/t=8s/HATCHING 进入时各截图；Lead 在 `production/qa/evidence/` 签字 | ADVISORY |
| 触觉反馈 | Visual/Feel | 真机 Android 设备测试；Lead 签字 | ADVISORY |

---

### Initialization

**AC-1** — `_ready()` 在任何用户输入被处理之前，对 AnimationHandler 调用 `play_hatch_idle()` 恰好一次。初始化期间不调用其他 AnimationHandler 动画方法。
> GUT: spy on AnimationHandler.play_hatch_idle(); after _ready(): assert call count=1; play_hatch_crack() call count=0.

**AC-2** — `_ready()` 以 one-shot 模式启动 `_idle_min_timer`，`wait_time = HATCH_IDLE_MIN_DISPLAY_MS / 1000.0`。默认值 1500ms 下，`wait_time=1.5`，计时器处于运行状态。
> GUT: read _idle_min_timer.wait_time and .is_stopped() after _ready(); inject HATCH_IDLE_MIN_DISPLAY_MS=2000 → assert wait_time=2.0.

**AC-3** — `_ready()` 完成后，内部状态 == `State.WAITING_FOR_TAP`。
> GUT: assert state == State.WAITING_FOR_TAP immediately after instantiation.

**AC-4** — AnimationHandler 作为静态子节点存在于 HatchScene.tscn 场景文件中。若 `_ready()` 时 AnimationHandler 缺失，`push_error` 被调用且初始化中止，场景不崩溃。
> Manual: 在 Godot 编辑器中打开 HatchScene.tscn，确认 AnimationHandler 作为直接命名子节点存在。
> GUT: 实例化不含 AnimationHandler 子节点的 HatchScene；assert push_error 被调用，无崩溃。

---

### Timing Protection

**AC-5** — `_idle_min_timer` 仍在运行期间，任意坐标的 tap 产生零次状态变化、零次 AnimationHandler 调用、零次触觉调用。状态保持 `WAITING_FOR_TAP`，`_tap_accepted` 保持 `false`。
> GUT: inject HATCH_IDLE_MIN_DISPLAY_MS=999000; simulate InputEventScreenTouch at t=0ms; assert state=WAITING_FOR_TAP, play_hatch_crack() count=0.

**AC-6** — `_idle_min_timer` 触发后，`_tap_accepted` 变为 `true`。计时器到期时无可见状态变化，`play_hatch_idle()` 不被再次调用。
> GUT: inject HATCH_IDLE_MIN_DISPLAY_MS=0; advance one frame; assert _tap_accepted=true, play_hatch_idle() total count=1.

**AC-7** — F-1 颤抖层分界精确：t < HATCH_IDLE_MIN_DISPLAY_MS/1000.0 → LAYER_1；t in [min, IDLE_ESCALATION_TIMEOUT) → LAYER_2；t ≥ IDLE_ESCALATION_TIMEOUT → LAYER_3。边界值：t=1.5s → LAYER_2；t=8.0s → LAYER_3。
> GUT: inject HATCH_IDLE_MIN_DISPLAY_MS=1500, IDLE_ESCALATION_TIMEOUT=8.0; sample at t=0.5/3.0/10.0/1.5/8.0s; assert correct layer at each point.

**AC-8** — t ≥ IDLE_ESCALATION_TIMEOUT 后，LAYER_3（1.5× 幅度）激活；t=IDLE_ESCALATION_TIMEOUT−0.1s 时 LAYER_3 尚未激活。
> GUT: inject IDLE_ESCALATION_TIMEOUT=8.0; sample at t=7.9s → layer≠LAYER_3; t=8.0s → layer=LAYER_3.

---

### Full-Screen Tap Target

**AC-9** — `_idle_min_timer` 触发后，视口内任意坐标的 tap（包括四个角点）均将状态切换为 `HATCHING`。触摸目标不限于蛋精灵的 bounding box。
> GUT: inject HATCH_IDLE_MIN_DISPLAY_MS=0; simulate tap at (0,0); assert state=HATCHING. Repeat for all four corners.

---

### Impulse Tap Behavior (Rule 6, F-3)

**AC-10** — `_tap_accepted=true` 且 `state=WAITING_FOR_TAP` 时，首次 tap 同时触发颤抖冲量（Δt=0 时位移=EGG_IMPULSE_AMPLITUDE）和裂纹序列（state→HATCHING，play_hatch_crack() 被调用）。
> GUT: inject HATCH_IDLE_MIN_DISPLAY_MS=0, EGG_IMPULSE_AMPLITUDE=8.0; simulate tap; assert displacement>0 at Δt=0, state=HATCHING, play_hatch_crack() called once.

**AC-11** — 冲量衰减遵循 F-3：Δt=0 → EGG_IMPULSE_AMPLITUDE; Δt=EGG_IMPULSE_DURATION/2 ≈ EGG_IMPULSE_AMPLITUDE/2 (±0.1px); Δt=EGG_IMPULSE_DURATION → ≤0.01px。
> GUT: inject EGG_IMPULSE_AMPLITUDE=8.0, EGG_IMPULSE_DURATION=0.3; sample at Δt=0/0.15/0.3s; assert values within tolerance.

**AC-12** — 多次冲量叠加：两次间隔 < EGG_IMPULSE_DURATION 的 tap，total_shake_offset = Σ active impulses，不互相替换。
> GUT: trigger two impulses 0.1s apart; at t=0.2s after first, assert total offset > single impulse at same Δt.

---

### Crack Trigger Sequence (Rule 7)

**AC-13** — 首次有效 tap 触发严格 4 步顺序：(1) state=HATCHING，(2) _tap_accepted=false，(3) hatch_sequence_completed 以 CONNECT_ONE_SHOT 连接，(4) play_hatch_crack() 被调用。顺序不可颠倒。
> GUT: spy on all four actions with call order recording; assert exact sequence 1→2→3→4.

**AC-14** — HATCHING 状态下的第二次 tap 不重新调用 play_hatch_crack()。
> GUT: after valid tap, simulate second tap during HATCHING; assert play_hatch_crack() total count=1.

**AC-15** — hatch_sequence_completed 以 CONNECT_ONE_SHOT 连接；手动二次触发该信号不导致 _on_hatch_completed 被第二次调用。
> GUT: emit hatch_sequence_completed twice; assert state transitions to COMPLETED exactly once.

**AC-16** — hatch_sequence_completed 信号连接发生在 play_hatch_crack() 调用之前。
> GUT: verify call order via spy: signal connection precedes play_hatch_crack().

---

### HATCHING Input Behavior (Rule 8)

**AC-17** — HATCHING 状态下每次 tap（HAPTIC_ENABLED=true）触发触觉振动调用恰好一次。
> GUT: spy on _trigger_haptic(); simulate 3 taps during HATCHING; assert called exactly 3 times.

**AC-18** — HATCHING 状态下每次 tap 在 tap 坐标（非蛋中心）生成粒子爆发。
> GUT: spy on _emit_tap_particles(); simulate tap at (100,200); assert called with position=(100,200).

**AC-19** — HATCHING 状态下的 tap 不调用 play_hatch_crack()、play_hatch_idle()，不改变状态。
> GUT: simulate 5 taps during HATCHING; assert state=HATCHING after each; play_hatch_crack() total count remains 1.

**AC-20** — HAPTIC_ENABLED=false 时，HATCHING 期间 tap 无触觉调用；粒子爆发仍正常生成。
> GUT: inject HAPTIC_ENABLED=false; simulate tap during HATCHING; assert _trigger_haptic() count=0, _emit_tap_particles() count=1.

---

### Back Button (Rule 9)

**AC-21** — WAITING_FOR_TAP 状态下，ui_cancel / KEY_BACK 事件不被 HatchScene 消费；事件在 HatchScene 处理后仍为 unhandled；状态保持 WAITING_FOR_TAP。
> GUT: simulate KEY_BACK during WAITING_FOR_TAP; assert event not consumed, state unchanged.

**AC-22** — HATCHING 状态下，ui_cancel / KEY_BACK 事件被 HatchScene 消费（标记 handled）；状态保持 HATCHING；_navigate_to_name_input() 不被调用。
> GUT: simulate KEY_BACK during HATCHING; assert event consumed, state=HATCHING, _navigate_to_name_input() count=0.

---

### Completion and Navigation (Rule 10)

**AC-23** — hatch_sequence_completed 触发后，state=COMPLETED，_celebrate_hold_timer 立即以 wait_time=CELEBRATE_HOLD_DURATION 启动（one-shot，is_stopped()=false）。
> GUT: inject CELEBRATE_HOLD_DURATION=2.5; emit hatch_sequence_completed; assert state=COMPLETED, timer.wait_time=2.5, is_stopped()=false.

**AC-24** — _celebrate_hold_timer 自然到期（期间无 tap）后，_navigate_to_name_input() 被调用恰好一次，路径精确为 `"res://scenes/ui/NameInputScreen.tscn"`。
> GUT: mock _navigate_to_name_input(); inject CELEBRATE_HOLD_DURATION=0.001; emit hatch_sequence_completed; advance time; assert called once with exact path.

**AC-25** — COMPLETED 状态下（计时器未到期前）收到任意 tap，_celebrate_hold_timer 被 .stop()，_navigate_to_name_input() 立即调用（不等待计时器）。
> GUT: inject CELEBRATE_HOLD_DURATION=9999; reach COMPLETED; simulate tap; assert _navigate_to_name_input() called within 1 frame, timer.is_stopped()=true.

**AC-26** — _celebrate_hold_timer.stop() 在 _exit_tree() 中被调用；场景在庆祝计时器运行期间被强制卸载时，不触发导航调用。
> GUT: inject CELEBRATE_HOLD_DURATION=9999; reach COMPLETED; call _exit_tree(); assert timer.is_stopped()=true, _navigate_to_name_input() not called.

**AC-27** — 导航路径参数精确为 `"res://scenes/ui/NameInputScreen.tscn"`（无拼写差异）。
> GUT: capture path argument; assert exact string equality.

---

### Transition Guard (EC-7)

**AC-28** — _is_transitioning=true 时，_navigate_to_name_input() 内的 change_scene_to_file() 不被执行；无论触发多少次，最多调用一次。
> GUT: mock change_scene_to_file(); force _is_transitioning=true; call _advance_to_name_input() twice; assert count=0. Separately: first call (is_transitioning=false) fires; second call (now true) does not → total=1.

**AC-29** — change_scene_to_file() 返回非 OK 错误码时，push_error() 被调用且 _is_transitioning 重置为 false（允许重试）。
> GUT: mock change_scene_to_file() to return ERR_FILE_NOT_FOUND on first call; trigger navigation; assert push_error called, _is_transitioning=false; trigger again; assert change_scene_to_file() called a second time.

---

### Watchdog (EC-5)

**AC-30** — play_hatch_crack() 被调用时，_hatch_watchdog_timer 以 one-shot 模式启动，wait_time=HATCH_SEQUENCE_WATCHDOG_MS/1000.0（默认 8.0s）。
> GUT: inject HATCH_SEQUENCE_WATCHDOG_MS=8000; trigger crack; assert timer.wait_time=8.0, is_stopped()=false.

**AC-31** — hatch_sequence_completed 在看门狗超时前触发时，_hatch_watchdog_timer 被取消（stopped）。
> GUT: start watchdog; emit hatch_sequence_completed; assert timer.is_stopped()=true.

**AC-32** — _hatch_watchdog_timer 到期而 hatch_sequence_completed 未收到时，push_error() 被调用且 _advance_to_name_input() 被调用。状态不永久停留在 HATCHING。
> GUT: inject HATCH_SEQUENCE_WATCHDOG_MS=0; suppress hatch_sequence_completed; advance time; assert push_error called, state≠HATCHING.

---

### Data Boundary (Rule 11)

**AC-33** — 从 _ready() 到 change_scene_to_file() 的完整生命周期内，ProfileManager 所有方法调用次数总计 = 0。
> GUT: replace ProfileManager AutoLoad with a zero-method spy; run full happy-path; assert total call count=0.

**AC-34** — 完整生命周期内，SaveSystem 所有方法调用次数总计 = 0。
> GUT: replace SaveSystem AutoLoad with a zero-method spy; run full happy-path; assert total call count=0.

---

### Glow Formula (F-2)

**AC-35** — glow_intensity(t) = 0.5×(1+sin(2π×t/EGG_GLOW_PERIOD))，以下采样点精确（容差 ±0.01）：t=0→0.50；t=EGG_GLOW_PERIOD/4→1.00；t=EGG_GLOW_PERIOD/2→0.50；t=3×EGG_GLOW_PERIOD/4→0.00。输出始终在 [0.0, 1.0] 内。
> GUT: inject EGG_GLOW_PERIOD=2.5; call glow_intensity() at four sample points; assert within tolerance; verify output range with arbitrary t values.

---

### Tuning Knob Injection

**AC-36** — 所有 8 个 Tuning Knob 可在不修改场景文件的情况下按实例覆盖，注入非默认值时对应行为发生改变。

| Knob | 默认值 | 关联 ACs |
|------|--------|---------|
| HATCH_IDLE_MIN_DISPLAY_MS | 1500ms | AC-5, AC-6, AC-7 |
| IDLE_ESCALATION_TIMEOUT | 8.0s | AC-7, AC-8 |
| EGG_GLOW_PERIOD | 2.5s | AC-35 |
| CELEBRATE_HOLD_DURATION | 2.5s | AC-23, AC-24, AC-25 |
| HAPTIC_ENABLED | true | AC-17, AC-20 |
| EGG_IMPULSE_AMPLITUDE | 8.0px | AC-10, AC-11 |
| EGG_IMPULSE_DURATION | 0.3s | AC-11, AC-12 |
| HATCH_SEQUENCE_WATCHDOG_MS | 8000ms | AC-30, AC-32 |

---

### GUT 替身需求（可测试性契约）

为使以上 GUT 测试可行，HatchScene 实现**必须**将以下三处调用封装为独立方法：

| 封装方法 | 替代的直接调用 | 关联 ACs |
|---------|-------------|---------|
| `_navigate_to_name_input()` | `get_tree().change_scene_to_file(...)` | AC-24, AC-25, AC-27, AC-28, AC-29 |
| `_trigger_haptic()` | `Input.vibrate_handheld(...)` | AC-17, AC-20 |
| `_emit_tap_particles(pos: Vector2)` | 粒子节点触发逻辑 | AC-18, AC-20 |

**程序员实现时须注意此契约**：三个包装方法是 GUT spy 注入的前提条件，不得将这三处逻辑内联至 `_unhandled_input()` 或 `_process()` 中。

## Open Questions

| # | 问题 | 优先级 | 解决于 | 状态 |
|---|------|--------|--------|------|
| OQ-1 | **GameRoot 场景导航机制**：Rule 10d 目前直接调用 `get_tree().change_scene_to_file()`。若 GameRoot GDD 最终定义导航通过信号或统一路由方法（参见 MainMenu OQ-1），Rule 10d 和 AC-24/27 均需对应更新。 | HIGH | GameRoot GDD | Open |
| OQ-2 | **HATCH_IDLE 环境音音量调优**：环境脉冲音定为 −24 dB，但实际效果需在真机测试。若分散孩子对蛋的注意力，可降至 −30 dB 或移除。此为测试决策，不影响其他规格。若真机测试证实 20–60Hz 不可闻，此音效自动删除（CD-1）。 | LOW | Week 3 原型测试 | Open |
| OQ-3 | **CELEBRATE sting 时长与 CELEBRATE_HOLD_DURATION 对齐**：策略 A 要求 sting 在 CELEBRATE_HOLD 结束前 ≥ 500ms 衰减至零。CELEBRATE_HOLD_DURATION 的最终默认值须在音频资产完成后与音频设计师对齐（当前 2.5s 为估算值）。⚠️ 音频资产投入生产前必须解决（CD-3）。 | MEDIUM | 音频资产交付时 | Open |
| OQ-4 | **幼龙软鸣（HATCH_EMERGE 可选音效）**：当前标注为可选——原型测试中若孩子反应为惊吓而非惊喜，仅保留壳片摩擦声。需要用户测试数据支持最终决策。 | LOW | Week 3 用户测试 | Open |
