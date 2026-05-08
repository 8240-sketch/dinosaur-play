# VoiceRecorder

> **Status**: Approved — /design-review RF-1~RF-8 + RF-NEW-1~RF-NEW-6 applied 2026-05-07; RF-3 (B1~B4, R1~R6) applied 2026-05-08; **S5-B1 applied 2026-05-08** (recording_interrupted signal, interrupt_and_commit unconditional emit)
> **Author**: Zhang Shaocong + agents
> **Last Updated**: 2026-05-08
> **Implements Pillar**: P3 (声音是成长日记), P2 (失败是另一条好玩的路)
> **Risk Level**: ⚠️ HIGH — go/no-go smoke test Day 1 of Week 3; if device cannot
> initialize AudioStreamMicrophone in 5 min → cut feature

## Overview

VoiceRecorder 是游戏中唯一的语音录制与回放层，连接 Godot `AudioStreamMicrophone` 平台接口与持久化层（ProfileManager → SaveSystem）。它的职责分为两侧：**记录侧**（在 TagDispatcher 发出 `recording_invite_triggered` 后，经 RecordingInviteUI 邀请开始录音，捕获最多 `MAX_RECORDING_SECONDS` 秒的 PCM 原始音频，写为 WAV 文件存储在 `user://recordings/profile_{index}/` 目录，并将路径写入 `vocab_progress[word_id].recording_path` 经 ProfileManager 持久化）；**回放侧**（供 ParentVocabMap 点击金星时播放对应的录音文件，`AudioStreamPlayer` 直接加载 WAV）。VoiceRecorder 以 AutoLoad 单例存在，被 RecordingInviteUI 调用启动/停止录音，被 ParentVocabMap 调用回放。Android `RECORD_AUDIO` 运行时权限的请求和结果处理由 VoiceRecorder 统一负责；权限拒绝后功能**静默禁用**——RecordingInviteUI 消失，`recording_path` 保持 `null`，剧情不阻断（P2 Anti-Pillar）。VoiceRecorder 订阅 `ProfileManager.profile_switch_requested`，在信号处理器中同步停止进行中的录音并清除引用，确保档案切换时不产生跨档案数据污染。

> ⚠️ **实现约束**：`AudioStreamMicrophone` + `AudioEffectCapture` 在目标 Android 真机上的行为需在 Week 3 Day 1 的 5 分钟 go/no-go 冒烟测试中验证。若无法在 5 分钟内初始化 → 立即砍除此功能；InterruptHandler 和 ParentVocabMap 的录音回放部分静默禁用，其余功能不受影响。

## Player Fantasy

大橙色圆钮出现的那一刻，T-Rex 举起一只爪子，等着。等的是只有眼前这个孩子才能给的东西——它的声音。这个瞬间的底层逻辑很简单，但对 4-6 岁的孩子来说是真实的：**我的声音可以被接住**。孩子凑近手机说出「T-Rex!」，感觉自己把什么东西递了出去，而 T-Rex 接了；这不是回答一道题，这是把自己的声音当礼物送了出去，而且它真的被收下了。

这一刻的权力感不止于此——游戏的核心是「我教恐龙说英文」，录音是这句话最直接的实体化：**我会这个词，我有发言权，我来教你怎么说**。整天被父母教、被老师教的 4-6 岁孩子，在 T-Rex 面前终于做了一回先知道的那个人。录音行为不是游戏核心幻想之外的附加功能——它就是游戏核心幻想本身（「我教恐龙说英文」）以声音为媒介的兑现。

P2 Anti-Pillar 在这里自然成立：大橙色按钮是邀请，不是考核。T-Rex 举爪请求，孩子可以说，也可以摆摆手，T-Rex 都温和地接受，剧情继续前进。没有惩罚，没有损失，没有「你没说所以怎样」——说话是一次可以拒绝的礼物交换，不是必须完成的任务。

孩子不知道的是：App 把那声「T-Rex!」悄悄接住了，完整的，带着今天的年纪，带着今天还没长好的口音，带着今天刚学到这个词时的认真劲——这是「成长日记」写下的第一行字。六个月后，家长打开词汇地图，点开金星旁的播放按钮，听到的是那个小老师在认真教恐龙的声音——那种认真、那种幼稚、那种初次拥有某个词时的专有感，再长大一点就消失了，而这里有一张存根。

## Detailed Design

### Core Rules

1. **AutoLoad 单例**：`autoload/voice_recorder.gd`，注册名 `VoiceRecorder`。全局唯一，不可通过场景实例化。

2. **接口两侧分离**（解决 TD-SYSTEM-BOUNDARY #5）：
   - **录制侧**：RecordingInviteUI 调用 `start_recording()` / `stop_recording()`，接收 `recording_saved` / `recording_failed` 信号。
   - **回放侧**：ParentVocabMap 调用 `get_recording_paths()` / `play_recording()`，接收 `playback_completed` / `playback_failed` 信号。
   - 两侧共用同一 AutoLoad，但接口文档化为两个独立边界，不得交叉调用。

3. **6 状态机**：

   | 状态 | 含义 |
   |------|------|
   | `UNINITIALIZED` | `_ready()` 前，麦克风未初始化 |
   | `PERMISSION_REQUESTING` | 正在等待系统权限对话框结果 |
   | `READY` | 麦克风就绪，可开始录音或回放 |
   | `RECORDING` | 正在录制 |
   | `SAVING` | 正在写 WAV 文件并更新 Profile |
   | `DISABLED` | 权限被拒绝，录音功能永久禁用（本次会话） |

4. **权限处理（App 启动时）**：
   ```
   _ready():
     if "RECORD_AUDIO" in OS.get_granted_permissions():
       if _init_microphone():    # 已授权，直接初始化；失败则转 DISABLED
         _state = READY
       # 失败时 _init_microphone() 内部已设置 _state = DISABLED 并 emit recording_unavailable
     else:
       _state = PERMISSION_REQUESTING
       OS.request_permissions_result.connect(_on_permissions_result)
       OS.request_permission("RECORD_AUDIO")

   # ⚠️ 以下为伪码——Godot 4.x Android 实际信号签名为数组形式：
   # request_permissions_result(permissions: PackedStringArray, granted: PackedInt32Array)
   # 实现前须 Week 3 真机验证；需迭代数组而非直接比较单值，参见 OQ-1
   _on_permissions_result(permissions, granted):
     var record_audio_granted := false
     for i in range(permissions.size()):
       if permissions[i] == "RECORD_AUDIO" and granted[i] != 0:
         record_audio_granted = true
     if record_audio_granted:
       if _init_microphone():    # 权限已授予；初始化失败则转 DISABLED
         _state = READY
       # 失败时 _init_microphone() 内部已设置 _state = DISABLED 并 emit recording_unavailable
     else:
       _state = DISABLED
       emit_signal("recording_unavailable")
   ```
   > ⚠️ `[TO VERIFY Week 3]` — `OS.request_permission()` 的回调签名在 Godot 4.6 Android 上须真机验证。**疑似实际签名为 `(permissions: PackedStringArray, granted: PackedInt32Array)`（数组形式），与上方伪码不同**；若按单值签名实现，信号将静默不触发，整个功能永久进入 DISABLED。

5. **麦克风初始化**：`_init_microphone() -> bool` 仅从 `_ready()`（权限已授予）或 `_on_permissions_result(granted=true)` 调用，严禁在 PERMISSION_REQUESTING 状态下调用。**返回值语义**：初始化成功 → `true`（调用方负责将 `_state` 置 READY）；失败（总线不存在、设备被占用等）→ 方法内部将 `_state = DISABLED`，emit `recording_unavailable`，返回 `false`。"Microphone" 总线必须在 Godot 编辑器 Audio 布局中预创建（含 AudioEffectCapture 效果插槽）。运行时通过 `AudioServer.get_bus_index(&"Microphone")` 获取总线索引。

6. **录制侧接口**：
   ```
   is_recording_available() -> bool          # 返回 _state == READY

   start_recording(word_id: String) -> bool  # READY→RECORDING；false 表示状态不对
   stop_recording() -> bool                  # RECORDING→SAVING；false 表示不在录音中
   interrupt_and_commit() -> void            # 供 InterruptHandler 调用；同步完成（无 await）
                                             # RECORDING/SAVING：立即写盘并 append 路径
                                             # 其他状态：no-op；is_instance_valid() 检查后调用
                                             # S5-B1 修复：所有路径末尾无条件 emit recording_interrupted()，确保 RecordingInviteUI 可从任意状态退出

   signal recording_started(word_id: String)
   signal recording_saved(word_id: String, path: String)
   signal recording_failed(word_id: String, reason: String)
   signal recording_unavailable()            # 权限被拒后 emit 一次（仅在转入 DISABLED 时）
   signal recording_interrupted()            # S5-B1 修复：interrupt_and_commit() 无条件 emit；供 RecordingInviteUI 从 RECORDING 退出至 DISMISSING
   ```

