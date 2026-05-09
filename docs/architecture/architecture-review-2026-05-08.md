# Architecture Review Report

| Field | Value |
|-------|-------|
| **Date** | 2026-05-08 |
| **Engine** | Godot 4.6 Standard (non-Mono) |
| **GDDs Reviewed** | 18 / 18 (full coverage) |
| **ADRs Reviewed** | 8 / 8 (ADR-0001 through ADR-0008) |
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
| StoryManager | 12 | Feature |
| TagDispatcher | 9 | Feature |
| VoiceRecorder | 14 | Feature |
| MainMenu | 13 | Presentation |
| HatchScene | 13 | Presentation |
| NameInputScreen | 10 | Presentation |
| ParentVocabMap | 9 | Feature |
| PostcardGenerator | 8 | Feature |
| VocabPrimingLoader | 9 | Presentation |
| Chapter2Teaser | 7 | Polish |
| AnimationHandler | 10 | Core |
| ChoiceUI | 10 | Presentation |
| InterruptHandler | 12 | Core |
| RecordingInviteUI | 11 | Presentation |

---

## Phase 3: Traceability Matrix

### Coverage Summary

| Status | Count | % |
|--------|:-----:|:---:|
| ✅ Covered | 58 | 33% |
| ⚠️ Partial | 22 | 12% |
| ❌ Gap | 96 | 55% |
| **Total** | **176** | **100%** |

### Foundation Layer

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
| TR-save-system-009 | SaveSystem | MAX_SAVE_PROFILES / SCHEMA_VERSION | ADR-0004 | ✅ |
| TR-profile-manager-001 | ProfileManager | Single in-memory authority | ADR-0005 | ✅ |
| TR-profile-manager-002 | ProfileManager | get_active_data() returns reference | ADR-0005 | ✅ |
| TR-profile-manager-003 | ProfileManager | Section-level access | ADR-0005 | ✅ |
| TR-profile-manager-004 | ProfileManager | Single flush entry point | ADR-0005 | ✅ |
| TR-profile-manager-005 | ProfileManager | switch_to_profile() 7-step | ADR-0005 | ✅ |
| TR-profile-manager-006 | ProfileManager | begin_session() called by MainMenu | — | ❌ GAP |
| TR-profile-manager-007 | ProfileManager | is_first_launch() | — | ❌ GAP |
| TR-profile-manager-008 | ProfileManager | Profile section write permission | ADR-0005 | ✅ |
| TR-profile-manager-009 | ProfileManager | Four-state machine | ADR-0005 | ✅ |
| TR-profile-manager-010 | ProfileManager | profile_switch_requested sync | ADR-0005 | ✅ |
| TR-profile-manager-011 | ProfileManager | delete_profile() 5-step | — | ❌ GAP |
| TR-profile-manager-012 | ProfileManager | create_profile() v2 default | — | ❌ GAP |
| TR-profile-manager-013 | ProfileManager | profile_exists() delegates | — | ❌ GAP |
| TR-profile-manager-014 | ProfileManager | NAME_MAX_LENGTH = 20 | — | ❌ GAP |
| TR-profile-manager-015 | ProfileManager | parent_map_hint_dismissed field | — | ❌ GAP |
| TR-vocab-store-001 | VocabStore | Two-layer memory state | ADR-0006 | ✅ |
| TR-vocab-store-002 | VocabStore | record_event() EventType | ADR-0006 | ✅ |
| TR-vocab-store-003 | VocabStore | Gold star award formula | ADR-0006 | ✅ |
| TR-vocab-store-004 | VocabStore | GDScript float cast CRITICAL | ADR-0006 | ✅ |
| TR-vocab-store-005 | VocabStore | is_learned monotonicity | ADR-0006 | ✅ |
| TR-vocab-store-006 | VocabStore | recording_paths ownership | ADR-0006 | ✅ |
| TR-vocab-store-007 | VocabStore | profile_switch sync handler | ADR-0006 | ✅ |
| TR-vocab-store-008 | VocabStore | Session lifecycle (begin/end) | ADR-0006 | ✅ |
| TR-vocab-store-009 | VocabStore | Gold star flush via ProfileManager | ADR-0006 | ✅ |
| TR-vocab-store-010 | VocabStore | NOT_CORRECT Anti-Pillar P2 | ADR-0006 | ✅ |

