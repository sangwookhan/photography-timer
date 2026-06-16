# PTIMER-146 — Android MVP Detailed Implementation Plan (Round 2)

> **Status:** Planning only. Round 2 converts the accepted Round 1-1 baseline
> (`docs/tasks/PTIMER-146-round1-1.md`) into a file-, type-, and test-level
> Android design. **Not** implementation approval. No production source
> changed, no commits, no Jira, no tickets. Implementation begins only after
> Round 3 readiness review is accepted.

Owner decisions applied verbatim: PTIMER-165 table/fitted **excluded**; catalog
JSON + `catalog-validation-cases.json` **authoritative**; pure-Kotlin `:core`
module, **no** version catalog, minimal deps; camera-slot **rename included**;
Scope-B = basic completion notification only if low-risk, background reliability
follow-up, Target Shutter deferred, custom-formula authoring deferred. MVP must
be a **working app**, camera slots **not** reduced to one slot.

---

## 1. Catalog / table-evaluator resolution (inspected this round)

Inspected `ios/PTimerKit/Sources/PTimerCore/Catalog/LaunchPresetFilmCatalog.json`
and `shared/test-fixtures/catalog-validation-cases.json` directly.

### 1.1 Verified catalog basis (authoritative)

- **37 films** (`canonicalStockName` ×37, `kind:"preset"` ×37). Fixture
  `expectedFilmCount = 37` — **matches**. The "34 films" prose is stale.
- **Manufacturer counts (catalog == fixture):** ILFORD / HARMAN **12**, Kodak
  **9**, Fujifilm **4**, FOMA BOHEMIA **3**, Rollei **7**, ADOX **2** (= 37).
- **Profile-shape distribution (by calculation rule kind):**
  - **Formula films: 20** (rule kind `formula`).
  - **Table-interpolation films: 11** (rule kind `tableInterpolation`).
  - **Threshold + limited-guidance films: 6** (rule kinds `threshold` +
    `limitedGuidance`).
  - `tableLookup` / legacy `table` rule kind: **0** (rule-10 satisfied — the
    forbidden token is literally `"table"`, which is absent; the present token
    is `"tableInterpolation"`).

### 1.2 Which films need which evaluator at calculation time

- **Formula evaluation (20 films):** the ILFORD/HARMAN line, Fujifilm,
  Kodak B/W formula stocks (e.g. the formula-shaped Kodak entries), etc.
- **Table interpolation (11 films, named):** Kodak **Tri-X 400**,
  **T-MAX 100**, **T-MAX 400**; FOMA **Fomapan 100 Classic**, **Fomapan 200
  Creative**, **Fomapan 400 Action**; Rollei **RPX 25**, **RPX 100**,
  **RPX 400**, **ORTHO 25 plus**; ADOX **CHS 100 II**.
- **Threshold + limited guidance (6 films):** Ektar 100, Portra 160,
  Portra 400, Gold 200, Ultra Max 400, Ektachrome E100.

### 1.3 Answers to the owner's questions

- **Which preset films require formula evaluation?** The 20 formula films above.
- **Which preset films require table interpolation at calculation time?** The
  **11** table films above.
- **Is `TableInterpolationModel` required in PTIMER-146 for catalog
  calculations?** **Yes.** 11 official preset films compute corrected exposure
  via log-log interpolation of published anchors. Porting the log-log evaluator
  is therefore Must scope for catalog calculation. This is **catalog**
  behavior, not PTIMER-165.
- **Which PTIMER-165 table/fitted surfaces remain excluded?** (1) custom table
  *anchor input UI*; (2) *fitted-formula preview/generation* (the
  `ReciprocityFormulaFitter` OLS fit + `CustomTableFittedFormulaPresenter`);
  (3) *log-log table model selection for custom profiles*. None of these is
  needed to evaluate the 11 built-in catalog tables.
- **What exact Android tests prove this?** `CatalogCalculationGoldenTest`
  computes corrected exposure for each of the 11 table films at sampled metered
  times and asserts against values derived from the catalog's own anchors via
  the ported log-log math; `ReciprocityTableInterpolationTest` unit-tests the
  evaluator (through-anchor exactness, beyond-last-anchor extrapolation,
  10%-tolerance no-correction, `safeCorrected = max(corrected, metered)`);
  `CatalogValidationFixtureTest` runs the `catalog-validation-cases.json` rules
  that hold (see §1.4 drift) plus the formula-film per-film params and
  threshold ranges.

### 1.4 Fixture drift (flag — owner awareness, not a blocker)

The catalog and fixture **agree** on count and manufacturer counts, but the
fixture's **profile-shape expectations are stale relative to the 11 table
films**:

- **rule-11** lists only two allowed shapes (`officialQuantifiedFormula`,
  `officialLimitedGuidance`) — it does **not** include a table-interpolation
  shape, yet 11 films use `tableInterpolation`. The iOS loader's
  `validateProfileShape` **does** accept table-interpolation-only as a valid
  launch shape, so the live code is more permissive than the fixture text.
- **perFilmExpectations** has 34 entries with rule kinds only
  `{formula, threshold, limitedGuidance}` — **zero** `tableInterpolation`
  entries. The 11 table films are not represented there.