7. **回放侧接口**：
   ```
   get_recording_paths(word_id: String) -> Array[String]  # 从当前 profile 读取

   play_recording(path: String) -> bool   # false 若文件不存在
   stop_playback() -> void

   signal playback_started(path: String)
   signal playback_completed(path: String)
   signal playback_failed(path: String, reason: String)
   ```
   > ⚠️ **`_playback_player.process_mode` 须在 `_ready()` 中显式设为 `Node.PROCESS_MODE_ALWAYS`**：默认 PAUSABLE 模式下，若 SceneTree 被暂停（如 InterruptHandler 触发系统级暂停），AudioStreamPlayer 将静默停止，P3 家长端 WAV 回放中断——与本 GDD 回放侧"不受游戏暂停影响"的承诺不符。

8. **WAV 写入**：录制期间，每帧调用 `AudioEffectCapture.get_buffer(frames_available)` 返回 `PackedVector2Array`，取每帧 `.x` 分量转换为 int16，**append 至预构建的 `PackedByteArray`**（在录制中持续积累 PCM 字节，不逐帧写盘）。`stop_recording()` 或 `interrupt_and_commit()` 触发写盘时，**一次性执行**：(1) 构建 44-byte WAV 头的 `PackedByteArray`；(2) 将 PCM 数据拼接至头部；(3) `FileAccess.store_buffer(full_wav_bytes)` **一次写入全部内容**。**严禁逐样本调用 `store_16()`**——132,300 次 GDScript 调用在低端 Android 设备上需 1.8–5.3 秒主线程冻结，与 `interrupt_and_commit()` 同步约束（<100ms）不兼容。写入完成后，路径 append 到 `vocab_progress[word_id]["recording_paths"]`，调用 `ProfileManager.flush()`。
   > ⚠️ `[TO VERIFY Week 3]` — 负样本值的 16-bit two's-complement 截断行为需真机 smoke test 验证。

9. **文件命名**：`user://recordings/profile_{active_index}/{word_id}_{YYYYMMDDTHHmmssZ}.wav`（时间戳不含冒号，Android 文件系统安全）。

10. **多次录音保留**：每次录音成功后路径 append 到 `recording_paths: Array[String]`，不覆盖旧录音。ProfileManager 持久化整个数组。

11. **档案切换（profile_switch_requested）**：同步处理器（严禁 await）。若在 RECORDING：停止 AudioEffectCapture，丢弃缓冲区，清除 `_current_word_id`，状态置 READY。若在 SAVING：放弃写入，清除 `_current_word_id`，状态置 READY，不 emit `recording_saved`。

12. **档案删除（active_profile_cleared）**：监听 ProfileManager `active_profile_cleared(reason: String)`。若 `reason == "user_deleted"`：调用内部 `_delete_dir_recursive(path)` 删除 `user://recordings/profile_{deleted_index}/` 目录及其下所有 WAV 文件。**实现规范：`DirAccess.remove_absolute()` 不能删除非空目录，必须先枚举目录内所有文件逐一 `remove_absolute()` 删除，再删除空目录本身**——若直接对非空目录调用 `remove_absolute()`，返回错误且目录不删除，留下孤儿 WAV 文件，违反隐私约束（儿童录音须随档案彻底清除）。目录不存在时 no-op（EC-PS4）。仅能清理当前 active profile 的录音；非 active 档案删除的录音文件孤存（见 Open Questions OQ-4）。

### States and Transitions

```
UNINITIALIZED
  ──[_ready(), RECORD_AUDIO already granted, _init_microphone() succeeds]──▶ READY
  ──[_ready(), RECORD_AUDIO already granted, _init_microphone() fails]──▶ DISABLED
  ──[_ready(), not granted]──▶ PERMISSION_REQUESTING

PERMISSION_REQUESTING
  ──[_on_permissions_result(granted=true), _init_microphone() succeeds]──▶ READY
  ──[_on_permissions_result(granted=true), _init_microphone() fails]──▶ DISABLED
  ──[_on_permissions_result(granted=false)]──▶ DISABLED
  ──[profile_switch_requested]──▶ PERMISSION_REQUESTING  (no-op)

READY
  ──[start_recording(word_id)]──▶ RECORDING
  ──[profile_switch_requested]──▶ READY  (no-op, already idle)
  ──[active_profile_cleared("user_deleted")]──▶ READY  (after dir delete)

RECORDING
  ──[stop_recording()]──▶ SAVING
  ──[MAX_RECORDING_SECONDS timer]──▶ SAVING  (auto-stop)
  ──[profile_switch_requested]──▶ READY  (discard buffer, no save)

SAVING
  ──[_write_wav() success]──▶ READY  (emit recording_saved, flush Profile)
  ──[_write_wav() failure]──▶ READY  (emit recording_failed, Profile unchanged)
  ──[profile_switch_requested]──▶ READY  (abandon write, no save, no emit)

DISABLED
  ──[no transitions]  (permanent this session; resolved by App restart + re-grant)
```

### Interactions with Other Systems

| 系统 | 方向 | 数据 / 接口 |
|------|------|------------|
| **ProfileManager** | VR 读取 | `get_section("vocab_progress")` 获取当前档案词汇进度；持有引用 |
| **ProfileManager** | VR 写入 | 录音完成后 append `recording_paths`，调用 `ProfileManager.flush()` |
| **ProfileManager** | VR 订阅 | `profile_switch_requested(new_index: int)` — 同步停止录音，清除引用 |
| **ProfileManager** | VR 订阅 | `active_profile_cleared(reason: String)` — user_deleted 时删除录音目录 |
| **SaveSystem** | 间接 | VoiceRecorder 不直接调用 SaveSystem；所有持久化通过 ProfileManager.flush() |
| **TagDispatcher** | 间接 | TagDispatcher emit `recording_invite_triggered`；VoiceRecorder 不订阅，由 RecordingInviteUI 中介 |
| **RecordingInviteUI** | ← 录制侧 | 调用 `start_recording()` / `stop_recording()`；订阅 `recording_saved` / `recording_failed` |
| **InterruptHandler** | ← 中断契约 | 调用 `interrupt_and_commit()`（同步，无 await）；须以 `is_instance_valid()` 检查后调用；**解决 IH OQ-6** |
| **ParentVocabMap** | ← 回放侧 | 调用 `get_recording_paths()` / `play_recording()`；订阅 `playback_completed` / `playback_failed` |

## Formulas

**F1. PCM 数据大小与文件总大小**

```
pcm_data_size = sample_rate × channels × bytes_per_sample × MAX_RECORDING_SECONDS
              = 44100 × 1 × 2 × 3 = 264,600 bytes

wav_file_size = RIFF_HEADER_SIZE + pcm_data_size
              = 44 + 264,600 = 264,644 bytes ≈ 258.6 KB（最坏情况，满录 3 秒）
```

变量：`sample_rate` = `AudioServer.get_mix_rate()`（典型 44100 Hz）；`channels` = 1（单声道）；`bytes_per_sample` = 2（16-bit PCM）

> ⚠️ WAV 头字段特别注意：`ChunkSize` = pcm_data_size + 36（非 +44）；`Subchunk2Size` = pcm_data_size。写错这两个字段将导致 Android 系统播放器拒绝解码。

**F2. WAV 头结构（标准 PCM，44 bytes，不可调）**

| 常量 | 值 | 说明 |
|------|----|------|
| `RIFF_HEADER_SIZE` | 44 bytes | RIFF/fmt/data 三块标准头总长（这是**文件偏移量**，不是 ChunkSize 字段值） |
| `ChunkSize`（偏移 4，uint32） | `pcm_data_size + 36` | RIFF 数据块大小 = 36（fmt+data 块头）+ PCM 字节数；**不是 +44**（+44 是总文件大小，+44 写入此字段将使 Android 播放器拒绝解码，见 EC-RQ4） |
| `Subchunk2Size`（偏移 40，uint32） | `pcm_data_size` | PCM 数据字节总数，等于 F1 中的 `pcm_data_size` |
| `BYTE_RATE`（偏移 28，uint32） | **不得硬编码**（EC-AD4：48000 Hz 设备上为 96,000 B/s，非 88,200 B/s） | = `AudioServer.get_mix_rate()` × channels × bytes_per_sample |
| `BLOCK_ALIGN` | 2 bytes | = channels × bytes_per_sample |

**F3. 时间戳生成（文件命名用）**

```
raw = Time.get_datetime_string_from_system(utc=true)
    # 格式："YYYY-MM-DDTHH:MM:SS"
timestamp = raw.replace("-", "").replace(":", "") + "Z"
    # 结果："YYYYMMDDTHHmmssZ"（Android 文件系统安全，不含冒号）
```

