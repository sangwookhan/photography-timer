# Calculator Spec

**Domain**: Exposure calculation (ND filter adjustment) and reciprocity correction (film-specific time correction).

This document is a behavior contract: what the calculator shall produce given inputs, what invariants must hold, and what the system must never do. It is platform-neutral.

---

## 1. Domain model

### 1.1 Exposure variables

The calculator works with four variables: **Shutter**, **Aperture**, **ISO**, **ND**. Of these, the current release scope covers **Shutter** and **ND**. **Aperture** and **ISO** are deferred to a later phase.

Each variable is in one of two roles at any time:

- **Fixed** — the user has set the value directly.
- **Derived** — the system computes the value from the others.

Rules:
1. At least one variable shall always be Derived.
2. The initial release shall cap the number of Derived variables at two.
3. When the user edits a Derived variable, that variable transitions to Fixed and the calculator recomputes the remaining Derived variables.

### 1.2 Base shutter and output shutter

The system shall maintain two distinct shutter values:

- **Base Shutter** — the metered exposure, before any adjustment.
- **Output Shutter** — the value produced after ND adjustment and (when a film is selected) reciprocity correction.

The Output Shutter is the value that drives timer creation. The Base Shutter is never used directly to start a timer.

### 1.3 Workflow modes

There is no explicit "Digital / Film" toggle. Workflow is determined entirely by film selection state:

- **Digital workflow** — no film selected. The Output Shutter (after ND only) is the final shooting value. Reciprocity is inactive.
- **Film workflow** — a film is selected. The reciprocity-corrected exposure ("Corrected Exposure") becomes the primary shooting value; the ND-adjusted shutter is intermediate.

The Corrected Exposure row shall remain visible in all film-workflow states, including states where it carries non-quantified guidance. (See §4 for what "non-quantified" means.)

### 1.4 Exposure scale mode

The calculator runs on an **exposure scale** that defines the granularity of one Base Shutter increment. The current shipping scale is **one-third stop**: Base Shutter advances in 1/3-stop increments along a densified ladder with conventional camera-facing labels (§2.3). One-third-stop applies to the **Base Shutter ladder only** — the ND picker stays whole-stop in every shipping mode (§2.2).

The model layer also retains a **full-stop** scale (1-stop shutter, same whole-stop ND) as a reserved abstraction. The full-stop scale shall not surface in the main calculator UI in the current release; it remains in the model so:

- the model layer keeps a single ladder-aware abstraction rather than splitting "the shipping scale" from "everything else";
- regression tests can validate full-stop math directly;
- a future Settings preference (Full / 1/2 / 1/3 stop) can swap the active scale without redesigning the calculator domain.

The fractional-aware `NDStep` domain primitive (with integer `thirdStopCount` round-trip) is likewise retained as **reserved domain infrastructure**, not a shipping ND option. It exists so a future custom or variable-ND workflow can flow through the same calculation and persistence path; the shipping ND picker shall not enumerate fractional ND values.

Until those future preferences exist, the user shall not see a runtime control for the active scale. Persistence still records the active scale token (§5) so when a future preference ships, an upgrade carries the user's prior choice rather than overwriting it on first launch.

---

## 2. Stop-based exposure math

### 2.1 Unit

All exposure adjustment math is performed in **stop space** (base-2 logarithmic). One stop represents a factor-of-two change in light. Shutter targets are computed as

```
output_seconds = base_seconds × 2^stops
```

ND values are stops. The shipping ND ladder is whole-stop (§2.2); the fractional-capable `NDStep` domain primitive is kept as reserved infrastructure for a future custom / variable-ND workflow (§1.4) and shall not surface in the shipping ND picker. Inputs that arrive in factor form (e.g. ND 64×) shall be converted to stops before entering the calculator.

### 2.2 ND input range