### Core Layer

| TR-ID | System | Requirement | ADR | Status |
|-------|--------|-------------|-----|:------:|
| TR-tts-bridge-001 | TtsBridge | AutoLoad + TtsProvider interface | ADR-0002 | ✅ |
| TR-tts-bridge-002 | TtsBridge | Three-tier fallback chain | ADR-0002 | ✅ |
| TR-tts-bridge-003 | TtsBridge | AI session health threshold | ADR-0002 | ✅ |
| TR-tts-bridge-004 | TtsBridge | Lazy audio cache | ADR-0002 | ✅ |
| TR-tts-bridge-005 | TtsBridge | Interrupt strategy | ADR-0002 | ✅ |
| TR-tts-bridge-006 | TtsBridge | warm_cache() Path X | ADR-0002 | ✅ |
| TR-tts-bridge-007 | TtsBridge | HTTP POST + WAV/MP3 .data | ADR-0002 | ✅ |
| TR-tts-bridge-008 | TtsBridge | System TTS watchdog timer | — | ❌ GAP |
| TR-tts-bridge-009 | TtsBridge | MAX_PERCEIVED_LATENCY_MS | — | ❌ GAP |
| TR-tts-bridge-010 | TtsBridge | ChoiceUI must NOT subscribe highlight | — | ❌ GAP |
| TR-animation-handler-001 | AnimationHandler | Per-scene instance | — | ❌ GAP |
| TR-animation-handler-002 | AnimationHandler | 14 logical states enum | — | ❌ GAP |
| TR-animation-handler-003 | AnimationHandler | NON_INTERRUPTIBLE_STATES | — | ❌ GAP |
| TR-animation-handler-004 | AnimationHandler | _transition() + custom_blend | — | ❌ GAP |
| TR-animation-handler-005 | AnimationHandler | animation_finished chain routing | — | ❌ GAP |
| TR-animation-handler-006 | AnimationHandler | stop_recording_listen() bypass | — | ❌ GAP |
| TR-animation-handler-007 | AnimationHandler | RECOGNIZE NON_INTERRUPTIBLE | — | ❌ GAP |
| TR-animation-handler-008 | AnimationHandler | CLIP_MAP + VARIANT_MAP | — | ❌ GAP |
| TR-animation-handler-009 | AnimationHandler | %AnimationPlayer naming | — | ❌ GAP |
| TR-animation-handler-010 | AnimationHandler | Confused = funny not fearful | — | ❌ GAP |
| TR-interrupt-handler-001 | InterruptHandler | AutoLoad + PROCESS_MODE_ALWAYS | — | ❌ GAP |
| TR-interrupt-handler-002 | InterruptHandler | _notification events | — | ❌ GAP |
| TR-interrupt-handler-003 | InterruptHandler | _background_flush_pending | — | ❌ GAP |
| TR-interrupt-handler-004 | InterruptHandler | Back button dual coverage | — | ❌ GAP |
| TR-interrupt-handler-005 | InterruptHandler | VR interrupt_and_commit() first | — | ❌ GAP |
| TR-interrupt-handler-006 | InterruptHandler | _on_chapter_interrupted routing | — | ❌ GAP |
| TR-interrupt-handler-007 | InterruptHandler | FOCUS_IN recovery | — | ❌ GAP |
| TR-interrupt-handler-008 | InterruptHandler | BACK_BUTTON_GUARD_TIMEOUT | — | ❌ GAP |
| TR-interrupt-handler-009 | InterruptHandler | _ih_triggered_stop flag | — | ❌ GAP |
| TR-interrupt-handler-010 | InterruptHandler | ui_cancel + KEY_BACK config | — | ❌ GAP |
| TR-interrupt-handler-011 | InterruptHandler | change_scene_to_file error | — | ❌ GAP |
| TR-interrupt-handler-012 | InterruptHandler | VoiceRecorder soft dependency | — | ❌ GAP |

### Feature Layer

