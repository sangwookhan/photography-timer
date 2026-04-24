# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build and Test Commands

```bash
# Run all tests
xcodebuild -project PTimer.xcodeproj -scheme PTimer \
  -testPlan PTimer \
  -destination 'platform=iOS Simulator,name=iPhone 17' test

# Run tests without a test plan (same scheme, ad-hoc)
xcodebuild -project PTimer.xcodeproj -scheme PTimer \
  -destination 'platform=iOS Simulator,name=iPhone 17' test

# List available simulator destinations
xcodebuild -showdestinations -project PTimer.xcodeproj -scheme PTimer
```

If `iPhone 17` is unavailable, choose any available iPhone simulator from the destinations list.

To run a single test class, add `-only-testing PTimerTests/<ClassName>` to the command.

## Architecture Overview

PTimer is a portrait-only iPhone app for film photography exposure calculation and countdown timers. The architecture has strict layer boundaries — see the section below on what must not cross them.

### Layer Stack (top to bottom)

**SwiftUI Views** (`*Screen.swift`, `BottomSheetWorkspaceShell.swift`)
- Render only. No business logic. Consume state structs emitted by the view model.

**View Model** (`ExposureCalculatorViewModel.swift`)
- Single `@MainActor ObservableObject` that orchestrates all app state.
- Owns `ExposureCalculator`, `TimerManager`, `ReciprocityCalculationPolicyEvaluator`, persistence stores, and `LockScreenTimerTargetCoordinator`.
- Produces display-state structs consumed by views (e.g. `FilmModeExposureResultState`, `FilmModeDetailsDisplayState`). These are computed properties, not stored state.
- Detects XCTest runtime (`XCTestRuntime.isRunningTests`) and injects NoOp persistence/live-activity implementations so unit tests never hit UserDefaults or ActivityKit.

**Domain / Policy**
- `ExposureCalculator.swift` — pure ND exposure math, shutter formatting, snap-to-full-stop logic.
- `ReciprocityCalculationPolicy.swift` — `ReciprocityCalculationPolicyEvaluator` evaluates a `ReciprocityProfile` against a metered exposure. Evaluation order is a contract: exact table → threshold no-correction → interpolated/extrapolated table → formula → advisory → unsupported.
- `ReciprocityConfidencePresentation.swift` — maps a policy result to a `ReciprocityConfidencePresentation` used for badge styling and text display.
- `ReciprocityDomain.swift` — all domain value types: `FilmIdentity`, `ReciprocityProfile`, rule variants (`threshold`, `formula`, `table`, `advisory`), and adjustment types. Fully `Codable`.

**Timer Runtime** (`Timers/`)
- `TimerManager.swift` — manages running/paused/completed `TimerState` objects, persistence via `UserDefaultsTimerPersistenceStore`, and notification scheduling.
- `LockScreenTimerLiveActivity.swift` — ActivityKit Live Activity for the lock screen widget.
- `TimerCompletionNotificationScheduler.swift`, `CompletedRelativeTimeFormatter.swift` — supporting timer concerns.

**Film Context / Persistence** (`ExposureCalculatorFilmContext.swift`)
- `ActiveExposureCalculatorContext` — transient view-model state (selected film, base shutter, ND stop).
- `PersistentExposureCalculatorContextSnapshot` / `UserDefaultsExposureCalculatorContextPersistenceStore` — persists calculator context across relaunches.
- All persistence stores follow a NoOp/real protocol pair pattern for testability.

**Film Catalog** (`PresetFilmCatalog.swift`, `Resources/LaunchPresetFilmCatalog.json`)
- Preset films load from the bundled JSON at launch via `LaunchPresetFilmCatalog`.

**Widgets** (`PTimerWidgets/`)
- Separate target. `LockScreenTimerTargetWidget.swift` renders the lock screen timer widget.

**App entry** (`PTimerApp.swift`)
- `@UIApplicationDelegateAdaptor` enforces portrait orientation at the UIKit boundary.
- `ActivityKitLockScreenTimerTargetExposer` / `LockScreenTimerTargetCoordinator` manage the Live Activity lifecycle.

### Tests (`PTimerTests/`)

Test files mirror source structure:
- `ExposureCalculator/` — calculation accuracy, ViewModel state, film catalog loading
- `Reciprocity/` — policy evaluation, confidence mapping
- `Timers/` — TimerManager lifecycle, time formatting
- `App/` — workspace shell behavior

## Protected Areas

The following behaviors must not be changed without explicit task-level authorization:

- Exposure calculation rules (`ExposureCalculator.calculate`, snap-to-full-stop, `stabilityEpsilon`)
- Reciprocity policy evaluation order and result semantics (`ReciprocityCalculationPolicyEvaluator`)
- Confidence presentation mapping (`ReciprocityConfidencePresentation`)
- Timer runtime semantics (pause/resume/complete state machine, `TimerManager`)
- Persistence and restore contracts (snapshot schemas, UserDefaults keys)

If a task is UI-only, do not touch policy, calculation, or persistence code.
If a task is policy-only, do not reshape unrelated UI.

## Scope and Working Style

- Read `AGENTS.md` before starting any ticket work — it governs source-of-truth order, scope discipline, and delivery expectations.
- Task specs live at `Docs/tasks/<TICKET_ID>.md`. Use `Docs/tasks/TASK_TEMPLATE.md` for new tickets.
- Prefer the smallest change that satisfies the spec. Do not mix cleanup with focused ticket work.
- Domain or policy changes require unit/regression tests. View-model changes require state-oriented tests.
- Documentation-only changes do not require app test execution.

## Commit Message Format

```
Short imperative summary

Body paragraphs wrapped consistently.

PTIMER-102 Extend quantified extrapolation policy for table-profile
           films beyond the current limit
```

Ticket context lines use `PTIMER-ID Title` format. Wrapped continuation lines use a hanging indent aligned after the ticket ID prefix — not flush-left.
