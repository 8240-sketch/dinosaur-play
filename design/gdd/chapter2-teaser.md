# Chapter2Teaser

> **Status**: Approved — CD-GDD-ALIGN APPROVED WITH NOTES 2026-05-08; N-1 applied (Chapter 2 theme locked to 动物); N-2/N-3 noted in Visual/Audio
> **Author**: user + agents
> **Last Updated**: 2026-05-08
> **Implements Pillar**: P1（看不见的学习）、P4（家长是骄傲见证者）

## Overview

Chapter2Teaser 是章节通关序列的收尾场景，在 PostcardGenerator 写入完成后由 GameScene 自动加载，无需孩子任何操作。数据层：完全无上游依赖——不查询 VocabStore、ProfileManager 或任何 AutoLoad 单例——以动物主题轮廓剪影图片 + 固定文案构成的静态 Godot 场景，通过 `Tween` 驱动 3 秒全屏渐出动画，动画完成后自动切换至主菜单并自销毁（`queue_free()`）。场景切换方式（`SceneTree.change_scene_to_file()` vs 信号委托 GameScene 切换）的技术选择在设计上留出灵活性，待实现阶段以 ADR 记录（见 Open Questions OQ-1）。玩家层：孩子通关后屏幕上缓缓浮现一组神秘动物剪影，3 秒渐出，画面中出现短句「还有更多冒险……」；整个序列对情绪不产生打断，不要求任何输入。这一画面向孩子传达「这次冒险是更大故事的开始」，在不使用任何显式学习框架的前提下建立对第2章的期待（P1：看不见的学习）；家长若在旁边看到，会感受到产品系列感（P4：家长是骄傲见证者）。

## Player Fantasy

通关之后，孩子还没来得及放手，屏幕上出现了几个陌生的轮廓。不是恐龙——是别的什么，安静地站在那里。孩子看着它们，心里不是笼统的「好奇」，而是一种更具体的感觉：T-Rex 认识我了，那这些家伙是不是还不认识我？

那 3 秒里，孩子已经开始打算下次要去找它们说话了。不需要任何提示，不需要「还想玩吗？」的弹窗——孩子自己已经决定了。

**设计验证标准**：孩子看完这 3 秒后，能否自主说出想再玩的意思，或指着屏幕问「那是谁」？——可观察，可测试，不依赖家长引导。

## Detailed Design

### Core Rules

1. **生命周期与节点身份**：Chapter2Teaser 是普通节点（非 AutoLoad），由 GameScene 在 PostcardGenerator 完成后立即实例化并 `add_child`。生命周期单向线性：`add_child` → `_ready()` 初始化 → HOLDING → FADING → `change_scene_to_file()` → 节点随场景切换销毁。节点不可重用、不可重置。

2. **串行实例化时序**：GameScene 订阅 PostcardGenerator 的 `postcard_saved(path: String)` 和 `postcard_failed(reason: String)` 信号，任一信号触发（成功或失败）均视为「明信片阶段结束」，立即实例化 Chapter2Teaser。GameScene 设 `_teaser_shown: bool` guard，防止同一章节内重复实例化。PostcardGenerator 在发出信号后 `queue_free()` 自销毁；二者无节点树重叠。

3. **动画两阶段结构**：
   - **HOLDING 阶段**：`_ready()` 完成后立即进入，持续 `HOLD_DURATION`（默认 0.5s），静态展示动物剪影，`CanvasLayer.modulate.a = 1.0`（全不透明）。使用 `get_tree().create_timer(HOLD_DURATION)` 等待。
   - **FADING 阶段**：HOLD 计时器到期后启动 `Tween`，将 `CanvasLayer.modulate.a` 从 `1.0` 渐变至 `0.0`，持续 `FADE_OUT_DURATION`（默认 2.5s）。Tween 配置：`TRANS_SINE`，`EASE_IN`。
   - 总展示时长 = HOLD_DURATION + FADE_OUT_DURATION = **3 秒**（默认值之和）。

4. **场景切换（Path A — 自主切换）**：Tween 的 `finished` 信号触发后，Chapter2Teaser 直接调用 `get_tree().change_scene_to_file("res://scenes/ui/MainMenu.tscn")`。`change_scene_to_file()` 内部以 `call_deferred` 方式执行，帧安全。Path A 下节点随场景销毁，无需显式 `queue_free()`。

