# ADR-0002: TTS Provider Interface and Selection Strategy

## Status
Proposed

## Date
2026-05-06

## Engine Compatibility

| Field | Value |
|-------|-------|
| **Engine** | Godot 4.6 |
| **Domain** | Audio / Scripting |
| **Knowledge Risk** | LOW — DisplayServer TTS API stable 4.4–4.6; no breaking audio changes |
| **References Consulted** | `docs/engine-reference/godot/VERSION.md`; `docs/engine-reference/godot/modules/audio.md`; `docs/engine-reference/godot/breaking-changes.md`; `docs/engine-reference/godot/current-best-practices.md` |
| **Post-Cutoff APIs Used** | `@abstract` decorator (Godot 4.5+); `DisplayServer.has_feature(FEATURE_TEXT_TO_SPEECH)` (stable) |
| **Verification Required** | Verify `DisplayServer.has_feature(FEATURE_TEXT_TO_SPEECH)` on target Android device (Week 1); verify AI TTS endpoint HTTPS reachable from Android APK; confirm `AudioStreamMP3.data` and `AudioStreamWAV.data` property names in Godot 4.6 |

## ADR Dependencies

| Field | Value |
|-------|-------|
| **Depends On** | ADR-0001 (defines StoryManager + TtsBridge co-existence as AutoLoad singletons) |
| **Enables** | TtsBridge implementation; StoryManager narration integration (Rule 4c) |
| **Blocks** | TtsBridge implementation (was OQ-1 in tts-bridge.md) |
| **Ordering Note** | TtsBridge code must not be written before this ADR is Accepted. ADR-0001 is Proposed but covers an independent domain — both can be Proposed concurrently. |

## Context

### Problem Statement
TtsBridge (AutoLoad singleton) requires a pluggable provider interface for AI TTS
vendors (Qwen3-TTS-Instruct, MiMo-V2.5-TTS). The interface must allow hot-swapping
providers via `configure()` without changing TtsBridge logic, must carry enough error
semantics to drive the 3-tier fallback (Tier 1 → Tier 2 → Tier 3), and must be
implementable in GDScript without C++ extensions.

