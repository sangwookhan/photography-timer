# PTIMER-146 — Android MVP Migration Plan (Round 1-1, corrected)

> **Status:** Planning document only. Round 1-1 correction of the Round 1
> plan. **Not** an implementation-ready spec. No code has been written, no
> commits made, no tickets created, no Jira edited.
>
> **Planning pipeline gate:** implementation may begin only after three
> planning rounds are accepted — Round 1-1 (this document), Round 2
> (detailed implementation plan), Round 3 (readiness review).

---

## 0. What changed from Round 1

- **Re-baselined to `main` before PTIMER-165.** PTIMER-165 custom reciprocity
  *table input* and *fitted-formula preview/generation* are removed from
  PTIMER-146 implementation scope and recast as a later Android follow-up.
- **Camera slots promoted to Must scope.** Round 1 allowed a single-slot MVP
  with slots as "Should-include." Multi-camera shooting is a primary PTIMER
  product problem, so per-slot calculator/film/timer-identity state is now a
  required part of the MVP, with a concrete Android plan (§4 / §7).
- **Architecture decisions tightened.** Explicit recommendation on the
  `:core` module vs an in-`:app` boundary, an explicit decision to **not**
  introduce a version catalog for 146, and a minimal, justified dependency
  list (§3).
- **Parity table reduced to a prioritized MVP table** with an explicit
  "required for 146 vs deferred vs iOS-only vs UI-polish" classification (§5).
- **Slices rewritten** to the required shape with explicit stop conditions,
  and camera slots + multi-timer workflow are required *before* the MVP is
  called complete (§6).
- **Review loop made concrete** (Claude self-review → ChatGPT review →
  fix/amend, per slice; three planning rounds before implementation) (§7-loops).

---

## 1. Baseline (authoritative for this round)

- **Planning baseline:** current `main` *before* PTIMER-165.
- **PTIMER-165 is excluded from PTIMER-146.** Specifically, custom
  reciprocity *table anchor input*, *log-log table model selection as the
  active calculation for custom profiles*, and *app-derived fitted-formula
  generation/preview* are **not** in PTIMER-146 scope.
- **PTIMER-165 Android integration is a later follow-up** task, opened only
  after PTIMER-165 itself is complete.
- **Any custom-profile behavior in PTIMER-146 is limited to baseline-main
  behavior** — i.e. custom *formula* profile authoring (the PTIMER-84/128
  lineage), never PTIMER-165 table/fitted behavior.

> **Baseline integrity note (owner decision needed — see §9 Q1).** The
> custom-table / fitted-formula source files
> (`CustomFilmEditorTableFormState`, `CustomTableFittedFormulaPresenter`,
> `TableInterpolationModel`, the table-capable `ReciprocityFormulaFitter`
> path) are **physically present on the current `main` checkout**. This
> contradicts "plan against main before PTIMER-165 starts." This document
> follows the owner directive — those behaviors are treated as PTIMER-165 and
> excluded from 146 — but the physical/conceptual mismatch is flagged rather
> than silently resolved. The Android port simply does not implement the
> table/fitted surfaces in 146; the underlying `ReciprocityFormulaFitter` and
> `TableInterpolationModel` algorithms are ported **only** if a baseline-main
> reciprocity profile actually requires them at calculation time (see §5).

---

## 2. Verdict and verified current state

### 2.1 Verdict

**PTIMER-146 can deliver a working Android MVP — including camera slots — as
one ticket, on the re-baselined scope, before UI-polish follow-ups.** The
domain layer is pure and fixture-backed, every OS surface on iOS already sits
behind a protocol seam, and `shared/test-fixtures/` is a ready-made
iOS↔Android equivalence oracle. Excluding PTIMER-165 *reduces* risk; promoting
camera slots adds bounded, well-understood work (per-slot state + persistence).

### 2.2 Verified current state (condensed; full detail in Round 1 inspection)

**Android side** — stock Android-Studio Empty-Compose-Activity template,
renamed package only, **zero product behavior**. Toolchain: Gradle 8.9, AGP
8.7.3, Kotlin 2.0.21, Compose compiler 2.0.21, Compose BOM 2024.10.01,
compileSdk/targetSdk 35, **minSdk 26** (so `java.time` is available), Java 17.
Single `:app` module, `applicationId`/`namespace` `com.sangwook.ptimer`, **no
version catalog**. Present deps: core-ktx, lifecycle-runtime-ktx 2.8.7,
activity-compose 1.9.3, Compose ui/material3 (BOM), JUnit4, espresso, compose
ui-test. **Absent:** kotlinx.serialization, DataStore, coroutines artifact,
viewmodel-compose, WorkManager. Only test is a trivial `ExampleUnitTest`.

