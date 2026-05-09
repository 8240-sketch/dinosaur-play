# Architecture Review Report

| Field | Value |
|-------|-------|
| **Date** | 2026-05-09 |
| **Engine** | Godot 4.6 Standard (non-Mono) |
| **GDDs Reviewed** | 18 / 18 (full coverage) |
| **ADRs Reviewed** | 16 / 16 (ADR-0001 through ADR-0016) |
| **Review Mode** | full |

---

## Phase 2: Technical Requirements Summary

Total technical requirements extracted: **176** across 18 GDD systems.

| System | TR Count | Layer |
|--------|:--------:|-------|
| SaveSystem | 9 | Foundation |
| ProfileManager | 15 | Foundation |
| VocabStore | 10 | Foundation |
| TtsBridge | 10 | Core |
| AnimationHandler | 10 | Core |
| InterruptHandler | 12 | Core |
| StoryManager | 12 | Feature |
| TagDispatcher | 9 | Feature |
| VoiceRecorder | 14 | Feature |
| ChoiceUI | 10 | Presentation |
| MainMenu | 13 | Presentation |
| HatchScene | 13 | Presentation |
| NameInputScreen | 10 | Presentation |
| RecordingInviteUI | 11 | Presentation |
| VocabPrimingLoader | 9 | Presentation |
| ParentVocabMap | 9 | Feature |
| PostcardGenerator | 8 | Feature |
| Chapter2Teaser | 7 | Polish |

---

## Phase 3: Traceability Matrix

### Coverage Summary

| Status | Count | % |
|--------|:-----:|:---:|
| ✅ Covered | 129 | 73.3% |
| ⚠️ Partial | 7 | 4.0% |
| ❌ Gap | 40 | 22.7% |
| **Total** | **176** | **100%** |

**Previous review (2026-05-09):** 58 covered (33%), 22 partial (12%), 96 gaps (55%).
**Improvement:** +71 covered, -15 partial, -56 gaps. ADR-0009~0016 drove the majority of gains.

### Foundation Layer (34 TRs)

| TR-ID | System | Requirement | ADR | Status |
|-------|--------|-------------|-----|:------:|
| TR-save-system-001 | SaveSystem | Single I/O entry point | ADR-0004 | ✅ |
| TR-save-system-002 | SaveSystem | File naming convention | ADR-0004 | ✅ |
| TR-save-system-003 | SaveSystem | Atomic write sequence | ADR-0004 | ✅ |
| TR-save-system-004 | SaveSystem | DirAccess.rename() return check | ADR-0004 | ✅ |
| TR-save-system-005 | SaveSystem | _migrate_to_v2() additive-only | ADR-0004 | ✅ |
| TR-save-system-006 | SaveSystem | .tmp recovery on _ready() | ADR-0004 | ✅ |
| TR-save-system-007 | SaveSystem | store_* returns bool (4.4) | ADR-0004 | ✅ |
| TR-save-system-008 | SaveSystem | Schema v2 structure | ADR-0004 | ✅ |
| TR-save-system-009 | SaveSystem | MAX_SAVE_PROFILES = 3 | ADR-0004 | ✅ |
| TR-profile-manager-001 | ProfileManager | Single _active_data authority | ADR-0005 | ✅ |
| TR-profile-manager-002 | ProfileManager | get_active_data() returns reference | ADR-0005 | ✅ |
| TR-profile-manager-003 | ProfileManager | Section-level access via get_section() | ADR-0005 | ✅ |
| TR-profile-manager-004 | ProfileManager | Single flush entry point | ADR-0005 | ✅ |
| TR-profile-manager-005 | ProfileManager | switch_to_profile() 7-step sequence | ADR-0005 | ✅ |
| TR-profile-manager-006 | ProfileManager | begin_session() called by MainMenu | ADR-0014 | ✅ |
| TR-profile-manager-007 | ProfileManager | is_first_launch() guard | ADR-0005 | ⚠️ |
| TR-profile-manager-008 | ProfileManager | Profile section write permission | ADR-0006 | ✅ |
| TR-profile-manager-009 | ProfileManager | Four-state machine | ADR-0005 | ✅ |
| TR-profile-manager-010 | ProfileManager | profile_switch_requested no await | ADR-0005 | ✅ |
| TR-profile-manager-011 | ProfileManager | delete_profile() 5-step sequence | — | ❌ |
| TR-profile-manager-012 | ProfileManager | create_profile() v2 default structure | — | ❌ |
| TR-profile-manager-013 | ProfileManager | profile_exists() delegates to SaveSystem | — | ❌ |
| TR-profile-manager-014 | ProfileManager | NAME_MAX_LENGTH = 20 | — | ❌ |
| TR-profile-manager-015 | ProfileManager | parent_map_hint_dismissed field | — | ❌ |
| TR-vocab-store-001 | VocabStore | Two-layer memory state | ADR-0006 | ✅ |
| TR-vocab-store-002 | VocabStore | record_event() EventType enum | ADR-0006 | ✅ |
| TR-vocab-store-003 | VocabStore | Gold star award formula | ADR-0006 | ✅ |
| TR-vocab-store-004 | VocabStore | Float cast int/int truncation | ADR-0006 | ✅ |
| TR-vocab-store-005 | VocabStore | is_learned monotonic | ADR-0006 | ✅ |
| TR-vocab-store-006 | VocabStore | recording_paths VoiceRecorder only | ADR-0006 | ✅ |
| TR-vocab-store-007 | VocabStore | profile_switch_requested sync | ADR-0006 | ✅ |
| TR-vocab-store-008 | VocabStore | begin/end chapter session | ADR-0006 | ✅ |
| TR-vocab-store-009 | VocabStore | Gold star flush via ProfileManager | ADR-0006 | ✅ |
| TR-vocab-store-010 | VocabStore | NOT_CORRECT no negative feedback | ADR-0006 | ✅ |