**Decision for Android (within owner directive "catalog + fixture
authoritative"):** the **catalog JSON is the loadable truth**; Android
validates structure against it directly and runs the fixture rules that are
self-consistent (count, manufacturer counts, ids/order, formula per-film
params, threshold ranges, rejection cases, vocabulary rule-12). Android does
**not** port rule-11's two-shape restriction as written (it contradicts the
shipped catalog) and instead asserts the catalog's three real shapes
(formula / tableInterpolation / threshold+limitedGuidance). The drift is logged
as **owner question Q-A** (§10) — the iOS fixture likely needs a follow-up
top-up, but that is an iOS-side concern, out of 146 scope.

---

## 2. Module & dependency setup (concrete)

```
android/
  settings.gradle.kts          edit: include(":app", ":core")
  build.gradle.kts             edit: add kotlin.jvm + serialization plugin aliases (inline versions)
  core/
    build.gradle.kts           new: org.jetbrains.kotlin.jvm + kotlin.plugin.serialization
    src/main/resources/com/sangwook/ptimer/core/catalog/LaunchPresetFilmCatalog.json   (copied verbatim from iOS resource)
    src/main/kotlin/com/sangwook/ptimer/core/...
    src/test/kotlin/com/sangwook/ptimer/core/...
  app/
    build.gradle.kts           edit: add :core, coroutines-android, lifecycle-viewmodel-compose,
                                      lifecycle-runtime-compose, datastore (typed), serialization plugin;
                                      test: kotlinx-coroutines-test
```

**Dependencies (inline versions, no catalog):**

| Where | Artifact | Version basis | Why |
|---|---|---|---|
| root/plugins | `org.jetbrains.kotlin.plugin.serialization` | = Kotlin 2.0.21 | JSON (de)serialization parity with Swift `Codable`. |
| `:core` | `org.jetbrains.kotlinx:kotlinx-serialization-json` | 1.7.x | Catalog + persistence schema (de)serialization. |
| `:core` test | `junit:4.13.2` | present | Fixture + state-machine tests. |
| `:app` | `project(":core")` | — | Domain. |
| `:app` | `org.jetbrains.kotlinx:kotlinx-coroutines-android` | 1.8.x | Tick loop + `StateFlow`. |
| `:app` | `androidx.lifecycle:lifecycle-viewmodel-compose`, `lifecycle-runtime-compose` | 2.8.7 (aligned) | ViewModel + `collectAsStateWithLifecycle`. |
| `:app` | `androidx.datastore:datastore` (typed) | 1.1.x | Persistence behind `:core` `*Store` interfaces. |
| `:app` test | `org.jetbrains.kotlinx:kotlinx-coroutines-test` | 1.8.x | Virtual-time ViewModel/coordinator tests. |
| `:app` androidTest | Compose `ui-test-junit4` | present (BOM) | Scope-B UI smoke. |

`:core` build verifies the boundary by construction (no `com.android.*` /
`androidx.*` on its classpath).

---

## 3. Kotlin type mapping

