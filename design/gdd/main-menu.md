# MainMenu

> **Status**: Approved — /design-review RF-1~RF-13 + R1~R8 applied 2026-05-08
> **Author**: Zhang Shaocong + agents
> **Last Updated**: 2026-05-08
> **Implements Pillar**: P4 (家长是骄傲见证者), P2 (失败是另一条好玩的路)

## Overview

MainMenu 是应用启动后的第一个界面（首次安装时由 GameRoot 直接路由至 HatchScene，MainMenu 始终假设「已存在至少一个档案」）。进入时：若活跃档案 `times_played > 0`（回归玩家），T-Rex 播放 `trex_recognize` 动画（认出孩子）后循环 `trex_idle`；若为全新档案（`times_played == 0`，刚完成 HatchScene），直接播放 `trex_idle`。底部「出发冒险！」主按钮引导孩子进入游戏；右上角放置家长入口纯图标按钮（无文字标签，图标尺寸 ≥ 80dp）：点击后弹出气泡「需要大人帮忙」，在气泡存在时父按钮可持续长按，满 5 秒并配合圆形进度环充满后跳转至 ParentVocabMap。若档案数量 ≥ 2，顶部显示档案切换指示器（最多 `MAX_SAVE_PROFILES`（3）个槽位，每槽显示档案头像、名字及该档案已解锁的词汇金星总数）。按下「出发冒险！」后，确认 StoryManager 处于 `IDLE` 状态，调用 `begin_chapter("chapter_1", "res://story/chapter_1.ink.json")` 跳转至 GameScene；无论 `story_progress` 状态如何，均从第一章起点开始（不存在「续关」语义，仅「重玩」）。

## Player Fantasy

MainMenu 服务两组眼睛，且两组眼睛的注意力永不相撞。

**孩子的感受**：每次回来不像打开一个 App，而像走进一间有人在等待的房间。`trex_recognize` 动画是整个论点——T-Rex 用整个身体表达记忆和喜悦，4 岁的孩子会立刻解读为「它专门认识我」。这是归属感：我有一只恐龙，它认得我，我知道这里该怎么玩。

**家长的感受**：孩子的目光锁在恐龙身上时，家长的目光自然落向档案槽里的词汇金星数——无需解释，一眼知道孩子赢得了多少。这是从身后的静默自豪：不是被展示分数，而是不经意间看到了孩子的成长证据。

**情感载体**：`trex_recognize` 动画独占孩子的注意力——它是全游戏质量最高的动画，每次回来只播一次；档案切换器只面向站在孩子背后的大人，星星用图标（而非数字）展示，头像永远比星星大，看见孩子先于看见成就。「出发冒险！」按钮没有倒计时、没有催促，只是敞开着，像一扇始终开着的门。

## Detailed Design

### Core Rules

**前置条件**

**Rule 1 — 活跃档案前置守卫**
`_ready()` 时调用 `ProfileManager.has_active_profile()`；若返回 `false`：`push_error`，中止初始化，不展示任何交互元素。正常流程此条件永远为 `true`（GameRoot 保证路由前档案已激活）。

**Rule 2 — 活跃档案索引**
MainMenu 通过 GameRoot 路由参数接收 `_active_index: int`（当前活跃档案槽位）。所有 `get_profile_header(_active_index)` 均基于此值；档案切换成功后更新。

**入场动画**

**Rule 3 — T-Rex 入场逻辑**
`_ready()` 时读取 `get_profile_header(_active_index).times_played`：
- `times_played > 0`（回归玩家）：播放 `trex_recognize` 一次 → 循环 `trex_idle`
- `times_played == 0`（刚完成 HatchScene 的全新档案）：直接循环 `trex_idle`

  *`is_first_launch()` 在 MainMenu 上下文中始终为 `false`，不用于此判断。*

**Rule 4 — `trex_recognize` 播放期间保护**
`trex_recognize` 播放期间不可被档案切换打断；按钮交互在动画期间正常响应（动画状态机与屏幕交互状态机相互独立）。