5. **超时保障**：`_ready()` 同时启动超时计时器（`TWEEN_TIMEOUT_SEC = 5.0`）。Tween 正常完成时在 `finished` 回调内 `timer.stop()` 取消；若超时先触发（Tween 异常静默失败），直接调用 `get_tree().change_scene_to_file()`，确保孩子不被卡住。两条路径均不向玩家展示任何错误提示。

6. **场景内容（静态）**：内容全部硬编码在场景文件，无数据查询：
   - 背景：深色渐变（美术在场景文件中配置）
   - 主视觉：4–6 个动物轮廓剪影（`@export` 暴露节点引用，美术在编辑器中指定资产）
   - 文案：`const TEASER_TEXT = "还有更多冒险……"`，居中 Label，字号 `TEASER_FONT_SIZE = 48`（px）
   - 根节点为 CanvasLayer，确保全屏覆盖、遮挡所有下层 UI

7. **禁止输入响应**：整个生命周期内不响应任何触屏、按键或系统返回事件，不实现 `_input()` / `_unhandled_input()`。ProcessMode 保持默认 `PROCESS_MODE_PAUSABLE`；App 转后台时 SceneTree 暂停，Tween 与超时计时器均暂停，App 恢复后自动继续（框架保证，无需额外处理）。

---

### States and Transitions

| 状态 | 描述 | 进入条件 | 退出条件 |
|------|------|---------|---------|
| **IDLE** | 节点已实例化，等待 `_ready()` | `add_child` 后初始状态 | 引擎调用 `_ready()` |
| **HOLDING** | 静态展示剪影，`modulate.a = 1.0` | `_ready()` 完成，HOLD 计时器启动 | HOLD 计时器到期 → FADING；TWEEN_TIMEOUT 触发 → TRANSITIONING |
| **FADING** | Tween 渐出 `modulate.a`：1.0 → 0.0 | HOLDING 计时器到期，Tween 启动 | `Tween.finished` → TRANSITIONING；TWEEN_TIMEOUT 触发 → TRANSITIONING |
| **TRANSITIONING** | `change_scene_to_file()` 已调用 | `Tween.finished` 或 TWEEN_TIMEOUT 触发 | 引擎完成场景切换，节点销毁 |

```
IDLE → HOLDING → FADING → TRANSITIONING → (节点销毁)
           ↑          ↑
           └──────────┴── TWEEN_TIMEOUT 超时跳过剩余阶段直达 TRANSITIONING
```

---

### Interactions with Other Systems

| 系统 | 方向 | 接口 | 说明 |
|------|------|------|------|
| **GameScene**（父节点） | 触发源（间接） | PostcardGenerator 完成信号转发 → `add_child` | GameScene 监听 PostcardGenerator 完成信号，串行实例化 Chapter2Teaser；Chapter2Teaser 不直接依赖 PostcardGenerator |
| **SceneTree** | 调用 | `get_tree().change_scene_to_file("res://scenes/ui/MainMenu.tscn")` | Tween `finished` 或超时后直接调用；内部 call_deferred，帧安全；节点随场景切换自动销毁 |
| **PostcardGenerator**（前序） | 间接时序约束 | `postcard_saved(path)` / `postcard_failed(reason)` | 通过 GameScene 串行逻辑形成时序依赖；PostcardGenerator 完成 → GameScene 实例化 Chapter2Teaser |
| **InterruptHandler** | 无直接依赖 | — | App 转后台 `SceneTree.paused = true`；Tween 与超时计时器均暂停；App 恢复后自动继续（框架保证） |

## Formulas

**T1 — 总展示时长**

```
total_display_time = HOLD_DURATION + FADE_OUT_DURATION
```

| 变量 | 类型 | 说明 | 默认值 | 安全范围 |
|------|------|------|--------|---------|
| `HOLD_DURATION` | float（秒） | 静态展示阶段时长 | 0.5s | 0.0–1.5s |
| `FADE_OUT_DURATION` | float（秒） | Tween 渐出阶段时长 | 2.5s | 1.5–4.0s |
| `total_display_time` | float（秒） | 孩子实际看到剪影的时长 | 3.0s | 2.0–5.0s |

示例（默认值）：`0.5 + 2.5 = 3.0s`

---

**T2 — Tween 缓动曲线**

```
modulate_a(t) = ease_in_sine(1.0 - t / FADE_OUT_DURATION)
              ≈ 1.0 - sin((t / FADE_OUT_DURATION) × π/2)
```

