# TtsBridge

> **Status**: Approved — CD-GDD-ALIGN 2026-05-06 (CONCERNS resolved); /design-review fixes applied 2026-05-07 (RF-1~RF-5: cancel() ghost fix, AC-27 load_from_buffer rewrite, RATE_LIMIT_ERROR enum, warm_cache ADR ref, AC-35~42 added)
> **Author**: Zhang Shaocong + agents
> **Last Updated**: 2026-05-07
> **Implements Pillar**: P1 (看不见的学习), P2 (失败是另一条好玩的路)

## Overview

TtsBridge 是 NPC 发音的执行层：它接收来自 TagDispatcher 的词汇发音请求，按优先级依次尝试 AI TTS 提供商（HTTP 调用，支持指令控制角色声音）、系统 TTS（`DisplayServer.tts_speak()`）、文字高亮信号（`tts_fallback_to_highlight`），并选择当前可用的最佳路径发音。系统对上层调用方（TagDispatcher）暴露统一的语义 API（`speak(text, instruction)`、`stop()`、`is_available()`），屏蔽所有降级判断和 HTTP 细节。AI TTS 提供商实现一个可插拔合约（`TtsProvider`），支持在 Qwen3-TTS-Instruct、MiMo-V2.5-TTS 等服务间按配置切换；API Key 由家长在设置页面输入，经 SaveSystem 持久化。孩子每次选对英文单词后——T-Rex 跳起来的同时，单词也从 T-Rex 的嘴里说出来——TtsBridge 就是那个声音的幕后执行者。

> **CD-GDD-ALIGN Review**: CONCERNS→APPROVED 2026-05-06 — 零阻断。修复：C1（补充 MAX_PERCEIVED_LATENCY_MS + warm_cache() API）；C2（Player Fantasy 增加 P2 错误选择场景和 Tier 2 声音落差说明）；C3（Dependencies ChoiceUI 行标注为 TtsBridge 集成测试前置输入）。

> **架构决策参考**: 提供商可插拔实现模式 → See ADR-0002-TTS-PROVIDER (`docs/architecture/adr-0002-tts-provider.md`, Status: Proposed)

## Player Fantasy

孩子的手指抬起来的那一秒，T-Rex 跳起来——动画先落，角色声音紧跟：「T-REX!」暖的，慢的，带着一点夸张的兴奋。孩子感知到的不是「App 在发音」，而是「T-Rex 在庆祝——它高兴了，因为我选对了」。T-Rex 用自己的声音把那个词说出来，就像在说：「对，你懂我！」这是 P1（看不见的学习）在声音层的落地：孩子的动机是让 T-Rex 高兴，附带听到了这个词的发音——而不是反过来。

声音质感是这个时刻的灵魂。AI TTS 的指令控制让 T-Rex 的声音有角色性格——暖橙色的兴奋，语速稍慢，让每个音节都完整落进耳朵。孩子第一次听到「T-REX」被这样说出来，会模仿——在游戏里，在饭桌上，在半年后——那个词已经离开了屏幕，住进了孩子身体里。

当语音不可用时（无 API Key、无网络、无英文语音引擎），词语在屏幕上泛起 `--highlight-pulse` 金光脉冲——T-Rex 还在庆祝，只是用另一种方式让那个词「被看见」。P2 在这里的含义是：体验降级了，但不破圈；孩子依然感到「选对了」，剧情依然向前。

孩子选错词时，T-Rex 的声音不会变硬、不会变冷、不会带评判感——它说那个词的方式和选对时一样暖、一样兴奋，只是对应 P2 里那个好笑的困惑动画。孩子感知到的不是「我答错了被说」，而是「T-Rex 用这个词说了什么奇怪的东西，我想再听一遍」。这是 NPC_VOICE_INSTRUCTION 要求「Use the same warm tone for both correct and incorrect word moments」的原因——TtsBridge 在正确和错误路径上使用完全相同的发音指令，因为声音的情感方向由指令决定，而不是由选择结果决定。

家长在饭桌上听到孩子突然说出「T-Rex!」——语调和游戏里的角色声音一模一样——那一刻他们感受到的是：那个词真的被学会了，不是因为孩子背了单词，而是因为孩子想让 T-Rex 再高兴一次。

当家长没有配置 API Key、或处于 Tier 2（系统 TTS）路径时，T-Rex 的声音是机器人发音，角色个性会减弱。这是有意的取舍——Tier 2 总比无声好，庆祝叙事依然完整。Tier 2 不是设计缺陷，是「能跑的最低线」。

## Detailed Design

### Core Rules

1. **实例模型**：TtsBridge 是 AutoLoad 单例（全局名 `TtsBridge`），跨场景保持 HTTPRequest 子节点和 AudioStreamPlayer 子节点的生命周期。不在各场景中创建独立实例。