The ND picker shall present **integer stops in the closed range [0, 30]** in every shipping mode. One-third-stop applies to the Base Shutter ladder only (§1.4); the ND ladder stays whole-stop because real-world fixed ND filters are sold in whole-stop strengths (ND2 = 1, ND4 = 2, ND8 = 3, …). Picker rows are `0, 1, 2, …, 30` — fractional values such as `1/3, 2/3, 7 1/3, 7 2/3` are **not** part of the shipping ND option set, and shall not be filtered out at the view layer (they shall not exist in the option list at all). Values outside the `[0, 30]` range shall not be representable through the picker.

The fractional-capable `NDStep` domain primitive (and its integer `thirdStopCount` persistence round-trip) is reserved infrastructure for a future custom / variable-ND workflow (§1.4); it shall not surface in the shipping ND picker without an explicit product decision.

### 2.3 Base shutter values

The Base Shutter picker presents a **1/3-stop densified ladder** built from the conventional 19-value full-stop reference (`1/8000 … 30 s`) by inserting two intermediate steps between each pair of neighbors at the geometric-mean ratios `2^(1/3)` and `2^(2/3)`. The full-stop reference is

```
1/8000, 1/4000, 1/2000, 1/1000, 1/500, 1/250, 1/125,
1/60, 1/30, 1/15, 1/8, 1/4, 1/2,
1, 2, 4, 8, 15, 30   (seconds)
```

so the densified ladder produces 55 entries spanning the same range. Picker rows render with conventional camera-facing labels (e.g. `1/8000, 1/6400, 1/5000, 1/4000, …, 1/30, 1/25, 1/20, 1/15, 1/13, 1/10, …, 1/2, 1/1.6, 1/1.3, 1s, 1.3s, 1.6s, 2s, 2.5s, 3s, 4s, …, 25s, 30s`) so the value matches what the photographer reads on a camera dial. The underlying canonical seconds remain the geometric-mean values; calculation continues to advance by stop-step index.

Sub-1s values render as reciprocal fractions (`1/N`, including the slow end `1/3, 1/2.5, 1/2, 1/1.6, 1/1.3`) and never carry an `s` suffix. Values at or above 1s render as integer or `N.Ns` per camera convention. Free-form numeric entry is not accepted; the picker is the only entry path.

The reserved full-stop scale (§1.4) presents the 19 full-stop values directly; that surface is currently used only for tests and reserved for a future Settings preference.

### 2.4 Snap-to-full-stop output rule

When the system computes an output shutter, the snap-to-output policy is **gated on the active exposure scale and ND step**. Snap is applied only when **both** of these conditions hold:

- the active scale is the reserved full-stop scale (§1.4); and
- the ND value lies on a whole-stop boundary.

In the shipping one-third-stop scale, neither condition holds for fractional inputs and the picker advances by 1/3 stop, so snap is **not** applied: collapsing a 1/3-stop input back onto the full-stop ladder would defeat the purpose of the finer scale. The calculated value is reported directly, formatted by the time-display rules in [UI Spec](UI.md) §2.4.

When snap does apply (the reserved full-stop scale with whole-stop ND), the system reports a value drawn from the full-stop reference scale to keep notation conventional:

- If the result falls **within the 1/8000 .. 30 s** range, it shall snap to the nearest of the 19 reference values.
- Above 30 s, the system shall step in a **power-of-two** sequence — the snapped value is the nearer of the two adjacent powers of two surrounding the calculated value (64, 128, 256, …). The sequence is not "60, 120, 240" decimal doubling: 60 s would round to 64 s, not be reported as 60 s.
- Across the 30 s boundary, the next presented value above 30 s is **64 s** (i.e. the post-30 s sequence is 30 → 64 → 128 → 256 → …). Inside the 30 s..64 s gap, the snap target is whichever of 30 or 64 is closer to the calculated value.

The "exact" calculated value (without snap) shall be retained alongside any snapped notation so that downstream timer logic uses the precise number while UI shows the conventional one. **Below 1 s** the system may use rounded reciprocal notation (e.g. "1/30") even when the exact value is, say, 0.0327. **At or above 1 s** the system shall not round the calculated value: a 2.13 s result is retained as 2.13 s when used by a timer, even if shown as "2 s" in the conventional notation.

