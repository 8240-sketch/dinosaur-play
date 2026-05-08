# NameInputScreen

> **Status**: Approved — CD-GDD-ALIGN APPROVED WITH NOTES 2026-05-08; CD-1~CD-2 applied
> **Author**: Zhang Shaocong + agents
> **Last Updated**: 2026-05-08
> **Implements Pillar**: P1 (看不见的学习), P4 (家长是骄傲见证者)

## Overview

NameInputScreen 是首次启动链中的最后一站——在 HatchScene 孵化仪式结束后、进入 MainMenu 之前出现，且每台设备终生执行一次。**技术层面**：这是整个游戏唯一一处调用 `ProfileManager.create_profile(0, name, avatar_id)` 的场景；创建完成后立即调用 `switch_to_profile(0)` 激活档案，然后导航至 MainMenu。输入约束由 `NAME_MAX_LENGTH`（= 20 字符）常量统一控制，UI 层与数据层共用同一常量，不得硬编码。**体验层面**：这是家长与孩子共同完成的第一个「属于我们的」时刻。孵化刚刚发生，T-Rex 还在屏幕上闪着喜悦——家长弯下腰，和孩子商量一个名字，选一个头像（孩子会指着说「这个！这个！」）。名字和头像是孩子日后认出「这是我的恐龙」的两条线索。屏幕可跳过：若家长希望孩子尽快进入游戏，点击跳过后默认填入「小朋友」；ProfileManager 仍创建完整档案，游戏正常进行。NameInputScreen 不感知孵化蛋的状态、不读取任何已有档案数据、不播放动画——它是一个轻量的「命名礼」界面，完成即消失，永不再出现。

## Player Fantasy

NameInputScreen 服务的是家长与孩子同框的那个罕见时刻——不是「我帮你操作」，而是「我们一起做这件事」。

**家长的那一刻**：孵化刚刚结束，家长弯下腰，一个字一个字打出孩子的名字，动作和在第一本故事书扉页写题词时很像。屏幕不催促，给足时间。孩子靠在大人身边，看着自己的名字出现在屏幕上——不是「小朋友」，是我。「这个游戏知道我叫什么」的感受，往后每次 T-Rex 叫出名字时都会被唤起，而它的起点在这里。

**孩子的那一刻**：头像选择界面出现时，孩子是唯一有权决定的人——家长只是帮忙点。四岁的孩子很少有机会做一个真正永久的决定：这只恐龙的脸是孩子用手指指定的，选完就是这样了，家长在旁边见证。一个有人目睹的永久选择——这只属于他的恐龙，从此长成了那个样子。

两个人各有一件事要做：一件由大人完成，一件由孩子决定，合起来才算结束。仪式感不是屏幕上加了一朵烟花，而是这两件事必须都发生，缺一不可。

## Detailed Design

### Core Rules

**Rule 1 — 入口前置守卫**
NameInputScreen 只能由 GameRoot 经首次启动链（HatchScene 结束后）路由进入。`_ready()` 时调用 `ProfileManager.profile_exists(0)`；若返回 `true`：`push_error`，中止所有初始化，不展示任何交互元素。正常首次启动流程中此条件永远为 `false`（GameRoot 已保证仅在 slot 0 无档案时路由至此屏幕）。

**Rule 2 — 名字输入框行为**
`LineEdit` 占位符文字：「给 T-Rex 起个名字吧~」。`_ready()` 时不自动获取焦点、不自动弹出软键盘；家长点击输入框后触发焦点和软键盘（Godot `LineEdit` OS 默认行为）。`LineEdit.clear_button_enabled = true`：输入文字非空时，右侧显示清除图标（✕），单击清空并保留焦点；文字为空时图标自动隐藏。

**Rule 3 — 字符限制：UI 层强制**
`LineEdit.max_length` 设为 `NAME_MAX_LENGTH`（注册表常量 = 20，从 ProfileManager 导入，不硬编码数字）。字符达到上限时静默拒绝后续输入——无错误提示。

**Rule 4 — 头像选择交互**
5 个头像按 3+2 网格排列（上 3 下 2 居中）。`_ready()` 时 `_selected_avatar_index = 0`（index 0 自动选中）。点击非当前头像：目标项执行缩放弹跳（scale 1.0 → 1.12 → 1.0，180ms ease-out），弹跳结束后展示选中指示（圆形边框高亮，颜色 `--accent-dino`，线宽 3dp）；原选中项取消高亮（无动画）。每个头像触摸目标区域 ≥ 88dp × 88dp。任意时刻只有一个头像处于选中状态。

