# PTIMER-146 Android MVP — iOS-to-Android Test-Intent Map

> **Superseded for coverage claims by the individual-test audit in
> [`PTIMER-146-ios-test-parity-audit.md`](PTIMER-146-ios-test-parity-audit.md).**
> That document audits all 1,382 iOS test functions at the per-test-case level
> with explicit Status/Decision and the MVP-blocker list. This file remains the
> area-level companion (notably §7's user-test corrections to the start-action
> model and the emulator-verification notes).

Review artifact for a separate verification session. Maps the behavior iOS
tests protect to the current Android implementation and its tests. iOS tests
were used as behavior-audit sources, not mechanically translated.

## 1. Summary

- **Stopping point:** all ten Round-3 slices implemented (1–10). The Android MVP
  is a working shooting app: per-slot calculator + film selection + reciprocity
  (formula/table/threshold/limited/unsupported) + alternate-model selection +
  Start-Timer enablement; timer lifecycle (start/pause/resume/complete/remove/
  Start-Again) with persistence/restore; camera slots + rename; custom film
  library (formula + table authoring, inspection-only fitted preview,
  Create-Formula-from-table + referenceTableFilmID); Target Shutter; Reciprocity
  Details transparency; and Android completion + ongoing running-timer
  notifications.
- **Completed slices:** 1 module, 2 exposure, 3 reciprocity+catalog+policy+
  confidence+alternates+resolver, 4 timer engine, 5 timer workflow, 6 calculator+
  film+alternate-model, 7 camera slots+rename, 8 custom film, 9 Target Shutter,
  10a Details, 10b notifications.
- **Total Android tests:** **111** (72 `:core`, 39 `:app`), 0 failures.
- **Final verification:** `./gradlew clean :core:test testDebugUnitTest
  assembleDebug` → BUILD SUCCESSFUL. iOS/shared diff vs origin/main: none.
- **Known gaps:** background completion is now a **best-effort scheduled alarm**
  (`AndroidTimerCompletionScheduler`; exact on API < 31, inexact on API 31+
  without `SCHEDULE_EXACT_ALARM`) — see audit doc *Background Timer Completion —
  Pass 5*. A guaranteed exact-alarm permission flow and/or foreground service
  remain deferred (platform work needing device testing);
  custom-table/editor/graph/picker UI polish; no
  `connectedDebugAndroidTest` run (no device; UI smoke not executed).
- **Not-applicable iOS-only areas:** ActivityKit/Live Activity (replaced by the
  ongoing notification), RecordReplay harness, concrete UserDefaults stores
  (replaced by DataStore), SwiftUI shell/layout-metric tests.

## 2. Test intent inventory

