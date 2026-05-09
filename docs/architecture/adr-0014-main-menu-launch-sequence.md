# ADR-0014: MainMenu Launch Sequence Strategy

## Status
Accepted (2026-05-09)

## Date
2026-05-09

## Engine Compatibility

| Field | Value |
|-------|-------|
| **Engine** | Godot 4.6 |
| **Domain** | UI |
| **Knowledge Risk** | LOW — MainMenu uses standard Control nodes, AnimationPlayer, Timer; no post-cutoff APIs |
| **References Consulted** | `docs/engine-reference/godot/VERSION.md`; `docs/engine-reference/godot/modules/ui.md` |
| **Post-Cutoff APIs Used** | None |
| **Verification Required** | (1) change_scene_to_file() error handling; (2) AnimationHandler recognize → confused deferred path; (3) Parent button long-press 5s on touch devices |

## ADR Dependencies

| Field | Value |
|-------|-------|
| **Depends On** | ADR-0005 (ProfileManager — switch_to_profile, begin_session); ADR-0006 (VocabStore — get_gold_star_count); ADR-0008 (AudioManager — BGM); ADR-0010 (StoryManager — begin_chapter, state); ADR-0011 (AnimationHandler — play_recognize, play_confused, play_sitting) |
| **Enables** | GameScene (receives begin_chapter); ParentVocabMap (long-press navigation) |
| **Blocks** | MainMenu implementation; First-launch flow completion; Parent entry point |
| **Ordering Note** | Must be Accepted after ADR-0010 and ADR-0011. Can be implemented in parallel with ADR-0013 (TagDispatcher) and ADR-0015 (RecordingInviteUI). |

## Context

### Problem Statement

MainMenu is the player's home base — the first screen after app launch (post-first-launch). It must serve two audiences simultaneously: the child (who sees T-Rex recognize them and presses "Depart on Adventure!") and the parent (who sees gold star counts and can access the vocabulary map via long-press). The system manages a complex 6-state machine, a strict 7-step launch sequence, profile switching, and deferred animation handling during LOAD_ERROR.

### Constraints

- **Two audiences**: Child-focused (T-Rex animations, big buttons) and parent-focused (profile switcher, gold stars, parent entry)
- **No optimistic UI**: Profile switch must wait for profile_switched signal confirmation
- **begin_session() once**: Per App visit, not per chapter; _session_started flag prevents repeats
- **LOAD_ERROR retry**: Max 3 retries; 3rd failure shows "tell adult" link
- **Parent entry**: 5-second long-press with bubble + progress ring; P2 Anti-Pillar (no forced parent login)
- **AnimationHandler integration**: recognize → confused deferred path during LOAD_ERROR

### Requirements

- 6 states: IDLE_SINGLE, IDLE_MULTI, PROFILE_SWITCHING, PARENT_HOLD, LAUNCHING_GAME, LOAD_ERROR
- 7-step launch sequence (disable → check SM → begin_session → connect signal → init flag → begin_chapter → check flag → navigate)
- Profile switcher: visible only when 2+ profiles; no optimistic update
- Parent button: 80dp, long-press 5s, bubble "需要大人帮忙"
- LOAD_ERROR: confused animation, warm amber bubble, retry/exit buttons
- T-Rex entry: recognize for returning players, idle for new players

## Decision

### Architecture

MainMenu is a scene-local Control node with a 6-state machine that orchestrates the gameplay launch flow.

