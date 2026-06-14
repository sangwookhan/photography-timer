# PTIMER-179 Requirements Analysis & Source Feasibility Review

> Audience: ChatGPT (input for product intent / UX direction /
> senior architecture decisions). Authored by Claude Code on
> 2026-06-13. Code claims are cited as `file:line`. This is a
> ticket-scoped reference artifact (disappears with the ticket).

## 1. Ticket summary

- **PTIMER-179** "Generate fitted formulas from custom table
  anchors" (Story, Epic `PTIMER-14` Reciprocity Data Management).
- Position: **slice 2 of 3 in the PTIMER-165 plan**
  - slice 1 `PTIMER-178` (create/use custom table profiles) —
    **done** (blocks cleared)
  - slice 2 `PTIMER-179` (← this) — generate & **inspect** a fitted
    formula from table anchors
  - slice 3 `PTIMER-180` (select table vs fitted-formula calc model)
    — 179 blocks it
- **User value**: generate an app-derived formula from custom table
  anchors and see how closely it matches the entered source table
  before judging suitability. **Not yet adopted as the active
  shooting calculation model (inspection-only).**

## 2. Bottom line (feasibility)

> **Very high.** Almost every building block 179 needs — the fitting
> math, the per-anchor comparison presentation, the fit-quality
> threshold policy, the non-shortening safety guard, the app-derived
> labeling infrastructure — already exists in code/docs, much of it
> directly reusable. **The only net-new core work is promoting a
> test-only fitting function into the runtime (PTimerCore)**, and
> that function is a closed-form OLS of ~12 lines.

## 3. Acceptance criteria → requirements decomposition

| AC | Class | Feasibility basis / reusable asset |
|---|---|---|
| Generate a fitted formula from a valid custom table | functional | fit math exists (§4.1); `TableAnchor` model exists |
| Generated output labeled "app-derived" | presentation | `isAppDerivedModel`, `modelBasis = manufacturerTable + guardedFormula`, confidence `.medium` mapping exist (§4.4) |
| Source anchors stay visibly distinct from fitted output | presentation | `sourceEvidence` (source-only) vs app comparison block separation already a documented contract (UI.md §5, ModelComparisonPresenter doc) |
| Show source-vs-fitted comparison per anchor | presentation | `ReciprocityModelComparisonPresenter` already builds metered/source/app/error(%, stop) table (§4.2) |
| Poor fits clearly marked (worst error, poor-fit warning) | presentation+policy | PTIMER-170 threshold policy (≤0.1 / ≤0.25 / >0.25 stop) + `worstAbsoluteStopError` helper exist (§4.3) |
| Fitted formula not presented as manufacturer/source evidence | policy | `.userDefined` authority, source-evidence separation contract exist |
| Existing custom table calc keeps using the table by default | policy | model selection/persistence is **180 scope**; 179 is inspection-only → no evaluator/calculator change |

## 4. Feasibility — asset-by-asset

### 4.1 Fitting math (★ the core net-new work)
- Free log-log least-squares fit `Tc = a·Tm^p` **already implemented
  but only in test code**:
  `AppDerivedFormulaEvaluationTests.swift:324 freeLogLogFit(anchors:)`
  — closed-form OLS, no dependencies, deterministic.
- The same function is locked to reproduce every shipped app-derived
  alternate constant from live catalog anchors
  (`AppDerivedFormulaEvaluationTests:213`). So **the math is already
  validated against the catalog**.
- **Work to do**: promote those ~12 lines into a pure `PTimerCore`
  function (e.g. `ReciprocityFormulaFitter`). Independent of
  snap-to-stop / `ExposureCalculator` / the evaluator → no protected
  area touched.

### 4.2 Per-anchor comparison presentation
- `ReciprocityModelComparisonPresenter.swift` already builds the
  `[Metered, Source, App, Error]` table and computes `percentDelta`
  and `stopDelta = log2(app/source)` (`:70-78`), with the
  "App-derived comparison" section title and disclaimer.
- Currently fires only for profiles with `sourceEvidence` + a formula
  rule. For 179 the input is **anchors (table) + the runtime-generated
  formula**, rendered through the same table.

### 4.3 Fit quality / poor-fit policy
- Thresholds are **already a documented decision** (PTIMER-170): worst
  absolute stop residual `≤0.1` shippable / `≤0.25` borderline /
  `>0.25` poor·unsafe.
- `worstAbsoluteStopError(coefficient:exponent:anchors:)` helper
  exists (`:339`). → directly drives "worst error + poor-fit
  warning".

### 4.4 Labeling / confidence infrastructure
- `AlternateReciprocityModels.isAppDerivedModel` (`:80`),
  `ReciprocityProfileModelBasis(sourceModel: .manufacturerTable,
  calculationModel: .guardedFormula)`, authority `.userDefined`,
  confidence formula=`.medium` (table=`.high`) mapping all exist.

### 4.5 Non-shortening safety guard
- `CustomFilmFormulaGuard.passesUsableRangeCheck` proves
  `Tc(Tm) ≥ Tm` across the whole range analytically (critical point
  included). → **can immediately judge whether a generated formula is
  safe (does not shorten exposure)**. A shortening fit is presented as
  an "unusable fit".

