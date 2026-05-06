# ProfileManager

> **Status**: Needs Revision (fixes applied 2026-05-06 — awaiting re-review)
> **Author**: Zhang Shaocong + agents
> **Last Updated**: 2026-05-06
> **Implements Pillar**: P3 (声音是成长日记), P4 (家长是骄傲见证者)
> **CD-GDD-ALIGN**: APPROVED 2026-05-06 — 3 concerns resolved: NAME_MAX_LENGTH=20 (game-concept.md updated), active_profile_cleared reason param added, MAX_SAVE_PROFILES=3 (MVP aligned)

## Overview

ProfileManager 是游戏的档案内存中继层——它位于底层 I/O（SaveSystem）与所有业务逻辑系统之间，持有当前活跃档案的 Dictionary 副本，并暴露档案全生命周期的管理 API。任何系统（VocabStore、StoryManager、VoiceRecorder 等）若需读写档案字段，均通过 ProfileManager 操作内存副本，由 ProfileManager 协调何时调用 SaveSystem 的 `flush_profile()` 将变更写盘。ProfileManager 负责：档案槽位管理（最多 `MAX_SAVE_PROFILES` 个槽位）、档案创建与删除的完整流程、首次启动判断（触发 HatchScene 的条件持有者）、`times_played` 计数器的写权限、以及档案切换时通过 `profile_switch_requested` 信号通知所有需要清理进行中状态的订阅系统。ProfileManager 不解读 `vocab_progress`、`story_progress` 等字段的含义——对它而言，这些是透明载体，只有 VocabStore 和 StoryManager 才赋予其语义。

## Player Fantasy

ProfileManager 对孩子不可见——它许诺的三件事，只有在事情「本来应该发生」时才能被感知到它做对了。**第一，T-Rex 认识的是你，不是随便哪个拿手机的孩子**：每次打开 App，那只恐龙记得你选过哪些单词，记得你的名字，记得你们上次走到了哪里。孩子不会说「ProfileManager 加载了我的档案」，只会说「T-Rex 看见我了」。这种感知只有在档案数据准确连续时才成立——ProfileManager 是让这句话为真的人，从不出声。**第二，你的第一句话还在这里**：孩子说出「T-Rex!」的那一刻是转瞬即逝的，六个月后家长打开词汇地图，点开金星旁的播放按钮——传出的是四个月前那个偏高、用力、不太确定的声音。ProfileManager 一直保管着正确的档案，从来没有混淆过谁说了什么。那个回放时刻是游戏给家长的礼物，ProfileManager 是让礼物能被拆开的人。**第三，Xiao 的 T-Rex 还没有听过任何英文单词**：在有两个孩子的家里，Mei 的金星是 Mei 的，Xiao 的蛋还没破壳，等待 Xiao 做它第一个老师。档案切换时 T-Rex 会播放「认出新主人」动画——孩子感知到的是「现在轮到我了，T-Rex 在等我」，不知道的是这背后有一次干净的内存切换和一次 SaveSystem load。没有 ProfileManager，这三件事都不成立：T-Rex 会把每个孩子的进度混在一起，声音没有对应的所有者，那个六个月后的回放时刻永远不会发生。

## Detailed Design

### Core Rules

1. **单一内存权威**：ProfileManager 在内存中只持有一份活跃档案 Dictionary（`_active_data`），是该档案的唯一内存镜像。任何系统不得另存档案副本——只能持有 `_active_data` 的 section 引用，并在 `profile_switch_requested` 信号触发时立即清除引用。

2. **`get_active_data() -> Dictionary` 返回引用**：返回 `_active_data` 本身，不调用 `duplicate()`。理由：GDScript 单线程无竞争条件；副本会引入漂移问题（VocabStore 和 StoryManager 各持旧副本，互不可见对方的改动）。调用方不得在成员变量中缓存此引用跨越 profile 切换边界。

3. **Section 级访问接口**：`get_section(key: String) -> Dictionary` 返回对 `_active_data[key]` 的直接引用。业务系统只访问自己归属的 section：VocabStore → `"vocab_progress"`，StoryManager → `"story_progress"`。ProfileManager 自身负责 `"profile"` 字段。业务系统不得通过此接口写入非归属 section。

4. **flush 入口唯一性**：`ProfileManager.flush() -> bool` 是唯一合法的持久化调用路径，内部调用 `SaveSystem.flush_profile(_active_index, _active_data)`。VocabStore、VoiceRecorder、InterruptHandler 均调用 `ProfileManager.flush()`，不直接调用 SaveSystem。在 `SWITCHING` 状态下，`flush()` 静默返回 `false`。

5. **`"profile"` section 写权限**：`_active_data["profile"]` 只有 ProfileManager 自身可写。外部系统不得修改 `profile.name`、`profile.avatar_id`、`profile.times_played`。ProfileManager 通过具名 setter 暴露修改接口：`set_profile_name(n: String)`、`set_avatar_id(id: String)`。

6. **`begin_session()` — times_played 写入点**：由游戏根场景（GameRoot）在档案激活完成后、进入主游戏前显式调用一次。ProfileManager 执行 `_active_data["profile"]["times_played"] += 1` 并立即调用 `flush()`（失败仅 push_error，不阻断流程）。在 `NO_ACTIVE_PROFILE` 状态下调用：push_warning，无操作。