| Area | Test intent | iOS source/test | Android function/type | Android test | Status |
|---|---|---|---|---|---|
| Exposure | ND = base·2^stops; snap; overflow | `ExposureCalculatorTests`, `exposure-golden.json` | `ExposureCalculator.calculate` | `ExposureGoldenTest`, `ExposureCoreTest` | Implemented + tested |
| Exposure | shutter/duration formatting (locale-independent) | format/timeDisplay fixtures | `formatShutter`/`formatTimeDisplay`/`formatExtendedClock` | `ExposureGoldenTest` | Implemented + tested |
| Exposure | parse + typed errors; 55/19 ladders; ND 0..30 | `errorCases`, `ExposureScale` | `parseBaseShutter`, `ExposureScale` | `ExposureGoldenTest`, `ExposureCoreTest` | Implemented + tested |
| Catalog/reciprocity | formula eval (no-correction/within/beyond/unsafe) | `ReciprocityFormula.evaluate` | `ReciprocityFormula.evaluate` | `ReciprocityCoreTest` | Implemented + tested |
| Catalog/reciprocity | log-log table interpolation + extrapolation | `TableInterpolationModel` | `TableInterpolationRule.evaluate` | `ReciprocityCoreTest` | Implemented + tested |
| Catalog/reciprocity | 37-film load + manufacturer counts + 3 real shapes | `LaunchPresetFilmCatalog(Shape)Tests`, `catalog-validation-cases.json` | `LaunchPresetFilmCatalogLoader` | `CatalogLoaderTest` | Implemented + tested |
| Catalog/reciprocity | 11 table films reproduce anchors | catalog goldens | loader + table eval | `CatalogLoaderTest` | Implemented + tested |
| Catalog/reciprocity | policy order + result/basis; no fabricated value | `ReciprocityCalculationPolicyEvaluator` | `ReciprocityCalculationPolicyEvaluator.evaluate` | `PolicyAndPresentationTest` | Implemented + tested |
| Catalog/reciprocity | confidence presentation + vocabulary gate | `ReciprocityConfidencePresentation` | `ReciprocityConfidencePresentationMapper.map` | `PolicyAndPresentationTest` | Implemented + tested |
| Catalog/reciprocity | preset alternate-model selection | model-picker/`AlternateReciprocityModels` | `AlternateReciprocityModels`, `CalculatorController.selectModel` | `CustomReferenceAndAlternatesTest`, `CalculatorControllerTest` | Implemented + tested |
| Custom film | no-shortening guard; duration parse | guard/editor tests | `CustomFilmFormulaGuard`, `CustomFilmDurationParser` | `ReciprocityCoreTest`, `CustomFilmTest` | Implemented + tested |
| Custom film | formula + table authoring validation | `CustomFilmEditor(Table)FormStateTests` | `CustomFilmFactory`, `CustomFilmLibrary` | `CustomFilmTest` | Implemented + tested |
| Custom film | fitted preview (quality/error, inspection-only) | `CustomTableFittedFormulaPresenterTests` | `FittedFormulaPreviewPresenter` | `CustomFilmTest`, `DetailsPresenterTest` | Implemented + tested |
| Custom film | create-formula-from-table + referenceTableFilmID | `CustomFilmCreateFormulaTests` | `CreateFormulaFromTable`, `CustomFilmReferenceTableResolver` | `CustomFilmTest`, `CustomReferenceAndAlternatesTest` | Implemented + tested |
| Custom film | library persistence round-trip + fail-safe | `PersistentCustomFilmLibraryTests` | `CustomFilmLibraryCodec`, `DataStoreCustomFilmStore` | `CustomFilmTest` | Implemented + tested (codec); DataStore wiring assemble-only |
| Timer | pause/resume/complete; paused→completed only via resume | `TimerStatePauseResumeTests` | `TimerState` | `TimerStateTest` | Implemented + tested |
| Timer | multi-timer tick, exactly-once completion, reconcile | `TimerManager*` rules | `TimerRuntime`, `TimerWorkspaceController` | `TimerRuntimeTest`, `TimerWorkspaceControllerTest` | Implemented + tested |
| Timer | snapshot/restore (auto-complete, paused-freeze, corrupt→completed, legacy token) | `TimerManagerPersistenceRestoreTests` | `PersistentTimerSnapshot`, `TimerSnapshotCodec` | `TimerRuntimeTest`, `TimerSnapshotCodecTest` | Implemented + tested |
| Timer | ordering active LIFO / completed behind | `BottomSheetWorkspaceOrderingTests` | `TimerWorkspaceOrdering` | `TimerRuntimeTest`, `TimerWorkspaceControllerTest` | Implemented + tested |
| Timer | Start Again (clone completed) | clone tests (PTIMER-36) | `TimerRuntime.startAgain` | `TimerRuntimeTest`, `TimerWorkspaceControllerTest` | Implemented + tested |
| Timer | immutable identity capture | `Calculator…MetadataTests` | `ExposureTimerIdentitySnapshot`; slot label embedded in timer name at start | `CameraSlotSessionTest` (label immutability) | Partially implemented (name-level identity; full snapshot capture not persisted) |
| Camera slots | per-slot state, capture/restore, rename isolation | `CameraSlot*` tests | `CameraSlotSession`, `SlotSessionCodec` | `CameraSlotSessionTest`, `SlotSessionCodecTest` | Implemented + tested |
| Target Shutter | comparison vs adjusted/corrected; nil non-quantified; per-slot | `…TargetShutterTests` | `TargetShutterPresenter`, `CalculatorController` | `TargetShutterTest` | Implemented + tested |
| Persistence | timer/session/custom round-trip + corrupt fail-safe | context/library persistence tests | `*Codec` + `DataStore*Store` | codec tests | Implemented + tested (codecs); DataStore wiring assemble-only |
| Details/presenter | model/source/calc rows, fitted comparison, reference columns, vocab | Details presenter tests | `DetailsPresenter` | `DetailsPresenterTest` | Implemented + tested |
| Notifications | representative selection; completion exactly-once; ongoing | `TimerManagerNotification/CompletionAlert`, `LockScreenTimerCoordinatorTests` | `RepresentativeTimerSelector`, `TimerNotifier`/`AndroidTimerNotifier` | `RepresentativeTimerSelectorTest` | Android replacement: selection + rule tested; NotificationManager wiring assemble-only; foreground service deferred |

## 3. Required areas — status