**Rule 5 — 确认按钮**
标签：「完成！」（26sp 粗体白色，`--accent-dino` 暖橙背景，16dp 圆角，触摸目标 ≥ 312×80dp）。**当 `LineEdit.text.strip_edges().is_empty()` 为 `true` 时，确认按钮禁用（不透明度 0.4，触摸无响应）；非空时启用。** 动态监听 `LineEdit.text_changed` 信号以实时更新按钮状态。跳过是唯一的「不起名也能进」路径。

**Rule 6 — 跳过按钮**
标签：「先不起名」（14sp，颜色 `--text-secondary`，无背景，文字链接样式）。位置：屏幕底部，确认按钮正下方 16dp，水平居中，触摸目标高度 ≥ 44dp。行为：**忽略当前输入框内容和已选头像**，固定使用 `("小朋友", avatar[0])` 执行 Rule 8 创建序列，不弹出确认对话框。

*设计取舍说明（CD-1）*：Player Fantasy 中"孩子是唯一有权决定头像的人"指的是走完整命名仪式的路径（确认路径）。跳过代表家长主动放弃命名仪式，此时孩子的头像选择也随之跳过——这是一致的：如果仪式没有发生，仪式的任何一个半成品都不应保存。如果家长希望保留孩子已经指定的头像，正确路径是完成起名（在确认路径中，孩子的选择被完整保留）。跳过是"跳过整个仪式"，不是"跳过名字部分"。

**Rule 7 — 输入值规范化**

| 路径 | `final_name` | `final_avatar_id` |
|------|-------------|-------------------|
| 点击确认 | `LineEdit.text.strip_edges()`（Rule 5 保证非空） | `_avatar_options[_selected_avatar_index].id` |
| 点击跳过 | 固定 `"小朋友"` | 固定 `_avatar_options[0].id` |

`avatar_id` 字符串从头像资产定义读取，不在此处硬编码具体值。

**Rule 8 — 创建 + 激活 + 导航序列（严格 6 步）**
点击确认或跳过后：
- **a.** 立即禁用确认/跳过按钮（`SUBMITTING` 状态，防重复提交），强制 dismiss 软键盘（`DisplayServer.virtual_keyboard_hide()`）
- **b.** 执行 Rule 7 规范化，得到 `final_name`、`final_avatar_id`
- **c.** 调用 `ProfileManager.create_profile(0, final_name, final_avatar_id) -> bool`
- **d.** 若返回 `false` → 执行 Rule 9 错误处理，序列**中止**
- **e.** 调用 `ProfileManager.switch_to_profile(0)`；连接 `profile_switched` 信号（ONE_SHOT），等待 `profile_switched(0)`
- **f.** 信号到达后：`get_tree().change_scene_to_file(SCENE_MAIN_MENU)`（路径常量，不硬编码字符串），交叉淡入过渡（≈300ms）

步骤 e 不设超时：`create_profile(0)` 成功后 slot 0 必然存在，`switch_to_profile(0)` 必然发出 `profile_switched(0)`（ProfileManager GDD Rule 8 保证）。

**Rule 9 — 错误处理：create_profile 返回 false**
屏幕状态 → `IDLE`，重新启用跳过按钮（确认按钮依 Rule 5 条件动态恢复），保留已输入名字与已选头像。显示屏幕内 toast：`--feedback-gentle` 暖橙背景，文字「保存失败，请再试一次」，2 秒后自动消失，**不使用红色**（Anti-Pillar P2）。

**Rule 10 — Android 返回键行为**
软键盘可见时：返回键仅 dismiss 键盘（Android OS 默认行为）。软键盘不可见时：在 `_unhandled_input(event)` 中捕获 `InputEventKey.keycode == KEY_BACK`，调用 `accept_event()` 吞掉事件，不路由至上层界面。理由：NameInputScreen 是首次启动链终止节点，无合理的「上一步」目标。

**Rule 11 — 软键盘弹出时布局适配**
在 `_process()` 中轮询 `DisplayServer.virtual_keyboard_get_height()` 获取键盘高度（若 Godot 4.6 已提供 `virtual_keyboard_height_changed` 信号，优先改用信号）。键盘弹出（高度 > 0）时：将 `ContentContainer`（含输入框 + 头像网格 + 确认/跳过按钮）在 Y 轴上移，偏移量 = 键盘高度，确认按钮底部与键盘顶部余留 ≥ 8dp。键盘收起时恢复初始 `position.y`。不使用 ScrollContainer（单屏内容无需滚动）。

---

### States and Transitions

| 状态 | 含义 | 确认按钮 | 跳过按钮 | LineEdit |
|------|------|---------|---------|---------|
| `IDLE` | 等待输入（初始状态） | 依 Rule 5 动态启/禁 | 可点击 | 可编辑 |
| `SUBMITTING` | Rule 8 步骤 a~f 执行中 | 禁用 | 禁用 | 不可编辑 |

