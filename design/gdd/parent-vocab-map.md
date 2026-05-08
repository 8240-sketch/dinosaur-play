# ParentVocabMap

> **Status**: Approved with Conditions
> **Author**: user + agents
> **Last Updated**: 2026-05-08
> **Implements Pillar**: P3（声音是成长日记）、P4（家长是骄傲见证者）
> **Review**: /design-review 2026-05-08 — 4 BLOCKING 已修复；OQ-2/OQ-3 为实现前必须完成的跨文档任务

## Overview

ParentVocabMap 是面向家长的全屏词汇进度视图，通过长按 5 秒从 MainMenu 或章节通关画面进入，孩子的正常触屏操作（≤ 0.5s）不会误触。数据层：从 VocabStore 查询当前活跃档案的 5 个 Chapter 1 词汇（`VOCAB_WORD_IDS_CH1`）的 `gold_star_count`、`is_word_learned`、`first_star_at`，从 VoiceRecorder 查询每个词汇的 `recording_paths` 列表，以金星卡片形式渲染；家长点击播放按钮时调用 `VoiceRecorder.play_recording()` 收听孩子录音，订阅 VocabStore `gold_star_awarded` 信号在地图开启期间实时更新星级。玩家层：家长长按屏幕进入一张「成长地图」——5 个恐龙词汇各自的学习进度一目了然，已掌握的词汇金星饱满发光，正在积累的词有几颗正在亮起；每个词旁有播放按钮，按下去就能听见孩子当时学这个词时留下的声音录音。这不是成绩单，是一本会响的相册：P3（声音是成长日记）在这里以可交互的形式呈现；P4（家长是骄傲见证者）在这里以私密的方式成立——这个入口只有家长知道在哪里，孩子不会偶然闯入。

## Player Fantasy

设置孩子档案的时候，App 告诉了你一件事：「长按主菜单 5 秒，进入孩子的成长地图。」那时候没什么可看的，孩子还没玩过一局。

第一颗金星出现的那天，主菜单上又出现了一次轻轻的提示。你按住屏幕，一秒、两秒、三秒……五秒之后，进来了。

家长进来的时候，孩子可能正在别处玩，或者已经睡了。词汇地图告诉你一件孩子还没意识到的事：这个词，他学会了。金星不是奖励，不是分数，只是记录——他在故事里选对了，说出来了，三颗星是真的认识，不是猜中。家长比孩子更先知道这件事，就像有时候你会在孩子睡着前先读完他枕边的书，等着他来跟你说「妈妈你知道吗……」。

播放按钮不是总有，只有孩子在故事里教过 T-Rex 这个词的时候才会出现。点下去，听见的是孩子那一次认真开口时的声音——那么一板一眼，好像全世界只有这件事是要紧的。那次认真孩子早忘了，但声音在这里，完整的，等你来发现。

孩子的声音会变，你每天在听，但记不住它怎么变的。这里存的是那个词在某个具体时刻的样子——那个 R 还没发利落，那个「big」的重音踩在奇怪的地方，那个下午孩子刚刚第一次学会这个词时的认真劲。那个版本只在那段时间存在，再长大一点就改变了，改变了就找不回来了。

词汇地图旁边的日期告诉你是哪一天。录音告诉你那天发生了什么。等孩子大一些，再点开来听——不是为了证明进步了，而是因为那条声音存着那个中间步骤的形状，那个正在往更远处走的孩子经过这里时留下的样子。

## Detailed Design

### Core Rules

1. **CanvasLayer 身份**：ParentVocabMap 是 CanvasLayer 节点（`layer = 128`，高于所有游戏 UI 层），由触发场景（MainMenu 或 GameScene 通关画面）实例化并 `add_child`；`_ready()` 中执行 `get_tree().paused = true`；`queue_free()` 前执行 `get_tree().paused = false`。所有 ParentVocabMap 内部节点的 `process_mode` 设为 `PROCESS_MODE_ALWAYS`，确保在 SceneTree 暂停期间仍可响应触屏输入和录音回放。（回放在暂停期间生效的前提：VoiceRecorder 的 `_playback_player.process_mode` 亦须为 `PROCESS_MODE_ALWAYS`，见 VoiceRecorder GDD——该设置由 VoiceRecorder 自身负责，ParentVocabMap 无需干预。）