**F4. 自动停止计时器**

```
_timer.wait_time = MAX_RECORDING_SECONDS  # 3.0 秒
_timer.one_shot  = true
_timer.autostart = false
# start_recording() 时启动；stop_recording() 或 profile_switch 时取消
```

**F5. 最小录音时长过滤**

```
MIN_RECORDING_FRAMES = floor(MIN_RECORDING_MS / 1000.0 × sample_rate)
                     = floor(150 / 1000.0 × 44100) = 6,615 frames

# _write_wav() 调用前检查（录制中 AudioEffectCapture 已被持续 drain 至近零；
# 实际帧计数须从已积累的 _pcm_buffer 字节数推算）：
var bytes_per_sample: int = 2  # 16-bit mono
if _pcm_buffer.size() / bytes_per_sample < MIN_RECORDING_FRAMES:
    emit_signal("recording_failed", _current_word_id, "too_short")
    _state = READY
    return
```

不满足最小帧数的录音直接丢弃，不写盘，不 append 路径，不 flush Profile。

## Edge Cases

### 1. 权限相关

| # | 边界情况 | 预期行为 |
|---|---------|---------|
| EC-P1 🔴 | 首次运行，用户在系统对话框中点击「拒绝」或「永远拒绝」 | `_on_permissions_result(granted=false)` → 转入 DISABLED，emit `recording_unavailable`（仅一次），RecordingInviteUI 消失，剧情不阻断。DISABLED 在本次 session 内永久，重新授权须重启 App |
| EC-P2 ⚠️ | 权限已授予，用户在游戏运行期间通过系统设置撤销（Android 允许运行时撤销）| 下次 `start_recording()` 后录音帧数 `< MIN_RECORDING_FRAMES`（权限撤销时麦克风无输入）→ 走 too_short 路径 emit `recording_failed("too_short")`；连续失败达 `PERMISSION_REVOKE_FAILURE_THRESHOLD` 次后转入 DISABLED，emit `recording_unavailable` |
| EC-P3 ⚠️ | PERMISSION_REQUESTING 状态期间，系统权限对话框被 Android OOM 杀死，`request_permissions_result` 信号永远不到达 | 永久停留 PERMISSION_REQUESTING；所有 `start_recording()` 调用返回 `false`；RecordingInviteUI 不出现，剧情静默跳过录音邀请 |
| EC-P4 💡 | `_init_microphone()` 调用时 `AudioServer.get_bus_index("Microphone")` 返回 -1（编辑器未创建 Microphone 总线）| push_error，转入 DISABLED，emit `recording_unavailable`。此问题须在 Week 3 Day 1 冒烟测试中发现 |

### 2. 状态机异常（非法调用）

| # | 边界情况 | 预期行为 |
|---|---------|---------|
| EC-SM1 🔴 | `start_recording()` 在 RECORDING 状态被调用（孩子快速连按录音按钮）| 返回 `false`，no-op。不重新初始化 AudioEffectCapture，不重置计时器，当前录音继续 |
| EC-SM2 🔴 | `stop_recording()` 在非 RECORDING 状态（READY / SAVING / DISABLED 等）被调用 | 返回 `false`，no-op |
| EC-SM3 🔴 | `start_recording()` 在 DISABLED 状态被调用 | 返回 `false`，no-op |
| EC-SM4 ⚠️ | `start_recording()` 在 SAVING 状态被调用（前一个词写盘未完成，下一个录音邀请到来）| 返回 `false`。RecordingInviteUI 对 `false` 静默处理；设计上接受一次录音机会丢失 |
| EC-SM5 💡 | `play_recording()` 在 RECORDING 状态被调用 | 返回 `false`，emit `playback_failed("recording_in_progress")`，不中断录音 |

### 3. 文件系统

| # | 边界情况 | 预期行为 |
|---|---------|---------|
| EC-FS1 🔴 | `_write_wav()` 期间磁盘满，`FileAccess.open()` 或写入失败 | 关闭 FileAccess，尝试删除不完整文件（`DirAccess.remove_absolute()`）。emit `recording_failed("write_error")`，状态回 READY，不 append 路径，不 flush |
| EC-FS2 🔴 | `user://recordings/profile_{index}/` 目录不存在（该 profile 首次录音）| 写盘前调用 `DirAccess.make_dir_recursive_absolute(path)`；失败则 emit `recording_failed("dir_create_error")`，状态回 READY |
| EC-FS3 ⚠️ | WAV 写入中途 App 被 Android OOM Killer 杀死 | 磁盘残留不完整 WAV，但 `recording_paths` 无此路径（flush 未执行），孤儿文件不被引用，功能不受影响 |
| EC-FS4 ⚠️ | `recording_paths` 中的路径对应文件已被外部删除 | `play_recording(path)` 前执行 `FileAccess.file_exists(path)` → false → emit `playback_failed("file_not_found")`；ParentVocabMap 据此灰化播放按钮 |
| EC-FS5 ⚠️ | WAV 写入成功，但 `ProfileManager.flush()` 返回 false | WAV 文件已固化，视为 `recording_saved`，但 push_error 记录 flush 失败 |
| EC-FS6 💡 | 同一秒内对同一 `word_id` 完成两次录音（时间戳碰撞导致文件名重复）| 检查目标路径是否存在；若存在则追加序号后缀 `_1`, `_2`……直至唯一，不覆盖已有文件 |
| EC-FS7 💡 | `word_id` 包含文件系统不安全字符（斜杠、空格等）| 文件名中的 `word_id` 部分执行 sanitize：非字母数字字符替换为下划线 |

### 4. 音频设备

| # | 边界情况 | 预期行为 |
|---|---------|---------|
| EC-AD1 🔴 | `_init_microphone()` 时麦克风被其他 App 占用（如系统通话）| 初始化失败或 AudioEffectCapture 无法捕获数据 → push_error → DISABLED，emit `recording_unavailable`。Week 3 Day 1 冒烟测试必验场景 |
| EC-AD2 ⚠️ | 录音进行中来电，Android 回收麦克风 | InterruptHandler 先捕获 `NOTIFICATION_APPLICATION_FOCUS_OUT` → 调用 `interrupt_and_commit()` → `get_frames_available()` 极低 → too_short，emit `recording_failed("too_short")`，录音丢弃，剧情不阻断 |
| EC-AD3 ⚠️ | 录音中蓝牙麦克风断开，Android 切换至内置麦克风 | Godot 使用系统默认音频路由，AudioEffectCapture 继续运行；录音不中断，接受降级音质 |
| EC-AD4 💡 | `AudioServer.get_mix_rate()` 在特定设备上返回非 44100 Hz（如 48000 Hz）| WAV header `SampleRate`/`ByteRate` 字段、`MIN_RECORDING_FRAMES` 和 `pcm_data_size` 计算均须使用 `get_mix_rate()` 实际返回值，不得硬编码 44100 |

### 5. 录音质量

| # | 边界情况 | 预期行为 |
|---|---------|---------|
| EC-RQ1 🔴 | 录音时长 < `MIN_RECORDING_MS`（默认 150 ms）| `_pcm_buffer.size() / bytes_per_sample < MIN_RECORDING_FRAMES`（AudioEffectCapture 在录制中已被持续 drain，写盘时 `get_frames_available()` 近零；须从积累的 PCM 字节数计算帧数） → 丢弃 buffer，不写盘，emit `recording_failed("too_short")`，状态回 READY |
| EC-RQ2 ⚠️ | PCM 样本值超出 `[-1.0, 1.0]`（AudioEffectCapture 超饱和）| 转换 int16 前执行 `clampf(sample, -1.0, 1.0)`，防止溢出产生爆音；文件正常保存，不视为失败 |
| EC-RQ3 💡 | 全零静音录音（孩子靠近麦克风但未发声）| 帧数满足 `MIN_RECORDING_FRAMES` → 正常保存为全零 WAV。不做噪音门检测，保留孩子「选择不说」的权利（P2 Anti-Pillar）|
| EC-RQ4 💡 | WAV header `ChunkSize` 字段写为 pcm_data_size+44（正确应为 +36）| Android 播放器拒绝解码，emit `playback_failed("decode_error")`。属实现 bug；smoke test 中验证首个录音可正常回放 |

### 6. Profile 切换期间并发