合法转换：`IDLE → SUBMITTING`（点击确认/跳过）；`SUBMITTING → IDLE`（Rule 9 错误路径）；`SUBMITTING → [场景销毁]`（Rule 8 步骤 f 正常退出）。

---

### Interactions with Other Systems

| 调用方 | API | 时机 |
|--------|-----|------|
| NameInputScreen → ProfileManager | `profile_exists(0)` | `_ready()` 前置守卫（Rule 1） |
| NameInputScreen → ProfileManager | `create_profile(0, name, avatar_id)` | Rule 8 步骤 c |
| NameInputScreen → ProfileManager | `switch_to_profile(0)` | Rule 8 步骤 e |
| (signal) ProfileManager → NameInputScreen | `profile_switched(new_index)` | Rule 8 步骤 e：ONE_SHOT 连接，确认激活完成 |
| NameInputScreen → SceneTree | `change_scene_to_file(SCENE_MAIN_MENU)` | Rule 8 步骤 f（正常退出） |
| HatchScene → NameInputScreen | `change_scene_to_file(...)` | HatchScene COMPLETED 状态导航至此（入境） |

## Formulas

NameInputScreen 不包含数值公式。本节定义两个可测试的算法谓词——覆盖 Rule 5 的按钮状态约束与 Rule 7 的输入规范化契约。

### F-1 — 确认按钮启用谓词（confirm_enabled）

```
sanitized_text  := strip_edges(raw_text).replace("\u3000", "")
confirm_enabled := NOT sanitized_text.is_empty()
                 = (sanitized_text.length() >= 1)
```

| 符号 | 类型 | 范围 | 说明 |
|------|------|------|------|
| `raw_text` | string | 0–`NAME_MAX_LENGTH` 字符 | `LineEdit.text` 当前值（含首尾空白和全角空格） |
| `sanitized_text` | string | 0–`NAME_MAX_LENGTH` 字符 | 去除首尾半角空白（`strip_edges`）及全角空格（`U+3000`）后的值 |
| `confirm_enabled` | bool | {true, false} | 确认按钮可点击状态 |

**输出范围**：布尔。`true` = 可点击；`false` = 不透明度 0.4，触摸无响应。

**示例**：`raw_text = "　"（全角空格）` → `sanitized_text = ""` → `confirm_enabled = false`；`raw_text = " 小明 "` → `sanitized_text = "小明"` → `confirm_enabled = true`

---

### F-2 — 输入规范化输出值域（name normalization）

```
[确认路径]  final_name      = sanitized_text                 -- 前置条件: confirm_enabled = true
            final_avatar_id = _avatar_options[selected_index].id

[跳过路径]  final_name      = "小朋友"                        -- 固定常量，忽略 raw_text
            final_avatar_id = _avatar_options[0].id          -- 固定第一项，忽略 selected_index
```

| 符号 | 类型 | 范围 | 说明 |
|------|------|------|------|
| `sanitized_text` | string | 1–`NAME_MAX_LENGTH` 字符 | F-1 `sanitized_text`（确认路径前置条件保证 length ≥ 1） |
| `selected_index` | int | 0–4 | 当前选中头像下标（`_selected_avatar_index`） |
| `final_name` | string | 确认路径：1–20 字符；跳过路径：固定 `"小朋友"` | 传入 `create_profile()` 的名字参数 |
| `final_avatar_id` | string | avatar 资产定义 id 集合 | 传入 `create_profile()` 的头像参数 |

**输出范围**：
- 确认路径：`final_name.length()` ∈ [1, 20]（下界由 F-1 前置条件保证，上界由 Rule 3 `LineEdit.max_length` 保证）
- 跳过路径：`final_name = "小朋友"`（3 字符），恒成立，与界面状态无关

**示例（确认路径）**：`raw_text = " 花花 "`, `selected_index = 2` → `final_name = "花花"`, `final_avatar_id = _avatar_options[2].id`

**示例（跳过路径）**：`raw_text = "任意值"`, `selected_index = 3` → `final_name = "小朋友"`, `final_avatar_id = _avatar_options[0].id`

**依赖关系**：F-2 确认路径以 `F-1 confirm_enabled = true` 为前置条件——Rule 5 的按钮禁用逻辑从结构上阻止了空名字进入 `create_profile()`；F-2 无需重复校验。

## Edge Cases

- **EC-1 — 全角空格输入**：如果 `raw_text` 含一个或多个全角空格（U+3000），F-1 在 `strip_edges()` 之后追加 `.replace("\u3000", "")` 清除全角空格；结果为空时 `confirm_enabled = false`，确认按钮禁用，用户无法提交视觉上为空的名字。半角空格（U+0020）由 `strip_edges()` 已处理，无需额外分支。