7. **`is_first_launch() -> bool`（首次启动门控）**：返回 `_active_data.get("profile", {}).get("times_played", 0) == 0 and _active_data.get("profile", {}).get("name", "") == ""`。ProfileManager 只暴露查询；跳转至 HatchScene 是 GameRoot 的职责，不在 ProfileManager 内部触发。

8. **`switch_to_profile(new_index: int)` — 七步切换序列**：
   a. 验证 new_index ∈ [0, MAX_SAVE_PROFILES)，否则 push_error 并返回
   b. 验证 `SaveSystem.profile_exists(new_index)`，否则 push_error 并返回
   c. 将状态置为 `SWITCHING`
   d. `emit("profile_switch_requested", new_index)` — **同步信号**；所有订阅者在此完成清理：保存中间状态至 ProfileManager、清除 section 引用、停止进行中操作。**订阅者信号处理器中严禁使用 `await`**（await 立即将控制权还给调用方，后续清理逻辑不再在 emit 返回前执行）
   e. `flush()` — 将旧档案状态写盘（失败仅 push_error）
   f. `_active_data = SaveSystem.load_profile(new_index).duplicate(true)`；`_active_index = new_index`
   g. 将状态置为 `ACTIVE`；`emit("profile_switched", new_index)`

9. **`delete_profile(index: int) -> bool` — 五步删除序列（删除活跃档案时）**：当 `index == _active_index`：
   a. `emit("profile_switch_requested", -1)` — 订阅者同步清理（-1 = 无目标档案）
   b. 将状态置为 `NO_ACTIVE_PROFILE`；`_active_data = {}`；`_active_index = -1`（先清内存，不 flush——删除前无需写盘）
   c. `SaveSystem.delete_profile(index)` — 失败时 push_error，返回 `false`
   d. `emit("active_profile_cleared", "user_deleted")` — UI 跳转档案选择界面
   e. 返回 `true`
   删除非活跃档案：直接 `SaveSystem.delete_profile(index)`，无信号，无内存操作。

10. **`create_profile(index: int, name: String, avatar_id: String) -> bool`**：
    若 `SaveSystem.profile_exists(index)` 为 true → push_error，返回 `false`（不覆盖已有档案）。否则：构建 v2 默认结构（补全所有 5 个词汇键默认值），设 `profile.name = name`、`profile.avatar_id = avatar_id`，调用 `SaveSystem.flush_profile(index, new_data)`，返回 flush 结果。**创建后不自动激活**——调用方须显式调用 `switch_to_profile(index)` 加载。

11. **`NO_ACTIVE_PROFILE` 状态防护**：当 `_active_index == -1` 时：`get_active_data()` 返回 `{}`；`get_section(key)` 返回 `{}`；`flush()` 返回 `false`；`begin_session()` push_warning 无操作。调用方在执行业务操作前应先检查 `has_active_profile() -> bool`（等价于 `_active_index != -1`）。

12. **`profile_exists()` 委托，不缓存**：`ProfileManager.profile_exists(index: int) -> bool` 直接委托给 `SaveSystem.profile_exists(index)`，ProfileManager 不维护槽位占用的本地缓存。

### States and Transitions

| 状态 | 含义 | `get_active_data()` | `flush()` | `begin_session()` |
|------|------|--------------------|-----------|--------------------|
| `UNINITIALIZED` | _ready() 尚未执行 | `{}` | `false` | 无操作 |
| `NO_ACTIVE_PROFILE` | 已初始化，`_active_index = -1` | `{}` | `false` | push_warning |
| `ACTIVE` | 档案已加载，游戏可正常运行 | 活跃档案引用 | 执行写盘 | 递增 times_played |
| `SWITCHING` | 切换序列进行中 | 旧档案引用（只读期） | 静默 false | push_warning |

**合法转换：**

| 从 | 到 | 触发 |
|----|----|------|
| UNINITIALIZED | NO_ACTIVE_PROFILE | _ready() 完成 |
| NO_ACTIVE_PROFILE | ACTIVE | switch_to_profile() 成功 |
| ACTIVE | SWITCHING | switch_to_profile() 或 delete_profile(active_index) 调用 |
| SWITCHING | ACTIVE | 切换序列第 g 步完成（加载新档案） |
| SWITCHING | NO_ACTIVE_PROFILE | delete_profile(active) 第 b 步完成 |

### Interactions with Other Systems

