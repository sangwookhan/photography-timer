# PTIMER-146 — Android MVP Plan, Round 2-1 (include completed PTIMER-165)

> **Status:** Planning only. Round 2-1 revises Round 2
> (`docs/tasks/PTIMER-146-round2.md`) and the accepted baseline Round 1-1
> (`docs/tasks/PTIMER-146-round1-1.md`) to target **current completed iOS
> shooting behavior, including PTIMER-165**. Not implementation approval. No
> production source changed (this document only), no commits, no Jira, no
> tickets.

**Revised scope principle (owner directive):** aim for **functional parity**
with current iOS shooting behavior. Do not drop a function merely because it is
more work. Defer/exclude only for: a real Android platform limitation; MVP-level
implementation risk that is too high; a feature that depends on platform UI/UX
tuning a human must test; or something explicitly out of product scope. **UI/UX
polish may be deferred; underlying function should be included where practical.**

---

## 0. What I verified in current source this round

This revision was prepared in the `PTIMER-146-android-mvp` worktree, whose base
is `0078b80`. Verified relationship: **`0078b80` = `origin/main` plus the
custom-table→formula work** (commits `25733eb` "Add reference-table link to
custom film metadata", `fdaab7b` "Seed and resolve formulas from a custom
table", `4bf518a` "Wire Create Custom Formula flow into editor UI", `19d1b06`
"Realign specs for custom table-to-formula flow", `0078b80` "Create an editable
custom formula from a saved custom table (#14)"); `origin/main` is an ancestor
of HEAD. So the current source carries more custom-profile behavior than the
`b309a25` state an earlier draft of this document was written against.

Findings grounded in the current source + tests:

- **Completed PTIMER-165 = custom reciprocity *table input* + *fitted-formula
  generation/preview*.** A custom profile holds **exactly one rule — formula
  XOR table interpolation** (`enum CustomFilmCalculationInputKind { case
  formula; case table }`), fixed at creation; Edit opens with the saved kind
  fixed. `CustomFilmLibrary.isWellFormedCustomFilm` enforces a single rule at
  load.
- **There is no runtime "table vs fitted calculation selection" on a single
  saved profile.** A saved custom **table** profile always calculates by
  log-log interpolation. The fitted formula is **inspection-only**
  (`CustomTableFittedFormulaPresenter`: `FittedFormula`, per-anchor
  `ComparisonRow` with `percentError`/`stopError`, `FitQuality {good,
  borderline, poor}`, `Unavailable` guidance) and never becomes the active
  shooting calculation. The directive's "choosing table vs fitted calculation
  if that exists in completed 165" therefore maps to the flow below, not to a
  per-profile toggle.
- **Create-Formula-from-table is present in the current source** (it was not
  present in the older `b309a25` state an earlier draft referenced — current
  source and that earlier draft do not match). The flow:
  `CustomFilmEditorFormState.creatingFormula(fromTable:)` fits a table's anchors
  and seeds a **separate, new** `.formula`-kind custom film, linked back to the
  table by the additive optional `UserEditableMetadata.referenceTableFilmID`.
  The link is **display-only** — the calculation policy never reads it; the
  formula computes only from its own parameters; the table is never converted.
  `CustomFilmReferenceTableResolver.resolve(for:lookup:)` re-hydrates the linked
  table's **current** anchors so the formula editor's graph markers and the
  Calculation-Basis Reference / Error columns reappear on edit; an unresolved
  link yields `isLinkedButMissing = true` ("reference table unavailable").
- **Preset alternate-model selection exists in current shooting behavior.**
  `AlternateReciprocityModels` is a hardcoded registry keyed by preset film id
  (e.g. `kodak-portra-400`, `foma-fomapan-100`, `kodak-tri-x-400`,
  `kodak-tmax-100`, `adox-chs-100-ii`); for those presets the user can pick
  among >1 calculation model in Details, and the chosen model's label is
  captured on the timer (`selectedModelLabel`, used in lock-screen naming).
  Custom films carry no alternates.
- **Target Shutter** is a per-camera-slot optional comparison target
  (`TargetShutterModel.targetSeconds/isActive`,
  `TargetShutterPresenter.ComparisonSource {adjustedShutter, correctedExposure,
  unavailable}`); independent of profiles/custom films.
- **Catalog facts unchanged** (verified): **37 films** (20 formula, 11
  table-interpolation, 6 threshold+limited-guidance); manufacturer counts
  ILFORD/HARMAN 12, Kodak 9, Fujifilm 4, FOMA 3, Rollei 7, ADOX 2.
  `TableInterpolationModel` is required for catalog calculation (11 official
  table films) — independent of any custom-table work.
- **Where current source and a document do not match:** the fixture
  `catalog-validation-cases.json` `rule-11` lists only two profile shapes and
  its `perFilmExpectations` (34 entries) contain no `tableInterpolation`
  entries, while the catalog JSON contains 11 table films and the iOS loader
  accepts a table-interpolation shape. Android asserts the catalog's three real
  shapes; reconciling the iOS fixture/document is an iOS-side concern, out of
  146 (owner Q2).

---

## 1. Verdict

**Yes — PTIMER-146 can still deliver a working Android MVP with completed
PTIMER-165 behavior (and the now-present table→formula flow) included.** It is a
materially larger MVP than Round 2's, but every newly included function is
either pure domain logic that ports directly (the fitter, table evaluator,
custom-profile validation, formula guard, reference-table resolver — all
Foundation-only / platform-neutral on iOS) or sits behind the protocol seams
already planned. The only genuinely new *platform* risk is reliable background
timer notification (the Android equivalent of the iOS Live Activity); that risk
is contained by including a foreground-service + notification approach
functionally while deferring exact-background-delivery edge cases with a stated
technical reason (§8). UI/UX polish (editor feel, graph fidelity, picker
interaction, widget) is deferred; function is included.

---

## 2. Scope changes from Round 2

### 2.1 Newly included functional scope (PTIMER-165 complete + parity principle)
- **Custom film library** — create / edit / delete / persist / select / restore
  custom films (both kinds below).
- **Custom *formula* profile authoring** (was deferred in Round 1-1/2): editor
  form state, validation, no-shortening guard.
- **Custom *table* profile authoring**: table anchor rows, validation (≥2
  anchors, strictly-ascending unique Tm, Tc ≥ Tm, no-correction strictly below
  first anchor, source range derived = last anchor), display-only evidence rows.
- **Fitted-formula generation + inspection-only preview**: OLS power-law fitter
  + comparison/quality/unavailable presenter. Preview only — never the active
  calculation.
- **Create-Formula-from-table flow** (present in current source): seed a new,
  separate `.formula` custom film from a table's fitted formula, linked by
  `referenceTableFilmID`; re-hydrate the linked table's anchors for the formula
  editor's reference/error columns and graph markers (display-only).
- **Custom-profile persistence** (`PersistentCustomFilmLibrarySnapshot`,
  including the additive `referenceTableFilmID`) + restore.
- **Custom-profile Details presentation** (source = "Custom (user-defined)",
  calculation = "Log-log table interpolation" / "Custom formula"; per-anchor
  fitted comparison block; reference/error columns for a linked formula; range
  lines).
- **Preset alternate-model selection** (model picker for presets with
  alternates) + `selectedModelLabel` capture on timers.
- **Target Shutter** (per-slot target + stop-difference comparison) — functional;
  picker feel deferred.
- **Android timer-completion notification** + **ongoing running-timer
  notification (foreground service)** as the Live Activity equivalent (§8).

### 2.2 Still-deferred UI/UX polish (function included; polish later)
- Custom-film editor visual/interaction polish (token-tap formula feel, keyboard
  ergonomics, row affordances, reference/error column styling).
- Reciprocity Details **graph** visual fidelity (curve sampling/markers) — a
  basic graph or tabular curve summary suffices for MVP transparency.
- Target Shutter picker feel (Quick / Fine-Tune wheel ergonomics).
- Film-picker grouping styling, slot pager animation, density tiers,
  bottom-sheet drag choreography, badge styling.

### 2.3 Platform-specific Android replacement work (new)
- iOS **Live Activity / lock-screen representative timer** → Android **ongoing
  (foreground-service) notification** for the representative running timer
  (earliest completion, stable tiebreak), updated ~1 s, named with
  `selectedModelLabel` — §8.
- iOS **local completion notification** → Android completion notification via
  the coordinator + NotificationManager + scheduled background delivery.

### 2.4 Truly excluded (with technical reason)
- **Android home-screen widget** — depends on platform-specific UX design and
  human visual testing (Glance/RemoteViews layout, update budget); UI/UX-tuning
  work, not core function. The ongoing notification covers "monitor a running
  timer outside the app" for MVP (§8).
- **Exact-alarm guaranteed background delivery across Doze / OEM battery
  policies** — real platform limitation requiring device-specific testing;
  best-effort scheduling included, hard guarantees deferred (§8).
- *(No custom-profile feature is excluded.* The earlier draft excluded the
  table→formula flow as a separate not-yet-merged ticket; on the current source
  it is present and is now in functional scope.)*

---

## 3. Updated Must scope

All current iOS shooting-mode functions, unless a technical blocker applies:

- Pure-Kotlin `:core`; exposure calc; 55-entry base ladder; ND `0..30`;
  shutter/duration formatting.
- Catalog/profile loading + validation (37 films) including the **table
  evaluator** for the 11 official table films.
- Reciprocity calculation (formula + table + threshold + limited-guidance) +
  confidence-presentation semantics + constrained vocabulary.
- **Preset alternate-model selection** + `selectedModelLabel`.
- Film selection / clear (No-film = digital).
- Digital adjusted-shutter result; film adjusted + corrected result; start-from-
  valid-result with the enablement rule.
- Timer runtime start/pause/resume/complete/remove; multiple timers; completed
  ordering; "start again" of a completed timer (clone).
- **Camera slots with per-slot calculator/film/target state + rename + immutable
  timer-identity capture** (identity incl. slot label, film descriptor, exposure
  source, `selectedModelLabel`, and for custom profiles "Custom table · N
  anchors" / "Custom formula").
- **Target Shutter** (per-slot target + comparison).
- **Custom film library**: custom **formula** + custom **table** authoring,
  validation, no-shortening guard; **fitted-formula inspection preview**;
  **Create-Formula-from-table** + reference-table link/resolution; selection for
  shooting; persistence + restore.
- **Reciprocity Details** with functional source/model/calculation transparency
  (model picker, custom-profile source/calc rows, fitted comparison block,
  linked-formula reference/error columns); graph fidelity deferred.
- **Timer notifications**: completion notification; ongoing running-timer
  notification (foreground service) as the Live Activity equivalent.
- Persistence/restore for **all** included state (timers, per-slot
  calculator/film/target/selected-model, camera-slot session, custom film
  library incl. `referenceTableFilmID`).
- Android unit/ViewModel parity tests for all of the above.

**Reconsidered items, resolved:** Target Shutter → **included**; custom formula
profile → **included**; custom table profile → **included**; table anchors →
**included**; fitted preview/generation → **included (inspection-only)**; "table
vs fitted selection" → **no per-profile runtime toggle exists; the equivalent is
the Create-Formula-from-table flow, included**; Details source/model/calc →
**included**; timer identity / lock-screen naming → **included via ongoing
notification + `selectedModelLabel`**; notification → **included**, widget →
**deferred**; camera slots + rename → **included**; persistence/restore for all
included state → **included**.

---

## 4. Updated architecture impact

On top of Round 2:

- **`:core` additions.** OLS power-law fitter, `AlternateReciprocityModels`
  registry, `CustomFilmFormulaGuard` (analytic no-shortening) +
  `CustomFilmDurationParser`, custom-profile validation (table + formula), and
  **`CustomFilmReferenceTableResolver`** (resolve linked table anchors;
  display-only). All Foundation-only on iOS → pure Kotlin, no Android.
  `TableInterpolationRule` evaluator was already in `:core` (catalog need).
- **Reciprocity table/fitted model additions.** Fitter + comparison/quality
  inputs in `:core`; preview *presentation* (rows, labels, graph, reference/
  error columns) in `:app` presenters reusing shared graph/text logic.
- **Custom-profile schema additions.** `FilmIdentity(kind=custom)` with a single
  `ReciprocityProfile` (`.formula` or `.tableInterpolation`), `source.authority
  = userDefined`, display-only `sourceEvidence` regenerated from anchors, and
  the additive optional `UserEditableMetadata` fields (`customSourceType`,
  `customManufacturer`, `referenceURL`, **`referenceTableFilmID`**;
  decode-if-present so older payloads decode unchanged).
- **Persistence schema additions.** New `CustomFilmLibraryStore` →
  `PersistentCustomFilmLibrarySnapshot { schemaVersion=1, films:[FilmIdentity] }`
  (file `custom_films.json`). Per-slot snapshot gains `selectedProfileId`
  (already present) and `targetShutterSeconds`. Timer identity gains
  `selectedModelLabel` and a custom-profile descriptor.
- **ViewModel/state additions.** `CustomFilmLibraryState` + a
  `CustomFilmEditorState` machine (kind switch, table rows, formula tokens, live
  preview, validation, create-formula-from-table seeding, reference-table
  resolution); `TargetShutterState`; model-selection events; film-picker custom
  group + create affordance.
- **Compose UI additions.** Custom-film editor screen (formula mode + table
  mode with anchor rows + fitted-preview section + linked reference/error
  columns), Details model picker + custom/source/calc rows + fitted comparison
  block, Target Shutter input sheet + result row, film-picker custom group.
- **Tests added/expanded.** Fitter; table-form validation; fitted presenter
  (quality/unavailable); custom library CRUD + sanitation + reload; custom-table
  calc reads rule anchors (not evidence); create-formula-from-table seeding +
  separate film + link persistence; reference-table resolver (linked / unlinked
  / linked-but-missing); custom-profile persistence round-trip incl.
  `referenceTableFilmID`; Details vocabulary/identity; alternate-model selection
  + `selectedModelLabel`; Target Shutter comparison + per-slot isolation;
  notification rule; foreground-service lifecycle.
- **Risks introduced.** (1) Background notification reliability (platform); (2)
  larger surface → more parity tests; (3) custom-profile + alternate-model
  selection interacting with per-slot `selectedProfileId` restore; (4) keeping
  the fitted formula and the reference-table link strictly **display-only** —
  must mirror the iOS invariant and test that neither leaks into calculation.

---

## 5. Updated Kotlin type mapping (PTIMER-165 + table→formula + parity)

(Extends Round 2 §3; new/changed rows.)

| Swift / iOS type | Kotlin / Android type | Package | Notes | Exact parity? |
|---|---|---|---|---|
| `CustomFilmEditorFormState` | `class CustomFilmEditorState` | `app.state` | `calculationInputKind`, formula tokens, `tableRows`; `validate()`; `switching(toCalculationKind)`; `creatingFormula(fromTable)`. | Behavior parity |
| `CustomFilmCalculationInputKind` | `enum class CustomFilmCalculationInputKind { FORMULA, TABLE }` | `app.state` | default FORMULA; saved kind fixed on edit. | **Yes** |
| `CustomFilmTableAnchorRowInput` | `data class CustomFilmTableAnchorRow(id, meteredText, correctedText, isBlank)` | `app.state` | row input; soft cap 20; seed 2. | Behavior parity |
| `TableInterpolationReciprocityRule` | `data class TableInterpolationRule(...)` + `evaluate` | `core.reciprocity` | log-log; through-anchor exact; extrapolate; 10% tol; `max(c,m)`. | **Yes** |
| `ReciprocityFormulaFitter` (+ `PowerLawFit`, `UnavailableReason`) | `object ReciprocityFormulaFitter` + types | `core.reciprocity` | OLS `Tc=a·Tm^p`; deterministic, order-independent. | **Yes** |
| `CustomTableFittedFormulaPresenter` (+ `FittedFormula`, `ComparisonRow`, `FitQuality`, `Unavailable`) | `object CustomTableFittedFormulaPresenter` + types | `app.presenter` | inspection-only; `stopError=log2(fitted/source)`; quality 0.1/0.25; `isTwoAnchorExactFit`; never the active calc. | **Yes** (incl. inspection-only invariant) |
| `CustomFilmReferenceTableResolver` (+ `Resolution`) | `object CustomFilmReferenceTableResolver` + `data class Resolution(anchors, isLinkedButMissing)` | `core.reciprocity` | resolve linked table anchors via `lookup`; unlinked→empty/not-missing; unresolved→missing; **display-only, never calculation**. | **Yes** |
| `UserEditableMetadata.referenceTableFilmID` | `referenceTableFilmID: String?` on `UserEditableMetadata` | `core.reciprocity` | additive optional; decode-if-present; set only on created formula. | **Yes** (schema) |
| `CustomFilmFormulaGuard` | `object CustomFilmFormulaGuard` | `core.reciprocity` | analytic `Tc(t) ≥ t − 1e-6`; casework on exponent. | **Yes** |
| `CustomFilmDurationParser` | `object CustomFilmDurationParser` | `core.reciprocity` | `""→empty`, `"unlimited"→unlimited`, `s/m/h`→seconds. | **Yes** |
| `CustomFilmLibrary` | `class CustomFilmLibrary` | `app.state` | add/replace-by-id/remove; insertion order; rejects non-custom; sanitizes malformed/shortening/mixed-rule. | Behavior parity |
| `PersistentCustomFilmLibrarySnapshot` | `@Serializable data class PersistentCustomFilmLibrarySnapshot(schemaVersion=1, films)` | `core.persistence` | wrapper over `FilmIdentity`. | **Yes** (schema) |
| `AlternateReciprocityModels` | `object AlternateReciprocityModels` | `core.reciprocity` | preset-id-keyed registry; `[]` for custom. | **Yes** |
| `ReciprocityModelMetadataPresenter` + model-selection display states | `object ReciprocityModelMetadataPresenter` + `ModelSelectionUi`/`ModelOptionUi` | `app.presenter` | source/calc rows; picker when >1 model; custom labels. | Behavior parity |
| `selectedModelLabel` (timer metadata) | field on `ExposureTimerIdentitySnapshot` | `core.timer` | captured at start; ongoing-notification name. | **Yes** |
| `TargetShutterModel` / `TargetShutterPresenter` (+ `ComparisonSource`) / `TargetShutterInputState` | `TargetShutterState` / `object TargetShutterPresenter` + `enum ComparisonSource` / `TargetShutterInputState` | `app.state` / `app.presenter` | stop-difference; matchEpsilon=1/24; nil when non-quantified; per-slot; feel deferred. | Behavior parity |

---

## 6. Updated test behavior inventory (PTIMER-165 + table→formula + parity)

Additive to Round 2 §8; iOS tests used as behavior-audit sources.

| iOS test group / source | Protected behavior | Representative inputs | Expected result / invariant | Android test type | 146? |
|---|---|---|---|---|---|
| `ReciprocityFormulaFitterTests` | OLS recovers params; deterministic; order-independent; rejections | `2.0·Tm^1.4` @{1,100}; degenerate | exact recover; `.insufficient/.nonPositive/.degenerate` | `:core` JVM | **Required** |
| `CustomTableFittedFormulaPresenterTests` | inspection-only fit; per-anchor error; quality; unavailable | table anchors; shortening fit | power-law map; reads rule anchors not evidence; quality 0.1/0.25; never active calc | `:app` presenter | **Required** |
| `CustomFilmEditorTableFormStateTests` | table validation + build | ≥2 anchors; dup/shortening/partial/zero-nc | single `.tableInterpolation`; no-correction default `min(0.5, first/2)`; source range = last anchor; auto-sort; kind-switch seeding; edit round-trip | `:app` state | **Required** |
| `CustomFilmTableProfileFlowTests` | sanitation + table calc | malformed/mixed tables; saved table | drops bad shapes; snapshot round-trips table+evidence; calc reproduces anchors + log-log + extrapolation; reads rule anchors not evidence; identity "Custom table · N anchors" | `:app` + `:core` | **Required** |
| `CustomFilmCreateFormulaTests` (PTIMER-180, present on base) | seed formula from table; separate film; link persists | saved table | `creatingFormula(fromTable)` → `.formula` film, `referenceTableFilmID` set, label "<label> Formula"; saved formula NOT `.tableInterpolation`; edit round-trip preserves link + kind; `nil` for ineligible/preset/formula films | `:app` state + persistence | **Required** |
| reference-table resolver tests | linked / unlinked / linked-but-missing | formula film + library lookup | unlinked→empty,not-missing; resolved→current anchors; deleted/non-table→missing; recompute from current anchors | `:core` JVM | **Required** |
| `UserEditableMetadataCodableTests` (`referenceTableFilmID`) | additive optional round-trip | with/without key | round-trips; absent → nil | `:core` JVM | **Required** |
| `CustomFilmAnchoredFormulaTests` | anchored formula round-trip + calc | `Tc=Tc₀(Tm/Tm₀)^p+b` | round-trips; defaults 1/1/0; preview uses anchored math | `:app`/`:core` | **Required** |
| `CustomFilmLibraryTests`, `…ReloadTests` | CRUD + order + sanitation + reload | add/replace/remove; reload | insertion order; rejects non-custom; sanitizes; reload preserves fields | `:app` + persistence | **Required** |
| `PersistentCustomFilmLibraryTests` (app-hosted) | fail-safe store | malformed; cross-instance | empty on malformed (no crash); persists; distinct key | `:app` DataStore | **Required** (greenfield store) |
| `CustomFilmEditorFormState`/`…InlineValidation`/`…SaveDisabledReason`/`…PreviewPresenter` | formula validation + preview + no-shortening | b<0; low exponent; linear | `.formulaShortensExposure`; row status set; quiet untouched form | `:app` state/presenter | **Required** |
| alternate-model selection + `selectedModelLabel` | choose model for presets; label persists/clones | Portra/Fomapan/Tri-X | picker >1 model; label captured + persisted + cloned; legacy decode nil | `:app` ViewModel + persistence | **Required** |
| `…TargetShutterTests` | per-slot target + comparison | target vs adjusted/corrected; limited | stop-difference; "0 stops"; nil non-quantified; per-slot isolation; `lastUsed` survives | `:app` ViewModel | **Required** (feel deferred) |
| notification rule (`TimerManagerNotification/CompletionAlert`) | schedule-on-start; cancel-on-pause; exactly-once | start/pause/complete | one per completion; cancel on pause; reschedule on resume | `:app` coordinator/notifier | **Required** |
| representative selection (`LockScreenTimerCoordinatorTests`) | running-only, earliest end, stable tiebreak; name w/ model label | mixed timers | correct representative; clears when none | `:app` notifier/coordinator | **Required (functional)**; exact OEM background delivery **deferred** (§8) |
| `CalculatorTimerLockScreenTests` (ActivityKit) | iOS Live Activity content state | — | iOS-only | — | **Deferred** (iOS-only; replaced by §8) |
| Details graph sampler/marker tests | curve fidelity | — | visual | — | **Deferred** (polish; tabular/basic graph suffices) |

---

## 7. Updated implementation slices

Custom-profile/table/fitted/table→formula placed structurally: the **fitter +
guard + table evaluator + reference-table resolver live in `:core`** (Slices
2/3); **authoring/preview/create-formula/persistence** form a dedicated slice
after film-selection UI. Slices 0–6 as in Round 2 with noted additions; new
slices 7–10.

- **Slice 0 — Gradle/module.** (Round 2; add custom-films DataStore usage.) Stop:
  `:core:test assembleDebug` green.
- **Slice 1 — Exposure core.** (Unchanged.) Stop: exposure fixtures green.
- **Slice 2 — Reciprocity core + catalog + fitter + guard + resolver.** *Add:*
  port `ReciprocityFormulaFitter`, `CustomFilmFormulaGuard`,
  `CustomFilmDurationParser`, `AlternateReciprocityModels`,
  `CustomFilmReferenceTableResolver`, confidence mapping. Result/test: fitter
  recovers params; guard analytic checks; resolver linked/unlinked/missing;
  catalog + reciprocity + table-calc green. Checkpoint: fitter/resolver pure;
  resolver display-only. Stop: §6 Slice-2 tests green.
- **Slice 3 — Timer state/runtime/snapshot.** *Add:* `selectedModelLabel` +
  custom-profile descriptor on identity. Stop: transition + restore + identity
  green.
- **Slice 4 — Coordinator + VM + persistence + timers UI.** (Round 2; incl.
  start-again clone of completed.) Stop: multi-timer lifecycle + restore green.
- **Slice 5 — Calculator + film selection + alternate-model selection.** *Add:*
  model picker for presets with alternates; capture `selectedModelLabel`; custom
  group + create affordance placeholder. Stop: workflow + model selection green.
- **Slice 6 — Camera slots + rename.** *Add:* per-slot `selectedProfileId` +
  `targetShutterSeconds` persistence. Stop: multi-slot + identity + persistence
  green.
- **Slice 7 — Custom film library + custom formula + custom table + fitted
  preview + Create-Formula-from-table + persistence + custom Details.**
  - Goal: full custom-profile authoring incl. inspection-only fitted preview and
    the table→formula create flow with reference/error columns.
  - Result: user creates a custom **formula** and a custom **table** profile;
    sees validation + fitted preview (params + per-anchor comparison + quality/
    unavailable); from a saved table runs **Create Formula** → a separate linked
    formula film whose editor shows reference/error columns from the table's
    current anchors; saves; selects for shooting; persists across relaunch; a
    saved table always calculates by log-log.
  - Files: `app.state` (`CustomFilmLibraryState`, `CustomFilmEditorState`),
    `core.reciprocity` (ported fitter/guard/resolver), `core.persistence`
    (`PersistentCustomFilmLibrarySnapshot` incl. `referenceTableFilmID`),
    `app.persistence` (`DataStoreCustomFilmStore`), `app.ui.customfilm`,
    `app.presenter` (fitted + details presenters).
  - Tests: §6 custom-profile rows incl. create-formula + resolver + codable.
  - Checkpoint: fitted formula and reference-table link **never** affect the
    active calculation; single-rule invariant enforced at load; `:core` purity.
  - Stop: custom authoring + calc + create-formula + persistence + preview green.
- **Slice 8 — Target Shutter.** Goal: per-slot target + comparison. Result: set
  a target; stop-difference vs adjusted (digital) / corrected (film); per-slot
  isolation; survives relaunch. Files: `app.state`/`app.presenter`/`app.ui.target`
  + slot `targetShutterSeconds`. Tests: §6 Target Shutter. Checkpoint: no
  fabrication when non-quantified. Stop: comparison + persistence green.
- **Slice 9 — Reciprocity Details (functional transparency).** Goal:
  source/model/calculation incl. picker + custom rows + fitted comparison +
  linked-formula reference/error; graph deferred. Files:
  `app.presenter`/`app.ui.details`. Tests: §6 Details. Checkpoint: vocabulary
  gate; "Custom" never manufacturer. Stop: Details functional green.
- **Slice 10 — Android notification platform replacement.** Goal: completion +
  ongoing running-timer notification (foreground service) — §8. Files:
  `app.notifications`, `app.timer`, manifest (service + `POST_NOTIFICATIONS`).
  Tests: §6 notification + representative selection; manual background check.
  Checkpoint: exactly-once; cancel-on-pause; clears correctly. Stop:
  notification rules green; ongoing notification works in foreground; background
  edge-case tuning deferred (§8).

---

## 8. Android platform replacement plan (Live Activity / widget / lock-screen)

- **Completion notification — included.** On completion the coordinator emits an
  event; `TimerCompletionNotifier` posts one notification (exactly-once,
  cancel-on-pause, reschedule-on-resume). Background delivery via `AlarmManager`
  (`setExactAndAllowWhileIdle`) keyed by timer identity.
- **Running timer notification — included (Live Activity equivalent).** A
  **foreground service** holds an **ongoing notification** for the
  representative running timer (earliest expected completion, stable tiebreak —
  reuse iOS selection logic), updated ~1 s, titled with name + `selectedModelLabel`;
  runs while ≥1 timer runs, stops when none; also keeps the tick loop alive in
  background.
- **Foreground service — needed.** Background countdown + live notification on
  modern Android requires a foreground service + `POST_NOTIFICATIONS` (API 33+).
  Included.
- **Notification actions — proposed, partial.** Pause/Resume actions map to
  existing intents; include if low-cost, else defer the buttons (not the
  notification).
- **Android home-screen widget — deferred (technical reason).** Glance/RemoteViews
  layout + update budget need platform-specific design + human testing; UI/UX
  tuning, not core function. Ongoing notification covers MVP monitoring.
- **Exact background delivery across Doze / OEM battery — deferred (platform
  limitation).** Best-effort exact alarms included; guaranteed delivery on
  aggressive OEM managers needs device testing; follow-up.

---

## 9. Remaining risks and owner decisions

**Risks (real):**
1. **Background notification reliability** (Doze / exact-alarm permission / OEM) —
   mitigated by foreground service + best-effort exact alarms; hard guarantees
   deferred (§8).
2. **Larger parity surface** — more tests; mitigated by fixtures + the new logic
   being pure and platform-neutral on iOS.
3. **Fitted formula + reference-table link must stay display-only** — porting
   risk if either leaks into the active calculation; mitigated by mirroring the
   iOS invariants and explicit "never active" tests.
4. **Catalog/fixture shape mismatch** (rule-11 / perFilmExpectations vs the 11
   table films) — Android asserts the catalog's real shapes; iOS reconciliation
   out of 146.

**Owner decisions:**
- **Q1 — base alignment.** This worktree base `0078b80` is `origin/main` plus the
  table→formula work (`#14`), checked out on `feature/PTIMER-188-...`. Confirm
  146 should target this source (PTIMER-180 included). **Assumption: yes** (the
  directive says target current completed behavior; the flow is present in
  source). If 146 must instead target plain `origin/main`, the Create-Formula
  flow + `referenceTableFilmID` drop to follow-up.
- **Q2** — Confirm Android validates against the catalog's three real profile
  shapes and does not enforce the document's two-shape `rule-11`; the iOS
  fixture/document reconciliation is tracked separately (out of 146).
- **Q3** — Notification action buttons (pause/resume) in 146, or notification-only
  with actions deferred? **Assumption: include only if low-cost, else defer.**
- **Q4** — Confirm the greenfield persistence consolidation (timer
  runtime+metadata in one snapshot; calculator context inside the slot session;
  separate custom-film library store).

---

## 10. Round 3 readiness impact

**The plan can proceed to Round 3 after this revision.** No further planning
correction is required to begin Round 3 readiness review: scope is aligned to
current completed iOS behavior on the actual worktree base (including the
table→formula flow), the one genuinely-absent feature (per-profile runtime
table-vs-fitted selection) is documented as nonexistent and mapped to the real
Create-Formula flow, and platform-replacement work has a concrete proposal.
Round 3 should close Q1–Q4 and confirm the larger Must scope + the
notification/foreground-service approach. Until Round 3 is accepted: no
implementation, no production source changes, no commits.

---

*End of Round 2-1. Planning only — not implementation approval.*
