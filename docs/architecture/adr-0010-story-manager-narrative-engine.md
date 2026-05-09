# ADR-0010: StoryManager Narrative Engine Strategy

## Status
Accepted (2026-05-09)

## Date
2026-05-09

## Engine Compatibility

| Field | Value |
|-------|-------|
| **Engine** | Godot 4.6 |
| **Domain** | Core / Scripting |
| **Knowledge Risk** | MEDIUM — inkgd v0.6.0 (godot4 branch) is post-LLM-cutoff; StoryManager wraps inkgd but the ADR's core logic (state machine, advance model, TTS wait gate) is engine-agnostic GDScript |
| **References Consulted** | `docs/engine-reference/godot/VERSION.md`; `docs/engine-reference/godot/modules/audio.md` (Timer API); ADR-0001 (inkgd runtime — covers loading API) |
| **Post-Cutoff APIs Used** | None beyond ADR-0001 — StoryManager's advance model uses standard GDScript signals, Timer nodes, and call_deferred() |
| **Verification Required** | (1) call_deferred("_advance_step") prevents GDScript synchronous recursion stack overflow on Android; (2) Timer node .stop() works correctly in AutoLoad singleton context; (3) Full Chapter 1 playthrough on Android device |

## ADR Dependencies

| Field | Value |
|-------|-------|
| **Depends On** | ADR-0001 (inkgd runtime — defines InkStory loading and API); ADR-0004 (SaveSystem — flush for chapter completion); ADR-0005 (ProfileManager — switch protocol, signal contract); ADR-0006 (VocabStore — begin/end chapter session); ADR-0007 (AutoLoad init order — StoryManager loads at position 6) |
| **Enables** | ChoiceUI (consumes choices_ready signal); TagDispatcher (consumes tags_dispatched signal); InterruptHandler (consumes chapter_interrupted signal, calls request_chapter_interrupt) |
| **Blocks** | ChoiceUI implementation; TagDispatcher implementation; GameScene (subscribes to tts_fallback_to_highlight); Full gameplay loop |
| **Ordering Note** | Must be Accepted after ADR-0001. ChoiceUI and TagDispatcher can be implemented in parallel after this ADR is Accepted. |

## Context

### Problem Statement

StoryManager is the central narrative engine that drives the entire gameplay loop. It wraps inkgd's InkStory runtime (ADR-0001) and translates branching Ink narratives into GDScript signals that drive TTS (TtsBridge), animations (TagDispatcher → AnimationHandler), vocabulary tracking (VocabStore), and UI (ChoiceUI). The system must manage a complex 7-state lifecycle including chapter loading, narrative advancement with TTS synchronization, choice handling, chapter completion, interrupt handling, and profile switching — all while maintaining strict ordering constraints and synchronous invariants.

### Constraints

- **Single chapter at a time**: StoryManager is an AutoLoad singleton; only one chapter can be active
- **Synchronous invariants**: profile_switch_requested handlers and request_chapter_interrupt must execute without await
- **TTS synchronization**: Each narrative step must wait for TTS completion (or fallback) before advancing
- **Recursive prevention**: _advance_step() must use call_deferred() to prevent GDScript synchronous recursion
- **Timer requirement**: Must use Timer node (not get_tree().create_timer()) for timeout —后者 lacks .stop() method
- **Profile data boundary**: StoryManager owns story_progress section; must not touch vocab_progress or profile sections

### Requirements

- 7-state machine: IDLE → LOADING → RUNNING → CHOICE_PENDING / COMPLETING / STOPPED / ERROR
- begin_chapter() 4-step ordered sequence (guard → vocab load → VocabStore+TtsBridge+TagDispatcher → InkStory load)
- _advance_step() single-step advance model with 3-way wait (speech_completed, tts_not_required, timeout)
- POST_TTS_PAUSE_MS delay after TTS completion before branch judgment
- MAX_CHOICES = 2 truncation
- chapter completion: !can_continue && current_choices.is_empty()
- interrupt protocol: request_chapter_interrupt / confirm_navigation_complete (sync, no await)
- profile_switch_requested sync handler: cancel timers, clear references, emit chapter_interrupted

## Decision

### Architecture

StoryManager is an AutoLoad singleton with a 7-state machine that wraps inkgd InkStory. It owns the narrative advance loop and emits signals consumed by downstream systems.