2. **TtsProvider 合约**（Path A — 见 ADR-0002-TTS-PROVIDER）：每个 AI TTS 提供商须实现以下接口（`@abstract class TtsProvider extends RefCounted`）：

   | 成员 | 签名 | 说明 |
   |------|------|------|
   | 方法 | `configure_credentials(api_key: String, endpoint: String) -> void` | 注入凭证；endpoint 必须为 HTTPS |
   | 方法 | `is_configured() -> bool` | 同步检查前提条件（Key 非空、endpoint 有效），不发网络请求 |
   | 方法 | `build_request_params(text: String, instruction: String) -> Dictionary` | 返回 `{url, headers, body}`；TtsBridge 使用此结果调用 HTTPRequest |
   | 方法 | `parse_response(body: PackedByteArray) -> AudioStream` | 解析 HTTP 200 响应体为 AudioStream；失败返回 null |
   | 方法 | `classify_error(http_code: int) -> int` | 返回 ProviderError 枚举值；仅在 http_code ≠ 200 时由 TtsBridge 调用 |

   TtsProvider **不发出信号**；TtsBridge 统一管理所有 HTTP I/O、降级逻辑和信号发出。`ProviderError`：`CONFIGURATION_ERROR = 0`（永久性，如 401/403 Key 无效）、`TRANSIENT_ERROR = 1`（临时性，如超时、502/503）、`RATE_LIMIT_ERROR = 2`（速率限制，如 429 Too Many Requests）。HTTP 400 由 TtsBridge 直接处理（push_error + Tier 2，不经 `classify_error`，不计入连续失败计数器）。

3. **三层降级链**：`speak()` 按以下优先级依次尝试：
   - **Tier 1**：AI TTS Provider（`is_configured() = true` 且 `_session_ai_healthy = true`）
   - **Tier 2**：System TTS（`DisplayServer.tts_get_voices()` 中含英文 voice；若列表无英文 voice 直接跳 Tier 3，不调用 `tts_speak()`）
   - **Tier 3**：发出 `tts_fallback_to_highlight(word_id: String, text: String)` 信号，由 UI 层响应显示 `--highlight-pulse` 脉冲

4. **状态机**（对调用方可见）：

   | 状态 | 描述 |
   |------|------|
   | `IDLE` | 无活跃发音请求 |
   | `SPEAKING` | 正在 HTTP 请求或音频播放中 |

   转换：`IDLE → SPEAKING`（speak() 调用）；`SPEAKING → IDLE`（播放完成 / stop() / 全部 tier 耗尽后 emit highlight）；`SPEAKING → SPEAKING`（新 speak() 中断旧的）。

5. **中断策略**：新 `speak()` 到来时，若 `_state == SPEAKING`，先调用 `_http_request.cancel_request()`（Tier 1 进行中时）或 `DisplayServer.tts_stop()`（Tier 2 进行中时）中止当前请求，再从降级链头部重新开始新的流程。被中断的发音不发出 `speech_completed`。⚠️ TtsProvider 接口（Path A）不提供 `cancel()` 方法——取消完全由 TtsBridge 在自身持有的 HTTPRequest 节点层面执行，Provider 对此不知情。

6. **AI TTS Session 健康管理**：维护 `_session_ai_healthy: bool`（启动时 `true`）。Tier 1 请求超时或返回 `TRANSIENT_ERROR` → `_consecutive_ai_failures++`；达到 `AI_FAILURE_THRESHOLD`（默认 2）→ `_session_ai_healthy = false`，本 session 后续所有调用直接跳 Tier 2。收到 `CONFIGURATION_ERROR`（401/403）→ 立即 `_session_ai_healthy = false`。收到 `RATE_LIMIT_ERROR`（429）→ **本次调用降级至 Tier 2，但不递增 `_consecutive_ai_failures`、不影响 `_session_ai_healthy`**（速率限制是临时性服务端约束，不代表 AI TTS 配置失效；区别于真正的网络故障）。Session 重置：下次 App 启动时恢复 `true`；`configure()` 重新调用时同样重置 `_session_ai_healthy = true`（为新凭证准备）。

7. **惰性音频缓存**：维护 `_audio_cache: Dictionary`（`word_id: String → AudioStream`）。首次 `speak(word_id, ...)` → Tier 1 成功后缓存 AudioStream；后续同 word_id 直接播放缓存，不再调用 API。调用 `configure()` 时清空整个缓存（Key 变更意味着声音模型可能不同）。Tier 2/3 不使用缓存。

8. **API Key 注入**：TtsBridge 暴露 `configure(provider_id: String, api_key: String, endpoint: String) -> void`。由启动协调者（GameRoot）在 SaveSystem 加载完成后调用；家长设置页修改 Key 时再次调用。TtsBridge 不持有 SaveSystem 引用，不自行读取存档。

9. **HTTP 请求格式**：向 API Endpoint 发 POST 请求（JSON body），包含 `text`（英文单词）和 `instruction`（角色声音指令，见 Tuning Knobs `NPC_VOICE_INSTRUCTION`）。超时：`TTS_HTTP_TIMEOUT_MS`（默认 5000ms）。响应：WAV 16-bit signed PCM（`AudioStreamWAV.new(); stream.data = body`）或 MP3（`AudioStreamMP3.new(); stream.data = body`），具体格式与提供商协商。⚠️ Godot 4.x 中 `load_from_buffer()` 不存在；须使用 `.data` 属性赋值。

