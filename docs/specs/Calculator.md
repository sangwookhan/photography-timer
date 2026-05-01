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

---

## 2. Stop-based exposure math

### 2.1 Unit

All exposure adjustment math is performed in **stop space** (base-2 logarithmic). One stop represents a factor-of-two change in light. Internally, ND values are integer stops; shutter targets are computed as

```
output_seconds = base_seconds × 2^stops
```

Inputs that arrive in factor form (e.g. ND 64×) shall be converted to stops before entering the calculator.

### 2.2 ND input range

ND stops are integers in the closed range **[0, 30]**. The picker shall present this range; values outside it shall not be representable.

### 2.3 Base shutter values

The Base Shutter picker shall present the **19 full-stop standard speeds**:

```
1/8000, 1/4000, 1/2000, 1/1000, 1/500, 1/250, 1/125,
1/60, 1/30, 1/15, 1/8, 1/4, 1/2,
1, 2, 4, 8, 15, 30   (seconds)
```

These are the values marked on analog camera shutter dials. There is no 1/3-stop input mode.

### 2.4 Snap-to-full-stop output rule

When the system computes an output shutter, it shall report a value drawn from the same stop-aligned reference scale to keep notation conventional:

- If the result falls **within the 1/8000 .. 30 s** range, it shall snap to the nearest of the 19 reference values.
- Above 30 s, the system shall step in a **power-of-two** sequence — the snapped value is the nearer of the two adjacent powers of two surrounding the calculated value (64, 128, 256, …). The sequence is not "60, 120, 240" decimal doubling: 60 s would round to 64 s, not be reported as 60 s.
- Across the 30 s boundary, the next presented value above 30 s is **64 s** (i.e. the post-30 s sequence is 30 → 64 → 128 → 256 → …). Inside the 30 s..64 s gap, the snap target is whichever of 30 or 64 is closer to the calculated value.

The "exact" calculated value (without snap) shall be retained alongside the snapped notation so that downstream timer logic uses the precise number while UI shows the conventional one. **Below 1 s** the system may use rounded reciprocal notation (e.g. "1/30") even when the exact value is, say, 0.0327. **At or above 1 s** the system shall not round the calculated value: a 2.13 s result is retained as 2.13 s when used by a timer, even if shown as "2 s" in the conventional notation.

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

### 3.6 Confidence presentation

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

The calculator's working context — selected film identity, Base Shutter, and ND stops — shall be persisted and restored on relaunch in both digital and film workflows. If a stored preset identity does not resolve to any catalog entry, or if numeric values fail validation, the system shall fall back safely to a defined default rather than crash or silently drift.

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

