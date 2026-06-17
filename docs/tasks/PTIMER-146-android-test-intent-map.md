# PTIMER-146 Android MVP — iOS-to-Android Test-Intent Map

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
- **Known gaps:** foreground service for guaranteed background countdown and
  exact-alarm background delivery (deferred — platform work needing device
  testing); custom-table/editor/graph/picker UI polish; no
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
Missing or partial intent: Guaranteed background timer completion + ongoing
        notification across Doze / OEM battery
iOS source/test: TimerManager background/notification behavior, Live Activity
Android status: Partial — foreground completion + ongoing notification posted;
        no foreground service, no AlarmManager background scheduling.
Reason: Foreground service + exact alarms need device-specific testing and
        permissions; out of a no-device session's safe scope.
Risk: Background reliability under aggressive battery managers. Medium.
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