10. **公开 API**：

    | 方法 | 签名 | 说明 |
    |------|------|------|
    | `speak` | `(word_id: String, text: String) -> void` | 发音请求，使用默认 NPC 指令 |
    | `speak_with_instruction` | `(word_id: String, text: String, instruction: String) -> void` | 带自定义指令的发音请求 |
    | `stop` | `() -> void` | 中止当前发音，返回 IDLE |
    | `configure` | `(provider_id: String, api_key: String, endpoint: String) -> void` | 注入 AI TTS 配置 |
    | `is_ai_configured` | `() -> bool` | 检查 AI TTS 是否已配置（用于设置页 UI 显示状态） |
    | `warm_cache` | `(word_id: String, text: String) -> void` | 静默预热：触发 Tier 1 HTTP 请求并缓存结果，不改变状态机、不 emit 任何信号。由 StoryManager 在场景加载时调用，解决首播延迟问题（满足 MAX_PERCEIVED_LATENCY_MS 目标）。若状态机正在 SPEAKING 或 ai 不可用，静默跳过。**实现遵循 ADR-0002 Path X 顺序队列机制**：`warm_cache()` 调用入队；`speak()` 调用清空队列并取消进行中的预热 HTTP 请求，自身立即优先执行；Tier 1 预热完成后结果写入 `_audio_cache`，下次同 `word_id` 的 `speak()` 直接命中缓存，不重复 HTTP 请求。详见 `docs/architecture/adr-0002-tts-provider.md`。 |

    TtsBridge 发出的信号：

    | 信号 | 签名 | 含义 |
    |------|------|------|
    | `speech_completed` | `(word_id: String)` | 发音播放完成（Tier 1 或 Tier 2） |
    | `tts_fallback_to_highlight` | `(word_id: String, text: String)` | 所有 TTS 路径不可用，UI 层显示文字高亮 |

---

### States and Transitions

| 状态 | 循环/单次 | 入口 | 出口 |
|------|---------|------|------|
| `IDLE` | 持续 | 初始化 / 发音完成 / `stop()` / Tier 3 信号发出后 | `speak()` 调用 |
| `SPEAKING` | 单次（有时长） | `speak()` | 播放完成 → IDLE；新 `speak()` → 重新 SPEAKING；`stop()` → IDLE |

---

### Interactions with Other Systems

| 调用方 / 订阅方 | 方向 | 接口 | 时机 |
|---------------|------|------|------|
| **TagDispatcher** | → TtsBridge | `speak(word_id, text)` | `SELECTED_CORRECT` 或 `NOT_CORRECT` 词汇事件触发时（TagDispatcher 决定是否调用） |
| **GameRoot** | → TtsBridge | `configure(provider_id, api_key, endpoint)` | App 启动 SaveSystem 加载完成后；家长修改 API Key 时 |
| **GameScene / 对话层（TBD）** | ← TtsBridge 信号 | `tts_fallback_to_highlight(word_id, text)` | Tier 3 降级时渲染 `--highlight-pulse` 脉冲；**ChoiceUI 不订阅（P2 保护 — 高亮会暗示正确答案，见 ChoiceUI GDD Rule 6）；GameScene GDD 须指定订阅方** |
| **StoryManager**（可选） | ← TtsBridge 信号 | `speech_completed(word_id)` | 若需等待发音完成再推进 Ink 节点（待 StoryManager GDD 确认） |

## Formulas

### 降级层选择（Fallback Tier Selection）

```
active_tier(ai_configured, ai_healthy, has_english_voice) =
    1    if ai_configured = true AND ai_healthy = true
    2    if (ai_configured = false OR ai_healthy = false) AND has_english_voice = true
    3    otherwise
```

| 变量 | 类型 | 值域 | 说明 |
|------|------|------|------|
| `ai_configured` | bool | {true, false} | `TtsProvider.is_configured()` 的返回值 |
| `ai_healthy` | bool | {true, false} | `_session_ai_healthy`，启动时 true |
| `has_english_voice` | bool | {true, false} | `DisplayServer.tts_get_voices()` 中含至少一个语言含 "en" 的 voice |

**输出**：int ∈ {1, 2, 3}。每次 `speak()` 调用前实时求值（非缓存）。Tier 3 为无条件兜底，`active_tier` 返回 3 时发 `tts_fallback_to_highlight` 信号。

---

### AI TTS Session 健康状态转换

```
ai_healthy_after(event, current_failures) =
    false       if event == CONFIGURATION_ERROR
    false       if event == TRANSIENT_ERROR AND current_failures + 1 >= AI_FAILURE_THRESHOLD
    true        if event == SPEECH_COMPLETED (reset consecutive counter to 0)
    unchanged   if event == RATE_LIMIT_ERROR (本次降级 Tier 2，但不修改健康状态或计数器)
    unchanged   otherwise
```

| 变量 | 类型 | 值域 | 说明 |
|------|------|------|------|
| `event` | enum | {SPEECH_COMPLETED, TRANSIENT_ERROR, CONFIGURATION_ERROR, RATE_LIMIT_ERROR} | 当前 Tier 1 请求结果 |
| `current_failures` | int | [0, AI_FAILURE_THRESHOLD] | 连续失败计数（成功后重置为 0） |
| `AI_FAILURE_THRESHOLD` | int | 默认 2 | 触发 session 停用的连续失败阈值 |

**输出**：bool（新 `_session_ai_healthy` 值）。`CONFIGURATION_ERROR` 立即置 false，与计数器无关。`RATE_LIMIT_ERROR`（HTTP 429）不修改计数器也不修改健康状态，仅本次请求降级至 Tier 2。Session 重置：下次 App 冷启动时恢复 `true`；`configure()` 调用时亦恢复 `true`。

