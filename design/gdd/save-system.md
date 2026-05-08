# SaveSystem

> **Status**: Approved — **B-1 applied 2026-05-08** (parent_map_hint_dismissed: false added to schema v2 JSON example, _migrate_to_v2(), _get_default_v2(), and field ownership table)
> **Author**: Zhang Shaocong + agents
> **Last Updated**: 2026-05-08
> **Implements Pillar**: Infrastructure — enables P3 (声音是成长日记) and P4 (家长是骄傲见证者)

## Overview

SaveSystem 是游戏唯一的持久化 I/O 层，负责将结构化 JSON 文件读写到设备 `user://` 目录。游戏中所有需要存储状态的系统（ProfileManager、VocabStore、VoiceRecorder、InterruptHandler）均通过 SaveSystem 的 API 完成文件操作，而不直接访问磁盘。SaveSystem 对外暴露两个核心操作：**load**（从磁盘读取 Dictionary，并在读取时自动将旧版 schema 迁移至 v2）和 **flush**（将当前 Dictionary 写回磁盘）。SaveSystem 本身不解读所存储的数据内容——字段含义属于各业务系统（如 ProfileManager 拥有 profile 字段、VocabStore 拥有词汇进度字段）。Schema v2 是 MVP 首发格式；迁移管道负责在 load 时将开发期遗留的 v1 数据自动升级，升级完成后立即 flush 一次以固化新格式。

## Player Fantasy

SaveSystem 对孩子不可见——它的幻想不是「存档成功」，而是它所许诺的三件事。**第一，游戏认识我**：每次打开 App，T-Rex 还在，词汇金星还在，故事从上次离开的地方继续；孩子感受到的不是进度恢复，而是回到一个认识自己的朋友身边。**第二，声音被留住了**：孩子说出「T-Rex!」的那一刻转瞬即逝，但六个月后家长打开词汇地图，点一颗金星，听到的是那个稚嫩清亮的声音——SaveSystem 是不会忘记的见证者，把孩子不知情时的每一次「第一次」悄悄装进了瓶子。**第三，足迹真实存在**：词汇地图里的每颗金星不是分数，是一次事件的痕迹——那天，孩子第一次独自选对了「Triceratops」，那一步真实发生过，不会消失。没有 SaveSystem，这三件事都不成立：足迹消失，地图永远空白，声音永远丢失，朋友每次见面都是陌生人。

## Detailed Design

### Core Rules

1. **唯一 I/O 入口**：游戏中任何系统均不直接读写 `user://` 目录下的 JSON 存档文件；所有持久化操作必须通过 SaveSystem API。

2. **文件命名约定**：
   - 存档文件：`user://save_profile_{index}.json`，index ∈ {0 … MAX_SAVE_PROFILES-1}
   - 临时文件：`user://save_profile_{index}.tmp`，仅在 flush 期间存在

3. **`load_profile(index)` 执行序列**：
   a. 若文件不存在 → 设置 `_last_load_error = FILE_NOT_FOUND`，返回 `_get_default_v2()`（不写磁盘）
   b. 读取文件失败 → 设置 `FILE_READ_ERROR`，返回 `{}`
   c. `JSON.parse_string()` 返回 `null`，或解析结果非 `Dictionary` → 设置 `JSON_PARSE_ERROR`，返回 `{}`（防止合法 JSON 非 Dict 类型在后续字段访问时崩溃）
   d. `schema_version > CURRENT_SCHEMA_VERSION` → 设置 `SCHEMA_VERSION_UNSUPPORTED`，返回 `{}`（降级防护：绝不用旧版格式覆盖更新版存档，不写磁盘）
   e. `schema_version == CURRENT_SCHEMA_VERSION` → 直接返回 data
   f. 版本低于当前版本 → 内存中执行 `_migrate_to_v2(data)`；调用 `flush_profile()` 持久化（flush 失败仅 push_error，不阻断返回）；返回 migrated_data