```
┌─────────────────────────────────────────────────────────┐
│  MainMenu (Scene-Local Control Node)                     │
│                                                          │
│  States:                                                 │
│  IDLE_SINGLE (1 profile, no switcher)                    │
│  IDLE_MULTI (2+ profiles, switcher visible)              │
│  PROFILE_SWITCHING (switcher disabled, awaiting signal)   │
│  PARENT_HOLD (bubble visible, long-press charging)       │
│  LAUNCHING_GAME (begin_chapter called, navigating)       │
│  LOAD_ERROR (chapter_load_failed, retry/exit)            │
│                                                          │
│  ┌────────────────────────────────────────────────────┐  │
│  │  Launch Sequence (7 steps, strict order)            │  │
│  │  a. Disable button                                  │  │
│  │  b. Check SM.state == IDLE                          │  │
│  │  c. begin_session() (once per App visit)             │  │
│  │  d. Connect chapter_load_failed (ONE_SHOT)           │  │
│  │  e. Init _launch_failed = false                      │  │
│  │  f. SM.begin_chapter("chapter_1", path)              │  │
│  │  g. Check _launch_failed → navigate or LOAD_ERROR    │  │
│  └────────────────────────────────────────────────────┘  │
│                                                          │
│  Profile Switch:                                          │
│  Click non-active card → PROFILE_SWITCHING                │
│  → PM.switch_to_profile(index)                            │
│  → wait profile_switched signal                          │
│  → update _active_index, recalculate stars                │
│  → return to IDLE_*                                      │
│                                                          │
│  Parent Entry:                                            │
│  Click parent button → PARENT_HOLD (bubble)              │
│  Long-press 5s → PM.flush() → navigate ParentVocabMap    │
│  Tap outside bubble → dismiss                             │
│                                                          │
│  Signals consumed:                                        │
│    PM.profile_switched                                    │
│    SM.chapter_load_failed                                 │
│    AH.animation_completed(RECOGNIZE)                     │
│    PM.profile_switch_requested (for IDLE transition)      │
│                                                          │
│  Calls:                                                   │
│    PM.begin_session() / switch_to_profile() / flush()     │
│    SM.begin_chapter() / is_story_active / state           │
│    VS.get_gold_star_count()                               │
│    AH.play_recognize() / play_confused() / play_sitting() │
│    AudioManager.play_bgm()                                │
└─────────────────────────────────────────────────────────┘
```

### Key Interfaces

```gdscript
# Signals consumed
signal profile_switched(new_index: int)  # from ProfileManager
signal chapter_load_failed(chapter_id: String)  # from StoryManager
signal animation_completed(state: AnimState)  # from AnimationHandler (RECOGNIZE only)

# Internal state
var _active_index: int  # current profile slot
var _session_started: bool = false  # begin_session() once per App visit
var _launch_failed: bool = false  # set by _on_chapter_load_failed
var _fail_count: int = 0  # LOAD_ERROR retry counter
var _deferred_confused: bool = false  # RECOGNIZE + LOAD_ERROR concurrent handling
```

### Launch Sequence (7 steps)

The launch sequence is the most critical flow — it must execute in strict order:

| Step | Action | Failure Path |
|------|--------|-------------|
| a | Disable "Depart on Adventure!" button | — |
| b | Check SM.state == IDLE | push_error, re-enable button, abort |
| c | begin_session() if _session_started == false | — |
| d | Connect chapter_load_failed (ONE_SHOT) | — |
| e | _launch_failed = false | — |
| f | SM.begin_chapter("chapter_1", ink_path) | chapter_load_failed fires → _launch_failed = true → LOAD_ERROR |
| g | Check _launch_failed: false → navigate; true → already LOAD_ERROR | change_scene_to_file() error → push_error → LOAD_ERROR |

### LOAD_ERROR + RECOGNIZE Concurrent Handling

When chapter_load_failed fires during trex_recognize playback:
1. `_on_chapter_load_failed`: set `_deferred_confused = true`; connect animation_completed (ONE_SHOT)
2. `_on_recognize_completed(state)`: if state == RECOGNIZE and _deferred_confused → play_confused()
3. If RECOGNIZE not playing when load_failed fires → directly play_confused()
4. Exit LOAD_ERROR ("算了先歇会儿"): disconnect ONE_SHOT connection if still active

### Profile Switch

Click non-active card → PROFILE_SWITCHING → PM.switch_to_profile(index) → wait profile_switched signal → update _active_index, recalculate gold stars, re-evaluate entry animation → return to IDLE_*.

**No optimistic UI**: The profile switcher does not visually update until profile_switched confirms. This prevents stale data display if switch fails.

## Alternatives Considered

### Alternative 1: Scene navigation for each screen (separate MainMenu scene per state)
- **Description**: Create separate scenes for IDLE, LOAD_ERROR, PROFILE_SWITCH
- **Pros**: Isolated state; simpler per-scene code
- **Cons**: Scene transitions add latency; T-Rex animation state lost between scenes; parent button must work across scenes
- **Rejection Reason**: MainMenu's 6 states share AnimationHandler, profile data, and button interactions. Splitting into scenes adds complexity without benefit. A single scene with state machine is simpler.

### Alternative 2: GameRoot-managed launch (MainMenu just emits a signal)
- **Description**: MainMenu emits "launch_requested"; GameRoot handles begin_chapter and navigation
- **Pros**: MainMenu stays pure UI; GameRoot owns all game logic
- **Cons**: GameRoot must know about SM.state, begin_session, chapter_load_failed — duplicating MainMenu's knowledge; adds indirection
- **Rejection Reason**: MainMenu already has intimate knowledge of SM.state and PM.begin_session(). Moving this to GameRoot would create a thin wrapper that adds complexity without clarity.