---

### 音频缓存命中判断

```
cache_hit(word_id) =
    true     if word_id ∈ _audio_cache AND _audio_cache[word_id] != null
    false    otherwise
```

| 变量 | 类型 | 值域 | 说明 |
|------|------|------|------|
| `word_id` | String | VOCAB_WORD_IDS_CH1 中的任意 ID | 如 "ch1_trex"、"ch1_run" |
| `_audio_cache` | Dictionary | {} → 满载 5 条目 | word_id → AudioStream 的惰性填充字典 |

**输出**：bool。缓存命中时直接调用 `_audio_player.stream = _audio_cache[word_id]` + `play()`，绕过所有 HTTP 和 DisplayServer 调用。`configure()` 被调用时 `_audio_cache.clear()`，所有缓存条目失效。

## Edge Cases

| # | 边界情况 | TtsBridge 行为 | 调用方职责 |
|---|---------|---------------|-----------|
| E1 | **Tier 1 HTTP 超时**（5s 无响应） | 视为 `TRANSIENT_ERROR`，`_consecutive_ai_failures++`；若达阈值设 `_session_ai_healthy = false`；立即跳 Tier 2 | 无需处理；TtsBridge 内部兜底 |
| E2 | **speak() 在 SPEAKING 状态下调用**（新词汇事件） | 先调用活跃 provider 的 `cancel()`；被中断的词不发 `speech_completed`；从 Tier 1 头部重新开始新词汇 | TagDispatcher 可直接调用；TtsBridge 保证中断安全 |
| E3 | **API 返回 HTTP 200 但 `load_from_buffer()` 失败**（音频格式错误、body 为 JSON 错误体） | 视为 `TRANSIENT_ERROR`；不写入缓存；跳 Tier 2 | 无；TtsBridge 内部处理 |
| E4 | **configure() 在 SPEAKING 状态下调用**（家长在游戏中途改 Key） | 先 `stop()`（中断当前播放/请求），再清空缓存，再更新凭证 | GameRoot 应尽量避开游戏高峰；TtsBridge 保证安全处理 |
| E5 | **configure() 传入空 api_key 或空 endpoint** | 视为「撤销 AI TTS 配置」：`is_configured()` 返回 false，缓存清空，`_session_ai_healthy` 重置为 true（为下次有效配置准备） | 无 |
| E6 | **System TTS Android 静默完成无回调**（特定 OEM 不触发 utterance 结束事件） | `tts_speak()` 后同时启动看门狗定时器（`text.length × TTS_MS_PER_CHAR + TTS_TIER2_BUFFER_MS`）；超时后强制发 `speech_completed` 并转 IDLE | 无 |
| E7 | **speak() 传入空字符串或纯空白文本** | `text.strip_edges() == ""` → 立即发 `speech_completed(word_id)`，保持 IDLE，跳过全部 tier | TagDispatcher 不应传空文本；TtsBridge 是最后防线 |
| E8 | **speak() 传入超长文本**（> `MAX_TTS_TEXT_LENGTH`，默认 50 字符） | 截断至 `MAX_TTS_TEXT_LENGTH`，`push_warning()`，继续正常流程；word_id 仍为缓存键 | TagDispatcher 应只传单词（< 15 字符）；此截断为防御性保护 |
| E9 | **stop() 在 IDLE 状态下调用** | 空操作，不发信号，不改状态，不打印警告 | 任何时刻调用 `stop()` 均安全，调用方无需预检查 |
| E10 | **HTTP 请求未完成即被新 speak() 中断** | 丢弃未完成响应，**不写入缓存**；下次同 word_id 调用时重新发起请求（缓存未命中为预期行为） | TagDispatcher 的防抖由其自身设计决定，不属于 TtsBridge 职责 |

## Dependencies

### 上游依赖（TtsBridge 依赖的系统）

| 系统 | 依赖内容 | 契约 |
|------|---------|------|
| **Godot DisplayServer**（引擎内置） | `tts_get_voices()`、`tts_speak()`、`tts_stop()` | Tier 2 路径；须在 `tts_speak()` 前调用 `tts_get_voices()` 过滤英文 voice |
| **Godot HTTPRequest 节点**（引擎内置） | HTTP POST + `request_completed` 信号 | Tier 1 路径；作为 TtsBridge AutoLoad 的子节点持有 |
| **Godot AudioStreamPlayer 节点**（引擎内置） | `.stream` 属性赋值 + `.play()` | Tier 1 路径；作为 TtsBridge AutoLoad 的子节点持有；播放由 `AudioStreamMP3.new(); stream.data = body` 或 `AudioStreamWAV.new(); stream.data = pcm` 生成的 AudioStream。⚠️ Godot 4.x 中 `load_from_buffer()` 不存在 |
| **AI TTS API**（外部服务，用户配置） | HTTP POST 端点，返回 WAV/MP3 bytes | 通过 `configure(provider_id, api_key, endpoint)` 注入；无固定提供商依赖（可插拔） |
| **SaveSystem**（经 GameRoot 间接依赖） | API Key 和 endpoint 持久化存储 | TtsBridge 不直接调用 SaveSystem；GameRoot 读取 SaveSystem 后调用 `configure()`。若 SaveSystem 数据变更（家长修改 Key），GameRoot 负责二次调用 `configure()` |