### Core Layer (42 TRs)

| TR-ID | System | Requirement | ADR | Status |
|-------|--------|-------------|-----|:------:|
| TR-tts-bridge-001 | TtsBridge | AutoLoad + TtsProvider pluggable | ADR-0002 | ✅ |
| TR-tts-bridge-002 | TtsBridge | Three-tier fallback chain | ADR-0002 | ✅ |
| TR-tts-bridge-003 | TtsBridge | AI session health threshold | ADR-0002 | ✅ |
| TR-tts-bridge-004 | TtsBridge | Lazy audio cache | — | ❌ |
| TR-tts-bridge-005 | TtsBridge | Interrupt: new speak cancels | ADR-0002 | ✅ |
| TR-tts-bridge-006 | TtsBridge | warm_cache() preloading | ADR-0002 | ✅ |
| TR-tts-bridge-007 | TtsBridge | HTTP POST / 5000ms timeout | ADR-0002 | ✅ |
| TR-tts-bridge-008 | TtsBridge | System TTS watchdog timer | — | ❌ |
| TR-tts-bridge-009 | TtsBridge | MAX_PERCEIVED_LATENCY_MS = 400 | — | ❌ |
| TR-tts-bridge-010 | TtsBridge | ChoiceUI NOT subscribe highlight | — | ❌ |
| TR-animation-handler-001 | AnimationHandler | Per-scene instance | ADR-0011 | ✅ |
| TR-animation-handler-002 | AnimationHandler | 14 states / 18 clips | ADR-0011 | ✅ |
| TR-animation-handler-003 | AnimationHandler | NON_INTERRUPTIBLE_STATES | ADR-0011 | ✅ |
| TR-animation-handler-004 | AnimationHandler | _transition() sole entry, hard cut | ADR-0011 | ✅ |
| TR-animation-handler-005 | AnimationHandler | animation_finished routing | ADR-0011 | ✅ |
| TR-animation-handler-006 | AnimationHandler | stop_recording_listen() bypass | ADR-0011 | ✅ |
| TR-animation-handler-007 | AnimationHandler | RECOGNIZE NON_INTERRUPTIBLE | ADR-0011 | ✅ |
| TR-animation-handler-008 | AnimationHandler | CLIP_MAP + VARIANT_MAP | ADR-0011 | ✅ |
| TR-animation-handler-009 | AnimationHandler | %AnimationPlayer naming | ADR-0011 | ✅ |
| TR-animation-handler-010 | AnimationHandler | confused funny not fearful | ADR-0011 | ✅ |
| TR-interrupt-handler-001 | InterruptHandler | AutoLoad + PROCESS_MODE_ALWAYS | ADR-0012 | ✅ |
| TR-interrupt-handler-002 | InterruptHandler | _notification events | ADR-0012 | ✅ |
| TR-interrupt-handler-003 | InterruptHandler | _background_flush_pending | ADR-0012 | ✅ |
| TR-interrupt-handler-004 | InterruptHandler | Back button dual coverage | ADR-0012 | ✅ |
| TR-interrupt-handler-005 | InterruptHandler | VR interrupt_and_commit() first | ADR-0012 | ✅ |
| TR-interrupt-handler-006 | InterruptHandler | _on_chapter_interrupted routing | ADR-0012 | ✅ |
| TR-interrupt-handler-007 | InterruptHandler | FOCUS_IN recovery | ADR-0012 | ✅ |
| TR-interrupt-handler-008 | InterruptHandler | BACK_BUTTON_GUARD_TIMEOUT | ADR-0012 | ✅ |
| TR-interrupt-handler-009 | InterruptHandler | _ih_triggered_stop flag | ADR-0012 | ✅ |
| TR-interrupt-handler-010 | InterruptHandler | ui_cancel + KEY_BACK | ADR-0012 | ✅ |
| TR-interrupt-handler-011 | InterruptHandler | change_scene_to_file error | ADR-0012 | ✅ |
| TR-interrupt-handler-012 | InterruptHandler | VoiceRecorder soft dependency | ADR-0012 | ✅ |