2. **长按 5 秒检测（触发场景职责）**：触发场景（MainMenu / GameScene 通关画面）在 `_unhandled_input()` 中监听 `InputEventScreenTouch`（使用 `_unhandled_input` 而非 `_input`：Button 等可交互控件会消费触屏事件，`_unhandled_input` 仅收到未被消费的事件，自然实现「交互控件上不启动计时器」，无需手动 hit-test）：若触屏按下位置命中**非交互背景区域**，启动 `_parent_hint_timer`（5.0 秒，`one_shot = true`）并显示进度环；松手时取消计时器、重置进度环；计时器超时时实例化 `ParentVocabMap.tscn` 并 `add_child`。**漂移容忍**：在触屏按下点 20dp 半径内的 `InputEventScreenDrag` 不中断计时器（手指轻微移动属正常持握行为）；累计漂移超过 20dp 时取消计时并重置进度环。

3. **发现提示机制**：
   - **NameInputScreen 首次建档**：完成姓名输入后，NameInputScreen 展示一行提示文字「家长长按屏幕 5 秒可进入孩子成长地图」，3 秒淡出；不需要家长操作（NameInputScreen GDD 需补充此 Interaction，见 OQ-1）
   - **MainMenu 金星提示**：VocabStore `gold_star_awarded` 信号触发后，MainMenu 在 T-Rex 旁显示提示标记（💡+「成长地图」）；提示标记在 MainMenu 进入后**延迟 30 秒**显示（减少孩子高频触屏期的视觉干扰）；直到 `parent_map_hint_dismissed = true`（ProfileManager `profile` section 字段，见 OQ-2）为止，每次打开 MainMenu 均显示；提示标记点击仅显示提示动画，不直接打开地图

4. **数据加载（`_ready()` 同步）**：实例化时在 `_ready()` 中同步查询：对 `VOCAB_WORD_IDS_CH1` 全部 5 词调用 `VocabStore.get_gold_star_count(word_id)`、`get_first_star_at(word_id)`、`is_word_learned(word_id)`；若 `is_instance_valid(VoiceRecorder)` 为 true 则调用 `VoiceRecorder.get_recording_paths(word_id)`，否则录音列表默认为 `[]`。查询结果注入各 `VocabEntryPanel.setup()` 方法。降级：VocabStore 查询失败时该词以 0 星展示；录音列表为空时播放区域完全隐藏。

5. **实时金星更新**：`_ready()` 中订阅 `VocabStore.gold_star_awarded(word_id, new_star_count)`；收到信号时调用对应 `VocabEntryPanel.set_star_count(new_star_count)` 更新显示；若 `new_star_count >= IS_LEARNED_THRESHOLD`，同时将对应面板切换为 MASTERED 状态（由此在 ACTIVE 期间无需独立订阅 `word_learned` 信号——VocabStore GDD 中 `word_learned` 接收方列表需移除 ParentVocabMap，见 OQ-3）；订阅随 `queue_free()` 自动断开。

6. **录音列表展示（每个词汇）**：若 `recording_paths.is_empty()`，播放区域完全隐藏，不占布局空间。若有多条录音：按时间戳从新到旧排列（最新在上）；若 `recording_paths.size() > MAX_RECORDINGS_DISPLAYED`，保留最新的 `MAX_RECORDINGS_DISPLAYED - 1` 条 + 始终钉住时间戳最旧的 1 条（确保孩子第一次录制的声音永不截断，对应 P3 核心承诺），每条显示「录音 N · 年-月-日」（N 为按录制顺序的编号，最旧 = 1，见 D3）；点击触发 `VoiceRecorder.play_recording(path)`；同时最多一条在播放——新播放启动前须**主动**将前一条目视觉状态重置为 idle（`stop_playback()` 不保证发出 `playback_completed` 信号，不可依赖信号回调重置）；`playback_failed("file_not_found")` 时该条目灰化不可点击。

