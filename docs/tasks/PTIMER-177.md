# Task Spec: PTIMER-177 / PTIMER-174 — Reusable Kit Architecture

## Metadata

- Ticket: `PTIMER-177` (carries `PTIMER-174` goal)
- Epic: `PTIMER-176` (Test suite scale, redundancy, execution cost)
- Base commit: `e6a3004` (the `main` this work started from)
- Target Platform: `iPhone / SwiftUI / Xcode`
- Prior work (reference only, do not patch):
  - `feature/PTIMER-174-test-suite-rationalization`
  - `feature/PTIMER-177-timer-state-machine`
  - `feature/PTIMER-177-timer-runtime` (latest combined exploration; abandoned at WIP `798403d`)

**Status (2026-06-10).** The three-layer architecture (§§1–8) has
landed. Phases C8 (SwiftUI component kit) and C9 (off-simulator test
relocation) merged to `main` via PR #2. Active branch
`feature/PTIMER-177-c10-viewmodel-testability` carries C10 (ViewModel
testability seam) and the in-progress C11 (reciprocity test
re-architecture by archetype). Current state, metrics, and the remaining
plan are in **§15**; that section supersedes §§9–10 where they differ.

---

## 1. Goal

Design and implement a clean, **API-first** three-layer architecture:

```
PTimer.app  ──▶  PTimerKit  ──▶  PTimerCore
     └──────────────────────────────▶ (app may import Core directly)
```

- **PTimerCore** — reusable, Foundation-only calculation/state **engine**.
- **PTimerKit** — reusable iOS app-logic **+ SwiftUI component kit** built on Core.
- **PTimer.app** — host app: OS integration, navigation, concrete persistence.

After the change, another app could embed PTimerCore (exposure/ND/reciprocity/
timer engine) and PTimerKit (calculator / film / timer SwiftUI component kit)
without importing the host app. The off-simulator unit-test improvement
(PTIMER-174) follows as a **result** of correct placement, not as a target to
chase.

This is **not** a continuation of the old headless-Kit patch series. Kit is now
a reusable SwiftUI component kit, not a headless logic layer.

---

## 2. Scope

- Stand up one local Swift package `ios/PTimerKit/` with two targets
  (`PTimerCore`, `PTimerKit`) and two test targets.
- Move the pure engine into **PTimerCore** (exposure/ND/shutter math,
  reciprocity domain + policy + table interpolation, film catalog + JSON
  resource, pure timer state machine, abstract presentation-semantic tokens).
- Move reusable iOS logic **and reusable SwiftUI components** into **PTimerKit**
  (models/view-models, presenters, display states, `TimerRuntime`, the timer
  completion seam, camera-slot/workspace logic, reusable component views).
- Slim `TimerManager` to an **app-side OS coordinator** driving a pure
  `TimerRuntime`; keep `TimerManager` in the app target.
- Keep concrete persistence (UserDefaults stores, keys, migration, legacy
  decode) in the app; keep protocols + snapshots + NoOp doubles in Core/Kit.
- Relocate tests to `PTimerCoreTests` / `PTimerKitTests` **only after** the API
  boundary they validate is stable; keep OS-integration tests app-hosted.

---

## 3. Out of Scope

- No change to exposure calculation results (snap-to-full-stop,
  `stabilityEpsilon`).
- No change to reciprocity policy evaluation order / result semantics.
- No change to confidence presentation mapping semantics.
- No change to timer pause/resume/complete state-machine semantics.
- No change to persistence/restore contracts (snapshot schemas, UserDefaults
  keys).
- Do **not** chase a target off-simulator percentage.
- Do **not** create host-app-composable `DisplayState` constructor/mutation
  APIs (DisplayState stays presenter/model output — Option A).
- Do **not** reduce public access modifiers as a first step.

---

## 4. Protected / Do-Not-Change Areas

Behavior-preserving extraction only; proven by existing tests.

