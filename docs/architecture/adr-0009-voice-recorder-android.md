# ADR-0009: VoiceRecorder Android Recording and Playback Strategy

## Status
Accepted (2026-05-09)

## Date
2026-05-09

## Engine Compatibility

| Field | Value |
|-------|-------|
| **Engine** | Godot 4.6 |
| **Domain** | Audio |
| **Knowledge Risk** | LOW — No audio-specific breaking changes in 4.4–4.6. AudioStreamMicrophone, AudioEffectCapture, AudioServer APIs are stable. |
| **References Consulted** | `docs/engine-reference/godot/VERSION.md`; `docs/engine-reference/godot/modules/audio.md`; `docs/engine-reference/godot/breaking-changes.md` |
| **Post-Cutoff APIs Used** | None — all audio APIs predate LLM training cutoff |
| **Verification Required** | Week 3 Day 1 go/no-go: (1) AudioStreamMicrophone + AudioEffectCapture functional on target Android device; (2) OS.request_permissions_result callback signature (suspected array form); (3) Negative PCM sample two's-complement truncation behavior |

## ADR Dependencies

| Field | Value |
|-------|-------|
| **Depends On** | ADR-0004 (SaveSystem atomic write — VoiceRecorder flushes via ProfileManager.flush()); ADR-0005 (ProfileManager switch protocol — profile_switch_requested sync handler) |
| **Enables** | ADR-0015 (RecordingInviteUI — depends on VoiceRecorder interface); ParentVocabMap (recording playback) |
| **Blocks** | RecordingInviteUI implementation; ParentVocabMap recording playback; InterruptHandler interrupt_and_commit() contract |
| **Ordering Note** | Must be Accepted before Feature layer coding begins. Week 3 Day 1 go/no-go smoke test is the acceptance trigger for the entire recording feature. |

## Context

### Problem Statement

The game's core fantasy is "I teach T-Rex English words." VoiceRecorder is the system that makes this fantasy tangible — the child's voice becomes a keepsake that parents can replay months later. The system must record PCM audio via Android microphone, write WAV files to persistent storage, and provide playback — all while handling Android permission lifecycle, profile switching, and graceful degradation when hardware is unavailable.

### Constraints

- **Platform**: Android API 24+ only; no iOS in v1
- **Permission**: RECORD_AUDIO is a runtime permission; denial must silently disable the feature (P2 Anti-Pillar)
- **Performance**: `interrupt_and_commit()` must complete synchronously (<100ms) for InterruptHandler contract
- **Storage**: WAV files stored at `user://recordings/profile_{index}/`; VoiceRecorder is sole writer
- **Risk**: Go/no-go smoke test Day 1 of Week 3; if AudioStreamMicrophone cannot initialize in 5 minutes → cut feature entirely
- **GDScript**: No JNI; pure GDScript path via AudioStreamMicrophone + AudioEffectCapture

### Requirements

- 6-state machine: UNINITIALIZED → PERMISSION_REQUESTING → READY → RECORDING → SAVING (+ DISABLED)
- WAV format: 16-bit mono PCM, ChunkSize = pcm_data_size + 36 (not +44), SampleRate from AudioServer.get_mix_rate()
- Minimum recording filter: recordings < MIN_RECORDING_MS (150ms) are discarded
- Maximum recording: auto-stop at MAX_RECORDING_SECONDS (3s)
- Profile switch: synchronous handler, no await, discard in-progress recordings
- Interrupt contract: `interrupt_and_commit()` must be synchronous, called by InterruptHandler across 4 interrupt paths
- Playback: AudioStreamPlayer with PROCESS_MODE_ALWAYS for pause-resistant playback
- Privacy: recording directory deleted on profile deletion (recursive DirAccess cleanup)

## Decision

### Architecture

VoiceRecorder is an AutoLoad singleton with a 6-state machine and split recording/playback interfaces.