7. **关闭与退出**：右上角 `×` 按钮（最小 80dp）；Android 返回键（在 `_notification()` 中处理 `NOTIFICATION_WM_GO_BACK_REQUEST`）和桌面端 `ui_cancel`（在 `_unhandled_input()` 中处理 `InputEventAction`）均触发关闭流程——两者是不同机制，实现时须分别处理。关闭顺序：① `VoiceRecorder.stop_playback()`（若 VoiceRecorder 有效）→ ② 若 `parent_map_hint_dismissed == false`，将其置 true 并调用 `ProfileManager.flush()` → ③ `get_tree().paused = false` → ④ `queue_free()`。

---

### States and Transitions

| 状态 | 描述 | 进入条件 | 退出条件 |
|------|------|---------|---------|
| **HIDDEN** | 未实例化，触发场景正常运行 | 初始状态 / 关闭后 | 长按计时器触发 |
| **ENTERING** | 长按倒计时中（进度环展示） | 触屏按下非交互区域 | 松手（→HIDDEN）或 5 秒完成（→ACTIVE） |
| **ACTIVE** | ParentVocabMap 显示，SceneTree 暂停 | 长按 5 秒完成 | ×/返回键（→HIDDEN） |
| **PLAYING** | ACTIVE 中录音正在回放 | `play_recording()` 返回 true | `playback_completed` / `playback_failed` / 关闭（→ACTIVE→HIDDEN） |

```
HIDDEN ──[长按 5s]──▶ ENTERING ──[5s 完成]──▶ ACTIVE ──[×/返回]──▶ HIDDEN
                       ──[松手]──▶ HIDDEN        │
                                              ──[点播放]──▶ PLAYING ──▶ ACTIVE
```

---

### Interactions with Other Systems

| 系统 | 方向 | 接口 | 说明 |
|------|------|------|------|
| **VocabStore**（AutoLoad） | 调用 | `get_gold_star_count(word_id)`、`get_first_star_at(word_id)`、`is_word_learned(word_id)` × 5 | `_ready()` 同步查询 |
| **VocabStore** | 订阅 | `gold_star_awarded(word_id, new_star_count)` | ACTIVE 期间实时更新星级 |
| **VoiceRecorder**（AutoLoad，可选） | 调用（带 `is_instance_valid` 守卫） | `get_recording_paths(word_id)` × 5、`play_recording(path)`、`stop_playback()` | 回放侧接口；VoiceRecorder 被砍除时录音区域全部隐藏 |
| **VoiceRecorder** | 订阅 | `playback_started(path)`、`playback_completed(path)`、`playback_failed(path, reason)` | 更新播放按钮视觉状态 |
| **ProfileManager**（AutoLoad） | 调用 | `get_section("profile").get("parent_map_hint_dismissed", false)`；`flush()` | 发现提示状态持久化（OQ-1）|
| **MainMenu / GameScene** | 触发方 | 长按 5 秒计时器 → 实例化 ParentVocabMap | 触发场景负责长按检测逻辑 |
| **NameInputScreen** | 单向通知 | 展示长按入口提示文字（OQ-1 跨文档更新） | NameInputScreen GDD 需补充 |

## Formulas

本系统无游戏数值公式。所有数值计算在上游系统完成，ParentVocabMap 只映射展示状态。

**D1 — 金星视觉等级映射（引用 VocabStore，不重新定义）**

```
star_tier(word_id) =
  FRESH       if gold_star_count == 0
  PROGRESSING if 1 ≤ gold_star_count < IS_LEARNED_THRESHOLD
  MASTERED    if gold_star_count ≥ IS_LEARNED_THRESHOLD（或 is_word_learned == true）
```

| 变量 | 来源 | 锁定值 |
|------|------|--------|
| `gold_star_count` | `VocabStore.get_gold_star_count(word_id)` | 0–∞ |
| `IS_LEARNED_THRESHOLD` | `entities.yaml`（权威定义；VocabStore GDD 拥有） | 3 |

> 此公式与 PostcardGenerator D1 相同。ParentVocabMap 引用，不拥有阈值。

**D2 — 录音条目排序与截断（时间戳解析）**