**Rule 4a — LOAD_ERROR 与识别动画的并发处理**
若 `chapter_load_failed` 在 `play_recognize()` 播放期间触发（用户在识别动画播放时快速点击「出发冒险！」），MainMenu 执行延迟逻辑：
- `_on_chapter_load_failed` 中：将 `_deferred_confused := true`；连接 `animation_handler.animation_completed`（ONE_SHOT）至 `_on_recognize_completed`
- `_on_recognize_completed(state)` 收到 `state == AnimState.RECOGNIZE` 时：若 `_deferred_confused`，调用 `play_confused()`，转入 LOAD_ERROR UI
- 若 `_on_chapter_load_failed` 触发时 AnimationHandler 不在 RECOGNIZE 状态：直接调用 `play_confused()`（无需延迟）
- AnimationHandler 保证 RECOGNIZE 在 NON_INTERRUPTIBLE_STATES 中，`play_confused()` 的并发调用被静默拒绝；`animation_completed(RECOGNIZE)` 信号是调用方恢复的唯一通知（CD D1）
- `animation_completed` 信号参数 `state` 类型为 `AnimationHandler.AnimState`（GDScript int 枚举）；订阅方须与 `AnimationHandler.AnimState.RECOGNIZE` 比较（R2）
- 退出 `LOAD_ERROR`（「算了先歇会儿」路径）时：若 `_deferred_confused == true`（RECOGNIZE 尚未完成），执行清理：`_deferred_confused := false`；若 ONE_SHOT 连接仍活跃，调用 `animation_handler.animation_completed.disconnect(_on_recognize_completed)`（防止 RECOGNIZE 完成后在 IDLE 状态触发幽灵 `play_confused()`）（B7）

**档案切换器**

**Rule 5** — 当且仅当 `get_profile_count() >= 2` 时显示切换器；1 个档案时完全隐藏（不占布局空间）。

**Rule 6** — 切换器仅渲染 `is_valid == true` 的槽位卡片，最多 `MAX_SAVE_PROFILES`（3）张。MVP 不展示空槽位或「+新建」占位符。

**Rule 7 — 卡片内容**
每张卡片展示：头像图片（≥52dp，`avatar_id` 对应）、名字（11sp）、金星数（★ 图标，非数字）。头像是不识字孩子识别「这是我的」的唯一线索，美术必须提供轮廓与颜色双重差异显著的头像。

**Rule 8 — 金星数计算**
活跃档案：对 `VOCAB_WORD_IDS_CH1`（5 个词）调用 `VocabStore.get_gold_star_count(wid)` 求和（见 Formulas F-1）。
非活跃档案：MVP 显示为 0 并附占位标注「暂无数据」（DG-2：待 ProfileManager / VocabStore / SaveSystem GDD 增量修订后改为读取 `get_profile_header(i).total_gold_stars`）。

**Rule 9 — 档案切换交互**
点击非活跃卡片 → 转 `PROFILE_SWITCHING`（切换器禁用）→ 调用 `switch_to_profile(index)` → 等待 `profile_switched(new_index)` 信号 → 更新 `_active_index`、重新计算金星数、按 Rule 3 重执行动画逻辑 → 退出 `PROFILE_SWITCHING`。**不乐观更新 UI**（必须等信号确认）。
点击活跃卡片：头像弹跳动画（scale 1.0→1.08→1.0，200ms），无状态变化。
**`PROFILE_SWITCHING` 期间「出发冒险！」不响应**（见状态表），防止以旧档案数据启动游戏（B13）。

**「出发冒险！」按钮**

**Rule 10** — 按钮标签固定为「出发冒险！」，无「继续」变体。游戏始终从第一章起点开始，不存在续关语义。视觉规格：`--accent-dino`（暖橙）背景，26sp 粗体白色文字，16dp 圆角，312×112dp（全屏视觉权重最高元素）。

**Rule 11 — 发射序列（严格 7 步）**
点击「出发冒险！」后：
  a. 立即禁用按钮（视觉与触摸同步，防双击）
  b. 检查 `StoryManager.state == IDLE`；若否：`push_error`，重新启用按钮，中止（防御守卫；正常流程此条件永远成立）
  c. 若 `_session_started == false`：调用 `ProfileManager.begin_session()`，并设 `_session_started := true`（本次 App 访问唯一一次；覆盖「算了先歇会儿」后重新点击的路径，防止重复调用）（B4）
  d. 连接 `chapter_load_failed` 信号至 `_on_chapter_load_failed`（`CONNECT_ONE_SHOT`）
  e. 初始化 `_launch_failed := false`
  f. 调用 `StoryManager.begin_chapter("chapter_1", "res://story/chapter_1.ink.json")`（同步调用；若失败，信号在返回前同步触发）
  g. 检查 `_launch_failed`：`false` → 转 `LAUNCHING_GAME`，调用 `SceneTree.change_scene_to_file()` 导航 GameScene；若返回非 `OK` 的 `Error`：`push_error`，`_launch_failed := true`，转入 `LOAD_ERROR`（防御守卫：`change_scene_to_file()` 失败不触发 `chapter_load_failed`，须在此单独处理）；`true` → 已在步骤 f 内转入 `LOAD_ERROR`（B2）