| 调用方 | API | 时机 |
|--------|-----|------|
| ProfileManager → SaveSystem | `load_profile(index)` | switch_to_profile 第 f 步 |
| ProfileManager → SaveSystem | `flush_profile(index, data)` | flush() 内部；create_profile |
| ProfileManager → SaveSystem | `profile_exists(index)` | create_profile 前；switch_to_profile 前 |
| ProfileManager → SaveSystem | `delete_profile(index)` | delete_profile |
| GameRoot → ProfileManager | `switch_to_profile(index)` | 档案选择确认 |
| GameRoot → ProfileManager | `begin_session()` | GameScene._ready() |
| GameRoot → ProfileManager | `is_first_launch()` | 决定 HatchScene 还是 GameScene |
| MainMenu → ProfileManager | `profile_exists(index)` | 渲染槽位卡片 |
| MainMenu → ProfileManager | `get_profile_header(index)` | 显示档案名/头像 |
| MainMenu → ProfileManager | `create_profile(index, name, avatar_id)` | 新建档案流程 |
| MainMenu → ProfileManager | `delete_profile(index)` | 删除档案确认 |
| VocabStore → ProfileManager | `get_section("vocab_progress")` | 读取词汇状态 |
| VocabStore → ProfileManager | `flush()` | 词汇批量更新后 |
| StoryManager → ProfileManager | `get_section("story_progress")` | 读取故事进度 |
| StoryManager → ProfileManager | `flush()` | 章节进度推进后 |
| VoiceRecorder → ProfileManager | `get_section("vocab_progress")` | 更新 recording_path |
| VoiceRecorder → ProfileManager | `flush()` | 录音完成 |
| InterruptHandler → ProfileManager | `flush()` | App 进入后台紧急写盘 |
| (signal) → StoryManager | `profile_switch_requested` | 同步保存 story 进度、清除引用 |
| (signal) → VoiceRecorder | `profile_switch_requested` | 同步停止进行中录音、清除引用 |
| (signal) → GameRoot | `active_profile_cleared` | 跳转档案选择界面 |

**SaveSystem GDD 修正备注**：SaveSystem 的 Interactions 表中 VocabStore 和 VoiceRecorder 直接调用 `SaveSystem.flush_profile()` — 这是 ProfileManager 尚未设计时的占位。按 Core Rules 4，两者应改为调用 `ProfileManager.flush()`。此修正在 Dependencies 节说明。

## Formulas

ProfileManager 不包含游戏数值公式。本节定义 **schema 契约 + 算法谓词**——ProfileManager 作为内存中继层的所有可测试承诺。

---

### F-1 — `profile` Section 数据契约

ProfileManager 是 `_active_data["profile"]` 字段的唯一写权限持有者。以下为该 section 所有字段的合法性约束。

| 字段 | 类型 | 有效范围 | 空值语义 |
|------|------|---------|---------|
| `name` | String | 0–20 字符 | `""` = 未命名；`is_first_launch()` 的必要条件之一 |
| `avatar_id` | String | 注册的 avatar_id 值，或 `""` | `""` = 头像未选择（仅 `create_profile()` 调用前合法） |
| `times_played` | int | 0 ≤ t < ∞ | 0 = `begin_session()` 从未被调用；`is_first_launch()` 的必要条件之一 |

**设计说明：**
- `name` 数据层最大长度为 **20 字符**；UI 层 NameInputScreen 同样限制 20 字符（两层保持一致）。⚠️ 这覆盖了游戏概念文档原定的「最大 6 字」，设计理由：数据层容量应大于或等于 UI 层限制，统一为 20 字符可避免迁移期数据层/UI 层不同步问题。
- `avatar_id` 的有效值集合由美术资产注册决定；当前 MVP 默认值为 `"trex_default"`，不在本 GDD 中枚举。

---

### F-2 — `times_played` 递增算法

`begin_session()` 是 `times_played` 的唯一写入点。

```
times_played_formula: t_new = t_old + 1
```

**Variables:**

| 变量 | 符号 | 类型 | 范围 | 描述 |
|------|------|------|------|------|
| 旧值 | `t_old` | int | 0 ≤ t_old | `begin_session()` 调用前 `_active_data["profile"]["times_played"]` 的当前值 |
| 新值 | `t_new` | int | t_old + 1 | 写回 `_active_data` 并立即 `flush()` 的值 |

**前置条件：** 当前状态为 `ACTIVE`；由 GameRoot 在档案激活完成后、进入 GameScene 前调用一次/场景。

**输出范围：** 0 → ∞（无上限）

**Example:** `t_old = 3` → `begin_session()` → `t_new = 4`，立即 `flush()`。

---

### F-3 — `is_first_launch()` 二元谓词

```
is_first_launch = (times_played == 0) AND (name == "")
```

**Variables:**

| 变量 | 符号 | 类型 | 来源 |
|------|------|------|------|
| 游玩次数 | `times_played` | int | `_active_data["profile"]["times_played"]` |
| 档案名 | `name` | String | `_active_data["profile"]["name"]` |

**输出范围：** bool

**示例：**
- `times_played=0, name=""` → `true`（首次启动，GameRoot 跳转 HatchScene）
- `times_played=0, name="豆豆"` → `false`（调试档案或重置后，不触发 HatchScene）
- `times_played=5, name="豆豆"` → `false`（常规启动）

**注意：** 仅 GameRoot 使用此谓词决定场景跳转；ProfileManager 只暴露查询，不内部触发任何场景切换。

---

### F-4 — `profile_index_in_range()` 边界谓词

```
profile_index_in_range(i) = (i ∈ ℤ) AND (0 ≤ i < MAX_SAVE_PROFILES)
```

**Variables:**

| 变量 | 符号 | 类型 | 范围 | 描述 |
|------|------|------|------|------|
| 待验证索引 | `i` | int | 任意整数 | 外部调用方传入的槽位编号 |
| 最大档案数 | `MAX_SAVE_PROFILES` | int (const) | 3（MVP）| 注册常量（entities.yaml），由 SaveSystem 声明 |

**输出范围：** bool。当 `MAX_SAVE_PROFILES = 3` 时，合法集合 = `{0, 1, 2}`。

**示例：** `i=0 → true`；`i=1 → true`；`i=2 → true`；`i=3 → false`；`i=-1 → false`