| # | 边界情况 | 预期行为 |
|---|---------|---------|
| EC-PS1 🔴 | `profile_switch_requested` 在 RECORDING 状态触发 | 同步处理器（严禁 await）：`AudioEffectCapture.clear_buffer()`，取消计时器，清除 `_current_word_id`。不 emit `recording_saved` / `recording_failed`（静默丢弃），状态置 READY |
| EC-PS2 🔴 | `profile_switch_requested` 在 SAVING 状态触发 | GDScript 单线程，设置内部标志 `_discard_after_save = true`。`_write_wav()` 完成后检测此标志：若为 `true` → 删除刚写入的文件，不 append 路径，不 flush，状态置 READY，清除标志。**优先级规则：`_discard_after_save` 优先于 `_commit_requested`**——若两标志同时为 `true`（profile switch 与 `interrupt_and_commit()` 同时触发），执行丢弃逻辑（删除文件，不 flush，不 emit `recording_saved`），不执行 commit 逻辑；清除两个标志。录音归属于特定 profile，档案切换语义优先于中断保全语义。⚠️ **同步路径注解**：`_write_wav()` 为同步函数，SAVING 状态在其调用栈内即进入并退出；外部信号处理器在 `_write_wav()` 返回前不被 GDScript 调度，`_discard_after_save` 在当前实现中实际不可达。**若未来将 `_write_wav()` 改为 async（加入 await），此标志机制才生效**；当前作为防御性设计保留，不删除。 |
| EC-PS3 ⚠️ | `active_profile_cleared("user_deleted")` 在 RECORDING 状态触发 | 先执行与 EC-PS1 相同的 RECORDING 停止逻辑，再删除录音目录（写盘已被阻断，目录删除安全）|
| EC-PS4 💡 | `active_profile_cleared("user_deleted")` 时录音目录不存在 | `DirAccess.dir_exists_absolute(path)` 检查后跳过删除，no-op |
| EC-PS5 💡 | `profile_switch_requested` 在 PERMISSION_REQUESTING 状态触发 | no-op；若权限随后 granted，以当前 active profile 上下文完成初始化，进入 READY |

### 7. 回放侧异常

| # | 边界情况 | 预期行为 |
|---|---------|---------|
| EC-PB1 ⚠️ | `play_recording("")`、`play_recording(null)` 或路径格式无效 | 返回 `false`，emit `playback_failed("invalid_path")`，不尝试文件访问 |
| EC-PB2 ⚠️ | WAV 文件存在但损坏（不完整写入、header 错误）| AudioStreamPlayer 加载失败 → false，emit `playback_failed("decode_error")`；ParentVocabMap 禁用该条目播放按钮 |
| EC-PB3 💡 | `get_recording_paths(word_id)` 的 `word_id` 不在当前 profile 的 `vocab_progress` 中 | 返回 `[]`，不报错 |
| EC-PB4 💡 | `play_recording()` 调用时 AudioStreamPlayer 正在播放另一个文件 | 先调用 `stop_playback()`，再加载新文件播放 |
| EC-PB5 💡 | `stop_playback()` 在无回放时调用 | no-op，不崩溃，不 emit 信号 |

### 8. interrupt_and_commit 各状态下的行为

| 状态 | 调用结果 |
|------|---------|
| **UNINITIALIZED** | no-op；**末尾无条件 emit `recording_interrupted()`**（S5-B1 修复） |
| **PERMISSION_REQUESTING** | no-op；**末尾无条件 emit `recording_interrupted()`**（S5-B1 修复） |
| **READY** | no-op；**末尾无条件 emit `recording_interrupted()`**（S5-B1 修复） |
| **RECORDING** 🔴 | 同步执行（无 await）：停止 AudioEffectCapture，取消计时器；检查积累的 PCM `PackedByteArray` 帧数——若 < MIN_RECORDING_FRAMES → 丢弃，不写盘，不 emit `recording_saved`；若 ≥ MIN_RECORDING_FRAMES → 构建 WAV `PackedByteArray` + 一次性 `store_buffer()` 写盘，append 路径，调用 `ProfileManager.flush()`，**emit `recording_saved(word_id, path)`**。无论哪条路径，状态置 READY，清除 `_current_word_id`，**无条件 emit `recording_interrupted()`**（S5-B1 修复：确保 RecordingInviteUI 可从 RECORDING 状态退出） |
| **SAVING** ⚠️ | 设置内部标志 `_commit_requested = true`；写盘完成后：若 `_discard_after_save == false` 且写盘成功 → 确认路径已 append，调用 `ProfileManager.flush()`，emit `recording_saved`；若 `_discard_after_save == true`（EC-PS2 优先级规则）→ 执行丢弃（删除文件，不 flush，不 emit `recording_saved`），`_commit_requested` 不执行；清除两标志；**末尾无条件 emit `recording_interrupted()`**（S5-B1 修复） |
| **DISABLED** | no-op；**末尾无条件 emit `recording_interrupted()`**（S5-B1 修复） |

| # | 特殊竞态 | 预期行为 |
|---|---------|---------|
| EC-IC1 🔴 | `interrupt_and_commit()` 在同一帧内被 InterruptHandler 两条路径调用（如 `FOCUS_OUT` + `WM_GO_BACK_REQUEST` 同帧触发）| GDScript 单线程，第一次调用完成后状态已离开 RECORDING（变为 READY）；第二次调用检测到 READY → no-op。双重调用自洽 |

### 9. 多次快速触发（竞态条件）

| # | 边界情况 | 预期行为 |
|---|---------|---------|
| EC-RC1 🔴 | `start_recording()` 快速被调用两次（孩子双击录音按钮）| 第一次：READY → RECORDING，返回 `true`；第二次：RECORDING → 返回 `false`，no-op。RecordingInviteUI 静默处理 `false`（按钮视觉禁用）|
| EC-RC2 🔴 | MAX_RECORDING_SECONDS 计时器超时与用户手动 `stop_recording()` 同帧触发 | 先执行者将状态 RECORDING → SAVING；后执行者检测到非 RECORDING → no-op。Timer handler 须在执行前检查状态 == RECORDING，防止重复写盘 |
| EC-RC3 ⚠️ | `interrupt_and_commit()`（InterruptHandler）与 `stop_recording()`（RecordingInviteUI）在极短窗口内均被触发 | 先执行者使状态离开 RECORDING；后执行者遇到非 RECORDING → no-op。状态机保证只有一次写盘，路径只 append 一次 |
| EC-RC4 💡 | `stop_recording()` 在 `start_recording()` 后立即调用（< MIN_RECORDING_MS）| RECORDING → SAVING → `_write_wav()` 检测 frames < MIN_RECORDING_FRAMES → emit `recording_failed("too_short")`，状态回 READY |

## Dependencies

### 上游依赖（VoiceRecorder 依赖的系统）

#### ProfileManager

VoiceRecorder 是 ProfileManager 的直接调用方和双信号订阅方。

| 接口 | 类型 | 用途 |
|------|------|------|
| `get_section("vocab_progress") -> Dictionary` | 方法调用（返回引用） | 初始化时获取词汇进度引用；写盘后将路径 append 至 `vocab_progress[word_id]["recording_paths"]` |
| `flush() -> bool` | 方法调用 | SAVING 路径写盘成功后持久化；`interrupt_and_commit()` 同步路径亦调用 |
| `profile_switch_requested(new_index: int)` 信号 | 信号订阅 | 同步处理器（严禁 await）：RECORDING 停止捕获丢弃缓冲；SAVING 设 `_discard_after_save=true`；清除 `_current_word_id` |
| `active_profile_cleared(reason: String)` 信号 | 信号订阅 | `reason == "user_deleted"` 时递归删除 `user://recordings/profile_{deleted_index}/`；`reason == "load_failed"` 时 no-op |

**调用约束：**
- `get_section("vocab_progress")` 返回引用，禁止跨越 `profile_switch_requested` 信号边界缓存。
- VoiceRecorder 不直接调用 SaveSystem；所有档案持久化路径为 `ProfileManager.flush()`。
- 字段写权限约定：VoiceRecorder 仅写 `recording_paths`；VocabStore 写 `is_learned`、`gold_star_count`、`first_star_at`；两者字段无交叠。

#### SaveSystem（间接依赖）

VoiceRecorder 与 SaveSystem **无直接接口调用**。`vocab_progress` 持久化经由 `ProfileManager.flush()` 路由，SaveSystem 对 VoiceRecorder 不可见。VoiceRecorder 直接操作的 `user://recordings/` 目录与 SaveSystem 管理的 JSON 存档文件路径不重叠。

#### Godot 引擎（平台依赖）

