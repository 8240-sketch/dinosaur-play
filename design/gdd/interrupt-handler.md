# InterruptHandler

> **Status**: In Review
> **Author**: Zhang Shaocong + agents
> **Last Updated**: 2026-05-07 (Revision 2)
> **Implements Pillar**: P3 (声音是成长日记), P4 (家长是骄傲见证者) — 保全孩子当局的词汇进度

## Overview

InterruptHandler 是游戏的平台中断响应层——一个 AutoLoad 单例 Node，在任何场景下均可捕获 Android 系统事件：应用程序转入后台（息屏、来电、切换应用）和用户按下返回键。当中断发生时，InterruptHandler 决策是否需要停止当前章节的叙事推进，并通过调用 `ProfileManager.flush()` 将本局尚未写盘的词汇进度、故事进度强制落盘，确保进度不丢失。对于章节进行中的返回键事件，InterruptHandler 还负责导航回主菜单。

从孩子的视角，这个系统不存在——孩子只知道「来电接完后，T-Rex 还认识我」；家长只知道「孩子通关时的词汇金星没有消失」。InterruptHandler 是让这两件事成真的后盾：没有它，任何未按正常完结流程退出的场景都会导致当局进度丢失，6 个月后的回放录音和词汇金星都可能缺席。

## Player Fantasy

InterruptHandler 没有任何孩子能感受到的时刻——它是纯粹的基础设施，不出声，不被感知。它保护的，是家长六个月后打开词汇地图时会发生的那件事：点开金星旁的播放按钮，传来的是孩子那天电话来电打断游戏前一秒说出的「Apple!」——那声偏高、不确定、用尽了力气的声音。这个录音能在这里，是因为来电那一刻 InterruptHandler 完成了一次写盘；没有它，那次中断会带走这局的全部进度——金星、录音路径、故事位置，都不会等到六个月后。P3 的成长日记和 P4 的骄傲见证，都仰赖一个从不露面的人把门关好。

> **P3 数据契约前提**：上述家长体验的实现依赖一条技术契约链：VoiceRecorder 须在中断前将录音路径写入 ProfileManager（经由 VocabStore），ProfileManager.flush() 须在中断时将该路径持久化至磁盘。InterruptHandler 是契约链的最后一环——它触发 flush，但不拥有路径。如果 VoiceRecorder 或 VocabStore 的写入未在中断发生前完成，录音路径将丢失，家长六个月后听到的将是静默。**IH 仅能保全录音路径引用（内存中的文件路径字符串）；磁盘上录音文件的完整性由 VoiceRecorder GDD（#8）的 `interrupt_and_commit()` 契约保证，属于不同层级的数据完整性责任。**

> **金星（first_star_at）写入时机**：词汇金星（`first_star_at`）在孩子选出正确词汇时（RUNNING/CHOICE_PENDING 阶段）立即写入 ProfileManager 内存，不等到 `end_chapter_session()` 调用。因此 InterruptHandler 在中断时调用 `ProfileManager.flush()` 可完整保留本局已获得的金星，章节中断不会导致金星丢失。

## Detailed Design

### Core Rules

**Rule 1 — AutoLoad 单例身份**
InterruptHandler 是 GDScript AutoLoad 单例（全局名 `InterruptHandler`，`extends Node`），持续活跃于整个游戏生命周期，跨场景不销毁。同一时刻只有一个实例；多次中断事件通过 `_background_flush_pending` 标志防重入。节点的 `process_mode` 必须设置为 `PROCESS_MODE_ALWAYS`，确保 SceneTree 暂停时（如弹窗、过场黑屏）`_process()` 和 `_physics_process()` 仍正常运行——虽然 `_notification()` 本身不受 `process_mode` 影响（通知通过 `propagate_notification()` 遍历整棵树派发），但部分 Godot 子系统在树暂停时会抑制事件派发，保留 `PROCESS_MODE_ALWAYS` 是对未来行为变化的防御性设置。

**Rule 2 — `_ready()` 初始化**
- 订阅 `StoryManager.chapter_interrupted` 信号，处理器 `_on_chapter_interrupted(reason: String)`
- 设置内部标志 `_background_flush_pending: bool = false`（防 FOCUS_OUT + PAUSED 双触发）
- 设置内部标志 `_back_button_pending: bool = false`（返回键防重入守卫，防过渡帧内重复触发）