**注意：** `_active_index = -1` 是 ProfileManager 内部的 `NO_ACTIVE_PROFILE` 标记（合法内部状态），但外部调用方传入 -1 是非法输入，此谓词返回 `false`。

---

### F-5 — `get_profile_header(index: int) -> Dictionary` 接口契约

用于 MainMenu 渲染档案槽位卡片，避免直接暴露完整档案数据。

**加载策略：**
- 当 `index == _active_index`：直接读取 `_active_data["profile"]`（内存优先，不触发磁盘 I/O）
- 当 `index ≠ _active_index`：调用 `SaveSystem.load_profile(index)` 完整加载，提取 `"profile"` section，结果不缓存

**返回结构（固定，永不返回裸 `{}`）：**

| 字段 | 类型 | 正常情况 | 错误/不存在情况 |
|------|------|---------|--------------|
| `name` | String | 档案名 | `""` |
| `avatar_id` | String | 头像 ID | `"trex_default"` |
| `times_played` | int | 游玩次数 | `0` |
| `is_valid` | bool | `true` | `false` |

**`is_valid = false` 触发条件（任一即可）：**
1. `profile_index_in_range(index)` 返回 `false`
2. `SaveSystem.profile_exists(index)` 返回 `false`
3. `SaveSystem.load_profile(index)` 返回 `{}`（文件损坏等）
4. 返回的 dict 中 `"profile"` 键不存在

**不暴露 `SaveSystem.LoadError` 的理由：** MainMenu 渲染只需「此槽位能否显示名字和头像」，不需要区分底层错误类型；`LoadError` 枚举是 I/O 层内部实现，由 ProfileManager 封装，不泄漏至 UI 层。

**示例：**
- 活跃档案 `index=0`，名字「豆豆」→ `{name:"豆豆", avatar_id:"trex_default", times_played:5, is_valid:true}`
- 空槽位 `index=1` → `{name:"", avatar_id:"trex_default", times_played:0, is_valid:false}`

## Edge Cases

| # | 边界情况 | ProfileManager 行为 | 调用方职责 |
|---|---------|---------------------|-----------|
| **EC-1** | **`switch_to_profile()` 第 f 步 — `SaveSystem.load_profile()` 返回 `{}`**（文件损坏、磁盘错误等）。此时 `profile_switch_requested` 已发出（第 d 步），旧档案已 flush（第 e 步）或 flush 失败。 | push_error；`_active_data = {}`，`_active_index = -1`；状态 → `NO_ACTIVE_PROFILE`；补发 `active_profile_cleared("load_failed")` 信号（触发 UI 回到档案选择界面）。**不进入 `ACTIVE` 状态。** | GameRoot 应订阅 `active_profile_cleared`，检查 `reason` 参数以区分用户主动删除与意外加载失败，并展示对应提示。 |
| **EC-2** | **`switch_to_profile(same_index)` — 传入与当前 `_active_index` 相同的 index，状态为 `ACTIVE`。** | 在步骤 a/b 验证通过后、步骤 c 之前增加守卫：`if new_index == _active_index and _state == ACTIVE`：push_warning，直接 return（不执行切换序列）。档案已在内存中，无需重加载。 | 不应依赖 same-index 调用来强制刷新内存；如需强制重载，应有独立 API（本 MVP 不提供）。 |
| **EC-3** | **`get_section("非归属 section")` — 调用方跨越归属边界访问（如 VocabStore 调用 `get_section("story_progress")`）。** | ProfileManager **不做**运行时访问控制；`get_section(key)` 返回 `_active_data[key]` 的引用，不报错。理由：GDScript 单线程无需内核级权限，运行时 caller 身份检测成本不可接受。 | 调用方合同违规；由 code review 和 GUT 测试覆盖，不由 ProfileManager 运行时拦截。编写测试时应覆盖跨节写入场景以捕获违规。 |
| **EC-4** | **`flush()` 失败（磁盘满、文件锁等）——`_active_data` 是否保持？** | `_active_data` 内存副本**保持不变**（`flush` 是只读操作，对内存无副作用）；`flush()` 返回 `false`；ProfileManager 不自动重试，不进入降级状态。 | InterruptHandler 是最重要的调用方——App 进后台时若 `flush()` 返回 false，应记录本地日志或提示用户；下次冷启动时数据可能丢失。 |
| **EC-5** | **`is_first_launch()` 在 `NO_ACTIVE_PROFILE` 或 `UNINITIALIZED` 状态下调用 — 假阳性风险。** | 函数内部增加状态守卫：`if _state != ACTIVE: return false`。理由：`is_first_launch()` 只对已加载的档案有意义；`NO_ACTIVE_PROFILE` 时 `_active_data = {}`，两个 `.get()` 均取默认值，会错误返回 `true`。 | GameRoot 应在 `switch_to_profile()` 完成（`profile_switched` 信号触发）后再调用 `is_first_launch()`；ProfileManager 内部守卫防止所有调用方踩坑。 |
| **EC-6** | **`profile_switch_requested` 订阅者在信号处理器中使用 `await`（违反 Core Rule 8）。** | ProfileManager **无法**在运行时检测此违规——GDScript 没有 API 可检查 Callable 是否含 `await`；`emit()` 遇到 await 点时控制权提前返回，ProfileManager 继续执行第 e/f 步，此时 `_active_data` 已被替换为新档案数据，而订阅者的 await 之后代码尚未执行。 | 违规后果：订阅者 await 之后的清理代码将对新档案数据执行，可能导致新档案引用被错误清除或旧档案中间状态未写盘。GUT 测试应覆盖此场景：mock 含 await 的订阅者，验证 e/f 步执行时序。 |
| **EC-7** | **`switch_to_profile()` 在 `SWITCHING` 状态下再次被调用**（如某订阅者在 `profile_switch_requested` 处理器中非法再次触发切换）。 | 在步骤 a/b 之前增加状态守卫：`if _state == SWITCHING: push_error; return`。理由：切换序列的中间状态不幂等，嵌套执行将产生递归信号，最终以不确定档案作为活跃档案。 | 订阅者不得在 `profile_switch_requested` 处理器中调用 `switch_to_profile()`——调用方合同。 |
| **EC-8** | **`delete_profile(非活跃档案)` — index 越界或 profile 不存在时缺少验证。** | 删除非活跃档案时，同样先执行 `profile_index_in_range(index)` 验证和 `profile_exists(index)` 验证：越界 → push_error，返回 `false`；不存在 → SaveSystem.delete_profile 幂等返回 `true`（SaveSystem GDD EC E8 保证）。不将边界验证职责隐式下推给 SaveSystem。 | 无额外调用方职责。 |