### Feature Layer (62 TRs)

| TR-ID | System | Requirement | ADR | Status |
|-------|--------|-------------|-----|:------:|
| TR-story-manager-001 | StoryManager | AutoLoad, single chapter | ADR-0010 | ✅ |
| TR-story-manager-002 | StoryManager | begin_chapter() 4-step | ADR-0010 | ✅ |
| TR-story-manager-003 | StoryManager | _advance_step + 3-way wait | ADR-0010 | ✅ |
| TR-story-manager-004 | StoryManager | POST_TTS_PAUSE_MS delay | ADR-0010 | ✅ |
| TR-story-manager-005 | StoryManager | MAX_CHOICES = 2 | ADR-0010 | ✅ |
| TR-story-manager-006 | StoryManager | request_chapter_interrupt | ADR-0010 | ✅ |
| TR-story-manager-007 | StoryManager | profile_switch sync | ADR-0010 | ✅ |
| TR-story-manager-008 | StoryManager | T-Rex vocab constraint (Ink) | ADR-0010 | ✅ |
| TR-story-manager-009 | StoryManager | story_progress schema | ADR-0010 | ✅ |
| TR-story-manager-010 | StoryManager | call_deferred _advance_step | ADR-0010 | ✅ |
| TR-story-manager-011 | StoryManager | Timer node required | ADR-0010 | ✅ |
| TR-story-manager-012 | StoryManager | GameScene tts_fallback subscriber | ADR-0010 | ⚠️ |
| TR-tag-dispatcher-001 | TagDispatcher | AutoLoad + tags_dispatched | ADR-0013 | ✅ |
| TR-tag-dispatcher-002 | TagDispatcher | AnimationHandler registration | ADR-0013 | ✅ |
| TR-tag-dispatcher-003 | TagDispatcher | Tag vocabulary 2/3-segment | ADR-0013 | ✅ |
| TR-tag-dispatcher-004 | TagDispatcher | Batch processing + tts_not_required | ADR-0013 | ✅ |
| TR-tag-dispatcher-005 | TagDispatcher | P2 unconditional anim | ADR-0013 | ✅ |
| TR-tag-dispatcher-006 | TagDispatcher | vocab_text_map injection | ADR-0013 | ⚠️ |
| TR-tag-dispatcher-007 | TagDispatcher | VocabStore direct call | ADR-0013 | ✅ |
| TR-tag-dispatcher-008 | TagDispatcher | choices_ready from StoryManager | ADR-0013 | ⚠️ |
| TR-tag-dispatcher-009 | TagDispatcher | Unknown tags push_warning | ADR-0013 | ✅ |
| TR-voice-recorder-001 | VoiceRecorder | AutoLoad + 6-state machine | ADR-0009 | ✅ |
| TR-voice-recorder-002 | VoiceRecorder | AudioStreamMicrophone + Capture | ADR-0009 | ✅ |
| TR-voice-recorder-003 | VoiceRecorder | PCM buffer + store_buffer() | ADR-0009 | ✅ |
| TR-voice-recorder-004 | VoiceRecorder | WAV header ChunkSize+36 | ADR-0009 | ✅ |
| TR-voice-recorder-005 | VoiceRecorder | File naming convention | ADR-0009 | ✅ |
| TR-voice-recorder-006 | VoiceRecorder | MIN_RECORDING_FRAMES filter | ADR-0009 | ✅ |
| TR-voice-recorder-007 | VoiceRecorder | interrupt_and_commit() sync | ADR-0009 | ✅ |
| TR-voice-recorder-008 | VoiceRecorder | Recording/playback split | ADR-0009 | ✅ |
| TR-voice-recorder-009 | VoiceRecorder | PROCESS_MODE_ALWAYS playback | ADR-0009 | ✅ |
| TR-voice-recorder-010 | VoiceRecorder | profile_switch sync handler | ADR-0009 | ✅ |
| TR-voice-recorder-011 | VoiceRecorder | active_profile_cleared cleanup | ADR-0009 | ✅ |
| TR-voice-recorder-012 | VoiceRecorder | OS.request_permissions_result | ADR-0009 | ✅ |
| TR-voice-recorder-013 | VoiceRecorder | PCM two's complement verify | ADR-0009 | ✅ |
| TR-voice-recorder-014 | VoiceRecorder | recording_paths sole writer | ADR-0009 | ✅ |
| TR-parent-vocab-map-001 | ParentVocabMap | CanvasLayer (layer=128) | — | ❌ |
| TR-parent-vocab-map-002 | ParentVocabMap | Long-press delegated | — | ❌ |
| TR-parent-vocab-map-003 | ParentVocabMap | 20dp drift tolerance | — | ❌ |
| TR-parent-vocab-map-004 | ParentVocabMap | _ready() synchronous query | ADR-0006 | ⚠️ |
| TR-parent-vocab-map-005 | ParentVocabMap | VoiceRecorder optional guard | — | ❌ |
| TR-parent-vocab-map-006 | ParentVocabMap | Recording display MAX_RECORDINGS | — | ❌ |
| TR-parent-vocab-map-007 | ParentVocabMap | Close sequence 4 steps | — | ❌ |
| TR-parent-vocab-map-008 | ParentVocabMap | gold_star_awarded signal | ADR-0006 | ⚠️ |
| TR-parent-vocab-map-009 | ParentVocabMap | Recording playback one-at-a-time | — | ❌ |
| TR-postcard-gen-001 | PostcardGenerator | One-shot node guard | ADR-0003 | ⚠️ |
| TR-postcard-gen-002 | PostcardGenerator | _ready() data query | ADR-0006 | ⚠️ |
| TR-postcard-gen-003 | PostcardGenerator | SubViewport build sequence | — | ❌ |
| TR-postcard-gen-004 | PostcardGenerator | Image write path + fallback | ADR-0003 | ✅ |
| TR-postcard-gen-005 | PostcardGenerator | Silent failure strategy | ADR-0003 | ✅ |
| TR-postcard-gen-006 | PostcardGenerator | File naming postcard_ch{N}_ | — | ❌ |
| TR-postcard-gen-007 | PostcardGenerator | All paths via _finish() | — | ❌ |
| TR-postcard-gen-008 | PostcardGenerator | Postcard.tscn setup API | — | ❌ |

