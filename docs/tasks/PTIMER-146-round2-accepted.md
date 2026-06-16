# PTIMER-146 — Android MVP, Accepted Round 2 Planning Baseline

> **Status:** Planning only. This document consolidates and **supersedes**
> `PTIMER-146-round2.md` and `PTIMER-146-round2-1.md` as the single accepted
> Round 2 baseline for Round 3 readiness review. Round 1-1 remains the accepted
> scope-principle baseline. Not implementation approval. No production source
> changed (this document only), no commits, no Jira, no tickets.

---

## 1. Verdict

**The accepted Round 2 baseline is ready for Round 3 readiness review.** Scope is
aligned to current completed iOS shooting behavior (including PTIMER-165 and
PTIMER-180), the source base is clean, the architecture is settled, and the
test/slice plan is concrete. Four owner decisions remain (§12), all answerable
in Round 3; none blocks starting Round 3.

---

## 2. Base alignment

Verified in the `PTIMER-146-android-mvp` worktree:

- **Current HEAD:** `0078b80` — "Create an editable custom formula from a saved
  custom table (#14)".
- **Relationship to `origin/main`:** `HEAD == origin/main` (both
  `0078b80…`). `origin/main..HEAD` and `HEAD..origin/main` are both empty — the
  worktree branch `worktree-PTIMER-146-android-mvp` points exactly at
  `origin/main`. Working tree is clean except the `docs/tasks/` planning files.
- **PTIMER-165 / PTIMER-180 included?** Yes. `origin/main` carries PTIMER-165
  (custom table input + inspection-only fitted-formula preview, merged as #13)
  and PTIMER-180 (Create-Formula-from-table flow + `referenceTableFilmID` link +
  `CustomFilmReferenceTableResolver`, merged as #14). The resolver file is
  present at HEAD.
- **PTIMER-188 unrelated behavior present?** No. There is no PTIMER-188 commit
  in `origin/main`, and the `startAgain` symbols found in the workspace files
  belong to the pre-existing PTIMER-36 "start a new timer from a completed
  exposure" feature (introduced by commit `5edda86`), not to PTIMER-188. The
  parent repository directory happens to be checked out on a branch named
  `feature/PTIMER-188-...`, but the PTIMER-146 worktree is on its own branch at
  `origin/main` and contains no PTIMER-188 changes.
- **Base correction needed?** No. The base is clean: it includes PTIMER-165/180
  and excludes PTIMER-188. (An earlier planning turn observed `origin/main` at
  `b309a25` with HEAD ahead by the PTIMER-180 commits; the older observation and
  the current source no longer match because `origin/main` has since advanced to
  include #14. Current source is authoritative.) **Recommendation:** keep this
  base; should the PTIMER-146 implementation branch ever need re-cutting, cut it
  from `origin/main` at `0078b80` (or later, provided no unrelated PTIMER-188
  work has landed) and preserve the `docs/tasks/` documents.

---

## 3. Superseded documents

This document **supersedes Round 2 (`PTIMER-146-round2.md`) and Round 2-1
(`PTIMER-146-round2-1.md`) for Round 3 review.** Those two, plus Round 1-1
(`PTIMER-146-round1-1.md`), are retained as **process history**: Round 1-1
established the accepted scope principle and the pure-`:core` architecture
decision; Round 2 produced the first file/type/test design (pre-165 scope);
Round 2-1 expanded scope to completed PTIMER-165 behavior. Where this accepted
baseline and an earlier document differ, **this document and current source
govern.**

---

## 4. Accepted scope principle

PTIMER-146 aims for **functional parity with current completed iOS shooting-mode
behavior.** A function is not excluded merely because it adds work. **Defer only
for:** (a) Android UI/UX polish requiring human tuning; (b) platform-specific
polish such as home-screen-widget visual design; (c) functionality blocked by a
real Android technical limitation; (d) functionality explicitly out of product
scope. UI/UX polish may be deferred; the underlying function is included where
practical.

---

## 5. Accepted Must scope

All current iOS shooting-mode functions, unless a real technical blocker applies:

**Calculation & catalog (`:core`)**
- Exposure calculation; 55-entry base-shutter ladder; ND integer stop behavior
  (`0..30`); shutter/duration formatting (locale-independent).
- Film catalog/profile loading + validation — **37 films** (20 formula, 11
  table-interpolation, 6 threshold+limited-guidance; manufacturer counts
  ILFORD/HARMAN 12, Kodak 9, Fujifilm 4, FOMA 3, Rollei 7, ADOX 2).
- Reciprocity **formula** calculation; reciprocity **table interpolation**
  (log-log; required for the 11 official table films); threshold / limited-
  guidance / unsupported behavior; confidence-presentation semantics +
  constrained vocabulary.
- **Preset alternate-model selection** (`AlternateReciprocityModels`) +
  `selectedModelLabel`.

**Shooting workflow**
- Film selection / clear (No-film = digital).
- Digital adjusted-shutter result; film adjusted + corrected-exposure result;
  Start-Timer from a valid result (enablement rule: limited-guidance/unsupported
  blocks the corrected timer with a hint; quantified positive-finite enables).
- **Target Shutter** functional behavior (per-slot target + stop-difference
  comparison vs adjusted/corrected; no fabrication when non-quantified).

**Timers**
- Start / pause / resume / complete / remove; multiple timers; completed
  ordering/history; **Start Again** (clone of a completed timer, as in current
  iOS source — PTIMER-36).
- **Immutable timer identity capture** at start (slot id + label, film
  descriptor, exposure source, `selectedModelLabel`, custom-profile descriptor
  e.g. "Custom table · N anchors" / "Custom formula").

**Camera slots**
- Camera slots (2–4; ship 4); **rename**; per-slot calculator / film+profile /
  target-shutter / selected-model state; capture-on-switch + restore-on-return.

**Custom film library (PTIMER-165 + PTIMER-180)**
- Custom film library (create / edit / delete / select / persist / restore).
- Custom **formula** profile authoring (validation, no-shortening guard).
- Custom **table** profile authoring; **table anchors** (≥2, strictly-ascending
  unique Tm, Tc ≥ Tm, no-correction strictly below first anchor, source range
  derived = last anchor; display-only evidence rows).
- **Fitted-formula preview/generation as inspection-only** (matches current iOS
  source: a saved table always calculates by log-log; the fit is preview only).
- **Create-Formula-from-table flow** (present in current source): seed a
  separate `.formula` custom film from a table's fit, linked by
  **`referenceTableFilmID`** (display-only); `CustomFilmReferenceTableResolver`
  re-hydrates the linked table's current anchors for reference/error columns and
  graph markers.
- Custom-profile persistence / restore (incl. `referenceTableFilmID`).

**Transparency & platform**
- **Reciprocity Details** source/model/calculation transparency (model picker;
  custom source/calc rows; fitted comparison block; linked-formula
  reference/error columns).
- **Android timer-completion notification.**
- **Android ongoing running-timer notification** (foreground service) as the
  Live-Activity equivalent, where technically reasonable.
- **Persistence / restore for all included state** (timers, per-slot
  calculator/film/target/selected-model, camera-slot session, custom film
  library).
- **Android unit / ViewModel / relevant UI smoke tests** for the above.

**Note — no per-profile runtime "table vs fitted" toggle exists.** In current iOS
source a custom profile holds exactly one rule (formula XOR table), fixed at
creation. The user-facing equivalent of "use a formula derived from my table" is
the Create-Formula-from-table flow above, which is included.

---

## 6. Deferred scope (with reasons)

| Deferred item | Reason |
|---|---|
| Base-shutter / ND / Target-Shutter picker feel & wheel tuning | UI/UX polish needing human interaction tuning |
| Reciprocity Details **graph** visual fidelity (curve/markers) | Visual polish; a basic graph or tabular curve summary gives MVP transparency |
| Custom-film editor layout / token-tap formula feel / keyboard ergonomics / reference-error column styling | UI/UX polish |
| Bottom-sheet two-detent drag choreography, density tiers, slot-pager animation, badge styling | UI/UX polish |
| Android home-screen widget | Platform-specific visual design + human testing; ongoing notification covers MVP monitoring |
| Guaranteed exact background delivery across Doze / OEM battery policies | Real platform limitation not fully controllable; best-effort scheduling is included |
| Notification action buttons (pause/resume) | Included only if low-cost; otherwise deferred (function-light) — owner Q3 |
| iOS ActivityKit / Live Activity specifics, RecordReplay traces, exact iOS layout metrics | iOS-platform-only; replaced functionally by the Android notification plan |
| PTIMER-188 "start again active timers" | Not present in source baseline; out of scope |

No custom-profile *function* is deferred.

---

## 7. Android architecture baseline

- **Pure-Kotlin `:core` module** (`org.jetbrains.kotlin.jvm` + serialization
  plugin), no Android dependency on the classpath — mechanical enforcement of
  the "no framework in domain" boundary (iOS `PTimerCore` analogue). Owns:
  exposure, reciprocity (formula + table evaluator + fitter + guard + duration
  parser + reference-table resolver + alternate-model registry + confidence
  presentation), catalog loader/validation (+ bundled `LaunchPresetFilmCatalog.json`
  resource), timer state machine + runtime, persistence schemas + `*Store`
  interfaces.
- **No version catalog for PTIMER-146** — two modules sharing a small dependency
  set; inline versions; revisit if module count grows.
- **Minimal dependencies:** `:core` → kotlinx-serialization-json (+ junit test);
  `:app` → `:core`, kotlinx-coroutines-android, lifecycle-viewmodel-compose /
  lifecycle-runtime-compose, androidx.datastore (typed), coroutines-test (test),
  Compose ui-test (androidTest).
- **`:app` owns** ViewModel (`ShootingViewModel`), Compose UI, DataStore
  persistence implementations, the timer coordinator
  (`AndroidTimerCoordinator`), and notifications/foreground service.
- **One-way UI event flow:** UI emits `onEvent(ShootingIntent)` (sealed); the
  ViewModel mutates single-owner feature-state holders and recomputes an
  immutable `ShootingUiState` exposed via `StateFlow`. Composables never mutate
  domain state.
- **Persistence boundary:** typed `DataStore<T>` (kotlinx.serialization JSON)
  behind `:core` `*Store` interfaces. Greenfield — no iOS legacy migration.
- **Timer tick ownership:** the state machine (`TimerRuntime`, `tick(now)`)
  lives in `:core`; the wall-clock tick loop (~100 ms while any timer runs) is
  owned by `AndroidTimerCoordinator`. Composables never tick.
- **Notification / foreground service:** completion notification +
  `AlarmManager` background delivery; an ongoing foreground-service notification
  for the representative running timer (earliest completion, stable tiebreak,
  named with `selectedModelLabel`). See §10 Slice 10 and the deferral of exact
  OEM background guarantees.

---

## 8. File/type design summary (merged)

**`:core` packages**
- `core.exposure` — `ExposureCalculator` (`calculate`, `parseBaseShutter`,
  `formatShutter`, `formatTimeDisplay`, `formatExtendedClock`, snap gated on
  full-stop scale **and** whole-stop ND; `STABILITY_EPSILON = 1e-6`),
  `ExposureScale`/`ExposureScaleMode`, `NdStep`/`ShutterStep`,
  `CalculatorDefaults`, `ExposureCalcError`, formatters. (Exact parity.)
- `core.reciprocity` — `@Serializable` domain (`FilmIdentity`,
  `ReciprocityProfile`, `sealed ReciprocityRule {Threshold, Formula,
  LimitedGuidance, TableInterpolation}`, provenance, adjustments,
  `UserEditableMetadata` incl. optional `referenceTableFilmID`),
  `ReciprocityFormula.evaluate`, `TableInterpolationRule.evaluate` (log-log),
  `ReciprocityPolicyEvaluator` (order formula→table→threshold→limited→
  unsupported), `ReciprocityResult` sealed + metadata (`CalculationBasis`
  5-case incl. `TABLE_LOG_LOG_DERIVED`), `ReciprocityConfidencePresentationMapper`,
  `ReciprocityFormulaFitter` (OLS `Tc=a·Tm^p`), `CustomFilmFormulaGuard`
  (analytic `Tc(t) ≥ t − 1e-6`), `CustomFilmDurationParser`,
  `CustomFilmReferenceTableResolver` (`Resolution{anchors, isLinkedButMissing}`;
  display-only), `AlternateReciprocityModels`. (Protected items: exact parity.)
- `core.catalog` — `LaunchPresetFilmCatalogLoader` + `CatalogLoadError`; bundled
  JSON resource.
- `core.timer` — `sealed TimerState {Running, Paused, Completed}`
  (`TIMER_STABILITY_EPSILON = 1e-6`), `TimerRuntime`, `TimerManaging`,
  `ExposureTimerIdentitySnapshot` (+ `ExposureTimerSource`, `selectedModelLabel`),
  `TimerWorkspaceOrdering`.
- `core.persistence` — `PersistentTimerCollectionSnapshot` /
  `PersistentTimerSnapshot`, `PersistentCameraSlotSessionSnapshot` (+ per-slot),
  `PersistentCustomFilmLibrarySnapshot` (`schemaVersion=1`, films incl.
  `referenceTableFilmID`); `*Store` interfaces + `NoOp*`.

**`:app` packages**
- `app.vm` — `ShootingViewModel`, `ShootingUiState`, `ShootingIntent` (sealed).
- `app.state` — single-owner holders: `CalculatorState`, `FilmSelectionState`,
  `CameraSlotSessionState`, `TimerWorkspaceState`, `TargetShutterState` /
  `TargetShutterInputState`, `CustomFilmLibraryState`, `CustomFilmEditorState`
  (kind switch, table rows, formula tokens, live preview, validation,
  create-formula-from-table seeding, reference-table resolution).
- `app.presenter` — `AuthorityLabelPresenter`, `ResultRowPresenter`,
  `StartEnablementPolicy`, `ReciprocityModelMetadataPresenter`,
  `CustomTableFittedFormulaPresenter` (inspection-only),
  `ReciprocityDetailsPresenter`, `TargetShutterPresenter`,
  `TimerStartComposer`, `TimerCardIdentityPresenter`.
- `app.timer` — `AndroidTimerCoordinator` (coroutine tick, injectable clock).
- `app.persistence` — `DataStoreTimerStore`, `DataStoreSessionStore`,
  `DataStoreCustomFilmStore`.
- `app.notifications` — `TimerCompletionNotifier`,
  `RunningTimerForegroundService`, representative-timer selector.
- `app.ui` — `ShootingScreen`, `SlotPager`/`SlotRenameDialog`,
  `BaseShutterPicker`, `NdPicker`, `FilmRow`/`FilmPickerSheet`, `ResultRows`,
  `StartTimerButton`, `TimerList`/`TimerCard`, `DetailsSheet`,
  `CustomFilmEditor*`, `TargetShutter*`.

**Type-mapping principle:** protected/domain types (exposure calc + snap,
reciprocity formula + table + policy order + confidence mapping, fitter, guard,
resolver, timer state machine, persistence schemas) require **exact parity**;
app state/presenter/UI types require **behavior parity**. (Full row-level tables
in Round 2 §3 and Round 2-1 §5.)

---

## 9. Test strategy

**iOS tests are used as behavior-audit sources — protected behavior, inputs,
expected invariants — not mechanically translated.** Required Android test
groups:

- **Fixture-driven** — `exposure-golden.json` (calc/error/format/time-display);
  `catalog-validation-cases.json` (count, manufacturer counts, ids/order,
  formula per-film params, threshold ranges, rejection cases, vocabulary
  rule-12). Android asserts the catalog's three real profile shapes (see §12 Q2).
- **`:core` parity** — exposure (calc/snap/ladder/format), reciprocity (policy
  order, formula evaluate, log-log table, confidence mapping), fitter (OLS
  recovery + rejections), formula guard, reference-table resolver
  (linked/unlinked/linked-but-missing), catalog calculation goldens for the 11
  table films + sample formula films, timer state machine + restore.
- **ViewModel** — calculator+film integration, Start enablement
  (limited/beyond/digital), alternate-model selection + `selectedModelLabel`,
  multi-timer lifecycle (tick/reconcile/exactly-once/ordering), immutable
  identity capture, Start-Again clone.
- **Persistence** — timer round-trip + restore (auto-complete, paused-freeze,
  corrupt→completed, legacy `stopped`), slot-session round-trip (4 slots, two
  reloads, future schema ignored, rename), custom-film library round-trip incl.
  `referenceTableFilmID`, corrupt-payload fail-safe.
- **Custom film** — table-form validation, fitted presenter
  (quality/unavailable, never active), create-formula-from-table (separate
  linked film, kind fixed), library CRUD + sanitation + reload, calc reads rule
  anchors not evidence, `UserEditableMetadata` codable (additive optional).
- **Timer / notification** — completion exactly-once, cancel-on-pause,
  reschedule-on-resume, representative selection, foreground-service lifecycle.
- **Camera slot** — per-slot independence, capture/restore, rename isolation +
  immutability on started timers.
- **Target Shutter** — comparison (adjusted/corrected), match "0 stops", nil
  when non-quantified, per-slot isolation, `lastUsed` persistence.
- **Details / presenter** — model/source/calc rows, model picker, fitted
  comparison, linked-formula reference/error columns, vocabulary gate.
- **UI smoke** (Compose) — minimal: shooting flow renders, start/pause/remove a
  timer, slot switch, open film picker/details. (androidTest; kept light.)

---

## 10. Implementation slices (accepted order)

Each slice ends green and reviewable. Self-review checklist applies to every
slice: `:core` has no Android dependency; calc/domain out of Composables;
ViewModel exposes immutable state; one-way intents; persistence behind
interfaces; explicit parse errors; ticks owned by coordinator/runtime;
protected-area parity; fitted formula + reference-table link stay display-only;
no iOS change; no unrelated cleanup; single-owner state holders don't reference
each other.

1. **Gradle/module.** Goal: pure `:core` + minimal deps. Result: both modules
   build; app shows placeholder. Tests: `:core` smoke. Stop: `:core:test
   assembleDebug` green. Checkpoint: `:core` classpath has no Android.
2. **Exposure core.** Goal: port calc + formatters. Result/Tests: exposure
   fixtures + snap/ladder/format. Stop: fixtures green; epsilon 1e-6. Checkpoint:
   locale-independent formatting.
3. **Reciprocity core + catalog + fitter + guard + resolver.** Goal: port
   domain, evaluators, fitter, guard, duration parser, reference-table resolver,
   alternate-model registry, confidence mapping, loader/validation + JSON.
   Result/Tests: §9 `:core` reciprocity + catalog + table-calc goldens. Stop:
   green; vocabulary gate green. Checkpoint: fitter/resolver pure + display-only;
   5-case basis enum; catalog's three real shapes asserted.
4. **Timer state/runtime/snapshot core.** Goal: state machine + runtime +
   snapshot (+ `selectedModelLabel`/custom descriptor on identity). Result/Tests:
   transitions + restore + ordering + identity. Stop: green. Checkpoint:
   `paused→completed` only via resume; duration never zeroed.
5. **Coordinator + ViewModel + persistence + timers UI (first runnable app).**
   Goal: multi-timer lifecycle + relaunch restore + Start-Again clone. Tests:
   ViewModel/coordinator (virtual time) + DataStore timer round-trip + manual.
   Stop: lifecycle + restore green in tests and on device. Checkpoint:
   Composables don't tick; one-way intents.
6. **Calculator + film selection + alternate-model selection.** Goal: shooting
   calculation surface for the active slot; preset model picker;
   `selectedModelLabel` capture; custom group placeholder. Tests: calc+film
   integration, Start enablement, alternate-model + label, presenters. Stop:
   workflow + model selection green. Checkpoint: no fabricated numbers for
   non-quantified.
7. **Camera slots + rename.** Goal: multi-slot per-slot state + rename +
   per-slot `selectedProfileId`/`targetShutterSeconds` persistence + immutable
   identity. Tests: slot independence, rename isolation, session round-trip,
   identity capture. Stop: multi-slot + identity + persistence green. **MVP
   shooting feature-complete here (pre-custom).**
8. **Custom film library + custom formula + custom table + fitted preview +
   Create-Formula-from-table + persistence + custom Details.** Goal: full
   custom-profile authoring incl. inspection-only fitted preview and the
   table→formula create flow with reference/error columns. Result: create custom
   formula + table profiles; fitted preview (params + per-anchor comparison +
   quality/unavailable); Create Formula from a saved table → separate linked
   formula film; select for shooting; persists across relaunch; a saved table
   always calculates by log-log. Tests: §9 custom-film group incl. create-formula
   + resolver + codable. Stop: authoring + calc + create-formula + persistence +
   preview green. Checkpoint: fitted formula + reference-table link never affect
   the active calculation; single-rule invariant enforced at load.
9. **Target Shutter.** Goal: per-slot target + comparison. Result: set target;
   stop-difference vs adjusted (digital)/corrected (film); per-slot isolation;
   survives relaunch. Tests: §9 Target Shutter. Stop: comparison + persistence
   green. Checkpoint: no fabrication when non-quantified.
10. **Reciprocity Details (functional transparency) + notifications.** Goal:
    Details source/model/calc incl. picker, custom rows, fitted comparison,
    linked-formula reference/error (graph fidelity deferred); completion
    notification + ongoing running-timer foreground-service notification. Tests:
    Details presenters; notification rule + representative selection; manual
    background check. Stop: Details functional green; notification rules green;
    ongoing notification works in foreground. Checkpoint: vocabulary gate;
    exactly-once; cancel-on-pause; clears correctly; exact OEM background
    delivery explicitly deferred.

---

## 11. Round 3 readiness checklist

Round 3 must verify, before implementation starts:
- Base remains clean: `HEAD == origin/main`, includes 165/180, excludes 188.
- Accepted architecture confirmed (pure `:core`; no version catalog; minimal
  deps; `:app` owns VM/Compose/DataStore/coordinator/notifications; one-way
  events; persistence boundary; tick ownership; notification/foreground-service
  approach).
- Accepted Must scope (§5) and deferrals (§6) confirmed.
- Test groups (§9) mapped to fixtures/iOS behaviors with per-slice
  "required-before-done" flags; parity oracle (`shared/test-fixtures/`) wiring
  agreed.
- Slice order (§10) and stop conditions agreed.
- The four owner decisions (§12) closed.
- Confirmed: no implementation, no production source changes, no commits during
  planning.

---

## 12. Remaining owner decisions

1. **Base alignment** — confirm PTIMER-146 targets `origin/main` at `0078b80`
   (includes 165/180, excludes 188). **Assumption: yes** (verified clean).
2. **Catalog shape validation** — confirm Android validates against the
   catalog's three real profile shapes (formula / tableInterpolation /
   threshold+limited-guidance) and does not enforce the document's two-shape
   `rule-11`. Current source and the fixture's `rule-11` / `perFilmExpectations`
   do not match (the fixture omits the 11 table films); reconciling the iOS
   fixture is an iOS-side concern, out of 146.
3. **Notification actions** — pause/resume action buttons on the ongoing
   notification in 146, or notification-only with actions deferred?
   **Assumption: include only if low-cost, else defer the buttons (not the
   notification).**
4. **Persistence consolidation** — confirm the greenfield decision to fold timer
   runtime + display/identity metadata into one `PersistentTimerCollectionSnapshot`
   and the calculator context into the slot-session snapshot, with a separate
   custom-film library store. **Assumption: yes.**

Android platform limits already characterized (not open questions): exact
background delivery across Doze/OEM battery is best-effort with a stated reason;
home-screen widget deferred as visual-design work.

---

## 13. Final recommendation

**Proceed to Round 3 readiness review.** The base is clean and current, scope is
at functional parity with completed iOS behavior (165/180 included, 188
excluded), and the architecture, tests, and slices are concrete. Close owner
decisions Q1–Q4 in Round 3 and confirm the parity-oracle wiring; no further
planning correction is required. No implementation until Round 3 is accepted.

---

*End of accepted Round 2 baseline. Planning only — not implementation approval.*