| API / 子系统 | 用途 | 风险标注 |
|-------------|------|---------|
| `AudioStreamMicrophone` | 麦克风输入流 | ⚠️ Android 设备兼容性须 Week 3 Day 1 go/no-go 验证 |
| `AudioEffectCapture` | 挂载于 "Microphone" 总线；`get_buffer()` 返回 `PackedVector2Array` | ⚠️ 负样本截断行为须真机验证（EC-RQ2）；总线须编辑器预创建 |
| `AudioServer.get_bus_index(&"Microphone")` | 运行时获取总线索引；-1 表示总线不存在 | 🔴 须在编辑器 Audio 布局预创建含 AudioEffectCapture 的 "Microphone" 总线 |
| `AudioServer.get_mix_rate()` | 获取实际采样率；WAV header 和 MIN_RECORDING_FRAMES 计算必须使用此值 | ⚠️ 部分设备返回 48000 Hz（见 EC-AD4） |
| `AudioStreamPlayer` | 回放侧：加载并播放 WAV；`finished` 信号驱动 `playback_completed` | 稳定 |
| `OS.get_granted_permissions()` | `_ready()` 中检查 RECORD_AUDIO 是否已授予 | ⚠️ Android 真机验证 |
| `OS.request_permission("RECORD_AUDIO")` | 首次运行时请求运行时权限（单数形式，非 `request_permissions`） | ⚠️ 回调签名须真机确认 |
| `OS.request_permissions_result` 信号 | 权限请求结果回调；**⚠️ 疑似实际签名为 `(permissions: PackedStringArray, granted: PackedInt32Array)`**，非 `(permission: String, granted: bool)`——Week 3 真机验证后适配实现 | ⚠️ 签名错误将导致处理器静默不触发，整个功能进入 DISABLED |
| `FileAccess` | WAV 写入（Core Rule 8：一次性 `store_buffer()` 写入完整 WAV；`store_16()` 在 Godot 4.4+ 返回 `bool`，忽略即可）；`file_exists()` 回放前检查 | `store_16()` 返回值为 Godot 4.4 breaking change；**WAV 头 uint32 字段（ChunkSize/SampleRate/ByteRate/Subchunk2Size 等）须使用 `PackedByteArray.encode_u32(offset, value)` 写入**，`FileAccess` 不提供等效的偏移写入接口 |
| `DirAccess` | `make_dir_recursive_absolute()` 建目录；`remove_absolute()` 清理残缺文件；`dir_exists_absolute()` 删除前检查 | 稳定 |
| `Time.get_datetime_string_from_system(utc=true)` | 文件名时间戳生成（F3） | 稳定 |

---

### 下游依赖（依赖 VoiceRecorder 的系统）

#### RecordingInviteUI（录制侧，#14）

GDD 状态：Not Started。接口契约由本 GDD 声明，RecordingInviteUI GDD 设计时须对齐。

| 接口 | 类型 | RecordingInviteUI 使用方式 |
|------|------|--------------------------|
| `is_recording_available() -> bool` | 方法调用 | TagDispatcher emit `recording_invite_triggered` 后，决定是否显示橙色录音按钮 |
| `start_recording(word_id: String) -> bool` | 方法调用 | 圆钮按下时调用；false 时静默禁用按钮 |
| `stop_recording() -> bool` | 方法调用 | 录音按钮释放时调用 |
| `recording_started(word_id: String)` 信号 | 信号订阅 | 显示录音进行中视觉状态 |
| `recording_saved(word_id: String, path: String)` 信号 | 信号订阅 | 录音成功正向反馈 |
| `recording_failed(word_id: String, reason: String)` 信号 | 信号订阅 | 静默处理，不阻断剧情（P2 Anti-Pillar） |
| `recording_unavailable()` 信号 | 信号订阅 | 权限被拒后 UI 永久消失 |
| `recording_interrupted()` 信号 | 信号订阅 | **S5-B1 修复**：`interrupt_and_commit()` 无条件 emit；RIUI 收到后从 RECORDING 状态转入 DISMISSING，防止界面卡死 |

注：RecordingInviteUI 经由 TagDispatcher 的 `recording_invite_triggered` 信号触发录音邀请，与 TagDispatcher 的关系属于信号订阅，非调用依赖（TD-SYSTEM-BOUNDARY Concern #4）。

#### InterruptHandler（中断契约，#9）

InterruptHandler GDD 已 Approved。IH GDD OQ-6 **已随本 GDD 批准标记为 RESOLVED**。

| 接口 | 类型 | InterruptHandler 使用方式 |
|------|------|--------------------------|
| `interrupt_and_commit() -> void` | 方法调用（同步，无 await） | FOCUS_OUT / PAUSED / WM_GO_BACK_REQUEST / `ui_cancel` 四路径中，在 `StoryManager.request_chapter_interrupt()` 之前调用 |

**已确认调用约束（解决 IH OQ-6）：**
- 严格同步，不含任何 `await`，可在单帧内完成。
- 调用前须以 `is_instance_valid(VoiceRecorder)` 守卫；权限被拒时静默跳过。
- RECORDING 状态：同步写盘（帧数足够）或丢弃（帧数不足），状态置 READY。
- SAVING 状态：设 `_commit_requested=true`，写盘完成后确认路径 append 并 flush。
- 其他状态：no-op。同一帧双触发自洽（EC-IC1）。
- **S5-B1 修复**：所有路径末尾无条件 emit `recording_interrupted()` 信号，确保 RecordingInviteUI 可从任意状态退出。

#### ParentVocabMap（回放侧，#17）

GDD 状态：Not Started。接口契约由本 GDD 声明，ParentVocabMap GDD 设计时须对齐。

| 接口 | 类型 | ParentVocabMap 使用方式 |
|------|------|------------------------|
| `get_recording_paths(word_id: String) -> Array[String]` | 方法调用 | 词汇地图打开时为每个金星查询录音列表；`[]` 表示无录音，不显示播放按钮 |
| `play_recording(path: String) -> bool` | 方法调用 | 点击播放按钮；false 时灰化按钮 |
| `stop_playback() -> void` | 方法调用 | 词汇地图关闭或切换词汇条目时停止回放 |
| `playback_started(path: String)` 信号 | 信号订阅 | 更新播放按钮进行中视觉 |
| `playback_completed(path: String)` 信号 | 信号订阅 | 恢复播放按钮可用状态 |
| `playback_failed(path: String, reason: String)` 信号 | 信号订阅 | `"file_not_found"` / `"decode_error"` → 灰化该条目播放按钮 |

---

### 依赖约束汇总

| 约束 | 说明 |
|------|------|
| **AutoLoad 加载顺序** | VoiceRecorder 须在 ProfileManager 之后加载，确保 `_ready()` 时信号连接有效 |
| **"Microphone" 总线须编辑器预创建** | 运行时不动态创建总线；缺失时转入 DISABLED |
| **`user://recordings/` 目录所有权** | 完全由 VoiceRecorder 管理；SaveSystem 不触碰此目录 |
| **profile_switch_requested 处理器中严禁 await** | 违反将导致新档案数据覆写时旧录音引用未清除 |
| **interrupt_and_commit() 必须同步完成** | InterruptHandler 在单帧内执行中断序列；任何 await 导致 P3 数据契约失效 |

## Tuning Knobs

下表列出所有可在不改动核心状态机逻辑的前提下安全调整的配置常量。
超出安全范围的值标注了具体的失效模式，而非泛泛的"不推荐"。

| 常量名 | 当前值 | 安全范围 | 影响描述 |
|--------|--------|----------|----------|
| `MAX_RECORDING_SECONDS` | `3` | `2 – 5` | 录音自动停止的最大时长。**下界 2 s**：低于 2 s 时，双音节词（如 "apple"、"T-Rex"）在正常语速下可能被截断，孩子来不及说完就自动停止。**上界 5 s**：高于 5 s 使单文件 PCM 数据超过 440 KB（5 s × 44100 × 2 B），超出用户体感"一次录音"的合理等待时间；`user://` 空间累积速度加倍。 |
| `MIN_RECORDING_MS` | `150` | `100 – 600` | 录音被判定为"有效"的最低帧数门槛（转换自毫秒，实际为 `floor(N/1000.0 × sample_rate)` 帧）。**下界 100 ms**：低于 100 ms 时意外触碰（手掌扫过屏幕）产生的噪声片段可能通过过滤，增加无意义录音写盘率。**上界 600 ms**：高于 600 ms 时，孩子快速说出的单音节词（如 "cat"、"eat"，约 0.3–0.5 s）将被丢弃，频繁触发 `recording_failed("too_short")`，破坏 P2 邀请体验。 |
| `PERMISSION_REVOKE_FAILURE_THRESHOLD` | `3` | `2 – 5` | 权限被运行时撤销后，连续触发 `recording_failed("too_short")` 多少次后转入 DISABLED 并 emit `recording_unavailable`（EC-P2）。**下界 2**：在极端情况下（孩子连续两次快速抬手）存在误判风险。**上界 5**：孩子须经历 5 次静默失败才看到 UI 消失，用户体验混乱期过长。当前值 3 基于：叙事流程中连续出现 3 个录音邀请且每次均 too_short 的概率极低，足以区分"偶发短录音"与"权限丢失"。计数器在任何一次 `recording_saved` 后归零。 |