### 下游依赖（依赖 TtsBridge 的系统）

| 系统 | 调用的 API | 依赖的接口契约 |
|------|-----------|--------------|
| **TagDispatcher** | `speak(word_id, text)` | 词汇事件触发时调用；TtsBridge 静默处理全部失败，TagDispatcher 无需预检查 availability |
| **GameRoot** | `configure(provider_id, api_key, endpoint)` | App 启动后 SaveSystem 加载完成时调用一次；API Key 变更时再次调用 |
| **GameScene / 对话层（TBD）** | 订阅 `tts_fallback_to_highlight(word_id, text)` 信号 | Tier 3 降级时渲染 `--highlight-pulse` 脉冲。**ChoiceUI 不订阅（P2 保护 — ChoiceUI GDD Rule 6 明确排除）；GameScene GDD 须指定具体订阅节点，否则 Tier 3 降级路径静默失效，P2 体验消失** |
| **StoryManager**（可选） | 订阅 `speech_completed(word_id)` 信号 | 若 StoryManager 需要等待发音完成再推进 Ink 节点，则订阅此信号；否则 `speech_completed` 为纯信息性信号。待 StoryManager GDD 确认 |

### 信号契约（TtsBridge 发出）

| 信号 | 签名 | 接收方 |
|------|------|--------|
| `speech_completed` | `(word_id: String)` | StoryManager（可选等待）；测试框架 |
| `tts_fallback_to_highlight` | `(word_id: String, text: String)` | GameScene / 对话层（TBD）；ChoiceUI 不订阅（P2 保护，ChoiceUI GDD Rule 6） |

## Tuning Knobs

| 旋钮名 | 当前值 | 安全范围 | 影响 |
|--------|--------|---------|------|
| `TTS_RATE` | 0.85 | 0.7–1.0 | Tier 2（系统 TTS）语速；来自 game-concept.md 全局设定，由 TtsBridge 传入 `DisplayServer.tts_speak()` 的 `rate` 参数 |
| `NPC_VOICE_INSTRUCTION` | `"Warm, enthusiastic dinosaur. Speak each English word slowly and clearly — as if discovering it for the first time and celebrating. Brief pause before the target word. Low-to-mid pitch, never shrill. Declarative intonation only, never questioning. Use the same warm tone for both correct and incorrect word moments — this voice celebrates the child's action, not the answer."` | 任意描述字符串 | Tier 1（AI TTS）默认角色指令；影响声音个性、情感色彩和语速感知。修改后缓存需主动清空才生效 |
| `AI_FAILURE_THRESHOLD` | 2 | 1–5 | 连续失败多少次后停用本 session 的 AI TTS；值越小则降级越激进（更安全但减少 AI TTS 机会），值越大则容忍更多网络抖动 |
| `TTS_HTTP_TIMEOUT_MS` | 5000 | 3000–10000 | AI TTS HTTP 请求超时毫秒数；低于 3000 在弱网条件下误判率高；高于 10000 会造成明显等待感 |
| `TTS_MS_PER_CHAR` | 80 | 60–120 | 系统 TTS 看门狗定时器：每个字符的预估播放毫秒数，用于计算 `text.length × TTS_MS_PER_CHAR + TTS_TIER2_BUFFER_MS` 的超时保护值 |
| `TTS_TIER2_BUFFER_MS` | 500 | 200–1000 | 系统 TTS 看门狗基础缓冲：防止 OEM 处理延迟误触发强制完成；过低导致提前截断，过高导致 SPEAKING 状态拖尾 |
| `MAX_TTS_TEXT_LENGTH` | 50 | 15–200 | speak() 传入文本的最大字符数；超出截断 + 警告。Chapter 1 最长词汇「Triceratops」= 12 字符，50 为防御值 |
| `HIGHLIGHT_DISPLAY_MS` | 600 | 400–900 | Tier 3 路径中，从 `tts_fallback_to_highlight` 发出到 `speech_completed` 发出的延迟毫秒数；使 Tier 3 时序与 Tier 1/2 的音频播放完成保持一致，防止 StoryManager 等调用方过早推进叙事 |
| `MAX_PERCEIVED_LATENCY_MS` | 400 | 300–600 | 「speak() 调用到用户可感知到声音开始播放」的最大目标延迟（主观感知阈值，非系统 timeout）。超过此值则「动画先落，声音紧跟」的 Player Fantasy 时刻断裂。**实现策略**：首播延迟由惰性缓存覆盖不到——StoryManager 应在场景加载时对 Chapter 1 全部词汇调用 warm_cache(word_id) 预热（TtsBridge 须提供该方法，内部静默调用 Tier 1 HTTP 不改变状态机、不 emit 任何信号）；若预热不可行（如无网络），降级至 Tier 2/3 的延迟也应保持在此目标内 |

`NPC_VOICE_INSTRUCTION` 属于内容设计常量，在 TtsBridge 代码中定义；`speak_with_instruction()` 路径允许 TagDispatcher 按词汇覆盖默认指令。

## Visual/Audio Requirements

### Tier 3 Text Highlight（`--highlight-pulse`）

当所有 TTS 路径不可用时，词语在屏幕上触发 glow swell 动效，由 ChoiceUI 响应 `tts_fallback_to_highlight` 信号渲染：