### Presentation Layer (31 TRs)

| TR-ID | System | Requirement | ADR | Status |
|-------|--------|-------------|-----|:------:|
| TR-choice-ui-001 | ChoiceUI | GameScene child node | ADR-0010 | ⚠️ |
| TR-choice-ui-002 | ChoiceUI | Three-state machine | — | ❌ |
| TR-choice-ui-003 | ChoiceUI | Button layout 96dp / 44-46% | — | ❌ |
| TR-choice-ui-004 | ChoiceUI | Card structure icon+word+translation | — | ❌ |
| TR-choice-ui-005 | ChoiceUI | P2 Anti-Pillar both identical | — | ❌ |
| TR-choice-ui-006 | ChoiceUI | Rule 6 not subscribe highlight | — | ❌ |
| TR-choice-ui-007 | ChoiceUI | chapter_interrupted handler | ADR-0010 | ✅ |
| TR-choice-ui-008 | ChoiceUI | FOCUS_NONE for all buttons | — | ❌ |
| TR-choice-ui-009 | ChoiceUI | Choices exactly 2 | ADR-0010 | ✅ |
| TR-choice-ui-010 | ChoiceUI | Multi-touch double submit | — | ❌ |
| TR-main-menu-001 | MainMenu | Active profile guard | ADR-0014 | ✅ |
| TR-main-menu-002 | MainMenu | T-Rex entry animation | ADR-0014 | ✅ |
| TR-main-menu-003 | MainMenu | Profile switcher visibility | ADR-0014 | ✅ |
| TR-main-menu-004 | MainMenu | Launch sequence 7 steps | ADR-0014 | ✅ |
| TR-main-menu-005 | MainMenu | begin_session() once per visit | ADR-0014 | ✅ |
| TR-main-menu-006 | MainMenu | Parent button long-press | ADR-0014 | ✅ |
| TR-main-menu-007 | MainMenu | PARENT_HOLD_DURATION = 5.0s | ADR-0014 | ✅ |
| TR-main-menu-008 | MainMenu | LOAD_ERROR 3 retries | ADR-0014 | ✅ |
| TR-main-menu-009 | MainMenu | SITTING_INACTIVITY decoupled | ADR-0014 | ✅ |
| TR-main-menu-010 | MainMenu | LOAD_ERROR during RECOGNIZE | ADR-0014 | ✅ |
| TR-main-menu-011 | MainMenu | No optimistic UI update | ADR-0014 | ✅ |
| TR-main-menu-012 | MainMenu | PROFILE_SWITCHING unresponsive | ADR-0014 | ✅ |
| TR-main-menu-013 | MainMenu | Layout 360x800dp | ADR-0014 | ✅ |
| TR-hatch-scene-001 | HatchScene | 3-state machine | ADR-0016 | ✅ |
| TR-hatch-scene-002 | HatchScene | Min display protection | ADR-0016 | ✅ |
| TR-hatch-scene-003 | HatchScene | 3-layer visual summoning | ADR-0016 | ✅ |
| TR-hatch-scene-004 | HatchScene | Full-screen touch target | ADR-0016 | ✅ |
| TR-hatch-scene-005 | HatchScene | HATCHING tap feedback | ADR-0016 | ✅ |
| TR-hatch-scene-006 | HatchScene | Android back button | ADR-0016 | ✅ |
| TR-hatch-scene-007 | HatchScene | CELEBRATE_SKIP_LOCK_MS | ADR-0016 | ✅ |
| TR-hatch-scene-008 | HatchScene | Watchdog timer | ADR-0016 | ✅ |
| TR-hatch-scene-009 | HatchScene | No SaveSystem/ProfileManager | ADR-0016 | ✅ |
| TR-hatch-scene-010 | HatchScene | AnimationHandler static child | ADR-0016 | ⚠️ |
| TR-hatch-scene-011 | HatchScene | Egg glow shader spec | ADR-0016 | ⚠️ |
| TR-hatch-scene-012 | HatchScene | Performance budget | ADR-0016 | ⚠️ |
| TR-hatch-scene-013 | HatchScene | GUT testability wrappers | ADR-0016 | ✅ |
| TR-recording-invite-001 | RecordingInviteUI | GameScene child node | ADR-0015 | ✅ |
| TR-recording-invite-002 | RecordingInviteUI | Signal subscriptions | ADR-0015 | ✅ |
| TR-recording-invite-003 | RecordingInviteUI | Appearance guard | ADR-0015 | ✅ |
| TR-recording-invite-004 | RecordingInviteUI | Hold-to-record via _input() | ADR-0015 | ✅ |
| TR-recording-invite-005 | RecordingInviteUI | INVITE_TIMEOUT_SEC | ADR-0015 | ✅ |
| TR-recording-invite-006 | RecordingInviteUI | T-Rex ack animation | ADR-0015 | ✅ |
| TR-recording-invite-007 | RecordingInviteUI | Silent failure P2 | ADR-0015 | ✅ |
| TR-recording-invite-008 | RecordingInviteUI | recording_interrupted S5-B1 | ADR-0015 | ✅ |
| TR-recording-invite-009 | RecordingInviteUI | stop_recording_listen timing | ADR-0015 | ✅ |
| TR-recording-invite-010 | RecordingInviteUI | Button >= 96dp | ADR-0015 | ✅ |
| TR-recording-invite-011 | RecordingInviteUI | dismissed signal semantics | ADR-0015 | ✅ |