- **EC-2 — 输入恰好达到 NAME_MAX_LENGTH（20 字符）**：如果 `raw_text` 为 20 个可见字符，`sanitized_text` length = 20，命中 F-2 输出范围上界，`create_profile()` 正常写盘。若为「1 个前置空格 + 19 个字符」（共 20 字符），`sanitized_text` length = 19，同样合法，无歧义。

- **EC-3 — App 在 SUBMITTING 状态被切到后台**：如果 Rule 8 步骤 c（`create_profile` 执行中）时 App 切后台，InterruptHandler 触发 `ProfileManager.flush()`；此时 ProfileManager 处于 `NO_ACTIVE_PROFILE` 状态，`flush()` 静默返回 false，不影响 `create_profile()` 直接调用的 `SaveSystem.flush_profile` 已写盘内容。如果发生在步骤 e 的 `await` 期间，GDScript 主线程在 Android 后台继续运行，`profile_switched(0)` 信号仍将发出，步骤 f 正常执行，用户回到前台时已处于 MainMenu。

- **EC-4 — OS 强杀后从步骤 c 中途重启**：如果 `create_profile(0)` 已写盘但 `switch_to_profile(0)` 尚未完成时进程被强杀，下次冷启动：`profile_exists(0)` 返回 true，GameRoot 不进入首次启动链，正常路由至 MainMenu（档案存在，可正常游戏）。若 GameRoot 因 bug 再次路由至 NameInputScreen：Rule 1 前置守卫检测到 `profile_exists(0) == true`，`push_error` + 中止初始化，不展示任何交互元素，防止覆盖已有档案。

- **EC-5 — `profile_switched` 信号携带非 0 的 new_index**：理论上不可能（步骤 e 显式调用 `switch_to_profile(0)`，ProfileManager 单线程确定性发出 `profile_switched(0)`）。防御性设计要求 ONE_SHOT 处理器在步骤 f 前校验 `new_index == 0`；若 `new_index ≠ 0`：`push_error`，不执行 `change_scene_to_file`，屏幕停留在 `SUBMITTING` 状态（两个按钮禁用，安全静止），不展示用户可见错误。

- **EC-6 — 用户连续快速点击确认 / 跳过（重复提交保护）**：Rule 8 步骤 a 是第一个 `_gui_input` 处理时的同步操作（`button.disabled = true`），GDScript 单线程保证同帧内后续事件到来时按钮已禁用，触摸被静默拦截。若用户几乎同时点击确认和跳过（两个不同节点），第一个事件进入步骤 a 后两个按钮同时禁用，第二个事件到来时均已禁用，创建序列不会被重入。

- **EC-7 — 软键盘完全遮住头像网格**：如果 360×800dp 屏幕上键盘高度达 280dp，Rule 11 将 ContentContainer 上移 280dp，头像网格被推出屏幕上边界，不可见且无法触摸。这是**设计意图**：家长输入名字时专注于 LineEdit，头像选择留待收起键盘后操作，两者不需要同时可见。在 360×800dp 设备上验证时，此状态为已验证预期行为，非 Bug。

- **EC-8 — Emoji 输入（MVP 已知限制）**：GDScript `String.length()` 按 Unicode 码位计算，ZWJ emoji 序列占多个码位，可能在视觉符号数量很少时就触发 `NAME_MAX_LENGTH` 上限；Godot 默认字体不渲染 emoji（显示方块）。MVP 不加字符集白名单过滤——4-6 岁儿童使用场景中输入 emoji 概率极低，家长输入阶段通常使用系统输入法而非 emoji 选择器。如需修复：在 F-1 谓词后追加字符集白名单（v1.1 候选项）。

## Dependencies

### 上游依赖

| 系统 | 依赖类型 | 接口 |
|------|---------|------|
| **ProfileManager** | 硬依赖（唯一） | `profile_exists(0)`（Rule 1 守卫）；`create_profile(0, name, avatar_id)`（Rule 8c）；`switch_to_profile(0)`（Rule 8e）；信号 `profile_switched(new_index)`（Rule 8e ONE_SHOT） |

**SaveSystem**：间接依赖，通过 ProfileManager 透明访问，NameInputScreen 不直接调用 SaveSystem 任何 API。

### 下游与架构相邻

| 系统 | 关系 | 说明 |
|------|------|------|
| **HatchScene** | 入境方（软架构依赖） | HatchScene 调用 `change_scene_to_file("...NameInputScreen.tscn")`；NameInputScreen 不感知 HatchScene 的存在 |
| **MainMenu** | 出境方（软架构依赖） | NameInputScreen 调用 `change_scene_to_file(SCENE_MAIN_MENU)`；MainMenu 不依赖 NameInputScreen |

### 双向一致性说明