**Rule 3 — 平台级中断检测（`_notification(what: int)`）**

同时捕获两个 Android 通知（仅其一不足以覆盖所有场景）：

| 通知 | 触发场景 |
|------|---------|
| `NOTIFICATION_APPLICATION_FOCUS_OUT` | Home 键、来电接听、切换 App |
| `NOTIFICATION_APPLICATION_PAUSED` | 息屏（Activity.onPause()）——FOCUS_OUT 不可靠覆盖此场景 |
| `NOTIFICATION_WM_GO_BACK_REQUEST` | Android 10+ 手势导航返回（不产生 KEY_BACK InputEvent；与 `_unhandled_input` 路径互补）⚠️ 须在真机（手势导航设备 + 物理按键设备各自）验证互补行为，实现前不视为已证实 |
| `NOTIFICATION_APPLICATION_FOCUS_IN` | 前台恢复（重置标志） |
| `NOTIFICATION_APPLICATION_RESUMED` | Activity.onResume()（与 FOCUS_IN 对称，重置标志） |

> **`is_story_active` 状态定义**：RUNNING、CHOICE_PENDING = `true`；IDLE、LOADING、COMPLETING、STOPPED、ERROR = `false`。COMPLETING 已定义为 `false`：章节正在收尾，IH 无需介入中断序列，直接 flush 即可（无活跃章节分支）。

```
_notification(FOCUS_OUT or PAUSED):
    if _background_flush_pending == true → 直接返回（防双触发）
    _background_flush_pending = true
    if StoryManager.is_story_active:
        if is_instance_valid(VoiceRecorder):   # 权限被拒时 VoiceRecorder 合法不可用
            VoiceRecorder.interrupt_and_commit()  # P3 保护：固化录音路径
        # VoiceRecorder 不可用时静默跳过；录音路径无法固化，flush 继续保全金星等进度
        StoryManager.request_chapter_interrupt("app_background")
        ↳ chapter_interrupted 信号触发 → _on_chapter_interrupted("app_background") → flush
    else:
        ProfileManager.flush()  # 无活跃章节时也写盘（保护 times_played 等字段）

_notification(WM_GO_BACK_REQUEST):                    # Android 10+ 手势导航返回（不产生 KEY_BACK InputEvent）
    if _back_button_pending: return
    if StoryManager.is_story_active:
        _back_button_pending = true
        if is_instance_valid(VoiceRecorder):
            VoiceRecorder.interrupt_and_commit()
        StoryManager.request_chapter_interrupt("user_back_button")
        [启动 BACK_BUTTON_GUARD_TIMEOUT_MS 超时计时器]
    # is_story_active == false → 不消费，允许 Android OS 处理（最小化 App）

_notification(FOCUS_IN or RESUMED):
    _background_flush_pending = false
    # 若 SM 因 app_background 中断而停留在 STOPPED，恢复至 IDLE 允许开始新章节
    # 不执行场景导航——进程存活则保持当前场景让孩子继续游戏（GameScene 负责恢复 UI）
    if not StoryManager.is_story_active and StoryManager.current_state == StoryManager.State.STOPPED:
        StoryManager.confirm_navigation_complete()
```

**Rule 4 — 返回键处理（`_unhandled_input(event: InputEvent)`）**

仅在 `StoryManager.is_story_active == true` 时拦截 `ui_cancel`（Android back button）。执行顺序（必须按此序，不可调换）：
1. `get_viewport().set_input_as_handled()` — 防止 OS 执行进程退出（**必须最先执行**）
2. 若 `is_instance_valid(VoiceRecorder)`：调用 `VoiceRecorder.interrupt_and_commit()` — P3 保护：固化录音路径；VoiceRecorder 不可用时静默跳过
3. 调用 `StoryManager.request_chapter_interrupt("user_back_button")`
4. `_on_chapter_interrupted("user_back_button")` 经由信号回调执行 flush + 导航

当 `StoryManager.is_story_active == false` 时：**不消费事件**，允许当前场景节点或 Android OS 处理（MainMenu 可自行响应 back 键最小化 App）。