```
sort_key(path) = path 中形如 "YYYYMMDDTHHmmssZ" 的时间戳子串
sorted_paths = recording_paths.sorted_custom(func(a, b): return sort_key(a) > sort_key(b))
# 结果：最新录音排在列表最上方（降序）。时间戳格式由 VoiceRecorder F3 定义（字典序等价于时间序）

# B-1 首条保护：若录音数超出上限，始终保留最旧一条
if sorted_paths.size() > MAX_RECORDINGS_DISPLAYED:
    display_paths = sorted_paths.slice(0, MAX_RECORDINGS_DISPLAYED - 1) + [sorted_paths[-1]]
else:
    display_paths = sorted_paths
# display_paths[0] = 最新录音；display_paths[-1] = 最旧录音（始终可见）
```

| 符号 | 类型 | 范围 | 来源 |
|------|------|------|------|
| `sort_key` | `String` | `"YYYYMMDDTHHmmssZ"` 格式 | 路径文件名中提取 |
| `sorted_paths` | `Array[String]` | size ≥ 0 | `recording_paths` 降序排列 |
| `display_paths` | `Array[String]` | 1 ≤ size ≤ `MAX_RECORDINGS_DISPLAYED` | 截断后的展示列表 |
| `MAX_RECORDINGS_DISPLAYED` | `int` | 3–10，默认 5 | Tuning Knob |

**D3 — 录音条目显示编号**

```
# N 为按录制顺序（时间顺序）的编号：最旧录音 = 录音 1，最新 = 录音 total
total_count = recording_paths.size()  # 截断前总条数

# 对 display_paths 中第 i 条（i=0 为最新）：
chronological_index(i) = total_count - i   # 最新=total_count, 最旧=1
display_label(i, path) = "录音 " + str(chronological_index(i)) + " · " + format_date(sort_key(path))
format_date("20260315T143022Z") → "2026-03-15"
```

| 符号 | 类型 | 范围 | 说明 |
|------|------|------|------|
| `total_count` | `int` | ≥ 1 | 截断前的录音总数（用于计算编号，确保 1=最旧） |
| `i` | `int` | 0 ≤ i < `display_paths.size()` | display_paths 中的展示索引（0=最新在上） |
| `chronological_index` | `int` | 1 ≤ value ≤ `total_count` | 按录制时间顺序的编号（1=第一次录音） |
| `display_label` | `String` | — | 展示给家长的条目文字 |

> 设计说明：编号按录制顺序（最旧=1）而非展示顺序，确保家长点开「录音 1」总是孩子第一次的声音。

## Edge Cases

**E1 — VoiceRecorder 不可用（被砍除或不可访问）**
条件：`is_instance_valid(VoiceRecorder) == false`（不直接访问私有 `_state` 字段；VoiceRecorder 缺失或未初始化时 `is_instance_valid` 返回 false 即可覆盖所有不可用场景）
行为：`_ready()` 跳过所有 VoiceRecorder 查询；5 张词汇卡的录音区域完全隐藏（不占布局空间）；金星星级正常显示；不报错、不显示占位文字。

**E2 — VoiceRecorder 可用但某词汇无录音**
条件：`get_recording_paths(word_id)` 返回 `[]`
行为：该词汇卡的播放区域完全隐藏；金星和日期区域正常显示；其他有录音的词汇不受影响。

**E3 — 录音文件路径存在但文件已被删除**
条件：`recording_paths` 非空，但 `path` 对应磁盘文件不存在
行为：`play_recording(path)` 触发 `playback_failed("file_not_found")`；对应录音条目灰化 + 不可点击；同词汇其他条目、其他词汇正常可用。

**E4 — gold_star_awarded 在地图关闭过程中触发**
条件：用户点 × 并执行 `queue_free()` 期间信号触发
行为：信号处理器首行 `if is_queued_for_deletion(): return`（`is_inside_tree()` 在 `queue_free()` 调用后、帧末真正释放前仍返回 true，无法正确守卫；应使用 `is_queued_for_deletion()`）；无崩溃，无 UI 更新尝试。

