# PTIMER-162 — Reciprocity Method Comparison

Parent epic: **PTIMER-128** — Film-specific Reciprocity Model Selection and
Verification.
Predecessors: **PTIMER-160** (shared guarded reciprocity formula model),
**PTIMER-163** (separate `sourceModel` from `calculationModel`), **PTIMER-161**
(Fomapan 100 multi-profile review).
Successor: **PTIMER-159** (multi-profile Details / selection UI).

This report decides **which reciprocity calculation / fitting methods should be
available or preferred by source shape**. It is decision support for
PTIMER-159. It does **not** change shipped catalog constants, refit any
production profile, enable `tableLookup` / interpolation as production
calculation, or implement selector / Details UI. Formula coefficients derived
here are illustrative comparison candidates only and are **not** applied to the
catalog.

> **Source-data discipline.** "Official" means values published by the film
> manufacturer. Any curve fitted from those anchors is an **app-derived
> comparison model**, never official guidance, even when it reproduces the
> official anchors exactly. The two are kept in separate sections so PTIMER-159
> can present them separately (Source Reference vs App-derived Comparison).

---

## 0. Method note: verified behavior vs. interpretation

- **[CODE]** — verified against the current working tree under `ios/PTimer/…`
  (`Reciprocity/ReciprocityCalculationPolicy.swift`,
  `Reciprocity/ReciprocityDomain.swift`,
  `ExposureCalculator/PresetFilmCatalog.swift`,
  `Resources/LaunchPresetFilmCatalog.json`) and `ios/PTimerTests/…`.
- **[GIT]** — verified against this repo's pre-formula-migration history
  (table evaluator `32c41c0`; ceiling removal `e82258f`; domain lock to
  formula + limited-guidance `5678112` / PTIMER-140; guarded formula `df81e6d`
  / PTIMER-160; source/calc split `f318195` / PTIMER-163).
- **[DOC]** — taken from `docs/tasks/PTIMER-161/fomapan-100-multi-profile-review.md`,
  whose numbers are pinned by `ios/PTimerTests/Reciprocity/Fomapan100ModelReviewTests.swift`.
- **[MATH]** — arithmetic worked in this report.
- **[INTERP]** — interpretation / recommendation.

The source now lives under `ios/` and **is genuinely post-PTIMER-128**:
production reciprocity calculation is **formula-only** (guarded modified
Schwarzschild) or limited-guidance; the table lookup / interpolation /
extrapolation evaluator that earlier shipped is **removed from production and
reserved**. That removed evaluator is documented in §3 as prior behavior.

---

## 1. Changed files

| File | Change |
|------|--------|
| `docs/tasks/PTIMER-162/reciprocity-method-comparison.md` | **New** — this report. |

No production source, catalog JSON, tests, or scripts were changed. `git status
--short` shows only this doc (plus the pre-existing untracked `android/` build
cache). No catalog constant edited; no `tableLookup` enabled; no UI added.

---

## 2. Current-source findings (post-PTIMER-128)

### 2.1 Source model vs. calculation model — PTIMER-163 split **[CODE]**

`ReciprocityProfileModelBasis` carries two orthogonal axes
(`ReciprocityDomain.swift:355`):

```
struct ReciprocityProfileModelBasis { sourceModel; calculationModel }
```

- **`ReciprocitySourceModel`** (`:299`): `manufacturerFormula`,
  `manufacturerTable`, `manufacturerRangeGuidance`,
  `manufacturerLimitedGuidance`, `practicalCommunityGuidance`, `userDefined`,
  `unknown`. — *what the source actually is.*
- **`ReciprocityCalculationModel`** (`:332`): `guardedFormula`,
  `limitedGuidance`, `unsupported`, `tableLookup`. — *how the app computes.*

When `modelBasis` is omitted it is **inferred** from rule shape + provenance
(`effectiveModelBasis`, `:228`): formula rule → `guardedFormula`; limited-
guidance rule → `limitedGuidance`; else `unsupported`; source side maps
`thirdPartyPublication` → `practicalCommunityGuidance`, manufacturer + formula +
no evidence → `manufacturerFormula`, manufacturer + formula + evidence →
`manufacturerTable`, etc.

### 2.2 Guarded formula model — PTIMER-160 **[CODE]**

`ReciprocityFormula` (`ReciprocityDomain.swift:599`) fields: `formulaFamily`,
`coefficientSeconds` (a), `referenceMeteredTimeSeconds` (Tref, default 1),
`exponent` (p), `offsetSeconds` (b, default 0), `noCorrectionThroughSeconds`,
`sourceRangeThroughSeconds?`.

`FormulaFamily` (`:568`) has exactly **one** case today:
**`modifiedSchwarzschild`**.

Evaluation (`evaluate(meteredExposureSeconds:)`, `:781`) returns a tagged
outcome:

1. **No-correction floor** — `if Tm ≤ noCorrectionThroughSeconds → .noCorrection`
   (`:797`).
2. **Corrected time** — `Tc = a · (Tm/Tref)^p + b` (`:801`).
3. **Output sanity** — `corrected.isFinite && > 0`, else `.formulaOutputUnusable`
   (`:809`).