- **Exposure** — Implemented + tested.
- **Catalog / reciprocity** — Implemented + tested (loader/validation, policy,
  confidence, alternates, resolver).
- **Custom film** — Implemented + tested (factory/library/fitted/create-from-table/
  codec); DataStore wiring assemble-only.
- **Timer** — Implemented + tested; full identity-snapshot persistence partial
  (name-level capture in place).
- **Camera slots** — Implemented + tested.
- **Target Shutter** — Implemented + tested.
- **Persistence** — Implemented + tested at codec level; DataStore impls
  assemble-verified (not unit-tested — Android binding).
- **Details / presenter** — Implemented + tested (graph deferred).
- **Notifications** — Android replacement: selection + rules tested; manager
  wiring assemble-only; foreground service + exact background delivery deferred.

## 4. Function/type mapping (concrete)

| iOS | Android |
|---|---|
| `ExposureCalculator.calculate` | `ExposureCalculator.calculate` |
| `ReciprocityFormula.evaluate` | `ReciprocityFormula.evaluate` |
| `TableInterpolationReciprocityRule.evaluate` | `TableInterpolationRule.evaluate` |
| `ReciprocityCalculationPolicyEvaluator.evaluate` | `ReciprocityCalculationPolicyEvaluator.evaluate` |
| `ReciprocityConfidencePresentationMapper.map` | `ReciprocityConfidencePresentationMapper.map` |
| `ReciprocityFormulaFitter.fit` | `ReciprocityFormulaFitter.fit` |
| `CustomFilmFormulaGuard.passesUsableRangeCheck` | `CustomFilmFormulaGuard.passesUsableRangeCheck` |
| `LaunchPresetFilmCatalogLoader` | `LaunchPresetFilmCatalogLoader` |
| `AlternateReciprocityModels.alternates` | `AlternateReciprocityModels.alternates` |
| `CustomTableFittedFormulaPresenter` | `FittedFormulaPreviewPresenter` |
| `CustomFilmReferenceTableResolver.resolve` | `CustomFilmReferenceTableResolver.resolve` |
| `creatingFormula(fromTable:)` | `CreateFormulaFromTable.create` |
| `TimerState` / `TimerRuntime` | `TimerState` / `TimerRuntime` |
| `PersistentTimerSnapshot.restore` | `PersistentTimerSnapshot.restore` (+ `TimerSnapshotCodec`) |
| `CameraSlotSessionModel` / slot snapshot | `CameraSlotSession` / `SlotCalculatorSnapshot` / `SlotSessionCodec` |
| `TargetShutterPresenter` | `TargetShutterPresenter` |
| `ReciprocityModelMetadataPresenter` / details | `DetailsPresenter` |
| `LockScreenTimerCoordinator` representative selection | `RepresentativeTimerSelector` |
| `TimerCompletionNotificationScheduler` | `TimerNotifier` / `AndroidTimerNotifier` |
| `ExposureCalculatorViewModel` | `ShootingViewModel` + `CalculatorController` + `TimerWorkspaceController` |
| concrete `UserDefaults*Store` | `DataStore*Store` |

## 5. Gap list

```
Missing or partial intent: Fully-guaranteed background timer completion across
        Doze / OEM battery
iOS source/test: TimerManager background/notification behavior, Live Activity
Android status: Improved — in-process completion + ongoing notification posted,
        AND a scheduled completion alarm that uses EXACT when permitted and
        best-effort INEXACT otherwise. SCHEDULE_EXACT_ALARM is declared, the
        exact/inexact choice is the pure ExactAlarmPolicy (JVM-tested), and the
        app surfaces a dismissible in-app request (opens
        ACTION_REQUEST_SCHEDULE_EXACT_ALARM) when exact is unavailable.
        schedule/cancel/relaunch-reconcile + exact-policy + prompt covered by
        JVM tests; both exact/inexact paths confirmed on device. Exact
        availability is also re-checked on resume (refreshExactAlarmAvailability
        via LifecycleEventEffect ON_RESUME): returning from the settings grant
        clears the notice and reschedules running timers through the exact path
        (settings round-trip confirmed on device). No foreground service yet.
Reason: Foreground service needs device-specific testing; faithful
        post-process-death delivery not yet verified. USE_EXACT_ALARM avoided
        (Play eligibility risk); SCHEDULE_EXACT_ALARM needs a Play declaration.
Risk: Inexact delivery may be delayed when exact not granted; OEM battery
        managers / task killers / force-stop can still suppress delivery. Medium.
Suggested follow-up: add a foreground service (type specialUse/shortService) +
        AlarmManager setExactAndAllowWhileIdle keyed by timer id, with
        cancel/reschedule on pause/resume/remove; verify on devices.
```
```
Missing or partial intent: Full immutable timer identity snapshot persistence
iOS source/test: ExposureTimerIdentitySnapshot capture/metadata tests
Android status: Partial — slot label is embedded in the (immutable) timer name
        at start; the structured ExposureTimerIdentitySnapshot type exists but
        is not persisted with each timer.
Reason: Greenfield timer codec persists runtime + name; structured identity
        persistence not yet wired.
Risk: Low (display name carries the identity for MVP).
Suggested follow-up: extend TimerSnapshotCodec to persist the identity snapshot.
```
```
Missing or partial intent: Compose UI smoke tests + visual polish
iOS source/test: SwiftUI shell/layout tests (iOS-only)
Android status: Functional Compose UI present; no connectedAndroidTest run
        (no device); pickers/dialogs/graph are minimal.
Reason: No emulator/device in session; UI polish is deferred by the plan.
Risk: Low (behavior is unit-covered).
Suggested follow-up: add minimal Compose UI smoke tests; human UX pass.
```