| 属性 | 值 |
|------|----|
| 动效名 | `--highlight-pulse` |
| 颜色 | ChoiceUI 主题金色 highlight 色 |
| Scale 曲线 | 1.0 → 1.10 → 1.0（放大后弹回） |
| Ease-in 时长 | 0.15 s |
| 顶点保持 | 0.15 s |
| Ease-out 时长 | 0.30 s |
| 总时长 | 0.60 s（= HIGHLIGHT_DISPLAY_MS） |
| 循环 | 否（单次脉冲，完成后恢复 scale=1.0） |

### Tier 3 本地提示音

| 属性 | 值 |
|------|----|
| 用途 | Tier 3 时补充听觉反馈（视觉 pulse 的伴音） |
| 时长 | ~180 ms |
| 音色 | 暖色调、清晰、非刺耳（类钟声或木鱼轻击） |
| 来源 | 本地 asset（不依赖任何 TTS 路径，离线可用） |
| 音量 | TTS Bus，target −12 LUFS（与 AI TTS 音量一致） |

### AI TTS 音频质量门槛

| 属性 | 要求 |
|------|------|
| 采样率 | ≥ 22050 Hz（低于 16000 Hz 视为音质不可接受，降至 Tier 2） |
| 格式偏好 | WAV 16-bit signed PCM（`AudioStreamWAV.new(); stream.data = pcm_bytes`）；MP3 可接受（`AudioStreamMP3.new(); stream.data = mp3_bytes`），最低 128 kbps。⚠️ `load_from_buffer()` 在 Godot 4.x 中不存在 |
| 音频 Bus | 独立 TTS Bus（与 Music/SFX 分离，便于独立音量控制） |
| 响度目标 | −12 LUFS（保持孩子耳朵舒适，不超过 Music Bus） |

### `speech_completed` 信号时序

| Tier | 触发时机 |
|------|---------|
| Tier 1（AI TTS） | 音频播放结束后立即 emit |
| Tier 2（System TTS） | 播放完成回调或看门狗超时后 emit |
| Tier 3（highlight） | `tts_fallback_to_highlight` 发出后 `HIGHLIGHT_DISPLAY_MS`（600 ms）延迟，再 emit `speech_completed` |

Tier 3 的 600 ms 延迟保证调用方（StoryManager 等）感知到一致的「发音已完成」语义，不因无声路径而过早推进叙事。

## UI Requirements

TtsBridge 自身不包含任何 UI 节点。与 UI 层的所有交互通过信号完成。

### Tier 3 订阅方（TBD — GameScene GDD 须声明）

**ChoiceUI 不订阅 `tts_fallback_to_highlight`（ChoiceUI GDD Rule 6，P2 保护）。** 高亮特定词汇按钮会隐性指示正确答案，违反 P2 设计柱「失败是另一条好玩的路」。

Tier 3 信号的订阅职责是 **MVP 已知缺口**：GameScene GDD 设计时须明确由哪个节点（对话文字节点 / 独立 overlay）订阅并渲染脉冲，同时播放 ~180 ms 暖色提示 SFX。在 GameScene GDD 批准前，Tier 3 降级路径不渲染任何视觉反馈（仅静默）。

### 家长设置页须声明的职责

| 职责 | 说明 |
|------|------|
| 提供 API Key 输入字段 | 家长输入 AI TTS 提供商的 API Key + Endpoint URL |
| 调用 `TtsBridge.configure()` | 输入确认后，Settings 页面通过 GameRoot 转发调用 `TtsBridge.configure(provider_id, api_key, endpoint)` |
| 显示配置状态 | 调用 `TtsBridge.is_ai_configured()` 决定 UI 上的「已配置 / 未配置」状态标签 |

## Acceptance Criteria

以下所有条目均为可测试的 Pass/Fail 标准，用 GUT 单元/集成测试验证。测试文件位置：`tests/unit/tts_bridge/test_tts_bridge.gd`