```
┌───────────────────────────────────────────────────────────────┐
│  StoryManager (AutoLoad Singleton, loading order 6)            │
│                                                                │
│  State Machine:                                                │
│  IDLE → LOADING → RUNNING → CHOICE_PENDING                     │
│                          → COMPLETING → IDLE                    │
│                          → STOPPED → IDLE                      │
│                          → ERROR → IDLE (auto)                  │
│                                                                │
│  ┌────────────────────────────────────────────────────────┐    │
│  │  begin_chapter(chapter_id, ink_json_path)               │    │
│  │  Step a: Guard (must be IDLE + active profile)          │    │
│  │  Step b: Load vocab_ch1.json → _vocab_word_texts       │    │
│  │  Step c: VocabStore.begin + TtsBridge.warm + TagDisp    │    │
│  │  Step d: Load InkStory → RUNNING                        │    │
│  └────────────────────────────────────────────────────────┘    │
│                                                                │
│  ┌────────────────────────────────────────────────────────┐    │
│  │  _advance_step() — single-step advance model            │    │
│  │  1. continue_story() → current_text → emit narration    │    │
│  │  2. current_tags → emit tags_dispatched                 │    │
│  │  3. Wait for: speech_completed | tts_not_required | TO  │    │
│  │  4. POST_TTS_PAUSE_MS delay                             │    │
│  │  5. Branch: choices → CHOICE_PENDING                    │    │
│  │             chapter_end → COMPLETING                     │    │
│  │             can_continue → call_deferred(_advance_step)  │    │
│  └────────────────────────────────────────────────────────┘    │
│                                                                │
│  Signals:                                                      │
│    chapter_started(chapter_id)    → MainMenu                   │
│    chapter_completed(chapter_id)  → MainMenu                   │
│    chapter_interrupted(reason)    → InterruptHandler, ChoiceUI  │
│    chapter_load_failed(chapter_id)→ MainMenu                   │
│    narration_text_ready(text)     → (reserved for MVP)         │
│    tags_dispatched(tags: Array)   → TagDispatcher              │
│    choices_ready(choices: Array)  → ChoiceUI                   │
│                                                                │
│  Calls:                                                        │
│    VocabStore.begin_chapter_session() / end_chapter_session()  │
│    TtsBridge.warm_cache()                                      │
│    TagDispatcher.set_vocab_text_map()                          │
│    ProfileManager.get_section("story_progress") / flush()      │
│                                                                │
│  Subscribes:                                                   │
│    ProfileManager.profile_switch_requested (sync)               │
│    ProfileManager.profile_switched                             │
│    TtsBridge.speech_completed (per-step)                        │
│    TagDispatcher.tts_not_required (persistent)                  │
└───────────────────────────────────────────────────────────────┘
```

### Key Interfaces

**Public API:**

```gdscript
func begin_chapter(chapter_id: String, ink_json_path: String) -> void:
    # 4-step ordered sequence; only valid from IDLE state

func submit_choice(index: int) -> void:
    # Only valid from CHOICE_PENDING state

func request_chapter_interrupt(reason: String) -> void:
    # Called by InterruptHandler; sync, no await
    # Only executes if is_story_active (RUNNING or CHOICE_PENDING)

func confirm_navigation_complete() -> void:
    # Called after user_back_button navigation or FOCUS_IN recovery
    # Only valid from STOPPED state

var is_story_active: bool:  # read-only
    # true when state is RUNNING or CHOICE_PENDING

var current_state: State:  # read-only
    # For InterruptHandler FOCUS_IN recovery check

var current_chapter_id: String:  # read-only
    # Active chapter ID; "" when no chapter active
```

**Signals (all defined in ADR-0001, formalized here):**

```gdscript
signal chapter_started(chapter_id: String)
signal chapter_completed(chapter_id: String)
signal chapter_interrupted(reason: String)  # "profile_switch" | "app_background" | "user_back_button"
signal chapter_load_failed(chapter_id: String)
signal narration_text_ready(text: String)
signal tags_dispatched(tags: Array)  # nullable elements; null-guard in TagDispatcher
signal choices_ready(choices: Array[Dictionary])  # [{index, text, word_id, chinese_text}]
```

### Advance Model (_advance_step)

The core narrative loop uses a single-step advance model to prevent synchronous recursion:

1. Guard: state must be RUNNING
2. `continue_story()` → `current_text` → emit `narration_text_ready`
3. `current_tags` → emit `tags_dispatched`
4. Wait for one of three signals (competing):
   - `TtsBridge.speech_completed` — TTS finished playing
   - `TagDispatcher.tts_not_required` — no vocab tags in this line
   - Timer timeout (`NARRATION_WAIT_TIMEOUT_MS`, default 5000ms) — safety fallback
5. POST_TTS_PAUSE_MS delay (default 150ms)
6. Branch decision (priority order):
   - `current_choices.size() > 0` → CHOICE_PENDING (emit choices_ready)
   - `!can_continue && current_choices.is_empty()` → COMPLETING (Rule 8)
   - `can_continue` → `call_deferred("_advance_step")` (next line)

**Critical invariant**: Steps 2-3 execute synchronously. Step 4 suspends until a signal fires. Steps 5-6 execute after signal receipt. The `call_deferred()` in step 6 prevents GDScript synchronous recursion when multiple consecutive lines have no vocab tags (tags_dispatched → tts_not_required → _advance_step → tags_dispatched → ...).

### Interrupt Protocol

```
InterruptHandler detects platform event
       │
       ▼
VoiceRecorder.interrupt_and_commit()  ← MUST be first (P3 data contract)
       │
       ▼
StoryManager.request_chapter_interrupt(reason)
       │
       ├─ 1. Cancel safety timer; disconnect speech_completed
       ├─ 2. _ink_story = null; clear vocab texts (KEEP _story_data for flush)
       ├─ 3. State → STOPPED (BEFORE emit — prevents re-entrant interrupt)
       └─ 4. emit chapter_interrupted(reason)
              │
              ▼
       InterruptHandler receives signal → ProfileManager.flush()
```

### Profile Switch Contract

`profile_switch_requested` handler (synchronous, no await):
- Cancel safety timer; disconnect speech_completed
- `_ink_story = null`; `_story_data = {}`; clear vocab texts
- Do NOT call VocabStore.end_chapter_session() (chapter interrupted, not completed)
- emit `chapter_interrupted("profile_switch")`
- State → STOPPED

After `profile_switched`:
- Re-acquire `_story_data = ProfileManager.get_section("story_progress")`
- If state == STOPPED → state = IDLE

## Alternatives Considered

### Alternative 1: Frame-based advance (_process polling)
- **Description**: Use _process() to poll inkgd state and advance automatically
- **Pros**: Simpler mental model; no signal wiring needed for TTS wait
- **Cons**: 60fps polling wastes CPU when story is idle (waiting for TTS or choice); harder to integrate TTS synchronization; no clean interrupt protocol
- **Rejection Reason**: TTS synchronization requires signal-based wait, not polling. The advance model must suspend between steps — _process cannot represent this state.

### Alternative 2: Coroutine-based advance (async/await)
- **Description**: Use GDScript await for TTS wait and POST_TTS_PAUSE_MS delay
- **Pros**: Linear code flow; no callback chains; natural for sequential narrative
- **Cons**: profile_switch_requested handler must be synchronous (await in handler breaks flush-load window); interrupt protocol must be sync for InterruptHandler contract; coroutines in AutoLoad singletons have lifecycle complexity
- **Rejection Reason**: Two hard constraints prohibit await: (1) profile_switch_requested sync invariant (ADR-0005); (2) request_chapter_interrupt sync contract (InterruptHandler). The single-step advance model with signal wait is the only approach satisfying both.

### Alternative 3: State machine as separate node (not embedded in StoryManager)
- **Description**: Extract state machine into a dedicated FSM node
- **Pros**: Reusable; testable in isolation; clear separation
- **Cons**: Adds node to scene tree; lifecycle management complexity; StoryManager IS the state machine — separating adds indirection without benefit for a single-use FSM
- **Rejection Reason**: StoryManager's state machine is tightly coupled to its inkgd wrapper and signal emission. Separating would create two nodes that must stay synchronized, increasing complexity without improving testability (GUT can test StoryManager directly).

## Consequences

### Positive

- Single-step advance model prevents synchronous recursion (call_deferred) while maintaining linear code flow
- 3-way TTS wait (speech_completed | tts_not_required | timeout) handles all scenarios: vocab lines, non-vocab lines, and TTS failure
- Interrupt protocol with state-before-emit ordering prevents re-entrant interrupt logic
- Profile switch handler preserves _story_data reference for flush (prevents null reference during signal chain)

### Negative