`_unhandled_input` 处理顺序保证：AutoLoad 节点在场景树中位于主场景之前，IH 的 `_unhandled_input` 在所有场景节点的 `_unhandled_input` **之前**触发——先于 GameScene、MainMenu 等。GUI `_gui_input()` 和 `_input()` 处理完成后进入 `_unhandled_input` 阶段，对话框或弹层可通过 `_input` 优先消费并调用 `set_input_as_handled()`，阻止事件传至 IH。IH 是 `_unhandled_input` 阶段中**最先**响应的节点，不是最后一个。

> **实现注意**：若 `request_chapter_interrupt()` 调用后 SM 未发出 `chapter_interrupted` 信号（SM 处于非 RUNNING/CHOICE_PENDING 过渡状态），`is_story_active` 仍为 `true`，后续 back button 事件会再次触发本处理器。实现应设置 `_back_button_pending: bool` 标志，在首次调用 `request_chapter_interrupt()` 后置 `true`，在 `_on_chapter_interrupted()` 响应时置 `false`，防止过渡帧内重复触发（见 E3）。为防止 SM 永不发出信号导致 `_back_button_pending` 永久锁定，实现须启动一个 `BACK_BUTTON_GUARD_TIMEOUT_MS`（见 Tuning Knobs）的超时计时器：超时触发时若 `_back_button_pending` 仍为 `true`，强制置 `false` 并 `push_warning`（见 E3）。

**Rule 5 — `_on_chapter_interrupted(reason: String)` 处理器**

订阅 `StoryManager.chapter_interrupted` 信号，根据 reason 分支：

| reason | ProfileManager.flush() | 场景导航 |
|--------|----------------------|---------|
| `"app_background"` | ✅ 调用 | 不导航（用户自行回来） |
| `"user_back_button"` | ✅ 调用 | `get_tree().change_scene_to_file(MAIN_MENU_PATH)` |
| `"profile_switch"` | ❌ 不调用 | 不导航（ProfileManager switch 序列步骤 e 已 flush） |

> `get_tree().change_scene_to_file()` 在 Godot 4 中内部延迟至帧末执行，在 `_unhandled_input` 中直接调用安全，无需 `call_deferred`。实现时须检查返回值：`var err = get_tree().change_scene_to_file(MAIN_MENU_PATH)`；若 `err != OK`，`push_error` 记录失败并**跳过** `confirm_navigation_complete()` 调用（导航未发生，SM 无需从 STOPPED 重置）。导航返回 OK 后，IH 须立即调用 `StoryManager.confirm_navigation_complete()`，将 SM 状态从 STOPPED 重置为 IDLE，防止 SM 永久锁死（见 OQ-4）。

**Rule 6 — `StoryManager.request_chapter_interrupt(reason: String)` — SM 补充方法（OQ-4 解析）**

为解决 StoryManager OQ-4，StoryManager 需补充此公开方法（本 GDD 批准后更新 story-manager.md）：
- **合法状态**：RUNNING 或 CHOICE_PENDING → 执行中断序列
- **其他状态**（IDLE、LOADING、COMPLETING、STOPPED、ERROR）：`push_warning`，直接返回
- **中断序列（同步，严禁 `await`）**：
  a. 取消安全超时计时器（若存在）；断开 `TtsBridge.speech_completed` 临时连接
  b. **状态立即转为 `STOPPED`**（先置状态，防止 emit 后重入时 `is_story_active` 仍为 true）
  c. `_ink_story = null`；`_vocab_word_texts = {}`（状态已 STOPPED，安全清除引用）
  d. **不调用** `VocabStore.end_chapter_session()`（章节中断，非正常完结）
  e. **不调用** `ProfileManager.flush()`（flush 责任属于 InterruptHandler）
  f. emit `chapter_interrupted(reason)`（引用已清除后再发出信号，防重入访问 null `_ink_story`）

### States and Transitions

InterruptHandler 维护两个防重入布尔标志，无持久状态机：

**`_background_flush_pending`**（后台中断防双触发）：

| 事件 | 标志变化 |
|------|---------|
| `NOTIFICATION_APPLICATION_FOCUS_OUT` / `PAUSED` | `false → true`（首次触发后锁定） |
| `NOTIFICATION_APPLICATION_FOCUS_IN` / `RESUMED` | `true → false`（重置，允许下次触发） |
| `_background_flush_pending == true` 时再次收到后台通知 | 忽略（防重入） |

**`_back_button_pending`**（返回键防过渡帧重复触发）：