**iOS domain (`PTimerCore`, Foundation-only — the port target)** — exposure
calculator (`calculate = base · 2^stops`, `stabilityEpsilon = 1e-6`, 19-value
full-stop ladder, 55-entry one-third ladder via `2^(1/3)`/`2^(2/3)` inserts,
ND whole stops `0…30`, snap-to-full-stop gated on full-stop scale **and**
whole-stop ND), reciprocity domain + `ReciprocityCalculationPolicyEvaluator`
(protected evaluation order), `ReciprocityFormula` `Tc = a·(Tm/Tref)^p + b`
(family `modifiedSchwarzschild`), confidence-presentation mapping, `TimerState`
sum type + restore semantics (`timerStabilityEpsilon = 1e-6`), catalog loader
with 12 validation rules.

**iOS app-logic (`PTimerKit`)** — `@MainActor` facade + six feature models
(calculator, reciprocity, film selection, camera-slot session, target shutter,
timer workspace), composed only by `WorkspaceCoordinator` (models never import
each other), pure `*Presenter`/`*DisplayState` types, `*Storing` persistence
protocols + `Persistent*` schemas (`schemaVersion = 1`), pure `TimerRuntime`
behind `TimerManaging` (tick driven externally). All OS surfaces (RunLoop tick,
notifications, ActivityKit, concrete `UserDefaults*Store`) are behind seams
with `NoOp` defaults.

**Shared fixtures (parity oracle)** — `shared/test-fixtures/exposure-golden.json`
(22 calc cases, 4 error cases, 19 full-stop speeds, 4 shutter-format, 10
time-display) and `shared/test-fixtures/catalog-validation-cases.json`
(`expectedFilmCount = 37`, 12 validation rules, 34 per-film expectations, 6
rejection cases; constrained reciprocity vocabulary).