| TR-ID | System | Requirement | ADR | Status |
|-------|--------|-------------|-----|:------:|
| TR-story-manager-001 | StoryManager | AutoLoad singleton | ADR-0001, ADR-0007 | ✅ |
| TR-story-manager-002 | StoryManager | begin_chapter() 4-step | ADR-0001 | ⚠️ Partial |
| TR-story-manager-003 | StoryManager | _advance_step 3-way wait | — | ❌ GAP |
| TR-story-manager-004 | StoryManager | POST_TTS_PAUSE_MS | — | ❌ GAP |
| TR-story-manager-005 | StoryManager | MAX_CHOICES = 2 | — | ❌ GAP |
| TR-story-manager-006 | StoryManager | request_chapter_interrupt | — | ❌ GAP |
| TR-story-manager-007 | StoryManager | profile_switch sync | ADR-0005 | ✅ |
| TR-story-manager-008 | StoryManager | Ink Rule 15 T-Rex vocab | — | ❌ GAP |
| TR-story-manager-009 | StoryManager | Story progress schema | — | ❌ GAP |
| TR-story-manager-010 | StoryManager | call_deferred for _advance_step | — | ❌ GAP |
| TR-story-manager-011 | StoryManager | Timer node (not create_timer) | — | ❌ GAP |
| TR-story-manager-012 | StoryManager | tts_fallback_to_highlight | — | ❌ GAP |
| TR-tag-dispatcher-001 | TagDispatcher | AutoLoad singleton | ADR-0001 | ✅ |
| TR-tag-dispatcher-002 | TagDispatcher | AnimationHandler registration | — | ❌ GAP |
| TR-tag-dispatcher-003 | TagDispatcher | Tag vocabulary (2/3 segment) | ADR-0001 | ⚠️ Partial |
| TR-tag-dispatcher-004 | TagDispatcher | Batch processing order | — | ❌ GAP |
| TR-tag-dispatcher-005 | TagDispatcher | P2 Anti-Pillar unconditional | — | ❌ GAP |
| TR-tag-dispatcher-006 | TagDispatcher | vocab_text_map injection | — | ❌ GAP |
| TR-tag-dispatcher-007 | TagDispatcher | VocabStore direct call | — | ❌ GAP |
| TR-tag-dispatcher-008 | TagDispatcher | choices_ready boundary | — | ❌ GAP |
| TR-tag-dispatcher-009 | TagDispatcher | Unknown tags fault tolerance | — | ❌ GAP |
| TR-voice-recorder-001 | VoiceRecorder | 6-state machine | — | ❌ GAP |
| TR-voice-recorder-002 | VoiceRecorder | AudioStreamMicrophone | — | ❌ GAP |
| TR-voice-recorder-003 | VoiceRecorder | PCM buffer accumulation | — | ❌ GAP |
| TR-voice-recorder-004 | VoiceRecorder | WAV header ChunkSize+36 | — | ❌ GAP |
| TR-voice-recorder-005 | VoiceRecorder | File naming convention | — | ❌ GAP |
| TR-voice-recorder-006 | VoiceRecorder | MIN_RECORDING_FRAMES | — | ❌ GAP |
| TR-voice-recorder-007 | VoiceRecorder | interrupt_and_commit sync | — | ❌ GAP |
| TR-voice-recorder-008 | VoiceRecorder | Recording/playback separation | — | ❌ GAP |
| TR-voice-recorder-009 | VoiceRecorder | PROCESS_MODE_ALWAYS playback | — | ❌ GAP |
| TR-voice-recorder-010 | VoiceRecorder | profile_switch sync handler | — | ❌ GAP |
| TR-voice-recorder-011 | VoiceRecorder | Profile delete cleanup | — | ❌ GAP |
| TR-voice-recorder-012 | VoiceRecorder | OS.request_permissions_result | — | ❌ GAP |
| TR-voice-recorder-013 | VoiceRecorder | PCM two's complement | — | ❌ GAP |
| TR-voice-recorder-014 | VoiceRecorder | recording_paths sole writer | — | ❌ GAP |
| TR-parent-vocab-map-001 | ParentVocabMap | CanvasLayer layer=128 | — | ❌ GAP |
| TR-parent-vocab-map-002 | ParentVocabMap | Long-press delegated | — | ❌ GAP |
| TR-parent-vocab-map-003 | ParentVocabMap | 20dp drift tolerance | — | ❌ GAP |
| TR-parent-vocab-map-004 | ParentVocabMap | _ready() sync query | — | ❌ GAP |
| TR-parent-vocab-map-005 | ParentVocabMap | VoiceRecorder optional | — | ❌ GAP |
| TR-parent-vocab-map-006 | ParentVocabMap | Recording display max | — | ❌ GAP |
| TR-parent-vocab-map-007 | ParentVocabMap | Close sequence | — | ❌ GAP |
| TR-parent-vocab-map-008 | ParentVocabMap | gold_star_awarded subscription | — | ❌ GAP |
| TR-parent-vocab-map-009 | ParentVocabMap | Recording playback one-at-time | — | ❌ GAP |
| TR-postcard-gen-001 | PostcardGenerator | One-shot lifecycle | — | ❌ GAP |
| TR-postcard-gen-002 | PostcardGenerator | _ready() sync data query | — | ❌ GAP |
| TR-postcard-gen-003 | PostcardGenerator | SubViewport 4-step build | — | ❌ GAP |
| TR-postcard-gen-004 | PostcardGenerator | Gallery save paths | ADR-0003 | ✅ |
| TR-postcard-gen-005 | PostcardGenerator | Silent failure strategy | ADR-0003 | ✅ |
| TR-postcard-gen-006 | PostcardGenerator | File naming | ADR-0003 | ✅ |
| TR-postcard-gen-007 | PostcardGenerator | _finish() cleanup | — | ❌ GAP |
| TR-postcard-gen-008 | PostcardGenerator | Postcard.tscn setup API | — | ❌ GAP |