| 事件 | 标志变化 |
|------|---------|
| 返回键触发（`WM_GO_BACK_REQUEST` / `ui_cancel`）且章节活跃 | `false → true` |
| `_on_chapter_interrupted()` 收到 `chapter_interrupted` 信号 | `true → false` |
| `BACK_BUTTON_GUARD_TIMEOUT_MS` 超时（SM 未发出信号） | `true → false`（强制重置 + `push_warning`） |

### Interactions with Other Systems

| 系统 | 方向 | 接口 | 数据 | 时机 |
|------|------|------|------|------|
| **StoryManager** | IH 查询 | `is_story_active: bool` | — | back button 检测时，决策是否拦截 `ui_cancel` |
| **StoryManager** | IH → 调用 | `request_chapter_interrupt(reason: String)` | reason | app_background 或 user_back_button 检测到且章节活跃时 |
| **StoryManager** | (signal) → IH | `chapter_interrupted(reason: String)` | reason | SM 完成 request_chapter_interrupt() 后同步发出 |
| **VoiceRecorder** | IH → 调用 | `interrupt_and_commit()` | — | FOCUS_OUT/PAUSED/WM_GO_BACK_REQUEST/`ui_cancel`（`_unhandled_input`）四路径，且章节活跃时，`request_chapter_interrupt()` 之前调用，固化录音路径至 VocabStore；调用前须 `is_instance_valid()` 守卫，权限被拒时静默跳过 |
| **ProfileManager** | IH → 调用 | `flush() -> bool` | — | `_on_chapter_interrupted("app_background"/"user_back_button")` 中；或无活跃章节时直接 app_background |
| **SceneTree** | IH → 调用 | `get_tree().change_scene_to_file(path: String)` | 场景路径 | `_on_chapter_interrupted("user_back_button")` 执行 flush 后 |
| **StoryManager** | IH → 调用 | `confirm_navigation_complete()` | — | `_on_chapter_interrupted("user_back_button")` 场景导航后立即调用，将 SM STOPPED → IDLE |

## Formulas

InterruptHandler 不包含游戏数值公式。本节定义两个决策谓词——InterruptHandler 核心判断逻辑的可测试形式。

---

### F-1 — 后台中断触发谓词

```
should_flush_on_background(is_story_active: bool) -> void

  if is_story_active:
      [if is_instance_valid(VoiceRecorder)]: VoiceRecorder.interrupt_and_commit()
      StoryManager.request_chapter_interrupt("app_background")
      → flush 由 _on_chapter_interrupted("app_background") 执行
  else:
      ProfileManager.flush()
      → 直接写盘（保护 times_played 等进行中字段）
```

| 变量 | 类型 | 来源 |
|------|------|------|
| `is_story_active` | bool | `StoryManager.is_story_active`（章节 RUNNING/CHOICE_PENDING = true；IDLE/STOPPED = false） |

注意：两条路径均最终执行 `ProfileManager.flush()`，区别在于路由方式——有章节时经过 SM 中断序列，无章节时直接调用。

---

### F-2 — 返回键拦截谓词

```
should_intercept_back_button(is_story_active: bool) -> bool
    return is_story_active
```

| 变量 | 类型 | 来源 |
|------|------|------|
| `is_story_active` | bool | `StoryManager.is_story_active` |

**输出范围**：bool。`true` = 消费事件 + 中断章节；`false` = 事件透传至当前场景或 OS。

**示例：**
- 章节进行中（RUNNING / CHOICE_PENDING）→ `true` → 消费 back button，中断章节，导航 MainMenu
- 主菜单中（无章节）→ `false` → back button 透传，Android OS 最小化 App

---

### F-3 — 防重入标志逻辑

```
_background_flush_pending: bool

on_background_notification():
    if _background_flush_pending: return   # 防双触发
    _background_flush_pending = true
    [执行 F-1 逻辑]

on_foreground_notification():
    _background_flush_pending = false
```

处理 `NOTIFICATION_APPLICATION_FOCUS_OUT` 和 `NOTIFICATION_APPLICATION_PAUSED` 在同一次后台事件中可能同时触发的情况（Android 实现差异）。

## Edge Cases