## Dependencies

### 上游依赖（ProfileManager 依赖的系统）

| 系统 | API | 使用时机 |
|------|-----|---------|
| **SaveSystem** | `profile_exists(index: int) -> bool` | switch_to_profile 步骤 b；create_profile；EC-8 非活跃档案删除前验证 |
| **SaveSystem** | `load_profile(index: int) -> Dictionary` | switch_to_profile 步骤 f；get_profile_header（非活跃档案） |
| **SaveSystem** | `flush_profile(index: int, data: Dictionary) -> bool` | flush() 内部；create_profile |
| **SaveSystem** | `delete_profile(index: int) -> bool` | delete_profile |

ProfileManager 不直接使用 Godot 引擎的任何文件 I/O API——所有磁盘访问经由 SaveSystem 封装。

### 下游依赖（依赖 ProfileManager 的系统）

| 系统 | 调用的 API | 归属 section | 依赖性质 |
|------|-----------|------------|---------|
| **GameRoot** | `switch_to_profile(index)`, `begin_session()`, `is_first_launch()` | — | 硬依赖（档案激活和首次启动判断） |
| **GameRoot** | 订阅 `profile_switched`，订阅 `active_profile_cleared` | — | 信号订阅（导航控制） |
| **MainMenu** | `profile_exists(index)`, `get_profile_header(index)`, `create_profile()`, `delete_profile()` | — | 硬依赖（档案选择 UI 渲染） |
| **NameInputScreen** | `create_profile(index, name, avatar_id)` | — | 硬依赖（新档案创建） |
| **VocabStore** | `get_section("vocab_progress")`, `flush()` | `vocab_progress` | 硬依赖（词汇读写全量路径） |
| **StoryManager** | `get_section("story_progress")`, `flush()` | `story_progress` | 硬依赖（故事进度读写） |
| **VoiceRecorder** | `get_section("vocab_progress")`, `flush()` | `vocab_progress` | 硬依赖（录音路径写入）；字段分工：VocabStore 写 `is_learned`/`gold_star_count`/`first_star_at`；VoiceRecorder 仅写 `recording_path`；两者字段无交叠 |
| **InterruptHandler** | `flush()` | — | 软依赖（App 进后台紧急写盘） |
| **PostcardGenerator** | `get_active_data()["profile"]["name"]` | `profile` | 软依赖（明信片个性化） |
| **HatchScene** | 读 `times_played`（间接，由 GameRoot 调 `is_first_launch()` 代为判断） | — | 软依赖（孵化动画条件） |

### 信号接口

| 信号名 | 参数 | 触发时机 | 订阅方 |
|--------|------|---------|--------|
| `profile_switch_requested(new_index: int)` | new_index: 目标档案 index（-1 = 正在删除活跃档案，无目标） | switch_to_profile 步骤 d；delete_profile(active) 步骤 a | StoryManager、VoiceRecorder（同步清理进行中状态）、VocabStore（同步清除 `_vocab_data` 和 `_session_counters` 引用） |
| `profile_switched(new_index: int)` | new_index: 已加载的新档案 index | switch_to_profile 步骤 g | GameRoot（确认切换完成，可进入游戏）、VocabStore（重新获取 `_vocab_data` 引用） |
| `active_profile_cleared(reason: String)` | reason: `"user_deleted"` — 主动删除；`"load_failed"` — 加载失败降级 | delete_profile(active) 步骤 d；EC-1 加载失败降级 | GameRoot（跳转档案选择界面；可据 reason 显示不同提示） |

### SaveSystem GDD 修正声明

~~SaveSystem GDD 的 Interactions 表（§ Interactions with Other Systems）中，VocabStore 和 VoiceRecorder 被列为直接调用 `SaveSystem.flush_profile()` 的调用方。按本 GDD Core Rule 4，这是 ProfileManager 尚未设计时的临时占位——**正确路径是 VocabStore 和 VoiceRecorder 调用 `ProfileManager.flush()`，由 ProfileManager 内部调用 `SaveSystem.flush_profile()`**。SaveSystem GDD 的 Interactions 表需在 ProfileManager GDD 批准后做一次勘误更新（更新三行调用方：VocabStore、VoiceRecorder、InterruptHandler）。~~