```
┌─────────────────────────────────────────────────────────┐
│  VoiceRecorder (AutoLoad Singleton, loading order 8)     │
│                                                          │
│  ┌──────────────────┐  ┌──────────────────────────────┐ │
│  │  RECORDING SIDE   │  │  PLAYBACK SIDE                │ │
│  │                   │  │                                │ │
│  │  start_recording()│  │  get_recording_paths(word_id) │ │
│  │  stop_recording() │  │  play_recording(path)         │ │
│  │  interrupt_and_   │  │  stop_playback()              │ │
│  │    commit()       │  │                                │ │
│  │                   │  │  signals:                      │ │
│  │  signals:         │  │    playback_started(path)      │ │
│  │    recording_     │  │    playback_completed(path)    │ │
│  │      started()    │  │    playback_failed(path,reason)│ │
│  │    recording_     │  └──────────────────────────────┘ │
│  │      saved()      │                                   │
│  │    recording_     │  ┌──────────────────────────────┐ │
│  │      failed()     │  │  AUDIO PATH                   │ │
│  │    recording_     │  │                                │ │
│  │      unavailable()│  │  "Microphone" bus (editor)     │ │
│  │    recording_     │  │  AudioEffectCapture → PCM buf  │ │
│  │      interrupted()│  │  AudioStreamPlayer (playback)  │ │
│  └──────────────────┘  └──────────────────────────────┘ │
│                                                          │
│  State: UNINIT|PERM_REQ|READY|RECORDING|SAVING|DISABLED │
│                                                          │
│  Subscribes:                                             │
│    ProfileManager.profile_switch_requested (sync)         │
│    ProfileManager.active_profile_cleared (user_deleted)   │
│                                                          │
│  Calls:                                                  │
│    ProfileManager.get_section("vocab_progress")           │
│    ProfileManager.flush()                                │
└─────────────────────────────────────────────────────────┘
```

### Key Interfaces

**Recording Side** (consumed by RecordingInviteUI, InterruptHandler):

```gdscript
func is_recording_available() -> bool:
    # Returns _state == READY

func start_recording(word_id: String) -> bool:
    # READY → RECORDING; false = wrong state

func stop_recording() -> bool:
    # RECORDING → SAVING; false = not recording

func interrupt_and_commit() -> void:
    # Sync (no await). Called by InterruptHandler across 4 paths.
    # RECORDING: write WAV if frames足够, or discard; always emit recording_interrupted()
    # SAVING: set _commit_requested = true
    # Other: no-op + emit recording_interrupted()
```

**Playback Side** (consumed by ParentVocabMap):

```gdscript
func get_recording_paths(word_id: String) -> Array[String]:
    # From current profile vocab_progress[word_id]["recording_paths"]

func play_recording(path: String) -> bool:
    # false if file doesn't exist

func stop_playback() -> void:
```

**Signals:**

```gdscript
# Recording side
signal recording_started(word_id: String)
signal recording_saved(word_id: String, path: String)
signal recording_failed(word_id: String, reason: String)
signal recording_unavailable()
signal recording_interrupted()  # S5-B1: unconditional emit in interrupt_and_commit()

# Playback side
signal playback_started(path: String)
signal playback_completed(path: String)
signal playback_failed(path: String, reason: String)
```

### WAV Write Protocol

1. Recording: each frame, `AudioEffectCapture.get_buffer()` returns `PackedVector2Array`; extract `.x` component, convert to int16, append to `PackedByteArray` (`_pcm_buffer`)
2. On stop/interrupt: build 44-byte WAV header as `PackedByteArray`, concatenate with `_pcm_buffer`, single `FileAccess.store_buffer(full_wav_bytes)` write
3. Header fields: `ChunkSize = pcm_data_size + 36` (NOT +44); `SampleRate/ByteRate` from `AudioServer.get_mix_rate()` (not hardcoded 44100)
4. **Never use `store_16()` per sample** — 132,300 GDScript calls on低端 Android = 1.8–5.3s main thread freeze