| Swift / iOS type (PTimerCore/Kit) | Kotlin / Android type | Package | Notes | Exact parity required? |
|---|---|---|---|---|
| `ExposureCalculator` (struct) | `object ExposureCalculator` (or stateless class) | `core.exposure` | `calculate(baseSeconds, ndStep, scaleMode)`, `parseBaseShutter`, `formatShutter`, `formatTimeDisplay`, `formatExtendedClock`, `reconstructedStop`; `STABILITY_EPSILON = 1e-6`. | **Yes** (protected) |
| `ExposureScale`, `ExposureScaleMode` | `enum class ExposureScaleMode { FULL_STOP, ONE_THIRD_STOP }` + `object ExposureScale` | `core.exposure` | `fullStopShutterSpeeds` (19), one-third ladder (55 via `2^(1/3)`,`2^(2/3)`), ND `0..30`, camera labels. | **Yes** |
| `NDStep` (struct), `ShutterStep` | `data class NdStep(val stops: Double)` (+ `isWholeStop`, `thirdStopCount`, `fromThirdStopCount`); `data class ShutterStep(val seconds: Double)` | `core.exposure` | Value types; `MAX_WHOLE_ND_STOPS = 30`. | **Yes** |
| `ExposureCalculatorError` (enum) | `sealed class ExposureCalcError` / `enum` | `core.exposure` | `EmptyBaseShutter, InvalidBaseShutter, NonPositiveBaseShutter, NonPositiveND, Overflow`. Returned via `Result`/throws. | **Yes** |
| `ReciprocityFormula` (struct) | `data class ReciprocityFormula(...)` + `fun evaluate(metered): EvalResult` | `core.reciprocity` | `Tc=a(Tm/Tref)^p+b`; strict no-correction; unsafe-shortening clamp; `FormulaFamily.MODIFIED_SCHWARZSCHILD`. | **Yes** (protected) |
| `TableInterpolationReciprocityRule` + `TableInterpolationModel` | `data class TableInterpolationRule(...)` + `fun evaluate(metered): EvalResult` | `core.reciprocity` | log10–log10 interpolation through anchors; extrapolate last segment; 10% no-correction tolerance; `safeCorrected = max(corrected, metered)`. **Required for 11 catalog films.** | **Yes** |
| `ReciprocityCalculationPolicyEvaluator` | `object ReciprocityPolicyEvaluator` | `core.reciprocity` | `evaluate(profile, meteredSeconds): ReciprocityResult`; order formula → table → threshold → limitedGuidance → unsupported. | **Yes** (protected) |
| `ReciprocityResult` (enum + payloads) | `sealed interface ReciprocityResult { Quantified, LimitedGuidance, Unsupported }` + `ReciprocityResultMetadata` | `core.reciprocity` | 5-case `CalculationBasis` enum incl. `TABLE_LOG_LOG_DERIVED` (ignore stale doc). | **Yes** |
| `ReciprocityConfidencePresentation(Mapper)` | `object ReciprocityConfidencePresentationMapper` + `data class ReciprocityConfidencePresentation` | `core.reciprocity` | basis→category/level/badge/label; forbidden vocabulary gate. | **Yes** (protected) |
| `FilmIdentity`, `ReciprocityProfile`, rules, provenance, adjustments | `@Serializable data class FilmIdentity / ReciprocityProfile / ...`; `sealed interface ReciprocityRule { Threshold, Formula, LimitedGuidance, TableInterpolation }` | `core.reciprocity` | kotlinx.serialization with `@SerialName("kind")` discriminator. `sourceEvidence` display-only (calc never reads). | **Yes** (schema) |
| `LaunchPresetFilmCatalogLoader` (+ 12 rules) | `object LaunchPresetFilmCatalogLoader` + `sealed class CatalogLoadError` | `core.catalog` | loads classpath JSON resource; validates; explicit fail-to-load. | **Yes** |
| `TimerState` (enum), `RunningTimer/PausedTimer/CompletedTimer` | `sealed interface TimerState { Running, Paused, Completed }` | `core.timer` | `TIMER_STABILITY_EPSILON = 1e-6`; `remainingTime(at)`, `pausing(at)`, `resume(at)`, `completed(at)`. | **Yes** (protected) |
| `TimerRuntime` (`ObservableObject`) | `class TimerRuntime` (pure; exposes `StateFlow<List<TimerState>>`) | `core.timer` | start/pause/resume/remove/tick(now)/reconcile(now)/restore; **no Android, no clock ownership**. | **Yes** |
| `TimerPersistenceStoring`, `PersistentTimerSnapshot` | `interface TimerStore` + `@Serializable data class PersistentTimerSnapshot` | `core.timer` / `core.persistence` | restore semantics; legacy `"stopped"`→paused tolerated. | **Yes** (schema) |
| `ExposureTimerIdentitySnapshot`, `ExposureTimerSource` | `@Serializable data class ExposureTimerIdentitySnapshot` + `enum ExposureTimerSource` | `core.timer` | digital / film-adjusted / film-corrected / target / manual; captured once at start. | **Yes** |
| `PersistentCameraSlotSessionSnapshot` + per-slot snapshot | `@Serializable data class PersistentCameraSlotSessionSnapshot` + `PersistentCameraSlotCalculatorSnapshot` | `core.persistence` | `schemaVersion=1`, `activeSlotIdRaw`, `slots[]`. | **Yes** (schema) |
| Calculator state/context (`CalculatorModel`, `PersistentCalculatorContext`) | `class CalculatorState` (app) + folded into per-slot snapshot | `app.state` / `core.persistence` | greenfield: calculator context lives **in** the slot session snapshot (no separate legacy single-context store). | Behavior parity |
| `FilmSelectionModel` / state | `class FilmSelectionState` | `app.state` | active film+profile; select/clear; resolve against catalog. | Behavior parity |
| `TimerWorkspaceModel` / ordering | `class TimerWorkspaceState` + `object TimerWorkspaceOrdering` | `app.state` | active LIFO; completed completion-desc. | Behavior parity |
| `CameraSlotSessionModel` | `class CameraSlotSessionState` | `app.state` | active slot, per-slot snapshots, custom names; capture/restore. | Behavior parity |
| `ExposureCalculatorViewModel` (facade) | `class ShootingViewModel : ViewModel()` | `app.vm` | exposes `StateFlow<ShootingUiState>`; `onEvent(ShootingIntent)`. | Behavior parity |
| `@Published` state + intent methods | `data class ShootingUiState` + `sealed interface ShootingIntent` | `app.vm` | one-way events. | Behavior parity |
| `*Presenter` (authority/result/details text) | plain `object`/`class` presenters | `app.presenter` | pure functions, JVM-testable. | Behavior parity |
| `TimerManager` (RunLoop coordinator) | `class AndroidTimerCoordinator : TimerManaging` | `app.timer` | coroutine tick (~100ms) drives `runtime.tick(now)`; owns wall clock. | Behavior parity |

---

## 4. File-level implementation design (by slice)

Package root `com.sangwook.ptimer`. `:core` files have **no** Android imports.

### Slice 0 — Gradle/module setup
- **Edit:** `android/settings.gradle.kts` (`include(":app",":core")`),
  `android/build.gradle.kts` (plugin aliases), `android/app/build.gradle.kts`
  (deps §2). **New:** `android/core/build.gradle.kts`.
- **Classes:** none. **Test:** `core/src/test/.../SmokeTest.kt` (`1+1`).
- **Dependencies:** none beyond §2.

### Slice 1 — Exposure core
- **Package:** `core.exposure`.
- **New:** `ExposureCalculator.kt`, `ExposureScale.kt` (+`ExposureScaleMode`),
  `NdStep.kt` (+`ShutterStep`), `CalculatorDefaults.kt`,
  `ExposureCalcError.kt`, `ShutterFormatter.kt`, `DurationFormatter.kt`.