**✅ 已完成 2026-05-06**：SaveSystem GDD Interactions 表中 VocabStore、VoiceRecorder、InterruptHandler 三行均已更新为 `ProfileManager.flush()` 路由，含删除线标注（save-system.md 第 75–77 行）。

## Tuning Knobs

ProfileManager 的可调旋钮极少——它是规则执行层，而非数值层。

| 旋钮名 | 当前值 | 安全范围 | 影响 | 来源 |
|--------|--------|---------|------|------|
| `MAX_SAVE_PROFILES` | 3（MVP）→ 5（Vertical Slice，待评估） | 1–5 | 最大档案槽位数；超出后 `create_profile()` 拒绝新建；MainMenu 显示的最大卡片数 | SaveSystem GDD（注册常量），ProfileManager 执行该限制 |
| `NAME_MAX_LENGTH` | 20 字符 | 6–50 | `set_profile_name()` 的字符数上限（数据层约束）；UI 层 NameInputScreen 同样使用此值——两层保持一致 | ProfileManager GDD（F-1）；NameInputScreen 引用此常量，不硬编码 |

`MAX_SAVE_PROFILES` 的权威定义在 SaveSystem GDD（entities.yaml 注册常量）；ProfileManager 只执行这个限制，不拥有它。`NAME_MAX_LENGTH` 是 ProfileManager 唯一独立拥有的常量。

## Visual/Audio Requirements

N/A — ProfileManager 是纯后端系统（Core/Persistence 层），无视觉或音频输出。需要向用户展示的错误信息（「存储空间不足」、「请更新 App」等）由调用方（GameRoot、MainMenu、InterruptHandler）负责渲染。

## UI Requirements

ProfileManager 不直接驱动任何 UI 节点。所有 UI 响应均通过信号触发：

- `active_profile_cleared(reason: String)` → GameRoot 跳转至档案选择界面；reason 区分 `"user_deleted"`（用户主动删除）与 `"load_failed"`（加载失败降级），可据此显示不同提示（UI 实现属于 MainMenu GDD）
- `profile_switched(new_index)` → GameRoot 确认切换完成，可进入游戏（UI 实现属于 GameRoot 职责）

UI 要求的详细规范见 MainMenu GDD 和 NameInputScreen GDD。

## Acceptance Criteria

以下所有条目均为可测试的 Pass/Fail 标准，用 GUT 单元测试验证（SaveSystem 使用 Mock 对象替代，不依赖完整游戏构建）。测试文件位置：`tests/unit/profile_manager/test_profile_manager.gd`

### 状态机转换

| # | 测试场景 | 期望结果 | 测试类型 |
|---|---------|---------|---------|
| AC-1 | `_ready()` 执行完毕 | `_state == NO_ACTIVE_PROFILE`；`_active_index == -1`；`_active_data == {}` | Unit |
| AC-2 | NO_ACTIVE_PROFILE 状态下调用 `switch_to_profile(0)`，MockSaveSystem.load_profile(0) 返回有效档案 | `_state == ACTIVE`；`_active_index == 0`；`profile_switched(0)` 信号发出一次 | Unit |
| AC-3 | ACTIVE 状态下调用 `switch_to_profile(1)` 时，在 `profile_switch_requested` 信号处理器内检查状态 | 信号处理器执行时 `_state == SWITCHING`（步骤 c 在步骤 d 之前执行） | Unit |

### `switch_to_profile()` 七步序列（Core Rule 8）

| # | 测试场景 | 期望结果 | 测试类型 |
|---|---------|---------|---------|
| AC-4 | ACTIVE 状态下调用 `switch_to_profile(3)`（越界，MAX_SAVE_PROFILES=3） | `push_error` 被调用；`_state` 保持 `ACTIVE`；`profile_switch_requested` 信号**未**发出；MockSaveSystem 未被调用 | Unit |
| AC-5 | ACTIVE 状态下调用 `switch_to_profile(1)`，MockSaveSystem.profile_exists(1) 返回 false | `push_error` 被调用；`_state` 保持 `ACTIVE`；`profile_switch_requested` 信号**未**发出 | Unit |
| AC-6 | ACTIVE 状态下切换至 index=1，MockSaveSystem 记录调用顺序 | MockSaveSystem 调用顺序：`flush_profile(0,...)` **先于** `load_profile(1)` | Unit |
| AC-7 | ACTIVE 状态下切换至 index=1，信号发出顺序验证 | 信号顺序：`profile_switch_requested(1)` → `profile_switched(1)`，各发出恰好一次 | Unit |

### 边界情况

| # | 测试场景（边界情况编号） | 期望结果 | 测试类型 |
|---|---------|---------|---------|
| AC-8 | **EC-1**：ACTIVE(_active_index=0) 下调用 `switch_to_profile(1)`，MockSaveSystem.load_profile(1) 返回 `{}` | `push_error`；`_state == NO_ACTIVE_PROFILE`；`_active_index == -1`；`active_profile_cleared("load_failed")` 发出；`profile_switched` **未**发出 | Unit |
| AC-9 | **EC-2**：ACTIVE(_active_index=0) 下调用 `switch_to_profile(0)` | `push_warning`；`_state` 保持 `ACTIVE`；`profile_switch_requested` **未**发出；MockSaveSystem.load_profile **未**调用 | Unit |
| AC-10 | **EC-7**：SWITCHING 状态下调用 `switch_to_profile(1)` | `push_error`；函数立即返回；切换序列**未**启动；`_state` 保持 `SWITCHING` | Unit |