4. **`Tc ≥ Tm` invariant** — `guard corrected ≥ Tm − 1e-6 else
   .unsafeShorteningFormula` (`:819`). A reciprocity correction must never
   *shorten* the shutter.
5. **Source-range classification** — if `Tm > sourceRangeThroughSeconds →
   .beyondSourceRange(corrected)` else `.withinSourceRange(corrected)` (`:822`).

### 2.3 How the policy maps formula outcomes **[CODE]**

`ReciprocityCalculationPolicyEvaluator.evaluate` (`…Policy.swift:585`) selects
rules in this order (`evaluateRuleSelection`, `:598`):

1. **Formula rule first** — if present, the formula owns the whole decision
   (`:624`).
2. **Threshold no-correction** (`:632`).
3. **Limited-guidance** (`:639`).
4. **Unsupported** (`:646`).

Formula outcome → result kind (`evaluateFormulaRule`, `:657`):

| Formula outcome | Result | Corrected value surfaced? |
|-----------------|--------|----------------------------|
| `.noCorrection` (Tm ≤ floor) | quantified, basis `officialThresholdNoCorrection` (`Tc=Tm`) | yes |
| `.withinSourceRange` | **quantified**, basis `formulaDerived` | yes |
| `.beyondSourceRange` | **unsupported** (`unsupportedFormulaOutsideSourceRange`) — carries the computed value for display but is **classed unsupported** with "outside manufacturer source range" notes (`:913`) | yes, but flagged unsupported |
| `.unsafeShorteningFormula` | quantified `invariantClampedNoCorrection` (`Tc=Tm`) (`:723`) | yes |
| `.invalidInput` / `.invalidFormula` / `.formulaOutputUnusable` | unsupported | no |

**Key behavior:** beyond `sourceRangeThroughSeconds` the app does **not** ship a
usable extrapolated correction — it returns **unsupported** (value shown only as
a labeled prediction). This is the deliberate, stricter replacement for the old
uncapped table extrapolation (§3).

### 2.4 Table calculation is removed from production and reserved **[CODE]**

- The evaluator's `Selection` only collects `threshold`, `formula`, and
  `limitedGuidance` rules (`:603`). There is **no table-rule evaluation path**.
- `calculationModel = .tableLookup` is a **reserved placeholder**; the catalog
  loader rejects it: `"modelBasis.calculationModel = tableLookup is not yet
  implemented"` (`PresetFilmCatalog.swift:271`). `.unsupported` is likewise
  rejected for launch profiles (`:266`).
- The original published rows survive only as **`sourceEvidence`**
  (`ReciprocityDomain.swift:104,170`) — explicitly **display-only**; the
  evaluator never consumes them as calculation anchors (comment at `:99`,
  test `ReciprocityProfileModelBasisTests:83`).

### 2.5 Catalog loader invariants **[CODE]** (`PresetFilmCatalog.swift`)

- Exactly **one** official, `manufacturerPublished` profile per film (`:119`,
  `:125`); film `preset` + `current` + ISO>0.
- **Allowed rule shapes only:** either a single **formula** rule (which owns its
  no-correction guard — a companion threshold is rejected, `:183`), or a
  **threshold + limited-guidance** pair (`:199`,`:206`). Formula + limited-
  guidance cannot coexist (`:175`). Limited-guidance profiles cannot carry
  `sourceEvidence` (`:213`).
- **Formula safe-parameter contract** (`hasValidParameters`,
  `ReciprocityDomain.swift:751`): `a>0` finite, `Tref>0` finite, `p` finite,
  `b` finite, `noCorrectionThroughSeconds ≥ 0`, and `sourceRangeThroughSeconds`
  (if set) **strictly above** the no-correction boundary.
- **modelBasis compatibility:** `guardedFormula` requires a formula rule;
  `limitedGuidance` requires a limited-guidance rule; `tableLookup` /
  `unsupported` rejected; `practicalCommunityGuidance` / `userDefined` /
  `unknown` source rejected for the official catalog (`:225–297`).

### 2.6 Catalog shape distribution **[CODE]**

34 films. Production calculation is entirely **guardedFormula** or
**limitedGuidance**; no `tableLookup`, no `unsupported`, no shipped community/
user profile. Representative shapes:

| Source shape | Example | modelBasis | Key fields |
|--------------|---------|------------|-----------|
| Official **formula** | ILFORD HP5+ (`…-official-formula`) | `manufacturerFormula` / `guardedFormula` | `p=1.31`, a=1, noCorr ≤1s, no source-range cap, no evidence |
| Official **table** → fitted formula | Kodak Tri-X (`kodak-tri-x-official-formula`) | `manufacturerTable` / `guardedFormula` | a=2.013654, `p=1.3891`, noCorr `0.999999` (≈<1s), sourceRange 100s, 3 evidence rows (1→2, 10→50, 100→1200) |
| Official **table** → fitted formula | **Fomapan 100** (`foma-fomapan-100-official-formula`) | `manufacturerTable` / `guardedFormula` | **a=2.2457, p=1.4515, Tref=1, b=0, noCorr 0.5s, sourceRange 100s**; evidence 1→2, 10→80, 100→1600 |
| **Limited** guidance | Kodak Ektar 100 | `manufacturerLimitedGuidance` / `limitedGuidance` | threshold ≤1s + "test under your conditions"; no formula, no evidence |
| **Range** guidance | *(enum exists; no shipped film)* | `manufacturerRangeGuidance` | reserved (domain cites Rollei RETRO 80S "1–2 sec" row) |
| **Community / user** | *(none shipped; rejected by loader)* | `practicalCommunityGuidance` / `userDefined` | Fomapan Ohzart table + community log-quadratic live **test-only** in `Fomapan100ModelReviewTests` |

---

## 3. Old pre-128 table behavior findings

This repo's own history shipped a full table-evaluation policy before the
formula migration (`32c41c0` … `e82258f` … then `5678112` locked the domain to
formula + limited-guidance). It is **prior behavior**, not a target.

| Aspect | Old behavior | Verified? |
|--------|--------------|-----------|
| **Evaluation order** | exact table rows → threshold no-correction → table interpolation/extrapolation → formula → advisory → unsupported. | **[GIT]** |
| **Exact-row handling** | `.exactSeconds` matched within 1e-6; corrected from `correctedTime`, else `Tm·2^stopDelta`, else `Tm·factor` (multiplier→`log2`); a stop-signal row returned unsupported even on exact hit. | **[GIT]** |
| **No-correction threshold** | first `noCorrectionRange` containing Tm → `Tc=Tm`, after exact rows, before estimation. | **[GIT]** |
| **Log-log behavior** | corrected-time anchors → power law `Tc=Cl·(Tm/Ml)^slope`, `slope=ln(Cu/Cl)/ln(Mu/Ml)`. | **[GIT]** |
| **Stop-space behavior** | stopDelta/multiplier anchors → linear-in-stops vs `log2(Tm)`, `Tc=Tm·2^Δ(Tm)`. | **[GIT]** |
| **Interpolation** | bracketing two quantified same-family anchors; range rows excluded as anchors. | **[GIT]** |
| **Extrapolation** | last two anchors extended with the same law — originally **capped** at `nextOrderOfMagnitudeLimit = pow(10, floor(log10(lastMetered))+1)` (e.g. last 100s → allowed <1000s; ≥1000s `unsupportedOutOfPolicyRange`). | **[GIT]** |
| **Ceiling removal** | `e82258f` deleted that cap; extrapolation then continued unbounded except at an explicit stop-signal row, re-labeled "low-confidence … verify with testing". | **[GIT]** |
| **Not-recommended boundary** | `warning.severity == .notRecommended` row = hard stop: excluded as anchor and capped extrapolation with `unsupportedStopSignal`. | **[GIT]** |
| **Range rows as anchors?** | **No** — never quantified points; usable only for exact-match containment. | **[GIT]** |

### 3.1 Should old extrapolation return as default? **[INTERP]**

**No.** Two independent reasons, both now baked into the shipped design:

1. The old `nextOrderOfMagnitudeLimit` was a base-10 artifact, not a
   photographic boundary (100s-anchor → fail at 1000s; 90s-anchor → fail at
   100s). Removing it was right; **restoring it is wrong.**
2. The post-128 design replaces *both* the cap and the uncapped extrapolation
   with an honest **`sourceRangeThroughSeconds` → unsupported** rule (§2.3):
   beyond the manufacturer's published range, the app declines to present a
   usable corrected value rather than extrapolate a table. That is stricter and
   more defensible than either old mode. Keep it.

---

## 4. Method comparison summary

Required fields per family. "Anchor range" = where the method is defined by its
inputs; "beyond range" = behavior past the last input. Recommendation reflects
the **already-shipped** post-128 policy.

