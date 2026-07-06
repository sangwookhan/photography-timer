<!-- Copyright © 2026 Sangwook Han -->
<!-- SPDX-License-Identifier: Apache-2.0 -->

# PTimer — Architecture

**Type**: Description of current code structure.
**Scope**: The iOS codebase (`ios/` — the SwiftPM package and the
Xcode targets). The Android module structure (`android/`) and the
cross-platform comparison are documented in
[`CrossPlatformArchitectureReview.md`](CrossPlatformArchitectureReview.md);
this document does not describe them.
**Audience**: Engineers working in the codebase who need to know which
file owns which responsibility, where layer boundaries lie, and how the
pieces compose at runtime.
**Direction of influence**: This document follows the requirements
(`docs/requirements/Requirements.md`) and behavior contracts
(`docs/specs/`). When the structure shifts, this file is updated to
match. It does *not* define behavior — if a layer description and a
spec disagree, the spec wins.

PTimer is a portrait-only iPhone app for film-photography exposure
calculation and countdown timers. It has strict layer boundaries
documented below and enforced by a combination of dependency direction,
the package compiler boundary (§0), code review, and SwiftLint custom
rules (see `docs/verification/Strategy.md` §2 L3).

---

## 0. Module layout

The codebase is one SwiftPM package plus two Xcode targets
(PTIMER-177 "Reusable Kit Architecture"; test relocation finished in
PTIMER-174):

- **`PTimerCore`** (`ios/PTimerKit/Sources/PTimerCore/`) — reusable,
  Foundation-only calculation/state engine: exposure math
  (`Exposure/`), the reciprocity domain and policy evaluator
  (`Reciprocity/`), presentation-semantics mapping
  (`PresentationSemantics/`), the timer state machine value types and
  on-disk schema (`Timer/`), and the bundled film catalog
  (`Catalog/`, JSON shipped as a package resource).
- **`PTimerKit`** (`ios/PTimerKit/Sources/PTimerKit/`) — reusable app
  logic built on Core: the view-model facade and feature models,
  presenters and display states, persistence contracts and
  `Persistent*` snapshot schemas (`Persistence/`), the timer runtime
  (`Runtime/`), and a UIKit-free SwiftUI component kit
  (`Components/`, `Theme/`, the details graph view, the target-shutter
  input sheet).
- **App target** (`ios/PTimer/`) — the thin OS shell: SwiftUI screens
  and the workspace shell, concrete `UserDefaults*Store`
  implementations, the RunLoop-based `TimerManager` coordinator,
  notification and ActivityKit adapters, and the DI factory.

The package declares macOS alongside iOS so its tests run
off-simulator via `swift test` and so the compiler enforces the layer
rule mechanically: `PTimerCore` imports Foundation only, and
`PTimerKit` must build without UIKit. Dependency direction is
app → `PTimerKit` → `PTimerCore`, never the reverse.

---

## 1. Layer stack (top to bottom)

Each layer reads from layers below it; no layer reaches up. A layer's
external surface (Live Activity, notifications, persistence keys) is
owned by exactly one collaborator.

### 1.1 SwiftUI Views

Files: `*Screen.swift`, `BottomSheetWorkspaceShell.swift` and the
broader workspace shell breakdown (`BottomSheetWorkspace*` siblings) —
all in the app target (`ios/PTimer/`). Reusable leaf components live
in `PTimerKit` (`Components/`, `FilmDetails/FilmModeDetailsGraphView`,
`TargetShutter/TargetShutterInputSheet`, `Theme/`).

Responsibility: render only. Views consume display-state structs
emitted by the view model facade and model/presenter surfaces. Views
do not mutate runtime state, do not call into the timer manager, and
do not reach into persistence.

### 1.2 Composition / coordination

Files: `WorkspaceCoordinator.swift` (Kit `Workspace/`),
`LockScreenTimerCoordinator.swift` (Kit `LockScreen/`),
`ViewModelDependencyFactory.swift` and
`ActivityKitLockScreenTimerTargetExposer` (app target).

- `WorkspaceCoordinator` is the composition root for the four feature
  models below. It holds strong references, wires the cross-model
  closures (e.g. a model that takes another model's state through an
  opaque closure parameter), and exposes a single observable lifetime
  to the screen.
- `ViewModelDependencyFactory` builds production and test dependency
  bundles. Tests use explicit NoOp dependencies through the factory or
  initializer surface; production code shall not branch on
  test-runtime detection.
- Coordinator types own external-surface lifecycles (Live Activity,
  workspace shell) and reconcile their state. Coordinators are wiring;
  they do not hold business state.