### Presentation Layer

| TR-ID | System | Requirement | ADR | Status |
|-------|--------|-------------|-----|:------:|
| TR-main-menu-001 | MainMenu | Active profile guard | — | ❌ GAP |
| TR-main-menu-002 | MainMenu | T-Rex entry animation | — | ❌ GAP |
| TR-main-menu-003 | MainMenu | Profile switcher visibility | — | ❌ GAP |
| TR-main-menu-004 | MainMenu | Launch sequence 7 steps | — | ❌ GAP |
| TR-main-menu-005 | MainMenu | begin_session() once | — | ❌ GAP |
| TR-main-menu-006 | MainMenu | Parent button long-press | — | ❌ GAP |
| TR-main-menu-007 | MainMenu | PARENT_HOLD_DURATION assert | — | ❌ GAP |
| TR-main-menu-008 | MainMenu | LOAD_ERROR 3 retries | — | ❌ GAP |
| TR-main-menu-009 | MainMenu | SITTING_INACTIVITY decoupled | — | ❌ GAP |
| TR-main-menu-010 | MainMenu | LOAD_ERROR during RECOGNIZE | — | ❌ GAP |
| TR-main-menu-011 | MainMenu | BGM at NameInputScreen | ADR-0008 | ✅ |
| TR-main-menu-012 | MainMenu | PROFILE_SWITCHING unresponsive | — | ❌ GAP |
| TR-main-menu-013 | MainMenu | Layout 360x800dp | — | ❌ GAP |
| TR-hatch-scene-001 | HatchScene | 3-state machine | — | ❌ GAP |
| TR-hatch-scene-002 | HatchScene | Min display protection | — | ❌ GAP |
| TR-hatch-scene-003 | HatchScene | 3-layer visual summoning | — | ❌ GAP |
| TR-hatch-scene-004 | HatchScene | Full-screen touch target | — | ❌ GAP |
| TR-hatch-scene-005 | HatchScene | HATCHING tap feedback | — | ❌ GAP |
| TR-hatch-scene-006 | HatchScene | Back button intercept | — | ❌ GAP |
| TR-hatch-scene-007 | HatchScene | CELEBRATE_SKIP_LOCK_MS | — | ❌ GAP |
| TR-hatch-scene-008 | HatchScene | Watchdog timer | — | ❌ GAP |
| TR-hatch-scene-009 | HatchScene | No SaveSystem/ProfileManager | — | ❌ GAP |
| TR-hatch-scene-010 | HatchScene | AnimationHandler static child | — | ❌ GAP |
| TR-hatch-scene-011 | HatchScene | Egg glow shader spec | — | ❌ GAP |
| TR-hatch-scene-012 | HatchScene | Performance budget | — | ❌ GAP |
| TR-hatch-scene-013 | HatchScene | GUT testability wrappers | — | ❌ GAP |
| TR-name-input-001 | NameInputScreen | Entry guard | — | ❌ GAP |
| TR-name-input-002 | NameInputScreen | LineEdit max_length | — | ❌ GAP |
| TR-name-input-003 | NameInputScreen | Avatar selection grid | — | ❌ GAP |
| TR-name-input-004 | NameInputScreen | Confirm disabled on empty | — | ❌ GAP |
| TR-name-input-005 | NameInputScreen | Skip button fixed default | — | ❌ GAP |
| TR-name-input-006 | NameInputScreen | Creation 6-step sequence | — | ❌ GAP |
| TR-name-input-007 | NameInputScreen | Full-width space handling | — | ❌ GAP |
| TR-name-input-008 | NameInputScreen | Back key dismiss keyboard | — | ❌ GAP |
| TR-name-input-009 | NameInputScreen | Soft keyboard adaptation | ADR-0008 | ⚠️ Partial |
| TR-name-input-010 | NameInputScreen | create_profile() sole caller | — | ❌ GAP |
| TR-choice-ui-001 | ChoiceUI | GameScene child node | — | ❌ GAP |
| TR-choice-ui-002 | ChoiceUI | 3-state machine | — | ❌ GAP |
| TR-choice-ui-003 | ChoiceUI | Button layout 96dp | — | ❌ GAP |
| TR-choice-ui-004 | ChoiceUI | Card structure | — | ❌ GAP |
| TR-choice-ui-005 | ChoiceUI | P2 visually identical | — | ❌ GAP |
| TR-choice-ui-006 | ChoiceUI | No highlight subscription | — | ❌ GAP |
| TR-choice-ui-007 | ChoiceUI | chapter_interrupted handler | — | ❌ GAP |
| TR-choice-ui-008 | ChoiceUI | FOCUS_NONE (4.6) | — | ❌ GAP |
| TR-choice-ui-009 | ChoiceUI | Exactly 2 choices | — | ❌ GAP |
| TR-choice-ui-010 | ChoiceUI | Multi-touch protection | — | ❌ GAP |
| TR-vocab-priming-001 | VocabPrimingLoader | Auto-start lifecycle | — | ❌ GAP |
| TR-vocab-priming-002 | VocabPrimingLoader | Static snapshot | — | ❌ GAP |
| TR-vocab-priming-003 | VocabPrimingLoader | Single Tween chain | — | ❌ GAP |
| TR-vocab-priming-004 | VocabPrimingLoader | Cards accumulate | — | ❌ GAP |
| TR-vocab-priming-005 | VocabPrimingLoader | No interaction | — | ❌ GAP |
| TR-vocab-priming-006 | VocabPrimingLoader | 3-tier gold star visual | — | ❌ GAP |
| TR-vocab-priming-007 | VocabPrimingLoader | Interrupt tolerance | — | ❌ GAP |
| TR-vocab-priming-008 | VocabPrimingLoader | priming_complete signal | — | ❌ GAP |
| TR-vocab-priming-009 | VocabPrimingLoader | Duration [5.0, 8.0]s | — | ❌ GAP |
| TR-recording-invite-001 | RecordingInviteUI | GameScene child node | — | ❌ GAP |
| TR-recording-invite-002 | RecordingInviteUI | Signal subscriptions | — | ❌ GAP |
| TR-recording-invite-003 | RecordingInviteUI | Appearance guard | — | ❌ GAP |
| TR-recording-invite-004 | RecordingInviteUI | Hold-to-record _input() | — | ❌ GAP |
| TR-recording-invite-005 | RecordingInviteUI | INVITE_TIMEOUT_SEC | — | ❌ GAP |
| TR-recording-invite-006 | RecordingInviteUI | T-Rex ack animation | — | ❌ GAP |
| TR-recording-invite-007 | RecordingInviteUI | Silent failure P2 | — | ❌ GAP |
| TR-recording-invite-008 | RecordingInviteUI | recording_interrupted | — | ❌ GAP |
| TR-recording-invite-009 | RecordingInviteUI | stop_recording_listen timing | — | ❌ GAP |
| TR-recording-invite-010 | RecordingInviteUI | Button >= 96dp | — | ❌ GAP |
| TR-recording-invite-011 | RecordingInviteUI | dismissed signal semantics | — | ❌ GAP |