**Rule 12 — 重试不重复 begin_session()**
`LOAD_ERROR` 下点击「再来一次！」：从步骤 d 重新执行，跳过步骤 c，`times_played` 不再递增。

**家长按钮**

**Rule 13** — 纯图标按钮（无文字标签），右上角，最小触摸目标 80dp×80dp。图标视觉应「乏味」，禁止使用恐龙/星星元素（孩子不应主动探索此按钮）；**正向规格：齿轮/设置类图形，单色线条风格，不传达任何游戏内容信息**（R4）。

**Rule 14 — 四态交互**
`IDLE`：点击 → 显示「需要大人帮忙」气泡 → 转 `PARENT_HOLD`。
`PARENT_HOLD`（气泡可见）：
- 按住按钮：展示圆形进度环（0%→100%，`PARENT_HOLD_DURATION` 秒）；满圆 → 导航 ParentVocabMap
- 松手（< 100%）：进度环归零，气泡保留，留在 `PARENT_HOLD`
- 点击气泡外任意区域：气泡消失，进度归零，退出 `PARENT_HOLD`（须重新点击才能再次启动充能）。「气泡外任意区域」定义：气泡 Panel 节点之外的所有触摸落点；该区域下的交互元素仍正常响应（例如点击档案卡片同时关闭气泡并触发档案切换，见 Rule 9 + B1 修复）（R5）
- 在 `PARENT_HOLD` 状态下点击「出发冒险！」：气泡关闭，进度环归零，立即按 Rule 11 执行发射序列（原子操作，不经过 `IDLE_*` 中间状态）（B12）

**加载错误**

**Rule 15 — LOAD_ERROR 进入**
`_on_chapter_load_failed` 触发：`_launch_failed = true` → 转 `LOAD_ERROR` → T-Rex 播放 `trex_confused` → 显示暖琥珀色（`#FFF3CD`）气泡，禁用红色，无技术性文字。*（`trex_confused` 此处上下文为加载失败；GameScene 内词汇练习中使用同一方法，上下文不同，接口相同，R3。）* 提供两个出口：「再来一次！」（**配重试/循环图标**，Rule 12 重试）和「算了，先歇会儿」（**配休息/暂停图标**，重新启用「出发冒险！」按钮，转回 `IDLE_*`）。**两个按钮须同时包含图标和文字标签；图标须在无文字情况下可独立传达意图（面向 4-6 岁读图能力）**（B6）。

**Rule 16 — 第三次累计失败**
连续失败 3 次（`_fail_count >= 3`）：隐藏重试按钮，改为「告诉大人」链接（18sp）；T-Rex 继续播放 `confused`（与前两次行为一致，不触发 SITTING）。`_fail_count` 不持久化，重启 App 后重置。SITTING 由 **`SITTING_INACTIVITY_THRESHOLD` 静置超时**独立触发（见 Tuning Knobs），与失败计数解耦（CD D2）。

**布局（360×800dp 竖屏）**

**Rule 17 — 元素位置**

| 元素 | 位置 dp (x, y) | 尺寸 (w×h dp) |
|------|--------------|---------------|
| 家长按钮 | x=280–360, y=8–88 | 80×80 |
| 档案卡片（2 档） | 槽1: x=16–96, 槽2: x=104–184; y=8–88 | 各 80×80 |
| 档案卡片（3 档） | 槽1: x=16, 槽2: x=104, 槽3: x=192; y=8–88 | 各 80×80 |
| T-Rex Stage | x=0–360, y=96–640 | 360×544 |
| 「出发冒险！」按钮 | x=24–336, y=648–760 | 312×112 |

**Rule 18** — 所有可交互元素触摸目标 ≥ 80dp×80dp。竖屏锁定由项目级导出设置保证，MainMenu 不处理方向变化。3 档布局时档案槽3 右边缘 x=272，家长按钮左边缘 x=280，间距 8dp（B5 修复：防止 4 岁手指误触家长入口）。

---

### States and Transitions

