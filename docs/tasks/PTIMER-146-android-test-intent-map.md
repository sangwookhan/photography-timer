# PTIMER-146 Android MVP — iOS-to-Android Test-Intent Map

Review artifact for a separate verification session. Maps the behavior iOS
tests protect to the current Android implementation and its tests. iOS tests
were used as behavior-audit sources, not mechanically translated.

## 1. Summary

- **Stopping point:** end of Slice 4. Pure-Kotlin `:core` foundation complete
  (exposure, reciprocity calculation primitives, timer engine). App layers and
  the full catalog domain are not yet implemented.
- **Completed slices:** 1 (module), 2 (exposure parity), 3-partial (reciprocity
  calculation primitives), 4 (timer state machine/runtime/snapshot).
- **Total Android tests added:** **51** (CoreModuleSmokeTest 1, ExposureGoldenTest
  5, ExposureCoreTest 8, ReciprocityCoreTest 18, TimerStateTest 6,
  TimerRuntimeTest 13).
- **Final verification:** `./gradlew clean :core:test testDebugUnitTest
  assembleDebug` → BUILD SUCCESSFUL, 0 failures. iOS source diff vs origin/main:
  none.
- **Known gaps:** full catalog JSON domain + 37-film loader/validation, policy
  evaluator, confidence presentation, alternate-model registry, reference-table
  resolver; all app layers (ViewModel, persistence/DataStore, Compose UI, camera
  slots, custom-film UI, Target Shutter, Details, notifications).
- **Not-applicable iOS-only areas:** ActivityKit/Live Activity, RecordReplay
  harness, concrete `UserDefaults*Store`, SwiftUI shell/layout-metric tests.

## 2. Test intent inventory