### 1.3 View model facade

File: `ExposureCalculatorViewModel.swift` (Kit `Calculator/`, plus the
`+CustomFilm` extension).

A lightweight `@MainActor ObservableObject` facade that preserves the
established view/test binding surface while delegating responsibility
to the four child models. It republishes model state such as active
film context and running timers, orchestrates cross-model workflows,
and binds timer updates to `LockScreenTimerCoordinator`.

Display-state structs consumed by views (e.g.
`FilmModeExposureResultState`, `FilmModeDetailsDisplayState`) are
computed properties on the facade, not stored business state.

### 1.4 Child models / presenters

All in `PTimerKit`, one directory per feature area:
`Calculator/CalculatorModel`, `Reciprocity/ReciprocityModel`,
`Workspace/TimerWorkspaceModel`, `Film/FilmSelectionModel`,
`CameraSlots/CameraSlotSessionModel`,
`TargetShutter/TargetShutterModel`; presenters sit next to their
feature (e.g. `FilmDetails/FilmModeDetailsPresenter`).

`@Observable` feature models, each owning one slice of state:

- **`CalculatorModel`** — calculator inputs and pure ND calculation.
- **`ReciprocityModel`** — reciprocity policy/presentation transforms.
- **`TimerWorkspaceModel`** — timer collection metadata and timer
  lifecycle commands around `TimerManager`.
- **`FilmSelectionModel`** — preset-film selection, profile override
  state, and calculator-context persistence.
- **`CameraSlotSessionModel`** — active camera-slot identity, the
  per-slot calculator snapshot for inactive slots, and the
  photographer-supplied custom display names keyed by slot id. The
  active slot's live state remains on `CalculatorModel` +
  `FilmSelectionModel`; the session model only stores the inactive
  slot snapshots, the `activeSlotID`, and `customDisplayNames`.
  Snapshot capture and load on slot switch are orchestrated by the
  view-model facade (the only place that already reads/writes both
  `CalculatorModel` and `FilmSelectionModel` in one step). Rename
  and reset are pure session-model mutations
  (`setCustomDisplayName(_:for:)` /
  `resetCustomDisplayName(for:)`); the facade re-publishes them as
  `cameraSlotCustomDisplayNames` so SwiftUI surfaces redraw without
  a slot switch.
- **`TargetShutterModel`** — the active slot's optional Target
  Shutter duration ([Calculator Spec](../specs/Calculator.md) §3.6)
  plus an in-session last-used memory. Per-slot persistence lives on
  the snapshot layer (`CameraSlotCalculatorSnapshot.targetShutterSeconds`);
  the session-global last-used memory is **not** wired into the
  input sheet's seed for an inactive slot, so one slot's last target
  cannot leak onto another.

The feature models do not import each other. Cross-model wiring lives
on `WorkspaceCoordinator`. A model that consumes another model's state
through an opaque closure parameter
(e.g. `currentBaseShutterSeconds: () -> Double`) is permitted but the
closure shall be supplied by `WorkspaceCoordinator`.

`FilmModeDetailsPresenter` is a pure value transform from domain state
into details display state — no lifecycle, no async dependency.

### 1.5 Domain / policy

Module: `PTimerCore`.

- `Exposure/ExposureCalculator.swift` — pure ND exposure math, shutter
  formatting, snap-to-full-stop logic.
- `Reciprocity/ReciprocityCalculationPolicy.swift` —
  `ReciprocityCalculationPolicyEvaluator` evaluates a
  `ReciprocityProfile` against a metered exposure. Evaluation order is
  a contract; see `docs/specs/Calculator.md` §3.2.
- `PresentationSemantics/ReciprocityConfidencePresentation.swift` —
  maps a policy result to a `ReciprocityConfidencePresentation` used
  for badge styling and text display.
- `Reciprocity/ReciprocityDomain.swift` — all domain value types:
  `FilmIdentity`, `ReciprocityProfile`, rule variants (`threshold`,
  `formula`, `limitedGuidance`), `ReciprocitySourceEvidenceRow`, and
  adjustment types. Fully `Codable`.

This layer is platform-neutral and pure-function-flavored. It imports
Foundation only — enforced by the package build itself (Core has no
other dependency to import), not just by fitness rule.

### 1.6 Timer runtime

Split across all three modules along the OS boundary:

- `PTimerCore` `Timer/` — `TimerState` (a sum type with
  running/paused/completed cases), the `Persistent*` on-disk schema,
  and the timer-persistence `*Storing` protocol — the one persistence
  contract that lives in Core beside its schema rather than in Kit
  `Persistence/` (§1.7). The on-disk schema is independent of the
  in-memory representation; see `docs/specs/Timer.md` §3.
- `PTimerKit` `Runtime/` — `TimerRuntime`, the pure timer state
  machine (start/pause/resume/tick/reconcile/remove, completion
  events, persistence + notification scheduling through injected
  protocols). `TimerManaging` is the minimal protocol boundary that
  Kit models depend on instead of the app's concrete coordinator;
  it deliberately omits `tick(now:)` (deterministic tick driving is
  a test-support concern).
- App `Timers/` — `TimerManager.swift`, a thin RunLoop/OS coordinator
  that wraps `TimerRuntime` 1:1 and conforms to `TimerManaging`; it
  also defines `UserDefaultsTimerPersistenceStore` and the
  UIKit-dependent completion alert services.
  `LockScreenTimerLiveActivity.swift` (ActivityKit Live Activity) and
  `TimerCompletionNotificationScheduler.swift` (UNUserNotification)
  are the other OS adapters. `CompletedRelativeTimeFormatter` lives in
  Kit `Workspace/`.

### 1.7 Film context / persistence

Contracts and snapshot schemas live in Kit; concrete UserDefaults
stores live in the app target.

- `ActiveExposureCalculatorContext` — transient film-selection state
  (Kit `Calculator/ExposureCalculatorWorkingContext.swift`).
- `PersistentCalculatorContextSnapshot` (Kit `Persistence/`) /
  `UserDefaultsCalculatorContextStore` (app
  `ExposureCalculator/FilmContext/`) — persists selected film plus
  calculator inputs across relaunches.
- Same pattern for the custom-film library, camera-slot session, and
  timer metadata: `Persistent*` schema + `*Storing` protocol in Kit
  `Persistence/`, `UserDefaults*Store` in the app.

All persistence stores follow a `*Storing` protocol pair pattern with a
real implementation plus a `NoOp*` implementation that unit tests use.

### 1.7a Camera slot domain