### `begin_session()`（Core Rule 6，F-2）

| # | 测试场景 | 期望结果 | 测试类型 |
|---|---------|---------|---------|
| AC-11 | ACTIVE 状态，`times_played == 3`，调用 `begin_session()` | `_active_data["profile"]["times_played"] == 4`；MockSaveSystem.flush_profile 被调用一次，参数含 times_played=4 | Unit |
| AC-12 | ACTIVE 状态，参数化 t_old ∈ {0, 1, 100}，调用 `begin_session()` | `times_played == t_old + 1`（F-2 公式验证） | Unit |
| AC-13 | NO_ACTIVE_PROFILE 状态下调用 `begin_session()` | `push_warning`；MockSaveSystem.flush_profile **未**调用；`_active_data` 不变 | Unit |

### `is_first_launch()`（Core Rule 7，F-3，EC-5）

| # | 测试场景 | 期望结果 | 测试类型 |
|---|---------|---------|---------|
| AC-14 | ACTIVE 状态，`times_played=0`，`name=""`，调用 `is_first_launch()` | 返回 `true` | Unit |
| AC-15 | ACTIVE 状态，`times_played=0`，`name="豆豆"`，调用 `is_first_launch()` | 返回 `false` | Unit |
| AC-16 | ACTIVE 状态，`times_played=5`，`name=""`，调用 `is_first_launch()` | 返回 `false` | Unit |
| AC-17 | **EC-5**：NO_ACTIVE_PROFILE 状态（`_active_data={}`），调用 `is_first_launch()` | 返回 `false`（内部状态守卫，不因 `.get()` 默认值产生假阳性） | Unit |

### `create_profile()`（Core Rule 10）

| # | 测试场景 | 期望结果 | 测试类型 |
|---|---------|---------|---------|
| AC-18 | MockSaveSystem.profile_exists(1) 返回 true，调用 `create_profile(1, "豆豆", "trex_default")` | 返回 `false`；`push_error`；MockSaveSystem.flush_profile **未**调用 | Unit |
| AC-19 | MockSaveSystem.profile_exists(0) 返回 false，调用 `create_profile(0, "小明", "trex_default")` | 返回 `true`；flush_profile 调用一次；传入 data 含 `profile.name="小明"`、`times_played=0`、所有 5 个词汇键默认值 | Unit |
| AC-20 | `create_profile(0, ...)` 成功，初始 `_state == NO_ACTIVE_PROFILE` | `_state` 保持 `NO_ACTIVE_PROFILE`；`_active_index` 保持 `-1`；`profile_switched` **未**发出 | Unit |

### `delete_profile()`（Core Rule 9，EC-8）

| # | 测试场景 | 期望结果 | 测试类型 |
|---|---------|---------|---------|
| AC-21 | ACTIVE(_active_index=0) 下调用 `delete_profile(0)` | 信号顺序：`profile_switch_requested(-1)` 先于内存清除；`_state == NO_ACTIVE_PROFILE`；`_active_data == {}`；`_active_index == -1`；MockSaveSystem.delete_profile(0) 调用；`active_profile_cleared("user_deleted")` 发出；返回 `true` | Unit |
| AC-22 | 删除活跃档案（index=0）期间 flush 调用验证 | MockSaveSystem.flush_profile **未**调用（删除前无需写盘） | Unit |
| AC-23 | ACTIVE(_active_index=0) 下调用 `delete_profile(1)`，MockSaveSystem.profile_exists(1) 返回 true | MockSaveSystem.delete_profile(1) 调用；`_active_data` 不变；`_active_index==0`；`profile_switch_requested` **未**发出 | Unit |
| AC-24 | **EC-8**：ACTIVE 状态下调用 `delete_profile(5)`（越界，MAX_SAVE_PROFILES=3） | 返回 `false`；`push_error`；MockSaveSystem.delete_profile **未**调用 | Unit |
| AC-25 | **EC-8**：`_active_index=0`，MockSaveSystem.profile_exists(1) 返回 false，调用 `delete_profile(1)` | MockSaveSystem.delete_profile(1) 仍调用（幂等委托）；返回 `true` | Unit |

### `flush()`（Core Rule 4，EC-4）

| # | 测试场景 | 期望结果 | 测试类型 |
|---|---------|---------|---------|
| AC-26 | ACTIVE(_active_index=0) 下调用 `flush()`，MockSaveSystem.flush_profile 返回 true | MockSaveSystem.flush_profile 调用一次，参数为 `(0, _active_data)`；返回 `true` | Unit |
| AC-27 | SWITCHING 状态下调用 `flush()` | 返回 `false`；MockSaveSystem.flush_profile **未**调用（静默，不发出 error/warning） | Unit |
| AC-28 | NO_ACTIVE_PROFILE 状态下调用 `flush()` | 返回 `false`；MockSaveSystem.flush_profile **未**调用 | Unit |
| AC-29 | **EC-4**：ACTIVE 状态下 MockSaveSystem.flush_profile 返回 false（模拟磁盘满），`_active_data` 包含已知内容 X | 返回 `false`；`_active_data` 内容仍为 X（flush 是只读操作，不修改内存） | Unit |