| # | 边界情况 | InterruptHandler 行为 | 调用方职责 |
|---|---------|---------------------|-----------|
| E1 | FOCUS_OUT 和 PAUSED 在同一次息屏事件中先后触发 | `_background_flush_pending` 标志锁定：首次触发执行 flush 序列，后续通知检测到标志为 `true` 直接返回，flush 不重复执行 | 无。IH 内部防重入 |
| E2 | `app_background` 时 `ProfileManager.flush()` 返回 `false`（磁盘满或文件锁） | IH 不重试，不抛异常；失败静默记录（`push_error`）。此次写盘失败意味着本局中断前的进度可能丢失；但 StoryManager 已转入 STOPPED 状态，章节不会继续推进 | InterruptHandler 应 `push_error` 留存日志；不向孩子展示错误提示 |
| E3 | back button 按下时 `request_chapter_interrupt()` 调用，SM 处于非 RUNNING/CHOICE_PENDING 状态（如 COMPLETING 尾帧） | SM 收到后 `push_warning` 并返回，`chapter_interrupted` 信号不发出；IH 因未收到信号而不导航。`BACK_BUTTON_GUARD_TIMEOUT_MS` 超时后 `_back_button_pending` 自动重置为 `false` 并 `push_warning`，防止 back button 永久失效 | IH Rule 4 实现须启动超时计时器，超时后强制解锁 |
| E4 | app 从后台恢复（FOCUS_IN/RESUMED），SM 状态为 STOPPED | InterruptHandler 重置 `_background_flush_pending = false`；IH 调用 `confirm_navigation_complete()` 将 SM 从 STOPPED 恢复为 IDLE，**不执行场景导航**（进程存活则保持当前场景，让孩子继续游戏，避免强制返回主菜单打断上下文）。GameScene 负责检测 SM.IDLE 并显示恢复 UI（如「章节已中断，重新开始？」覆盖层） | GameScene GDD 须定义 SM.IDLE 状态下的界面契约。进程被杀后冷启动的「上次中断提示」由 MainMenu/GameRoot 负责（见 OQ-8），不在 IH 范围内 |
| E5 | `chapter_interrupted` 信号收到 `"profile_switch"` reason（ProfileManager 驱动的切换） | Rule 5 明确：IH 不调用 flush、不导航 | ProfileManager 和 GameRoot 协作处理 profile switch UI |
| E6 | back button 在 HatchScene（首次启动）按下，`is_story_active == false` | `is_story_active == false` → IH 不拦截；HatchScene 或 Android OS 处理 back button | HatchScene GDD 定义是否响应 back button |
| E7 | 快速连按两次 back button | 首次：消费事件 + 调用 `request_chapter_interrupt("user_back_button")` + SM 转 STOPPED；第二次：`is_story_active == false` → IH 不拦截，事件透传 | 无。逻辑自洽 |
| E8 | 无活跃档案（ProfileManager 处于 `NO_ACTIVE_PROFILE`）时 app 后台 | IH 直接调用 `ProfileManager.flush()`；PM `flush()` 在 `NO_ACTIVE_PROFILE` 状态下返回 `false`，不执行写盘。无副作用 | 无需额外处理 |
| E9 | `user_back_button` 触发场景切换，`change_scene_to_file()` 失败（`err != OK`），SM 保持 STOPPED；用户随后按 Home 键后返回，触发 FOCUS_IN | IH 在 FOCUS_IN 时检测 SM.STOPPED，调用 `confirm_navigation_complete()` 将 SM 重置为 IDLE。当前场景仍为 GameScene（切换未发生），SM 与场景不同步——GameScene 须对 SM.IDLE 状态有鲁棒 UI 处理（同 E4 契约） | `change_scene_to_file()` 失败时须 `push_error`；后续 FOCUS_IN 恢复路径与 E4 相同，GameScene 恢复 UI 覆盖层兜底处理 |

## Dependencies

### 上游依赖（InterruptHandler 依赖）

