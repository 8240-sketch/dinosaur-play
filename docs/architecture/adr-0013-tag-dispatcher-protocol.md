# ADR-0013: TagDispatcher Tag Dispatch Protocol

## Status
Accepted (2026-05-09)

## Date
2026-05-09

## Engine Compatibility

| Field | Value |
|-------|-------|
| **Engine** | Godot 4.6 |
| **Domain** | Core |
| **Knowledge Risk** | LOW — TagDispatcher is pure GDScript signal routing with no engine-specific API dependencies |
| **References Consulted** | `docs/engine-reference/godot/VERSION.md` |
| **Post-Cutoff APIs Used** | None |
| **Verification Required** | None — engine-agnostic; all verification is against GDD contract compliance |

## ADR Dependencies

| Field | Value |
|-------|-------|
| **Depends On** | ADR-0001 (inkgd runtime — defines tags_dispatched signal); ADR-0006 (VocabStore — record_event() API); ADR-0010 (StoryManager — tags_dispatched emission, tts_not_required subscription); ADR-0011 (AnimationHandler — play_* semantic API) |
| **Enables** | RecordingInviteUI (recording_invite_triggered signal); ChoiceUI (indirectly — TagDispatcher does not route choices) |
| **Blocks** | TagDispatcher implementation; Full gameplay tag routing; RecordingInviteUI implementation |
| **Ordering Note** | Must be Accepted after ADR-0010 and ADR-0011. Can be implemented in parallel with ADR-0009 (VoiceRecorder) and ADR-0012 (InterruptHandler). |

## Context

### Problem Statement

Ink narrative scripts emit tags (e.g., `vocab:ch1_trex`, `anim:happy`, `record:invite:ch1_trex`) that must be translated into concrete system calls: TTS playback, vocabulary tracking, animation triggering, and recording invites. TagDispatcher is the central dispatch bus that parses these raw tag strings and routes them to the correct system. It also solves StoryManager's open problem: when a narrative line has no vocabulary tags, TagDispatcher emits `tts_not_required()` to skip the 5000ms TTS wait.

### Constraints

- **AutoLoad singleton**: Must survive scene transitions; subscribes to StoryManager.tags_dispatched
- **AnimationHandler dynamic binding**: Per-scene instance, not AutoLoad; must be registered/unregistered via set_animation_handler()
- **P2 Anti-Pillar**: anim:happy and anim:confused execute unconditionally — no correct/not_correct branching for display
- **Direct VocabStore calls**: Both TagDispatcher and VocabStore are AutoLoad; use direct method calls, not signal routing
- **No choice routing**: ChoiceUI subscribes directly to StoryManager.choices_ready; TagDispatcher does not process choices

### Requirements

- Parse 2-segment tags: `vocab:<word_id>` → speak + PRESENTED; `anim:<state>` → play_*
- Parse 3-segment tags: `vocab:<word_id>:correct` → SELECTED_CORRECT; `vocab:<word_id>:not_correct` → NOT_CORRECT; `record:invite:<word_id>` → signal
- Batch processing: process all tags in array order; emit tts_not_required if no 2-segment vocab found
- AnimationHandler registration: set_animation_handler(handler) / null; is_instance_valid guard on every call
- Unknown tags: push_warning, skip, do not interrupt batch
- vocab_text_map: injected by StoryManager for record:invite word_text lookup

## Decision

### Architecture

TagDispatcher is an AutoLoad singleton that subscribes to StoryManager's tags_dispatched signal and dispatches parsed tags to downstream systems.

```
┌─────────────────────────────────────────────────────────┐
│  TagDispatcher (AutoLoad Singleton, loading order 7)     │
│                                                          │
│  Subscribes:                                             │
│    StoryManager.tags_dispatched(tags: Array)             │
│                                                          │
│  References (dynamic):                                   │
│    _animation_handler: AnimationHandler (per-scene)      │
│    _vocab_text_map: Dictionary (injected by StoryManager)│
│                                                          │
│  Tag Parsing:                                            │
│    2-segment "vocab:<word_id>"                           │
│      → TtsBridge.speak(word_id)                          │
│      → VocabStore.record_event(word_id, PRESENTED)       │
│    2-segment "anim:<state>"                              │
│      → _animation_handler.play_<state>()                 │
│    3-segment "vocab:<word_id>:correct"                   │
│      → VocabStore.record_event(word_id, SELECTED_CORRECT)│
│    3-segment "vocab:<word_id>:not_correct"               │
│      → VocabStore.record_event(word_id, NOT_CORRECT)     │
│    3-segment "record:invite:<word_id>"                   │
│      → emit recording_invite_triggered(word_id, word_text)│
│    other → push_warning, skip                            │
│                                                          │
│  Batch Logic:                                            │
│    After processing all tags:                            │
│    if no 2-segment vocab found → emit tts_not_required() │
│                                                          │
│  Signals emitted:                                        │
│    tts_not_required()                                    │
│    recording_invite_triggered(word_id, word_text)        │
│                                                          │
│  Public API:                                             │
│    set_animation_handler(handler) → void                 │
│    set_vocab_text_map(map) → void                        │
└─────────────────────────────────────────────────────────┘
```