| # | 测试场景 | 期望结果 | 测试类型 |
|---|---------|---------|---------|
| **状态机** | | | |
| AC-01 | 初始化后查询状态 | `IDLE` | Unit |
| AC-02 | `IDLE` 状态调用 `speak(word_id, text)` | 立即转换为 `SPEAKING` | Unit |
| AC-03 | Tier 1 音频播放完成（mock `AudioStreamPlayer.finished` 信号） | 状态转为 `IDLE`；emit `speech_completed(word_id)` | Unit |
| AC-04 | `SPEAKING` 状态调用 `stop()` | 状态转为 `IDLE`；不 emit `speech_completed` | Unit |
| AC-05 | `SPEAKING` 状态调用新 `speak()` | 旧请求被取消；状态保持 `SPEAKING`（自跳转） | Unit |
| **降级层选择** | | | |
| AC-06 | `ai_configured=true`, `ai_healthy=true` | 发起 HTTP POST（Tier 1）；不调用 `DisplayServer.tts_speak()` | Unit |
| AC-07 | `ai_configured=false`, `has_english_voice=true` | 调用 `DisplayServer.tts_speak()`（Tier 2）；不发 HTTP 请求 | Unit |
| AC-08 | `ai_healthy=false`, `has_english_voice=true` | 跳过 Tier 1，直接 Tier 2 | Unit |
| AC-09 | `ai_configured=false`, `has_english_voice=false` | emit `tts_fallback_to_highlight(word_id, text)`（Tier 3）；两层 TTS 均不调用 | Unit |
| AC-10 | `ai_healthy=false`, `has_english_voice=false` | Tier 3；两层 TTS 均不调用 | Unit |
| AC-11 | `ai_healthy` 在两次 `speak()` 之间变为 false | 第二次重新评估降级层，不缓存前次 tier 决策 | Unit |
| **Session 健康管理** | | | |
| AC-12 | Tier 1 首次返回 `TRANSIENT_ERROR` | `_session_ai_healthy` 保持 `true`；`_consecutive_ai_failures = 1` | Unit |
| AC-13 | Tier 1 连续第二次 `TRANSIENT_ERROR`（达 `AI_FAILURE_THRESHOLD=2`） | `_session_ai_healthy = false`；后续 `speak()` 跳过 Tier 1 | Unit |
| AC-14 | Tier 1 返回 `CONFIGURATION_ERROR`（401/403） | `_session_ai_healthy` 立即置 `false`，与 `_consecutive_ai_failures` 值无关 | Unit |
| AC-15 | Tier 1 成功一次后（前序 failures=1） | `_consecutive_ai_failures` 重置为 0；`_session_ai_healthy` 保持 `true` | Unit |
| AC-16 | `_session_ai_healthy=false`, `has_english_voice=true` 时调用 `speak()` | 直接 Tier 2；HTTP 请求不被发出 | Unit |
| **惰性音频缓存** | | | |
| AC-17 | 首次 `speak(word_id)` 且 Tier 1 成功返回音频 | AudioStream 写入 `_audio_cache[word_id]` | Unit |
| AC-18 | 同 `word_id` 第二次调用 `speak()`，缓存存在 | 不发 HTTP 请求；直接播放缓存 AudioStream | Unit |
| AC-19 | `configure()` 后对已缓存 `word_id` 调用 `speak()` | 缓存已清空；重新发 HTTP 请求（缓存未命中） | Unit |
| AC-20 | Tier 1 请求被新 `speak()` 中断（未完成响应） | 未完成音频不写入缓存；下次同 `word_id` 仍为缓存未命中 | Unit |
| **中断策略** | | | |
| AC-21 | `SPEAKING` 状态下调用新 `speak(new_word_id)` | TtsBridge 直接调用 `_http_request.cancel_request()`（Tier 1 进行中时）或 `DisplayServer.tts_stop()`（Tier 2 进行中时）（mock spy 验证 — 注意：TtsProvider 接口无 `cancel()` 方法，此处验证的是 TtsBridge 自身的中止调用）；新请求从 Tier 1 开始 | Unit |
| AC-22 | 旧 `speak()` 被新 `speak()` 中断 | 旧 `word_id` 不 emit `speech_completed` | Unit |
| AC-23 | 新 `speak()` 完成后 | 新 `word_id` 正常 emit `speech_completed(new_word_id)` | Unit |
| **边界情况** | | | |
| AC-24 | `speak(word_id, "")` — 空字符串 | 立即 emit `speech_completed(word_id)`；状态保持 `IDLE`；三层 tier 均不调用 | Unit |
| AC-25 | `speak(word_id, text)` 中 text 长度 > `MAX_TTS_TEXT_LENGTH=50` | 截断至 50 字符后继续正常流程；`push_warning()` 被调用；`word_id` 作为缓存键不变 | Unit |
| AC-26 | `stop()` 在 `IDLE` 状态调用 | 无操作；不改状态；不 emit 信号；不抛异常（幂等） | Unit |
| AC-27 | HTTP 200 响应体无法构建有效 AudioStream（如 JSON 错误体、非 WAV/MP3 格式字节） | `parse_response()` 返回 `null`；视为 `TRANSIENT_ERROR`；`_consecutive_ai_failures++`；不写缓存；降级至 Tier 2（注：Godot 4.x 使用 `stream.data = body` 赋值，`load_from_buffer()` 不存在；`parse_response()` 须通过魔数检验字节格式） | Unit |
| AC-28 | `DisplayServer.tts_get_voices()` 中无英文 voice | 跳过 Tier 2，不调用 `DisplayServer.tts_speak()`；直接进入 Tier 3 | Unit |
| **Tier 3 时序** | | | |
| AC-29 | 进入 Tier 3 路径，`tts_fallback_to_highlight` 发出后 | `speech_completed` 在 `HIGHLIGHT_DISPLAY_MS=600ms` 后 emit（定时器驱动；GUT `advance_clock()` 可加速，无需等待真实 600ms） | Integration |
| AC-30 | Tier 3 路径完成 | 两信号均携带相同 `word_id`；`tts_fallback_to_highlight` 还携带原始 `text` | Integration |
| **configure() 行为** | | | |
| AC-31 | `configure(provider_id, "", endpoint)` — 空 `api_key` | `is_ai_configured()` 返回 `false` | Unit |
| AC-32 | 空 `api_key` 时（前序 `_session_ai_healthy=false`） | `_session_ai_healthy` 重置为 `true`，为下次有效配置准备 | Unit |
| AC-33 | `configure()` 在 `SPEAKING` 状态调用 | `stop()` 先执行（中断当前播放/请求）；再清空 `_audio_cache`；再更新凭证 | Unit |
| **speak_with_instruction** | | | |
| AC-34 | `speak_with_instruction(word_id, text, custom_instruction)` | HTTP 请求体含 `custom_instruction`（而非默认 `NPC_VOICE_INSTRUCTION`）；其余行为与 `speak()` 相同 | Unit |
| **HTTP 400 特殊路径** | | | |
| AC-35 | Tier 1 HTTP 请求返回 400 Bad Request | `push_error()` 被调用；TtsBridge 降级至 Tier 2；`_consecutive_ai_failures` 不递增；`_session_ai_healthy` 不变（HTTP 400 是调用方参数错误，不代表 AI TTS 服务不可用；Rule 6 直接处理，不经 `classify_error()`） | Unit |
| **warm_cache() 行为** | | | |
| AC-36 | IDLE 状态且 Tier 1 可用时调用 `warm_cache(word_id, text)` | HTTP 请求已发出；请求成功后 AudioStream 写入 `_audio_cache[word_id]`；状态保持 IDLE（预热不触发 SPEAKING） | Unit |
| AC-37 | SPEAKING 状态调用 `warm_cache(word_id, text)` | 无 HTTP 请求发出；无报错；静默跳过（speak 路径优先，预热入队后等待 IDLE） | Unit |
| AC-38 | `ai_configured=false` 或 `_session_ai_healthy=false` 时调用 `warm_cache(word_id, text)` | 无 HTTP 请求发出；无报错；静默跳过（Tier 1 不可用时预热无意义） | Unit |
| AC-39 | `warm_cache(word_id, text)` 成功完成后调用 `speak(word_id, text)` | 无新 HTTP 请求（缓存命中）；直接播放缓存 AudioStream | Unit |
| AC-40 | warm_cache HTTP 请求进行中时调用 `speak(word_id2, text2)` | 进行中的预热 HTTP 请求被取消（`_http_request.cancel_request()` 调用 mock spy 验证）；预热队列清空；`speak()` 自身正常发起 Tier 1 请求（speak 总是优先） | Unit |
| **System TTS 看门狗定时器（E6）** | | | |
| AC-41 | Tier 2 `tts_speak()` 调用后，看门狗计时器到期前 TTS 未发出 utterance 完成回调（模拟 OEM 静默） | 看门狗定时器到期（时长 = `text.length × TTS_MS_PER_CHAR + TTS_TIER2_BUFFER_MS`）后 emit `speech_completed(word_id)`；状态转为 IDLE（GUT `advance_clock()` 可加速，无需等待真实时长） | Integration |
| AC-42 | Tier 2 `tts_speak()` 调用后，TTS utterance 完成回调在看门狗到期前正常触发 | `speech_completed(word_id)` emit 一次；看门狗定时器被取消；信号不重复发出 | Unit |