ProfileManager GDD Interactions 表中 `MainMenu → ProfileManager: create_profile(index, name, avatar_id)` 一行在 ProfileManager GDD 撰写时是占位表述（NameInputScreen GDD 尚未存在）。现更正：**`create_profile()` 的唯一合法调用方是 NameInputScreen，不是 MainMenu**——ProfileManager GDD Interactions 表需在后续维护时修正此行。本 GDD 为权威来源。

### 不依赖的系统（显式排除）

| 系统 | 原因 |
|------|------|
| **StoryManager** | NameInputScreen 仅创建档案，无叙事状态；章节由 MainMenu 发起 |
| **VocabStore** | 档案创建时词汇字段由 ProfileManager 填充默认值（create_profile 内部），不经 VocabStore |
| **TtsBridge** | 全程零 TTS 需求（P1：无文字，无朗读，无提示音） |
| **AnimationHandler** | 无动画系统接入；头像选择弹跳由 Tween 直接实现 |

## Tuning Knobs

| 常量名 | 默认值 | 安全范围 | 影响维度 | 说明 |
|--------|--------|---------|---------|------|
| `AVATAR_BOUNCE_SCALE` | `1.12` | `1.06 – 1.20` | 孩子对点击"已落地"的感知；选中时刻的愉悦强度 | 低于 1.06 在 5 英寸屏幕手持距离下视觉上几乎不可见；高于 1.20 时弹跳帧可能与 3+2 网格中相邻头像重叠，在小屏设备上看起来错位 |
| `AVATAR_BOUNCE_DURATION_MS` | `180` | `120 – 280` | 4-6 岁儿童是否会在动画结束前重复点击（误判输入未响应） | 低于 120ms 动画几乎是无意识的，4-6 岁孩子感知不到，愉悦感归零；高于 280ms 反馈延迟超出幼儿耐心，可能引发快速连击导致弹跳循环 |
| `TOAST_DISMISS_DURATION_SEC` | `2.0` | `1.5 – 4.0` | Rule 9 错误路径（`create_profile` 返回 false）时家长能否读到提示 | 家长在操作屏幕的同时照看 4 岁孩子，2 秒窗口易错过；上限 4.0s，超过后 toast 停留时间长于反应窗口，用户会误认为界面卡死。此路径极少触发，但安全范围不直观，若真机测试中家长反映未看到提示，建议先调至 2.5s |

## Visual/Audio Requirements

### Visual Requirements

**背景（Background）**

- 基底色：`--surface-bg`（暖米白），全屏平铺，无渐变；延续 HatchScene 过渡色调（`#FFF8F0`），视觉无跳切
- 禁止：装饰性背景插图、粒子效果、环境动画；视觉权重全部聚焦在输入区域

**T-Rex 在场**

- 位置：屏幕上方 ~35% 区域，水平居中；播放 `trex_idle` 循环（与 MainMenu Rule 3 相同逻辑：仅空闲动画）；渲染尺寸约 160×160dp——比 HatchScene 孵化时小，角色定位为「陪伴者」而非「主角」
- 键盘弹出时：T-Rex **独立**处理——ContentContainer 上移时，T-Rex 执行独立淡出（透明度 1.0 → 0.0）同时缩小（scale 1.0 → 0.6），目标：T-Rex 以半透明小图存留在屏幕右上角，时长 200ms ease-in-out；键盘收起时以相同时长反向恢复至原始位置和透明度。T-Rex 在输入期间作为无干扰的「角落目击者」存在。

**文字层级（Typography Hierarchy）**

- 主标题：「给 T-Rex 起个名字吧！」，16sp，Nunito Regular，`--text-secondary`，居中，位于 T-Rex 下方 8dp 间距
  - 意图：语境锚定，柔和引导，故意不抢眼——仪式感来自 T-Rex 的在场和操作本身，不靠标题
  - 禁止：大号加粗标题、彩色文字、强调动效
- 头像分区标签：「选一个头像」，12sp，Nunito Regular，`--text-secondary`，左对齐于头像网格上方

**头像视觉规格（Avatar Visual Spec）**

- 风格：手绘圆润插画，与游戏主角 T-Rex 美术语言统一；禁止写实渲染或扁平 icon 风格
- 内容：5 种不同表情/主色调的迷你恐龙脸（物种不限于 T-Rex，可含 Triceratops 等游戏已有角色，增加可识别差异度）
- 色彩要求：每个头像主色调需在明度和色相上同时区分（非仅色相差异）；所有 5 个头像在灰度下可区分（色盲合规）
- 画面构成：面部居中占圆形区域 ≥ 70%；表情微笑或好奇，无攻击性情绪
- 规格：128×128px 透明背景 PNG；触摸目标 88×88dp 由容器保证，此为美术交付尺寸
- 选中指示：3dp `--accent-dino` 圆形边框（Detailed Design 已锁定）；无额外 shadow 或背景填充叠加
- **LineEdit 清除按钮（✕）颜色**：使用 `--text-secondary` 颜色；禁止任何红色或橙色调渲染（Anti-Pillar P2 — ✕ 符号在教育场景有"错误"语义）（CD-2）