| Protected behavior | Location (current `main`) |
|---|---|
| Exposure math, `snapToFullStop`, `stabilityEpsilon` | `ExposureCalculator.swift` (~L72, L354–376) |
| Reciprocity policy evaluation order & result semantics | `ReciprocityCalculationPolicy.swift` (`…Evaluator`, ~L615+) |
| Confidence presentation mapping | `ReciprocityConfidencePresentation.swift` (mapper, ~L362–607; validators ~L200–241) |
| Catalog rule allow-list validation | `PresetFilmCatalog.swift` (~L134–150) |
| Timer pause/resume/complete state machine | `TimerManager.swift` (`TimerState` methods, ~L510–564) |
| Persistence/restore contracts (schemas, keys) | `TimerManager.swift`, `*Persistence*.swift` |

Moving a protected type across a layer boundary is allowed; **changing its
behavior is not**. Each move is gated by the existing tests for that behavior.

---

## 5. Layer Contracts

### PTimerCore — pure engine (Foundation only)

May contain: calculations, value types, catalog load+validation + JSON
resource, timer state transitions, portable strings, **abstract** semantic
descriptors / tone / badge / confidence / source / range / guidance tokens,
formula text.

Must **not** import: PTimerKit, SwiftUI, UIKit, UserNotifications, ActivityKit,
AudioToolbox, app lifecycle, app storage wiring.