- **Key fns:** `calculate(...)`, `parseBaseShutter(String): Result<Double>`,
  `formatShutter(Double)`, `formatTimeDisplay(Double): TimeDisplay`,
  `formatExtendedClock(Double)`, `snapToFullStop(...)` (gated on full-stop scale
  **and** whole-stop ND), `oneThirdStopLadder()`.
- **Responsibilities:** ND math, ladders, snap, locale-independent formatting.
- **Deps:** none.
- **Test:** `core/.../exposure/ExposureGoldenTest.kt` (fixture),
  `ExposureSnapTest.kt`, `ExposureLadderTest.kt`, `DurationFormatTest.kt`.

### Slice 2 — Reciprocity core + catalog
- **Packages:** `core.reciprocity`, `core.catalog`.
- **New (reciprocity):** `ReciprocityDomain.kt` (FilmIdentity, ReciprocityProfile,
  `sealed ReciprocityRule`, provenance, adjustments, `@Serializable`),
  `ReciprocityFormula.kt`, `TableInterpolationRule.kt` (+ evaluator),
  `ReciprocityPolicyEvaluator.kt`, `ReciprocityResult.kt` (+ metadata enums,
  `CalculationBasis`), `ReciprocityConfidencePresentation.kt`,
  `FormulaEquationFormatter.kt` (for Details text).
- **New (catalog):** `LaunchPresetFilmCatalogLoader.kt` (+`CatalogLoadError`),
  resource `LaunchPresetFilmCatalog.json`.
- **Key fns:** `ReciprocityPolicyEvaluator.evaluate(profile, metered)`,
  `ReciprocityFormula.evaluate`, `TableInterpolationRule.evaluate`,
  `loadBundledCatalog(): Result<List<FilmIdentity>>`, `validate(...)`.
- **Deps:** kotlinx-serialization-json.
- **Test:** `ReciprocityPolicyOrderTest.kt`, `ReciprocityFormulaTest.kt`,
  `ReciprocityTableInterpolationTest.kt`, `ConfidencePresentationTest.kt`,
  `CatalogLoaderTest.kt`, `CatalogValidationFixtureTest.kt` (fixture rules that
  hold + per-film formula params + threshold ranges + rejection cases),
  `CatalogCalculationGoldenTest.kt` (11 table films + sample formula films).

### Slice 3 — Timer state/runtime/snapshot core
- **Packages:** `core.timer`, `core.persistence`.
- **New:** `TimerState.kt` (`sealed interface` + payloads + transitions),
  `TimerRuntime.kt`, `ExposureTimerIdentity.kt` (snapshot + `ExposureTimerSource`),
  `PersistentTimerSnapshot.kt` (+ `PersistentTimerCollectionSnapshot`),
  `TimerStore.kt` (interface) + `NoOpTimerStore.kt`,
  `TimerWorkspaceOrdering.kt`.
- **Key fns:** `TimerState.remainingTime(at)`, `.pausing(at)`, `.resume(at)`,
  `.completed(at)`; `TimerRuntime.start/pause/resume/remove/removeCompleted/
  tick(now)/reconcile(now)/restore(snapshot, now)`.
- **Deps (core.persistence):** kotlinx-serialization.
- **Test:** `TimerStateTransitionTest.kt`, `TimerRuntimeTickTest.kt`,
  `TimerRestoreTest.kt`, `TimerOrderingTest.kt`.

### Slice 4 — Coordinator + ViewModel + persistence + runnable timers UI
- **Packages:** `app.timer`, `app.vm`, `app.persistence`, `app.ui.timers`.
- **New:** `AndroidTimerCoordinator.kt` (`: TimerManaging`, coroutine tick,
  injectable `Clock`/`dateProvider`), `TimerManaging.kt` (interface, in `core`
  or `app`; place in `core.timer` to mirror iOS),
  `ShootingViewModel.kt`, `ShootingUiState.kt`, `ShootingIntent.kt`,
  `DataStoreTimerStore.kt` (`: TimerStore`), `DataStoreFactory.kt`,
  `TimerListScreen.kt` (minimal), `TimerCard.kt`.
- **Key fns:** coordinator `start/pause/resume/remove`, `tickLoop()`;
  VM `onEvent`, `observeTimers()`.
- **Deps:** coroutines, datastore, lifecycle-viewmodel.
- **Test:** `app/.../vm/TimerWorkflowViewModelTest.kt` (virtual time),
  `CoordinatorTickTest.kt`, `DataStoreTimerRoundTripTest.kt`.

### Slice 5 — Calculator + film selection wired to UI
- **Packages:** `app.state`, `app.presenter`, `app.ui.shooting`.
- **New:** `CalculatorState.kt`, `FilmSelectionState.kt`,
  `AuthorityLabelPresenter.kt`, `ResultRowPresenter.kt`,
  `StartEnablementPolicy.kt`, `ShootingScreen.kt`, `BaseShutterPicker.kt`,
  `NdPicker.kt`, `FilmRow.kt`, `FilmPickerSheet.kt`, `ResultRows.kt`,
  `StartTimerButton.kt`, `DataStoreSessionStore.kt` (calculator context folded
  into session — see Slice 6).
- **Edit:** `ShootingViewModel.kt`/`ShootingUiState`/`ShootingIntent` (add
  calculator + film events/state), `MainActivity.kt` (host `ShootingScreen`).