**入场动画（Screen Entrance Animation）**

- HatchScene 已定义完整过渡：暖白渐入覆盖层 + NameInputScreen 从底部轻柔滑入，时长 ≥ 400ms；NameInputScreen 不重复定义过渡起点
- 屏幕内元素：随屏幕滑入同步显示，无逐元素淡入或弹出
  - 理由：「命名礼」节奏强调静默到位；逐元素弹出会在家长开始打字前制造视觉噪音
  - T-Rex 在屏幕加载完成的第一帧即开始播放 `trex_idle`，动画本身即存在感

---

### Audio Requirements

**背景音乐（BGM）**

- 首次出现：NameInputScreen 是全游戏 BGM **首次引入**的场景（HatchScene 全程无 BGM）
- 风格：轻柔钢片琴或木琴 loop，带轻微弦乐垫底；速度 ≈ 65–75 BPM，温暖迟缓，无节拍感强的打击乐
- 引入方式：随屏幕到达从 0 淡入至 −14 dB，淡入时长 ≈ 600ms
- Loop 时长：≥ 30 秒，避免 1–2 分钟内明显感知重复
- 架构：BGM 由 **AutoLoad AudioStreamPlayer**（`AudioManager` 单例）承载；NameInputScreen 通过调用 `AudioManager.play_bgm("bgm_main")` 启动，跨越 `change_scene_to_file()` 至 MainMenu 无断点；MainMenu 期间 BGM 持续播放，不重新启动

**音效（SFX）**

| 触发来源 | 设计意图 | 音效构成 | 相对音量 |
|---------|---------|---------|---------|
| 头像点击（非当前选中项） | 孩子每次选择有落地感 | 单音木质拨弦或钢琴短音（中高音区），干净短促，无延音 | −12 dB |
| 确认按钮「完成！」 | 命名礼的收尾句号 | 上行 2–3 音符钢片琴 sting，总时长 ≤ 1.5 秒；需在 `change_scene_to_file()` 调用前 ≥ 200ms 衰减至零（场景切换前自然播完） | −8 dB |
| 跳过链接「先不起名」 | 中性路径，不惩罚不奖励 | 无音效（静默） | — |
| Toast 错误提示（Rule 9） | 温和告知，不打破仪式感 | 无音效（静默）；`--feedback-gentle` 背景色已传达反馈 | — |
| LineEdit 文字输入 | 系统键盘默认行为 | 无自定义音效 | — |

**T-Rex 环境声**

- `trex_idle` 期间无持续环境声或呼吸声；T-Rex 存在感由视觉动画承载，声音通道留给 BGM
- 理由：P4——家长打字专注时不被叫声分神；与 HatchScene 音频哲学一致（减少情绪竞争）

**性能约束**

| 约束项 | 限制值 |
|--------|--------|
| BGM 文件（OGG Vorbis，压缩后）| ≤ 1.5 MB |
| SFX 合计（压缩后）| ≤ 200 KB |

## UI Requirements

### 1. 竖向布局层级（360×800dp 竖屏）

T-Rex 层（`TRexLayer`）与 ContentContainer **相互独立**，不共用同一容器，以支持 Rule 11 的独立键盘适配行为。

| # | 元素 | 所属容器 | 高度约束 | 元素间距（上边距） |
|---|------|---------|---------|-----------------|
| — | T-Rex 角色（160×160dp，水平居中） | TRexLayer（独立） | 160dp | 距屏幕顶边 ~60dp（居中于上方 ~35% 区域） |
| 1 | 标题「给 T-Rex 起个名字吧！」 | ContentContainer | 单行 16sp（≈24dp） | ContentContainer 顶部内边距 8dp（对齐 T-Rex 底部 8dp 间距） |
| 2 | LineEdit 输入框 | ContentContainer | ≥80dp | 距标题底部 12dp |
| 3 | 头像分区标签「选一个头像」 | ContentContainer | 单行 12sp（≈20dp） | 距 LineEdit 底部 16dp |
| 4 | 头像网格（3+2 排列，详见第 4 节） | ContentContainer | ≈184dp（88 + 8gap + 88） | 距标签底部 8dp |
| ↕ | 弹性间距（Spacer，`SIZE_EXPAND_FILL`） | ContentContainer | 最小 16dp，弹性分配剩余空间 | — |
| 5 | 确认按钮「完成！」 | ContentContainer | ≥80dp 触摸目标，宽 312dp | Spacer 下方紧贴 |
| 6 | 跳过链接「先不起名」 | ContentContainer | 触摸目标高 ≥44dp | 距确认按钮底部 16dp |