Must **not** output concrete UI types: `SwiftUI.Color`, `UIColor`, `Font`,
`Image`, `View`, `ViewModifier`, `EdgeInsets`, **SF Symbol bindings**.
(A plain string is fine; resolving a string to an `Image`/symbol is Kit's job.)

### PTimerKit — reusable iOS logic + SwiftUI component kit

May import: PTimerCore, SwiftUI, Combine/Observation, Foundation.
May contain: `@Observable`/`ObservableObject` models, presenters, display
states, `TimerRuntime`, the `TimerManaging`/completion seam protocols,
camera-slot/session logic, workspace state/snapshot logic, **reusable SwiftUI
components**, theme/style mapping from Core tokens (incl. SF-symbol-name
resolution), dependency protocols.

Must **not** import: UIKit, UserNotifications, ActivityKit, AudioToolbox.
Must **not** contain: concrete OS feedback/scheduler/live-activity/widget,
app lifecycle, app root navigation, app screen shells, concrete host
persistence (unless explicitly justified and reported first).

### PTimer.app — host app

Owns: app root, navigation/sheet orchestration, app-specific screen
composition, app lifecycle, permission flow, and all OS integration.

**`TimerManager`** stays in the app target as the OS **coordinator**: it owns
RunLoop/tick coordination and **delegates** timer behavior to the pure
`TimerRuntime` (Kit). It does **not** own OS-effect implementations — UIKit
feedback, `UserNotifications`, and ActivityKit/Live Activity are **app-owned
adapters** (each implementing a Kit seam protocol). `TimerManager` invokes those
adapters when needed; it is not itself a haptics/notification/live-activity
implementation.

**Persistence** the app owns: concrete `UserDefaults` stores, storage keys,
migration / legacy decode, and app-lifecycle save/restore wiring. (Persistence
protocols and snapshot value types live in Core/Kit per §8.)

---

## 6. API Design (the three required use-flow answers)

### 6.1 PTimerCore public use flows

- **Load the film catalog**: `LaunchPresetFilmCatalogLoader.loadBundledCatalog()`
  reads the bundled `LaunchPresetFilmCatalog.json` (now a **package resource**
  of PTimerCore via `Bundle.module`) → `[FilmIdentity/Profile]`, throwing a
  typed loader error on malformed/duplicate/invalid entries.
- **Calculate base + ND exposure**: `ExposureCalculator.calculate(...)` over
  `ExposureScale` value types; snap-to-full-stop and `stabilityEpsilon`
  preserved.
- **Apply reciprocity correction**: `ReciprocityCalculationPolicyEvaluator`
  over a `ReciprocityProfile` → `ReciprocityResult` (basis + corrected value);
  formula/table evaluation via `ReciprocityFormula` / `TableInterpolationModel`.
- **Inspect range/source/confidence/guidance**: read the abstract
  presentation-semantic tokens from `ReciprocityConfidencePresentation`
  (category/level/badge style/warning emphasis/source authority/range status +
  portable guidance/explanation/formula text). No UI types.
- **Use pure timer state transitions**: `TimerState` +
  `pausing(at:)/resume(at:)/completed(at:)/updatingStatus(at:)/remainingTime(at:)`
  and `PersistentTimerSnapshot.restore(at:)`. No RunLoop, no OS.

### 6.2 PTimerKit public use flows

- **Embed a calculator component**: host creates a `CalculatorModel`/
  `ExposureCalculatorViewModel` (Kit), injects dependency protocols
  (persistence, timer seam), and renders the Kit calculator/result components.
- **Embed film selector / details components**: host feeds a
  `FilmSelectionDisplayState` / `FilmModeDetailsDisplayState` (produced by Kit
  presenters from Core domain) into the Kit selector/details/graph components.
- **Embed timer card / workspace components**: host observes a `TimerRuntime`
  (Kit), maps it through the workspace snapshot/state stores (Kit), and renders
  the Kit timer-card / workspace component views; host injects OS effects
  (feedback/notifications/live-activity) and concrete persistence through Kit
  seam protocols.
- **Dependencies the host must inject**: concrete `*Storing` persistence,
  `TimerCompletionAlerting`, `TimerCompletionNotificationScheduling`,
  lock-screen target exposer — all defined as protocols in Kit, implemented in
  the app.
- **OS adapters that remain host responsibility**: RunLoop driving
  (`TimerManager`), haptics/audio, notifications, ActivityKit, widget.

### 6.3 PTimer.app responsibilities

- App root (`PTimerApp`), `ContentView`, orientation lock, sheet/navigation
  orchestration, app-specific screen shells.
- `TimerManager` as the OS coordinator: RunLoop/tick coordination +
  delegation to `TimerRuntime`; it calls app-owned OS adapters but does not own
  their implementations.
- App-owned OS adapters (each implements a Kit seam protocol): UIKit feedback,
  `UserNotifications` scheduler, ActivityKit/Live Activity exposer; plus the
  widget extension.
- Concrete `UserDefaults*Store`s, storage keys, migration, legacy decode,
  app-lifecycle save/restore wiring.

---

## 7. Component Placement

### 7.1 PTimerCore (engine) — internal groups: `Exposure / Reciprocity / Catalog / Timer / PresentationSemantics`

| Goes to Core | From |
|---|---|
| `ExposureCalculator`, `ExposureScale` (+ value types) | ExposureCalculator/ |
| `ReciprocityDomain`, `ReciprocityCalculationPolicy`, `TableInterpolationModel` | Reciprocity/ |
| `PresetFilmCatalog` loader + `LaunchPresetFilmCatalog.json` (→ `Bundle.module`) | ExposureCalculator/, Resources/ |
| `ReciprocityConfidencePresentation` (abstract tokens; **protected**) | Reciprocity/ |
| `CustomFilmFormulaGuard`, `CustomProfileSourceType` | FilmContext/ |
| Timer state machine: `TimerState`/`TimerStatus`/`RunningTimer`/`PausedTimer`/`CompletedTimer` | Timers/TimerManager.swift |
| **Timer-only** persistence: `PersistentTimerSnapshot` + collection + `restore(at:)`, `TimerPersistenceStoring` protocol + NoOp | Timers/TimerManager.swift |

Core holds **only** timer-state-machine state/snapshot/protocol. All
model/view-model workflow snapshots and their persistence protocols live in Kit
(§7.2). Pure domain value types referenced by Core math/policy (e.g. exposure /
scale / formula-guard types) stay in Core; identity/workflow value types
(`CameraSlotIdentity`, `CameraSlotCalculatorSnapshot`, `RunningTimerItem`,
`ExposureTimerIdentity`) are Kit-leaning and resolved per the §13 open question.

### 7.2 PTimerKit (logic + components) — internal groups: `Runtime / Calculator / Film / FilmDetails / CustomFilm / TargetShutter / CameraSlots / Workspace / Components / Theme / Persistence / LockScreen / Reciprocity`

**Logic (models / view-models / presenters / display states):**
`CalculatorModel`, `ReciprocityModel`, `TargetShutterModel`,
`ExposureCalculatorViewModel` (+CustomFilm), `FilmSelectionModel`,
`CameraSlotSessionModel`, `TimerWorkspaceModel`, `CustomFilmLibrary`,
`CalculatorDefaults`, `PresetFilmCatalog` identity list; all `*Presenter`s
(~21) and `*DisplayState`s (~8); `ReciprocitySecondaryGuidancePresentation`,
`AlternateReciprocityModels`, `FilmSelectorSupportPresenter` (SF-symbol-name
resolution), `CalculatorContextRestorePlanBuilder`, `CameraSlotPageStateBuilder`,
`TimerStartComposer`, `TimerCardIdentityPresenter`.

**Timer runtime + seam:** `TimerRuntime` (orchestrator, no RunLoop),
`TimerCompletionEvent`, completion seam protocols (`TimerCompletionAlerting`,
`TimerCompletionFeedbackPlaying`, `TimerCompletionNotificationScheduling`),
`CompletedRelativeTimeFormatter`, `LockScreenTimerCoordinator` (selection
logic only — abstraction, not ActivityKit).

**Model/view-model persistence (Kit):** the persistence **protocols** +
**snapshot/value types** + NoOp doubles for Kit workflow state — calculator
context, custom film library, camera-slot session, timer metadata
(`CustomFilmLibraryStoring`/`PersistentCustomFilmLibrarySnapshot`,
`PersistentCalculatorContextSnapshot`, `PersistentCameraSlotSessionSnapshot`,
`PersistentTimerMetadataSnapshot`, etc.). Concrete UserDefaults stores stay in
the app (§7.3).

**Workspace state/snapshot logic (Kit, non-view):** snapshot value types,
presentation state, snapshot/state stores, presentation adapter,
metrics/actions, `TimerCardIdentityPresenter`. (Which of these move is also a
§13 open question; the *views* are classified in §7.4.)

**Reusable SwiftUI components — FIRM (small, clearly reusable):**
- `ExposureCalculatorResultViews` (result rows) — closure-driven cards, no app binding.
- `TargetShutterSectionView` (target-shutter reusable controls) — stateless, callback-driven.
- `FilmModeDetailsGraphView` (+ `…GraphRendering`) — pure graph component over display state.
- timer card component (`CompactTimerCardStripView`) — renders a timer card from snapshot + actions.

Everything else view-side is **report-first** (§7.4), not firm.

### 7.3 PTimer.app (host) — stays

`PTimerApp`, `ContentView`, `ExposureCalculatorScreen`, `FilmModeDetailsView`
(sheet shell), `CustomFilmEditorView` (+ field sheets, live-check),
`FilmSelectorOverlayView`, `RunningTimerPanelView`, `WorkspaceCoordinator`,
`ViewModelDependencyFactory`, layout-style helpers; concrete persistence
(`UserDefaults*Store`, `CameraSlotSessionPersistenceController`); OS effects
(`SystemTimerCompletionFeedbackPlayer`, `ForegroundTimerCompletionAlertService`,
`UserNotification…Scheduler`, `ActivityKitLockScreenTimerTargetExposer`);
`LockScreenTimerLiveActivity`; the `PTimerWidgets` extension; `TimerManager`.

### 7.4 SwiftUI component boundary — **report-first** (decided per commit)

Not firmly decided. Each is settled in the relevant commit with a one-line
reusable-component-vs-app-screen/shell justification before moving:

- `FullScreenTimersWindow` — full-screen timer surface; may be a reusable
  window component or an app screen. *Lean: report — likely app screen.*
- `BottomSheetLargeWorkspaceView` — large workspace list; reusable workspace
  component vs. app-composed screen. *Lean: report — workspace component if it
  takes snapshot + actions cleanly.*
- `CameraSlotRenameSheet` — generic rename form vs. app sheet. *Lean: reusable,
  but confirm no app-flow coupling.*
- `WheelPickerContinuousObserver` — picker gesture helper; uses UIKit
  introspection. *Lean: report — only Kit if UIKit-free.*
- `CameraSlotPagerIndicator` — pure indicator; small reusable candidate.
  *Lean: reusable, confirm no state coupling.*
- `FilmSelectorOverlayView` — overlay shell with app-specific delete/edit flows
  vs. reusable selector body. *Lean: app shell.*
- `RunningTimerPanelView` — tied to workspace lifecycle. *Lean: app screen.*
- `CustomFilmEditorView` family (+ field sheets, live-check) — app-specific
  form. *Lean: app screen.*
- `FilmModeDetailsView` — sheet shell hosting the (reusable) graph component.
  *Lean: app shell; the graph component stays Kit.*

---

## 8. Persistence Split

- **Core** — Core-only persistence: the timer state-machine snapshot
  (`PersistentTimerSnapshot` + `restore(at:)`) and its `TimerPersistenceStoring`
  protocol + NoOp. Nothing model/view-model-specific.
- **Kit** — workflow persistence: model/view-model persistence **protocols**,
  **snapshot/value types**, and NoOp doubles (calculator context, custom film
  library, camera-slot session, timer metadata). No concrete stores.
- **App** — concrete `UserDefaults*Store`s, storage keys, migration / legacy
  decode, and app-lifecycle save/restore wiring. Concrete stores never live in
  Kit, even temporarily.

**Regression requirement (past “user action not saved” bug):**
- **Kit tests** verify a user action triggers a persistence **write through the
  protocol** (using an in-memory/spy `*Storing`).
- **App-hosted tests** verify concrete UserDefaults save/restore, corruption
  fallback, and legacy decode.
- Existing coverage to preserve: `TimerManagerPersistenceRestoreTests`
  (start→persist→restore; pause→freeze→restore),
  `TimerManagerNotificationSchedulingTests`, `B4TimerLifecycleBaselineTests`,
  RecordReplay baselines.

---

## 9. Test Categorization

| Bucket | Examples | Target |
|---|---|---|
| Pure domain (off-sim) | Reciprocity/* (~37), Exposure accuracy/scale, catalog load, table interpolation, timer state-machine (`TimerManagerTests`, pause/resume/reconcile) | `PTimerCoreTests` |
| Reusable logic/component (off-sim) | CustomFilm editor form-state/validation, FilmSelectionModel, presenter/display-state, workspace component logic, DisplayState snapshot tests | `PTimerKitTests` |
| **Mixed — split by assertion** | **ViewModel context-persistence**, camera-slot persistence | see below |
| App-hosted (must stay) | scene-phase lifecycle, notification scheduling, lock-screen/ActivityKit, completion-alert (UIKit), RecordReplay harness + baselines, lifecycle baselines | `PTimerTests` |

**Mixed test split (revision):** ViewModel context-persistence is **not**
blanket app-hosted. Split it:
- protocol **write-through** + **in-memory restore** assertions → `PTimerKitTests`
  candidates (verify the model writes through the persistence protocol and
  restores from a snapshot, using an in-memory/spy store).
- **concrete UserDefaults adapter behavior** (real save/restore, corruption
  fallback, legacy decode) → stays app-hosted (`PTimerTests`).

Move a test group **only after** the boundary it validates is stable. Never
delete/consolidate a test without a surviving coverage path.

---

## 10. Commit Plan (reviewable outcome units)

1. **Package + API skeleton, no behavior change.** Add `ios/PTimerKit/Package.swift`
   (`PTimerCore`, `PTimerKit` + test targets), wire the package into the
   pbxproj/app target; app still builds. No code moved yet.
2. **Extract Core exposure engine.** Move exposure/ND/shutter math + scale value
   types; verify calculator behavior; move math tests to `PTimerCoreTests`.
3. **Extract Core reciprocity + catalog.** Domain + policy + table interpolation
   + confidence tokens + catalog loader + JSON resource (`Bundle.module`);
   verify; move pure reciprocity/catalog tests.
4. **Extract pure timer state machine to Core.** `TimerState`/snapshot/
   persistence protocols; `TimerManager` keeps using them from the app; verify
   with timer state-machine tests (move them to `PTimerCoreTests`).
5. **Extract `TimerRuntime` + completion seam into Kit; slim `TimerManager`**
   to an app-side RunLoop/OS coordinator that delegates to `TimerRuntime` and
   calls app-owned OS adapters. *(177 core decoupling.)*
6. **Establish the persistence boundary (before models move).** Define the
   model/view-model persistence **protocols** + snapshot/value types + NoOp in
   Kit; move concrete `UserDefaults` stores + keys + migration/legacy decode +
   app-lifecycle save/restore wiring to the app. Models then bind to Kit
   protocols; concrete stores never transit through Kit. Preserve the
   save-regression split (Kit write-through; app concrete save/restore +
   corruption fallback + legacy decode).
7. **Move Kit logic layer** — models/view-models/presenters/display states
   (incl. the timer-coupled workspace/camera-slot models now unblocked), binding
   to the Kit persistence protocols from step 6.
8. **Move FIRM reusable SwiftUI components into Kit** — one cohesive group per
   commit (result rows; target-shutter controls; film-details graph; timer
   card). Settle each §7.4 report-first view here with a one-line justification
   **before** moving it.
9. **Relocate remaining test groups** to `PTimerCoreTests`/`PTimerKitTests`;
   keep OS-integration/RecordReplay/lifecycle tests app-hosted.
10. **Finalize** — full app-hosted `xcodebuild test`, `swift test`, SwiftLint,
    boundary grep; small cleanup only.

Avoid standalone “move files / fix imports / pbxproj cleanup” commits except as
small trailing cleanups after a behavior-preserving change.

---

## 11. Verification

At each meaningful checkpoint:

```bash
# package off-simulator
swift test --package-path ios/PTimerKit

# focused app-hosted (OS integration still in app)
cd ios && xcodebuild -project PTimer.xcodeproj -scheme PTimer \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing PTimerTests/<Suite> test

# final full app-hosted
cd ios && xcodebuild -project PTimer.xcodeproj -scheme PTimer \
  -testPlan PTimer -destination 'platform=iOS Simulator,name=iPhone 17' test

# lint
cd ios && swiftlint lint
```

**Boundary grep (must pass):**
- PTimerCore imports none of: PTimerKit, SwiftUI, UIKit, UserNotifications,
  ActivityKit, AudioToolbox.
- PTimerKit imports none of: UIKit, UserNotifications, ActivityKit, AudioToolbox.
- `TimerManager` remains under the app target.
- Concrete `UserDefaults` stores remain under the app target.

---

## 12. Definition of Done

- Three-layer package builds; app builds and runs unchanged.
- Protected behaviors unchanged, proven by their existing tests.
- Reusable Core engine + reusable SwiftUI Kit, clean App/Kit/Core separation.
- Persistence regression split in place (Kit write-through + app concrete).
- Tests relocated only where the boundary is stable; OS tests app-hosted.
- All verification (swift test, app-hosted xcodebuild, lint, boundary grep)
  green.
- Final report in the agreed format (verdict / branch+base / API design /
  changed structure / SwiftUI component boundary / persistence / tests /
  verification / risks).

---

## 13. Open Questions / Report-First Items

To resolve during the relevant commit, reporting the call + reason first:

- **Which persistence snapshots/protocols belong in Core vs Kit?** Plan: Core
  holds only the timer state-machine snapshot/protocol; all model/view-model
  workflow snapshots + protocols go to Kit. Confirm per type during commit 6.
- **Which SwiftUI views are reusable components vs app screen shells?** The §7.4
  report-first list (full-screen timer window, bottom-sheet large workspace,
  rename sheet, wheel-picker observer, pager indicator, film selector overlay,
  running timer panel, custom film editor, film-details sheet) — settle per
  commit 8 with a one-line reason each.
- **Which workspace state/snapshot components move to Kit?** The non-view
  snapshot/state stores + presentation adapter + metrics/actions are Kit
  candidates; confirm which during commits 7–8.
- **What is the public Core calculation facade, if any?** Decide whether Core
  exposes a single calculation entry point (e.g. an exposure/reciprocity facade)
  or just the individual engine types. Resolve in commit 2/3.
- **Which `DisplayState` initializers remain public under Option A?** Default:
  public readable properties, **non-public** memberwise init and mutation. Only
  widen if a clear product reason appears — report first.
- Whether `ReciprocityConfidencePresentation` belongs in Core (abstract tokens)
  or Kit. *Plan: Core, as portable semantic tokens; revisit only if it forces an
  unnatural dependency.*
- `WheelPickerContinuousObserver` UIKit usage: if it requires UIKit
  introspection it **cannot** enter Kit and stays in the app.
- **`ExposureCalculator.fullStopShutterSpeeds` / `stabilityEpsilon` public
  surface** — extracted as `public` in commit 2 to preserve current usage
  (`ExposureScale` reads the ladder). Revisit in a later API-hardening pass
  whether these constants should stay public or be hidden behind a narrower
  exposure facade.

---

## 14. Maintained Principles (non-negotiable)

- PTimerCore = reusable Foundation-only engine.
- PTimerKit = reusable iOS app logic + SwiftUI component kit.
- PTimer.app = host app + OS integration.
- PTimerCore may be imported by both the app and Kit.
- PTimerKit may import SwiftUI, but **not** UIKit / UserNotifications /
  ActivityKit / AudioToolbox.
- Off-simulator ratio is an **outcome**, not the acceptance criterion.

---

## 15. Progress & C11 Reciprocity Test Re-Architecture (2026-06-10)

This section records the work done after the architecture (§§1–8) landed
and the live plan. Where it differs from §§9–10, this section wins.

### 15.1 Phases delivered

- **C8 — reusable SwiftUI component kit.** Component theme, result row,
  timer action button, film-details graph, target-shutter card + input
  sheet (moved into Kit under `#if os(iOS)`), and an app-owned
  `WheelTelemetry` seam so the live wheel readout stays app-side while
  the sheet lives in Kit. Merged via PR #2.
- **C9 — off-simulator test relocation.** Pure reciprocity,
  ExposureCalculator, and timer/workspace suites moved (not copied) from
  app-hosted `PTimerTests` into `PTimerCoreTests` / `PTimerKitTests`;
  shared pure helpers duplicated where remaining app tests still need
  them. Merged via PR #2.
- **C10 — ViewModel testability seam.** A package-safe
  `FakeTimerManaging` plus the `TimerManaging` protocol let ViewModel
  suites whose only off-sim blocker was constructing a concrete
  `TimerManager` move to `PTimerKitTests` with no production change.
- **C11 — reciprocity test re-architecture.** Express repeated behavior
  as table-driven contracts and reorganize the reciprocity suite by
  **archetype**. Batch 1: same-file near-duplicates → case tables. Batch
  2: cross-file table-log-log invariants → `TableLogLogReciprocityContractTests`
  (+ a follow-up cleanup commit). Batch 3 (in progress): the full
  archetype re-architecture below.

### 15.2 Metrics (fixed denominator)

- **Baseline total TC = 1502** — the count at `eed873c`, the last commit
  before the PTimerKit package was stood up (100% app-hosted).
- **app-hosted ratio = remaining app-hosted ÷ 1502.** This is the
  primary readout for C8–C10 (how much is still simulator-bound).
  Currently 435 / 1502 ≈ **29.0%** (down from 100%).
- **executable TC reduction = current executable total − 1502.** This is
  the primary readout for C11 (consolidation removing duplicate
  executable functions). Coverage location (the app-hosted ratio) is
  unchanged by C11 because consolidation happens inside the package.

### 15.3 Reciprocity archetype model

An *archetype* is the film's mid-region reciprocity behavior. Films in
one archetype share the same behavior contracts and differ only by case
data, so they are tested as a film-case table, **never** one suite or
one function per film.

**Hard naming rule: a film name must not appear in a test-function
name.** Film identity lives only as case-table data or, for a genuinely
single-film suite, a single `private let film` constant. Function names
describe the behavior contract.

**Reporting scope.** Each stage reports "no film name in a function name"
**only for the archetype files that stage restructures** — never as a
suite-wide claim. Film-named functions still living in the ViewModel /
presenter / catalog test layer (outside the reciprocity-profile
archetypes) are real but out of scope for 3a–3f; they are tracked and
cleaned in **3g** (see §15.4).

| Archetype | Members | Contract suite(s) |
|---|---|---|
| No-source-range bare power-law (ILFORD / HARMAN, `Tc = Tm^p`, no source data) | HP5, Pan F, FP4, Delta 100/400/3200, Kentmere 100/200/400, Ortho, SFX 200, XP2 (12) | `BarePowerLawReciprocityContractTests` |
| Converted guarded formula (inclusive threshold, bounded source range) | Velvia 50, Velvia 100, Provia 100F, ADOX CMS 20 II, Rollei RETRO 80S, SUPERPAN 200 | `GuardedFormula{RegionBasis,Fit,SourceEvidence,Presentation}ContractTests` |
| Constant-multiplier converted formula (open boundary, `< 120 s`) | Acros II | single-film suite, film as a constant |
| Table log-log | T-MAX 100/400, Tri-X 400, Foma 200/400, Fomapan 100 (+ Ohzart community), RPX 100/400, ADOX CHS 100 | `TableLogLogReciprocityContractTests` + a source-data contract |
| Limited guidance | Portra 160/400, Ektar 100, Ektachrome E100 | `LimitedGuidanceReciprocityContractTests` |

Rollei splits across two archetypes: **RPX 100 / RPX 400 → table
log-log**; **RETRO 80S / SUPERPAN 200 → converted guarded formula**.
Authority / provenance (official / community / app-derived / user) is a
case-data column, not an archetype axis — "if the source data differs,
it is a different case."

### 15.4 Stage plan (each its own commit)

- **3a — Ilford bare power-law (done).** New `BarePowerLawReciprocityContractTests`
  over 12 films; dissolved `HP5PlusFormulaProfileTests`.
- **3b — converted guarded formula (done).** Four behavior contracts
  (region-basis, fit, source-evidence, presentation); dissolved Velvia 50,
  Velvia 100, Provia 100F formula suites; CMS 20 II reduced to a
  film-constant remainder.
- **3c — Acros II constant-multiplier (done).** Behavior-named functions,
  film as a constant.
- **3d — table log-log (done; 3d-1 Kodak, 3d-2 Foma/Fomapan + Ohzart
  community via provenance columns, 3d-3 ADOX CHS 100, 3d-4 Rollei split
  RPX→table / RETRO·SUPERPAN→guarded).** All table films + their source
  data are case rows in `TableLogLogReciprocityContractTests` +
  `TableProfileSourceDataContractTests`.
- **3e — limited guidance + model-basis (next).** Case-drive the Kodak
  limited-guidance suite, the bundled model-basis declarations, and the
  related migration invariants into behavior/case contracts.
- **3f — Provia presentation / graph / scale.** Constant-ise the
  film-named graph/scale/presentation tests (these exercise the
  graph/scale engine, not the reciprocity model).
- **3g — ViewModel / presenter / catalog naming cleanup (separate
  theme).** The reciprocity-archetype stages (3a–3f) do not reach the
  ViewModel/presenter/catalog test layer (`ExposureCalculatorViewModelFilm*`,
  `FilmModeDetailsSecondaryGuidancePresenterTests`, `LaunchPresetFilmCatalogTests`,
  `ReciprocityModel{Selection,Metadata,Comparison}PresenterTests`,
  `CustomFilm*`, plus a few cross-cutting reciprocity files). ~70 film-named
  functions there must move film identity into case data / constants and be
  renamed by behavior. Tracked as its own stage so a coherent theme lands
  per commit; it is **not** optional — it must be done.

Each stage: `swift test --package-path ios/PTimerKit` + full app-hosted
`xcodebuild` + SwiftLint + boundary grep, then a single commit. No
production change in any C11 stage; no source-data guard weakened (exact
anchors / parameters / corrected values move to explicit case columns).
