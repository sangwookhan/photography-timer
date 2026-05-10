# PTIMER-25 task spec — WIP checkpoint backup (2026-05-10)

> **Working-notes copy.** The canonical spec lives in Jira (PTIMER-25)
> and, locally, at `docs/tasks/PTIMER-25.md`, which is intentionally
> excluded from regular ticket commits per repo convention. This
> timestamped copy under `docs/working-notes/` exists only so the
> PTIMER-25 WIP commit on the feature branch is self-contained — a
> resumed session can read the requirements without re-fetching from
> Jira. Do not promote this file to be the canonical spec; treat it
> as a frozen-at-checkpoint reference. Delete this file before the
> final ticket commit.

---

# Task Spec: PTIMER-25 Implement optional Target Shutter mode with stop-difference feedback

## Metadata

- Ticket: `PTIMER-25`
- Epic: `PTIMER-121` (Shooting Workflow Improvements)
- Feature Branch: `feature/PTIMER-121-shooting-workflow-improvements`
- Target Platform: iPhone / SwiftUI / Xcode
- Related Docs:
  - Wiki: `Shooting Timer Requirements` (Target Shutter section)
  - Wiki: `Shooting Timer - Target Shutter Use Cases`

---

## 1. Goal

Add an optional Target Shutter workflow to the shooting calculator.

A photographer can set a desired final exposure duration, keep using the
normal calculator controls, and see how far the current calculated
shooting value sits from that target in photographic stop units.

After the change is complete:

- Target Shutter can be enabled, displayed, edited/cleared, and
  compared against the active calculation.
- Stop difference is shown using readable stop notation
  (e.g. `+1/3 stops`, `-2/3 stops`, `Target matches calculated exposure`).
- Digital workflow compares against Adjusted Shutter.
- Film workflow compares against Corrected Exposure when quantified.
- Film workflow without quantified corrected exposure shows a calm
  unavailable state — never a fabricated stop difference.
- A timer can be started from Target Shutter and is distinguishable
  from Adjusted Shutter / Corrected Exposure timers.
- Target-started timers preserve camera-slot identity metadata.

---

## 2. Scope

- New `TargetShutterModel` feature model owning target duration state
  and active/inactive transitions.
- New `TargetShutterPresenter` that formats stop differences into
  readable strings.
- New display-state structs that the SwiftUI view consumes.
- Facade-level methods on `ExposureCalculatorViewModel` for enabling,
  setting, clearing, and starting a target timer.
- Add `.targetShutter` case to `ExposureTimerSource` and route the
  source label through `TimerCardIdentityPresenter`.
- New compact Target Shutter UI section inside the result area of the
  calculator screen.
- Unit tests for stop-difference calculation, display states, timer
  integration, and source metadata.

---

## 3. Out of Scope

- Inventory-aware ND recommendation.
- Automatic filter combination search.
- Aperture recommendation engine.
- Full reverse-calculator flow.
- Equipment inventory model.
- Development compensation recommendation.
- Redesigning the whole calculator layout.
- Changing reciprocity calculation policy or non-preset profile editing.
- Persistence of the target across app relaunches (in-session state
  only for first implementation).
- Persisting per-slot target values across slot switches.

---

## 4. Protected / Do-Not-Change Areas

- `ExposureCalculator.calculate` and snap-to-full-stop logic.
- Reciprocity policy evaluation order.
- Confidence presentation mapping.
- Timer runtime semantics (`TimerManager` state machine).
- Existing persistence schemas and `UserDefaults` keys.

---

## 5. Constraints and Policy

- One-way reads; no business logic in SwiftUI views.
- Feature models do not import each other; cross-model wiring lives
  on `WorkspaceCoordinator`.
- Source-of-truth ownership: the new target state lives only on
  `TargetShutterModel`.
- Timer source enum: stored as `rawValue` so adding the new case
  preserves backward compatibility for older snapshots.
- Display strings (`Target Shutter`, `Target matches calculated exposure`,
  etc.) live in the presentation layer, never in the runtime/domain
  layer.

---

## 6. Expected Approach

1. Add `.targetShutter` to `ExposureTimerSource` and the source label
   in `TimerCardIdentityPresenter`.
2. Create a `TargetShutterModel` with the in-session target duration
   state plus enable / set / clear mutators.
3. Wire the new model through `WorkspaceCoordinator` and expose
   read-only target display state on `ExposureCalculatorViewModel`.
4. Add a `TargetShutterPresenter` that, given a target value plus a
   comparison value (or no comparison), produces the display state
   for the Target Shutter card (status text, stop-difference text,
   timer-action state).
5. Render the new card in the result section of
   `ExposureCalculatorScreen`. Inactive state shows a compact "Set
   Target" affordance; active state shows the duration, the stop
   difference, a start-timer action, and clear/edit actions.
6. Wire `startTargetShutterTimer` on the facade to the same start
   path used by other source timers, stamping the new exposure
   source and the camera-slot identity at start time.
7. Cover the behavior with focused tests at each layer.

---

## 7. Test Requirements

### Required

- `TargetShutterModelTests`: enable, set, clear, validation (zero,
  negative, non-finite rejected).
- `TargetShutterPresenterTests`: stop-difference formatting for
  positive / negative / match cases; rounding/snapping near 1/3-stop
  boundaries; unavailable comparison.
- `ExposureCalculatorViewModelTargetShutterTests`:
  - inactive target produces no comparison display
  - digital workflow compares against Adjusted Shutter
  - film workflow with quantified corrected exposure compares against
    Corrected Exposure
  - film workflow without quantified corrected exposure shows
    unavailable, not a fabricated comparison
  - target remains fixed while base shutter / ND / film selection
    changes
- Timer integration tests:
  - target-started timer carries `.targetShutter` exposure source
  - target-started timer carries the active camera slot
  - target-started timer is created with the target duration
  - target timer can coexist with adjusted/corrected timers

### Suggested Commands

```bash
xcodebuild -project PTimer.xcodeproj -scheme PTimer \
  -destination 'platform=iOS Simulator,name=iPhone 17' test
```

### Manual Checks

1. Launch the app.
2. Open the shooting calculator.
3. Use a non-film setup; set Base Shutter and ND so Adjusted Shutter
   is visible.
4. Enable Target Shutter and set a target such as 1m or 20m.
5. Confirm the target stays visible while changing ND or Base Shutter.
6. Confirm the stop difference updates against Adjusted Shutter.
7. Start a timer from Target Shutter; confirm it is identifiable as
   target-started in the dock and expanded sheet.
8. Switch to a film setup with quantified Corrected Exposure;
   confirm the comparison uses Corrected Exposure.
9. Switch to a film/advisory state without quantified corrected
   exposure; confirm no fabricated stop difference.
10. Clear Target Shutter and confirm the result section returns to
    the original layout.

---

## 8. Definition of Done

- All required behaviors above are implemented.
- All required tests pass locally.
- The change stays within the Scope above.
- Protected behavior is unchanged.
- The PR description includes the manual test procedure.

---

## 9. Review Checkpoints

1. Does the UI clearly communicate inactive vs. active target state?
2. Do digital and film workflows route to the correct comparison
   value?
3. Does the film/advisory path avoid fabricating comparison values?
4. Is the target-started timer clearly distinguishable from
   adjusted/corrected timers in the dock and the expanded sheet?
5. Does the new feature model respect the architecture boundaries?

---

## 10. Delivery Notes

- New files plus targeted edits to facade, view, and presenter
  surfaces.
- No persistence schema change.
- Manual test procedure included in PR description.

---

## 11. Open Questions

- None — the spec is concrete enough for first implementation.