**E5 — 新档案（所有词汇 gold_star_count == 0）**
条件：档案首次进入地图，从未获得任何金星
行为：5 张词汇卡全部显示 FRESH 状态（空星）；录音区域隐藏（无录音）；不显示错误，地图有效可关闭。

**E6 — 所有词汇已完全掌握**
条件：5 个词 `is_word_learned == true`
行为：5 张卡全部显示 MASTERED 状态；若有录音则播放按钮正常显示；无特殊处理需求。

**E7 — Android 返回键在录音播放中触发**
条件：PLAYING 状态下用户按下系统返回键
行为：Core Rule 7 关闭流程：① `VoiceRecorder.stop_playback()` → ② 处理提示标志 → ③ `get_tree().paused = false` → ④ `queue_free()`；音频干净停止，状态机无残留。

**E8 — `parent_map_hint_dismissed` 字段在旧存档中不存在**
条件：从早期 schema 版本升级，profile section 不含此字段
行为：Core Rule 7 通过 `.get("parent_map_hint_dismissed", false)` 读取，默认 false；地图关闭时写入 true 并 flush；不破坏存档。

**E9 — 两条录音时间戳字符串相同（极低概率）**
条件：同一词汇的两条录音文件名时间戳完全一致
行为：`sort_key()` 排序结果未定义但稳定（GDScript sort 稳定）；两条均显示；播放各自独立；不崩溃。

**E10 — VocabStore 查询在 `_ready()` 中返回无效值**
条件：VocabStore 处于异常状态（不应发生，但防御性处理）
行为：对应词汇卡显示 0 星（FRESH）；`first_star_at` 留空；继续渲染其余词汇；不中断整体显示。

## Dependencies

| 系统 | 方向 | 说明 |
|------|------|------|
| **VocabStore**（AutoLoad） | ParentVocabMap → VocabStore | 调用 `get_gold_star_count`、`get_first_star_at`、`is_word_learned` × 5；订阅 `gold_star_awarded` |
| **VoiceRecorder**（AutoLoad，可选） | ParentVocabMap → VoiceRecorder | 调用 `get_recording_paths` × 5、`play_recording`、`stop_playback`；订阅 `playback_started/completed/failed`；`is_instance_valid` 守卫，缺失时静默降级 |
| **ProfileManager**（AutoLoad） | ParentVocabMap → ProfileManager | 读/写 `parent_map_hint_dismissed`；调用 `flush()` |
| **MainMenu / GameScene** | MainMenu → ParentVocabMap | 触发场景负责长按检测，实例化并 `add_child(ParentVocabMap)` |
| **NameInputScreen** | ParentVocabMap → NameInputScreen（单向文档任务） | OQ-1：NameInputScreen GDD 需补充「建档完成后展示长按入口提示」Interaction |
| **entities.yaml** | ParentVocabMap → 常量 | `VOCAB_WORD_IDS_CH1`（词汇列表）、`IS_LEARNED_THRESHOLD`（金星阈值；权威定义在 VocabStore GDD） |
| **SaveSystem** | 间接（经 ProfileManager） | ParentVocabMap 不直接调用 SaveSystem；flush 路由经 ProfileManager |

**反向依赖（其他系统依赖 ParentVocabMap）**：

- **MainMenu**：需要监听 `VocabStore.gold_star_awarded`，在 `parent_map_hint_dismissed == false` 时显示发现提示标记（逻辑在 MainMenu，不在 ParentVocabMap）
- **NameInputScreen**：需在建档完成后展示入口提示文字（OQ-1 待确认）

## Tuning Knobs

| 参数 | 默认值 | 安全范围 | 说明 |
|------|--------|---------|------|
| `LONG_PRESS_DURATION_SEC` | `5.0` | 3.0 – 8.0 | 触发长按进入的持续时间（秒）。低于 3 秒有误触风险；高于 8 秒家长体验过差。**注**：此常量由触发场景（MainMenu / GameScene）消费，建议迁移至 `entities.yaml` 作为跨场景共享常量，避免各触发场景各自硬编码 |
| `HINT_FADE_OUT_SEC` | `3.0` | 1.5 – 5.0 | NameInputScreen 提示文字淡出时长（秒）。**注**：控制 NameInputScreen 行为，OQ-1 完成后此调参项应迁移至 NameInputScreen GDD，此处为临时占位 |
| `MAX_RECORDINGS_DISPLAYED` | `5` | 3 – 10 | 每个词汇最多显示的录音条目数（含始终钉住的最旧一条；实际可滚动显示的最新录音为 `MAX_RECORDINGS_DISPLAYED - 1` 条；截断规则见 D2） |