### Zero Coverage Systems (26 TRs)

| System | TRs | Layer | Priority |
|--------|:---:|-------|----------|
| NameInputScreen | 10 | Presentation | VS |
| VocabPrimingLoader | 9 | Presentation | VS |
| Chapter2Teaser | 7 | Polish | VS |

---

## Phase 4: Cross-ADR Conflict Detection

### Conflict 1: ADR-0013 vs ADR-0006 — Interface Contract (🔴 HIGH)

**Type:** Integration Contract

ADR-0013 calls `VocabStore.record_event(word_id, PRESENTED)` / `record_event(word_id, SELECTED_CORRECT)` / `record_event(word_id, NOT_CORRECT)`. ADR-0006 defines `correct_event(word_id)` and `not_correct_event(word_id)` — no `record_event()` method exists.

**Impact:** Runtime crash — TagDispatcher cannot route vocab events to VocabStore. Blocks entire gameplay loop.

**Resolution:**
- Option A: ADR-0006 adds `record_event(word_id: String, event_type: EventType)` facade
- Option B: ADR-0013 changes to call `correct_event()` / `not_correct_event()` + new `presented_event()`

### Conflict 2: ADR-0007 Internal Inconsistency (🟡 MEDIUM)

**Type:** Internal Self-Contradiction