| 系统 | 接口 | 用途 |
|------|------|------|
| **StoryManager** | `is_story_active: bool`（只读属性） | back button 检测时判断是否需要拦截 `ui_cancel` |
| **StoryManager** | `request_chapter_interrupt(reason: String)` | app 后台或 back button 触发时启动中断序列 |
| **StoryManager** | `chapter_interrupted(reason: String)` 信号 | SM 完成中断后回调 `_on_chapter_interrupted`，执行 flush / 导航 |
| **StoryManager** | `confirm_navigation_complete()` | `_on_chapter_interrupted("user_back_button")` 导航后调用，将 SM STOPPED → IDLE，防止 SM 永久锁死 |
| **VoiceRecorder** | `interrupt_and_commit()` | 中断前主动调用（FOCUS_OUT/PAUSED/WM_GO_BACK_REQUEST/`ui_cancel` 四路径），固化录音路径至 VocabStore；确保 P3 录音路径在 flush 时已就绪。**调用前须以 `is_instance_valid()` 检查可用性**：权限被拒时 VoiceRecorder 合法不可用，静默跳过，不崩溃 |
| **ProfileManager** | `flush() -> bool` | 写盘：将未持久化进度强制落盘 |
| **SceneTree** | `get_tree().change_scene_to_file(path: String)` | `user_back_button` 中断后导航至主菜单 |
| **VocabStore** | （数据前提，非直接调用） | VocabStore 须在中断发生前将录音路径字段更新至 ProfileManager 内存；VoiceRecorder.interrupt_and_commit() 确保此前置已完成 |

### 下游依赖（依赖 InterruptHandler）

无。InterruptHandler 是终端基础设施层——只向上调用，不被其他游戏系统反向依赖。

### 约束

- **AutoLoad 加载顺序**：InterruptHandler 必须在 StoryManager 和 ProfileManager 之后加载，确保 `_ready()` 订阅 `chapter_interrupted` 信号时两者已初始化。
- **`ui_cancel` Input Map 必须包含 KEY_BACK**：Godot 4 默认 `ui_cancel` 仅映射 KEY_ESCAPE；Android back button 发出 KEY_BACK，不属于默认 `ui_cancel`。须在 Project Settings → Input Map → `ui_cancel` 手动添加 KEY_BACK，否则 `_unhandled_input` 中的 `ui_cancel` 检测在真机上完全失效（见 OQ-5）。
- **`process_mode = PROCESS_MODE_ALWAYS`**：AutoLoad 节点默认 `PROCESS_MODE_INHERIT`；若 SceneTree 暂停，IH 将无法接收 Android 通知。实现时须在 `_ready()` 或场景属性面板中显式设置 `process_mode = PROCESS_MODE_ALWAYS`。
- **不调用 SaveSystem**：flush 权威路径为 IH → ProfileManager → SaveSystem；IH 不绕过 ProfileManager。
- **不调用 VocabStore**：章节正常完结时由 StoryManager 调用 `VocabStore.end_chapter_session()`；IH 走中断路径，不触发此调用。

## Tuning Knobs

| 旋钮 | 当前值 | 类型 | 安全范围 | 影响 |
|------|--------|------|---------|------|
| `MAIN_MENU_PATH` | `"res://src/ui/MainMenu.tscn"` | 常量（String） | N/A | back button 导航目标；MainMenu 路径变更时此处同步更新 |
| `BACK_BUTTON_GUARD_TIMEOUT_MS` | `3000` | 常量（int，毫秒） | 1000–10000 | `_back_button_pending` 守卫标志自动超时重置时长；值过小会在 SM 正常过渡期内误重置（允许重复触发），值过大会在 SM 异常时延迟 back button 恢复响应 |

> **实现注意 — Timer 单位**：`Timer.wait_time` 接受秒（float），而本常量单位为毫秒（int）。设置计时器时必须使用 `timer.wait_time = BACK_BUTTON_GUARD_TIMEOUT_MS / 1000.0`（浮点除），否则将设置 3000 秒（约 50 分钟）超时，守卫永不触发。

InterruptHandler 无其他数值调参项。所有时序参数（如 ProfileManager flush 超时、StoryManager 状态转换）均由下游系统负责。

## Visual/Audio Requirements

无。InterruptHandler 是纯基础设施层，不产生任何视觉或音频效果。

## UI Requirements

无。InterruptHandler 不直接渲染 UI。back button 触发的导航调用 `change_scene_to_file(MAIN_MENU_PATH)`，MainMenu 场景负责自身 UI 渲染。

## Acceptance Criteria