### Polish/Output Layer

| TR-ID | System | Requirement | ADR | Status |
|-------|--------|-------------|-----|:------:|
| TR-chapter2-teaser-001 | Chapter2Teaser | One-shot lifecycle | — | ❌ GAP |
| TR-chapter2-teaser-002 | Chapter2Teaser | 2-phase animation | — | ❌ GAP |
| TR-chapter2-teaser-003 | Chapter2Teaser | TWEEN_TIMEOUT_SEC | — | ❌ GAP |
| TR-chapter2-teaser-004 | Chapter2Teaser | No input response | — | ❌ GAP |
| TR-chapter2-teaser-005 | Chapter2Teaser | _transitioning guard | — | ❌ GAP |
| TR-chapter2-teaser-006 | Chapter2Teaser | SceneTree.paused integration | — | ❌ GAP |
| TR-chapter2-teaser-007 | Chapter2Teaser | Hardcoded content | — | ❌ GAP |

---

## Phase 4: Cross-ADR Conflict Detection

### Conflicts Found: 0

All 8 ADRs are mutually consistent. No data ownership conflicts, integration contract conflicts, performance budget conflicts, dependency cycles, or state management conflicts detected.

**Key consistency checks passed:**
- ADR-0005 (ProfileManager) correctly references ADR-0004 (SaveSystem) for flush/load in switch sequence
- ADR-0006 (VocabStore) correctly references ADR-0005 for `profile_switch_requested` handler
- ADR-0007 (AutoLoad order) correctly positions all systems per their dependency graphs
- ADR-0008 (AudioManager) correctly slots into ADR-0007's boot chain at position 5
- Field ownership partition in ADR-0006 (VocabStore vs VoiceRecorder) is clean with no overlap
- All `profile_switch_requested` handlers documented as synchronous (ADR-0005 invariant maintained)