### `get_profile_header()`（F-5）

| # | 测试场景 | 期望结果 | 测试类型 |
|---|---------|---------|---------|
| AC-30 | ACTIVE(_active_index=0)，`_active_data["profile"]={name:"豆豆",avatar_id:"trex_default",times_played:5}`，调用 `get_profile_header(0)` | 返回 `{name:"豆豆",avatar_id:"trex_default",times_played:5,is_valid:true}`；MockSaveSystem.load_profile **未**调用 | Unit |
| AC-31 | `_active_index=0`，MockSaveSystem.load_profile(1) 返回含 `profile.name="Xiao"` 的有效 dict，调用 `get_profile_header(1)` | 返回 dict 含 `is_valid=true`，`name="Xiao"`；MockSaveSystem.load_profile(1) 调用一次 | Unit |
| AC-32 | MockSaveSystem.profile_exists(1) 返回 false（或 index 越界），调用 `get_profile_header(1)` | 返回 dict 含 `is_valid=false`；函数**不**返回裸 `{}`；load_profile **未**调用 | Unit |
| AC-33 | MockSaveSystem.profile_exists(1) 返回 true，load_profile(1) 返回 `{}`，调用 `get_profile_header(1)` | 返回 dict 含 `is_valid=false`（F-5 第 3 条触发） | Unit |

### 公式和数据契约（F-1，F-4）

| # | 测试场景 | 期望结果 | 测试类型 |
|---|---------|---------|---------|
| AC-34 | `MAX_SAVE_PROFILES=3`，分别调用 `profile_index_in_range(i)` for i ∈ {-1, 0, 1, 2, 3} | 返回值：`{-1:false, 0:true, 1:true, 2:true, 3:false}` | Unit |
| AC-37 | ACTIVE 状态，调用 `set_profile_name("a".repeat(21))`（21 字符，超过 NAME_MAX_LENGTH=20） | 返回 `false`；`_active_data["profile"]["name"]` 保持原值（不写入超限字符串） | Unit |

### `get_section()` 和 `profile_exists()`（Core Rules 3，12）

| # | 测试场景 | 期望结果 | 测试类型 |
|---|---------|---------|---------|
| AC-35 | ACTIVE 状态，调用 `get_section("vocab_progress")` 并对返回值写入 `["apple"]=2` | `_active_data["vocab_progress"]["apple"] == 2`（确认返回引用，非副本） | Unit |
| AC-36 | NO_ACTIVE_PROFILE 状态下调用 `get_section("vocab_progress")` | 返回 `{}`；不 push_error 或抛出异常 | Unit |
| AC-38 | MockSaveSystem.profile_exists(0) 第一次返回 true，第二次返回 false，先后调用 `profile_exists(0)` 两次 | 两次均透传给 MockSaveSystem；结果分别为 `true` 和 `false`（ProfileManager 本地无缓存） | Unit |

### 设计契约文档化（非自动化验证）

| # | 测试场景 | 期望结果 | 测试类型 |
|---|---------|---------|---------|
| AC-39 | **EC-3（DOCUMENTATION）**：ACTIVE 状态，VocabStore 对 `get_section("story_progress")` 的返回值写入数据，验证 ProfileManager 不阻止跨节写入 | 写入成功（无报错、无异常）；`_active_data["story_progress"]` 包含写入的值。**注意**：此行为是已知设计决策（ProfileManager 不做运行时访问控制），这条 AC 记录「不阻止」为预期行为，并作为未来 code review 检查点的基线。 | Unit (Documentation) |

---

**EC-6 覆盖声明**：EC-6（订阅者在 `profile_switch_requested` 处理器中使用 `await`）无法由 ProfileManager 单元测试自动捕获——GDScript 运行时不暴露 await 检测 API。覆盖策略：(1) StoryManager / VoiceRecorder 的信号处理函数应在 code review checklist 中标注「禁止 await」；(2) 在集成测试中 mock 含 await 的订阅者，验证步骤 e/f 的执行时序不被 await 阻塞。

## Open Questions

1. ~~**game-concept.md 中 name 限制为 6 字**~~ — **已解决（2026-05-06）**：CD 批准将两层统一为 20 字符；game-concept.md 已同步更新。

2. **profile_switch_requested 同步执行时间预算**：当前 MVP 有 StoryManager、VoiceRecorder 和 VocabStore 三个订阅者，同步清理可在单帧内完成。随系统增加，若订阅者达到 5 个以上，需评估是否引入异步切换协议（记录为潜在 v1.1 设计风险，不阻断本 GDD 批准）。

3. **avatar_id 注册表**：F-1 规定 avatar_id 的有效值集合由美术资产注册决定。MVP 仅有 `"trex_default"` 一个值，完整注册表待美术资产确认后补充（不阻断本 GDD 批准）。

4. **GameRoot 的实现身份**：Interactions 表中 GameRoot 是 ProfileManager 的主要调用方和信号订阅方。GameRoot 是否作为 Autoload Singleton 实现，还是普通 SceneRoot，将影响信号连接时序——待 GameRoot 或架构 ADR 明确（不阻断本 GDD 批准，但需在 StoryManager 和 ChoiceUI GDD 设计前确认）。