ContentContainer 底部内边距：≥24dp（距屏幕底边）。

---

### 2. 屏幕边缘安全边距

| 方向 | 值 | 说明 |
|------|----|------|
| 左 / 右 | 24dp | 确认按钮宽 312dp，屏幕宽 360dp：(360 − 312) ÷ 2 = 24dp；所有内容元素对齐此边距 |
| 顶 | 24dp | Android 状态栏安全区；T-Rex 居中区域从此起算 |
| 底 | 24dp | 跳过链接触摸目标底边至屏幕底边 |

---

### 3. 确认 / 跳过按钮锚点

| 属性 | 规格 |
|------|------|
| 确认按钮宽度 | 312dp（固定），水平居中；左右各 24dp 边距 |
| 确认按钮高度 | ≥80dp 触摸目标（`custom_minimum_size.y = 80`） |
| 确认按钮圆角 | 16dp |
| 跳过链接宽度 | 自适应文字宽度，水平居中，无背景 |
| 跳过链接触摸目标高度 | ≥44dp（`custom_minimum_size.y = 44`） |
| 确认 → 跳过间距 | 16dp |
| 底部锚定方式 | ContentContainer 使用 Spacer（`SIZE_EXPAND_FILL`）将确认 / 跳过组推至底部；ContentContainer 底部内边距 24dp 保证底边安全区 |

---

### 4. 头像网格布局锚点

| 属性 | 规格 |
|------|------|
| 结构 | 外层 VBoxContainer；行 1：HBoxContainer（3 个头像，`alignment = CENTER`）；行 2：HBoxContainer（2 个头像，`alignment = CENTER`） |
| 每个触摸目标 | ≥88×88dp（`custom_minimum_size`）；美术交付尺寸 128×128px 透明背景 PNG |
| 行间距 | 8dp |
| 行内头像间距 | 8dp |
| 网格最大宽度 | 312dp（受 24dp 水平边距约束，与确认按钮等宽） |
| 选中指示器 | 3dp `--accent-dino` 圆形描边，叠加于头像容器边缘；未选中项无描边、无背景色变化 |

---

### 5. 软键盘适配

见 Detailed Design **Rule 11**。摘要约束：ContentContainer 整体 Y 轴上移 = `DisplayServer.virtual_keyboard_get_height()`；确认按钮底部与键盘顶部余留 ≥8dp；T-Rex 独立淡出缩小至右上角（不随 ContentContainer 移动）；不使用 ScrollContainer。

---

### 6. 无障碍最低合规

| 要求 | 规格 | 参照 |
|------|------|------|
| 触摸目标最小尺寸 | 全部可交互元素 ≥80dp；头像触摸区域 ≥88×88dp；跳过链接触摸高度 ≥44dp | technical-preferences.md |
| 状态区分不依赖单一颜色 | 确认按钮禁用态同时使用 opacity 0.4 + `disabled = true`（非仅颜色变化）；头像选中态使用 3dp 描边 + 颜色双重信号 | WCAG 2.1 §1.4.1 |
| 最小字号 | 全屏最小字体：头像标签 12sp；跳过链接 14sp；标题 16sp；确认按钮 26sp；无任何文字 < 12sp | technical-preferences.md |
| 头像色盲合规 | 5 个头像主色调须在明度与色相上同时区分，灰度模式下可区分（详见 Visual Requirements 头像视觉规格） | game-concept.md P1 |
| 无 hover 依赖 | 全部状态变化仅由触摸触发；禁止任何 hover-only 状态 | technical-preferences.md（Android 触屏） |
| 无危险闪烁 | 本屏无高频闪烁内容（T-Rex idle 低频慢动画；头像弹跳 180ms，频率 < 3Hz） | WCAG 2.1 §2.3 |
| 错误反馈非红色 | Toast 错误使用 `--feedback-gentle` 暖背景；禁止红色 | game-concept.md P2 Anti-Pillar |

## Acceptance Criteria

**Core Flow**

- **AC-1** Verify that Confirm is disabled (opacity 0.4, untappable) when `LineEdit.text.strip_edges().replace("\u3000", "")` is empty, and enabled (opacity 1.0) when the result contains at least one character.
- **AC-2** Given a name is entered and avatar N is selected, when Confirm is tapped, then MainMenu loads and `ProfileManager.get_profile(0)` returns `name == LineEdit.text.strip_edges()` and `avatar_index == N`. *(Integration — BLOCKING)*
- **AC-3** Given any UI state, when Skip is tapped, then MainMenu loads and `ProfileManager.get_profile(0)` returns `name == "小朋友"` and `avatar_index == 0`, regardless of what was typed or selected. *(Integration — BLOCKING)*
- **AC-4** After either Confirm or Skip navigation completes, verify that `ProfileManager.has_active_profile()` returns `true`. *(Integration — BLOCKING)*