### ADR Dependency Order (Topologically Sorted)

```
Foundation (no dependencies):
  1. ADR-0001: inkgd Runtime vs. Custom JSON State Machine
  2. ADR-0004: SaveSystem Atomic Write Protocol

Depends on ADR-0004:
  3. ADR-0005: ProfileManager Profile Switch Protocol (requires ADR-0004)

Depends on ADR-0004 + ADR-0005:
  4. ADR-0006: VocabStore Gold Star Formula (requires ADR-0004, ADR-0005)

Depends on ADR-0004 + ADR-0005 + ADR-0006:
  5. ADR-0007: AutoLoad Initialization Order (requires ADR-0004, ADR-0005, ADR-0006)

Depends on ADR-0001:
  6. ADR-0002: TTS Provider Interface (requires ADR-0001)
  7. ADR-0003: Android Gallery Save (requires ADR-0001)

Depends on ADR-0007:
  8. ADR-0008: AudioManager BGM Strategy (requires ADR-0007)
```

**Unresolved dependencies:** None. All referenced ADRs exist.

---

## Phase 5: Engine Compatibility Cross-Check

### Engine Audit Results

**Engine:** Godot 4.6-stable (pinned 2026-02-12)

**ADRs with Engine Compatibility section:** 8 / 8 (100%)

| ADR | Engine Risk | Post-Cutoff APIs | Status |
|-----|:-----------:|-----------------|:------:|
| ADR-0001 | HIGH | InkResource, InkStory.new() | ⚠️ Week 1 verify |
| ADR-0002 | LOW | @abstract (4.5) | ✅ Confirmed |
| ADR-0003 | HIGH | OS.get_system_dir | ⚠️ Week 1 verify |
| ADR-0004 | MEDIUM | FileAccess.store_* bool (4.4) | ✅ Confirmed |
| ADR-0005 | LOW | None | ✅ |
| ADR-0006 | LOW | None | ✅ |
| ADR-0007 | LOW | None | ✅ |
| ADR-0008 | LOW | None | ✅ |