| # | 验收条件 | 对应规则 | 测试类型 |
|---|---------|---------|---------|
| AC-1a | 应用转入后台（`is_story_active == false`，模拟 FOCUS_OUT），`ProfileManager.flush()` 在同一通知回调内被直接调用且返回值被记录 | Rule 3 + F-1 | 集成测试 |
| AC-1b | 章节进行中（`is_story_active == true`）应用转入后台，`ProfileManager.flush()` 在 `_on_chapter_interrupted()` 信号处理器中被调用（非通知回调直接调用）；可通过信号追踪验证调用链：FOCUS_OUT → request_chapter_interrupt → chapter_interrupted → flush | Rule 3 + F-1 | 集成测试 |
| AC-2 | 息屏（模拟 PAUSED）时，`ProfileManager.flush()` 被调用；若 FOCUS_OUT 和 PAUSED 同时触发，flush 只调用一次 | Rule 3 + F-3 | 集成测试 |
| AC-3 | 章节进行中（`StoryManager.is_story_active == true`）按下物理返回键（`ui_cancel` / `_unhandled_input` 路径），`get_viewport().set_input_as_handled()` 被调用，Android OS 不执行进程退出（仅适用于 `_unhandled_input` 路径；`WM_GO_BACK_REQUEST` 通知路径通过 OS 机制处理，不经此接口） | Rule 4 | 手动测试（Android 设备） |
| AC-4 | back button 中断后，场景切换至 MainMenu；切换在同一帧结束后完成，不产生一帧空白 | Rule 4 + Rule 5 | 手动测试 |
| AC-5 | 章节进行中后台中断，flush 完成后，磁盘持久化数据中 `first_star_at`（词汇金星时间戳）和 `recording_path`（录音文件路径）与中断前 ProfileManager 内存中的值一致（无进度丢失）；`last_played_at` 和 `story_progress` 不在本 AC 验证范围（由 `begin_session()` / `end_chapter_session()` 负责写入） | Rule 3 + Rule 5 + P3 数据契约 | 集成测试 |
| AC-6 | 无活跃章节（MainMenu 界面）按下 back button，IH 不消费事件，Android 最小化 App | Rule 4 + F-2 | 手动测试（Android 设备） |
| AC-7 | `chapter_interrupted("profile_switch")` 信号到达时，IH 不调用 `ProfileManager.flush()`，不执行场景导航 | Rule 5 | 单元测试 |
| AC-8 | 快速连续触发两次 FOCUS_OUT，flush 只调用一次；FOCUS_IN 后再次 FOCUS_OUT，flush 再次调用一次 | F-3 | 单元测试 |
| AC-9 | `StoryManager.request_chapter_interrupt()` 在 SM 非 RUNNING/CHOICE_PENDING 状态被调用时，`chapter_interrupted` 信号不发出，IH 不导航 | Rule 6 + E3 | 单元测试 |
| AC-10 | InterruptHandler 作为 AutoLoad 在整个游戏生命周期保持单一实例，场景切换后实例不销毁 | Rule 1 | 集成测试 |
| AC-11 | back button 触发 `request_chapter_interrupt()` 后，`_back_button_pending` 置 `true`；`_on_chapter_interrupted()` 收到信号后置 `false`；若 `BACK_BUTTON_GUARD_TIMEOUT_MS` 超时仍未收到信号，`_back_button_pending` 强制重置为 `false` 并记录 `push_warning` | Rule 4 + E3 + BACK_BUTTON_GUARD_TIMEOUT_MS | 单元测试 |
| AC-12 | 章节处于 COMPLETING 状态（`is_story_active == false`）时 app 后台，IH 不调用 `request_chapter_interrupt()`，直接调用 `ProfileManager.flush()`；flush 成功保留已获得的词汇金星 | Rule 3 | 集成测试 |
| AC-13 | app 后台中断（SM 转 STOPPED）后恢复前台（FOCUS_IN/RESUMED），SM 状态恢复为 IDLE，`begin_chapter()` 可正常调用，游戏不进入死锁 | Rule 3 FOCUS_IN 分支 | 集成测试 |
| AC-14a | 章节进行中后台中断（FOCUS_OUT/PAUSED 路径），`VoiceRecorder.interrupt_and_commit()` 在 `StoryManager.request_chapter_interrupt()` 之前被调用（调用顺序正确） | Rule 3 + P3 数据契约 | 集成测试 |
| AC-14b | 章节进行中后台中断后，flush 完成，磁盘持久化数据中的录音路径与中断前 VocabStore 内存中的录音路径字符串一致（数据完整性） | Rule 3 + P3 数据契约 | 集成测试 |
| AC-15 | `WM_GO_BACK_REQUEST` 通知触发时，`is_story_active == true`：章节中断（SM 转 STOPPED）、ProfileManager flush、场景导航至 MainMenu 全部执行 | Rule 3 | 手动测试（Android 10+ 手势导航设备） |
| AC-16 | `WM_GO_BACK_REQUEST` 通知触发时，`is_story_active == false`：IH 不处理（不 flush、不导航），Android OS 正常最小化 App | Rule 3 | 手动测试（Android 10+ 手势导航设备） |
| AC-17 | `user_back_button` 导航完成后，`confirm_navigation_complete()` 被调用，SM 状态为 IDLE，随后 `begin_chapter()` 可正常调用（SM 未锁死） | Rule 5 + OQ-4 | 集成测试 |