### 4.1 Direct table lookup
- **Math:** exact equality (≈1e-6) to a published anchor → that row's value.
- **Input shape:** ≥1 `.exactSeconds` anchor (or a `.range` row for containment).
- **Suitable:** any table source (official or community) for *exact* points.
- **Unsuitable:** formula / limited sources; any non-anchor metered value.
- **Fitting basis:** none (published).
- **Anchor range / beyond:** only the published points; nothing between/beyond.
- **`Tc≥Tm`?** Yes (it is the source value); not clamped arithmetically.
- **Sub-second guard?** Not needed (only published rows return).
- **Range rows safe?** Yes (containment is the source's own statement).
- **Recommendation:** **OPTIONAL / reserved** — the value is sound, but the
  shipped policy uses formulas; lookup-only adds no coverage between anchors.
  Keep as a Source-Reference display, not a production calc model
  (`tableLookup` stays reserved).

### 4.2 Stop-space table interpolation
- **Math:** linear interp of stop delta vs `log2(Tm)`; `Tc=Tm·2^Δ(Tm)`.
- **Input shape:** ≥2 same-family `.exactSeconds` anchors expressed in
  stops/multipliers, no direct corrected time.
- **Suitable:** stop-expressed tables, *if* table calc is ever enabled.
- **Unsuitable:** corrected-time tables (use log-log to hit anchors exactly);
  formula/limited sources.
- **Anchor range / beyond:** between anchors; extends last segment's stop slope.
- **`Tc≥Tm`?** Guaranteed for Δ≥0; not clamped.
- **Sub-second guard?** Rely on threshold floor.
- **Range rows safe?** Not as anchors.
- **Recommendation:** **OPTIONAL / app-derived only** (reserved with
  `tableLookup`).

### 4.3 Log-log table interpolation
- **Math:** piecewise power law through adjacent corrected-time anchors,
  `slope=ln(Cu/Cl)/ln(Mu/Ml)`, `Tc=Cl·(Tm/Ml)^slope`.
- **Input shape:** ≥2 same-family corrected-time anchors.
- **Suitable:** corrected-time tables; **hits every anchor exactly** (its edge
  over a single global power fit).
- **Unsuitable:** stop-only / single-anchor / formula / limited sources.
- **Anchor range / beyond:** between anchors; extends last segment's slope
  (monotone, low-confidence).
- **`Tc≥Tm`?** Guaranteed for `Cl≥Ml`, slope≥1; not clamped — validate (§8).
- **Sub-second guard?** Rely on threshold floor.
- **Range rows safe?** Not as anchors.
- **Recommendation:** **OPTIONAL / app-derived only** — best *interpolation*
  for corrected-time anchors if table calc is ever enabled; not a production
  default today (`tableLookup` reserved).

### 4.4 Old table extrapolation (next-order-of-magnitude ceiling)
- **Math:** §4.2/4.3 law, hard-capped at `pow(10, floor(log10(lastAnchor))+1)`.
- **Suitable / unsuitable:** none better than alternatives; the cap is a decimal
  artifact.
- **Beyond range:** `unsupportedOutOfPolicyRange`.
- **Recommendation:** **REJECT.** Superseded by `sourceRangeThroughSeconds →
  unsupported` (§2.3, §3.1).

### 4.5 Modified Schwarzschild / guarded power-style formula **(shipped)**
- **Math:** `Tc = a·(Tm/Tref)^p + b`, with no-correction floor and `Tc≥Tm`
  clamp (§2.2). Shipped FOMA/Tri-X use `Tref=1, b=0` → `Tc=a·Tm^p`.
- **Input shape:** one exponent `p` (+ optional `a`, `Tref`, `b`) and a
  no-correction floor; optional `sourceRangeThroughSeconds`.
- **Suitable:** **(i)** films whose manufacturer publishes an exponent
  (ILFORD/HARMAN — `a=1`); **(ii)** an **app-derived** fit through a clean
  corrected-time table (FOMA/Tri-X — `a≠1`).
- **Unsuitable:** range / limited sources; sparse (≤2-point) tables; pure
  `Tc=Tm^p` (a=1) on a table whose first anchor is already corrected (FOMA 1s→2s
  forces `Tc=1` at Tm=1 — see §6 D).
- **Fitting basis:** if app-derived, least-squares in log space.
- **Anchor range / beyond:** within `sourceRangeThroughSeconds`; **beyond →
  unsupported** (not extrapolated as usable).
- **`Tc≥Tm`?** Enforced at runtime via the clamp → `Tc=Tm` (`:819`).
- **Sub-second guard?** Enforced via `noCorrectionThroughSeconds`.
- **Range rows safe?** N/A.
- **Recommendation:** **RETAIN** as the production calculation model — published
  exponent when the source is a formula; app-derived fit (separately labeled)
  when the source is a table.

### 4.6 Kron–Halm continuous formula
- **Math:** a continuous closed-form curve with 1–2 fitted constants; a sibling
  of the guarded power law with a different curvature term.
- **Input shape:** published/derived constant(s). No catalog film publishes one.
- **Suitable:** only where a source publishes constants, or as an app-derived
  alternative if a power law fits poorly but a 1-extra-parameter curve fits well
  and stays monotone.
- **Unsuitable:** as a default; over-parameterised from 2–3 anchors.
- **`Tc≥Tm`?** Must be guarded; **Sub-second guard?** Required.
- **Recommendation:** **REJECT as default / OPTIONAL app-derived only.** No data
  motivates adding a second `FormulaFamily` now.

### 4.7 Log-log power fit (global)
- **Math:** single global `Tc=a·Tm^p` by OLS on `(log Tm, log Tc)`. **This is
  exactly the shipped `modifiedSchwarzschild` form with `Tref=1, b=0`** — so for
  FOMA/Tri-X §4.5 and §4.7 are the *same curve*.
- **Suitable:** app-derived model for a dense, well-behaved corrected-time table
  (the shipped table→formula path).
- **Unsuitable:** sparse / range / limited; cases needing exactness at every
  anchor (it generally does not pass through all anchors).
- **Beyond range:** smooth, monotone for `p≥1` — best-behaved extrapolator, but
  the shipped policy still gates it with `sourceRangeThroughSeconds`.
- **`Tc≥Tm`?** Guaranteed `a≥1,p≥1,Tm≥1`; clamp covers the rest.
- **Recommendation:** **RETAIN (this IS the shipped table→formula method).**
  Best generated-formula family when one is wanted; gate by §8.

### 4.8 Log-quadratic multiplier / other practical fit
- **Math:** a **log-quadratic multiplier** model — `Tc` is the metered time
  times a multiplier that is quadratic in `log10 Tm`. The PTIMER-161 community
  FOMA formula is one instance:
  `Te = Tm × ((log10 Tm)² + 5·log10 Tm + 2)` (with `Tm` in seconds). The
  bracketed term is the multiplier; it is **not** a quadratic fit of
  `log10 Tc`. At the FOMA anchors the multiplier collapses to FOMA's published
  factors — `(0²+0+2)=2`, `(1²+5+2)=8`, `(2²+10+2)=16` — so the formula **passes
  the 1s / 10s / 100s FOMA anchors exactly** (§6 C). **[DOC]**
- **Input shape:** ≥3 corrected-time anchors (exact through 3).
- **Suitable:** app-derived **interpolation** across a 3-anchor table when a
  single closed form hitting all three anchors is wanted.
- **Unsuitable / required guards (community FOMA formula, raw):** **[DOC]**
  - it requires the existing **no-correction guard at or below 0.5s** (the
    profile's `noCorrectionThroughSeconds`);
  - raw output gives **`Te < Tm` below about 0.619s** (the correction would
    shorten the shutter);
  - the raw **multiplier becomes negative below about 0.364s** (the formula
    breaks down entirely);
  - **extrapolation beyond the 100s source range must be capped / treated as
    unsupported** — the image itself notes a ≈100s upper bound on `Tm`.
- **`Tc≥Tm`?** In-range yes; out-of-range no → must be guarded by the existing
  `noCorrectionThroughSeconds` floor (≤0.5s for FOMA), the runtime `Tc≥Tm`
  clamp, and a hard source-range cap.
- **Recommendation:** **OPTIONAL / app-derived only, interpolation-only,
  community-labeled.** Equivalent in-range to piecewise log-log (both exact at
  the three anchors); inferior beyond range.

---

## 5. Recommended default method policy by source shape **[INTERP]**

This codifies the **already-shipped** post-128 design.

| Source shape (`sourceModel`) | Source model = authority | Default calc model (`calculationModel`) | Generated formula? |
|------------------------------|--------------------------|-----------------------------------------|--------------------|
| **Official formula** (`manufacturerFormula`) | the published formula | **`guardedFormula`** with the published exponent (a=1), no-correction floor | Not needed — source *is* a formula |
| **Official table** (`manufacturerTable`) | the table (kept as `sourceEvidence`) | **`guardedFormula`** = app-derived log-log fit, labeled app-derived, with `noCorrectionThroughSeconds` + `sourceRangeThroughSeconds` (beyond → unsupported) | Yes, **app-derived only**, gated by §8; never relabeled official |
| **Sparse official table (≤2 anchors)** | the table | Prefer `limitedGuidance`; a 2-point "fit" is just the segment | Only if error profile explicitly accepted |
| **Range guidance** (`manufacturerRangeGuidance`) | the range row | Direct **containment** display; **do not** fit range endpoints | No |
| **Limited guidance** (`manufacturerLimitedGuidance`) | advisory text | **`limitedGuidance`** (threshold + "test under your conditions"); keep unsupported quantified prediction | **No — do not fabricate a curve** |
| **Practical/community** (`practicalCommunityGuidance`) | separate unofficial profile | Same methods, authority kept unofficial/labeled; **rejected from the official launch catalog** today | Allowed, labeled practical/community/app-derived |

Answers to the ticket's decision questions:

1. **Default for official formulas?** `guardedFormula` with the published
   exponent (modified Schwarzschild, a=1), applied above its no-correction
   floor. **[INTERP/CODE]**
2. **Default for official table-origin profiles?** Keep the table as
   `sourceEvidence` (Source Reference); compute with an **app-derived
   `guardedFormula` log-log fit**, guarded by no-correction floor +
   source-range cap. **[INTERP/CODE]**
3. **When is direct table lookup enough?** Only for display of exact published
   anchors. It adds no between-anchor coverage, so it stays a Source-Reference
   element; `tableLookup` remains reserved. **[INTERP]**
4. **When is stop-space interpolation preferable?** Only if table calc is ever
   enabled, and only for stop-expressed tables — never the production default
   now. **[INTERP]**
5. **When is log-log interpolation preferable?** Same caveat; it is the right
   *interpolation* for corrected-time anchors (exact at anchors) if table calc
   is enabled, but the shipped path already captures table data via the global
   log-log fit. **[INTERP]**
6. **Should old extrapolation return as default?** No (§3.1). The shipped
   `sourceRangeThroughSeconds → unsupported` rule is the correct replacement.
7. **When is a derived formula acceptable as app-derived?** For a table with ≥3
   clean monotone corrected-time anchors, when the §8 gate passes, and only as a
   separately labeled App-derived Comparison — never as the source. (This is
   exactly what FOMA/Tri-X already do.) **[INTERP/CODE]**
8. **Best generated-formula family?** **Global log-log power fit `Tc=a·Tm^p`**
   (the shipped `modifiedSchwarzschild`) — monotone, well-behaved, one extra
   parameter. Log-quadratic only for exact-through-3-anchor *interpolation* with
   a hard cap. **[INTERP]**
9. **Unsafe/misleading for sparse/range/limited?** Any fit on ≤2 anchors; using
   range endpoints as fit points; log-quadratic extrapolation; pure `Tc=Tm^p`
   (a=1) on a corrected-1s-anchor table; fabricating any curve for
   limited/advisory sources. **[INTERP]**
10. **Validation rules before accepting a generated formula?** §8.
11. **What PTIMER-159 shows separately?** §9.

---

## 6. Recommended generated-formula family + worked error report

### 6.1 Reusable source-anchor comparison format (for PTIMER-159)

| Tm (s) | Source Tc (s) | Calc Tc (s) | Abs err (s) | % err | Stop err | Source range status | Notes |
|--------|---------------|-------------|-------------|-------|----------|---------------------|-------|

- **% err** = `(CalcTc − SourceTc)/SourceTc × 100`.
- **Stop err** = `log2(CalcTc/SourceTc)`.
- **Range status** ∈ `{below no-correction floor, within source range, beyond
  source range → unsupported}`.

### 6.2 Worked example — Fomapan 100 official anchors

Official FOMA table data (preserved as `sourceEvidence`; **a table source, not
a formula**):

- No correction through about **1/2 s**.
- **1s → 2× (+1 stop) → 2s.**
- **10s → 8× (+3 stops) → 80s.**
- **100s → 16× (+4 stops) → 1600s.**

> None of the fitted curves below is FOMA guidance.

Candidate A — **piecewise log-log table interpolation** (reserved; would be
`tableLookup`): exact at every anchor.

| Tm | Source Tc | Calc Tc | Abs err | % err | Stop err | Range status | Notes |
|----|-----------|---------|---------|-------|----------|--------------|-------|
| 1   | 2    | 2.000   | 0.000 | 0.0% | 0.000 | within | exact anchor |
| 10  | 80   | 80.000  | 0.000 | 0.0% | 0.000 | within | exact anchor |
| 100 | 1600 | 1600.000| 0.000 | 0.0% | 0.000 | within | exact anchor |

Local slopes differ (1→10s: `ln40/ln10=1.602`; 10→100s: `ln20/ln10=1.301`) — the
data is **not a single power law**, so a global fit must spread residual. **[MATH]**

Candidate B — **shipped guarded modified-Schwarzschild = global log-log power
fit** `Tc = 2.2457·Tm^1.4515` (a=2.2457, p=1.4515, Tref=1, b=0). Values pinned
by `Fomapan100ModelReviewTests`. **[CODE/DOC]**

| Tm | Source Tc | Calc Tc | Abs err | % err | Stop err | Range status | Notes |
|----|-----------|---------|---------|-------|----------|--------------|-------|
| 1   | 2    | 2.2457  | +0.2457 | +12.3% | +0.167 | within | overexposes |
| 10  | 80   | 63.5114 | −16.49  | −20.6% | −0.333 | within | underexposes |
| 100 | 1600 | 1796.19 | +196.19 | +12.3% | +0.167 | within (= sourceRange) | overexposes |

Worst-case ≈ **⅓ stop at 10s**; ~⅙ stop at the 1/100s anchors — the fit caps the
10s residual by accepting symmetric residual at the ends. **[DOC]**

Candidate C — **log-quadratic multiplier (community image)**
`Te = Tm × ((log10 Tm)² + 5·log10 Tm + 2)` — `Tm` times a multiplier quadratic
in `log10 Tm`. **Exactly matches the 1s / 10s / 100s FOMA anchors** (the
multiplier collapses to 2, 8, 16 there). **[DOC]**

| Tm | Source Tc | Calc Tc | Abs err | % err | Stop err | Range status | Notes |
|----|-----------|---------|---------|-------|----------|--------------|-------|
| 1   | 2    | 2.000   | 0.000 | 0.0% | 0.000 | within | exact match (multiplier = 2) |
| 10  | 80   | 80.000  | 0.000 | 0.0% | 0.000 | within | exact match (multiplier = 8) |
| 100 | 1600 | 1600.000| 0.000 | 0.0% | 0.000 | within (= sourceRange) | exact match (multiplier = 16) |

Exact at the three anchors, but the **raw** community formula needs the same
guards the shipped FOMA profile already provides: **[DOC]**
- requires the existing **no-correction guard at or below 0.5s**;
- gives **`Te < Tm` below about 0.619s** (correction would shorten the shutter);
- the **multiplier becomes negative below about 0.364s**;
- **beyond the 100s source range it must be capped / treated as unsupported**
  (the image notes a ≈100s upper bound on `Tm`).

Community-derived, not FOMA-published.

Candidate D — **pure modified-Schwarzschild** `Tc=Tm^p` (a=1): structurally
`Tc=1` at Tm=1, contradicting the 2s anchor. **[MATH]**

| Tm | Source Tc | Calc Tc (p=1.45) | Abs err | % err | Stop err | Notes |
|----|-----------|------------------|---------|-------|----------|-------|
| 1  | 2 | 1.000 | −1.000 | −50.0% | −1.000 | cannot hit a corrected 1s anchor → **reject for FOMA** |

### 6.3 Below floor and beyond range

- **Below the no-correction floor (Tm ≤ 0.5s):** the shipped formula returns
  `.noCorrection` → `Tc=Tm` (§2.2). Without the floor, Candidate B at Tm=0.1s
  gives `Tc≈0.079s` (`Tc<Tm`) — the `Tc≥Tm` clamp would then force `Tc=Tm`. The
  floor is mandatory for any formula candidate. **[CODE/MATH]**
- **Beyond the source range (Tm > 100s):** the shipped policy returns
  **unsupported** (value shown only as a labeled prediction), §2.3 — it does
  **not** present an extrapolated correction. Any candidate inherits this. **[CODE]**

### 6.4 Cross-check vs. the unofficial Ohzart table **[DOC]**

The shipped FOMA fit and the community Ohzart practical table disagree by ~¼–⅖
stop across 1–60s (e.g. 4s: Ohzart 13s vs app 16.8s, +0.37 stop; 8s: 35s vs
45.9s, +0.39 stop). The community log-quadratic and Ohzart disagree even more
(up to +0.75 stop at 8s). Conclusion (from PTIMER-161): these are **three
distinct models** — official anchor fit, community formula, community table —
and must never be merged or cross-relabeled.

### 6.5 Recommended generated-formula family **[INTERP]**

- **Single smooth global model:** **log-log power fit `Tc=a·Tm^p`** — already
  the shipped `modifiedSchwarzschild`. Best default generated candidate
  (monotone, safe extrapolation shape, gated by source-range). Cost: ≤~⅓-stop
  anchor error for FOMA, which **must be disclosed**.
- **Exact-through-3-anchor interpolation overlay:** log-quadratic
  (interpolation-only, hard-capped, community-labeled).
- **Kron–Halm / new `FormulaFamily`:** not justified by current data.

**Net (recommendation, not a catalog decision):** this report does **not**
change any catalog value. On the evidence here, **PTIMER-162 sees no need to add
a new formula family or refit FOMA** — the shipped `guardedFormula` already
encodes the recommended method, and PTIMER-159 should be able to proceed by
*presenting* the source/derived split rather than introducing a new model. Any
actual change to FOMA's catalog constants or a new `FormulaFamily` remains a
separate, explicitly authorised implementation ticket.

---

## 7. Rejected / unsafe methods and reasons **[INTERP]**

| Method | Verdict | Reason |
|--------|---------|--------|
| Old next-order-of-magnitude ceiling | Reject | Decimal artifact; removed in `e82258f`; superseded by source-range→unsupported. |
| Uncapped table extrapolation | Reject as production | Post-128 deliberately returns unsupported beyond source range. |
| Pure `Tc=Tm^p` (a=1) on corrected-1s-anchor tables | Reject | −1 stop at the FOMA 1s anchor. |
| Log-quadratic extrapolation | Reject (interpolation-only) | Non-monotone far out; `Te<Tm` below ≈0.619s; negative multiplier below ≈0.364s. |
| Any fit on ≤2 anchors | Reject | A 2-point "fit" is just the segment — false confidence. |
| Range endpoints as fitting anchors | Reject | Source stated a band, not points. |
| Generating a curve for limited/advisory sources | Reject | Fabricates data the manufacturer declined to publish. |
| Enabling `tableLookup` in production | Reject (out of scope) | Reserved; loader rejects it; needs a dedicated implementation ticket. |
| Merging Ohzart table with community formula | Reject | They differ by ⅓–¾ stop (§6.4); distinct models. |

---

## 8. Validation rules required before accepting a generated formula **[INTERP]**

A generated/app-derived formula may be surfaced only if **all** pass — most are
already enforced by the loader / formula contract (§2.5):

1. **Anchor coverage:** ≥3 monotone `.exactSeconds` corrected-time anchors
   (exclude range, threshold, limited, stop-signal rows).
2. **Monotonicity:** `Tc(Tm)` strictly increasing across anchors + intended
   in-range domain.
3. **`Tc ≥ Tm`** over the domain above the floor — enforced at runtime by the
   clamp (`:819`), but also checked at fit time so the clamp is never the normal
   path.
4. **Sub-second floor:** `noCorrectionThroughSeconds` set so sub-floor values
   return `Tc=Tm` (enforced; safe-parameter contract requires it ≥0).
5. **Source-range cap:** `sourceRangeThroughSeconds` set strictly above the
   floor (enforced, `ReciprocityDomain.swift:751`); beyond it → unsupported, not
   extrapolated.
6. **Anchor-error gate:** per-anchor `|stop err| ≤ S_max`, `|% err| ≤ P_max`
   (suggested first cut **S_max = ⅓ stop**, **P_max = 25%** — FOMA's shipped fit
   sits exactly at this edge; tune with a catalog sweep). Fits exceeding the gate
   are rejected, not shipped.
7. **Safe-parameter contract:** finite, `a>0`, `Tref>0` (loader-enforced).
8. **Authority separation:** stored/labeled app-derived; never promoted to
   `authority=.official`; community/user sources rejected from the official
   catalog (loader-enforced). The one-official-profile-per-film invariant stays.

---

## 9. PTIMER-159 handoff notes **[INTERP]**

Present **two clearly separated registers** (this matches PTIMER-161 §5.2):

- **Source Reference (authoritative).** For a `manufacturerTable` profile, the
  `sourceEvidence` rows verbatim (FOMA's three multiplier rows: 1→2, 10→80,
  100→1600); for a `manufacturerFormula` profile, the published exponent; for
  limited, the advisory text — plus publisher/citation from
  `ReciprocitySourceProvenance`. **Derived predictions must not appear here.**
- **App-derived Comparison (optional, labeled).** The `guardedFormula` output
  with the §6.1 anchor-error table and an explicit "app-derived, verify with
  testing" label. Never styled as manufacturer guidance.

Concrete handoff points:

- **Method is chosen by `sourceModel`, not a global switch.** `manufacturerFormula`
  → published exponent; `manufacturerTable` → app-derived fit + evidence;
  `manufacturerLimitedGuidance` → no prediction; range/community → kept separate.
- **Surface existing metadata** the evaluator already produces:
  `ReciprocityCalculationBasis` (`formulaDerived` / `officialThresholdNoCorrection`
  / `unsupportedOutOfPolicyRange` / …), `rangeStatus`, `warningLevel`,
  `sourceAuthorityImpact`. Map directly to badges (within-range vs beyond-range
  unsupported vs no-correction-clamped). **[CODE]**
- **Beyond `sourceRangeThroughSeconds`** must render as *unsupported / labeled
  prediction*, never as a confident corrected value (§2.3).
- **Multi-profile per film** (FOMA "Official anchor fit" / "Community Ohzart
  table" / "Community log-quadratic"): the catalog data model after PTIMER-163
  supports it, but community/user profiles are currently **loader-rejected** for
  the official catalog — PTIMER-159 must define where unofficial profiles live
  before surfacing them.
- **Do not change the calculation default** or enable `tableLookup`.

---

## 10. Verification performed

Documentation-only change. Per `AGENTS.md` / `CLAUDE.md`, documentation-only
changes do not require app build/test execution, and **no runtime behavior was
modified**. Checks:

- **Changed files:** only this report (new). `git status --short` shows no
  tracked source/catalog/test changes (only the doc + pre-existing untracked
  `android/`). Stale snapshot artifacts from the earlier wrong-source run were
  removed.
- **No production catalog constants changed** — `LaunchPresetFilmCatalog.json`
  untouched (confirmed via `git status`).
- **No selector/Details UI implemented** — no Swift files changed.
- **No production `tableLookup` enabled** — it remains loader-rejected and
  reserved; evaluator unchanged.
- **Source vs app-derived separation** — enforced throughout (§2.1, §5, §6, §9).
- **Old source used only as reference** — §3 is reconstruction from this repo's
  pre-migration history, tagged `[GIT]`, labeled prior behavior.
- **`git diff --check`** — run; no whitespace/conflict errors (no tracked
  changes to check).
- Cross-checked FOMA residuals against the pinned values in
  `docs/tasks/PTIMER-161/fomapan-100-multi-profile-review.md` /
  `Fomapan100ModelReviewTests` (`[DOC]`).

Build/tests were **not** run because no code, test, script, or fixture changed —
only Markdown was added.

---

## 11. Anything not verified

- **§6.2 Candidate B figures** are reproduced from the PTIMER-161 doc /
  `Fomapan100ModelReviewTests` (pinned), and Candidates A/C/D are hand-computed
  `[MATH]` — not re-run through a fresh fixture in this ticket. PTIMER-159 should
  reproduce any digits it depends on.
- **Suggested §8 gate thresholds** (S_max = ⅓ stop, P_max = 25%, hard
  extrapolation cap) are starting points, **not** validated against the full
  34-film catalog; they need a catalog-wide error sweep. FOMA's shipped fit sits
  at the ⅓-stop edge.
- **`manufacturerRangeGuidance`** has no shipped film, so its behavior is
  reasoned from the domain definition, not exercised.
- **Kron–Halm** is described mathematically; no concrete fit was produced (no
  catalog source publishes constants).
- The ticket-named archives (`ptimerv1-ios-1318.zip`,
  `PTimerv1_before_128.zip`) were not unpacked separately; "old behavior" (§3)
  was reconstructed from this repo's own git history, which contains the full
  pre-migration table evaluator. If those archives differ from this history, §3
  would need re-verification against them.