ADR-0007 Context says "8 AutoLoads" but Decision lists 9 (includes AudioManager from ADR-0008). Migration Plan says "if a future ADR adds a 9th" — but Decision already has 9.

**Impact:** Developer confusion about current AutoLoad count. Boot time budget assessment wrong.

**Resolution:** Update ADR-0007 Context and Migration Plan to reference 9 AutoLoads.

### Conflict 3: ADR-0008 vs ADR-0007 — Numbering (🟢 LOW)

**Type:** Numbering Mismatch

ADR-0008 says "AudioManager loads before StoryManager (⑤)" but ADR-0007 positions StoryManager at ⑥.

**Impact:** Minor developer confusion.

**Resolution:** Update ADR-0008 to say "before StoryManager (⑥)".

### No Circular Dependencies

All 16 ADRs form a clean DAG. No cycles detected.

### ADR Dependency Order (Topological Sort)

```
Level 0 (no deps, parallel):  ADR-0001, ADR-0004, ADR-0011
Level 1 (parallel):           ADR-0002, ADR-0003, ADR-0005, ADR-0016
Level 2 (parallel):           ADR-0006, ADR-0009
Level 3:                      ADR-0007
Level 4:                      ADR-0008
Level 5:                      ADR-0010
Level 6 (parallel):           ADR-0012, ADR-0013, ADR-0014
Level 7:                      ADR-0015
```