### Deprecated API References

None found. No ADR references any deprecated API from `deprecated-apis.md`.

### Post-Cutoff API Conflicts

None. ADR-0002's `@abstract` (4.5+) and ADR-0004's `FileAccess.store_*` return type (4.4+) are the only post-cutoff APIs, and they are correctly documented with verification notes.

### Missing Engine Compatibility Sections

None. All 8 ADRs include the Engine Compatibility section.

### GDD Revision Flags (Architecture -> Design Feedback)

No GDD revision flags — all GDD assumptions are consistent with verified engine behaviour.

---

## Phase 6: Architecture Document Coverage

### architecture.md vs GDDs

**Systems covered in architecture.md:** 18 / 18 system GDDs have corresponding entries in the Module Ownership section.

**Issues found:**

| # | Issue | Severity | Detail |
|---|-------|:--------:|--------|
| ARCH-1 | **AudioManager missing from layer map** | MEDIUM | ADR-0008 defines AudioManager as a new AutoLoad, but `architecture.md` System Layer Map, Module Ownership, and Initialization Order all omit it. Open Question #6 asked "is AudioManager separate?" — ADR-0008 answered yes, but the answer was never integrated into architecture.md. |
| ARCH-2 | **Initialization order mismatch with ADR-0007** | MEDIUM | architecture.md shows 8 AutoLoads with order: SaveSystem(1) → ProfileManager(2) → VocabStore(3) → TtsBridge(4) → StoryManager(5) → TagDispatcher(6) → VoiceRecorder(7) → InterruptHandler(8). ADR-0007 defines 9 AutoLoads with different order: StoryManager at 6 (not 5), TagDispatcher at 7 (not 6), AudioManager inserted at 5. The ADR order is authoritative — architecture.md needs updating. |
| ARCH-3 | **VocabStore API stale** | LOW | architecture.md Module Ownership shows `correct_event()` / `not_correct_event()` but ADR-0006 defines `record_event(word_id, EventType)` with an enum. The ADR is authoritative. |
| ARCH-4 | **ADR list incomplete** | LOW | architecture.md header says "ADRs Referenced: ADR-0001, ADR-0002, ADR-0003" but ADR-0004 through ADR-0008 now exist. |
| ARCH-5 | **Data ownership table missing VoiceRecorder fields** | LOW | The "Data ownership" table in Save/Load Path section lists `vocab_progress.*.recording_paths` as VoiceRecorder-owned but does not list the VocabStore-owned fields that ADR-0006 partitioned (gold_star_count, is_learned, first_star_at, seen, correct). |

### Orphaned Architecture

No systems exist in architecture.md without a corresponding GDD.

---

## Phase 7: Verdict

### Verdict: CONCERNS (⚠️)

**Rationale:** 8 ADRs are mutually consistent with zero conflicts and 100% engine compatibility section coverage. The Foundation layer (SaveSystem, ProfileManager, VocabStore) is fully covered by ADRs. However, 55% of technical requirements (96/176) remain without architectural coverage, spanning the entire Core, Feature, and Presentation layers.

### Blocking Issues

None. No FAIL-level blocking issues. All Foundation and Core data contracts are covered. The gaps are in gameplay logic and UI implementation details that can be addressed incrementally.

### Coverage Gaps by Priority

#### P0 — Must Have Before Coding (Foundation/Core complete, gaps in Feature layer)

| # | Gap | Missing ADR | Systems Affected | Engine Risk |
|---|-----|-------------|-----------------|:-----------:|
| GAP-1 | **VoiceRecorder 全系统** — 14 TRs, zero ADR coverage | ADR-0009 | VoiceRecorder, InterruptHandler, ParentVocabMap, RecordingInviteUI | HIGH (Android permission, AudioStreamMicrophone) |
| GAP-2 | **StoryManager 游戏逻辑** — _advance_step, TTS wait, chapter lifecycle | ADR-0010 | StoryManager, ChoiceUI, TagDispatcher | MEDIUM |
| GAP-3 | **AnimationHandler 状态机** — 14 states, NON_INTERRUPTIBLE, chain routing | ADR-0011 | AnimationHandler, HatchScene, MainMenu, RecordingInviteUI, TagDispatcher | MEDIUM (AnimationMixer 4.3) |
| GAP-4 | **InterruptHandler 平台中断** — Android back button, background flush, FOCUS_IN recovery | ADR-0012 | InterruptHandler, StoryManager, VoiceRecorder | HIGH (WM_GO_BACK_REQUEST 4.6) |