### Key Interfaces

```gdscript
# Signals
signal tts_not_required()
signal recording_invite_triggered(word_id: String, word_text: String)

# Public API — called by scenes and StoryManager
func set_animation_handler(handler: AnimationHandler) -> void:
    # Scene _ready() registers; _exit_tree() clears (passes null)

func set_vocab_text_map(map: Dictionary) -> void:
    # StoryManager calls in begin_chapter() step c; clears on chapter end

# Internal — called by tags_dispatched handler
func _dispatch_tag(tag: String) -> void:
    # Parse tag → route to system
```

### Tag Parsing Algorithm

```
parse_tag(raw: String) -> TagAction:
    parts = raw.split(":")
    match parts.size():
        2:
            if parts[0] == "vocab"  → VOCAB_PRESENT(word_id=parts[1])
            if parts[0] == "anim"   → ANIM(state=parts[1])
            else → UNKNOWN_TAG(push_warning)
        3:
            if parts[0] == "vocab" and parts[2] == "correct"     → VOCAB_CORRECT(word_id=parts[1])
            if parts[0] == "vocab" and parts[2] == "not_correct" → VOCAB_NOT_CORRECT(word_id=parts[1])
            if parts[0] == "record" and parts[1] == "invite"     → RECORD_INVITE(word_id=parts[2])
            else → UNKNOWN_TAG(push_warning)
        _ → UNKNOWN_TAG(push_warning)
```

### AnimationHandler Registration Protocol

TagDispatcher holds a nullable reference to AnimationHandler (per-scene, not AutoLoad):

```
Scene._ready():
    TagDispatcher.set_animation_handler(self)  # register

Scene._exit_tree():
    TagDispatcher.set_animation_handler(null)  # clear

TagDispatcher._dispatch_tag("anim:happy"):
    if not is_instance_valid(_animation_handler):
        push_warning("AnimationHandler not registered")
        return
    _animation_handler.play_happy()
```

### P2 Anti-Pillar Enforcement

TagDispatcher executes `anim:happy` and `anim:confused` unconditionally. There is no branching on vocab correct/not_correct to decide which animation to play. The tag format in Ink scripts controls which animation fires — this is the Ink author's responsibility, not TagDispatcher's. This design ensures that:
- The child never sees "wrong = sad animation" (Anti-P2)
- Both paths produce entertaining animations
- TagDispatcher is a dumb router, not a game logic evaluator

## Alternatives Considered

### Alternative 1: Signal-based dispatch (emit signals for each tag type)
- **Description**: TagDispatcher emits vocab_presented, vocab_correct, anim_triggered signals; downstream systems subscribe
- **Pros**: Loose coupling; testable with signal assertions
- **Cons**: 5+ signal types for a simple routing layer; VocabStore.record_event() is a direct call in the GDD (both AutoLoad); adds indirection without benefit
- **Rejection Reason**: TagDispatcher's routing is simple and well-defined. Direct method calls are clearer than signal chains for this use case. VocabStore GDD explicitly specifies direct call (Core Rule 7).

### Alternative 2: Parser as separate node (not embedded in TagDispatcher)
- **Description**: Extract tag parsing into a dedicated TagParser node
- **Pros**: Reusable; testable in isolation
- **Cons**: Parsing is trivial (string split + match); separating adds indirection for ~20 lines of logic
- **Rejection Reason**: Tag parsing is simple enough to embed. The value of TagDispatcher is the routing decision, not the parsing — separating them adds complexity without improving testability.

