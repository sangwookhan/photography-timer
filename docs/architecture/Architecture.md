# PTimer — Architecture

**Type**: Description of current code structure.
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
code review, and SwiftLint custom rules (see
`docs/verification/Strategy.md` §2 L3).

---

## 1. Layer stack (top to bottom)

Each layer reads from layers below it; no layer reaches up. A layer's
external surface (Live Activity, notifications, persistence keys) is
owned by exactly one collaborator.

### 1.1 SwiftUI Views

Files: `*Screen.swift`, `BottomSheetWorkspaceShell.swift` and the
broader workspace shell breakdown (`BottomSheetWorkspace*` siblings).

Responsibility: render only. Views consume display-state structs
emitted by the view model facade and model/presenter surfaces. Views
do not mutate runtime state, do not call into the timer manager, and
do not reach into persistence.

### 1.2 Composition / coordination

Files: `WorkspaceCoordinator.swift`, `ViewModelDependencyFactory.swift`,
`LockScreenTimerCoordinator.swift`, `ActivityKitLockScreenTimerTargetExposer`.

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

File: `ExposureCalculatorViewModel.swift`.

A lightweight `@MainActor ObservableObject` facade that preserves the
established view/test binding surface while delegating responsibility
to the four child models. It republishes model state such as active
film context and running timers, orchestrates cross-model workflows,
and binds timer updates to `LockScreenTimerCoordinator`.

Display-state structs consumed by views (e.g.
`FilmModeExposureResultState`, `FilmModeDetailsDisplayState`) are
computed properties on the facade, not stored business state.

### 1.4 Child models / presenters

Directory: `ExposureCalculator/Models/`. Plus
`FilmModeDetailsPresenter.swift`.

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
  Shutter duration ([Calculator Spec](../specs/Calculator.md) §3.8)
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

- `ExposureCalculator.swift` — pure ND exposure math, shutter
  formatting, snap-to-full-stop logic.
- `ReciprocityCalculationPolicy.swift` —
  `ReciprocityCalculationPolicyEvaluator` evaluates a
  `ReciprocityProfile` against a metered exposure. Evaluation order is
  a contract; see `docs/specs/Calculator.md` §3.2.
- `ReciprocityConfidencePresentation.swift` — maps a policy result to
  a `ReciprocityConfidencePresentation` used for badge styling and
  text display.
- `ReciprocityDomain.swift` — all domain value types: `FilmIdentity`,
  `ReciprocityProfile`, rule variants (`threshold`, `formula`, `table`,
  `advisory`), and adjustment types. Fully `Codable`.

This layer is platform-neutral and pure-function-flavored. It does not
import UIKit/SwiftUI and (per fitness rule) shall continue not to.

### 1.6 Timer runtime

Directory: `Timers/`.

- `TimerManager.swift` — manages `TimerState` (a sum type with
  running/paused/completed cases) plus persistence via
  `UserDefaultsTimerPersistenceStore` and notification scheduling. The
  on-disk schema is independent of the in-memory representation; see
  `docs/specs/Timer.md` §3.
- `LockScreenTimerLiveActivity.swift` — ActivityKit Live Activity for
  the lock-screen widget.
- `TimerCompletionNotificationScheduler.swift`,
  `CompletedRelativeTimeFormatter.swift` — supporting timer concerns.

### 1.7 Film context / persistence

Directory: `ExposureCalculator/FilmContext/`.

- `ActiveExposureCalculatorContext` — transient film-selection state.
- `PersistentExposureCalculatorContextSnapshot` /
  `UserDefaultsExposureCalculatorContextPersistenceStore` — persists
  selected film plus calculator inputs across relaunches.

All persistence stores follow a `*Storing` protocol pair pattern with a
real implementation plus a `NoOp*` implementation that unit tests use.

### 1.7a Camera slot domain

Directory: `ExposureCalculator/CameraSlot/`.

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
`UserDefaultsCameraSlotSessionPersistenceStore` under a dedicated
key. On first launch after upgrade, the legacy single-context store
(`UserDefaultsExposureCalculatorContextPersistenceStore`) is read by
the ViewModel's restore path; once any state mutation happens, the
new session snapshot becomes the source of truth and the legacy key
is ignored.