| Area | Test intent | iOS source/test | iOS function/type | Android function/type | Android test | Status |
|---|---|---|---|---|---|---|
| Exposure | ND output = base·2^stops; snap; overflow | `ExposureCalculatorTests`, `ExposureCalculationAccuracyTests`, `exposure-golden.json` | `ExposureCalculator.calculate` | `ExposureCalculator.calculate` | `ExposureGoldenTest.calculationCasesMatchFixture` | Implemented + tested |
| Exposure | snap gated on full-stop scale + whole-stop ND | snap suite | `ExposureCalculator.snapToFullStop` | `ExposureCalculator.snapToFullStop` (private), gating in `calculate` | `ExposureCoreTest.oneThirdScaleDoesNotSnapEvenWhenNdIsWhole` | Implemented + tested |
| Exposure | shutter/duration formatting, locale-independent | format + timeDisplay fixtures | `formatShutter`, `formatTimeDisplay`, `formatExtendedClock` | same names | `ExposureGoldenTest.{shutterFormatCases,timeDisplayCases}MatchFixture` | Implemented + tested |
| Exposure | base shutter parsing + typed errors | `errorCases` | `parseBaseShutter`, `ExposureCalculatorError` | `parseBaseShutter`, `ExposureCalcError` | `ExposureGoldenTest.errorCasesMatchFixture` | Implemented + tested |
| Exposure | 55-entry ⅓ ladder, 19 full-stop, ND 0..30 | `ExposureScale` | `ExposureScale` | `ExposureScale` | `ExposureCoreTest` (ladder sizes) | Implemented + tested |
| Catalog/reciprocity | formula evaluation (strict no-correction, unsafe-shortening, beyond-range) | `ReciprocityFormula.evaluate` tests | `ReciprocityFormula.evaluate` | `ReciprocityFormula.evaluate` | `ReciprocityCoreTest.formula*` | Implemented + tested |
| Catalog/reciprocity | log-log table interpolation, anchor exactness, extrapolation, 10% tolerance | `TableInterpolationModel` tests | `TableInterpolationReciprocityRule.evaluate` | `TableInterpolationRule.evaluate` | `ReciprocityCoreTest.table*` | Implemented + tested |
| Catalog/reciprocity | OLS power-law fit, rejections, order-independence | `ReciprocityFormulaFitterTests` | `ReciprocityFormulaFitter.fit` | `ReciprocityFormulaFitter.fit` | `ReciprocityCoreTest.fitter*` | Implemented + tested |
| Catalog/reciprocity | 37-film load + 3-shape validation + manufacturer counts | `LaunchPresetFilmCatalog(Shape)Tests`, `catalog-validation-cases.json` | `LaunchPresetFilmCatalogLoader` | (none yet) | (none) | Deferred |
| Catalog/reciprocity | policy evaluation order + result/basis | `ReciprocityCalculationPolicyEvaluator` tests | `ReciprocityCalculationPolicyEvaluator.evaluate` | (none yet) | (none) | Deferred |
| Catalog/reciprocity | confidence presentation + vocabulary gate | `ReciprocityConfidencePresentation` tests | `ReciprocityConfidencePresentationMapper.map` | (none yet) | (none) | Deferred |
| Catalog/reciprocity | preset alternate-model selection | model-picker / `AlternateReciprocityModels` tests | `AlternateReciprocityModels.alternates` | (none yet) | (none) | Deferred |
| Custom film | no-shortening guard (analytic) | `CustomFilmEditorFormState`/guard tests | `CustomFilmFormulaGuard.passesUsableRangeCheck` | `CustomFilmFormulaGuard.passesUsableRangeCheck` | `ReciprocityCoreTest.guard*` | Implemented + tested |
| Custom film | duration parsing | editor tests | `CustomFilmDurationParser.parse` | `CustomFilmDurationParser.parse` | `ReciprocityCoreTest.durationParser*` | Implemented + tested |
| Custom film | fitted preview (quality/error rows, inspection-only) | `CustomTableFittedFormulaPresenterTests` | `CustomTableFittedFormulaPresenter` | (fitter ported; presenter not) | (none) | Partially implemented |
| Custom film | table-form validation + library CRUD + persistence | `CustomFilmEditorTableFormStateTests`, `CustomFilmLibraryTests` | `CustomFilmEditorFormState`, `CustomFilmLibrary` | (none yet) | (none) | Deferred |
| Custom film | create-formula-from-table + referenceTableFilmID + resolver | `CustomFilmCreateFormulaTests` | `creatingFormula(fromTable:)`, `CustomFilmReferenceTableResolver.resolve` | (none yet) | (none) | Deferred |
| Timer | pause/resume/complete transitions; paused→completed only via resume | `TimerStatePauseResumeTests` | `TimerState.{pausing,resume,completed}` | `TimerState.{pausing,resume,completed}` | `TimerStateTest` | Implemented + tested |
| Timer | multi-timer tick, exactly-once completion, reconcile no-replay | `TimerManager*` (rules) | `TimerRuntime` (iOS) / `TimerManager` | `TimerRuntime.{tick,reconcile}` | `TimerRuntimeTest` | Implemented + tested |
| Timer | snapshot/restore (auto-complete, paused freeze, corrupt→completed, legacy token) | `TimerManagerPersistenceRestoreTests` | `PersistentTimerSnapshot.restore` | `PersistentTimerSnapshot.restore` | `TimerRuntimeTest.restore*` | Implemented + tested |
| Timer | ordering active LIFO / completed behind | `BottomSheetWorkspaceOrderingTests` | `TimerWorkspaceOrdering` | `TimerWorkspaceOrdering.order` | `TimerRuntimeTest.ordering*` | Implemented + tested |
| Timer | Start Again (clone completed) | clone tests (PTIMER-36) | `startTimer(cloningCompleted:)` | `TimerRuntime.startAgain` | `TimerRuntimeTest.startAgainClonesCompletedDuration` | Implemented + tested |
| Timer | immutable identity capture | `Calculator…MetadataTests` | `ExposureTimerIdentitySnapshot` | `ExposureTimerIdentitySnapshot` (value type) | (type only; capture flow deferred) | Partially implemented |
| Camera slots | per-slot state, capture/restore, rename isolation | `CameraSlot*` tests | `CameraSlotSessionModel`, `PersistentCameraSlotSessionSnapshot` | (none yet) | (none) | Deferred |
| Target Shutter | comparison vs adjusted/corrected, nil non-quantified, per-slot | `…TargetShutterTests` | `TargetShutterPresenter`, `TargetShutterModel` | (none yet) | (none) | Deferred |
| Persistence | timer/session/custom-film round-trip + corrupt fail-safe | `CalculatorContextPersistenceTests`, `PersistentCustomFilmLibraryTests` | `*Storing` + DataStore-equivalents | timer snapshot type only | (restore tested) | Partially implemented |
| Details/presenter | model/source/calc rows, picker, fitted comparison, vocab | Details presenter tests | `ReciprocityModelMetadataPresenter`, `FilmModeDetailsPresenter` | (none yet) | (none) | Deferred |
| Notifications | completion exactly-once, cancel/reschedule, representative selection | `TimerManagerNotification/CompletionAlert`, `LockScreenTimerCoordinatorTests` | scheduler/coordinator | (none yet) | (none) | Android replacement (deferred) |

## 3. Required areas — status

- **Exposure** — Implemented + tested (fixture parity).
- **Catalog / reciprocity** — calculation primitives Implemented + tested; catalog
  loader/validation, policy evaluator, confidence presentation, alternate models
  Deferred.
- **Custom film** — guard + duration parser + fitter Implemented + tested; editor
  state, library, table authoring, fitted-preview presenter, create-formula flow
  Deferred/Partial.
- **Timer** — Implemented + tested (state machine, runtime, snapshot/restore,
  ordering, Start Again). Identity type present; capture flow Deferred.
- **Camera slots** — Deferred.
- **Target Shutter** — Deferred.
- **Persistence** — timer snapshot/restore Implemented + tested; DataStore stores
  and session/custom-film persistence Deferred.
- **Details / presenter** — Deferred.
- **Notifications** — Deferred (Android replacement design recorded in
  `PTIMER-146-round2-accepted.md` §7 and round2-1 §8).

## 4. Function/type mapping (concrete)