**Known drift to resolve before asserting counts** — narrative says "34
films," fixtures say **37**, `perFilmExpectations` covers 34; manufacturer
counts differ between narrative and fixture. `DomainSchema.md §6` omits
`tableLogLogDerived` from the `calculationBasis` enum the code defines (port
the code's 5-case enum). See §8.

**Camera slots are core, not optional** (confirmed in specs/code): 2–4 slots,
each owning independent film/baseShutter/ND/scale/target; switching captures
the outgoing slot and restores the incoming; rename trims whitespace and is
isolated from calc state and from already-started timers; persisted via
`PersistentCameraSlotSessionSnapshot` (`schemaVersion = 1`).

---

## 3. Architecture (corrected)

### 3.1 `:core` module vs an in-`:app` boundary

**Recommendation: introduce a pure-Kotlin `:core` Gradle module
(`org.jetbrains.kotlin.jvm`, no Android dependencies).**

- **Why the module boundary is worth it.** The parity-critical surface
  (exposure math, reciprocity policy, timer state machine, catalog
  loading/validation, persistence schemas) is large and is exactly the code
  that must be provably identical to iOS. On iOS this boundary is enforced
  *mechanically* — `PTimerCore` is Foundation-only and the macOS build fails
  if UIKit leaks in. A pure `kotlin.jvm` module reproduces that guarantee by
  construction: Android framework types are simply **not on the classpath**,
  so a `View`, `Context`, or `ViewModel` import cannot compile in `:core`.
- **Tradeoff.** Cost is a second `build.gradle.kts`, a `settings` include, and
  slightly slower first configuration. The alternative — keeping everything in
  `:app` and enforcing "no Android in domain packages" via convention or an
  ArchUnit/Konsist rule — is weaker (relies on a lint rule staying green and
  being run) and easy to violate accidentally, which is precisely the failure
  mode the iOS design spends effort to prevent. For a domain this size and this
  parity-sensitive, the mechanical guarantee outweighs the module overhead.
- **`:core` JVM tests are emulator-free**, mirroring iOS `swift test`
  (off-simulator) for the bulk of the suite — a real velocity win for the
  fixture-driven parity tests.

`:app` holds ViewModels, Compose UI, the tick coordinator, DataStore
persistence implementations, and OS adapters. The pure presenter / state-mapper
logic (iOS `PTimerKit`'s non-SwiftUI parts) lives as **plain classes in `:app`
state/presenter packages** so they stay JVM-unit-testable without Robolectric.
A future third `:kit` android-library is possible but **not** needed for 146.

**Dependency direction:** `:app → :core`. `:core` depends on nothing Android.

### 3.2 Version catalog decision

**Recommendation: do NOT introduce a version catalog (`libs.versions.toml`)
for PTIMER-146.** With only two modules sharing a small, stable dependency set,
a catalog is cleanup, not a 146 need. Versions can be declared inline (or in a
small root `extra`/`ext` block) and kept aligned by hand across `:core` and
`:app`. If module count grows in later Android tickets, revisit then — at that
point the catalog earns its keep. This keeps the 146 diff focused on product
behavior, not build-tooling churn.

### 3.3 Required dependencies (minimal, each tied to the MVP)

| Module | Dependency | Why it is required for 146 |
|---|---|---|
| `:core` | `kotlinx-serialization-json` (+ serialization plugin) | Codable parity for the bundled catalog JSON and the `Persistent*` snapshot schemas; lets the same JSON shapes round-trip as on iOS. |
| `:core` (test) | `junit:4.13.2` (already in repo) | Fixture-driven + state-machine unit tests. |
| `:app` | `kotlinx-coroutines-android` | The timer tick loop (replacing the iOS RunLoop) and `StateFlow` exposure of UI state. |
| `:app` | `androidx.lifecycle:lifecycle-viewmodel-compose` + `lifecycle-runtime-compose` (`collectAsStateWithLifecycle`) | ViewModel ownership of state across config changes and lifecycle-correct state collection in Compose. |
| `:app` | `androidx.datastore:datastore-preferences` (or `datastore-core` with a JSON serializer) | Persistence behind the `:core` `*Store` interfaces (timers, calculator context, camera-slot session). UserDefaults has no 1:1 analogue; DataStore is the idiomatic, async-safe replacement. |
| `:app` (test) | `kotlinx-coroutines-test` | Virtual-time tests for the tick coordinator and ViewModels. |
| `:app` (androidTest) | Compose `ui-test-junit4` (already present) | Should-include Compose UI smoke tests. |

No WorkManager / notification deps in Must scope (background notification is
"May include," §4). No third-party DI, no Turbine, no Room — kept deliberately
out to minimize the MVP surface.

---

## 4. Scope correction (A / B / C)

### A. Must include in PTIMER-146

- Pure-Kotlin `:core` boundary (per §3.1).
- **Exposure calculation** (`calculate`, parse, overflow→typed error).
- **Base-shutter ladder** (55-entry one-third ladder; picker-only entry).
- **ND integer stop behavior** (`0…30`).
- **Duration / shutter formatting** needed by the MVP (the
  `exposure-golden.json` format ladder: `1/N`, `N.Ns`, `MM:SS`, `HH:MM:SS`,
  day/month/year, locale-independent).
- **Film catalog / profile loading** (bundled JSON + the 12 validation rules;
  fail-to-load on malformed, not silent).
- **Reciprocity calculation and presentation semantics** — policy evaluator
  order, formula evaluation, confidence-presentation mapping, constrained
  vocabulary. *(Log-log table interpolation is ported only if a baseline-main
  catalog profile requires it at calc time — see §5; the PTIMER-165 custom
  table/fitted UI is not built.)*
- **Film selection / clear film** (No-film = digital workflow).
- **Digital adjusted-shutter result.**
- **Film adjusted-shutter + corrected-exposure result** (two fixed rows;
  non-quantified shows status, never a fabricated number).
- **Start timer from a valid result** (enablement rule: limited-guidance blocks
  the corrected-exposure timer; quantified positive-finite enables it).
- **Timer runtime:** start, pause, resume, complete, remove.
- **Multiple timers.**
- **Completed history + basic ordering** (active group LIFO-by-creation;
  completed group completion-time descending, behind active).
- **Camera slots** with per-slot calculator state, per-slot film/profile state,
  and per-slot timer-identity capture (§7). *Not* reduced to one slot.
- **Basic persistence + restore** for timers, calculator context, and the
  camera-slot session.
- **Basic Reciprocity Details screen/sheet** (model, basis, provenance,
  source-reference summary).
- **Android unit / ViewModel tests proving parity** for the above (fixtures +
  ported state-machine + ViewModel behavior).
- **Android build/test documentation update** if commands change.

### B. May include only if low-risk after Must scope is stable

- **Basic Android notification on timer completion** (NotificationManager;
  schedule-on-start / cancel-on-pause / exactly-once rule from the iOS
  TimerManager notification + completion-alert tests). Background reliability
  via WorkManager/AlarmManager is the risky part — only if Must scope is solid.
- **Target Shutter** — only because it exists on baseline main; include only if
  it does not destabilize the Must MVP. Per-slot target persistence already
  fits the camera-slot snapshot.
- **Minimal custom-profile behavior** — **only** custom *formula* profile
  authoring that exists on baseline main (create/validate a formula profile,
  no-shortening guard, library persistence). **Explicitly excludes** PTIMER-165
  table input and fitted-formula preview.

### C. Defer / follow-up

- **PTIMER-165 custom table / fitted-preview behavior** (separate Android
  follow-up after PTIMER-165 completes).
- iOS-level custom-profile editor polish.
- Exact Reciprocity Details **graph** parity (curve sampling, markers).
- Android lock-screen / widget (iOS Live Activity equivalent).
- Bottom-sheet drag choreography and exact iOS layout tuning (92/64 pt
  thresholds, density tiers, three-layer progress animation).
- Full visual polish after human testing.
- Aperture/ISO variables (already deferred on iOS).
- Any behavior not present on baseline main.

---

## 5. iOS test behavior inventory (prioritized MVP table)

Classified by *protected behavior*. "Android test type" picks the cheapest
layer that genuinely proves the behavior. Large optional surfaces are listed
only where they touch Must scope.

### 5.1 Required parity for PTIMER-146

| iOS test group / source | Protected behavior | Representative inputs | Expected result / invariant | Android test type | 146? |
|---|---|---|---|---|---|
| `ExposureCalculatorTests`, `ExposureCalculationAccuracyTests`; `exposure-golden.json` `cases` | output `= base·2^stops`; overflow→typed error | `1/30 +6 → 2`; `1/8 +10 → 128`; `1 +24 → 2^24` | exact (tol 1e-4); monotonic; `log2(out/base)=stops` | `:core` JVM (param. over fixture) | **Required** |
| snap suite; `exposure-golden.json` `_meta` | snap gated on full-stop scale **and** whole-stop ND; power-of-two >64 | `1.0 +3/+4/+5 → 8/15/30`; `1/30 +11 → 64` (not 60) | one-third scale = raw; snap only in full-stop scale | `:core` JVM | **Required** |
| `shutterFormatCases`, `timeDisplayCases` | shutter + duration formatting ladder | `0.0333→"1/30s"`, `90000→"1d 01:00:00"`, `128.25→"02:08.250"` | exact, locale-independent (month=30d, year=365d) | `:core` JVM (fixture) | **Required** |
| `errorCases` | typed failures, not bad numbers | `""`,`"abc"`,`"0"`, ND `-1` | `emptyBaseShutter`/`invalidBaseShutter`/`nonPositiveBaseShutter`/`nonPositiveND` | `:core` JVM (fixture) | **Required** |
| `ReciprocityCalculationPolicyEvaluator` suites | evaluation order formula→threshold→limited→unsupported; result form↔basis pairing | catalog profile + metered seconds | exact result variant + `calculationBasis` (5-case enum) | `:core` JVM | **Required** (protected) |
| `ReciprocityFormula.evaluate` | `Tc=a(Tm/Tref)^p+b`; strict no-correction; unsafe-shortening clamp | Acros II `119.999999`; b<0 | `noCorrection`/`withinSourceRange`/`beyondSourceRange`/`unsafeShorteningFormula` | `:core` JVM + fixture per-film | **Required** |
| `ReciprocityConfidencePresentation` mapping | basis→category/label/badge; forbidden vocabulary | each basis | "No correction"/"Formula-derived"/"Beyond source range"; never Exact/Estimated/Interpolated/Extrapolated/Advisory | `:core` JVM + `catalog-validation-cases` rule-12 | **Required** (protected) |
| `LaunchPresetFilmCatalog(Shape)Tests`; `catalog-validation-cases.json` | catalog loads; 12 rules; allowed profile shapes; rejection cases | bundled JSON | count/order/ids/manufacturer-counts; explicit fail-to-load | `:core` JVM (fixture) | **Required** (resolve count drift first) |
| `FilmSelectorSupportPresenterTests`, authority tests | manufacturer vs custom authority; never present user data as manufacturer | official / unofficial / userDefined | "Official guidance"/"Unofficial practical"/"Custom"; badge tone follows calc status first | `:app` presenter unit test | **Required** |
| `TimerStatePauseResumeTests`; `ios/PTimerTests/Timers/*` (rules) | state machine running⇄paused→completed; resume recomputes endDate; pause-at-0 short-circuit | paused remaining 6 @ +2/+7; pause at endDate | exact transitions; duration never zeroed; `paused→completed` only via resume | `:core` JVM (fake clock) | **Required** (protected) |
| `TimerManagerTests/PauseResume/Reconcile/CompletionAlert` (*rules*) | multi-timer independent ticks; reconcile w/o replaying alert; completion alert exactly once | several timers, injected clock | independent remaining; idempotent completion; one alert per transition | `:app` ViewModel/coordinator test (virtual time) | **Required** (mechanism differs; rule matches) |
| `TimerManagerPersistenceRestoreTests`; `PersistentTimerSnapshot` | snapshot schema; paused omits `expectedCompletionAt`; running auto-completes on restore if past end; corrupt paused→completed (no fabricated time) | snapshot round-trips; `now ≥ end−ε` | exact restore; legacy `"stopped"`→paused decode tolerated | `:core` JVM + `:app` DataStore round-trip | **Required** (protected) |
| `Calculator…MetadataTests`, identity tests | timer identity captured once at start, immutable across slot rename / film swap / restore; manual timer captures no identity | start corrected timer, then mutate | identity frozen; exposure-source preserved | `:app` ViewModel test | **Required** |
| `BottomSheetWorkspaceOrderingTests` | active LIFO-by-creation; completed behind, completion-desc; selection doesn't reorder | mixed timers | stable ordering across status changes | `:core`/`:app` pure unit test | **Required** |
| `ExposureCalculatorViewModelTimerIntegrationTests` | start-from-adjusted/corrected; limited-guidance blocks corrected; beyond-source formula still starts | Portra (limited), Velvia (beyond), digital | `canStartCorrected` flags; correct duration source | `:app` ViewModel test | **Required** |
| `CameraSlot*` tests | 2–4 slots; per-slot independent state; capture-on-switch / restore-on-return; rename isolation + immutability on started timers | 4 slots, switch + rename | independent film/ND/scale; rename ≠ inputs; persists across relaunch | `:app` ViewModel test + `:core`/`:app` persistence test | **Required** |

### 5.2 Deferred — PTIMER-165-related (NOT in 146)

| iOS source | Behavior | Why deferred |
|---|---|---|
| `CustomFilmEditorTableFormStateTests`, `CustomFilmTableProfileFlowTests` | custom table anchor input + validation | PTIMER-165 |
| `CustomTableFittedFormulaPresenterTests` | fitted power-law preview, per-anchor error, fit quality | PTIMER-165 |
| `TableInterpolationModel` log-log tests (as a *custom* calc path) | log-log table model selected as active calc for custom profiles | PTIMER-165 |

> **Caveat:** if a *baseline-main catalog* profile (e.g. a manufacturer film
> whose only rule is a log-log table) requires `TableInterpolationModel` at
> calculation time, that algorithm is ported as part of §5.1 reciprocity — but
> the **custom table authoring UI and fitted-formula preview are not built**.
> Resolving exactly which baseline catalog profiles need the table evaluator is
> a Round 2 input (§9 Q2).

### 5.3 iOS-only platform tests (no Android equivalent in 146)

| iOS source | Behavior |
|---|---|
| `CalculatorTimerLockScreenTests`, B4 lock-screen traces | ActivityKit / Live Activity |
| `App/BottomSheetWorkspaceShell/LayoutMetricsTests` | UIApplication portrait lock, SwiftUI shell geometry |
| `RecordReplay/*` | iOS-specific trace-baseline harness |
| concrete `UserDefaults*Store` tests | iOS storage binding (Android uses DataStore) |

### 5.4 UI-polish tests requiring human review (deferred)

| iOS source | Behavior |
|---|---|
| `DisplayStateSnapshotTests` (golden text) | presenter output strings — optional Android parity guard later |
| compact-dock layout / progress-layer tests | drag thresholds, density tiers, progress animation |
| Details **graph** sampler/marker tests | curve fidelity |

---

## 6. Implementation slices (corrected)

Each slice ends green, is independently reviewable, and has an explicit stop
condition. **The MVP is not "complete" until Slice 6 (camera slots) and the
multi-timer workflow in Slice 4 are done and green.**

### Slice 0 — Gradle foundation
- **Goal:** create the pure-Kotlin boundary and wire minimal deps.
- **Test-visible result:** `:core` compiles and runs a trivial JVM test; `:app`
  depends on `:core`; app still launches the placeholder.
- **Files/packages:** `settings.gradle.kts`, `core/build.gradle.kts`,
  `app/build.gradle.kts` (add serialization, coroutines, viewmodel-compose,
  DataStore; **no** version catalog).
- **Tests:** `:core` smoke test.
- **Checkpoint:** `:core` classpath contains no Android artifacts.
- **Stop condition:** `./gradlew :core:test assembleDebug` green before any
  domain code.

### Slice 1 — Exposure core + golden parity
- **Goal:** port the exposure calculator and formatters.
- **Test-visible result:** `exposure-golden.json` passes end-to-end on Android.
- **Files/packages:** `core/.../exposure/` (`ExposureCalculator`,
  `ExposureScale`, `NDStep`, formatters, errors).
- **Tests:** parameterized over `cases`/`errorCases`/`shutterFormatCases`/
  `timeDisplayCases`; snap unit tests.
- **Checkpoint:** math in `:core`; locale-independent formatting; `1e-6` epsilon
  matches iOS.
- **Stop condition:** all exposure fixtures green.

### Slice 2 — Reciprocity core + catalog
- **Goal:** port reciprocity domain, policy evaluator, formula evaluation,
  confidence presentation, catalog loader/validation; copy catalog JSON.
- **Test-visible result:** `catalog-validation-cases.json` passes; reciprocity
  results match per-film expectations.
- **Files/packages:** `core/.../reciprocity/`, `core/.../catalog/`,
  bundled catalog JSON as a `:core` resource.
- **Tests:** validation rules, per-film formula params, rejection cases,
  vocabulary gate (rule-12), evaluator order.
- **Checkpoint:** 5-case `calculationBasis` enum (ignore stale doc); evaluation
  order matches; **film-count drift resolved** (§8 / §9 Q3).
- **Stop condition:** catalog + reciprocity fixtures green.

### Slice 3 — Timer state machine + persistence (core)
- **Goal:** port `TimerState`, `TimerRuntime`, `PersistentTimerSnapshot`,
  restore.
- **Test-visible result:** deterministic transition + restore tests pass.
- **Files/packages:** `core/.../timer/`.
- **Tests:** pause/resume/complete (fake clock); restore (auto-complete,
  paused-freeze, corrupt→completed, legacy `"stopped"`).
- **Checkpoint:** `paused→completed` only via resume; duration never zeroed.
- **Stop condition:** state-machine + restore tests green.

### Slice 4 — Timer coordinator + ViewModel + first runnable timers UI
- **Goal:** first genuinely runnable app — start/observe/pause/resume/remove
  multiple timers; relaunch restores them.
- **User-visible result:** tap to start a timer, see it count down; multiple
  timers run independently, newest-first; completed move to a completed group;
  kill+relaunch restores running/paused timers.
- **Files/packages:** `app/timer/AndroidTimerCoordinator` (coroutine tick),
  `app/vm/ShootingViewModel` (`StateFlow` + sealed `ShootingIntent`),
  `app/persistence/` (DataStore timer store), minimal `app/ui/` timer list.
- **Tests:** ViewModel/coordinator (virtual time) — tick, reconcile,
  exactly-once completion, ordering, identity-at-start.
- **Checkpoint:** Composables never tick; events one-way; persistence behind
  the `:core` interface.
- **Stop condition:** multi-timer lifecycle + restore green on device/emulator
  and in tests.

### Slice 5 — Calculator + film selection wired into UI
- **Goal:** the shooting calculation surface for a single active slot.
- **User-visible result:** pick base shutter + ND → adjusted shutter; pick film
  → corrected exposure + badge; clear film → digital; Start Timer enablement
  follows the rule; calculator context restores on relaunch.
- **Files/packages:** `app/ui/` (pickers, film picker sheet, result rows),
  `app/state/` + presenters, calculator-context DataStore store.
- **Tests:** ViewModel integration (adjusted/corrected/limited/beyond) +
  context round-trip; authority-subtitle presenter tests.
- **Checkpoint:** no fabricated numbers for non-quantified; authority labels
  correct.
- **Stop condition:** single-slot shooting workflow green; can start a timer
  from a real corrected result.

### Slice 6 — Camera slots (required before MVP complete)
- **Goal:** multi-camera shooting — per-slot calculator/film state, capture on
  switch, restore on return, per-slot timer identity, persistence.
- **User-visible result:** swipe/select among 4 slots; each keeps its own
  film/base/ND; a timer started in a slot carries that slot's label; slots
  survive relaunch; (rename if included).
- **Files/packages:** `app/state/CameraSlotSessionState`,
  `app/ui/` slot pager + (optional) rename dialog,
  `core/.../persistence/PersistentCameraSlotSession*` + DataStore impl.
- **Tests:** per-slot independence; capture-on-switch/restore; rename isolation
  + immutability on started timers; session persistence round-trip across
  relaunch (greenfield — **no** iOS legacy single-context migration needed).
- **Checkpoint:** slot stamped on timer at start is immutable; state holders
  don't reference each other.
- **Stop condition:** multi-slot workflow + persistence green. **MVP feature-complete here.**

### Slice 7 — Basic Reciprocity Details (Must) + Scope-B sub-slices
- **Goal:** basic Details sheet (Must); then, if low-risk: notification,
  target shutter, custom *formula* authoring.
- **Result:** Details shows model/basis/provenance/source-reference summary;
  Scope-B items each behind their own green tests.
- **Files/packages:** `app/ui/` Details, plus per-feature packages.
- **Tests:** presenter unit tests; per Scope-B feature tests.
- **Checkpoint:** vocabulary gate; "Custom" never shown as manufacturer; each
  Scope-B item independently revertable.
- **Stop condition:** Details green; Scope-B items added only with Must scope
  stable.

---

## 7. Camera slot plan (concrete)

- **UI representation.** A horizontal pager across the configured slots (ship
  4; config range 2–4) — Compose `HorizontalPager` (foundation) or a simple
  segmented slot selector for the first cut. Active slot's display name is the
  screen title; a page indicator sits below. Visual styling is allowed to stay
  rough until human tuning.
- **Per-slot calculator state.** Each slot owns `baseShutterSeconds`,
  `ndStop`/`ndStep`, `exposureScaleMode`. Switching slots captures the outgoing
  slot's live state into its snapshot and restores the incoming slot's snapshot.
- **Per-slot film/profile state.** Each slot owns `selectedPresetFilmID?` and
  `selectedProfileID?`. Unresolvable film → No-film; unresolvable profile →
  primary profile (matching iOS fallback semantics).
- **Per-slot timer identity capture.** On Start, snapshot the active slot id +
  the slot's display label *as it stands at start* into the timer identity
  (`ExposureTimerIdentitySnapshot` analogue). Frozen thereafter — later slot
  switches, renames, or film swaps never mutate a started timer's identity.
- **Rename behavior (if included — Scope B-adjacent, low cost).** A dialog/sheet
  sets a custom name; trimmed; empty/whitespace resets to canonical
  `Camera N`. Rename changes only the display name — not inputs, film, scale,
  result, the slot's stable id, or any already-started timer's captured label.
- **Persistence shape.** `PersistentCameraSlotSessionSnapshot { schemaVersion =
  1, activeSlotIDRaw, slots: [PersistentCameraSlotCalculatorSnapshot] }`, where
  each slot snapshot carries `slotIDRaw`, `selectedPresetFilmID?`,
  `selectedProfileID?`, `baseShutterSeconds?`, `ndStop?`, `ndStopThirds?`,
  `exposureScaleMode?`, `customDisplayName?`, and (if Target Shutter is
  included) `targetShutterSeconds?`. Serialized via kotlinx.serialization into
  DataStore. **Android is greenfield — no legacy single-context migration path
  is required** (a simplification vs iOS).
- **Tests required.** Per-slot independence; capture-on-switch + restore-on-
  return; active-slot persistence; rename trim/reset + isolation from calc
  state and from started timers; full session round-trip across two relaunches;
  unresolvable film/profile fallbacks; future `schemaVersion` ignored on load.
- **What can stay visually rough until human tuning.** Pager swipe animation
  and indicator styling, slot-tint palette, rename-sheet layout, page-edge
  affordances. Behavior and persistence must be correct; pixels can wait.

---

## 8. Build and verification plan

```bash
# Pure-Kotlin domain — bulk of parity proof, no emulator
cd android && ./gradlew :core:test

# Whole project unit tests (core + app JVM)
cd android && ./gradlew test

# Debug build
cd android && ./gradlew assembleDebug

# Lint (run if practical)
cd android && ./gradlew lint

# Compose UI smoke tests (Scope B / if planned) — emulator/device
cd android && ./gradlew connectedDebugAndroidTest

# Install for manual verification
cd android && ./gradlew installDebug
```

- **iOS:** this plan touches **no** iOS code and no shared fixtures, so iOS
  verification is "confirm no iOS files changed." (If a shared fixture were
  ever edited — it should not be in 146 — then
  `swift test --package-path ios/PTimerKit` would be required.)
- **Manual Android MVP verification:** (1) launch → shooting screen; (2) base
  shutter + ND → adjusted shutter; (3) pick film → corrected + badge; (4) clear
  → digital; (5) Start → timer counts down; (6) second timer → both independent,
  newest-first; (7) pause/resume → freeze/continue; (8) complete → "Done", one
  alert; (9) remove; (10) **switch camera slot → independent film/ND per slot;
  start a timer in a slot → carries that slot's label**; (11) kill+relaunch →
  timers + calculator context + slot session restored; (12) open Details →
  model/basis/provenance shown.

**Known drift to resolve before Slice 2 assertions:** film count
(narrative 34 vs fixture 37; `perFilmExpectations` 34) and manufacturer counts.
Validate against the bundled catalog JSON + `catalog-validation-cases.json`
(machine-checkable truth), not prose. Port the code's 5-case `calculationBasis`
enum, not the stale `DomainSchema.md §6` list.

---

## 9. Review loops

### Per-slice loop (after every major slice)
1. **Claude self-review** against the §6 checkpoint and the parity table — does
   the slice meet its stop condition, stay in scope, and keep `:core` pure?
2. **ChatGPT review** — product intent, scope discipline, architecture sanity.
3. **Fix / amend plan** — apply corrections, re-run the slice's tests, and only
   then proceed to the next slice.

Architecture checkpoints to assert at each loop: domain/calc out of Composables;
`:core` has no Android dependency; ViewModels expose immutable `StateFlow`
state; UI→ViewModel one-way via sealed intents; persistence behind `*Store`
interfaces; catalog/profile parse errors explicit; ticks owned by the
coordinator/runtime, never a Composable; side effects isolated behind seams;
tests validate behavior not implementation; protected-area parity (exposure
calc+snap+epsilon, reciprocity order+semantics, confidence mapping, timer
pause/resume/complete, persistence schemas); no iOS behavior changed; no
unrelated cleanup; state holders don't reference each other.

### Planning gate (before any implementation)
Three planning rounds must be accepted in order:
1. **Round 1-1** — this corrected plan.
2. **Round 2** — detailed implementation plan (per-slice file-level design,
   exact Kotlin type mapping, resolved catalog count, persistence key/serializer
   choices).
3. **Round 3** — readiness review (parity oracle wiring confirmed, test layout
   agreed, risks closed).

Implementation begins only after Round 3 is accepted.

---

## 10. Risks and open questions

**Risks (discovered from source):**
1. **Film-count drift** (34 vs 37) — must be resolved against the catalog JSON +
   fixture before Slice 2 count assertions.
2. **`calculationBasis` doc drift** — port the code's 5-case enum.
3. **`perFilmExpectations` covers 34 of 37** — three films have structural-only
   coverage; validate those via loader rules; flag a fixture top-up.
4. **Background completion semantics** — foreground tick is straightforward;
   background notifications (WorkManager/AlarmManager) are OS-divergent and are
   Scope B, not Must.
5. **Baseline integrity** — PTIMER-165 files are physically on `main` (see §1
   note); the plan excludes them by directive, but the mismatch is real.

**Owner-decision questions (§9 references):**
- **Q1.** PTIMER-165 custom-table/fitted files are already on `main`. Confirm
  they remain out-of-scope for 146 (planned "as if" before PTIMER-165), and
  that the Android port simply does not implement those surfaces.
- **Q2.** Which baseline-main *catalog* profiles (if any) require the log-log
  table evaluator at calculation time? This determines whether
  `TableInterpolationModel` is ported in §5.1 reciprocity (without any custom
  table UI). Round 2 input.
- **Q3.** Confirm the authoritative film count/order/manufacturer counts
  (catalog JSON + `catalog-validation-cases.json` as truth over narrative).
- **Q4.** Confirm the architecture decisions: pure `:core` module (recommended)
  and **no** version catalog for 146 (recommended).
- **Q5.** Confirm Scope-B intent for 146: notification, Target Shutter, and
  custom *formula* authoring — in or out, given they affect sizing.
- **Q6.** Confirm camera-slot rename is in 146 (low cost) or deferred to polish.

---

*End of Round 1-1. This is a planning document; implementation is not ready and
must pass Round 2 and Round 3 review first.*