### Permission Lifecycle

```
_ready():
  if "RECORD_AUDIO" in OS.get_granted_permissions():
    _init_microphone() → READY or DISABLED
  else:
    OS.request_permission("RECORD_AUDIO")
    → PERMISSION_REQUESTING → _on_permissions_result()
    → READY (if granted + mic init OK) or DISABLED
```

⚠️ `OS.request_permissions_result` callback signature must be verified on Week 3 device — suspected array form `(PackedStringArray, PackedInt32Array)`.

### Profile Switch Contract

`profile_switch_requested` handler is synchronous (no await):
- RECORDING: stop capture, discard buffer, clear `_current_word_id`, state → READY
- SAVING: set `_discard_after_save = true`; after write completes, delete file, don't flush
- Other states: no-op

### Directory Cleanup

On `active_profile_cleared("user_deleted")`: recursively delete `user://recordings/profile_{deleted_index}/` directory. `DirAccess.remove_absolute()` cannot delete non-empty directories — must enumerate files first, delete each, then delete empty directory.

## Alternatives Considered

### Alternative 1: AudioStreamGenerator for recording
- **Description**: Use AudioStreamGenerator to capture microphone input programmatically
- **Pros**: More control over buffer management
- **Cons**: Not designed for recording; AudioEffectCapture is the intended Godot API for capturing bus audio; AudioStreamGenerator is for procedural audio generation
- **Rejection Reason**: Wrong tool for the job; AudioEffectCapture is purpose-built for this use case

### Alternative 2: JNI-based recording via Android SDK
- **Description**: Use Android Java/Kotlin APIs via GDNative/GDExtension for recording
- **Pros**: Full Android audio API access; known stable path
- **Cons**: Requires JNI bridge code; adds native dependency; violates "GDScript path, no JNI" constraint from game-concept.md; increases build complexity
- **Rejection Reason**: Game-concept.md TR-game-concept-005 mandates AudioStreamMicrophone + AudioEffectCapture (GDScript path, no JNI). Go/no-go gate will validate this path works.

### Alternative 3: Store recordings in app sandbox only (no gallery)
- **Description**: Save WAV files only in `user://recordings/` without any gallery integration
- **Pros**: Simpler; no permission concerns beyond RECORD_AUDIO
- **Cons**: Parents cannot discover recordings in system gallery; degrades P3 (成长日记) fantasy
- **Rejection Reason**: Recording paths are for ParentVocabMap playback, not gallery. Gallery integration is ADR-0003's domain (PostcardGenerator). VoiceRecorder only needs persistent storage.

## Consequences

### Positive

- Single AutoLoad handles both recording and playback; simple mental model
- Split interface (recording/playback) prevents accidental cross-calls
- Synchronous interrupt contract guarantees InterruptHandler's single-frame execution budget
- Profile switch handler eliminates cross-profile data contamination
- Silent degradation on permission denial preserves P2 Anti-Pillar (no child-visible failures)

### Negative

- Go/no-go risk: entire recording feature depends on AudioStreamMicrophone working on target Android device; feature cut if 5-minute test fails
- WAV files consume ~259KB each; 3 profiles × 5 words × multiple recordings = potential storage pressure
- `interrupt_and_commit()` synchronous constraint limits future async improvements
- `OS.request_permissions_result` callback signature uncertainty requires real device verification

### Risks

| Risk | Severity | Mitigation |
|------|:--------:|------------|
| AudioStreamMicrophone fails on target device | HIGH | Go/no-go smoke test Day 1 Week 3; 5-min window; feature cut if failed |
| OS.request_permissions_result wrong signature | HIGH | Pseudocode in GDD marks array form; verify on device; fallback to polling |
| WAV header ChunkSize off-by-8 (+44 vs +36) | MEDIUM | AC-24 binary validation test; Android system player decode check (AC-27) |
| Permission revoked at runtime | LOW | Consecutive too_short failures → DISABLED after threshold (EC-P2) |
| Negative PCM sample truncation | LOW | clampf() before int16 conversion; verify on device (EC-RQ2) |

