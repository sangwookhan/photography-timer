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
- Task specs live at `docs/tasks/<TICKET_ID>.md`. Use `docs/tasks/TASK_TEMPLATE.md` for new tickets.
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

## Companion Docs and Conventions

### Documentation map

- **`docs/requirements/Requirements.md`** — user-scenario-driven
  requirements layer between the user-need wiki and the behavior
  contracts. Personas, core scenarios with goals + steps + boundary
  conditions, functional requirements ("system shall …" with
  scenario back-references), non-functional requirements
  (determinism, type safety, architectural fitness, verification,
  performance, persistence stability), and explicit out-of-scope /
  reserved decisions. Read this first when answering "what does the
  app need to do, and why".
- **`docs/specs/{Calculator,Timer,UI,DomainSchema}.md`** — behavior
  contracts. Authoritative description of *what* the system does,
  written so the documents survive refactoring. Wiki and PTIMER-tagged
  commits are cited as `[wiki <page_id>]` and `(PTIMER-XX)`. Specs
  deliberately contain no code identifiers, file paths, or line
  numbers. Specs realize the requirements above at contract level.
- **`docs/verification/`** — five-layer verification strategy and
  rerunnable manual procedures.
- **`docs/conventions/ErrorModel.md`** — when to use `Optional`,
  `throws`, `Result`, and `precondition` in each layer.

### Korean translations

A Korean translation of Requirements and Specs lives under
`docs/translations/ko/` (same filenames). It is for human reference
only — CLAUDE.md and agent tooling reference the canonical English
paths above. Cross-references in any document shall point at the
English path (`docs/specs/Calculator.md`) so the citation graph stays
single-rooted.

### Spec precedence

When code under `PTimer/` disagrees with a spec under `docs/specs/`,
treat it as either a bug or a spec drift, not as a license to ignore
the spec.

1. If wiki, JIRA, or commit history confirms a deliberate change,
   update the spec.
2. Otherwise, change the code to match the spec.

The Protected Areas above carry a stronger form of this rule: a spec
change requires an explicit ticket; do not silently re-derive behavior
from code.

### Naming conventions

- **`*Storing` / `NoOp*` pair** — every persistence target exposes a
  `*Storing` protocol with a real implementation plus a `NoOp*`
  implementation that unit tests use.
- **`*Scheduling`** — same pair pattern for notification or live-
  activity adapters.
- **`Persistent*` prefix** — types that represent a serialized
  snapshot on disk; distinct from runtime state.
- **`*DisplayState` suffix** — transient view-model state struct that
  views consume read-only. Display state is computed, not stored.
  Files holding a single display-state type use the singular
  (`FilmSelectionDisplayState.swift`); files grouping several
  related display-state types use the plural
  (`FilmModeResultDisplayStates.swift`).
- **`*Coordinator` suffix** — types whose responsibility is to own
  the lifecycle of an external surface (Live Activity, dock,
  workspace) and reconcile its state. Coordinators are wiring; they
  do not hold business state. Example:
  `LockScreenTimerTargetCoordinator`.
- **`*Presenter` suffix** — pure-value transforms from domain state
  into display state. Presenters take inputs as parameters (or an
  input struct), produce display-state output, and have no
  lifecycle or async dependency. Example:
  `FilmModeDetailsPresenter`.
- **`*Factory` suffix** — dependency-creation surface for the DI
  boundary. Provides `production()` / `test()` static factories
  that return a `*Dependencies` struct of collaborators. Example:
  `ViewModelDependencyFactory`.
- **Module-prefixed file groups** — when a directory contains
  several files for one structural area, share a common prefix
  (`BottomSheetWorkspace*` for the workspace shell breakdown,
  `ExposureCalculator*` for calculator-scoped types). Files outside
  that directory do not need the prefix.
- **`PTIMER-<n>-` filename prefix** — used only for ticket-scoped
  artifacts that are expected to disappear with the ticket.
  Permanent reference docs drop the prefix on rename.

### Linting

A baseline `.swiftlint.yml` lives at the repo root. The Phase 0 baseline
is intentionally relaxed to avoid churn; size and complexity thresholds
are scheduled for a later commit (B2 in the action plan). Run locally:

```bash
swiftlint lint
```

CI integration is deferred until the platform decision (Bitbucket
Pipelines with self-hosted macOS runner, GitHub Actions, Xcode Cloud,
or local hooks only) is resolved.