- **Key fns:** `ResultRowPresenter.rows(result, filmSelected)`,
  `StartEnablementPolicy.canStartCorrected(result)`.
- **Test:** `CalculatorFilmViewModelTest.kt`, `StartEnablementTest.kt`,
  `AuthorityLabelPresenterTest.kt`, `ResultRowPresenterTest.kt`.

### Slice 6 — Camera slots + rename (Must; MVP feature-complete here)
- **Packages:** `app.state`, `core.persistence`, `app.ui.slots`.
- **New:** `CameraSlotSessionState.kt`, `CameraSlotId.kt` (`camera1..camera4`),
  `PersistentCameraSlotSessionSnapshot.kt` (+ per-slot snapshot, in
  `core.persistence`), `CameraSlotSessionStore.kt` (interface) +
  `DataStoreSessionStore.kt` (impl), `SlotPager.kt`, `SlotRenameDialog.kt`,
  `TimerStartComposer.kt` (builds `ExposureTimerIdentitySnapshot`).
- **Edit:** `ShootingViewModel` (slot switch/rename intents + capture/restore),
  `ShootingUiState`/`ShootingIntent`, `ShootingScreen` (host pager + title).
- **Key fns:** `CameraSlotSessionState.switchActiveSlot(to, capturing)`,
  `setCustomName/resetCustomName`, `restore(snapshot)`;
  `TimerStartComposer.compose(activeSlot, film, result): identity`.
- **Test:** `CameraSlotSessionStateTest.kt`, `SlotRenameTest.kt`,
  `SlotSessionRoundTripTest.kt`, `TimerIdentityCaptureTest.kt`.

### Slice 7 — Basic Reciprocity Details (Must) + Scope-B notification (cond.)
- **Packages:** `app.presenter`, `app.ui.details`, `app.notifications` (cond.).
- **New:** `ReciprocityDetailsPresenter.kt`, `DetailsSheet.kt` (model/basis/
  provenance/source-reference summary; **no graph**); *(conditional, low-risk)*
  `TimerCompletionNotifier.kt` (NotificationManager; schedule-on-start /
  cancel-on-pause / exactly-once), `NotificationPermission.kt`.
- **Edit:** `AndroidTimerCoordinator` (emit completion event to notifier).
- **Test:** `ReciprocityDetailsPresenterTest.kt`; *(cond.)*
  `CompletionNotificationRuleTest.kt`.

---

## 5. Persistence design

### 5.1 DataStore choice
**Typed `DataStore<T>`** (one per concern) backed by **kotlinx.serialization
JSON** via a small `Serializer<T>` — not Preferences DataStore (nested snapshot
objects are awkward as flat key/values). Greenfield: **no iOS legacy
migration**; the slot-session snapshot is the source of truth and folds in the
calculator context (no separate legacy single-context store).

### 5.2 Stores, files, schema classes

| Store interface (`:core`) | Impl (`:app`) | DataStore file | Root `@Serializable` schema | schemaVersion |
|---|---|---|---|---|
| `TimerStore` | `DataStoreTimerStore` | `timers.json` | `PersistentTimerCollectionSnapshot { schemaVersion:Int=1, nextTimerOrder:Int, timers: List<PersistentTimerSnapshot> }` | 1 |
| `CameraSlotSessionStore` | `DataStoreSessionStore` | `camera_session.json` | `PersistentCameraSlotSessionSnapshot { schemaVersion:Int=1, activeSlotIdRaw:String?, slots: List<PersistentCameraSlotCalculatorSnapshot> }` | 1 |

`PersistentTimerSnapshot` fields (runtime **+** display/identity folded — a
greenfield simplification vs the iOS two-snapshot split, preserving the same
data): `id:String(UUID)`, `status:String` (`running`/`paused`/`completed`;
decoder also accepts legacy `stopped`→paused), `duration:Double`,
`startEpochMs:Long`, `expectedCompletionEpochMs:Long?`,
`pausedRemainingSeconds:Double?`, `pausedAtEpochMs:Long?`,
`completedAtEpochMs:Long?`, `order:Int`, `name:String`, `basisSummary:String`,
`identity: ExposureTimerIdentitySnapshot?` (slot id+label, film descriptor,
exposure source; `null` for manual).

`PersistentCameraSlotCalculatorSnapshot` fields: `slotIdRaw:String`,
`selectedPresetFilmId:String?`, `selectedProfileId:String?`,
`baseShutterSeconds:Double?`, `ndStop:Int?`, `ndStopThirds:Int?`,
`exposureScaleMode:String?`, `customDisplayName:String?`. (`targetShutterSeconds`
omitted — Target Shutter deferred.)

### 5.3 Restore behavior
- **Timers:** `running` → if `now ≥ expectedCompletion − ε` restore as
  `completed` (completion time = recorded expected end), else running; `paused`
  → frozen remaining (missing/inconsistent freeze metadata → `completed`, never
  fabricate a timestamp); `completed` → completed. No alerts on restore.
  `nextTimerOrder` restored; ordering recomputed by `TimerWorkspaceOrdering`.
- **Calculator context:** restored **per slot** from the session snapshot;
  sanitized (base shutter snapped to ladder, ND clamped `0..30`, unknown scale
  token → `oneThirdStop`).
