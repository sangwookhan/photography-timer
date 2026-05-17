# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build and Test Commands

Commands are run from the repository root. Cross-platform fixtures
stay at the repo root under `shared/test-fixtures/`.

### iOS

```bash
# Run all tests
cd ios && xcodebuild -project PTimer.xcodeproj -scheme PTimer \
  -testPlan PTimer \
  -destination 'platform=iOS Simulator,name=iPhone 17' test

# Run tests without a test plan (same scheme, ad-hoc)
cd ios && xcodebuild -project PTimer.xcodeproj -scheme PTimer \
  -destination 'platform=iOS Simulator,name=iPhone 17' test

# List available simulator destinations
cd ios && xcodebuild -showdestinations -project PTimer.xcodeproj -scheme PTimer
```

If `iPhone 17` is unavailable, choose any available iPhone simulator from the destinations list.

To run a single test class, add `-only-testing PTimerTests/<ClassName>` to the command.

### Android

```bash
cd android && ./gradlew assembleDebug          # build debug APK
cd android && ./gradlew test                   # unit tests
cd android && ./gradlew lint                   # Android Lint
cd android && ./gradlew installDebug           # install on device/emulator
```

Requires JDK 17 or newer (Android Studio's bundled JBR is
sufficient; for CLI builds, point `JAVA_HOME` at a JDK 17+ install)
and `ANDROID_HOME` pointing at the Android SDK (or
`android/local.properties` with `sdk.dir=<path>`).
`connectedAndroidTest` is not part of skeleton DoD.

Prefer opening the repository root in Android Studio when reviewing
Git history across both platforms. If you open `android/` directly
and Git history is not visible, add the parent repository directory
as a Git root from *Preferences/Settings → Version Control →
Directory mappings*. Do not initialize a new Git repository inside
`android/`, and do not commit `android/.idea/`.

## Architecture Overview

PTimer is a portrait-only iPhone app for film photography exposure
calculation and countdown timers. The architecture has strict layer
boundaries (one-way reads, single-owner state, dedicated coordinators
for external surfaces) and a small set of fitness rules enforced via
SwiftLint.

The current structure — layer-by-layer file ownership, dependency
direction, naming conventions, and source-of-truth ownership table —
lives in [`docs/architecture/Architecture.md`](docs/architecture/Architecture.md). Read that document
when you need to know which file owns which responsibility.

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

Each document has a single role; cross-document references stay
single-rooted on the English paths.

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
  written so the documents survive refactoring. Specs deliberately
  contain no code identifiers, file paths, or line numbers. Specs
  realize the requirements above at contract level.
- **`docs/architecture/Architecture.md`** — current code structure:
  layer stack, file-level responsibilities, dependency direction,
  source-of-truth ownership, naming conventions, and architectural
  fitness rules. Read this when you need to know which file owns
  which responsibility.
- **`docs/verification/Strategy.md`** — five-layer verification
  strategy. `docs/verification/{BackgroundNotificationDelivery,RelaunchRestore}.md`
  are rerunnable manual procedures.
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

When code under `ios/PTimer/` disagrees with a spec under `docs/specs/`,
treat it as either a bug or a spec drift, not as a license to ignore
the spec.

1. Follow the source-of-truth order in `AGENTS.md`.
2. If higher-priority guidance confirms a deliberate behavior change,
   update the spec.
3. Otherwise, change the code to match the spec.

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
  `LockScreenTimerCoordinator`.
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

A baseline `.swiftlint.yml` lives under `ios/`. The Phase 0 baseline
is intentionally relaxed to avoid churn; size and complexity thresholds
may be tightened as the codebase evolves. Run locally from the
repository root:

```bash
cd ios && swiftlint lint
```

CI integration is deferred until the platform decision (Bitbucket
Pipelines with self-hosted macOS runner, GitHub Actions, Xcode Cloud,
or local hooks only) is resolved.