| 状态 | 含义 | 出发冒险！ | 家长按钮 | 切换器 |
|------|------|-----------|---------|--------|
| `IDLE_SINGLE` | 1 个档案，切换器隐藏 | 可点击 | 可点击 | 隐藏 |
| `IDLE_MULTI` | 2–3 个档案，切换器可见 | 可点击 | 可点击 | 可点击 |
| `PROFILE_SWITCHING` | 档案切换中 | 不响应（B13） | 不响应 | 禁用 |
| `PARENT_HOLD` | 气泡可见，长按计时中（可选） | 可点击 | 长按计时 | 可点击 |
| `LAUNCHING_GAME` | begin_chapter() 已调用 | 禁用 | 不响应 | 禁用 |
| `LOAD_ERROR` | chapter_load_failed 已触发 | 禁用（重试替代） | 可点击 | 禁用 |

**合法转换**

| 从 | 到 | 触发条件 |
|----|----|---------| 
| (初始化) | `IDLE_SINGLE` | `_ready()` + `get_profile_count()==1` |
| (初始化) | `IDLE_MULTI` | `_ready()` + `get_profile_count()>=2` |
| `IDLE_*` | `PARENT_HOLD` | 家长按钮单击 |
| `IDLE_MULTI` | `PROFILE_SWITCHING` | 非活跃卡片点击 |
| `PARENT_HOLD` | `PROFILE_SWITCHING` | 非活跃卡片点击（气泡关闭，进度归零，进入切换）（B1） |
| `PARENT_HOLD` | `LAUNCHING_GAME` | 点击「出发冒险！」（气泡关闭，进度归零，Rule 11 发射序列）（B12） |
| `IDLE_*` | `LAUNCHING_GAME` | Rule 11g `_launch_failed==false` |
| `PARENT_HOLD` | `IDLE_*` | 气泡外点击 |
| `PARENT_HOLD` | (ParentVocabMap) | `PARENT_HOLD_DURATION` 满 |
| `PROFILE_SWITCHING` | `IDLE_*` | `profile_switched` 信号收到 |
| `LAUNCHING_GAME` | (GameScene) | Rule 11g 成功 |
| `LAUNCHING_GAME` | `LOAD_ERROR` | `chapter_load_failed` 信号 |
| `LOAD_ERROR` | `LAUNCHING_GAME` | 「再来一次！」且 `_fail_count < 3` |
| `LOAD_ERROR` | `IDLE_*` | 「算了，先歇会儿」 |

---

### Interactions with Other Systems

| 系统 | 调用 / 信号 | 方向 | 时机 |
|------|-----------|------|------|
| ProfileManager | `has_active_profile() -> bool` | MainMenu → PM | `_ready()` 前置守卫 |
| ProfileManager | `get_profile_count() -> int` | MainMenu → PM | `_ready()`；每次退出 PROFILE_SWITCHING |
| ProfileManager | `get_profile_header(i) -> {...}` | MainMenu → PM | `_ready()`；`profile_switched` 后 |
| ProfileManager | `switch_to_profile(i)` | MainMenu → PM | Rule 9 档案切换 |
| ProfileManager | `begin_session()` | MainMenu → PM | Rule 11c 发射序列（本次访问唯一一次） |
| ProfileManager | Signal `profile_switched(new_index)` | PM → MainMenu | 档案切换完成 |
| VocabStore | `get_gold_star_count(wid) × 5` | MainMenu → VS | `_ready()`；`profile_switched` 后 |
| StoryManager | `.state`（与 `IDLE` 比较）| MainMenu 读取 | Rule 11b 发射前置守卫 |
| StoryManager | `begin_chapter(id, path)` | MainMenu → SM | Rule 11f 发射；Rule 12 重试 |
| StoryManager | Signal `chapter_load_failed` | SM → MainMenu | `begin_chapter()` 内同步触发 |
| AnimationHandler (T-Rex) | `play_recognize()` | MainMenu → AH | 入场，`times_played > 0` |
| AnimationHandler (T-Rex) | `play_menu_idle()` | MainMenu → AH | 入场（`times_played == 0`）；`trex_recognize` 完成后自动链；`LOAD_ERROR` 退出后 |
| AnimationHandler (T-Rex) | `play_confused()` | MainMenu → AH | `chapter_load_failed` 触发（直接或延迟，见 Rule 4a），进入 LOAD_ERROR |
| AnimationHandler (T-Rex) | Signal `animation_completed(RECOGNIZE)` | AH → MainMenu | RECOGNIZE 完成通知；用于 Rule 4a 延迟 confused 执行 |
| AnimationHandler (T-Rex) | `play_sitting()` | MainMenu → AH | `SITTING_INACTIVITY_THRESHOLD` 超时（静置触发，与 `_fail_count` 无关）|
| GameRoot / SceneTree | 导航至 GameScene | MainMenu → SceneTree | Rule 11g 发射成功 |
| GameRoot / SceneTree | 导航至 ParentVocabMap | MainMenu → SceneTree | Rule 14 长按满 |