### 4.6 Editor surface
- `CustomFilmEditorPreviewPresenter` already renders Tm→Tc tables and
  a preview graph and carries `.tableApplied / .beyondSourceRange /
  .invalidFormulaResult` statuses. Natural home for the fitted-result
  inspection UI.

### 4.7 Deterministic derivation (no persistence)
- AC "Prefer deterministic derivation from anchors rather than
  storing redundant fitted state" + out-of-scope "Persisting model
  selection" → **the fit is a pure function of the anchors, so derive
  on demand; no new schema/migration**. Persistence contract
  (protected) untouched.

## 5. Protected areas / scope (confirmed avoidable)
- **Out of scope**: selecting the fitted formula as the active model
  (→180), persisting model selection, timer identity for fitted
  selection, stop-delta/multiplier input, community/shipped catalog
  changes, remote sync.
- **Protected (unchanged)**: `ExposureCalculator.calculate`/snap/
  `stabilityEpsilon`, `ReciprocityCalculationPolicyEvaluator` order &
  semantics, `ReciprocityConfidencePresentation` mapping,
  `TimerManager`, persistence/restore contracts. → 179 is
  **additive + inspection-only**, so all are avoidable.
- Specs currently lock this as explicit future scope:
  `Calculator.md:277`, `DomainSchema.md:383 / :405`. → **starting 179
  requires updating those paragraphs to "implemented"** (spec
  alignment step).

## 6. Open items for ChatGPT (product / UX / architecture)

Each carries a Claude Code recommendation for ChatGPT to confirm/edit:

1. **Formula family.** Full guarded model `a·(Tm/Tref)^p + b` vs the
   narrower 2-parameter power law `a·Tm^p` (b=0, Tref=1).
   *Rec: narrow power law.* Every shipped app-derived alternate uses
   this shape; PTIMER-170 explicitly defers an offset (b) family to
   future. Matches the ticket's "safer narrower family" cue.
2. **Boundary inheritance.** Inherit the fitted formula's
   `noCorrectionThroughSeconds` / `sourceRangeThroughSeconds` from the
   table profile (170 alternates' practice). *Rec: inherit.*
3. **Poor-fit gating.** Does a poor fit **block** generation or only
   **warn**? AC ("inspect + poor fit clearly marked") → *Rec: warn,
   do not block.* Confirm reuse of PTIMER-170 thresholds (0.1/0.25
   stop).
4. **UX placement.** Entry point / surface — a "Generate fitted
   formula" inspection panel inside the custom table editor (family +
   params + per-anchor comparison + worst error). *Rec: inspection-
   only section in the editor, reusing the existing comparison
   presentation.*
5. **Anchor count vs fit meaning.** 2 anchors → the power law passes
   through exactly (zero error), so "fit quality" is meaningless.
   Surface the quality warning only at **≥3 anchors**? *Product
   call.*
6. **Failure-mode presentation.** If OLS yields a shortening /
   non-finite formula (fails `CustomFilmFormulaGuard`), present it as
   an "unusable fit" with no adoption path. *Rec: yes.*
7. **Label vocabulary.** Reuse existing "App-derived formula" /
   "App formula" wording. *Rec: yes.*

## 7. Dependencies / sequencing
- **Predecessor**: PTIMER-178 done (table-anchor authoring path
  exists) — satisfied.
- **Successor**: PTIMER-180 (model selection) depends on 179; 179
  deliberately stops just short of "selection" (inspection-only).
- Suggested branch (ticket): `feature/PTIMER-14-custom-table-formula-fitting`.

## 8. Source references (for the spec-writing step)
- Guarded formula model: `ios/PTimerKit/Sources/PTimerCore/Reciprocity/ReciprocityDomain.swift` (`ReciprocityFormula`, ~785-1049; `hasValidParameters` ~964-974)
- Table rule: `ReciprocityDomain.swift` (`TableAnchor` ~688-699, `TableInterpolationReciprocityRule` ~701-760); interpolation `TableInterpolationModel.swift:140-159`
- Policy evaluator: `ReciprocityCalculationPolicy.swift` (formula branch ~709-785, table branch ~787-833)
- Fitting math (test-only): `Tests/PTimerKitTests/Reciprocity/AppDerivedFormulaEvaluationTests.swift:324` (`freeLogLogFit`), `:339` (`worstAbsoluteStopError`)
- App-derived comparison presenter: `Sources/PTimerKit/Reciprocity/ReciprocityModelComparisonPresenter.swift`
- Non-shortening guard: `Sources/PTimerKit/CustomFilm/CustomFilmFormulaGuard.swift`
- App-derived labeling: `Sources/PTimerCore/Reciprocity/AlternateReciprocityModels.swift` (`isAppDerivedModel` ~80)
- Editor preview surface: `Sources/PTimerKit/CustomFilm/CustomFilmEditorPreviewPresenter.swift`
- Custom film form state / sanitizer (178): `Sources/PTimerKit/CustomFilm/CustomFilmEditorFormState.swift`, `CustomFilmEditorTableFormState.swift`, `CustomFilmLibrary.swift` (`isWellFormedCustomFilm` ~94-199)
- PTIMER-170 method & thresholds: `docs/tasks/PTIMER-170/app-derived-formula-evaluation.md`
- PTIMER-178 task spec (format template): `docs/tasks/PTIMER-178.md`
- Spec paragraphs to update at start: `docs/specs/Calculator.md:277`, `docs/specs/DomainSchema.md:383`, `:405`