- **Camera slots:** all slots restored with independent state; `activeSlotIdRaw`
  unresolvable → first slot; slots sorted by id for determinism.
- **Selected film/profile:** film id unresolvable against catalog → No-film
  (clean snapshot written back); profile id unresolvable → primary profile.
- **Renamed slots:** `customDisplayName` restored; empty/whitespace → canonical
  `Camera N`.

### 5.4 Corrupt / unknown / future schema
- **Corrupt JSON / deserialization failure:** `Serializer` returns the default
  (empty collection / default session) — fail-safe, never crash; next save
  rewrites clean.
- **Unknown/future `schemaVersion`:** load returns default (greenfield: discard
  and start fresh); next save writes `schemaVersion = 1`.
- **Missing optional fields:** decode to `null`/defaults (forward/backward
  tolerant; adding an optional field never bumps the version).

### 5.5 Persistence test plan
`DataStoreTimerRoundTripTest` (running/paused/completed round-trip; restore
auto-complete; corrupt paused→completed; legacy `stopped` decode; empty
collection clears file), `SlotSessionRoundTripTest` (4-slot round-trip across
two reloads; unresolvable film/profile fallback; rename round-trip; future
schemaVersion ignored; corrupt→default), `CorruptPayloadFailSafeTest`.

---

## 6. ViewModel and UI event design

### 6.1 `ShootingUiState` (immutable)
```
data class ShootingUiState(
  val activeSlot: SlotUi,                 // id, title (custom or "Camera N"), index
  val slots: List<SlotChipUi>,            // for the pager/selector
  val film: FilmRowUi,                    // none -> "Choose Film"; selected -> name/brand/authority/Clear
  val baseShutter: PickerUi,              // 55-entry ladder + selected index
  val nd: PickerUi,                       // 0..30 + selected index
  val result: ResultUi,                   // digital: adjusted; film: adjusted + corrected + badge/tone
  val canStartTimer: Boolean,             // derived from result + enablement policy
  val startDisabledHint: String?,         // shown when disabled (not hidden)
  val timers: TimerListUi,                // active (LIFO) + completed (desc) groups
  val details: ReciprocityDetailsUi?,     // for the Details sheet
)
```
Sub-UI types are plain data classes produced by presenters. The VM holds the
mutable feature-state objects (`CalculatorState`, `FilmSelectionState`,
`CameraSlotSessionState`, `TimerWorkspaceState`) and recomputes `ShootingUiState`
on every change; UI never sees mutable domain state.

### 6.2 `ShootingIntent` (one-way)
```
sealed interface ShootingIntent {
  data class SetBaseShutterIndex(val i: Int)
  data class SetNdStop(val stops: Int)
  data object OpenFilmPicker; data class SelectFilm(val filmId: String?)
  data class SelectProfile(val profileId: String); data object ClearFilm
  data object StartTimer                        // binds to corrected (film) or adjusted (digital)
  data class PauseTimer(val id: String); data class ResumeTimer(val id: String)
  data class RemoveTimer(val id: String); data object ClearCompleted
  data class SelectSlot(val id: String); data object NextSlot; data object PrevSlot
  data class RenameSlot(val id: String, val name: String); data class ResetSlotName(val id: String)
  data object OpenDetails; data object CloseDetails
}
```

### 6.3 Ownership & event flow
- **State ownership:** each feature state object owns exactly one concern
  (mirrors iOS single-owner table). Cross-cutting wiring lives only in the VM
  (the `WorkspaceCoordinator` analogue); state objects don't reference each
  other.
- **One-way:** UI emits `onEvent(intent)`; VM mutates the owning state object,
  recomputes `ShootingUiState`, emits via `MutableStateFlow`. No callbacks
  mutate domain directly.
- **Ticks → state:** `AndroidTimerCoordinator` runs a coroutine loop (~100 ms
  while any timer is running) calling `runtime.tick(now)`; the runtime's
  `StateFlow<List<TimerState>>` is collected by the VM, which maps to
  `TimerListUi`. Composables never tick.
- **Slot switching:** `SelectSlot/Next/Prev` → VM calls
  `CameraSlotSessionState.switchActiveSlot(to, capturing = currentCalcAndFilm)`
  which snapshots the outgoing slot and restores the incoming, then persists.
- **Immutable timer identity:** `StartTimer` → VM asks `TimerStartComposer` to
  build an `ExposureTimerIdentitySnapshot` from the **current** active slot
  (id + label as-is), film descriptor, and exposure source; passes it to
  `runtime.start(...)`. Captured once; later slot/film/rename changes never
  mutate it.
- **Reciprocity → Start enablement:** `StartEnablementPolicy` derives
  `canStartTimer` from the `ReciprocityResult` variant — `Quantified`
  (positive finite) enables; `LimitedGuidance`/`Unsupported`-without-numeric
  disables the corrected timer with a hint (adjusted-shutter timer may still be
  allowed in the digital/film-adjusted path, matching iOS).

---

## 7. Compose UI design (MVP-level, no polish)