**关键 mock 依赖**（实现前须与程序员对齐）：
- `HTTPRequest` 节点 → 伪造 `request_completed` 信号，注入任意 response body / error code
- `DisplayServer.tts_speak()` / `tts_get_voices()` → 通过依赖注入或 GUT `double()` mock
- `AudioStreamPlayer.finished` 信号 → 手动 emit 触发播放完成
- `_http_request.cancel_request()` → spy mock，验证 speak() 中断 warm 请求时被调用（AC-40）；TtsProvider 接口无 `cancel()` 方法（Path A，见 ADR-0002）
- Tier 3 定时器 → 使用 `get_tree().create_timer()`（非 `await`），GUT `advance_clock()` 可加速时间推进
- System TTS 看门狗定时器 → 同上，GUT `advance_clock()` 触发到期（AC-41/42）

## Open Questions

1. ~~**ADR-TTS-PROVIDER 待创建**~~：✅ **RESOLVED 2026-05-06** — `docs/architecture/adr-0002-tts-provider.md`（Status: Proposed）。TtsProvider 接口已定为 Path A（`@abstract extends RefCounted`，`build_request_params / parse_response / classify_error / configure_credentials / is_configured`）；PROVIDER_REGISTRY Dictionary；configure() 注入；warm_cache() 队列（Path X）。Core Rule 2 已同步更新。

2. **StoryManager 是否等待 `speech_completed`**：若 StoryManager 需要在发音完成后再推进 Ink 节点，则须订阅 `speech_completed` 信号；若不等待，`speech_completed` 为纯信息性信号。**待 StoryManager GDD 确认**。建议与 AnimationHandler 的 `animation_completed` 信号在 StoryManager GDD 中统一决策（两者语义相似）。

3. **AI TTS 提供商 HTTP 响应格式确认**：Detailed Design 中记录了 WAV 16-bit signed PCM 或 MP3 的期望响应格式。实际 Qwen3-TTS-Instruct 和 MiMo-V2.5-TTS 的响应格式（Content-Type、编码方式、错误体结构）须在实现前通过 API 文档或实测确认，以决定 `AudioStreamWAV.load_from_buffer()` 与 `AudioStreamMP3.load_from_buffer()` 的选择逻辑。

4. ~~**ChoiceUI highlight 接线方式**~~：✅ **RESOLVED 2026-05-08（/review-all-gdds F2）** — ChoiceUI GDD Rule 6（批准 2026-05-07）明确不订阅 `tts_fallback_to_highlight`（P2 保护）。Tier 3 订阅方为 MVP 已知缺口；由 **GameScene GDD** 设计时指定具体订阅节点。UI Requirements 节已更新。