## Formulas

**F-1 — 活跃档案金星总数**

```
total_gold_stars = Σ VocabStore.get_gold_star_count(wid)
                   for wid ∈ VOCAB_WORD_IDS_CH1
```

| 变量 | 类型 | 范围 | 说明 |
|------|------|------|------|
| `VOCAB_WORD_IDS_CH1` | `Array[String]` | 固定 5 元素 | `["ch1_trex", "ch1_triceratops", "ch1_eat", "ch1_run", "ch1_big"]`（由 VocabStore 权威定义，MainMenu 引用不拥有） |
| `get_gold_star_count(wid)` | `int` | 0 ≤ n | 单词金星数；无活跃档案时返回 0 |
| `total_gold_stars` | `int` | 0 ≤ n（上限由 VocabStore 每词最大星数 × 5 决定；VocabStore GDD 拥有该上限定义） | 显示于活跃档案卡片 |

示例：孩子学会 2 个词，各 1 星 → `0+1+0+1+0 = 2`

**F-2 — T-Rex 入场动画选择**

```
entry_animation = "trex_recognize"  IF times_played > 0
                  "trex_idle"        OTHERWISE
```

输入：`get_profile_header(_active_index).times_played`。调用时机：`begin_session()` 尚未在本次访问中调用（Rule 11c 在点击「出发冒险！」时才调用，`_ready()` 读取在此之前，不受影响）。

**F-3 — 切换器可见性**

```
switcher_visible = (get_profile_count() >= 2)
```

**F-4 — 家长长按进度**

```
hold_progress = clamp(elapsed_ms / (PARENT_HOLD_DURATION × 1000), 0.0, 1.0)
```

| 变量 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `elapsed_ms` | `float` | 0–∞ | 手指触摸家长按钮后经过的毫秒数（每帧更新） |
| `PARENT_HOLD_DURATION` | `float` | 5.0 秒 | 见 Tuning Knobs |
| `hold_progress` | `float` | [0.0, 1.0] | 圆形进度环填充比例；达到 1.0 时触发导航 |

> ⚠️ **断言（B3）**：实现须加守卫 `assert(PARENT_HOLD_DURATION > 0.0, "PARENT_HOLD_DURATION 不得为零")`；若测试注入 `0.0`，GDScript `clamp(inf, 0.0, 1.0) = 1.0` 将立即触发导航，Tuning Knobs 安全范围标注不足以阻止此情况。

## Edge Cases

| # | 边界情况 | 行为 |
|---|---------|------|
| EC-1 | `StoryManager.state != IDLE` 时点击「出发冒险！」 | `push_error`；按钮重新启用；`begin_session()` 不调用；`begin_chapter()` 不调用 |
| EC-2 | 快速双击「出发冒险！」（间隔 < 100ms） | 步骤 a 在第一次点击时立即禁用按钮；第二次点击落在禁用状态，无响应；`begin_chapter()` 仅调用一次 |
| EC-3 | `chapter_load_failed` 触发后再次重试仍失败 | 维持 `LOAD_ERROR`；`_fail_count` 递增；若 < 3 显示重试按钮；`begin_session()` 不再调用 |
| EC-4 | 连续失败 3 次 | 隐藏重试按钮，改为「告诉大人」链接；T-Rex 继续播放 confused（行为与前两次相同）；SITTING 不触发（SITTING 由独立静置超时触发，与 `_fail_count` 无关，CD D2）；`_fail_count` 不持久化 |
| EC-5 | `PROFILE_SWITCHING` 期间 `profile_switched` 信号未收到（切换超时） | 3 秒超时保护：`push_error`，切换器重新启用，转回进入前的 `IDLE_*`；不调用 `begin_session()` |
| EC-6 | 进行长按（进度 60%）时，另一触摸点落在气泡外 | 长按计时立即停止，进度归零，执行 Rule 14 气泡外点击逻辑退出 `PARENT_HOLD` |
| EC-7 | `PARENT_HOLD` 下手指在进度达到 99% 时松开 | 进度环归零，**不**导航；必须等 `hold_progress >= 1.0`（即满 `PARENT_HOLD_DURATION` 秒）才触发 |
| EC-8 | `get_profile_header(i).is_valid == false` | 该卡片不渲染（Rule 7 前置守卫）；数据损坏由 ProfileManager 处理，MainMenu 不尝试修复 |
| EC-9 | `_ready()` 时 `has_active_profile() == false` | `push_error`，不初始化任何 UI，屏幕显示空白（GameRoot 路由 bug） |
| EC-10 | 1 个档案时，家长在 ParentVocabMap 创建第二档案后返回 MainMenu | `_ready()` 重新执行（正常重入），`get_profile_count()` 返回 2，进入 `IDLE_MULTI`，切换器显示 |
| EC-11 | `trex_confused` / `trex_sitting` 动画名称 | AnimationHandler GDD 已确认；MainMenu 通过 `play_confused()` / `play_sitting()` 调用（不直接引用 clip 名），无需额外对齐 |