**Critical path:** ADR-0004 → 0005 → 0006 → 0007 → 0010 → 0013 → 0015 (7 layers).

All 16 ADRs are **Proposed** — no ADR is Accepted yet. Per project rules, stories referencing Proposed ADRs are auto-blocked.

---

## Phase 5: Engine Compatibility

### Audit Results

| Check | Result |
|-------|--------|
| Engine | Godot 4.6 |
| ADRs with Engine Compatibility | 16 / 16 |
| Version Consistency | All 16 ADRs target Godot 4.6 |
| Deprecated API Usage | None |
| Missing Engine Compatibility Sections | None |

### Post-Cutoff APIs

| API | ADR | Risk |
|-----|-----|:----:|
| InkResource / InkStory.new / can_continue | ADR-0001 | HIGH |
| OS.get_system_dir (Scoped Storage) | ADR-0003 | HIGH |
| NOTIFICATION_WM_GO_BACK_REQUEST | ADR-0012 | HIGH |
| @abstract decorator (4.5+) | ADR-0002 | MEDIUM |
| DirAccess.make_dir_recursive_absolute | ADR-0003 | MEDIUM |
| FileAccess.store_string() bool return (4.4) | ADR-0004 | MEDIUM |
| DirAccess.rename() semantics (4.4) | ADR-0004 | MEDIUM |
| AnimationPlayer.play() custom_blend | ADR-0011 | LOW |
| duplicate_deep() (4.5+) | ADR-0005 | LOW |
| Time.get_datetime_string_from_system | ADR-0004 | LOW |

### Stale References

- ADR-0007: "8 AutoLoads near ceiling" — should be 9 (AudioManager added by ADR-0008)

### Post-Cutoff API Conflicts

- ADR-0011 and ADR-0016 both reference 4.6 glow pipeline change. No conflict — they agree on the risk. ADR-0016's egg glow shader verification is the more specific concern.

### GDD Revision Flags

No GDD revision flags — all GDD assumptions are consistent with verified engine behaviour.

---

## Phase 6: Architecture Document Coverage

Architecture doc (`docs/architecture/architecture.md`) ADR list references ADR-0001~0008 only. Needs update to include ADR-0009~0016.

---

## Verdict: CONCERNS (⚠️)

| Condition | Assessment |
|-----------|-----------|
| All requirements covered | ❌ 40 gaps (22.7%) — all VS/Presentation layer |
| No blocking conflicts | ⚠️ 1 HIGH (ADR-0013 vs ADR-0006 interface) |
| Engine consistent | ✅ All 16 ADRs target 4.6 |
| Foundation/Core covered | ✅ 100% Foundation, 90% Core |

**Rationale:** 73% coverage (+40pp from previous), no Foundation/Core blocking gaps, clean DAG. One HIGH interface conflict must be resolved. All gaps are Vertical Slice / Presentation layer — not blocking MVP core loop.

### Blocking Issues (must resolve before PASS)

1. **ADR-0013 vs ADR-0006**: `record_event()` interface mismatch — runtime crash risk
2. **ADR-0007**: AutoLoad count 8→9 internal inconsistency

### Required ADRs (from gaps)

| Priority | System | TRs | Suggested ADR |
|----------|--------|:---:|---------------|
| P2 | NameInputScreen | 10 | ADR-0017 |
| P2 | VocabPrimingLoader | 9 | ADR-0018 |
| P3 | Chapter2Teaser | 7 | ADR-0019 |
| P2 | ChoiceUI (detailed) | 6 | Expand ADR-0010 or new ADR |
| P2 | ParentVocabMap | 5 | ADR-0020 |
| P2 | PostcardGenerator (detailed) | 5 | Expand ADR-0003 or new ADR |
