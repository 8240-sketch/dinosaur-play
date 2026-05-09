# ADR-0024: TtsBridge Cache, Watchdog, and Latency Details

## Status
Accepted (2026-05-09)

## Date
2026-05-09

## Engine Compatibility

| Field | Value |
|-------|-------|
| **Engine** | Godot 4.6 |
| **Domain** | Audio |
| **Knowledge Risk** | LOW — TtsBridge uses standard AudioStreamPlayer, HTTPRequest, and Timer |
| **References Consulted** | `docs/engine-reference/godot/VERSION.md` |
| **Post-Cutoff APIs Used** | None |
| **Verification Required** | (1) System TTS watchdog timer fires correctly on OEM silent completion; (2) Lazy cache clears on configure() |

## ADR Dependencies

| Field | Value |
|-------|-------|
| **Depends On** | ADR-0002 (TTS Provider Interface) |
| **Enables** | None — extends existing TtsBridge specification |
| **Blocks** | TtsBridge implementation details |
| **Ordering Note** | ADR-0002 must be Accepted. |

## Context

### Problem Statement

ADR-0002 covers the TTS provider interface and three-tier fallback chain, but several TtsBridge implementation details lack formal documentation: lazy audio cache behavior, System TTS watchdog timer, MAX_PERCEIVED_LATENCY_MS target, and the P2 protection rule that ChoiceUI must NOT subscribe to tts_fallback_to_highlight.

### Requirements

- Lazy audio cache: word_id → AudioStream; cleared on configure()
- System TTS watchdog: timer for OEM silent completion detection
- MAX_PERCEIVED_LATENCY_MS = 400ms target for first-play latency
- P2 protection: ChoiceUI must NOT subscribe to tts_fallback_to_highlight

## Decision

### Lazy Audio Cache

```gdscript
var _audio_cache: Dictionary = {}  # word_id → AudioStream

func speak(word_id: String, text: String) -> void:
    if _audio_cache.has(word_id):
        _play_cached(_audio_cache[word_id])
        return
    # Cache miss → fetch from provider or system TTS
    _fetch_and_play(word_id, text)

func warm_cache(word_id: String, text: String) -> void:
    # Silent pre-fetch; does not interrupt current playback
    if _audio_cache.has(word_id): return
    _fetch_silent(word_id, text)

func configure(provider_id: String, api_key: String, endpoint: String) -> void:
    _audio_cache.clear()  # new provider = new voice = invalidate cache
```

### System TTS Watchdog

When Tier 2 (System TTS) is active, some OEM implementations report completion immediately without actually speaking. A watchdog timer detects this:

```gdscript
const SYSTEM_TTS_WATCHDOG_MS: int = 3000  # max expected speech duration

func _speak_system_tts(text: String) -> void:
    DisplayServer.tts_speak(text, voice_id)
    _watchdog_timer.start(SYSTEM_TTS_WATCHDOG_MS / 1000.0)

func _on_watchdog_timeout() -> void:
    # If speech_completed hasn't fired, assume OEM silent completion
    # Fall through to Tier 3 (highlight signal)
    _emit_highlight_fallback()
```

### MAX_PERCEIVED_LATENCY_MS

Target: first word spoken within 400ms of choices_ready signal. This constrains:
- warm_cache() must pre-fetch during narrative advance (not at choice time)
- Cache hit path must be <10ms (AudioStreamPlayer.play())
- Cache miss path: HTTP timeout is 5000ms (TTS_HTTP_TIMEOUT_MS), but warm_cache should prevent misses

### P2 Protection: ChoiceUI Subscription Ban

```gdscript
# In TtsBridge — documented constraint:
# tts_fallback_to_highlight signal must NOT be subscribed by ChoiceUI.
# Reason: Highlighting one button = visual "correct answer" indicator = violates P2.
# GameScene subscribes for Tier 3 visual feedback, but NOT on choice buttons.
```

This is enforced by convention (code review), not by runtime guard.

## GDD Requirements Addressed

| GDD System | Requirement | How This ADR Addresses It |
|------------|-------------|--------------------------|
| tts-bridge.md TR-tts-bridge-004 | Lazy audio cache | _audio_cache Dictionary with warm_cache() pre-fetch |
| tts-bridge.md TR-tts-bridge-008 | System TTS watchdog timer | _watchdog_timer for OEM silent completion |
| tts-bridge.md TR-tts-bridge-009 | MAX_PERCEIVED_LATENCY_MS = 400 | Target documented; warm_cache prevents cache misses |
| tts-bridge.md TR-tts-bridge-010 | ChoiceUI NOT subscribe highlight | Documented P2 constraint; code review enforced |

## Consequences

- **Warm cache eliminates perceived latency**: Pre-fetched words play instantly
- **Watchdog handles OEM quirks**: Silent TTS completion detected and falls through to Tier 3
- **P2 protection documented**: ChoiceUI highlight ban is formally specified

## Related Decisions

- ADR-0002: TTS Provider Interface (provider API, fallback chain)
- ADR-0010: StoryManager (warm_cache called during begin_chapter)
- design/gdd/tts-bridge.md — TtsBridge GDD