4. **`flush_profile(index, data)` 原子写入序列**：
   a. 深拷贝 data，追加 `schema_version = CURRENT_SCHEMA_VERSION` + `last_saved_timestamp`（当前 UTC 时间）
   b. `FileAccess.open(tmp_path, WRITE)` 打开 .tmp；若返回 `null` → 清除 .tmp，push_error，返回 `false`；否则序列化写入并检查 `store_string()` 的 `bool` 返回值（Godot 4.4+ breaking change）
   c. `DirAccess.open("user://")` 打开目录；若返回 `null` → 清除 .tmp，push_error，返回 `false`
   d. `dir.rename(tmp_path, final_path)` 完成原子替换；**返回值必须用 `!= OK` 判断**（`DirAccess.rename()` 返回 `Error` 枚举，`Error.OK = 0` 为 falsy，truthy 判断会将每次成功误判为失败）；rename 直接覆盖已存在的 .json，Android ext4/F2FS 保证原子性，无中间无文件窗口
   e. 任意步骤失败 → 清除 `.tmp`，`push_error`，返回 `false`；成功 → emit `profile_saved(index)`，返回 `true`

5. **v1 → v2 迁移（受控补缺）**：只添加缺失字段，绝不删除已有字段。迁移是幂等的——若 flush 失败，下次 load 会以相同结果重新迁移。v1 的已知词汇键：`["ch1_trex", "ch1_triceratops", "ch1_eat", "ch1_run", "ch1_big"]`。迁移时对每个词汇条目补填：`first_star_at: null`（若已存在则不覆盖）；`recording_paths: []`（若已存在则不覆盖）；若 v1 中存在非 null 的 `recording_path` 字段，包装为 `[recording_path]` 赋值给 `recording_paths`。迁移时对 `profile` section 补填：`parent_map_hint_dismissed: false`（若已存在则不覆盖）——B-1 修复：ParentVocabMap GDD OQ-2 要求此字段存在于 F-1 profile schema。

6. **`_get_default_v2()`**：文件不存在时返回含完整 v2 结构的默认 Dictionary（不写磁盘）：`schema_version = CURRENT_SCHEMA_VERSION`，`last_saved_timestamp = ""`（ProfileManager 用此空字符串判断「从未写过盘」），`profile = {name: "", avatar_id: "", times_played: 0, parent_map_hint_dismissed: false}`（B-1 修复：含 ParentVocabMap 所需字段），`vocab_progress` 含所有 5 个词汇键（每键默认：`is_learned: false, gold_star_count: 0, first_star_at: null, recording_paths: []`），`story_progress = {current_chapter_id: "", path_history: []}`。文件只在 `ProfileManager.create_profile()` 调用 `flush_profile()` 时才被实际写入磁盘。

7. **`last_saved_timestamp`**：每次 flush 时由 SaveSystem 更新（`Time.get_datetime_string_from_system(true) + "Z"`）；业务系统不写此字段。

8. **`delete_profile(index: int) -> bool`（幂等删除）**：删除 `user://save_profile_{index}.json` 文件。若文件不存在，视为成功返回 `true`（幂等语义）；删除失败返回 `false`。不触碰 `user://recordings/` 目录（录音文件生命周期由 VoiceRecorder 负责）。

### LoadError 枚举定义

```gdscript
enum LoadError {
    NONE = 0,
    FILE_NOT_FOUND = 1,
    FILE_READ_ERROR = 2,
    JSON_PARSE_ERROR = 3,
    SCHEMA_VERSION_UNSUPPORTED = 4,
    INVALID_INDEX = 5
}
```

`get_last_load_error() -> LoadError` 返回最近一次 `load_profile()` 调用的错误码；flush 操作不修改此值。每次 `load_profile()` 开始时重置为 `NONE`。

### States and Transitions

SaveSystem 无持久状态机——每次调用是原子同步操作，调用间无内部状态。唯一的非持久状态是 `_last_load_error`，在每次 `load_profile()` 起始时重置为 `NONE`。GDScript 单线程，不存在并发写冲突。

### Interactions with Other Systems

| 调用方 | API | 时机 |
|--------|-----|------|
| ProfileManager | `profile_exists(index)` | App 启动，检查槽位 |
| ProfileManager | `load_profile(index)` | App 启动 + 切换档案 |
| ProfileManager | `flush_profile(index, data)` | 档案创建、times_played 更新 |
| VocabStore | ~~`flush_profile(index, data)`~~ → `ProfileManager.flush()` | 词汇状态批量更新后（ProfileManager GDD 勘误：VocabStore 调用 ProfileManager.flush()，不直接调用 SaveSystem） |
| VoiceRecorder | ~~`flush_profile(index, data)`~~ → `ProfileManager.flush()` | 录音完成，更新 recording_paths（ProfileManager GDD 勘误：VoiceRecorder 调用 ProfileManager.flush()，不直接调用 SaveSystem） |
| InterruptHandler | ~~`flush_profile(index, data)`~~ → `ProfileManager.flush()` | App 进入后台 / 来电中断（ProfileManager GDD 勘误：InterruptHandler 调用 ProfileManager.flush()，不直接调用 SaveSystem） |