## Dependencies

**MainMenu 依赖的系统（上游）**

| 系统 | 依赖性质 | MainMenu 使用的接口 |
|------|---------|-------------------|
| ProfileManager | 强依赖 | `has_active_profile()`, `get_profile_count()`, `get_profile_header(i)`, `switch_to_profile(i)`, `begin_session()`; Signal `profile_switched` |
| StoryManager | 强依赖 | `.state`, `begin_chapter(id, path)`; Signal `chapter_load_failed` |
| VocabStore | 强依赖 | `get_gold_star_count(wid)` × 5 |
| AnimationHandler (T-Rex) | 强依赖 | `play_recognize()`, `play_menu_idle()`, `play_confused()`, `play_sitting()` — 语义方法调用，AnimationHandler 封装所有 clip 细节。**T-Rex 动画行为规格（时长 ≥1.5s、情感表达要求）见 AnimationHandler GDD § Visual/Audio Requirements；MainMenu 引用不拥有该规格（A1 降级修复）。** |
| GameRoot / SceneTree | 强依赖 | 场景路由（导航至 GameScene / ParentVocabMap）；路由参数传入 `_active_index` |

**依赖 MainMenu 的系统（下游）**

| 系统 | 依赖性质 | 期望 |
|------|---------|------|
| ParentVocabMap | 软依赖（被导航目标） | 从 MainMenu 家长长按完成后进入 |
| GameScene | 软依赖（被导航目标） | 从 MainMenu「出发冒险！」成功后进入 |

**跨文档注意**

- ProfileManager GDD 原定 `begin_session()` 由 GameRoot 调用——已在本 GDD 调整为 MainMenu 调用（Rule 11c）。**GameRoot GDD 设计时须不重复调用 `begin_session()`。**
- AnimationHandler GDD 已声明 `play_recognize()`、`play_menu_idle()`、`play_confused()`、`play_sitting()` 四个语义方法（RF-NEW-6 2026-05-08 对齐）。
- DG-2（非活跃档案金星缓存）推迟至 v1.1，届时需对 ProfileManager、VocabStore、SaveSystem 三个 GDD 做增量修订。

## Tuning Knobs

| 旋钮名 | 默认值 | 安全范围 | 类型 | 影响 |
|--------|--------|---------|------|------|
| `PARENT_HOLD_DURATION` | 5.0 秒 | 3.0–8.0 秒 | Gate | 越短家长越容易意外触发；越长越难到达。5 秒针对「孩子看着、大人单手操作」场景。**测试钩子**：可通过依赖注入覆盖，支持自动化 AC-14/AC-15 验证 |
| `PROFILE_SWITCH_TIMEOUT` | 3.0 秒 | 1.0–5.0 秒 | Reliability | `PROFILE_SWITCHING` 状态的超时保护时长（EC-5）；过短会误判正常的慢速 I/O |
| `LOAD_ERROR_MAX_RETRIES` | 3 次 | 1–5 次 | UX | 显示重试按钮的最大次数；达到上限后改为「告诉大人」（Rule 16）；**不持久化** |
| `SITTING_INACTIVITY_THRESHOLD` | 45 秒 | 15–120 秒 | UX | MainMenu 静置多久后调用 `play_sitting()`；过短会让正常浏览的家长看到 T-Rex 坐下；过长会让等待孩子的屏幕显得死寂。计时器在任何交互（点击、切换档案）后重置。**不持久化**，重入 MainMenu 重置计时。**实现（R1）：`Timer` 节点，`one_shot=true`；任何用户交互后调用 `.start(SITTING_INACTIVITY_THRESHOLD)` 重置；`_exit_tree()` 时调用 `.stop()`，防止场景 `queue_free()` 后信号触发。**|

## Acceptance Criteria