### Alternative 3: No LOAD_ERROR state (just show error and return to IDLE)
- **Description**: On chapter_load_failed, show error toast and return to IDLE
- **Pros**: Simpler state machine (5 states instead of 6)
- **Cons**: No retry mechanism; child sees error with no path forward; violates P2 (child should always have a way to continue)
- **Rejection Reason**: P2 Anti-Pillar requires that the child always has a path forward. LOAD_ERROR with retry gives the child agency ("再来一次！") rather than a dead end.

## Consequences

### Positive

- Strict 7-step launch sequence prevents race conditions (begin_session, connect signal, begin_chapter ordering)
- _session_started flag prevents duplicate begin_session() calls across retries
- LOAD_ERROR + RECOGNIZE concurrent handling is fully specified (no ambiguous states)
- Profile switch waits for signal confirmation — no stale UI
- Parent entry uses long-press (not tap) to prevent child accidental access

### Negative

- 6-state machine adds complexity; must be tested across all state combinations
- _deferred_confused + ONE_SHOT connection management is fragile — must clean up on LOAD_ERROR exit
- begin_session() timing (step c) is a subtle invariant — easy to get wrong during refactoring

### Risks

| Risk | Severity | Mitigation |
|------|:--------:|------------|
| change_scene_to_file() failure not caught | MEDIUM | Step g checks return value; LOAD_ERROR fallback |
| begin_session() called twice (retry path) | LOW | _session_started flag; Rule 12 skips step c on retry |
| RECOGNIZE + LOAD_ERROR race condition | MEDIUM | _deferred_confused + ONE_SHOT connection; AC covers |
| Parent button 5s too long for 4-year-old | LOW | Tuning knob (3-8s range); parent entry is for adults |

## GDD Requirements Addressed

| GDD System | Requirement | How This ADR Addresses It |
|------------|-------------|--------------------------|
| main-menu.md TR-MM-001 | Active profile guard | Decision: Rule 1 guard |
| main-menu.md TR-MM-002 | T-Rex entry animation | Decision: Rule 3 entry logic |
| main-menu.md TR-MM-003 | Profile switcher visibility | Decision: Rule 5 visibility |
| main-menu.md TR-MM-004 | Launch sequence 7 steps | Decision: Launch Sequence table |
| main-menu.md TR-MM-005 | begin_session() once | Decision: _session_started flag |
| main-menu.md TR-MM-006 | Parent button long-press | Decision: Parent Entry spec |
| main-menu.md TR-MM-007 | PARENT_HOLD_DURATION assert | Decision: tuning knob |
| main-menu.md TR-MM-008 | LOAD_ERROR 3 retries | Decision: _fail_count spec |
| main-menu.md TR-MM-009 | SITTING_INACTIVITY decoupled | Decision: SITTING由MainMenu控制 |
| main-menu.md TR-MM-010 | LOAD_ERROR during RECOGNIZE | Decision: concurrent handling spec |
| main-menu.md TR-MM-011 | No optimistic UI update | Decision: Profile Switch spec |
| main-menu.md TR-MM-012 | PROFILE_SWITCHING unresponsive | Decision: launch sequence guard |
| main-menu.md TR-MM-013 | Layout 360x800dp | Not addressed here — UI spec |

## Performance Implications

- **CPU**: Zero per-frame cost when idle; launch sequence is event-driven
- **Memory**: One scene instance; negligible
- **Load Time**: begin_chapter() is synchronous (~50ms); occurs after TtsBridge warm_cache
- **Network**: None

## Validation Criteria

- AC-01 to AC-08: State machine lifecycle (IDLE, LOAD_ERROR, PROFILE_SWITCHING)
- AC-09 to AC-12: Launch sequence correctness (7 steps, begin_session, retry)
- AC-13 to AC-16: Profile switch (no optimistic UI, signal confirmation)
- AC-17 to AC-20: Parent entry (long-press, bubble, navigation)
- AC-21 to AC-24: LOAD_ERROR handling (confused animation, retry, 3rd failure)

## Related Decisions

- ADR-0005 (ProfileManager switch protocol) — switch_to_profile, begin_session
- ADR-0006 (VocabStore formula) — get_gold_star_count for profile cards
- ADR-0008 (AudioManager BGM) — BGM starts at NameInputScreen, persists
- ADR-0010 (StoryManager narrative engine) — begin_chapter, state check
- ADR-0011 (AnimationHandler state machine) — play_recognize, play_confused, play_sitting
- design/gdd/main-menu.md — MainMenu GDD (full specification)
