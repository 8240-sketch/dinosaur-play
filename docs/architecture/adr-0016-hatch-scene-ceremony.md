# ADR-0016: HatchScene Hatching Ceremony Sequence

## Status
Accepted (2026-05-09)

## Date
2026-05-09

## Engine Compatibility

| Field | Value |
|-------|-------|
| **Engine** | Godot 4.6 |
| **Domain** | Animation + Rendering |
| **Knowledge Risk** | MEDIUM — Egg glow shader may behave differently under 4.6 glow pipeline (glow processes BEFORE tonemapping since 4.6); CPUParticles2D performance on low-end Android |
| **References Consulted** | `docs/engine-reference/godot/VERSION.md`; `docs/engine-reference/godot/modules/animation.md`; `docs/engine-reference/godot/breaking-changes.md` (4.6 glow rework) |
| **Post-Cutoff APIs Used** | None — HatchScene uses standard AnimationPlayer, CPUParticles2D, Tween, Timer |
| **Verification Required** | (1) Egg glow shader renders correctly under 4.6 glow pipeline; (2) CPUParticles2D stays within Draw Calls <= 20 budget; (3) Hatch sequence completes within watchdog timeout |

## ADR Dependencies

| Field | Value |
|-------|-------|
| **Depends On** | ADR-0011 (AnimationHandler — hatch_idle/crack/emerge/celebrate chain) |
| **Enables** | NameInputScreen (navigation target after ceremony) |
| **Blocks** | First-launch flow completion; NameInputScreen access |
| **Ordering Note** | Must be Accepted after ADR-0011. Independent of all other ADRs — HatchScene has zero game-system dependencies. |

## Context

### Problem Statement

HatchScene is the game's one-time entry ceremony — executed only on first install when no profiles exist. A trembling egg waits for the child's touch; tapping triggers a crack → emerge → celebrate animation sequence, then navigates to NameInputScreen. The ceremony is pure visual — no data is written, no profiles created. It is the child's first interaction with the game world, establishing the core fantasy: "I made that happen."

### Constraints

- **One-time only**: GameRoot routes here when profile_exists(0) == false; never returns
- **No data writes**: Rule 11 — must NOT call ProfileManager or SaveSystem
- **AnimationHandler chain**: HATCH_CRACK → HATCH_EMERGE → HATCH_CELEBRATE are NON_INTERRUPTIBLE
- **Full-screen touch**: Entire viewport is the tap target (not egg sprite bounding box)
- **Min display protection**: Taps ignored before HATCH_IDLE_MIN_DISPLAY_MS (1500ms)
- **Celebrate hold**: CELEBRATE_SKIP_LOCK_MS (600ms) before tap can skip remaining
- **Watchdog**: HATCH_SEQUENCE_WATCHDOG_MS (8000ms) safety net for animation chain
- **Performance**: Draw Calls <= 20, CPUParticles2D <= 3, texture budget <= 2MB
- **Android back**: WAITING_FOR_TAP → pass to OS; HATCHING → intercept (no-op)

### Requirements

- 3 states: WAITING_FOR_TAP, HATCHING, COMPLETED
- AnimationHandler chain: hatch_idle → hatch_crack → hatch_emerge → hatch_celebrate → signal
- Three-layer visual summoning: tremble, glow pulse, escalation
- Tap feedback during HATCHING: haptic + particles (no interruption)
- Celebrate hold with skip lock
- Watchdog timer for fault tolerance
- change_scene_to_file() to NameInputScreen with fade transition

## Decision

### Architecture

HatchScene is a scene-local node with a 3-state machine that orchestrates the hatching ceremony via AnimationHandler.