## Open Questions

| # | 问题 | 影响 | 待处理时机 |
|---|------|------|-----------|
| OQ-1 | `StoryManager.request_chapter_interrupt()` 和 `confirm_navigation_complete()` 方法已在本 GDD Rule 6 / Rule 5 完整定义——需在 `story-manager.md` 中补充这两个方法 | StoryManager GDD 与 IH GDD 存在短暂不同步 | IH GDD 批准后立即执行 |
| OQ-2 | `MAIN_MENU_PATH` 路径需在 MainMenu GDD（#11）确认后核对一致 | path 不匹配将导致运行时跳转失败 | MainMenu GDD 设计时确认 |
| OQ-3 | E4 中 SM 从后台恢复后保持 STOPPED——是否需要在 GameScene 或 MainMenu 增加「上次中断提示」UI？ | 用户体验设计决策，不影响 IH 本身 | ChoiceUI / MainMenu GDD 中考虑 |
| OQ-4 | `StoryManager.confirm_navigation_complete()` 方法定义：IH 导航后调用，将 SM 从 STOPPED 重置为 IDLE，防止游戏死锁。此方法必须在 story-manager.md 中补充 | 不实现将导致 back button 中断后 SM 永久停留 STOPPED，游戏无法继续 | IH GDD 批准后与 OQ-1 同步处理 |
| OQ-5 | Godot 4 默认 Input Map 的 `ui_cancel` 动作仅映射 KEY_ESCAPE，不包含 Android KEY_BACK。在 Godot 编辑器 Project Settings → Input Map 中必须将 KEY_BACK 加入 `ui_cancel` 动作，否则 `_unhandled_input` 中的 `ui_cancel` 检测在真机上完全失效 | back button 中断逻辑在真机上静默失效，IH 不拦截任何事件 | 实现 IH 前在 Project Settings 验证并补充 |
| OQ-6 | `VoiceRecorder.interrupt_and_commit()` 接口契约待 VoiceRecorder GDD（#8）确认：方法须同步完成（无 `await`）或在合理时间窗口内保证录音路径写入 VocabStore；若 VoiceRecorder 尚未录制则为 no-op | VoiceRecorder GDD 未确认前，P3 录音路径保全路径存在接口假设风险 | VoiceRecorder GDD 设计时与本 GDD 对齐 |
| OQ-7 | `StoryManager.current_state` 属性需暴露为公开只读属性（供 FOCUS_IN 恢复路径检测 STOPPED 状态）；当前 SM GDD 未明确 `current_state` 的可见性 | FOCUS_IN SM 恢复逻辑依赖此属性；若不暴露需通过其他机制实现 STOPPED 检测 | IH GDD 批准后在 story-manager.md 更新时同步确认 |
| OQ-8 | 进程被 Android 杀死后冷启动，是否应在 MainMenu 显示「上次有正在进行的游戏，想继续吗？」提示？ | 若设计决策为"是"，需在 MainMenu/GameRoot GDD 中定义：检测 `story_progress.last_played_chapter` 非空时显示提示；此场景不在 IH 范围内（进程被杀时 IH 不存在） | MainMenu GDD（#11）或 GameRoot GDD 设计时确认 |

> ~~StoryManager OQ-4~~（由谁触发 `chapter_interrupted("app_background"/"user_back_button")`）已在本 GDD 中解析：InterruptHandler 调用 `StoryManager.request_chapter_interrupt(reason)`，SM 作为唯一信号发出方。✅ RESOLVED。