**关键约定**：所有调用方均传入完整的档案 Dictionary（通过 ProfileManager 持有的内存副本）。SaveSystem 只接受完整 dict，不做部分字段更新。部分更新语义由调用方在内存中操作 ProfileManager 的 dict 后再调用 flush。

## Formulas

SaveSystem 不包含游戏数值公式。本节定义 **schema v2 JSON 结构**——这是 SaveSystem 的"契约公式"，所有下游系统的 GDD 必须与此结构一致。

### Schema v2 完整示例（`user://save_profile_0.json`）

```json
{
  "schema_version": 2,
  "last_saved_timestamp": "2026-05-06T14:32:01Z",

  "profile": {
    "name": "豆豆",
    "avatar_id": "trex_default",
    "times_played": 3,
    "parent_map_hint_dismissed": false
  },

  "vocab_progress": {
    "ch1_trex":        { "is_learned": true,  "gold_star_count": 3, "first_star_at": "2026-04-15T10:23:41Z", "recording_paths": ["user://recordings/profile_0/ch1_trex.wav"] },
    "ch1_triceratops": { "is_learned": false, "gold_star_count": 1, "first_star_at": "2026-05-01T09:15:00Z", "recording_paths": [] },
    "ch1_eat":         { "is_learned": false, "gold_star_count": 0, "first_star_at": null, "recording_paths": [] },
    "ch1_run":         { "is_learned": false, "gold_star_count": 0, "first_star_at": null, "recording_paths": [] },
    "ch1_big":         { "is_learned": false, "gold_star_count": 0, "first_star_at": null, "recording_paths": [] }
  },

  "story_progress": {
    "current_chapter_id": "ch1",
    "path_history": [
      { "knot": "scene_intro",     "choice": 0 },
      { "knot": "scene_dino_meet", "choice": 1 }
    ]
  }
}
```

### 字段归属说明

| 字段 | 拥有者（负责写入） | SaveSystem 的角色 |
|------|--------------------|-------------------|
| `schema_version` | SaveSystem | 每次 flush 时强制覆写为 `CURRENT_SCHEMA_VERSION` |
| `last_saved_timestamp` | SaveSystem | 每次 flush 时更新为当前 UTC 时间 |
| `profile.*` | ProfileManager | 透明载体，不解读内容 |
| `profile.parent_map_hint_dismissed` | ParentVocabMap | 透明载体；首次关闭 ParentVocabMap 后由其写入 `true`；SaveSystem 迁移时补填 `false`（B-1 修复） |
| `vocab_progress.*` | VocabStore | 透明载体，迁移时用硬编码默认值补缺 |
| `vocab_progress.first_star_at` | VocabStore | 透明载体；首次获得金星时由 VocabStore 填入 UTC 时间戳；初始 `null`；一旦设值不覆盖（SaveSystem 迁移时补填 `null`，但已有值不覆盖） |
| `story_progress.*` | StoryManager | 透明载体，不解读内容 |
| `recording_paths` | VoiceRecorder | 透明载体（数组），迁移时填 `[]`；v1 若存在非 null `recording_path`，包装为 `[recording_path]` |

## Edge Cases