```
┌─────────────────────────────────────────────────────────┐
│  HatchScene (Scene-Local Node)                           │
│                                                          │
│  States:                                                 │
│  WAITING_FOR_TAP → HATCHING → COMPLETED                  │
│                                                          │
│  ┌────────────────────────────────────────────────────┐  │
│  │  WAITING_FOR_TAP                                    │  │
│  │  - play_hatch_idle() (tremble loop)                 │  │
│  │  - Min display timer (HATCH_IDLE_MIN_DISPLAY_MS)    │  │
│  │  - 3-layer summoning: tremble + glow + escalation   │  │
│  │  - Full-screen touch target                         │  │
│  │  - Android back → pass to OS                        │  │
│  │                                                     │  │
│  │  Tap accepted → HATCHING                            │  │
│  └────────────────────────────────────────────────────┘  │
│                                                          │
│  ┌────────────────────────────────────────────────────┐  │
│  │  HATCHING                                           │  │
│  │  - play_hatch_crack() → auto chain                  │  │
│  │    CRACK → EMERGE → CELEBRATE → signal              │  │
│  │  - Taps: haptic + particles (no interruption)       │  │
│  │  - Android back → intercept (no-op)                 │  │
│  │  - Watchdog timer (HATCH_SEQUENCE_WATCHDOG_MS)      │  │
│  │                                                     │  │
│  │  hatch_sequence_completed → COMPLETED               │  │
│  └────────────────────────────────────────────────────┘  │
│                                                          │
│  ┌────────────────────────────────────────────────────┐  │
│  │  COMPLETED                                          │  │
│  │  - Celebrate hold timer (CELEBRATE_HOLD_DURATION)   │  │
│  │  - Skip lock (CELEBRATE_SKIP_LOCK_MS = 600ms)      │  │
│  │  - Tap after unlock → skip remaining                │  │
│  │  - Timer expires → navigate to NameInputScreen      │  │
│  │  - change_scene_to_file() with fade >= 400ms        │  │
│  └────────────────────────────────────────────────────┘  │
│                                                          │
│  NO DATA WRITES:                                         │
│  - No ProfileManager.create_profile()                    │
│  - No ProfileManager.begin_session()                     │
│  - No SaveSystem calls                                   │
│  -档案创建在 NameInputScreen 发生                        │
└─────────────────────────────────────────────────────────┘
```

### Key Interfaces

```gdscript
# No public API — scene-local, self-contained

# AnimationHandler calls (via @onready)
func _start_ceremony() -> void:
    # WAITING_FOR_TAP → play_hatch_idle(), start min display timer

func _trigger_hatch() -> void:
    # HATCHING → play_hatch_crack(), connect hatch_sequence_completed

func _on_hatch_completed() -> void:
    # COMPLETED → start celebrate hold + skip lock timers

func _navigate_to_name_input() -> void:
    # COMPLETED → change_scene_to_file() with fade
```

### Three-Layer Visual Summoning

| Layer | Timing | Implementation |
|-------|--------|---------------|
| Layer 1 (Tremble) | Continuous during WAITING_FOR_TAP | AnimationHandler.play_hatch_idle() (loop) |
| Layer 2 (Glow) | Every EGG_GLOW_PERIOD (2.5s) | Egg glow shader: pure brightness variation, no hue shift |
| Layer 3 (Escalation) | After IDLE_ESCALATION_TIMEOUT (8s) | Tremble amplitude 1.5× base value |

### Celebrate Hold + Skip Lock

After hatch_sequence_completed:
1. Start _celebrate_hold_timer (CELEBRATE_HOLD_DURATION = 2.5s)
2. Start _skip_lock_timer (CELEBRATE_SKIP_LOCK_MS = 600ms)
3. Tap during lock → ignore (P4: parent witnesses at least 600ms)
4. Tap after lock → skip remaining, navigate immediately
5. Timer expires → navigate to NameInputScreen
6. Both timers stopped in _exit_tree() (prevents ghost signals)

### Android Back Button

| State | Behavior |
|-------|----------|
| WAITING_FOR_TAP | Pass to OS (exit to desktop; next launch re-routes) |
| HATCHING | Intercept (no-op); prevents hatch_sequence_completed deadlock |
| COMPLETED | Pass to OS or ignore (scene is transitioning) |

## Alternatives Considered

### Alternative 1: Dynamic instantiation of AnimationHandler
- **Description**: Create AnimationHandler as a child node at runtime
- **Pros**: Flexible; scene doesn't need pre-configured AnimationHandler
- **Cons**: GDD Rule 10 requires static child node (not dynamic); dynamic instantiation adds lifecycle complexity
- **Rejection Reason**: GDD explicitly requires AnimationHandler to be a static child node in the scene tree. This is a hard constraint.

### Alternative 2: Use AnimationTree for egg animation
- **Description**: Use AnimationTree for egg trembling and glow
- **Pros**: Visual state machine; built-in blending
- **Cons**: Egg is a 2D sprite; AnimationTree is designed for skeletal animation; hard cut (custom_blend = 0.0) negates blending advantage
- **Rejection Reason**: Same as ADR-0011 — 2D frame sprite animation needs hard cuts, not blending. AnimationPlayer with GDScript state machine is simpler.