```
MainActivity
└─ ShootingScreen (Scaffold)
   ├─ SlotPager / SlotSelector  (HorizontalPager or row of chips; active title = top bar)
   │    └─ (tap title) → SlotRenameDialog
   ├─ FilmRow                   (empty: "Choose Film"; selected: name · brand · authority + Change/Clear)
   │    └─ FilmPickerSheet (ModalBottomSheet): manufacturer-grouped list,
   │         "No film" sentinel row, ISO chip, reserved checkmark slot;
   │         tap applies+dismisses
   ├─ VariableSection
   │    ├─ BaseShutterPicker     (wheel/list over 55-entry ladder; no free text)
   │    └─ NdPicker              (0..30)
   ├─ ResultRows                 (digital: Adjusted; film: Adjusted + Corrected + status badge)
   ├─ StartTimerButton          (enabled per StartEnablementPolicy; disabled shows hint)
   ├─ TimerList
   │    ├─ Active section        (LIFO; TimerCard: name, remaining, pause/resume/remove)
   │    └─ Completed section     ("Done"; completion-desc; Clear Completed)
   └─ DetailsSheet (ModalBottomSheet, on demand): model · basis · provenance · source-reference summary
```
Rough-until-tuning: pager animation/indicator, tints, spacing/density tiers,
badge styling, rename-sheet layout, **no** Details graph, **no** bottom-sheet
drag choreography. Behavior + persistence must be correct; pixels can wait.

---

## 8. Prioritized test matrix (by slice)

| Slice | Android test file | Source iOS behavior / fixture | Inputs | Expected output / invariant | Fixture-driven? | Required before slice done? |
|---|---|---|---|---|---|---|
| 1 | `ExposureGoldenTest` | `exposure-golden.json` cases/errors/format/timeDisplay | fixture rows | exact (tol 1e-4); locale-independent strings | **Yes** | **Yes** |
| 1 | `ExposureSnapTest` | snap suite + `_meta` | `1.0+3/4/5`, `1/30+11` | 8/15/30; 64 (not 60); raw in ⅓ scale | No | **Yes** |
| 1 | `ExposureLadderTest`, `DurationFormatTest` | `ExposureScale`, formatters | ladder, durations | 55 entries; day/mo/yr formatting | partly | **Yes** |
| 2 | `ReciprocityPolicyOrderTest` | policy evaluator | profiles + metered | order + basis enum | No | **Yes** (protected) |
| 2 | `ReciprocityFormulaTest` | `ReciprocityFormula.evaluate` | Acros II 119.999999; b<0 | noCorrection/within/beyond/unsafe-clamp | partly | **Yes** |
| 2 | `ReciprocityTableInterpolationTest` | `TableInterpolationModel` | Fomapan/Tri-X anchors | through-anchor exact; extrapolate; 10% tol; `max(c,m)` | No | **Yes** |
| 2 | `ConfidencePresentationTest` | presentation mapper | each basis | labels; forbidden vocab absent | rule-12 | **Yes** (protected) |
| 2 | `CatalogLoaderTest` + `CatalogValidationFixtureTest` | loader + `catalog-validation-cases.json` | bundled JSON | 37 films, order, manufacturer counts, formula params, threshold ranges, rejection cases | **Yes** | **Yes** (count drift resolved) |
| 2 | `CatalogCalculationGoldenTest` | 11 table + sample formula films | sampled metered | corrected matches anchor-derived log-log / formula | derived | **Yes** |
| 3 | `TimerStateTransitionTest` | `TimerStatePauseResumeTests` | paused remaining 6 @ +2/+7; pause at end | exact transitions; duration not zeroed; paused→completed only via resume | No | **Yes** (protected) |
| 3 | `TimerRuntimeTickTest` | `TimerManager*` rules | injected clock | independent ticks; exactly-once completion; reconcile no-replay | No | **Yes** |
| 3 | `TimerRestoreTest` | `PersistentTimerSnapshot` restore | snapshots; `now≥end−ε` | auto-complete; paused-freeze; corrupt→completed; legacy `stopped` | No | **Yes** (protected) |
| 3 | `TimerOrderingTest` | ordering tests | mixed timers | active LIFO; completed desc; selection no-reorder | No | **Yes** |
| 4 | `TimerWorkflowViewModelTest` | VM integration | start/pause/resume/remove | UiState reflects lifecycle; one-way intents | No | **Yes** |
| 4 | `CoordinatorTickTest` | tick coordinator | virtual time | tick advances; stops when none running | No | **Yes** |
| 4 | `DataStoreTimerRoundTripTest` | persistence | round-trips | restore correct; corrupt fail-safe; empty clears | No | **Yes** |
| 5 | `CalculatorFilmViewModelTest` | calc+film integration | base/ND/film/clear | adjusted+corrected; digital on clear | No | **Yes** |
| 5 | `StartEnablementTest` | timer-integration tests | Portra/Velvia/digital | limited blocks corrected; beyond-source starts; digital adjusted | No | **Yes** |
| 5 | `AuthorityLabelPresenterTest`, `ResultRowPresenterTest` | presenters | profiles/results | labels; no fabricated numbers | No | **Yes** |
| 6 | `CameraSlotSessionStateTest` | slot tests | 4 slots, switch | per-slot independence; capture/restore | No | **Yes** |
| 6 | `SlotRenameTest` | rename tests | rename/empty | trim; reset; isolated from calc + started timers | No | **Yes** |
| 6 | `SlotSessionRoundTripTest` | persistence | reload×2 | slots survive; future schema ignored | No | **Yes** |
| 6 | `TimerIdentityCaptureTest` | metadata/identity tests | start then mutate | identity frozen; manual captures none | No | **Yes** |
| 7 | `ReciprocityDetailsPresenterTest` | details presenters | profiles | model/basis/provenance text; vocab gate | partly | **Yes** |
| 7 | `CompletionNotificationRuleTest` *(cond.)* | notification rules | start/pause/complete | schedule-on-start; cancel-on-pause; exactly-once | No | only if notification included |