### Alternative 3: AnimationHandler as AutoLoad (shared across scenes)
- **Description**: Make AnimationHandler a global AutoLoad so TagDispatcher doesn't need dynamic registration
- **Pros**: No set_animation_handler() protocol; simpler code
- **Cons**: AnimationHandler is per-scene (different clip sets per scene); AutoLoad would require scene-aware clip switching
- **Rejection Reason**: AnimationHandler is per-scene by design (ADR-0011). Dynamic registration via set_animation_handler() is the correct pattern for AutoLoad-to-scene component communication.

## Consequences

### Positive

- Simple, explicit routing: each tag type maps to exactly one system call
- P2 Anti-Pillar enforced by design: no correct/not_correct branching in display path
- Dynamic AnimationHandler registration handles scene transitions cleanly
- tts_not_required signal solves StoryManager's TTS wait problem without polling
- Unknown tags are non-fatal (push_warning + skip) — batch processing continues

### Negative

- Dynamic AnimationHandler reference adds runtime complexity (is_instance_valid checks on every anim: tag)
- Tag format is implicit (约定 between Ink author and TagDispatcher) — no compile-time validation
- VALID_ANIM_STATES list must be kept in sync with AnimationHandler's public methods

### Risks

| Risk | Severity | Mitigation |
|------|:--------:|------------|
| AnimationHandler reference stale after scene unload | LOW | is_instance_valid guard; scene _exit_tree() clears reference |
| Ink author uses unknown anim: state | LOW | AnimationHandler method missing → GDScript error; AC-N3 covers validation |
| vocab_text_map empty when record:invite fires | LOW | word_text defaults to ""; push_warning; RecordingInviteUI tolerates empty |
| Multiple 2-segment vocab: tags in one batch | LOW | Each triggers speak() independently; TtsBridge cancels previous; AC-5 covers |

## GDD Requirements Addressed

| GDD System | Requirement | How This ADR Addresses It |
|------------|-------------|--------------------------|
| tag-dispatcher.md TR-TD-001 | AutoLoad singleton; subscribes tags_dispatched | Decision: AutoLoad spec |
| tag-dispatcher.md TR-TD-002 | AnimationHandler registration protocol | Decision: set_animation_handler() + is_instance_valid |
| tag-dispatcher.md TR-TD-003 | Tag vocabulary (2/3 segment) | Decision: parsing algorithm |
| tag-dispatcher.md TR-TD-004 | Batch processing order + tts_not_required | Decision: batch logic spec |
| tag-dispatcher.md TR-TD-005 | P2 Anti-Pillar unconditional anim | Decision: no correct/not_correct branching |
| tag-dispatcher.md TR-TD-006 | vocab_text_map injection | Decision: set_vocab_text_map() spec |
| tag-dispatcher.md TR-TD-007 | VocabStore direct call | Decision: direct method call pattern |
| tag-dispatcher.md TR-TD-008 | choices_ready boundary | Not addressed here — StoryManager owns choices (ADR-0010) |
| tag-dispatcher.md TR-TD-009 | Unknown tags fault tolerance | Decision: push_warning + skip |

## Performance Implications

- **CPU**: Tag parsing is O(n) where n = tags per batch (typically 1-3 tags); negligible
- **Memory**: One nullable AnimationHandler reference + one Dictionary reference; negligible
- **Load Time**: No impact; _ready() only connects StoryManager.tags_dispatched signal
- **Network**: None

## Validation Criteria

- AC-1 to AC-3: vocab: tags route to correct VocabStore event types
- AC-4/5/12: AnimationHandler registration and is_instance_valid guard
- AC-6/7: record:invite signal with word_text from vocab_text_map
- AC-8/9/10: tts_not_required logic (present vs absent 2-segment vocab)
- AC-11: Unknown tags non-fatal
- AC-13/13b: P2 Anti-Pillar — anim:happy and anim:confused unconditional
- AC-N1 to AC-N4: Edge cases (mixed tags, empty word_id, invalid anim state, 4-segment)

## Related Decisions

- ADR-0001 (inkgd runtime) — defines tags_dispatched signal that TagDispatcher subscribes to
- ADR-0006 (VocabStore formula) — record_event() API called by TagDispatcher
- ADR-0010 (StoryManager narrative engine) — emits tags_dispatched, subscribes tts_not_required
- ADR-0011 (AnimationHandler state machine) — play_* semantic API called by TagDispatcher
- design/gdd/tag-dispatcher.md — TagDispatcher GDD (full specification)
- design/gdd/story-manager.md — StoryManager Rule 4d (tags_dispatched emission)
- design/gdd/recording-invite-ui.md — subscribes to recording_invite_triggered