### 2.5 Direction

ND adjustment runs forward or reverse:

- **Forward (ND as input)** — given Base Shutter and a stop count, compute Output Shutter.
- **Reverse (ND as output)** — given Base Shutter and a target Output Shutter, compute the required stop count.

Both directions use the same stop-space math.

---

## 3. Reciprocity correction (film workflow)

When a film is selected, the system shall apply the film's reciprocity profile to the ND-adjusted shutter to produce the Corrected Exposure. Reciprocity is strictly post-processing: it does not feed back into the base exposure calculation.

### 3.1 Three-layer separation

The reciprocity computation shall preserve a clean layer split:

- **Domain layer** holds the manufacturer-published table or formula plus full provenance. It shall not encode any interpolation policy.
- **Calculation policy layer** consumes domain data plus a metered exposure, applies an interpolation/extrapolation strategy (see §3.3), and produces a structured result with explicit metadata.
- **Presentation layer** consumes the result metadata and renders confidence cues, notes, and warnings. It shall not invent numbers and it shall not flatten metadata distinctions (e.g. "estimated" must not be displayed as "exact").

### 3.2 Evaluation order

For a metered exposure `t`, the policy layer shall evaluate the film's profile in the following order. Each step either produces a result and stops, or falls through.

1. **Exact table point** — if `t` matches a quantified table row exactly, return the row's corrected value with basis = `exact_table_point`.
2. **Threshold no-correction** — if the profile defines a no-correction threshold and `t` lies inside it, return `corrected = t` (no shift) with basis = `official_threshold_no_correction`.
3. **Manufacturer stop signal** — if the profile contains a stop signal at or below `t` whose severity is "not-recommended", short-circuit to advisory-only / unsupported (per the signal's policy). The signal overrides any later step.
4. **Table interpolation / extrapolation** — if `t` falls between or beyond quantified table rows and the policy allows, compute via the appropriate estimation family (see §3.3) and return with basis = `interpolated_within_table` or `extrapolated_beyond_table`.
5. **Formula** — if the profile defines an exponent formula `T_c = T_m^P` (or equivalent), apply it and return with basis = `formula_derived`. Formula evaluation shall run before generic "unsupported" fallback so films with formulas remain quantified at long exposures.
6. **Advisory / unsupported fallback** — if the metered exposure is beyond every supported region of the profile, return without a numeric corrected value: basis = `advisory_only_beyond_official_range` or `unsupported_out_of_policy_range` per the policy.

### 3.3 Estimation family selection

When the policy needs to interpolate or extrapolate:

- A profile whose adjustments are expressed as **corrected times** shall use **log-log** interpolation.
- A profile whose adjustments are expressed as **stop deltas** or **multipliers** shall use **stop-space** interpolation.

Estimation families shall not be mixed inside a single film's evaluation.

### 3.4 Threshold-to-table downward extrapolation

When a profile has a no-correction threshold whose maximum is below the first quantified table row (creating a gap between the threshold and the table), the policy shall, for metered values inside the gap, derive an extrapolated corrected value using the **first two quantified table points** as anchors. No synthetic table rows shall be created; the result is reported as `extrapolated_beyond_table` with both anchor rows recorded in `usedReferencePoints`. The downward extrapolation requires at least two quantified points to anchor; if only one is available, the result falls through to advisory-only.

### 3.5 Result shape and metadata

Every reciprocity evaluation produces a result that takes one of three mutually-exclusive forms:

- **Quantified** — a numeric corrected exposure is returned. The result carries the metered exposure, the corrected exposure (always present), and the metadata block described below.
- **Advisory-only** — no numeric corrected exposure can be returned, but the system still reports an explanation and confidence cues. The result carries the metered exposure and the metadata block; no corrected exposure is present.
- **Unsupported** — the metered exposure is outside the policy-supported range. The result carries the metered exposure and the metadata block; no corrected exposure is present.

A result form and its calculation basis are bound together: `quantified` corresponds to `exact_table_point`, `interpolated_within_table`, `extrapolated_beyond_table`, `official_threshold_no_correction`, or `formula_derived`; `advisory_only_beyond_official_range` corresponds to `advisoryOnly`; `unsupported_out_of_policy_range` corresponds to `unsupported`. The pairing is structural — it is enforced at compile time rather than checked at runtime, so a result can never claim a numeric corrected value while omitting one (or vice versa).

The metadata block, present in all three forms, carries:

- `calculationBasis` — one of: `exact_table_point`, `interpolated_within_table`, `extrapolated_beyond_table`, `official_threshold_no_correction`, `advisory_only_beyond_official_range`, `unsupported_out_of_policy_range`, `formula_derived`.
- `sourceAuthorityImpact` — derived from the profile provenance (manufacturer-published / field-tested / anecdotal).
- `rangeStatus` — within / extrapolated / threshold-only / beyond-guidance.
- `warningLevel` — none / caution / advisory / not-recommended.
- `supportingNotes` — human-readable text describing the result.
- `usedReferencePoints` — which table rows or formula coefficients informed the result.

The persistence layer shall accept both the flat-field layout (metered, corrected, an explicit returned-time flag, and the metadata block) and the three-form layout on decode; the encoder writes the three-form layout. (See [DomainSchema Spec](DomainSchema.md) §6.)

### 3.6 Reference data presentation

The reference panel surfaces the source data used by a profile. Its presentation rules are about preserving source facts, not about calculation:

- A table row that carries both a stop correction (or multiplier) and an adjusted/corrected time shall surface both. A formatter that picks one value and drops the other hides published source information from the user.
- The compact column for a row shall combine the two facts in a single cell when both exist (e.g. `+0.5 stops · 15s`). When only one form is published, that form is shown alone.
- A corrected-time value that the catalog stores as `isApproximate` (i.e. a rounded display of an irrational conversion, typically a fractional-stop derivation `metered × 2^stopDelta`) shall be visually distinguished — for example with a leading "≈" — so the user can tell rounded values from published or exactly-converted ones at a glance. Multiplier-derived corrected times (`metered × multiplier`) are exact arithmetic and are not marked.
- Development-time hints and color-filter suggestions stay as separate cells / notes rather than being folded into the calculation column. They are documentation, not calculation inputs.
- The reference panel shall not introduce new calculation policy. It is a presentation contract over data the calculation policy already consumes.
- PTIMER-88 adds a secondary-guidance formatter in the presentation layer only.
- The formatter preserves stored notation exactly (for example `5M`, `7.5M`, `2.5G`, `CC10R`, `-10% development`) and does not normalize text.
- It maps guidance into separate categories: color correction, development adjustment, warning, and note.
- Exposure-time output remains the primary calculator result; these rows are secondary guidance only.

### 3.7 Confidence presentation

The presentation layer shall map each result to one of five confidence categories:

- **Exact** — basis = `exact_table_point` or `formula_derived` with a directly published coefficient.
- **Estimated** — basis = `interpolated_within_table`.
- **Extrapolated** — basis = `extrapolated_beyond_table`. Extrapolated and estimated shall be presented as distinct categories; extrapolated shall carry a stronger low-confidence signal.
- **Advisory-only** — basis = `advisory_only_beyond_official_range` or threshold no-correction beyond the threshold band. The UI shall show calm explanatory text in place of a number; it shall not fabricate a value.
- **Unsupported** — basis = `unsupported_out_of_policy_range`. Same rule: no fabricated number.

---

## 4. Timer integration

A timer is created from the **Output Shutter** (digital workflow) or the **Corrected Exposure** (film workflow). The system shall not start a timer from a non-quantified result: when the corrected exposure is advisory-only or unsupported, the Film-mode timer-start affordance shall be disabled and the user shall be guided to either change inputs or proceed with the ND-adjusted shutter explicitly.

A timer's metadata shall be a snapshot of the calculation result at creation time. Subsequent changes to the calculator inputs shall not mutate any already-created timer. (See [Timer Spec](Timer.md) §1.)

---

## 5. Restoration across relaunches

The calculator's working context — selected film identity, **exposure scale token** (§1.4), Base Shutter, and ND value — shall be persisted and restored on relaunch in both digital and film workflows. If a stored preset identity does not resolve to any catalog entry, or if numeric values fail validation against the active scale's ladder, the system shall fall back safely to a defined default rather than crash or silently drift.

A snapshot written by an older release that predates the exposure scale token (or fractional ND) shall continue to restore correctly: missing fields shall resolve to the **shipping one-third-stop scale** (§1.4) with the integer ND value treated as a whole-stop count on the new ladder. The shipping ladder is a strict superset of the legacy full-stop ladder, so a legacy whole-stop value remains valid without rewriting it.

---

## 6. Forbidden patterns

The system shall **not**:

1. Fabricate a numeric corrected value when the result is advisory-only or unsupported.
2. Encode interpolation or extrapolation policy inside the domain model. (Domain stores manufacturer data verbatim; policy is its own layer.)
3. Mix estimation families (e.g. apply log-log to a stop-delta profile, or vice versa).
4. Ignore a manufacturer "not-recommended" stop signal in favor of generic extrapolation.
5. Round a calculated value at or above 1 s. (Rounded notation is permitted only sub-second.)
6. Allow calculator input changes to mutate already-created timer metadata.
7. Start a timer from a non-quantified corrected exposure.

---

## 7. Drift and open questions

These are unresolved or partially specified. They are recorded so the system does not silently drift further from intent.

- **Aperture and ISO** as exposure variables are intent-level (wiki 3964929) but not part of the current release. The Fixed/Derived state machine, the multi-variable linkage rules, and the reverse calculation across more than one variable are deferred.
- **Multi-derived ceiling above two.** Wiki 3964929 reserves the option to extend; no decision is recorded.
- **Per-data-shape policy selection.** Wiki 15761409 notes that not every profile shape may want log-log; some may want stop-space. Current code applies §3.3 uniformly. A per-profile override mechanism is undecided.
- **Extrapolation caps.** Quantified table extrapolation continues until a manufacturer stop signal blocks it; in the absence of a stop signal there is no upper bound. (Open: whether an implicit ceiling should exist for profiles lacking a stop signal.)
- **User-defined film schema.** Wiki 15138817 lists this as a validation requirement; the data model and UX are not specified.
- **Multi-profile films.** Some films may have multiple official profiles (different developers, push/pull). Selection rules are not yet defined; the current launch policy ships one primary profile per film identity.
- **Color and development guidance.** Profiles record these (e.g. Velvia 50 "M color correction", Tri-X dev-time adjustments) but the spec does not yet define how the calculator surfaces them.

---

## 8. Sources of intent (reference)

These are *reference material*, not normative. The spec body above
captures the user-visible contract; the citations below let a reader
trace the published research that informed it.

**Wiki (Confluence pages cited by page id)**
- 3964929 — 계산 엔진 규칙 (variables, fixed/derived state, ND policy, reciprocity application flow)
- 7438337 — 노출 스톱 스케일 관행 조사 (rounded-notation vs exact-value separation)
- 13172737 — Reciprocity Film Research List (launch scope, method keys, provenance rules)
- 15237121 — Reciprocity Table Calculation Policy Notes (separation of domain / policy / presentation)
- 15761409 — Reciprocity Table Interpolation and Calculation Policy Draft (responsibility split, metadata, policy direction)
- 15138817 — Reciprocity Validation Samples (minimum validation matrix, example profiles)
- 16482307 — Film Selection and Reciprocity Calculator UI (workflow direction, state semantics)