| # | 边界情况 | SaveSystem 行为 | 调用方职责 |
|---|---------|----------------|-----------|
| E1 | **App 在 flush 中途被杀死** | SaveSystem 在 `_ready()` 启动时扫描 .tmp 文件：**若 .tmp 存在且对应 .json 不存在** → `rename(.tmp → .json)` 恢复数据（.tmp 是该档案唯一副本）；**若 .tmp 存在且对应 .json 也存在** → 删除 .tmp（stale，上次 rename 已成功完成）。恢复后执行正常 load 流程，ProfileManager 无需特殊处理。 | ProfileManager 启动时等待 SaveSystem `_ready()` 初始化完成后再调用 `load_profile()` |
| E2 | **存档文件损坏**（JSON 解析失败） | 返回 `{}`，`JSON_PARSE_ERROR`；原文件保留（不覆盖）以供人工排查 | ProfileManager 展示错误 UI，提供「重置此档案」选项 |
| E3 | **磁盘空间不足** | `store_string()` 返回 `false` → 清除 .tmp → `flush_profile()` 返回 `false` | 调用方接到 `false` 后提示「存储空间不足」；游戏继续（内存数据不丢失，下次写入时重试） |
| E4 | **`dir.rename()` 在 Android 上失败** | rename 失败时旧 .json 仍完整（直接覆盖设计无「无文件」窗口）；.tmp 残留；`push_error` 记录；flush 返回 `false`。下次 `_ready()` 扫描时 .tmp 与 .json 共存 → 删除 stale .tmp。 | 调用方接到 `false` 后提示用户并记录遥测日志（v1 无遥测，仅 push_error） |
| E5 | **schema_version > CURRENT_SCHEMA_VERSION**（新版存档在旧版 App 上运行） | 设置 `SCHEMA_VERSION_UNSUPPORTED`，返回 `{}`；绝不用 v2 格式覆盖更新版存档 | ProfileManager 展示「请更新 App」提示，不允许继续游戏 |
| E6 | **index 越界**（< 0 或 >= MAX_SAVE_PROFILES） | 设置 `INVALID_INDEX`，返回 `{}` | ProfileManager / VocabStore 在调用前自行验证 index |
| E7 | **recording_paths 中的 .wav 文件不存在** | SaveSystem 不验证 recording_paths 数组中的文件有效性；透明载体 | VoiceRecorder 在播放前检查文件存在性；金星显示不受影响 |
| E8 | **首次安装/首次启动**，无任何存档文件 | `profile_exists(0)` 返回 `false`；`load_profile(0)` 返回 `_get_default_v2()`；不写磁盘 | GameRoot 通过 `profile_exists(0)=false` 检测，直接路由至 HatchScene；ProfileManager 不触发任何场景切换（Core Rule 7） |
| E9 | **槽位 0 有存档，槽位 1 无存档** | `profile_exists(1)` 返回 `false`；`load_profile(1)` 返回 `_get_default_v2()` | ProfileManager 在 MainMenu 中将槽位 1 显示为「创建新档案」 |
| E10 | **迁移后 flush 失败** | 迁移在内存中完成，返回正确的 migrated_data；下次 load 重新迁移（幂等），不丢数据 | 无需额外处理；正常游戏流程继续 |

## Dependencies

### 上游依赖（SaveSystem 依赖的系统）

无游戏系统依赖。SaveSystem 仅使用 Godot 4.6 内置 API：

| API | 用途 |
|-----|------|
| `FileAccess` | 读写文件；注意 `store_*` 系列自 Godot 4.4 起返回 `bool` |
| `DirAccess` | 目录操作（rename、remove、扫描 .tmp 孤立文件） |
| `JSON` | `parse_string()` / `stringify()` |
| `Time.get_datetime_string_from_system(true)` | 生成 UTC 时间戳字符串 |

### 下游依赖（依赖 SaveSystem 的系统）

| 系统 | 调用的 API | 期望的接口契约 |
|------|-----------|--------------|
| **ProfileManager** | `profile_exists()`, `load_profile()`, `flush_profile()` | load 返回干净 Dictionary 或 `{}`（无 `_error` 污染字段）；flush 返回 bool |
| **VocabStore** | `ProfileManager.flush()` → `flush_profile()` | 词汇批量更新后经 ProfileManager 路由；SaveSystem 不直接接收 VocabStore 调用 |
| **VoiceRecorder** | `ProfileManager.flush()` → `flush_profile()` | 录音完成后经 ProfileManager 路由；SaveSystem 不直接接收 VoiceRecorder 调用 |
| **InterruptHandler** | `ProfileManager.flush()` → `flush_profile()` | 后台中断经 ProfileManager 路由；SaveSystem 不直接接收 InterruptHandler 调用 |

## Tuning Knobs

| 旋钮名 | 当前值 | 安全范围 | 影响 |
|--------|--------|---------|------|
| `MAX_SAVE_PROFILES` | 3（MVP）→ 5（Vertical Slice，待评估） | 1–5 | 最大档案槽位数；超出后 ProfileManager 禁止新建档案 |
| `CURRENT_SCHEMA_VERSION` | 2 | 只增不减 | 控制迁移逻辑触发条件；降低此值会导致已迁移存档被错误地重新迁移 |
| `SAVE_INDENT` | `"\t"` | `""` / `"\t"` / `"  "` | JSON 序列化缩进；`""` 可减小文件体积约 15%（5 词汇档案约 0.8 KB，无优化必要） |

## Visual/Audio Requirements

N/A — SaveSystem 是纯后端系统，无视觉或音频输出。