**Avatar Selection**

- **AC-5** On `_ready()`, verify that avatar index 0 displays the selection border at scale 1.0 and no other avatar shows a selection border. *(UI — ADVISORY)*
- **AC-6** Given avatar N is selected, when the user taps avatar M (M ≠ N), then M completes a scale 1.0→1.12→1.0 animation within 180ms, M shows the selection border, and N's border is removed. *(UI — ADVISORY)*
- **AC-7** At any point after any avatar tap, verify that exactly one avatar simultaneously shows a selection border. *(Logic — BLOCKING)*

**Input Constraints**

- **AC-8** Given `LineEdit.text.length() == 20` (NAME_MAX_LENGTH), when the user inputs an additional character, verify that `LineEdit.text.length()` remains 20. *(Logic — BLOCKING)*
- **AC-9** Verify that the Clear button (✕) is visible when `LineEdit.text.length() > 0` and hidden when `LineEdit.text == ""`; tapping Clear sets text to `""` and the button immediately hides. *(UI — ADVISORY)*

**SUBMITTING State**

- **AC-10** From the moment Confirm or Skip is first tapped until scene transition begins, verify that Confirm, Skip, and Clear are all non-interactive and `LineEdit.editable == false`. *(Logic — BLOCKING)*
- **AC-11** When Confirm is tapped twice within 300ms, verify that `ProfileManager.create_profile` is called exactly once and exactly one profile entry exists in storage. *(Logic — BLOCKING)*

**Entry Guard**

- **AC-12** Given `ProfileManager.profile_exists(0)` returns `true` when `_ready()` is called, verify that all interactive elements (LineEdit, all avatar buttons, Confirm, Skip) are hidden, no user action triggers any UI response, and `push_error` has been invoked. *(Logic — BLOCKING)*

**Error Path**

- **AC-13** Given Confirm is tapped and `create_profile` returns `false`, then a toast reading `"保存失败，请再试一次"` appears within 0.1s, auto-dismisses after 2±0.25s, Confirm and Skip re-enable, and `LineEdit.text` and selected avatar index are unchanged. *(Logic — BLOCKING)*

**Keyboard**

- **AC-14** On `_ready()`, verify that the Android soft keyboard is not open (tester confirms no keyboard visible on screen immediately after the scene loads). *(UI — ADVISORY)*
- **AC-15** Given the keyboard is visible, when Back is pressed, then the keyboard dismisses and NameInputScreen remains loaded; given the keyboard is hidden, when Back is pressed, then no scene change occurs and NameInputScreen stays loaded. *(UI — ADVISORY)*

**Navigation Guard**

- **AC-16** Given profile 0 exists in persistent storage at app launch, verify that GameRoot routes to MainMenu and `NameInputScreen._ready()` is never invoked. *(Integration — BLOCKING)*

---

| 门控级别 | AC 编号 |
|---------|--------|
| BLOCKING（Logic / Integration） | AC-1, 2, 3, 4, 7, 8, 10, 11, 12, 13, 16 |
| ADVISORY（UI / Manual walkthrough） | AC-5, 6, 9, 14, 15 |

## Open Questions

- **OQ-1 — ProfileManager GDD Interactions 表一致性修正**：ProfileManager GDD Interactions 表中 `MainMenu → ProfileManager: create_profile()` 一行为历史占位（NameInputScreen GDD 撰写前填写）。权威调用方是 NameInputScreen，不是 MainMenu。待 ProfileManager GDD 维护时修正此行（非阻断，NameInputScreen 已为权威来源）。

- **OQ-2 — AudioManager AutoLoad 架构**：Visual/Audio Requirements 定义 BGM 由 AutoLoad `AudioManager` 单例承载，NameInputScreen 调用 `AudioManager.play_bgm("bgm_main")`。`AudioManager` 尚未有 GDD——在 NameInputScreen 实现前需确认 `AudioManager` 接口设计（信号？方法？）；可在 MainMenu 实现阶段一并确认，因 MainMenu 也需 BGM 连续播放。

- **OQ-3 — EC-8 Emoji 字符集白名单（v1.1 候选）**：MVP 不做字符集过滤，emoji 输入会触发 Godot String 码位截断 + 方块渲染问题。若 v1.1 需修复，在 F-1 谓词后追加字符集白名单（建议：仅允许 Unicode Letters + Mark + Decimal Number + Space）；届时需更新 F-1 谓词和 AC-1。