| 变量 | 类型 | 说明 |
|------|------|------|
| `t` | float（秒） | 自 FADING 阶段开始的经过时间，0 ≤ t ≤ FADE_OUT_DURATION |
| `modulate_a(t)` | float | CanvasLayer `modulate.a` 值，1.0（开始）→ 0.0（结束） |

EASE_IN 选用原因：开始慢→结尾快，孩子有足够时间看清剪影，渐出加速产生「消失感」；与 PostcardGenerator 完成后的自然情绪降落吻合。

示例（t = 1.25s，即 FADE_OUT_DURATION 的中点）：`modulate_a ≈ 0.29`（偏暗，符合 EASE_IN 前慢后快特征）

---

**T3 — 超时门限**

```
TWEEN_TIMEOUT_SEC ≥ HOLD_DURATION + FADE_OUT_DURATION + δ
```

| 变量 | 说明 | 默认值 |
|------|------|--------|
| `TWEEN_TIMEOUT_SEC` | 超时保障计时器时长 | 5.0s |
| `δ` | 安全余量，留给低配设备帧调度延迟 | ≥ 1.5s（默认余量 = 5.0 − 3.0 = 2.0s） |

约束：`TWEEN_TIMEOUT_SEC` 必须严格大于 `total_display_time`；否则超时会在 Tween 完成前触发，导致提前跳转。

## Edge Cases

| # | 场景 | 处理方式 |
|---|------|----------|
| E1 | Tween 对象未触发 `finished`（静默失败或 GC 回收） | `TWEEN_TIMEOUT_SEC = 5.0s` 的 Timer 触发，调用 `_do_scene_transition()`，切换至 MainMenu；场景切换不依赖 Tween 成功 |
| E2 | HOLD 阶段（0–0.5s）App 切至后台 | InterruptHandler 执行 `SceneTree.paused = true`；HOLD Timer、Tween 及超时 Timer 全部冻结；App 恢复后从暂停点继续播放，不在后台触发切场景 |
| E3 | FADING 阶段（0.5–3.0s）App 切至后台 | 同 E2：Tween 冻结于当前 alpha（例如 0.6），超时 Timer 同步冻结；App 恢复后 Tween 从当前 alpha 继续渐出剩余部分，正常切换至 MainMenu |
| E4 | `Tween.finished` 与超时 Timer 在同一帧内同时触发 | `_do_scene_transition()` 内以 `_transitioning: bool` 标志防重入：首次调用设置标志并执行切换，后续同帧调用检测标志后提前 `return`，确保 `change_scene_to_file()` 仅调用一次 |
| E5 | 剪影贴图文件在导出包中缺失 | Godot 4 渲染品红占位纹理，不触发致命错误；Tween 与场景切换逻辑按计划执行，孩子看到破损剪影但 MainMenu 正常加载 |
| E6 | `res://scenes/ui/MainMenu.tscn` 在导出包中缺失 | `change_scene_to_file()` 返回 `ERR_FILE_NOT_FOUND`；Chapter2Teaser 留在屏幕上（此时 alpha = 0，全黑屏，无交互路径）。缓解：`_ready()` 中以 `assert(ResourceLoader.exists("res://scenes/ui/MainMenu.tscn"))` 在开发期提前暴露 |
| E7 | Android OOM 系统在预告播放期间强杀进程 | PostcardGenerator 在发出 `postcard_saved`/`postcard_failed` 信号**后** Chapter2Teaser 才被创建，章节进度此时已落盘；下次冷启动从入口场景正常加载，进度不丢失 |
| E8 | GameScene 在预告播放期间被销毁（极端路径：profile 切换） | Chapter2Teaser 随父节点销毁，Tween 自动中止，`_do_scene_transition()` 不再执行；章节数据在 PostcardGenerator 阶段已写入，无数据丢失风险 |

## Dependencies

### 上游依赖（本系统依赖这些系统）

| 系统 | 依赖类型 | 具体接口 |
|------|---------|---------|
| **GameScene**（父节点） | 生命周期控制 | GameScene 监听 PostcardGenerator 的完成信号后实例化 Chapter2Teaser 并 `add_child`；Chapter2Teaser 无需主动发现父节点 |
| **PostcardGenerator**（前序，间接） | 时序约束 | `postcard_saved(path)` / `postcard_failed(reason)` 经 GameScene 转发；Chapter2Teaser 不直接订阅，仅依赖「PostcardGenerator 先完成」的时序保证 |
| **InterruptHandler** | 行为约定 | `SceneTree.paused = true` 在 App 转后台时由 InterruptHandler 执行；Chapter2Teaser 的 Tween/Timer 行为依赖此约定（见 E2/E3） |