### 不在调节范围内的常量

以下常量在代码中以字面量出现，但**不应被视为可调节旋钮**，改动需同步修改 WAV 写入逻辑或存储格式：

| 常量 | 固定值 | 锁定原因 |
|------|--------|---------|
| `RIFF_HEADER_SIZE` | `44 bytes` | WAV 标准 RIFF/fmt/data 三块头的固定长度；改动使 Android 播放器拒绝解码（EC-RQ4） |
| 声道数 (`channels`) | `1`（单声道） | 架构决策：取 PackedVector2Array 每帧 `.x` 分量；改为双声道需同步修改 F1 公式和 WAV header 多个字段 |
| 位深 (`bytes_per_sample`) | `2`（16-bit PCM） | 架构决策；改动需重写 `store_16()` 循环及 WAV header `BitsPerSample` 字段 |
| 采样率 (`sample_rate`) | 运行时读取 | 由 `AudioServer.get_mix_rate()` 返回，不得硬编码（EC-AD4）；WAV header 写入实际值 |

## Visual/Audio Requirements

VoiceRecorder 是 AutoLoad 单例，不直接持有 UI 节点或音效播放器（AudioStreamPlayer 仅用于录音回放）。以下规格描述各信号触发后其他系统的责任边界。

### 录制侧信号责任矩阵

| 信号 | RecordingInviteUI 职责 | AnimationHandler 职责 | 音效 |
|------|----------------------|----------------------|------|
| `recording_started` | 橙色圆钮视觉：激活态（颜色加深、脉冲动画）| 无（RECORDING_LISTEN 状态由 Ink `anim:RECORDING_LISTEN` 标签驱动，不经 VoiceRecorder 信号）| 无（开始录音静默，不打断孩子注意力）|
| `recording_saved` | 恢复静息态 | 无（后续 T-Rex 反应由 Ink 剧情续篇的 `anim:HAPPY` 标签驱动）| 无（正向反馈由 TtsBridge 发音 + AnimationHandler HAPPY 动画提供，VoiceRecorder 不额外叠加音效）|
| `recording_failed("too_short")` | **静默**恢复静息态；禁止红色✗、否定图标、任何惩罚视觉（P2 Anti-Pillar）| 无（T-Rex 不对短录音失败作出反应）| **无**（严禁任何否定音效；体验上孩子抬手→按钮恢复→剧情继续，无感知失败）|
| `recording_unavailable` | **无动画静默消失**；整个录音邀请 UI 消失，不留痕迹 | 无 | 无 |
| `recording_interrupted` | **S5-B1 修复**：从 RECORDING 状态转入 DISMISSING（静默退出，无错误提示）| 无（T-Rex 不对中断作出反应） | 无 |

### 回放侧信号责任矩阵（ParentVocabMap 家长端）

| 信号 | ParentVocabMap 职责 | 音频 |
|------|-------------------|------|
| `playback_started(path)` | 播放按钮显示进行中视觉（脉冲或进度指示）| VoiceRecorder AudioStreamPlayer 直接播放 WAV；走 Master 总线；**须将 `_playback_player.process_mode = Node.PROCESS_MODE_ALWAYS`**（默认 PAUSABLE 下 SceneTree 暂停时回放静默停止，违反 P3 承诺）|
| `playback_completed(path)` | 恢复播放按钮可用状态 | — |
| `playback_failed(path, reason)` | 灰化该条目播放按钮，不可再点击 | — |

**VoiceRecorder 本身不新增任何音效资产**。录音中的 T-Rex 视觉（举爪/RECORDING_LISTEN）、录音成功后的欢庆动画（HAPPY）均由 Ink 剧情标签通过 TagDispatcher → AnimationHandler 驱动，与 VoiceRecorder 信号链无直接关联。

## UI Requirements

VoiceRecorder 无独立 UI 场景或节点。录音相关 UI 完全委托给 RecordingInviteUI（#14）；回放相关 UI 完全委托给 ParentVocabMap（#17）。

### VoiceRecorder 对 RecordingInviteUI 的 UI 约束

| 约束 | 规格 | 依据 |
|------|------|------|
| 录音按钮最小尺寸 | ≥ 96dp（触屏主交互按钮推荐尺寸）| 技术偏好（所有交互元素最小 80dp，录音主按钮更大）|
| 录音中持续按下 | 须支持"持续按住"交互，不是点击切换（孩子松手即停录） | 技术偏好（Primary Input: 持续按下 — 录音按钮保持）|
| 错误静默化 | `recording_failed` 任何 reason 均不得显示错误文本或否定图标 | P2 Anti-Pillar；EC-RQ1 / EC-SM1 |
| DISABLED 态消失 | 收到 `recording_unavailable` 后，按钮及整个录音邀请面板须完整消失（不灰化、不遮挡） | Section B Player Fantasy；EC-P1 |
| 竖屏布局 | 录音 UI 仅设计竖屏方向，不支持横屏 | 技术偏好（仅竖屏方向）|

### VoiceRecorder 对 ParentVocabMap 的 UI 约束

| 约束 | 规格 |
|------|------|
| 文件不存在时灰化 | `play_recording()` 返回 `false` 时，ParentVocabMap 须灰化该播放按钮，不可再触发（EC-FS4）|
| 多条录音展示 | `get_recording_paths(word_id)` 返回 `Array[String]`（可能多条）；ParentVocabMap 须支持列表或分页展示，不假定单条 |
| 播放时长不确定 | WAV 回放时长取决于实际文件长度（≤ MAX_RECORDING_SECONDS）；ParentVocabMap 不得假设固定时长 |

## Acceptance Criteria

> **前置条件**：所有 AC（AC-3 至 AC-59）以 **AC-1a go/no-go 通过**为前提。若 AC-1a 失败，整个 VoiceRecorder 功能砍除，后续 AC 全部作废。
>
> **测试类型**：
> - **Logic/Integration（BLOCKING）**：须自动化测试通过，位于 `tests/unit/voice_recorder/` 和 `tests/integration/voice_recorder/`
> - **手动验证（ADVISORY）**：截图归档至 `production/qa/evidence/`

---

### go/no-go 前置门控

**AC-1a** [go/no-go — READY 状态] 在目标 Android 真机上，5 分钟内完成 `AudioStreamMicrophone` 初始化并将 `AudioEffectCapture` 成功挂载至 "Microphone" 总线 → VoiceRecorder 状态达到 `READY`，`is_recording_available()` 返回 `true`。（手动验证）

**AC-1b** [go/no-go — 试录音文件验证] AC-1a 通过后，执行一次完整录音流程（`start_recording()` → 按住 ≥ 150 ms → `stop_recording()`）→ `recording_saved` 信号发出，`user://recordings/` 目录下可观察到对应 WAV 文件实际存在（READY 状态不保证文件存在，仅首次录音后才生成）。（手动验证）

**AC-2** [go/no-go 失败路径] 若 **AC-1a** 在 5 分钟内未通过 → 整个 VoiceRecorder 功能立即切除，AC-3 至 AC-57 全部作废；InterruptHandler 中 `VoiceRecorder.interrupt_and_commit()` 调用因 `is_instance_valid()` 守卫静默跳过，其余游戏功能不受影响。切除决策须在窗口结束后 10 分钟内写入 `production/qa/` 记录。（手动）

---

### 1. 权限处理

**AC-3** [权限已授予] 设备已授予 `RECORD_AUDIO`，App 冷启动 → `_ready()` 检测权限，`_init_microphone()` 被调用，最终状态为 `READY`，`recording_unavailable` 信号未发出，`is_recording_available()` 返回 `true`。（自动）

**AC-4** [首次运行拒绝权限] 用户在系统权限对话框点击「拒绝」 → 状态转为 `DISABLED`，`recording_unavailable` 发出恰好一次，此后 `start_recording()` 返回 `false`，`is_recording_available()` 返回 `false`。（自动）

**AC-5** [DISABLED 会话内不可解除] DISABLED 状态在本次 App 会话内不可由任何游戏内 API 解除；重启 App 并补授权限后可重新进入 READY。（手动）

**AC-6a** [运行时撤销权限 — 达到阈值（逻辑，自动）] **前置条件**：VoiceRecorder 实现须暴露 `_capture_effect` 为可注入属性（或提供 `_inject_capture_mock(mock)` 接口），否则此 AC 无法自动化。Mock `AudioEffectCapture` 使 `_pcm_buffer` 永远不积累足够帧（模拟无输入）；连续调用 3 次 `start_recording()` + `stop_recording()` → 第 1、2 次 emit `recording_failed("too_short")` 且状态保持 READY；第 3 次后状态转为 `DISABLED`，`recording_unavailable` 发出恰好一次。（自动）

