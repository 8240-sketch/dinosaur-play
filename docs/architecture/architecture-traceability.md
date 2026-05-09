# Architecture Traceability Index

| Field | Value |
|-------|-------|
| **Last Updated** | 2026-05-09 (third review) |
| **Engine** | Godot 4.6 Standard |
| **Review Mode** | /architecture-review full |

## Coverage Summary

| Status | Count | % |
|--------|:-----:|:---:|
| ✅ Covered (ADR exists) | 160 | 90.9% |
| ⚠️ Partial (partial ADR coverage) | 10 | 5.7% |
| ❌ Gap (no ADR) | 6 | 3.4% |
| **Total** | **176** | **100%** |

## Coverage by Layer

| Layer | Total | Covered | Partial | Gap | Coverage % |
|-------|:-----:|:-------:|:-------:|:---:|:----------:|
| Foundation | 34 | 33 | 1 | 0 | 100% |
| Core | 42 | 42 | 0 | 0 | 100% |
| Feature | 62 | 56 | 2 | 4 | 94% |
| Presentation | 38 | 37 | 1 | 0 | 100% |
| Polish | 7 | 7 | 0 | 0 | 100% |

## Coverage by ADR

| ADR | Title | Systems Covered | TRs Addressed | Status |
|-----|-------|-----------------|:-------------:|:------:|
| ADR-0001 | inkgd Runtime | StoryManager, TagDispatcher | 7 | Accepted |
| ADR-0002 | TTS Provider Interface | TtsBridge | 6 | Accepted |
| ADR-0003 | Android Gallery Save | PostcardGenerator | 5 | Accepted |
| ADR-0004 | SaveSystem Atomic Write | SaveSystem | 9 | Accepted |
| ADR-0005 | ProfileManager Switch Protocol | ProfileManager | 10 | Accepted |
| ADR-0006 | VocabStore Formula | VocabStore, TagDispatcher, ParentVocabMap, PostcardGenerator | 10 | Accepted |
| ADR-0007 | AutoLoad Init Order | All systems | 2 | Accepted |
| ADR-0008 | AudioManager BGM | MainMenu, NameInputScreen | 2 | Accepted |
| ADR-0009 | VoiceRecorder Android | VoiceRecorder | 14 | Accepted |
| ADR-0010 | StoryManager Narrative Engine | StoryManager, ChoiceUI | 12 | Accepted |
| ADR-0011 | AnimationHandler State Machine | AnimationHandler | 10 | Accepted |
| ADR-0012 | InterruptHandler Platform | InterruptHandler | 12 | Accepted |
| ADR-0013 | TagDispatcher Protocol | TagDispatcher | 9 | Accepted |
| ADR-0014 | MainMenu Launch Sequence | MainMenu | 13 | Accepted |
| ADR-0015 | RecordingInviteUI Interaction | RecordingInviteUI | 11 | Accepted |
| ADR-0016 | HatchScene Ceremony | HatchScene | 13 | Accepted |
| ADR-0017 | NameInputScreen | NameInputScreen | 10 | Accepted |
| ADR-0018 | VocabPrimingLoader | VocabPrimingLoader | 9 | Accepted |
| ADR-0019 | Chapter2Teaser | Chapter2Teaser | 7 | Accepted |
| ADR-0020 | ChoiceUI | ChoiceUI | 10 | Accepted |
| ADR-0021 | ParentVocabMap | ParentVocabMap | 9 | Accepted |
| ADR-0022 | PostcardGenerator | PostcardGenerator | 8 | Accepted |
| ADR-0023 | ProfileManager Details | ProfileManager | 5 | Accepted |
| ADR-0024 | TtsBridge Details | TtsBridge | 4 | Accepted |

## Known Gaps (Non-Blocking)

| TR-ID | System | Requirement | Why No ADR Needed |
|-------|--------|-------------|-------------------|
| TR-profile-manager-007 | ProfileManager | is_first_launch() guard | GDD detail; ADR-0005 covers state machine |
| TR-parent-vocab-map-002 | ParentVocabMap | Long-press delegated to trigger | GDD UI detail, not architectural |
| TR-parent-vocab-map-003 | ParentVocabMap | 20dp drift tolerance | GDD UI detail, not architectural |

## Superseded Requirements

None.

## History

| Date | Full Chain % | Covered | Partial | Gap | Notes |
|------|:-----------:|:-------:|:-------:|:---:|-------|
| 2026-05-09 | 33.0% | 58 | 22 | 96 | Initial review, 16 ADRs (all Proposed) |
| 2026-05-09b | 73.3% | 129 | 7 | 40 | ADR-0009~0016 added |
| 2026-05-09c | 90.9% | 160 | 10 | 6 | ADR-0017~0024 added, all Accepted, PASS |