### 下游依赖（依赖本系统的系统）

无。Chapter2Teaser 是章节通关序列的末端节点，无其他系统依赖其输出或信号。

### 双向声明要求

- **GameScene**：需在 GameScene 实现阶段补充「PostcardGenerator 完成 → 实例化 Chapter2Teaser」的串行逻辑（`_teaser_shown` guard）
- **PostcardGenerator GDD**（已批准）：不需要更新；Chapter2Teaser 通过 GameScene 间接触发，PostcardGenerator 不感知下游

## Tuning Knobs

| 常量 | 默认值 | 安全范围 | 影响的行为 |
|------|--------|---------|-----------|
| `HOLD_DURATION` | 0.5s | 0.0–1.5s | 静态展示阶段时长。值过短（< 0.2s）→ 孩子来不及看清剪影轮廓；值过长（> 1.5s）→ 总时长超出情绪节奏窗口 |
| `FADE_OUT_DURATION` | 2.5s | 1.5–4.0s | Tween 渐出时长。值过短（< 1.5s）→ 渐出太急，像 UI 闪烁而非诗意消失；值过长（> 4.0s）→ 孩子等待时间过久，情绪期待被消耗 |
| `TWEEN_TIMEOUT_SEC` | 5.0s | > HOLD_DURATION + FADE_OUT_DURATION + 1.5s | 兜底超时门限。**不可将此值调至小于 total_display_time**，否则超时在 Tween 完成前触发，导致动画被截断。安全下限 = 当前 total_display_time + 1.5s |
| `TEASER_FONT_SIZE` | 48px | 36–64px | 文案「还有更多冒险……」字号。低于 36px 在小屏 Android 设备（360dp）上过小；高于 64px 与剪影视觉争夺注意力 |
| `MAIN_MENU_SCENE_PATH` | `"res://scenes/ui/MainMenu.tscn"` | 任意有效 `.tscn` 路径 | 预告结束后切换至的目标场景；修改时同步更新 E6 断言中的路径 |

## Visual/Audio Requirements

> **美术意图锚点**：预告是「神秘的第一眼」，不是「下一章广告」。剪影必须让孩子感到「那些家伙还不认识我」——静止、安静、等待被认识。

**背景**

竖向线性渐变（`ColorRect` 全屏覆盖，`GradientTexture2D`）：

| 位置 | 颜色 | Hex | 语义 |
|------|------|-----|------|
| 底部（100%） | 暖琥珀橙 | `#E8845A` | 地平线余晖，呼应游戏现有暖橙色系 |
| 中部（50%） | 玫瑰紫红 | `#C4566A` | 黄昏过渡，保持温暖 |
| 顶部（0%） | 深紫 | `#2D1B4E` | 天空渐深，剪影从暗处浮现 |

禁止加入亮星星/闪光粒子（分散注意力，与「神秘等待」情绪相悖）。

> **N-2 实现注意（CD-GDD-ALIGN）**：背景顶部色 `#2D1B4E` 与剪影色 `#2B1B4E` 仅差 R:2，在深色背景中可能对比不足。实现阶段美术须在真机上目视验证长颈鹿头部轮廓可辨；如对比不足，可将剪影色调亮至 `#3D2B5E` 或将背景顶部加深至 `#1D0B3E`。

> **N-3 实现注意（CD-GDD-ALIGN）**：黄昏紫红渐变对 4–6 岁幼儿的情绪影响存在低风险不确定性。建议在第一次内部测试时以 1 名无引导幼儿观察为基准——观察孩子看完 3 秒后的自然反应（好奇/安静 vs. 不适）。如有不适迹象，可将顶部深紫替换为深蓝 `#1B2D6E`。

**剪影**

**数量：5 个**（奇数，4 个过于对称，6 个在 360dp 竖屏上过于拥挤）