---

## 9. Slice-by-slice execution plan

For every slice: **steps → expected result → tests → self-review → stop
condition → rollback/amend.** Self-review checklist (all slices): `:core` has
no Android dep; calc/domain out of Composables; ViewModel exposes immutable
state; one-way intents; persistence behind interfaces; explicit parse errors;
ticks owned by coordinator/runtime; protected-area parity; no iOS change; no
unrelated cleanup; state holders don't reference each other.

- **Slice 0.** Steps: add `:core` module + deps + plugins. Result: both modules
  build, app still shows placeholder. Tests: `:core:test` smoke. Stop: `gradlew
  :core:test assembleDebug` green. Rollback: revert build files only.
- **Slice 1.** Steps: port exposure types + formatters; copy nothing yet. Result:
  exposure fixtures pass. Tests: §8 Slice-1. Stop: all exposure fixtures green;
  epsilon = 1e-6. Amend: if a golden mismatches, diff against iOS math before
  changing the fixture (fixture is authoritative).
- **Slice 2.** Steps: port domain + evaluators + presentation + loader; copy
  catalog JSON resource. Result: catalog loads, reciprocity computes for all 37
  films incl. 11 table films. Tests: §8 Slice-2. Stop: catalog + reciprocity +
  table-calc green; vocabulary gate green. Amend: on rule-11 conflict, follow
  §1.4 decision (assert the catalog's three real shapes).
- **Slice 3.** Steps: port timer state machine + runtime + snapshot. Result:
  deterministic transitions + restore. Tests: §8 Slice-3. Stop: transition +
  restore green. Amend: keep `1e-6`; never zero duration.
- **Slice 4.** Steps: coordinator + ViewModel + DataStore timer store + minimal
  timer UI. Result: **first runnable app** — multi-timer lifecycle + relaunch
  restore. Tests: §8 Slice-4 + manual (start/pause/resume/remove/relaunch).
  Stop: lifecycle + restore green in tests and on device. Amend: if tick races,
  make the clock injectable and assert virtual time.
- **Slice 5.** Steps: calculator + film selection state + presenters + shooting
  UI; wire Start. Result: single-slot shooting workflow; start from real result.
  Tests: §8 Slice-5 + manual steps 1–9. Stop: workflow green; enablement rule
  correct. Amend: no fabricated numbers for non-quantified.
- **Slice 6.** Steps: camera-slot session state + persistence + pager + rename +
  identity composer. Result: **MVP feature-complete** — multi-slot shooting,
  per-slot state, immutable timer identity, persistence. Tests: §8 Slice-6 +
  manual step 10–11. Stop: multi-slot + identity + persistence green. Amend: if
  switch loses state, verify capture-before-restore ordering.
- **Slice 7.** Steps: Details presenter + sheet (Must); then, only if Must scope
  is stable and low-risk, the basic completion notifier. Result: Details shows
  model/basis/provenance; (cond.) one notification per completion. Tests: §8
  Slice-7. Stop: Details green; notification (if included) obeys the rule.
  Amend: if background delivery proves non-trivial, drop notification to
  follow-up (per owner decision) and ship Must scope.

---

## 10. Round 3 readiness criteria

Before implementation may begin (after Round 3 acceptance), all must hold:

- **Accepted architecture decisions:** pure `:core` JVM module; no version
  catalog; minimal deps (§2); `:app` owns ViewModel/Compose/persistence/coord.
- **Accepted scope:** Must = §4 Slices 0–6 + Slice 7 Details; Scope-B
  notification conditional; Target Shutter / custom-formula / PTIMER-165
  table-fitted deferred.
- **Resolved:** catalog basis (37 films; 20 formula / 11 table / 6
  threshold+limited; manufacturer counts §1.1); `TableInterpolationModel`
  **required** for catalog calc; `calculationBasis` = 5-case enum.
- **Tests identified:** full §8 matrix mapped to fixtures/iOS behavior, with
  per-slice "required before done" flags.
- **Unresolved questions (need owner sign-off in Round 3):**
  - **Q-A (fixture drift):** confirm Android asserts the catalog's three real
    profile shapes and does **not** enforce the stale fixture rule-11
    two-shape restriction; confirm the iOS fixture top-up (rule-11 +
    perFilmExpectations for the 11 table films) is tracked as a separate
    iOS-side concern, out of 146.
    - **Q-B (notification):** confirm whether the basic completion notification
    is attempted in 146 (Slice 7, conditional) or deferred wholesale.
  - **Q-C (persistence consolidation):** confirm the greenfield decision to fold
    timer display/identity metadata into a single `PersistentTimerCollectionSnapshot`
    and the calculator context into the slot-session snapshot (vs mirroring the
    iOS multi-snapshot split).
  - **Q-D (catalog resource):** confirm copying `LaunchPresetFilmCatalog.json`
    verbatim into `:core` resources is acceptable (vs a generated copy step).
- **Guards:** no implementation yet; no production source changed; no commits;
  no Jira; no tickets.

---

*End of Round 2. This is a detailed implementation design for review — not
implementation approval. Round 3 readiness review must be accepted first.*