Exposure-calculated timer identity lives in
`ExposureCalculator/Models/ExposureTimerIdentity.swift`:
`ExposureTimerSource` enum + `ExposureTimerIdentitySnapshot` struct.
The runtime `Timers/` layer carries no exposure-source concept on
its own — those types describe which exposure computation produced
the timer, which is a calculator-domain concern.

### 1.8 Film catalog

Files: `PresetFilmCatalog.swift`,
`Resources/LaunchPresetFilmCatalog.json`.

Preset films load from the bundled JSON at launch via
`LaunchPresetFilmCatalog`. Catalog validation (see
`docs/specs/DomainSchema.md` §11) runs at load time; a failing catalog
is a load-time error rather than a soft-warn.

### 1.9 Widgets

Directory: `PTimerWidgets/` (separate target).

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
| Running timer collection + remaining time | `TimerManager` (via `TimerWorkspaceModel`) |
| Active camera-slot id + inactive slot snapshots + custom slot display names | `CameraSlotSessionModel` |
| Camera-slot identity stamped on a started timer | `TimerWorkspaceModel` (via `RunningTimerItem.cameraSlot` and `PersistentTimerMetadataSnapshot.cameraSlotIDRaw` / `cameraSlotDisplayName`) |
| Active slot's Target Shutter duration | `TargetShutterModel` |
| Per-slot persisted Target Shutter duration | `CameraSlotCalculatorSnapshot.targetShutterSeconds` |
| Lock-screen Live Activity lifetime | `LockScreenTimerCoordinator` |
| Timer persistence | `UserDefaultsTimerPersistenceStore` |
| Calculator context persistence | `UserDefaultsExposureCalculatorContextPersistenceStore` |
| Local notifications for completion | `TimerCompletionNotificationScheduler` |

Display state (the structs consumed by SwiftUI views) is *computed*
from these owners, never stored alongside them.

---

## 3. Dependency direction

```
SwiftUI Views
    │
    ▼
WorkspaceCoordinator  ─▶  ExposureCalculatorViewModel (facade)
    │                          │
    ▼                          ▼
CalculatorModel  ReciprocityModel  TimerWorkspaceModel  FilmSelectionModel  CameraSlotSessionModel
    │                                   │
    ▼                                   ▼
Domain / Policy  (pure)            TimerManager + persistence + notification
    │                                   │
    ▼                                   ▼
              Persistence (*Storing pair) + ActivityKit / UNUserNotification
```

Reads point downward. Writes are confined to the model/runtime layer
that owns the state. The composition root (`WorkspaceCoordinator`) is
the only place allowed to assemble cross-model wiring.

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

Test files under `PTimerTests/` mirror the source layout:

- `ExposureCalculator/` — calculation accuracy, ViewModel state, film
  catalog loading, feature-model unit tests
  (`CalculatorModelTests`, `ReciprocityModelTests`,
  `TimerWorkspaceModelTests`, `FilmSelectionModelTests`,
  `CameraSlotSessionModelTests`), and the slot-routing facade tests
  (`ExposureCalculatorViewModelCameraSlotsTests`).
- `Reciprocity/` — policy evaluation, confidence mapping.
- `Timers/` — TimerManager lifecycle, time formatting.
- `App/` — workspace shell behavior.
- `RecordReplay/` — display-state and event-sequence baselines that
  fence semantic equivalence across structural changes
  (see `docs/verification/Strategy.md` §2 L2).

---

## 6. Architectural fitness rules

The following invariants are auto-checked on every PR via SwiftLint
custom rules and (where SwiftLint cannot reach) review-time
discipline. The full taxonomy lives in
`docs/verification/Strategy.md` §2 L3 (rules F1–F12).

- Production code shall not detect whether it is running under tests
  (`XCTestRuntime` / `isRunningTests` are forbidden in `PTimer/`).
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
- Timer runtime semantics (pause / resume / complete state machine,
  `TimerManager`).
- Persistence and restore contracts (snapshot schemas, UserDefaults
  keys).

If a task is UI-only, do not touch policy, calculation, or persistence
code. If a task is policy-only, do not reshape unrelated UI.