### Constraints
- Engine: Godot 4.6, GDScript only (no C#, no GDExtension)
- Platform: Android API 24+; Android 9+ (API 28+) requires HTTPS for all HTTP traffic
- Timeline: 4-week MVP; TtsBridge must be testable before StoryManager integration (Week 2)
- API keys are parent-configured via parental settings; must never be hardcoded
- Adding a new TTS provider must not require modifying TtsBridge or StoryManager

### Requirements
- Stable GDScript interface callable regardless of active provider
- Support Qwen3-TTS-Instruct and MiMo-V2.5-TTS sharing the same interface
- Distinguish permanent errors (401/403) from transient errors (timeout, 502/503)
- Support `configure()` injection (GameRoot → TtsBridge → provider)
- Support `warm_cache()` pre-warming without state change or HTTP concurrency conflicts
- Android-compatible (no JNI, no additional permissions beyond INTERNET)
- Support test injection of mock providers for GUT tests

## Decision

Adopt **Path A: TtsBridge-owned HTTPRequest with class-based TtsProvider interface**:

1. `TtsProvider` is an `@abstract` GDScript class extending `RefCounted` — a
   request-builder and response-parser, not an autonomous speaker
2. TtsBridge owns a single `HTTPRequest` child node and drives all HTTP I/O
3. TtsProvider implements: `build_request_params()`, `parse_response()`,
   `classify_error()`, `configure_credentials()`, `is_configured()`
4. A `PROVIDER_REGISTRY` Dictionary maps `provider_id: String` → class reference
5. `warm_cache()` uses an internal queue (`_warm_cache_queue`) to send requests
   sequentially through the shared `HTTPRequest` node (Path X)

### TtsProvider Base Interface (Path A)

```gdscript
@abstract
class_name TtsProvider extends RefCounted
# extends RefCounted: automatic reference-counted lifecycle — no manual .free() needed
# @abstract: enforces override at class definition time (Godot 4.5+)

# Called by TtsBridge.configure() with parent-provided credentials
@abstract
func configure_credentials(api_key: String, endpoint: String) -> void:
    pass

@abstract
func is_configured() -> bool:
    return false

# TtsBridge calls this to get HTTP request parameters
# Returns: {url: String, headers: PackedStringArray, body: String}
# url MUST be HTTPS (Android 9+ blocks cleartext HTTP)
@abstract
func build_request_params(text: String, instruction: String) -> Dictionary:
    return {}

# TtsBridge calls this after HTTPRequest.request_completed (http_code == 200)
# Returns AudioStream on success, null on parse error
@abstract
func parse_response(body: PackedByteArray) -> AudioStream:
    return null

# TtsBridge calls this when http_code != 200
# Returns a ProviderError enum value
@abstract
func classify_error(http_code: int) -> int:
    return ProviderError.TRANSIENT_ERROR

enum ProviderError {
    CONFIGURATION_ERROR = 0,  # Permanent: 401/403 — disable AI TTS for session
    TRANSIENT_ERROR     = 1,  # Temporary: timeout, 502/503 — increment failure counter
    # HTTP 400 is NOT routed through this enum:
    #   TtsBridge handles it directly: push_error, fall to Tier 2, NO failure counter increment
}
```

> ⚠️ `TtsProvider` emits **no signals**. All flow control (fallback, cache, signals)
> is owned by TtsBridge. Provider is purely data transformation.

### Provider Registry

```gdscript
# Both provider scripts must be preloaded so class references resolve at const init.
# Values are class references (Script), not instances.
const PROVIDER_REGISTRY: Dictionary = {
    "qwen3-tts":    QwenTtsProvider,
    "mimo-v2.5-tts": MimoTtsProvider,
}
```

### configure() — Injection, Signal Lifecycle, Unknown ID Handling

```gdscript
func configure(provider_id: String, api_key: String, endpoint: String) -> void:
    # Unknown provider_id: push_error + clear provider (is_configured() → false)
    if not PROVIDER_REGISTRY.has(provider_id):
        push_error("TtsBridge: unknown provider_id '%s'" % provider_id)
        _active_provider = null
        _cache.clear()
        _warm_cache_queue.clear()
        return
    # No signal disconnect needed — Path A providers emit no signals
    _active_provider = PROVIDER_REGISTRY[provider_id].new()
    _active_provider.configure_credentials(api_key, endpoint)
    _cache.clear()              # New provider = new voice; invalidate AudioStream cache
    _warm_cache_queue.clear()   # Cancel pending warm requests for old provider
```

> ⚠️ `configure()` must be called before the first `speak()`. The call chain
> `GameRoot._ready()` → `configure()` → `begin_chapter()` → `speak()` ensures this
> in normal operation. Test scenes that call `begin_chapter()` directly must call
> `configure()` first or `is_configured()` will return false and Tier 2 activates.

### HTTP Request Flow (Path A)

```gdscript
# TtsBridge._speak_via_ai(text, instruction):
var params: Dictionary = _active_provider.build_request_params(text, instruction)
# params.url must be HTTPS — enforce at configure() time or assert here
_http_request.request(params.url, params.headers, HTTPClient.METHOD_POST, params.body)

# On _http_request.request_completed(result, http_code, headers, body):
if http_code == 200:
    var stream: AudioStream = _active_provider.parse_response(body)
    if stream == null:
        _fallback_to_tier2()  # parse error — treat as transient
        return
    # Sample rate check — permanent endpoint misconfiguration:
    if stream is AudioStreamWAV and stream.mix_rate < 16000:
        push_warning("TtsBridge: AI TTS sample rate %d Hz below minimum — disabling AI TTS" % stream.mix_rate)
        _disable_ai_tts_for_session()  # same path as CONFIGURATION_ERROR
        return
    _cache[_current_word_id] = stream
    _play_stream(stream)  # → speech_completed signal
elif http_code == 400:
    push_error("TtsBridge: AI TTS bad request (HTTP 400) — check build_request_params()")
    _fallback_to_tier2()  # NOT a failure counter increment
elif http_code in [401, 403]:
    var err: int = _active_provider.classify_error(http_code)  # CONFIGURATION_ERROR
    _disable_ai_tts_for_session()
    _fallback_to_tier3()  # → tts_fallback_to_highlight signal
else:
    var err: int = _active_provider.classify_error(http_code)  # TRANSIENT_ERROR
    _consecutive_ai_failures += 1
    if _consecutive_ai_failures >= AI_FAILURE_THRESHOLD:
        _disable_ai_tts_for_session()
    _fallback_to_tier2()
```

### Tier 2 Guard (has_feature check)

```gdscript
func _speak_via_system_tts(text: String) -> void:
    if not DisplayServer.has_feature(DisplayServer.FEATURE_TEXT_TO_SPEECH):
        # Platform has no TTS engine at all — go directly to Tier 3
        _fallback_to_tier3()
        return
    # Check for English voice (existing logic in tts-bridge.md)
    var voices: Array = DisplayServer.tts_get_voices_for_language("en")
    if voices.is_empty():
        _fallback_to_tier3()
        return
    DisplayServer.tts_speak(text, voices[0])
```

### AudioStream Construction (Godot 4.x — no load_from_buffer())

```gdscript
# MP3 response (preferred — smaller payload):
var stream := AudioStreamMP3.new()
stream.data = response_body  # PackedByteArray

# WAV/PCM response (raw PCM only — strip 44-byte RIFF header first):
var stream := AudioStreamWAV.new()
stream.data = response_body.slice(44)  # Strip WAV file header
stream.format = AudioStreamWAV.FORMAT_16_BITS
stream.mix_rate = 22050
stream.stereo = false
```

> ⚠️ `load_from_buffer()` does **NOT** exist in Godot 4.x.
> Use `.data = PackedByteArray` property assignment.

### warm_cache() Queue (Path X — sequential via shared HTTPRequest)

```gdscript
# TtsBridge state fields:
var _warm_cache_queue: Array[Dictionary] = []  # [{word_id, text}]
var _warming_active: bool = false

func warm_cache(word_id: String, text: String) -> void:
    if _cache.has(word_id) or not _active_provider.is_configured():
        return  # Already cached or no provider — silent no-op
    _warm_cache_queue.append({word_id = word_id, text = text})
    _process_warm_queue()

func _process_warm_queue() -> void:
    if _warming_active or _warm_cache_queue.is_empty():
        return
    _warming_active = true
    var item: Dictionary = _warm_cache_queue.pop_front()
    # Uses shared _http_request; result stored to _cache[item.word_id]
    # speak() cancels warm queue and sets _warming_active = false

# speak() always wins over warm_cache():
func speak(word_id: String, text: String) -> void:
    _warm_cache_queue.clear()
    _warming_active = false
    _http_request.cancel_request()  # Abort in-flight warm request if any
    # ... normal speak flow continues
```

### Test Injection Path (GUT tests only)

```gdscript
# Production code must NEVER call this method.
# Allows GUT tests to inject MockTtsProvider without modifying PROVIDER_REGISTRY.
func _set_provider_for_test(provider: TtsProvider) -> void:
    _active_provider = provider
```

### Architecture Diagram

```
GameRoot._ready()
  └→ TtsBridge.configure("qwen3-tts", api_key, https_endpoint)
          ↓
     PROVIDER_REGISTRY["qwen3-tts"].new()  →  QwenTtsProvider (extends RefCounted)
          ↓
     _active_provider: TtsProvider

TtsBridge.speak(word_id, text)
  ├── _cache hit → AudioStreamPlayer.play() → speech_completed           [Tier 1 cached]
  ├── is_configured() == false → _speak_via_system_tts()                 [Tier 2 direct]
  └── AI HTTP flow:
        _active_provider.build_request_params(text, NPC_VOICE_INSTRUCTION)
        _http_request.request(https_url, headers, POST, body)
                    ↓ request_completed
        200 → parse_response(body) → AudioStream
              mix_rate ≥ 16000 → cache + play → speech_completed         [Tier 1 live]
              mix_rate < 16000 → _disable_ai_tts → tts_fallback_to_highlight [Tier 3]
        400 → push_error → Tier 2 (no failure counter)
        401/403 → CONFIGURATION_ERROR → _disable_ai_tts → Tier 3
        5xx/timeout → TRANSIENT_ERROR → _consecutive_ai_failures++
                      ≥ threshold → _disable_ai_tts → Tier 2
                      < threshold → Tier 2

warm_cache(word_id, text) [called 5× in begin_chapter()]
  └── enqueue → _process_warm_queue() → sequential HTTP via _http_request
       (speak() clears queue + cancels active warm request immediately)
```

### Key Interfaces

```gdscript
# TtsProvider base class — contract all concrete providers implement
@abstract class_name TtsProvider extends RefCounted
func configure_credentials(api_key: String, endpoint: String) -> void  # @abstract
func is_configured() -> bool                                            # @abstract
func build_request_params(text: String, instruction: String) -> Dictionary  # @abstract
func parse_response(body: PackedByteArray) -> AudioStream               # @abstract
func classify_error(http_code: int) -> int                              # @abstract
enum ProviderError { CONFIGURATION_ERROR = 0, TRANSIENT_ERROR = 1 }

# TtsBridge public API (unchanged from GDD — StoryManager interface unaffected)
func configure(provider_id: String, api_key: String, endpoint: String) -> void
func speak(word_id: String, text: String) -> void
func cancel() -> void
func warm_cache(word_id: String, text: String) -> void
func _set_provider_for_test(provider: TtsProvider) -> void  # GUT only
signal speech_completed
signal speech_failed
signal tts_fallback_to_highlight(word_id: String)
```

## Alternatives Considered

### Alternative A: Single Hardcoded Provider Class
- **Description**: TtsBridge directly contains Qwen3-specific HTTP logic. API key injected via configure() but endpoint and format hardcoded.
- **Pros**: Simpler; no registry; no base class overhead
- **Cons**: Adding MiMo requires forking TtsBridge; no test injection; violates GDD requirement for provider-agnostic design
- **Rejection Reason**: tts-bridge.md explicitly requires provider-agnostic design. Single class locks TtsBridge to one vendor.

### Alternative B: TtsProvider extends Node
- **Description**: Providers are Node subclasses. TtsBridge calls `add_child`/`remove_child` during configure() to swap active provider. Each provider owns its HTTPRequest child.
- **Pros**: Provider lifecycle is explicit in scene tree; each provider owns its HTTP lifecycle
- **Cons**: configure() requires scene-tree operations; Node lifecycle adds complexity; RefCounted's automatic memory management is lost
- **Rejection Reason**: Both Godot Specialist and TD recommended Path A as simpler and consistent with GDD's "HTTPRequest as TtsBridge child" description.

### Alternative C: Resource-Based Provider Configuration
- **Description**: Each provider is a `.tres` Resource declaring endpoint, format, and instruction template. Shared HTTP logic in TtsBridge.
- **Pros**: Declarative; non-programmer-friendly
- **Cons**: Provider differences extend to request schema and streaming behavior — cannot be expressed as Resource fields without a mini-DSL
- **Rejection Reason**: Behavioral differences (request body format, response parsing) require code, not data.

### Alternative D: Autonomous Provider (speak/cancel/signals — original draft)
- **Description**: TtsProvider.speak() handles HTTP internally and emits speech_completed/speech_failed signals. TtsBridge wires to provider signals.
- **Pros**: More encapsulated per provider; matches original GDD TtsProvider description
- **Cons**: Requires TtsProvider to manage HTTPRequest Node — impossible without `extends Node`. Would require Path B (Node) with its added complexity.
- **Rejection Reason**: Path A achieves the same encapsulation with simpler lifecycle. Provider as RefCounted + request-builder/response-parser is the correct pattern.

## Consequences

### Positive
- Adding a provider = one new GDScript file + one `PROVIDER_REGISTRY` entry; TtsBridge unchanged
- Concurrent warm_cache() conflicts eliminated by Path X sequential queue
- `@abstract` enforces contract at class definition time; missing overrides caught immediately
- `extends RefCounted` = automatic memory management; no manual `.free()` on configure() swap
- `_set_provider_for_test()` enables full GUT test coverage including AC-21 (cancel spy)
- CONFIGURATION_ERROR / TRANSIENT_ERROR / HTTP 400 distinction drives precise fallback logic

### Negative
- TtsProvider interface changed from autonomous (speak/cancel/signals) to passive (build/parse/classify); `tts-bridge.md` Core Rule 2 TtsProvider section updated alongside this ADR
- Provider cannot independently control retry logic; TtsBridge owns all retry/fallback decisions
- warm_cache() is sequential; 5-word pre-warm in begin_chapter() fires one request at a time (~1–2s total background, non-blocking)
- Two provider scripts (QwenTtsProvider, MimoTtsProvider) preloaded into TtsBridge at AutoLoad init regardless of active provider

### Risks

| Risk | Severity | Mitigation |
|------|----------|------------|
| **R1: Tier 2 (DisplayServer.tts_speak) absent on OEM Android** | MEDIUM | `has_feature(FEATURE_TEXT_TO_SPEECH)` guard → direct Tier 3. Tier 3 (highlight pulse) always available. Verify Week 1. |
| **R2: AI TTS endpoint not HTTPS** | LOW | Validate HTTPS in `configure()`: if `not endpoint.begins_with("https://")` → push_error, set provider null |
| **R3: AudioStream API name differs in Godot 4.6** | LOW | Verify `AudioStreamMP3.data` and `AudioStreamWAV.data` property names before implementation. Do NOT use `load_from_buffer()`. |
| **R4: warm_cache() queue blocked by slow HTTP** | LOW | `speak()` always cancels `_http_request` and clears queue. Live speech always wins over pre-warm. |
| **R5: ProviderError misclassification** | LOW | GUT tests: 401 mock → CONFIGURATION_ERROR; timeout mock → TRANSIENT_ERROR; 400 mock → no failure counter increment |
| **R6: configure() called mid-speak()** | LOW | `configure()` calls `cancel()` before replacing provider. Document: callers must not call configure() mid-narration. |

## GDD Requirements Addressed

| GDD System | Requirement | How This ADR Addresses It |
|------------|-------------|--------------------------|
| tts-bridge.md | OQ-1: "ADR-TTS-PROVIDER 待创建：TtsProvider 接口定义、提供商切换机制、provider_id 注册表管理" | Defines `@abstract TtsProvider extends RefCounted`, PROVIDER_REGISTRY, configure() injection |
| tts-bridge.md | OQ-3: "warm_cache() 跨 provider 切换的缓存失效规则" | configure() clears _cache + _warm_cache_queue; Path X queue handles sequential warm |
| tts-bridge.md | Core Rule 2: TtsProvider 接口契约 | Revised to Path A interface: build_request_params, parse_response, classify_error, configure_credentials, is_configured |
| tts-bridge.md | Core Rule 3: 三层降级逻辑 | CONFIGURATION_ERROR → Tier 3; TRANSIENT_ERROR → failure counter; HTTP 400 → Tier 2 (no counter); has_feature() → Tier 3 if Tier 2 absent |
| tts-bridge.md | Core Rule 4: warm_cache() 预热约束 | Path X sequential queue; speak() cancels queue; configure() clears queue |
| story-manager.md | Rule 4c: TtsBridge narration step | TtsBridge.speak(word_id, text) public interface unchanged from StoryManager perspective |

## Performance Implications
- **CPU**: HTTPRequest is async; no frame blocking. Path X queue overhead: <0.1ms per enqueue.
- **Memory**: AudioStream cache per word_id: ~66 KB (MP3, 1.5s) or ~132 KB (WAV PCM, 22050 Hz). 5 words Chapter 1 → ~330 KB peak. Well within 256 MB ceiling.
- **Load Time**: warm_cache() sequential queue — 5 requests × 200–400ms each = ~1–2s total background pre-warm during begin_chapter(). Non-blocking from player perspective.
- **Network**: HTTPS required. One request per uncached word_id. Chapter 1 warm: 5 requests during begin_chapter().

## Migration Plan
Provider API schema change (e.g., Qwen3 updates request format):
1. Update `QwenTtsProvider.build_request_params()` and `parse_response()` only
2. No changes to TtsBridge, StoryManager, TagDispatcher, or ChoiceUI
3. Re-run TtsProvider GUT tests to verify error classification

Adding a third provider (e.g., local TTS server):
1. Create `LocalTtsProvider.gd` extending TtsProvider
2. Add `"local-tts": LocalTtsProvider` to PROVIDER_REGISTRY
3. Done — TtsBridge needs no changes

## Validation Criteria
1. `QwenTtsProvider.build_request_params("hello", instruction)` returns `{url: "https://...", headers: [...], body: "..."}` — url is HTTPS
2. `TtsBridge.configure("qwen3-tts", valid_key, https_endpoint)` → `is_configured() == true`
3. `TtsBridge.configure("unknown-provider", ...)` → push_error emitted + `is_configured() == false`
4. Mock HTTP 401 → `classify_error(401)` returns `ProviderError.CONFIGURATION_ERROR`
5. Mock HTTP 504 → `classify_error(504)` returns `ProviderError.TRANSIENT_ERROR`
6. Mock HTTP 400 → TtsBridge falls to Tier 2; `_consecutive_ai_failures` unchanged
7. `warm_cache()` × 5 executes sequentially (verified by GUT MockHTTPRequest)
8. `speak()` during active warm_cache() → queue cleared, speak fires immediately
9. `DisplayServer.has_feature(FEATURE_TEXT_TO_SPEECH)` called before tts_speak() on Android device — **Week 1 gate**
10. All 5 Chapter 1 words warm-cached before first `continue_story()` call — **Week 2 gate**

## Related Decisions
- design/gdd/tts-bridge.md — TtsBridge GDD (Core Rule 2 TtsProvider interface updated to Path A)
- docs/architecture/adr-0001-inkgd-runtime.md — AutoLoad co-existence (StoryManager + TtsBridge)
- docs/engine-reference/godot/VERSION.md — Engine version and post-cutoff risk reference