| iOS | Android |
|---|---|
| `ExposureCalculator.calculate(baseShutterSeconds:ndStep:scaleMode:)` | `ExposureCalculator.calculate(baseShutterSeconds, ndStep, scaleMode)` |
| `ExposureCalculator.parseBaseShutter` / `formatTimeDisplay` / `snapToFullStop` | same method names on Kotlin `ExposureCalculator` |
| `ExposureScale` / `NDStep` / `ShutterStep` / `ExposureScaleMode` | `ExposureScale` / `NdStep` / `ShutterStep` / `ExposureScaleMode` |
| `ReciprocityFormula.evaluate(meteredExposureSeconds:)` | `ReciprocityFormula.evaluate(meteredExposureSeconds)` |
| `TableInterpolationReciprocityRule.evaluate` | `TableInterpolationRule.evaluate` |
| `ReciprocityFormulaFitter.fit(anchors:)` | `ReciprocityFormulaFitter.fit(anchors)` |
| `ReciprocityNoCorrectionBoundary.isWithinNoCorrection` | `ReciprocityNoCorrectionBoundary.isWithinNoCorrection` |
| `CustomFilmFormulaGuard.passesUsableRangeCheck` | `CustomFilmFormulaGuard.passesUsableRangeCheck` |
| `CustomFilmDurationParser.parse` | `CustomFilmDurationParser.parse` |
| `TableAnchor` | `TableAnchor` |
| `TimerState` (Running/Paused/Completed) | `TimerState` sealed (Running/Paused/Completed) |
| `PersistentTimerSnapshot.restore(at:)` | `PersistentTimerSnapshot.restore(now)` |
| iOS `TimerRuntime` / `TimerManager` | `TimerRuntime` (pure; Android coordinator deferred) |
| `TimerWorkspaceOrdering` | `TimerWorkspaceOrdering.order` |
| `ExposureTimerIdentitySnapshot` / `ExposureTimerSource` | `ExposureTimerIdentitySnapshot` / `ExposureTimerSource` |
| `CustomTableFittedFormulaPresenter` | (fitter ported; presenter type deferred) |
| `CustomFilmReferenceTableResolver.resolve` | (deferred) |
| `LaunchPresetFilmCatalogLoader` | (deferred) |
| `CameraSlotSessionModel` / `PersistentCameraSlotSessionSnapshot` | (deferred) |
| `TargetShutterPresenter` / `TargetShutterModel` | (deferred) |

## 5. Gap list

```
Missing or partial intent: Catalog domain + 37-film loader + shape validation
iOS source/test: LaunchPresetFilmCatalogLoader, catalog-validation-cases.json
Android status: Deferred (not started)
Reason: Requires modeling the full FilmIdentity/ReciprocityProfile JSON schema
        (provenance, adjustments, userMetadata) as @Serializable Kotlin; large
        and best done as its own green checkpoint.
Risk: No film selection / reciprocity-by-catalog until done. Medium.
Suggested follow-up: Slice 3-remainder — model domain, copy
        LaunchPresetFilmCatalog.json into :core resources, port loader +
        validation, assert 3 real shapes + 37 count + manufacturer counts;
        add anchor-derived goldens for the 11 table films.
```
```
Missing or partial intent: Policy evaluator + confidence presentation + alternates
iOS source/test: ReciprocityCalculationPolicyEvaluator, ReciprocityConfidencePresentation
Android status: Deferred
Reason: Depends on the catalog domain (ReciprocityProfile rules) above.
Risk: No end-to-end reciprocity result/badge until done. Medium.
Suggested follow-up: after catalog domain; reuse the ported formula/table evaluators.
```
```
Missing or partial intent: App layers (VM, DataStore, Compose UI, slots, custom-film UI,
        Target Shutter, Details, notifications)
iOS source/test: ExposureCalculatorViewModel, *Storing, SwiftUI views, etc.
Android status: Deferred (Slices 5-10 not started)
Reason: Largest portion of the MVP; out of this session's safe budget.
Risk: No runnable shooting app yet. High for "working MVP" goal.
Suggested follow-up: proceed Slice 5 onward per round2-accepted §10 after the
        catalog/policy core lands.
```
```
Missing or partial intent: Fitted-preview presenter + create-formula-from-table flow
iOS source/test: CustomTableFittedFormulaPresenter, CustomFilmCreateFormulaTests
Android status: Partial — OLS fitter ported + tested; presenter/flow not.
Reason: Presenter needs comparison-row/quality types + editor state (app layer).
Risk: Low (inspection-only feature).
Suggested follow-up: Slice 8b/8c per round2-accepted.
```

## 6. Not applicable / Android replacement

- iOS **ActivityKit / Live Activity** → Android **ongoing foreground-service
  notification** (planned, deferred — round2-accepted §7).
- iOS **local completion notification** → Android `NotificationManager` +
  `AlarmManager` background delivery (planned, deferred).
- iOS **concrete `UserDefaults*Store`** → Android **typed DataStore** stores
  (planned, deferred).
- iOS **RecordReplay** harness → not part of Android MVP verification.
- iOS **SwiftUI shell / layout-metric tests** → UI polish, not an MVP functional
  gate.
- iOS **Details graph visual fidelity** → deferred visual polish.