## UI Requirements

N/A — SaveSystem 不直接驱动任何 UI 节点。错误处理 UI（如「存储空间不足」提示）由调用方（ProfileManager、InterruptHandler）负责。

## Acceptance Criteria

以下所有条目均为可测试的 Pass/Fail 标准，用 GUT 单元测试验证。测试文件位置：`tests/unit/save_system/test_save_system.gd`

| # | 测试场景 | 期望结果 | 测试类型 |
|---|---------|---------|---------|
| AC-1 | 调用 `load_profile(0)` 且 `user://save_profile_0.json` 不存在 | 返回含所有 5 个词汇键的 v2 默认 Dictionary；`get_last_load_error() == FILE_NOT_FOUND`；磁盘上不创建任何文件 | Unit |
| AC-2 | 调用 `flush_profile(0, data)` | 磁盘上存在 `user://save_profile_0.json`；不存在 `user://save_profile_0.tmp`；文件内 `schema_version == CURRENT_SCHEMA_VERSION`；`last_saved_timestamp` 非空 | Unit |
| AC-3 | flush → load 往返一致性 | `load_profile(0)` 返回的 Dictionary 与传入 `flush_profile()` 的 data 中所有业务字段完全相等（去除 `schema_version` 和 `last_saved_timestamp` 后比较） | Unit |
| AC-4 | flush 写入 .json 之前先写 .tmp | 在 `flush_profile()` 执行期间（模拟中途中断），`.tmp` 文件在 rename 完成前存在；rename 成功后 `.tmp` 消失 | Unit |
| AC-5 | v1 存档自动迁移 | 在 `user://save_profile_1.json` 中写入 `schema_version: 1` 的旧格式文件；调用 `load_profile(1)` 后：返回的 dict 中 `schema_version == 2`，所有 5 个词汇键存在；磁盘上的文件已更新为 v2 格式 | Unit |
| AC-6 | 迁移幂等性 | 对同一 v1 文件调用 `load_profile()` 两次，两次返回相同结果 | Unit |
| AC-7 | 损坏的 JSON 文件 | 向文件写入非法 JSON 字符串；`load_profile()` 返回 `{}`；`get_last_load_error() == JSON_PARSE_ERROR`；原文件未被覆盖 | Unit |
| AC-8 | 未来版本 schema（降级防护） | 文件中写入 `schema_version: 99`；`load_profile()` 返回 `{}`；`get_last_load_error() == SCHEMA_VERSION_UNSUPPORTED`；文件未被修改 | Unit |
| AC-9 | `profile_exists()` 准确性 | 无文件时返回 `false`；flush 后返回 `true`；delete 后返回 `false` | Unit |
| AC-10 | index 越界 | `load_profile(-1)` 和 `load_profile(MAX_SAVE_PROFILES)` 均返回 `{}`；`INVALID_INDEX` | Unit |
| AC-11a | .tmp 存在且 .json 不存在（数据恢复） | 写入 `user://save_profile_0.tmp` 但不创建对应 .json；新建 SaveSystem 实例（模拟 App 重启）；`.tmp` 被 rename 为 `.json`；随后 `load_profile(0)` 成功返回已写入的数据 | Unit |
| AC-11b | .tmp 存在且 .json 存在（删除 stale） | 同时写入 `user://save_profile_0.tmp` 和 `.json`（各含不同内容）；新建 SaveSystem 实例；`.tmp` 被删除，`.json` 内容保持不变 | Unit |
| AC-12 | `delete_profile()` 幂等 | 对不存在的 profile 调用 `delete_profile()` 返回 `true`（不抛错） | Unit |

## Open Questions

1. **`DirAccess.rename()` 覆盖已存在文件的行为**：当前设计假定 `dir.rename(tmp, json)` 在目标 .json 已存在时原子覆盖（POSIX `rename()` 语义，Android ext4/F2FS 均支持）。需在目标 Android 设备上实测确认（Week 1 inkgd 验证时顺带测）。若 rename 在目标已存在时返回非 OK 错误，降级方案改为 `dir.remove(.json)` + `dir.rename(.tmp → .json)`（接受极短的无文件窗口）。
2. **`VOCAB_WORD_IDS_CH1` 硬编码**：迁移函数和 `_get_default_v2()` 目前硬编码 5 个词汇键。等 VocabStore GDD 完成后，确认是否需要从 VocabStore 注册表读取（设计边界决策：SaveSystem 是否应知道词汇 ID 列表）。