Directory: Kit `CameraSlots/` (the concrete
`UserDefaultsCameraSlotSessionStore` and the pager/rename views stay in
the app's `ExposureCalculator/CameraSlot/`).

- `CameraSlotIdentity` — `CameraSlotID` enum (`camera1` … `camera4`)
  plus a stable id + default/custom display label pair. The id is
  the only value written to timer metadata; the display label is
  reconstructed on decode and also captured at start time so the
  workspace can render the timer's slot label without resolving the
  id back. The `customDisplayName` field is the photographer-
  supplied label set through the rename surface; it lives on the
  session model and is merged into the identity on read.
- `CameraSlotCalculatorSnapshot` — value type carrying the per-slot
  calculator working state (base shutter, ND, scale mode, selected
  film, profile override, optional `targetShutterSeconds`).
  Live-preview overlays (`CalculatorModel.liveBaseShutter` /
  `liveNDStep`) deliberately stay out of the snapshot — a preview
  only exists while a wheel drag is in flight on the active slot.
- `CameraSlotPageState` — per-slot view-facing snapshot consumed by
  the workspace TabView pages. Active slot reads live calculator
  state; inactive slots read their preserved snapshot from the
  session model.
- `PersistentCameraSlotSession` — on-disk schema
  (`PersistentCameraSlotSessionSnapshot` +
  `PersistentCameraSlotCalculatorSnapshot`) for the multi-slot
  session. Stores raw `CameraSlotID` raw values, film/profile ids,
  and an Optional photographer-supplied `customDisplayName` per
  slot. The runtime resolves ids back through the preset catalog
  and falls back to "No film" for any id no longer in the catalog.
  The `customDisplayName` field is additive; pre-PTIMER-123
  snapshots decode unchanged and the schema version stays at `1`.
- `CameraSlotSessionPersistenceController` — bridges the runtime
  `CameraSlotSessionModel` and the on-disk session snapshot. Owns
  serialise/deserialise so the ViewModel facade stays a thin
  wiring layer.

Slot session state lives on `CameraSlotSessionModel` (see §1.4). The
camera-slot identity that gets stamped on a timer flows into
`PersistentTimerMetadataSnapshot.cameraSlotIDRaw` /
`cameraSlotDisplayName`; both fields are optional so older snapshots
without slot identity decode unchanged.

Multi-slot persistence: every slot's calculator snapshot is saved to
`UserDefaultsCameraSlotSessionStore` under a dedicated
key. On first launch after upgrade, the legacy single-context store
(`UserDefaultsCalculatorContextStore`) is read by
the ViewModel's restore path; once any state mutation happens, the
new session snapshot becomes the source of truth and the legacy key
is ignored.

Exposure-calculated timer identity lives in Kit
`Workspace/ExposureTimerIdentity.swift`:
`ExposureTimerSource` enum + `ExposureTimerIdentitySnapshot` struct.
The timer runtime layer carries no exposure-source concept on
its own — those types describe which exposure computation produced
the timer, which is a calculator-domain concern.

### 1.8 Film catalog

Files: `PTimerCore` `Catalog/PresetFilmCatalogV2.swift` +
`Catalog/LaunchPresetFilmCatalog.v2.json` (a package resource).

Preset films load from the bundled JSON at launch via
`LaunchPresetFilmCatalogV2`. Catalog validation (see
`docs/specs/DomainSchema.md` §12) runs at load time; a failing catalog
is a load-time error rather than a soft-warn.

### 1.9 Widgets

Directory: `ios/PTimerWidgets/` (separate target).

`LockScreenTimerTargetWidget.swift` renders the lock-screen timer
widget. The widget is read-only; user input on the widget is out of
scope.

### 1.10 App entry

File: `PTimerApp.swift`.

`@UIApplicationDelegateAdaptor` enforces portrait orientation at the
UIKit boundary. `ActivityKitLockScreenTimerTargetExposer` /
`LockScreenTimerCoordinator` manage the Live Activity lifecycle.

---

## 2. Source-of-truth ownership

Each piece of state has exactly one owner. UI surfaces shall not
maintain a parallel copy.

| State | Owner |
|---|---|
| Calculator inputs (base shutter, ND) | `CalculatorModel` |
| Selected film + profile override | `FilmSelectionModel` |
| Reciprocity result derivation | `ReciprocityModel` (transform) |
| Running timer collection + remaining time | `TimerRuntime` (wrapped by the app's `TimerManager`; consumed via `TimerWorkspaceModel`) |
| Active camera-slot id + inactive slot snapshots + custom slot display names | `CameraSlotSessionModel` |
| Camera-slot identity stamped on a started timer | `TimerWorkspaceModel` (via `RunningTimerItem.cameraSlot` and `PersistentTimerMetadataSnapshot.cameraSlotIDRaw` / `cameraSlotDisplayName`) |
| Active slot's Target Shutter duration | `TargetShutterModel` |
| Per-slot persisted Target Shutter duration | `CameraSlotCalculatorSnapshot.targetShutterSeconds` |
| Lock-screen Live Activity lifetime | `LockScreenTimerCoordinator` |
| Timer persistence | `UserDefaultsTimerPersistenceStore` |
| Calculator context persistence | `UserDefaultsCalculatorContextStore` |
| Local notifications for completion | `TimerCompletionNotificationScheduler` |

Display state (the structs consumed by SwiftUI views) is *computed*
from these owners, never stored alongside them.

---

## 3. Dependency direction

```
SwiftUI Views                                          [app]
    │
    ▼
WorkspaceCoordinator  ─▶  ExposureCalculatorViewModel (facade)   [Kit]
    │                          │
    ▼                          ▼
CalculatorModel  ReciprocityModel  TimerWorkspaceModel  FilmSelectionModel  CameraSlotSessionModel   [Kit]
    │                                   │
    ▼                                   ▼
Domain / Policy  (pure)  [Core]    TimerRuntime (any TimerManaging)   [Kit]
    │                                   │
    ▼                                   ▼
              concrete UserDefaults*Store + TimerManager (RunLoop)
              + ActivityKit / UNUserNotification adapters       [app]
```

Reads point downward. Writes are confined to the model/runtime layer
that owns the state. The composition root (`WorkspaceCoordinator`) is
the only place allowed to assemble cross-model wiring. Kit reaches the
OS only through protocols (`TimerManaging`, `*Storing`, `*Scheduling`,
the lock-screen exposer); the app target supplies the concrete
implementations through `ViewModelDependencyFactory`.

---

## 4. Naming conventions

These suffix conventions are enforced by code review; new files
introduced for the same role shall reuse them.

- **`*Storing` / `NoOp*` pair** — every persistence target exposes a
  `*Storing` protocol with a real implementation plus a `NoOp*`
  implementation that unit tests use.
- **`*Scheduling`** — same pair pattern for notification or
  live-activity adapters.
- **`Persistent*` prefix** — types that represent a serialized
  snapshot on disk; distinct from runtime state.
- **`*DisplayState` suffix** — transient view-model state struct that
  views consume read-only. Display state is computed, not stored.
  Files holding a single display-state type use the singular
  (`FilmSelectionDisplayState.swift`); files grouping several related
  display-state types use the plural
  (`FilmModeResultDisplayStates.swift`).
- **`*Coordinator` suffix** — types whose responsibility is to own the
  lifecycle of an external surface (Live Activity, dock, workspace)
  and reconcile its state. Coordinators are wiring; they do not hold
  business state.
- **`*Presenter` suffix** — pure-value transforms from domain state
  into display state. Presenters take inputs as parameters (or an
  input struct), produce display-state output, and have no lifecycle
  or async dependency.
- **`*Factory` suffix** — dependency-creation surface for the DI
  boundary. Provides `production()` / `test()` static factories that
  return a `*Dependencies` struct of collaborators.
- **Module-prefixed file groups** — when a directory contains several
  files for one structural area, share a common prefix
  (`BottomSheetWorkspace*` for the workspace shell breakdown,
  `ExposureCalculator*` for calculator-scoped types). Files outside
  that directory do not need the prefix.

---

## 5. Tests mirror this structure

A test lives in the test target of the module that owns its subject
(the PTIMER-174 placement rule; see `AGENTS.md` Build and Test
Commands).

- `ios/PTimerKit/Tests/PTimerCoreTests/` — exposure math and timer
  state-machine value types.
- `ios/PTimerKit/Tests/PTimerKitTests/` — the large majority of the
  suite, run off-simulator via `swift test`: ViewModel/facade state,
  feature models, presenters, reciprocity policy and confidence
  mapping, persistence contracts against in-memory stores, workspace
  snapshots, and the display-state snapshot baselines
  (`Snapshots/` + `__Snapshots__/`). Timer-dependent suites use the
  test-support seams: `FakeTimerManaging` (records starts only — no
  time-advance/transition behavior shall be added) or
  `RuntimeBackedTimerManaging` (wraps the real `TimerRuntime`,
  exposes deterministic `tick(now:)`).
- `ios/PTimerTests/` (app-hosted, simulator) — OS-boundary behavior
  only: the concrete `TimerManager` RunLoop coordinator suites,
  workspace shell + layout metrics, ActivityKit content-state,
  concrete `UserDefaults*Store` round-trips, app view helpers, and
  `RecordReplay/` — display-state and event-sequence baselines that
  fence semantic equivalence across structural changes
  (see `docs/verification/Strategy.md` §2 L2).

---

## 6. Architectural fitness rules

The following invariants are auto-checked on every PR via SwiftLint
custom rules and (where SwiftLint cannot reach) review-time
discipline. The full taxonomy lives in
`docs/verification/Strategy.md` §2 L3 (rules F1–F12).

- `PTimerCore` imports Foundation only; `PTimerKit` shall not import
  UIKit. Both are enforced by the package's macOS build — `swift test`
  failing to compile is the fitness signal.
- Production code shall not detect whether it is running under tests
  (`XCTestRuntime` / `isRunningTests` are forbidden in `ios/PTimer/`).
- The `ExposureCalculatorViewModel` facade shall not import
  `ActivityKit`; lock-screen concerns belong in
  `LockScreenTimerCoordinator`.
- The feature models shall not import each other by type name.
- A SwiftUI view shall observe at most one feature model.
  Cross-cutting state belongs on `WorkspaceCoordinator`.
- The reciprocity result shape (the legacy
  `didReturnCalculatedTime` / `hasCalculatedExposureTime` flag pair)
  shall not be reintroduced; the type is now a sum type.
- The legacy `TimerState` struct constructor (`status:` paired with
  optional sibling fields) shall not be reintroduced; the type is now
  a sum type.

---

## 7. Protected areas

Some layers carry behavioral contracts that shall not be changed
without explicit task-level authorization (see `CLAUDE.md`):

- Exposure calculation rules
  (`ExposureCalculator.calculate`, snap-to-full-stop,
  `stabilityEpsilon`).
- Reciprocity policy evaluation order and result semantics
  (`ReciprocityCalculationPolicyEvaluator`).
- Confidence presentation mapping
  (`ReciprocityConfidencePresentation`).
- Timer runtime semantics (pause / resume / complete state machine —
  `TimerRuntime` in Kit and the app's `TimerManager` coordinator).
- Persistence and restore contracts (snapshot schemas, UserDefaults
  keys).

If a task is UI-only, do not touch policy, calculation, or persistence
code. If a task is policy-only, do not reshape unrelated UI.