> **不拥有的调参项**（引用，不定义）：
> - `IS_LEARNED_THRESHOLD`：权威定义在 entities.yaml（VocabStore GDD 拥有）
> - `MAX_RECORDING_SECONDS`：权威定义在 VoiceRecorder GDD

## Visual/Audio Requirements

### 视觉

**布局**：全屏竖版 CanvasLayer（360×800dp 基准）。顶部标题栏（档案名 + 「成长地图」，最小高度 **56dp**），右上角 × 按钮（最小 80dp）；标题栏 sticky，ParentVocabMap 实例化时初始 AccessKit 焦点落在 × 按钮。下方 5 张 `VocabEntryPanel` 垂直滚动列表，每卡左侧英文词 + 中文释义 + 星级可视化 + 首获日期，右侧录音播放区（有录音时显示，无录音时消失）。

**首获日期**：`first_star_at` 非 null 时，每张词汇卡在星级可视化下方显示「首次获星：YYYY-MM-DD」（格式同 D3 中 `format_date`）；`first_star_at == null`（从未获得金星）时此行隐藏，不占布局空间。

**金星视觉等级**（与 PostcardGenerator 保持一致）：
- `FRESH`（0 星）：空星轮廓，灰色，无光效
- `PROGRESSING`（1–2 星）：金星渐亮，微粒子光效
- `MASTERED`（3+ 星 / `is_word_learned=true`）：金星饱满发光，暖橙色辉光

**长按进度环**：半透明圆环环绕触屏点，随时间填充（5 秒完成）；松手时渐隐消失。

**录音条目**：每条「录音 N · YYYY-MM-DD」（N 按录制顺序编号，1=首次录音）+ 播放按钮（▶）；播放中条目脉冲动画；被新播放抢占后条目立即恢复 idle 静止状态；灰化条目透明度 0.4，无点击反馈。

### 音频

- 地图打开/关闭：轻柔音效（与主菜单风格一致）
- 播放按钮点击：轻触反馈音效
- 录音回放：使用 `AudioStreamPlayer`，无空间音效处理
- 长按进度环：无声（静默长按，不惊扰孩子）

## UI Requirements

### 触屏交互

- 所有可点击元素（播放按钮、× 按钮）最小点击区域 **80dp × 80dp**
- 长按检测仅响应**非交互背景区域**的触屏按下（Button、Panel 等控件上的触屏不启动长按计时器）
- 录音播放按钮：点击立即响应，无需双击确认
- × 按钮和 Android 返回键等效，均触发 Core Rule 7 关闭流程

### 无障碍

- 所有 VocabEntryPanel 标题（英文词 + 中文释义）可通过 AccessKit 屏幕阅读器访问
- 播放按钮提供 `tooltip_text`：「播放 [词汇] 录音 [序号] · [日期]」
- 金星状态通过文字 aria-label 补充（不仅依赖颜色）：「[词汇]：0 颗星 / 2 颗星 / 已掌握」

### 空状态处理

- 所有词汇均无金星时：5 张 FRESH 空星卡片正常显示；列表顶部附加一行副标题文字「孩子学到的词汇会在这里出现」，与卡片共存（不互斥）；说明文字仅在所有词汇 `gold_star_count == 0` 时显示
- 某词汇无录音时：播放区域完全隐藏（不显示「暂无录音」占位符）

### 滚动

- 5 张词汇卡若超出屏幕高度（低端小屏设备），支持垂直滚动（`ScrollContainer`）
- 顶部标题栏和 × 按钮 sticky（不随滚动移动）

## Acceptance Criteria