### Alternative 3: Skip ceremony on subsequent launches (returning player)
- **Description**: Skip HatchScene even on first install if user has played before on another device
- **Pros**: Faster onboarding for returning players
- **Cons**: HatchScene is per-device (profile_exists(0) check); cross-device state not available; violates "one-time per device" constraint
- **Rejection Reason**: GameRoot routes based on local device state (profile_exists). Cross-device sync is out of scope for MVP.

## Consequences

### Positive

- Pure visual ceremony with zero data dependencies — cannot corrupt game state
- AnimationHandler chain (NON_INTERRUPTIBLE) ensures ceremony completes without interruption
- Three-layer summoning provides escalating visual invitation without text
- Celebrate hold + skip lock balances parent visibility (P4) with child agency
- Watchdog timer prevents dead state if animation chain fails

### Negative

- Egg glow shader may render differently under 4.6 glow pipeline (glow before tonemapping)
- CPUParticles2D performance budget (<=3 active, each amount <=15) is tight on low-end devices
- No LOAD_ERROR UI — change_scene_to_file() failure leaves user stuck (must restart App)

### Risks

| Risk | Severity | Mitigation |
|------|:--------:|------------|
| Egg glow shader looks wrong under 4.6 glow pipeline | MEDIUM | Visual QA on target device; shader uses pure brightness (no hue), less affected by pipeline changes |
| CPUParticles2D exceeds Draw Calls budget | LOW | Limit to 3 active particles, each amount <= 15; verify on low-end device |
| hatch_sequence_completed never fires (animation chain deadlock) | MEDIUM | Watchdog timer (HATCH_SEQUENCE_WATCHDOG_MS = 8000); HATCH_CELEBRATE in NON_INTERRUPTIBLE |
| change_scene_to_file() fails | LOW | push_error; no recovery UI (parent restarts App) |

## GDD Requirements Addressed

| GDD System | Requirement | How This ADR Addresses It |
|------------|-------------|--------------------------|
| hatch-scene.md TR-HS-001 | 3-state machine | Decision: state machine spec |
| hatch-scene.md TR-HS-002 | Min display protection | Decision: _idle_min_timer spec |
| hatch-scene.md TR-HS-003 | 3-layer visual summoning | Decision: Layer table |
| hatch-scene.md TR-HS-004 | Full-screen touch target | Decision: entire viewport |
| hatch-scene.md TR-HS-005 | HATCHING tap feedback | Decision: haptic + particles |
| hatch-scene.md TR-HS-006 | Back button intercept | Decision: Android back table |
| hatch-scene.md TR-HS-007 | CELEBRATE_SKIP_LOCK_MS | Decision: skip lock spec |
| hatch-scene.md TR-HS-008 | Watchdog timer | Decision: HATCH_SEQUENCE_WATCHDOG_MS |
| hatch-scene.md TR-HS-009 | No SaveSystem/ProfileManager | Decision: data boundary spec |
| hatch-scene.md TR-HS-010 | AnimationHandler static child | Decision: @onready %AnimationHandler |
| hatch-scene.md TR-HS-011 | Egg glow shader spec | Decision: pure brightness, no hue |
| hatch-scene.md TR-HS-012 | Performance budget | Decision: Draw Calls <= 20 |
| hatch-scene.md TR-HS-013 | GUT testability wrappers | Not addressed here — testability detail |

## Performance Implications

- **CPU**: CPUParticles2D limited to 3 active, each amount <=15; AnimationPlayer idle loop minimal
- **Memory**: Texture budget <= 2MB compressed; egg sprite + particles
- **Load Time**: Scene loads with GameRoot routing; no async loading needed
- **Network**: None

## Validation Criteria

- AC-01 to AC-05: State machine transitions (WAITING_FOR_TAP → HATCHING → COMPLETED)
- AC-06 to AC-08: Min display protection and tap handling
- AC-09 to AC-12: AnimationHandler chain (crack → emerge → celebrate → signal)
- AC-13 to AC-15: Celebrate hold + skip lock timing
- AC-16 to AC-18: Android back button handling
- AC-19 to AC-21: Watchdog timer and fault tolerance
- AC-22 to AC-24: Performance (Draw Calls, CPUParticles, texture budget)

## Related Decisions

- ADR-0011 (AnimationHandler state machine) — hatch chain states (HATCH_IDLE/CRACK/EMERGE/CELEBRATE)
- design/gdd/hatch-scene.md — HatchScene GDD (full specification)
- design/gdd/animation-handler.md — AnimationHandler hatch states
- design/gdd/name-input-screen.md — navigation target after ceremony