| 动物 | 轮廓辨识依据 | 构图高度（屏幕高度比例） |
|------|------------|----------------------|
| 长颈鹿 | 极长颈部，全场最高 | ~38% |
| 大象 | 象鼻 + 大耳，宽扁轮廓 | ~28% |
| 狮子 | 皇冠状鬃毛，头部剪影辨识度最高 | ~22% |
| 河马 | 宽圆头 + 低扁身体，大质量感但无攻击性 | ~16% |
| 猴子 | 卷曲尾巴 + 弯腰姿态，形体最小巧 | ~14% |

**剪影颜色：`#2B1B4E`（深暖紫）** — 禁止纯黑（幼儿恐惧联想）。

**姿态约束：** 所有剪影侧面（profile）或 3/4 侧面朝向，**绝对不正面朝向屏幕**（正面会触发幼儿「被盯着看」焦虑）。姿态静止，不采用奔跑/张嘴等动作姿态（与 T-Rex NPC 的动态姿态形成区隔）。

**构图**

地平线群像布局：剪影脚部基准线位于屏幕高度 62% 处。水平排列（左→右）：猴子 → 大象 → 狮子 → 长颈鹿 → 河马。剪影整体占据屏幕 20%–65% 垂直区域；长颈鹿头顶不超过屏幕顶部 22%；各动物间留 8–12dp 间隙，保证轮廓可辨。

**文案「还有更多冒险……」**

- 字体：Nunito Bold（游戏统一字体）
- 字号：`TEASER_FONT_SIZE`（48px，见 Tuning Knobs）
- 颜色：`#FFF3C4`（暖奶油黄）
- 文字阴影：`rgba(45, 27, 78, 0.55)`，偏移 0/2px，模糊 8px
- 位置：水平居中，垂直 78% 处（剪影群组下方）
- **动画处理：随 CanvasLayer `modulate.a` 统一渐出，不设独立动画**

**音频**

推荐加入一段轻柔音效 Sting（不使用完全静默）：

| 参数 | 规格 |
|------|------|
| 类型 | 2–3 音符上行旋律（木琴 / 马林巴 / 音乐盒音色） |
| 时长 | 2.0–2.5s，与 FADING 阶段对齐 |
| 音量 | `-14dB` |
| 起始时机 | HOLDING 阶段开始即播放（第 0 秒） |
| 结束方式 | 自然尾音消失；`AudioStreamPlayer.volume_db` 随 Tween 渐出至 `-60dB` |
| 素材授权 | CC0；推荐来源：freesound.org（「marimba sting ascending」或「music box wonder」） |

上行旋律在听觉中普遍编码「疑问/期待」，对 4–6 岁幼儿无需文化学习即有效。禁止使用真实动物叫声（在静默后突然出现对幼儿存在惊吓风险；动物叫声保留至第 2 章正式游戏内容使用）。

## UI Requirements

Chapter2Teaser 是全自动播放的关闭场景，无菜单、无按钮、无交互元素。

**Godot 节点树**

```
Chapter2Teaser (CanvasLayer)           ← 根节点，modulate.a 由 Tween 控制
├── Background (ColorRect)             ← 全屏渐变背景，锚点 FULL_RECT
├── SilhouetteContainer (Node2D)       ← 管理 5 个剪影，便于美术批量调整
│   ├── Silhouette_Monkey (Sprite2D)   ← @export 资产引用
│   ├── Silhouette_Elephant (Sprite2D)
│   ├── Silhouette_Lion (Sprite2D)
│   ├── Silhouette_Giraffe (Sprite2D)
│   └── Silhouette_Hippo (Sprite2D)
├── TeaserLabel (Label)                ← 文案「还有更多冒险……」，居中锚点
└── SoundPlayer (AudioStreamPlayer)    ← 音效 Sting，volume_db 随 Tween 渐出
```

**节点规范：**
- CanvasLayer 的 `layer` 属性设为高值（如 `10`），确保覆盖 GameScene 所有下层 UI
- 所有 Sprite2D 的 `mouse_filter` 设为 `MOUSE_FILTER_IGNORE`（不拦截触摸事件）
- TeaserLabel 的 `mouse_filter` 设为 `MOUSE_FILTER_IGNORE`
- 不实现任何 `_input()` / `_gui_input()` 函数

**@export 暴露至编辑器（供美术直接配置）：**

```gdscript
@export var silhouette_textures: Array[Texture2D]  ## 顺序: [猴子, 大象, 狮子, 长颈鹿, 河马]
@export var teaser_sound: AudioStream               ## CC0 音效资产
```