## 6. Not applicable / Android replacement

- iOS **ActivityKit / Live Activity** → Android **ongoing notification**
  (implemented; foreground-service upgrade deferred).
- iOS **local completion notification** → `AndroidTimerNotifier` completion
  channel (implemented; AlarmManager background scheduling deferred).
- iOS **concrete `UserDefaults*Store`** → `DataStore*Store` (implemented).
- iOS **RecordReplay** harness → not part of Android MVP verification.
- iOS **SwiftUI shell / layout-metric tests** → UI polish, not an MVP gate.
- iOS **Details graph visual fidelity** → deferred visual polish (functional
  transparency implemented via rows + comparison lines).

## 7. User-test correction — start-action model (post PR #16 review)

**Finding:** PR #16 exposed a single generic `Start timer` action that went
disabled for limited-guidance films, which also blocked the (valid) adjusted
timer. Corrected behavior is separate per-source start actions; limited guidance
disables only the corrected start.

| Behavior | iOS source | Android function/type | Android test | Status |
|---|---|---|---|---|
| Adjusted start (digital + film) enabled whenever adjusted is valid | iOS result-card Adjusted row play | `CalculatorController.adjustedAction` | `CalculatorControllerTest.noFilm…`, `…quantifiedFilm…`, `…limitedGuidance…` | Implemented + tested |
| Corrected start enabled only when quantified positive-finite | iOS Corrected row play | `CalculatorController.correctedAction` | `CalculatorControllerTest.quantifiedFilm…`, `…noCorrectionFilm…` | Implemented + tested |
| Limited guidance keeps adjusted enabled, disables corrected, no fabricated value | iOS limited-guidance handling | `adjustedAction`/`correctedAction` | `CalculatorControllerTest.limitedGuidanceKeepsAdjustedEnabled…` | Implemented + tested |
| Target start enabled only when a valid target is set | iOS Target Shutter card play | `CalculatorController.targetAction` | `CalculatorControllerTest.targetActionAppearsOnlyWhenSet` | Implemented + tested |
| Timer rows show exposure source (title + subtitle + source) | iOS Timers list identity rows | `TimerWorkspaceController` (title/subtitle/`ExposureTimerSource`), `TimerSnapshotCodec` | `TimerWorkspaceControllerTest.sourceIdentity…`, `…startAgainClones…`, `…restoreFromJson…`; `TimerSnapshotCodecTest` | Implemented + tested |
| Source identity immutable after slot rename | identity-at-start tests | title captured at start; `CameraSlotSession` rename isolated | `CameraSlotSessionTest.startedTimerLabel…`, `TimerWorkspaceControllerTest` | Implemented + tested |

A regression to a single generic start action would now fail
`CalculatorControllerTest` (it asserts separate `adjustedAction` /
`correctedAction` / `targetAction`).

**Manual emulator verification (emulator-5554, 2026-06-17):** the result card
renders Adjusted and Corrected rows each with their own Start button (Reciprocity
row = basis badge + Details; Target = Set); starting from Corrected created an
active timer row titled "Camera 3 · Fomapan 100 Classic" with subtitle
"Corrected Exposure · Official FOMA table · 06:35.159" counting down — confirming
per-source start actions and timer source identity. The limited-guidance
adjusted-enabled/corrected-disabled case remains covered by unit tests (not
separately screenshotted); broader Compose UI smoke (`connectedAndroidTest`)
still not automated.