## GDD Requirements Addressed

| GDD System | Requirement | How This ADR Addresses It |
|------------|-------------|--------------------------|
| voice-recorder.md TR-VR-001 | AutoLoad singleton; 6-state machine | Core decision: VoiceRecorder is AutoLoad with state machine |
| voice-recorder.md TR-VR-002 | AudioStreamMicrophone + AudioEffectCapture | Core decision: "Microphone" bus with AudioEffectCapture, editor-created |
| voice-recorder.md TR-VR-003 | PCM buffer accumulation; single store_buffer() write | WAV Write Protocol: PackedByteArray accumulation, single write |
| voice-recorder.md TR-VR-004 | WAV header ChunkSize+36; SampleRate from get_mix_rate() | WAV Write Protocol: header field specifications |
| voice-recorder.md TR-VR-005 | File naming: word_id + timestamp .wav | Decision: naming convention in Context |
| voice-recorder.md TR-VR-006 | MIN_RECORDING_FRAMES filter | Decision: minimum recording filter |
| voice-recorder.md TR-VR-007 | interrupt_and_commit() synchronous | Key Interfaces: sync contract definition |
| voice-recorder.md TR-VR-008 | Recording/playback interface separation | Architecture: split interface diagram |
| voice-recorder.md TR-VR-009 | PROCESS_MODE_ALWAYS for playback | Decision: playback AudioStreamPlayer mode |
| voice-recorder.md TR-VR-010 | profile_switch_requested sync handler | Profile Switch Contract: synchronous handler spec |
| voice-recorder.md TR-VR-011 | active_profile_cleared directory cleanup | Directory Cleanup: recursive delete specification |
| voice-recorder.md TR-VR-012 | OS.request_permissions_result signature | Permission Lifecycle: verification requirement noted |
| voice-recorder.md TR-VR-013 | PCM two's-complement verification | Engine Compatibility: verification required |
| voice-recorder.md TR-VR-014 | recording_paths sole writer | ADR Dependencies: aligns with ADR-0006 field ownership |
| interrupt-handler.md | interrupt_and_commit() called before request_chapter_interrupt() | Key Interfaces: sync contract enables IH ordering |
| recording-invite-ui.md | start/stop recording, signal subscription | Key Interfaces: recording side contract |
| parent-vocab-map.md | get_recording_paths, play_recording | Key Interfaces: playback side contract |

## Performance Implications

- **CPU**: PCM buffer accumulation is O(1) per frame (single get_buffer + append); WAV write is O(n) but n ≤ 264,600 bytes (<1ms)
- **Memory**: Peak = 2× PCM buffer during write (original + WAV with header); ~520KB worst case
- **Load Time**: No impact; VoiceRecorder._ready() only requests permission or initializes microphone
- **Storage**: ~259KB per 3-second WAV; 3 profiles × 5 words × 2 recordings = ~7.8MB worst case

## Validation Criteria

- AC-1a: AudioStreamMicrophone initializes on target Android device within 5 minutes (go/no-go)
- AC-1b: Full recording流程 produces valid WAV file (go/no-go)
- AC-24 to AC-27: WAV header fields correct, Android system player can decode
- AC-35 to AC-39: Profile switch safety (sync handler, no cross-profile contamination)
- AC-48 to AC-53: interrupt_and_commit() contract (sync, correct behavior across all states)

## Related Decisions

- ADR-0004 (SaveSystem atomic write) — VoiceRecorder flushes via ProfileManager.flush()
- ADR-0005 (ProfileManager switch protocol) — profile_switch_requested sync handler
- ADR-0006 (VocabStore formula) — recording_paths field ownership partition
- ADR-0007 (AutoLoad init order) — VoiceRecorder loads at position 8
- ADR-0003 (Android gallery save) — PostcardGenerator, not VoiceRecorder, handles gallery