**AC-1（长按触发）**：在 MainMenu 非交互背景区域按住 5 秒，ParentVocabMap 全屏打开，SceneTree 暂停（游戏 UI 不响应点击）。

**AC-2（误触保护）**：在 MainMenu 按住任意可交互控件（`mouse_filter != MOUSE_FILTER_IGNORE`，如开始游戏按钮、图标等）超过 5 秒，ParentVocabMap 不打开。

**AC-3（金星显示）**：档案中 T-Rex 词汇 `gold_star_count == 2` 时，对应词汇卡显示 2 颗金星（PROGRESSING 状态），视觉与其他词汇区分。

**AC-4（实时更新）**：ParentVocabMap 开启期间，VocabStore 产生 `gold_star_awarded` 信号，对应词汇卡星级实时更新，无需关闭重开。

**AC-5（无录音空状态）**：VoiceRecorder 可用但词汇无录音时，该词汇卡不显示播放按钮，不显示占位符，布局无空缺。

**AC-6（录音回放）**：点击有效录音条目，`play_recording()` 返回 true，录音正常播放，播放按钮显示播放中状态；播放完成后恢复可点击。若 `play_recording()` 同步返回 false（点击时立即失败），按钮立即恢复 idle 状态，不进入 PLAYING。【注：录音回放音频质量需手动在目标设备验证；GUT 自动化仅验证按钮状态机。】

**AC-7（文件缺失降级）**：录音路径存在但文件已删除时，点击该条目不崩溃，条目灰化，其他录音条目仍可播放。

**AC-8（关闭恢复）**：点击 × 或按 Android 返回键，地图关闭，SceneTree 恢复运行，游戏 UI 恢复响应；进行中的录音回放停止。

**AC-9（VoiceRecorder 不可用）**：VoiceRecorder 被砍除或 DISABLED 时，ParentVocabMap 正常打开，5 张词汇卡金星正常显示，无录音相关 UI 元素，无错误弹窗。

**AC-10a（标志写入）**：首次打开地图并关闭后，`ProfileManager.get_section("profile").get("parent_map_hint_dismissed") == true`（GUT 可自动化）。

**AC-10b（徽章隐藏）**：`parent_map_hint_dismissed == true` 的档案打开 MainMenu，💡 提示标记不显示（属 MainMenu 测试范围，手动验证；与 AC-10a 拆分）。

**AC-11（发现提示——NameInputScreen）**【BLOCKED — 等待 OQ-1 完成后可验证】：首次建档完成后，NameInputScreen 显示「家长长按屏幕 5 秒可进入孩子成长地图」，3 秒后淡出。

## Open Questions

**OQ-1（parent_map_hint_dismissed 字段 + NameInputScreen 提示）**：
`parent_map_hint_dismissed` 是 ProfileManager `profile` section 的新字段，需确认：
① SaveSystem `_migrate_to_v2` 是否在初始化时预填此字段（默认 false）；
② NameInputScreen GDD 需补充「建档完成后展示长按入口提示文字」Interaction（跨文档更新任务）。
_暂 OPEN，实现前需协调 SaveSystem + NameInputScreen GDD。_

**OQ-2（`parent_map_hint_dismissed` 字段归属声明）**【BLOCKING — 实现前必须完成】：
`profile` section 现有字段由 ProfileManager + SaveSystem 共同定义。此新字段当前在 ProfileManager GDD schema 表（F-1）中**不存在**（已确认）。需在 ProfileManager GDD 中声明该字段、类型（`bool`，默认 `false`）及迁移路径；SaveSystem `_migrate_to_v2` 需预填此字段，防止旧存档读取异常。本 GDD 进入 APPROVED 状态前此项必须完成。

**OQ-3（VocabStore GDD `word_learned` 信号接收方列表）**：
VocabStore GDD 中 `word_learned` 信号的接收方列表含 ParentVocabMap（"标记已认识徽章"）。按本 GDD Core Rule 5 的设计，ParentVocabMap 通过 `gold_star_awarded` + 阈值推算 MASTERED 状态，**不订阅 `word_learned` 信号**。需在 VocabStore GDD 中将 ParentVocabMap 从该信号的接收方列表移除，避免文档矛盾。