| # | 测试场景 | 期望结果 | 类型 |
|---|---------|---------|------|
| AC-1 | `_ready()`，活跃档案 `times_played==0` | `trex_recognize` **未**播放；`trex_idle` 直接循环 | Unit |
| AC-2 | `_ready()`，活跃档案 `times_played==5` | `trex_recognize` 播放一次后转 `trex_idle`；`trex_recognize` 播放计数 == 1 | Unit |
| AC-3 | `get_profile_count()` 返回 1 | 切换器节点不可见（`visible == false`）；状态 == `IDLE_SINGLE` | Unit |
| AC-4 | `get_profile_count()` 返回 2 | 切换器可见，渲染 2 张卡片；状态 == `IDLE_MULTI` | Unit |
| AC-5 | `get_profile_count()` 返回 3 | 切换器可见，渲染 3 张卡片（无第 4 张） | Unit |
| AC-6 | 快速双击「出发冒险！」（间隔 < 100ms） | `begin_session()` 调用恰好 **1 次**；`begin_chapter()` 调用恰好 **1 次** | Unit |
| AC-7 | 点击「出发冒险！」，`StoryManager.state == RUNNING` | `push_error` 调用；`begin_session()` **未**调用；`begin_chapter()` **未**调用；按钮重新启用 | Unit |
| AC-8 | 正常点击「出发冒险！」，Mock `begin_chapter()` 成功 | `begin_session()` 调用 1 次；`begin_chapter()` 参数为 `("chapter_1", "res://story/chapter_1.ink.json")`；状态转 `LAUNCHING_GAME` | Unit |
| AC-9 | `chapter_load_failed` 信号在 `begin_chapter()` 内同步触发 | 状态转 `LOAD_ERROR`；`出发冒险！` 按钮保持禁用；LOAD_ERROR UI 显示；`_launch_failed == true` | Unit |
| AC-10 | `LOAD_ERROR` 下点击「再来一次！」 | `begin_session()` **未**再次调用；`begin_chapter()` 被调用 1 次 | Unit |
| AC-11 | `LOAD_ERROR` 下点击「算了，先歇会儿」（`get_profile_count()==1`） | 状态转 `IDLE_SINGLE`；`出发冒险！` 重新启用；T-Rex 播放 `trex_idle` | Unit |
| AC-12 | 连续失败 3 次 | 重试按钮隐藏；「告诉大人」链接显示；T-Rex 播放 `confused`（**不**播放 `sitting`；SITTING 不由失败触发，CD D2） | Unit |
| AC-13 | 家长按钮点击 | 状态转 `PARENT_HOLD`；气泡「需要大人帮忙」显示 | Unit |
| AC-14 | `PARENT_HOLD` 下点击气泡外区域 | 气泡消失；状态转回 `IDLE_*`；`hold_progress == 0` | Unit |
| AC-15 | `PARENT_HOLD` 下按住家长按钮 1.0 秒后松开（`PARENT_HOLD_DURATION` 注入为 **1.5s**，非默认值，验证注入机制有效性） | **不**导航 ParentVocabMap；进度环重置为 0 | Unit（需 `PARENT_HOLD_DURATION` 测试钩子）（R8） |
| AC-16 | `PARENT_HOLD` 下持续按住家长按钮满 1.5 秒（`PARENT_HOLD_DURATION` 注入为 **1.5s**，非默认值） | 进度环达到 100%；触发导航至 ParentVocabMap | Unit（需 `PARENT_HOLD_DURATION` 测试钩子）（R8） |
| AC-17 | 进行长按（进度 60%）时另一触摸点落在气泡外 | 长按计时立即停止；进度归零；状态退出 `PARENT_HOLD` | Unit |
| AC-18 | 档案切换至新档案（`times_played==3`） | `_active_index` 更新；`trex_recognize` 播放；金星数重新计算（VocabStore × 5）；切换器重新启用 | Unit |
| AC-19 | 档案切换至新档案（`times_played==0`） | `trex_recognize` **未**播放；`trex_idle` 直接循环 | Unit |
| AC-20 | `has_active_profile()` 在 `_ready()` 时返回 `false` | `push_error`；无 UI 交互元素初始化 | Unit |
| AC-21 | 完整 MainMenu → 「出发冒险！」→ GameScene 流程（真实 StoryManager + 真实 chapter_1.ink.json） | 全流程无崩溃；导航成功；`begin_session()` 被调用；`times_played` 在下次 MainMenu 打开时 > 0 | Integration（**依赖 OQ-1 解决后确定的导航机制；OQ-1 解决前仅可手动执行**，R7） |
| AC-22 | `trex_recognize` 动画质量评审（人工，CD 门审） | **最低测试规格（R6）**：测试者 ≥3 人（年龄 3–5 岁）；至少 2/3 人在无提示情况下自发描述 T-Rex 的情绪反应（如「恐龙认识我」「它很开心」，而非单纯「它在动」）；动画时长 ≥1.5 秒，包含头部或身体朝向变化（非技术占位级别）。 | 主观（CD 评审） |
| AC-23 | `chapter_load_failed` 在 `play_recognize()` 播放期间同步触发（Rule 4a 路径） | `play_confused()` 在 RECOGNIZE 完成后被调用恰好 1 次；`play_confused()` 在 RECOGNIZE 播放期间**不**被调用（守卫拦截）；LOAD_ERROR UI 在识别动画完成后显示。**GUT 前置条件（B11）**：`var mock_ah = double(AnimationHandler); stub(mock_ah.play_recognize()).to_call(func(): pass); inject mock_ah; watch_signals(mock_ah)` — 手动 emit `mock_ah.animation_completed.emit(AnimationHandler.AnimState.RECOGNIZE)` 触发信号链。 | Unit（mock animation_completed signal）（B11） |
| AC-24 | `SITTING_INACTIVITY_THRESHOLD` 超时后（注入为 2.0 秒） | `play_sitting()` 被调用 1 次；T-Rex 进入 SITTING 状态；与 `_fail_count` 值无关（0 或任意值均触发） | Unit（需 `SITTING_INACTIVITY_THRESHOLD` 测试钩子） |
| AC-25 | 静置计时器在用户交互后重置 | 点击任意按钮 / 切换档案后，`SITTING_INACTIVITY_THRESHOLD` 计时器从 0 重新开始；`play_sitting()` 不被提前调用 | Unit |
| AC-26 | `PROFILE_SWITCHING` 下 `PROFILE_SWITCH_TIMEOUT`（注入为 0.5s）内未收到 `profile_switched` 信号 | `push_error` 调用；切换器重新启用；状态转回进入前的 `IDLE_*`；`_active_index` 未改变 | Unit（需 `PROFILE_SWITCH_TIMEOUT` 测试钩子）（B8） |
| AC-27 | 活跃档案 `get_profile_header(i)` 某槽位 `is_valid == false` | 该卡片不渲染（节点不加入树或 `visible == false`）；其余槽位正常渲染；无崩溃 | Unit（B9） |
| AC-28 | 从 ParentVocabMap 返回 MainMenu，`get_profile_count()` 由 1 变 2（新档案已在 ParentVocabMap 创建） | `_ready()` 重新执行；切换器可见；状态为 `IDLE_MULTI`；两张卡片均正常渲染 | Integration（B10） |