**AC-6b** [运行时撤销权限 — 真机验证（集成，手动）] 在目标 Android 设备上：App 运行中进入系统设置撤销 `RECORD_AUDIO` 权限 → 返回 App 连续触发 3 次录音操作 → 确认第 3 次后进入 `DISABLED`，RecordingInviteUI 消失。（手动；权限撤销场景须真机或模拟器验证，GUT Mock 无法覆盖 AudioEffectCapture 底层行为）

**AC-7** [失败计数器归零] 连续失败 2 次后一次录音成功（`recording_saved` 发出）→ 失败计数器归零；此后须再连续失败 3 次才触发 DISABLED，2 次不触发。（自动）

**AC-8** [PERMISSION_REQUESTING 期间调用 start_recording] 状态为 `PERMISSION_REQUESTING` 时调用 `start_recording("cat")` → 返回 `false`，状态保持，`recording_started` 未发出。（自动）

---

### 2. 状态机合法/非法转换

**AC-9** [合法：READY → RECORDING] READY 状态调用 `start_recording("apple")` → 返回 `true`，状态变为 `RECORDING`，`recording_started("apple")` 发出一次。（自动）

**AC-10** [合法：RECORDING → SAVING → READY] RECORDING 状态调用 `stop_recording()`（录音时长 ≥ MIN_RECORDING_MS）→ 返回 `true`，最终状态为 READY，`recording_saved` 发出。（自动）

**AC-11** [非法：start_recording 在 RECORDING] 再次调用 `start_recording("banana")` → 返回 `false`，状态不变，计时器不重置，`recording_started` 未发出。（自动）

**AC-12** [非法：stop_recording 在 READY] 返回 `false`，状态保持 READY，无文件写入。（自动）

**AC-13** [非法：stop_recording 在 SAVING] 返回 `false`，当前写盘操作完整完成，`recording_saved` 或 `recording_failed` 正常发出。（自动）

**AC-14** [非法：stop_recording 在 DISABLED] 返回 `false`，no-op，无崩溃。（自动）

**AC-15** [非法：start_recording 在 DISABLED] 返回 `false`，no-op，`recording_failed` 未发出。（自动）

**AC-16** [非法：start_recording 在 SAVING] 返回 `false`，旧录音 `recording_saved` 仍正常发出。（自动）

**AC-17** [非法：play_recording 在 RECORDING] 返回 `false`，`playback_failed(path, "recording_in_progress")` 发出，录音不中断。（自动）

**AC-18** [DISABLED 无出口转换] DISABLED 状态下调用任何公开 API 均不改变状态。（自动）

---

### 3. 正常录音流程

**AC-19** [完整录音路径] `start_recording("t_rex")` → 按住 ≥ MIN_RECORDING_MS（150 ms）→ `stop_recording()` → `recording_saved("t_rex", path)` 发出，path 匹配 `user://recordings/profile_\d+/t_rex_\d{8}T\d{6}Z\.wav`，文件在磁盘实际存在。（自动+集成）

**AC-20** [路径 append，不覆盖旧录音] 同一 `word_id = "apple"` 录音两次 → `get_recording_paths("apple")` 返回长度 == 2 的数组，两路径不同，两文件均存在。（自动）

**AC-21** [路径持久化至磁盘] 录音成功后 `ProfileManager.flush()` 在 `recording_saved` 发出的同步路径内被调用一次。（自动，Mock ProfileManager 验证调用顺序）

**AC-22** [录音目录首次自动创建] 目录不存在时，首次录音流程自动调用 `make_dir_recursive_absolute`，WAV 写入成功，`recording_saved` 发出，`recording_failed("dir_create_error")` 未发出。（集成）

**AC-23** [文件名字符安全] 含非字母数字字符的 `word_id` 生成的文件名通过正则 `^[a-zA-Z0-9_]+_\d{8}T\d{6}Z\.wav$` 验证，时间戳无冒号或斜杠。（自动）

---

### 4. WAV 文件格式（EC-RQ4 关键验收）

**AC-24** [ChunkSize 字段正确] WAV 文件偏移 4 处 uint32 == 总字节数 - 8（即 pcm_data_size + 36）；值为 pcm_data_size + 44 则 Fail。（自动，二进制解析）

**AC-25** [Subchunk2Size 字段正确] 偏移 40 处 uint32 == 总字节数 - 44（即 pcm_data_size）。（自动）

**AC-26** [SampleRate 使用实际采样率] 偏移 24 处 uint32 == `AudioServer.get_mix_rate()` 实际返回值；48000 Hz 设备上值为 48000 而非 44100。（自动）

**AC-27** [WAV 可被 Android 系统播放器解码] 目标真机用系统媒体播放器打开录音 WAV → 无"不支持格式"提示，播放进度条开始移动，并在 `[MIN_RECORDING_MS, MAX_RECORDING_SECONDS × 1000 + 500ms]` 范围内自然结束，无错误提示对话框。（手动，截图记录；测试设备可静音——此 AC 仅验证格式可解码性，不评估音质）

**AC-28** [play_recording 无 decode_error] 对正常录制流程生成的 WAV 调用 `play_recording(path)` → 返回 `true`，`playback_failed("decode_error")` 未发出。（自动）

---

### 5. 最小录音时长过滤

**AC-29** [低于 MIN_RECORDING_MS 被丢弃] 录音 < MIN_RECORDING_MS（150 ms）→ `recording_failed("too_short")` 发出，状态返回 READY，无新文件，`recording_paths` 未 append，flush 未调用。（自动，四项均须满足）

**AC-30** [MIN_RECORDING_FRAMES 使用实际采样率] 采样率 48000 Hz 时 MIN_RECORDING_FRAMES == 7200（非 6615）；44100 Hz 时为 6615。（自动，参数化单元测试）

**AC-31** [临界帧数边界值] `get_frames_available() == MIN_RECORDING_FRAMES` → 通过过滤，`recording_saved` 发出；`== MIN_RECORDING_FRAMES - 1` → 被拒绝，`recording_failed("too_short")` 发出。（自动）

---

### 6. 最大录音时长自动停止

**AC-32** [MAX_RECORDING_SECONDS 自动停止] 不调用 `stop_recording()`，等待 > 3 秒 → 计时器自动触发，`recording_saved` 发出；从 start 到 saved 总时长 ≤ 3 秒 + 1 帧。（自动）

**AC-33** [stop_recording 取消计时器] 1 秒内手动 stop → 3 秒时计时器不再触发，3 秒后状态为 READY，无第二次信号发出。（自动）

**AC-34a** [计时器先触发，stop_recording 后执行] GUT 设置：预填充 `_pcm_buffer`（帧数 ≥ MIN_RECORDING_FRAMES）；在 RECORDING 状态先 emit `Timer.timeout` 信号（状态→SAVING）→ 再调用 `stop_recording()` → 断言：`stop_recording()` 返回 `false`（no-op），`recording_saved` 发出恰好一次，磁盘 WAV 文件恰好一个，`ProfileManager.flush()` 调用次数 == 1。（自动）

**AC-34b** [stop_recording 先执行，计时器后触发] GUT 设置：预填充 `_pcm_buffer`（帧数 ≥ MIN_RECORDING_FRAMES）；在 RECORDING 状态先调用 `stop_recording()`（状态→SAVING）→ 再 emit `Timer.timeout` 信号 → 断言：Timer handler 检测状态非 RECORDING → no-op；`recording_saved` 发出恰好一次，磁盘 WAV 文件恰好一个，`ProfileManager.flush()` 调用次数 == 1。（自动）

---

### 7. Profile 切换安全性

**AC-35** [RECORDING 状态切换，同步无 await] `profile_switch_requested` 触发后同步完成：buffer 清空，计时器取消，`_current_word_id` 清除，状态变为 READY，`recording_saved` 和 `recording_failed` 均未发出。（自动）

**AC-36** [SAVING 状态切换，文件删除] `_discard_after_save = true` 被设置；`_write_wav()` 完成后文件被删除，路径不 append，flush 不执行，`recording_saved` 未发出，状态变为 READY。（自动）

**AC-37** [PERMISSION_REQUESTING 状态切换为 no-op] 状态保持 PERMISSION_REQUESTING；后续授权后 `is_recording_available()` 返回 `true`。（自动）

**AC-38** [切换后无跨档案数据污染] 档案 A 录音成功切换至档案 B → `get_recording_paths` 返回列表不包含档案 A 的路径。（集成）

**AC-39** [处理器无 await（静态检查）] `profile_switch_requested` 处理函数体内不含任何 `await` 关键字。（CI 静态检查：从 `autoload/voice_recorder.gd` 中提取 `profile_switch_requested` 处理函数体——**签名行起，至下一个相同或更小缩进级别的非空行止**；GDScript 无闭括号，须以 `awk` 或 Python 按缩进边界切片——在切片内执行 `grep -c 'await'`，断言结果为 0。此检查不覆盖被调函数内的间接 await，须代码审查补充保证。）