- call_deferred() means _advance_step is never truly synchronous — debugging requires tracing deferred calls
- Safety timer (NARRATION_WAIT_TIMEOUT_MS) adds complexity; timeout path must be tested as thoroughly as normal path
- POST_TTS_PAUSE_MS adds artificial delay; must be tuned for 4-year-old perception (too fast = cognitive overload, too slow = boredom)

### Risks

| Risk | Severity | Mitigation |
|------|:--------:|------------|
| GDScript synchronous recursion on Android (tts_not_required → _advance_step → tags_dispatched → ...) | HIGH | call_deferred() mandatory; CI static check for await-free handlers |
| TTS timeout too aggressive on slow devices | MEDIUM | NARRATION_WAIT_TIMEOUT_MS = 5000ms default; tunable up to 10000ms |
| Interrupt during LOADING/COMPLETING (not considered "active") | LOW | Rule 13 guard: only RUNNING/CHOICE_PENDING execute; LOADING/COMPLETING are transient |
| _story_data reference stale after profile switch | LOW | profile_switched handler re-acquires reference; request_chapter_interrupt KEEPS reference for flush |

## GDD Requirements Addressed

| GDD System | Requirement | How This ADR Addresses It |
|------------|-------------|--------------------------|
| story-manager.md TR-SM-001 | AutoLoad singleton; single chapter | Decision: StoryManager is AutoLoad with single _ink_story |
| story-manager.md TR-SM-002 | begin_chapter() 4-step sequence | Key Interfaces: begin_chapter() specification |
| story-manager.md TR-SM-003 | _advance_step 3-way wait | Advance Model: speech_completed / tts_not_required / timeout |
| story-manager.md TR-SM-004 | POST_TTS_PAUSE_MS | Advance Model: step 5 delay |
| story-manager.md TR-SM-005 | MAX_CHOICES = 2 truncation | Decision: Rule 5 truncation |
| story-manager.md TR-SM-006 | request_chapter_interrupt / confirm_navigation_complete | Interrupt Protocol: full specification |
| story-manager.md TR-SM-007 | profile_switch sync handler | Profile Switch Contract: synchronous handler spec |
| story-manager.md TR-SM-008 | Ink Rule 15 T-Rex vocab constraint | Not addressed here — Ink authoring constraint, not architecture |
| story-manager.md TR-SM-009 | story_progress schema | Decision: schema definition in Context |
| story-manager.md TR-SM-010 | call_deferred for _advance_step | Advance Model: recursion prevention |
| story-manager.md TR-SM-011 | Timer node (not create_timer) | Advance Model: Timer child node requirement |
| story-manager.md TR-SM-012 | tts_fallback_to_highlight subscription | ADR Dependencies: GameScene subscriber |

## Performance Implications

- **CPU**: _advance_step() is event-driven (signal-triggered), not polled; zero CPU when story is idle
- **Memory**: InkStory runtime state ~50-100 KB; _ink_story = null on interrupt/switch releases immediately
- **Load Time**: begin_chapter() step d (InkStory load) is synchronous; ~50ms expected; occurs after TtsBridge warm_cache so player perceives it as loading
- **Network**: None — all story assets local

## Validation Criteria

- AC-01 to AC-08: State machine lifecycle (IDLE → LOADING → RUNNING → CHOICE_PENDING / COMPLETING / STOPPED / ERROR)
- AC-09 to AC-12: VocabStore integration (begin/end session, warm_cache)
- AC-13 to AC-16: TTS wait behavior (speech_completed, timeout, tts_not_required)
- AC-17 to AC-20: Option handling (submit_choice, MAX_CHOICES truncation)
- AC-21 to AC-24: Profile switch safety (sync handler, no cross-profile contamination)
- AC-29 to AC-36: Interrupt protocol (request_chapter_interrupt, confirm_navigation_complete)

## Related Decisions

- ADR-0001 (inkgd runtime) — defines InkStory loading and API; StoryManager wraps this runtime
- ADR-0002 (TTS provider) — TtsBridge.speech_completed signal consumed by _advance_step wait
- ADR-0004 (SaveSystem atomic write) — chapter completion flushes via ProfileManager
- ADR-0005 (ProfileManager switch protocol) — profile_switch_requested sync handler
- ADR-0006 (VocabStore formula) — begin/end chapter session lifecycle
- ADR-0007 (AutoLoad init order) — StoryManager loads at position 6
- ADR-0008 (AudioManager BGM) — BGM starts at NameInputScreen, persists across chapter transitions