#### P1 — Should Have Before Relevant System

| # | Gap | Missing ADR | Trigger |
|---|-----|-------------|---------|
| GAP-5 | TagDispatcher dispatch protocol + AnimationHandler registration | ADR-0013 | Before TagDispatcher coding |
| GAP-6 | MainMenu launch sequence + begin_session contract | ADR-0014 | Before MainMenu coding |
| GAP-7 | RecordingInviteUI hold-to-record + signal contract | ADR-0015 | Before RecordingInviteUI coding |
| GAP-8 | HatchScene ceremony sequence + performance budget | ADR-0016 | Before HatchScene coding |

#### P2 — Can Defer to Implementation

| # | Gap | Notes |
|---|-----|-------|
| GAP-9 | ChoiceUI FOCUS_NONE + dual-focus isolation | Implementation detail, GDD is clear |
| GAP-10 | VocabPrimingLoader Tween chain + timing | Self-contained, GDD is complete |
| GAP-11 | Chapter2Teaser static animation | Trivial, zero dependencies |
| GAP-12 | PostcardGenerator SubViewport rendering | Mostly GDD-driven |
| GAP-13 | ParentVocabMap CanvasLayer overlay | Mostly GDD-driven |

### Required ADRs (Prioritized)

| Priority | ADR | Title | Covers | Engine Risk |
|:--------:|-----|-------|--------|:-----------:|
| P0 | ADR-0009 | **VoiceRecorder Android 录音可行性** | 14 TRs | HIGH |
| P0 | ADR-0010 | **StoryManager 叙事推进引擎** | 8 TRs | MEDIUM |
| P0 | ADR-0011 | **AnimationHandler 状态机架构** | 10 TRs | MEDIUM |
| P0 | ADR-0012 | **InterruptHandler 平台中断协议** | 12 TRs | HIGH |
| P1 | ADR-0013 | **TagDispatcher 标签分发协议** | 8 TRs | LOW |
| P1 | ADR-0014 | **MainMenu 启动序列** | 12 TRs | LOW |
| P1 | ADR-0015 | **RecordingInviteUI 录音邀请交互** | 11 TRs | LOW |
| P1 | ADR-0016 | **HatchScene 孵化仪式序列** | 13 TRs | LOW |

### Architecture Document Fixes Needed

| # | Fix | Severity |
|---|-----|:--------:|
| 1 | Add AudioManager to System Layer Map, Module Ownership, and Initialization Order | MEDIUM |
| 2 | Update AutoLoad initialization order to match ADR-0007 (9 systems, correct order) | MEDIUM |
| 3 | Update VocabStore API from `correct_event()`/`not_correct_event()` to `record_event(word_id, EventType)` | LOW |
| 4 | Update ADRs Referenced list to include ADR-0004 through ADR-0008 | LOW |
| 5 | Add VocabStore field ownership details to Data Ownership table | LOW |

### Immediate Actions

1. **Update `architecture.md`** — Fix the 5 issues listed above (AudioManager, init order, VocabStore API, ADR list, field ownership)
2. **Create ADR-0009 (VoiceRecorder)** — Highest risk gap; Android recording is the project's #1 technical risk
3. **Create ADR-0010 (StoryManager)** — Core gameplay loop depends on this
4. **Create ADR-0011 (AnimationHandler)** — 5+ systems depend on its state machine
5. **Create ADR-0012 (InterruptHandler)** — Platform interrupt handling needs formal specification

### Gate Guidance

When all P0 ADRs (ADR-0009 through ADR-0012) are written and architecture.md is updated, run `/gate-check pre-production` to advance.

### Rerun Trigger

Re-run `/architecture-review` after each new ADR is written to verify coverage improves.