## Acceptance Criteria

所有 BLOCKING 条件必须通过；ADVISORY 条件在发布前截图存档至 `production/qa/evidence/`。

| # | 条件 | 类型 |
|---|------|------|
| AC-1 | PostcardGenerator 发出 `postcard_saved` **或** `postcard_failed` 任一信号后，Chapter2Teaser 节点被实例化并加入 GameScene 场景树，无需额外调用启动方法 | BLOCKING |
| AC-2 | `_ready()` 完成后，CanvasLayer `modulate.a = 1.0`，画面在 HOLDING 阶段（0.5s）内静止不变，不提前启动 Tween | BLOCKING |
| AC-3 | HOLDING 计时器到期后，Tween 在 2.5s 内将 CanvasLayer `modulate.a` 从 1.0 连续渐变至 0.0，全程可观察到平滑过渡（非瞬间跳变） | BLOCKING |
| AC-4 | `Tween.finished` 触发后，游戏切换至主菜单；从节点加入场景树到主菜单出现的总耗时在 3.0s ± 0.2s 内（正常流程，不含后台暂停时间） | BLOCKING |
| AC-5 | 若 Tween 在 5.0s（`TWEEN_TIMEOUT_SEC`）内未触发 `finished`，超时计时器触发后游戏仍正常切换至主菜单；孩子不被滞留在预告界面 | BLOCKING |
| AC-6 | HOLDING 和 FADING 全程，在屏幕任意位置点击或滑动均无任何反应，不提前结束动画，不触发场景跳转 | BLOCKING |
| AC-7 | `_teaser_shown` guard 生效：同一章节流程内即使完成信号重复发出，Chapter2Teaser 仅被实例化一次 | BLOCKING |
| AC-8 | HOLDING 或 FADING 阶段 App 切至后台时，Tween 与超时计时器均冻结，后台期间不触发场景切换（ADB 日志确认 `change_scene_to_file` 在前台恢复前未被调用） | BLOCKING |
| AC-9 | App 从后台恢复后，Tween 从暂停时的 `modulate.a` 值继续渐出至 0.0（不重头播放、不瞬间跳至 0），最终正常切换至主菜单 | BLOCKING |
| AC-10 | HOLDING 阶段时，屏幕上可见 5 个动物轮廓剪影（猴子、大象、狮子、长颈鹿、河马），各剪影轮廓可辨，无缺失、无粉色占位块 | ADVISORY |
| AC-11 | HOLDING 阶段时，文案「还有更多冒险……」可见、字体可读，位于剪影群组下方水平居中（截图存档至 `production/qa/evidence/`） | ADVISORY |
| AC-12 | AudioStreamPlayer 在 HOLDING 阶段开始（t = 0）即时播放上行旋律 Sting，声音在 HOLDING 阶段内可听见 | ADVISORY |
| AC-13 | 主菜单切换完成后，Chapter2Teaser 节点已随场景切换自动销毁，不在 MainMenu 场景树中留有残留节点（Godot 调试器 Remote SceneTree 面板验证） | BLOCKING |

## Open Questions

| # | 问题 | 优先级 | 解决时机 |
|---|------|--------|---------|
| OQ-1 | **场景切换 ADR**：本 GDD 选用 Path A（Chapter2Teaser 自主调用 `change_scene_to_file()`），技术决策需在实现阶段以 ADR 记录，明确 Path A vs Path B 的取舍理由和 Godot 4.6 行为确认 | MEDIUM | 实现 Chapter2Teaser 时创建 ADR-0004 |
| OQ-2 | **AudioStreamPlayer volume_db Tween 实现细节**：`AudioStreamPlayer` 不受 CanvasLayer `modulate.a` 影响，需单独 Tween `volume_db` 从 `-14dB` 渐出至 `-60dB`。具体是与主 Tween 合并为一个 Tween 对象（`tween_property` 两个属性并行），还是分开的 Timer + `stop()`？ | LOW | 实现阶段确认（不阻断设计批准） |
| OQ-3 | **`silhouette_textures` 排列顺序与节点绑定**：`@export var silhouette_textures: Array[Texture2D]` 依赖美术按约定顺序填入，若顺序错误则剪影与节点不匹配。是否需要在 `_ready()` 中增加 `assert(silhouette_textures.size() == 5)` 防护？ | LOW | 实现阶段确认 |