## Open Questions

| # | 问题 | 优先级 | 解决方 |
|---|------|--------|--------|
| OQ-1 | 场景导航机制未定：MainMenu → GameScene / ParentVocabMap 是信号驱动还是 `change_scene_to_file` 直接调用？（DG-4）| HIGH | GameRoot GDD 设计时解决 |
| OQ-2 | 非活跃档案金星缓存（DG-2）：需对 ProfileManager / VocabStore / SaveSystem 三个已批准 GDD 做增量修订，增加 `total_gold_stars` 缓存字段 | MEDIUM | 推迟至 v1.1；届时由相关 GDD 负责人增量修订 |
| OQ-3 | 家长首次启动引导（发现机制）：家长如何知晓右上角图标按钮的存在及长按 5 秒功能？是否需要首次使用 hint 或依赖外部引导（App Store 说明）？本 GDD 仅记录问题，不拥有解决职责。（A2 降级处理）| HIGH | GameRoot / HatchScene GDD 设计时解决 |
| ~~OQ-3~~ | ~~`trex_confused` / `trex_sitting` 动画名称占位（EC-11）~~ | ~~MEDIUM~~ | ✅ **已解决** — AnimationHandler GDD 增量修订（2026-05-08）增加 RECOGNIZE / SITTING 状态；MainMenu 改为调用 `play_recognize()` / `play_sitting()` 语义方法 |
| ~~OQ-4~~ | ~~`ProfileManager.get_profile_count()` 接口尚未在 ProfileManager GDD 中正式定义（DG-3）~~ | ~~LOW~~ | ✅ **已解决** — ProfileManager GDD 增量修订（2026-05-08）增加 Core Rule 13 |