---

### 8. 回放侧功能

**AC-40** [正常回放] `play_recording(path)` → 返回 `true`，`playback_started` 和 `playback_completed` 均发出，无 `playback_failed`。（自动）

**AC-41** [文件不存在] `play_recording` 目标不存在 → 返回 `false`，`playback_failed(path, "file_not_found")` 发出，`playback_started` 未发出。（自动）

**AC-42** [损坏 WAV 文件] 文件存在但内容截断 → 返回 `false`，`playback_failed(path, "decode_error")` 发出。（自动）

**AC-43** [空路径或 null] `play_recording("")` → 返回 `false`，`playback_failed(path, "invalid_path")` 发出，无文件系统访问，无崩溃。（自动）

**AC-44** [未知 word_id] `get_recording_paths("nonexistent_word")` → 返回 `Array[String]`，长度 == 0，无 push_error，无崩溃。（自动）

**AC-45** [回放中抢占] 回放中再次调用 `play_recording(new_path)` → 旧回放停止，新文件开始播放，`playback_started(new_path)` 发出。（自动）

**AC-46** [stop_playback 无回放时调用] no-op，无崩溃，无信号发出。（自动）

**AC-47** [回放不改变录音状态] `playback_completed` 后 `is_recording_available()` 仍返回 `true`。（自动）

---

### 9. interrupt_and_commit 契约

**AC-48** [RECORDING + 帧数充足] `interrupt_and_commit()` 同步返回后：WAV 已写盘，路径已 append，flush 已调用，**`recording_saved(word_id, path)` 已发出**，**`recording_interrupted()` 已发出**，状态为 READY，`_current_word_id` 已清除。（自动，共 6 项断言；S5-B1 修复新增 `recording_interrupted` 验证）

**AC-49** [RECORDING + 帧数不足] buffer 丢弃，无写盘，flush 未调用，状态变为 READY，`recording_failed` 未发出，**`recording_interrupted()` 已发出**。（自动；S5-B1 修复新增 `recording_interrupted` 验证——此为关键路径：短录音帧数不足时 RIUI 依赖此信号退出 RECORDING 状态）

**AC-50** [SAVING 状态] `_commit_requested = true` 被设置；写盘完成后路径已 append，flush 已调用。（自动）

**AC-51** [其他状态均为 no-op] READY/DISABLED/UNINITIALIZED/PERMISSION_REQUESTING 状态调用 → 状态不变，flush 调用次数 == 0，无崩溃，**`recording_interrupted()` 已发出**（S5-B1 修复：无条件 emit）。（自动，参数化测试覆盖 4 种状态）

**AC-52** [严格同步，无 await（静态检查）] `interrupt_and_commit()` 函数体内不含任何 `await` 关键字。（CI 静态检查：从 `autoload/voice_recorder.gd` 中提取 `interrupt_and_commit()` 函数体——**签名行起，至下一个相同或更小缩进级别的非空行止**；GDScript 无闭括号，须以 `awk` 或 Python 按缩进边界切片——在切片内执行 `grep -c 'await'`，断言结果为 0。此检查不覆盖被调函数内的间接 await，须代码审查补充保证。）

**AC-53** [同一帧双触发自洽] 模拟同一帧两次调用 → WAV 文件写入一次，路径 append 一次，flush 调用一次。（自动，双调用单元测试）

---

### 10. P2 Anti-Pillar 合规

**AC-54** [recording_failed 静默化] `recording_failed` 发出（任意 reason）时，RecordingInviteUI 无错误文本、红色图标、否定动画；录音按钮恢复静息态，剧情继续推进。（手动，截图归档）

**AC-55** [recording_unavailable 静默消失] 信号发出后，RecordingInviteUI 整体消失，无灰化残留，无错误提示。（手动，截图）

**AC-56** [录音是邀请不是必须] 孩子不按录音按钮，剧情继续推进；无惩罚分数、无视觉惩罚、无 `recording_failed` 发出。（手动；**⚠️ DEFERRED — 依赖 RecordingInviteUI GDD #14 解决 OQ-5**：超时/跳过机制未设计前此 AC 的 Pass 条件无法定义；RecordingInviteUI GDD 批准后恢复验收。VoiceRecorder 本身不阻断剧情，阻断来自 RecordingInviteUI 的 UI 等待行为。）

**AC-57** [全零静音录音被接受] Mock AudioEffectCapture 返回全零 buffer 且帧数 ≥ MIN_RECORDING_FRAMES → `recording_saved` 发出，文件存在，无 `recording_failed`。（自动）

---

### 11. WAV 字段与竞态补充（/design-review RF-3）

**AC-58** [BYTE_RATE 字段使用实际采样率] WAV 文件偏移 28 处 uint32 == `AudioServer.get_mix_rate()` × 1 × 2；48000 Hz 设备上值为 96,000（非 88,200）。（自动，二进制解析，与 AC-26 同类）

**AC-59** [EC-PS2 双标志同时为 true，丢弃优先] GUT 设置：进入 SAVING 状态后，同时将 `_discard_after_save = true` 和 `_commit_requested = true`；`_write_wav()` 完成后断言：WAV 文件已删除（或未写入），路径未 append，`ProfileManager.flush()` 调用次数 == 0，`recording_saved` 未发出，两标志均已清除，状态为 READY。（自动；⚠️ R3 注解：当前同步实现下 SAVING 状态不可被外部信号抢入，此 AC 须以直接赋值标志的方式模拟触发条件，不依赖实际信号时序）

## Open Questions

**OQ-1** `[TO VERIFY Week 3]` — `OS.request_permission("RECORD_AUDIO")` 的回调信号名在 Godot 4.6 Android 须真机验证。**⚠️ 疑似实际签名为 `(permissions: PackedStringArray, granted: PackedInt32Array)`（数组形式），与 GDD 伪码中的单值形式不同**——若按单值实现，信号静默不触发，功能永久 DISABLED。Core Rule 4 代码块已标注为伪码；实现前必须查阅 Godot 4.6 正式文档并真机验证后适配。

**OQ-2** `[TO VERIFY Week 3]` — 负样本 PCM 值（`[-1.0, 0.0]` 范围）的 16-bit two's-complement 截断行为须真机 smoke test 验证。理论上 `int(clamp(sample, -1.0, 1.0) × 32767)` 应产生正确结果，但负零边界行为需确认（已标注于 Core Rule 8）。

**OQ-3** `[OPEN]` — 孤儿 WAV 文件清理策略（EC-FS3）：OOM Killer 中途杀死 App 时磁盘残留不完整 WAV 文件，当前设计不清理。是否需要 App 启动时扫描录音目录，删除未被 `recording_paths` 引用的文件？MVP 阶段暂未实现，延迟至 v1.1 或视磁盘占用情况决定。

**OQ-4** `[OPEN]` — 非 active 档案删除时的录音目录清理（Core Rule 12 注）：`active_profile_cleared` 仅在当前 active profile 被删除时触发，其他档案的录音目录无法通过此信号清理（文件孤存）。MVP 阶段接受孤儿录音目录，用户存储全满时手动清理；v1.1 可扩展 `SaveSystem.delete_profile()` 同时删除对应录音目录。

**OQ-5** `[OPEN — 委托 RecordingInviteUI GDD #14]` — RecordingInviteUI 录音邀请的超时/跳过机制：AC-56 验收标准"孩子不按录音按钮，剧情继续推进"的 Pass 条件依赖 RecordingInviteUI 定义录音邀请无响应的处理方式。VoiceRecorder 本身不阻断剧情——录音是邀请，`start_recording()` 不被调用时 VoiceRecorder 保持 READY，剧情继续；阻断来自 RecordingInviteUI 的 UI 等待行为。需在 RecordingInviteUI GDD (#14) 设计时确认：(A) 超时 N 秒自动推进（N = ？）；(B) 显式跳过按钮；(C) 两者结合。**AC-56 已标注 DEFERRED，待 RecordingInviteUI GDD 解决本 OQ 后恢复验收。**

~~**OQ-6**~~ ~~`[原 InterruptHandler OQ-6]` — VoiceRecorder GDD (#8) 未确认前，P3 录音路径保全路径存在接口假设风险~~
> ✅ **RESOLVED — VoiceRecorder GDD (#8) Approved 2026-05-07**：`interrupt_and_commit()` 已在本 GDD Core Rules §6（录制侧接口）中完整定义；RECORDING/SAVING/其他状态各自行为已在 Edge Cases §8 和 Dependencies §InterruptHandler 节确认；同步无 await 约束已加入 Dependencies 约束汇总。接口假设风险消除，IH OQ-6 同步关闭。
