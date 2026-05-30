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

The Corrected Exposure row shall remain visible in all film-workflow states, including states where it carries non-quantified guidance. (See §3.3 for what "non-quantified" means.)

### 1.4 Exposure scale mode

The calculator runs on an **exposure scale** that defines the granularity of one Base Shutter increment. The current shipping scale is **one-third stop**: Base Shutter advances in 1/3-stop increments along a densified ladder with conventional camera-facing labels (§2.3). One-third-stop applies to the **Base Shutter ladder only** — the ND picker stays whole-stop in every shipping mode (§2.2).

The model layer also retains a **full-stop** scale (1-stop shutter, same whole-stop ND) as a reserved abstraction. The full-stop scale shall not surface in the main calculator UI in the current release; it remains in the model so:

- the model layer keeps a single ladder-aware abstraction rather than splitting "the shipping scale" from "everything else";
- regression tests can validate full-stop math directly;
- a future Settings preference (Full / 1/2 / 1/3 stop) can swap the active scale without redesigning the calculator domain.

The fractional-aware `NDStep` domain primitive (with integer `thirdStopCount` round-trip) is likewise retained as **reserved domain infrastructure**, not a shipping ND option. It exists so a future custom or variable-ND workflow can flow through the same calculation and persistence path; the shipping ND picker shall not enumerate fractional ND values.

Until those future preferences exist, the user shall not see a runtime control for the active scale. Persistence still records the active scale token (§5) so when a future preference ships, an upgrade carries the user's prior choice rather than overwriting it on first launch.

### 1.5 Active-slot scoping of calculator inputs

The calculator's inputs — workflow mode (digital vs. film), selected film and active reciprocity profile, Base Shutter, ND, exposure scale mode, and the most recently derived reciprocity result — are scoped to the **active camera slot**. A shooting session may carry multiple slots ([Requirements](../requirements/Requirements.md) §3.8); at any moment exactly one slot is active and its inputs drive the calculator surface and any timer that starts from the result section.

Switching the active slot replaces the input set rather than mutating it:

- The departing slot's calculator state is preserved as that slot's own state — film, base shutter, ND, scale, and reciprocity result are kept untouched.
- The arriving slot's previously-stored state becomes the calculator's active inputs, and the result section recomputes against those inputs.
- A slot that has never been visited arrives with the same defaults a fresh app launch would expose; visiting it does not consume any state from another slot.

A switch shall not invoke any "reset" or "clear" path on the calculator, the film selection, or the reciprocity result. Slots are independent: a calculator input mutation made on the active slot — moving Base Shutter, changing ND, picking a different film, swapping profiles — shall affect only the active slot's state.

The above rules describe input scoping only. Calculation policy (§2 and §3) is unchanged: every slot evaluates its own inputs against the same exposure math and the same reciprocity policy.

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

- **Domain layer** holds the manufacturer-published threshold, formula, and limited-guidance rules plus full provenance, and (display-only) source-evidence rows. It shall not encode any calculation policy.
- **Calculation policy layer** consumes domain data plus a metered exposure and produces a structured result with explicit metadata. Source-evidence rows are display-only and are intentionally invisible to the policy layer.
- **Presentation layer** consumes the result metadata and renders status / badge text, confidence cues, notes, and warnings. It shall not invent numbers and it shall not flatten metadata distinctions.

### 3.2 Evaluation order

For a metered exposure `t`, the policy layer shall evaluate the film's profile in the following order. Each step either produces a result and stops, or falls through.

1. **Formula rule** — if the profile defines a formula rule, evaluate the shared `ReciprocityFormula` (`Tc = a × (Tm / Tref)^p + b`) at `t`. The formula owns its own guards:
   - `t ≤ noCorrectionThroughSeconds` → return `corrected = t` with basis = `officialThresholdNoCorrection`.
   - Otherwise the formula's `evaluate(...)` returns one of: `withinSourceRange(corrected)`, `beyondSourceRange(corrected)`, `invalidInput`, `invalidFormula`, `formulaOutputUnusable`, `unsafeShorteningFormula`. The policy routes those to:
     - `withinSourceRange` → `formulaDerived` (corrected exposure attached);
     - `beyondSourceRange` → `unsupportedOutOfPolicyRange` carrying the numeric continuation (the value is a formula prediction past `sourceRangeThroughSeconds` and is presented as outside manufacturer guidance);
     - `invalidInput` → `unsupportedOutOfPolicyRange` describing the bad metered input;
     - `invalidFormula` → `unsupportedOutOfPolicyRange` describing the parameter-contract failure (PTIMER-84 custom formulas use this distinct case);
     - `formulaOutputUnusable` → `unsupportedOutOfPolicyRange` describing the runtime arithmetic failure;
     - `unsafeShorteningFormula` → handoff to `officialThresholdNoCorrection` with `corrected = t` (universal safety net so a reciprocity correction never shortens the shutter).
2. **Table-interpolation rule** — if the profile defines a table-interpolation rule, evaluate it at `t`. The rule converts a manufacturer reciprocity *table* (published metered→corrected anchors) into a corrected exposure by piecewise-linear interpolation in **log10–log10** space, so interpolation passes through every published anchor exactly. The rule owns its own guards:
   - `t ≤ noCorrectionThroughSeconds` → return `corrected = t` with basis = `officialThresholdNoCorrection`.
   - `t` within the published range → basis = `tableLogLogDerived` (corrected exposure attached).
   - `t` above the last anchor (`sourceRangeThroughSeconds`) → the rule keeps computing by extrapolating the last log-log segment and the result is reclassified to `unsupportedOutOfPolicyRange` carrying the numeric continuation (presented as beyond the published source range). It does **not** dead-end — a value-less unsupported result is reserved for genuinely uncomputable input.
   - invalid input / malformed anchors → `unsupportedOutOfPolicyRange` with no corrected exposure.

   Fomapan 100 Classic is the representative table-model profile (official FOMA rows 1s→2s, 10s→80s, 100s→1600s). Its app-derived power-law formula is retained as a non-default, clearly-labelled alternate model, not the official default.
3. **Threshold no-correction** — for profiles that still carry a standalone threshold rule (the limited-guidance shape), if `t` lies inside the threshold band return `corrected = t` with basis = `officialThresholdNoCorrection`.
4. **Limited guidance** — if the profile defines a limited-guidance rule whose `appliesWhenMetered` covers `t` (or is open-ended), return `limitedGuidanceNoQuantifiedPrediction`. No numeric corrected exposure.
5. **Unsupported fallback** — if no rule applies, return `unsupportedOutOfPolicyRange` with no corrected exposure.

`sourceRangeThroughSeconds` is a **source / fitting confidence boundary**, not a calculation hard stop — every formula keeps producing a numeric value past it (subject to the runtime safety check above), and the result is reclassified to the beyond-source presentation rather than suppressed.

The `unsafeShorteningFormula` handoff in step 1 is the universal **correction invariant**: a corrected exposure shorter than the metered value is replaced by the identity. A reciprocity correction can never shorten the adjusted shutter; the safety net keeps that guarantee even when a formula's curve bleeds across its no-correction boundary.

User-defined custom profiles ([DomainSchema Spec](DomainSchema.md) §13.4) flow through the same evaluation order, the same shared `ReciprocityFormula` value, and the same routing table above — `formulaDerived` inside the source range, `unsupportedOutOfPolicyRange` carrying a numeric continuation past `sourceRangeThroughSeconds`, `officialThresholdNoCorrection` at or below `noCorrectionThroughSeconds`, and `unsafeShorteningFormula` short-circuited to the identity. The calculation policy does not distinguish a user-defined profile from a preset formula profile at evaluation time; the difference is carried in `sourceAuthorityImpact` so presentation can keep user-defined data visually distinct from manufacturer-published data without altering the math.

### 3.3 Result shape and metadata

Every reciprocity evaluation produces a result that takes one of three mutually-exclusive forms:

- **Quantified** — a numeric corrected exposure is returned. The result carries the metered exposure, the corrected exposure, and the metadata block described below. Basis is `officialThresholdNoCorrection`, `formulaDerived`, or `tableLogLogDerived`.
- **Limited-guidance** — no numeric corrected exposure can be returned, but the system reports the metered exposure and the metadata block. Basis is `limitedGuidanceNoQuantifiedPrediction`. The presentation layer renders calm guidance text in place of a number.
- **Unsupported** — the metered exposure is outside the policy-supported range. The result carries the metered exposure and the metadata block. Basis is `unsupportedOutOfPolicyRange`. An optional corrected exposure is present only when a formula- or table-backed profile produced a numeric continuation past its supported boundary; the presenter marks such values as outside manufacturer guidance.

The pairing of form and basis is structural — it is enforced at compile time rather than checked at runtime, so a result can never claim a numeric corrected value while omitting one (with the single allowed exception of the unsupported case above carrying a formula- or table-derived numeric continuation outside the supported range).

The metadata block, present in all three forms, carries:

- `calculationBasis` — one of: `officialThresholdNoCorrection`, `formulaDerived`, `tableLogLogDerived`, `limitedGuidanceNoQuantifiedPrediction`, `unsupportedOutOfPolicyRange`.
- `sourceAuthorityImpact` — derived from the profile provenance (current official / archival official / unofficial secondary / user-defined).
- `rangeStatus` — `withinStatedRange`, `beyondLastRepresentativePoint`, or `beyondPolicyLimit`.
- `warningLevel` — `none`, `note`, `caution`, or `strongWarning`.
- `notes` — array of token-tagged human-readable strings.

### 3.4 Reference data presentation

The reference panel surfaces the source data attached to a profile. Its presentation rules are about preserving source facts, not about calculation:

- A source-evidence row that carries both a stop correction (or multiplier) and an adjusted/corrected time shall surface both. A formatter that picks one value and drops the other hides published source information from the user.
- The compact column for a row shall combine the two facts in a single cell when both exist (e.g. `+0.5 stops · 15s`). When only one form is published, that form is shown alone.
- A corrected-time value that the catalog stores as `isApproximate` (a rounded display of an irrational conversion, typically a fractional-stop derivation `metered × 2^stopDelta`) shall be visually distinguished — for example with a leading "≈" — so users can tell rounded values from published or exactly-converted ones at a glance. Multiplier-derived corrected times (`metered × multiplier`) are exact arithmetic and are not marked.
- Source-evidence rows marked `isSourceEvidenceOnly` are preserved as published evidence but rendered with a `*` footnote marker so users can tell the row is not used as a formula-fitting anchor (ADOX CMS 20 II's sub-1s reference is the canonical case).
- Development-time hints and color-filter suggestions stay as separate cells / notes rather than being folded into the corrected-exposure column. They are documentation, not calculation inputs.
- The reference panel shall not introduce new calculation policy. It is a presentation contract over data the calculation policy already consumes (threshold + limited-guidance rules) or intentionally ignores (source-evidence rows).
- The PTIMER-88 secondary-guidance formatter lives in the presentation layer only. It preserves stored notation exactly (for example `5M`, `7.5M`, `2.5G`, `CC10R`, `-10% development`) and maps guidance into separate categories: color correction, development adjustment, warning, and note. Exposure-time output remains the primary calculator result; these rows are secondary guidance only.

### 3.5 Confidence presentation

The presentation layer maps each result to one of four confidence categories:

- **No correction** — basis = `officialThresholdNoCorrection`. The corrected exposure equals the metered exposure. User-facing label: `No correction`.
- **Formula-derived** — basis = `formulaDerived`. The result is anchored on the active calculation curve. User-facing label: `Formula-derived` for preset profiles; `Custom formula` when the active profile is user-defined ([DomainSchema Spec](DomainSchema.md) §13.4), so a normal custom-profile result reads as a method/authority statement rather than the warning copy reserved for converted formula profiles.
- **Table-derived** — basis = `tableLogLogDerived`. The result is interpolated from a manufacturer reciprocity table in log-log space (Fomapan 100's official model). User-facing label: `Table-derived`; the Details model summary reads the calculation method as `Log-log table interpolation` — never a bare "lookup".
- **Limited guidance** — basis = `limitedGuidanceNoQuantifiedPrediction`. User-facing label: `No quantified prediction`. The UI shall show calm explanatory text in place of a number; it shall not fabricate a value.
- **Unsupported** — basis = `unsupportedOutOfPolicyRange`. User-facing label depends on the active profile and whether a numeric continuation outside the supported range is available: `Beyond source range` for converted preset formula profiles (formula rule with sourceEvidence), for the official log-log table model past its published anchors, and for user-defined custom formula profiles past their `sourceRangeThroughSeconds`; `Outside guidance` for a numeric continuation that is none of those; `No corrected value` when no value at all is available.

The category and badge wording shall not surface `Exact`, `Estimated`, `Interpolated`, `Extrapolated`, or `Advisory` as primary status / badge text on launch preset reciprocity presentation; those terms encoded the legacy table model and are not part of the current vocabulary.

### 3.6 Target Shutter comparison (optional, post-reciprocity)

Target Shutter is an optional workflow that compares a photographer-supplied target duration against the calculator's current result. It is layered on top of the calculation policy (§2) and the reciprocity policy (§3.1–§3.5); enabling, disabling, or editing the target shall not feed back into either policy or alter any committed result.

**Comparison basis.** Selection is determined by workflow:

- **Non-film workflow** — the comparison value is the Adjusted Shutter.
- **Film workflow with a quantified corrected exposure** — the comparison value is the Corrected Exposure.
- **Film workflow without a quantified corrected exposure** (limited-guidance or unsupported, §3.3) — no comparison value is available.

**Stop-difference reporting.** When a comparison value is available, the system shall report the stop difference between the target duration and the comparison value. The displayed stop difference is rounded to the app's stop-display granularity. Differences that round to zero are presented as a *match* form rather than as a signed zero. The system shall not fabricate a stop difference when no comparison value is available; in that case the row surfaces a calm unavailable indicator while the target itself remains visible.

**Target stability.** The target duration shall remain fixed while base shutter, ND, film selection, or reciprocity policy results change; only the comparison value updates. Editing the target is the only way to mutate it.

**Per-slot scoping.** Target Shutter state is scoped to the active camera slot on the same terms as other calculator inputs (§1.5). Switching the active slot replaces the target along with the rest of the slot's inputs; an inactive slot's stored target shall not surface on another slot.

---

## 4. Timer integration

A timer is created from the **Output Shutter** (digital workflow), the **Corrected Exposure** (film workflow), or the **Target Shutter** (when set, §3.6). The system shall not start a timer from a limited-guidance corrected exposure: when the result is `limitedGuidanceNoQuantifiedPrediction`, or `unsupportedOutOfPolicyRange` without a numeric continuation, the Film-mode corrected-exposure timer affordance shall be disabled and the user shall be guided to either change inputs or proceed with the ND-adjusted shutter explicitly. An unsupported result that carries a numeric continuation outside the supported range (a formula prediction, or a table-derived extrapolation past the published anchors) does enable the timer with a warning treatment so the user can still commit to the predicted value. A Target-Shutter-started timer's duration is the target itself, independent of the comparison value or its availability.

A timer's metadata shall be a snapshot of the calculation result at creation time. Subsequent changes to the calculator inputs shall not mutate any already-created timer. A timer's exposure source remains distinguishable across its lifetime — a Target-Shutter timer remains a Target-Shutter timer regardless of later input changes. (See [Timer Spec](Timer.md) §1.4.)

---

## 5. Restoration across relaunches

The calculator's working context — selected film identity, **exposure scale token** (§1.4), Base Shutter, ND value, and Target Shutter duration (§3.6) when set — shall be persisted and restored on relaunch in both digital and film workflows. The working context is scoped per camera slot (§1.5): every slot's state is preserved, the active-slot id is preserved, and the on-disk shape of the multi-slot session is described in [DomainSchema Spec](DomainSchema.md) §7.4. If a stored preset identity does not resolve to any catalog entry, or if numeric values fail validation against the active scale's ladder, the system shall fall back safely to a defined default rather than crash or silently drift.

A snapshot written by an older release that predates the exposure scale token (or fractional ND) shall continue to restore correctly: missing fields shall resolve to the **shipping one-third-stop scale** (§1.4) with the integer ND value treated as a whole-stop count on the new ladder. The shipping ladder is a strict superset of the legacy full-stop ladder, so a legacy whole-stop value remains valid without rewriting it. A snapshot written by a release that predates the multi-slot session shall similarly continue to restore correctly: the legacy single-context shape is read at first launch after upgrade and the next save writes the multi-slot session shape (see [DomainSchema Spec](DomainSchema.md) §7.4.1).

---

## 6. Forbidden patterns

The system shall **not**:

1. Fabricate a numeric corrected value when the result is limited-guidance, or unsupported without a numeric continuation. Numeric continuations outside the supported range (formula predictions or table-derived extrapolations) are permitted and presented as outside manufacturer guidance.
2. Encode calculation policy inside the domain model. (Domain stores manufacturer data verbatim; policy is its own layer.)
3. Promote source-evidence rows (display reference data) into calculation anchors.
4. Allow a reciprocity correction to shorten the adjusted shutter. Any rule path that would yield `corrected < metered` is reclassified to `officialThresholdNoCorrection` (§3.2 correction invariant).
5. Round a calculated value at or above 1 s. (Rounded notation is permitted only sub-second.)
6. Allow calculator input changes to mutate already-created timer metadata.
7. Start a timer from a limited-guidance corrected exposure, or from an unsupported result with no numeric continuation.
8. Fabricate a Target Shutter stop difference when the active workflow has no quantified comparison value. The row shall surface a calm unavailable indicator instead.
9. Present a signed-zero Target Shutter stop difference; differences that round to zero shall collapse to the *match* form (§3.6).
10. Surface `Exact`, `Estimated`, `Interpolated`, `Extrapolated`, or `Advisory` as primary user-facing status / badge wording on launch preset reciprocity presentation.

---

## 7. Drift and open questions

These are unresolved or partially specified. They are recorded so the system does not silently drift further from intent.

- **Aperture and ISO** as exposure variables are intent-level (wiki 3964929) but not part of the current release. The Fixed/Derived state machine, the multi-variable linkage rules, and the reverse calculation across more than one variable are deferred.
- **Multi-derived ceiling above two.** Wiki 3964929 reserves the option to extend; no decision is recorded.
- **Outside-source-range prediction caps.** A formula (or the log-log table model) with a `sourceRangeThroughSeconds` boundary keeps producing a numeric continuation past it (the boundary is a source/fitting confidence marker, not a hard stop). Whether a profile-independent ceiling should cap how far that continuation extends is open.
- **User-defined table input.** User-defined *formula* profiles are implemented and evaluated through the shared guarded formula path described in §3.2 ([DomainSchema Spec](DomainSchema.md) §13.4). A future user-defined *table* workflow — multi-row reference tables and point fitting as a custom calculation model — is outside the launch preset scope and would need its own feature design.
- **Multi-profile films.** Some films may have multiple official profiles (different developers, push/pull). Selection rules are not yet defined; the current launch policy ships one primary profile per film identity.
- **First-class color / development policy.** Profiles record these as source-evidence adjustments (e.g. Velvia 50 `5M`, Tri-X 400 `-10% development`) but the spec does not yet define how the calculator promotes them beyond display.

---

## 8. Sources of intent (reference)

These are *reference material*, not normative. The spec body above
captures the user-visible contract; the citations below let a reader
trace the published research that informed it.

**Wiki (Confluence pages cited by page id)**
- 3964929 — 계산 엔진 규칙 (variables, fixed/derived state, ND policy, reciprocity application flow)
- 7438337 — 노출 스톱 스케일 관행 조사 (rounded-notation vs exact-value separation)
- 13172737 — Reciprocity Film Research List (launch scope, method keys, provenance rules)
- 15237121 — Reciprocity Table Calculation Policy Notes (historical: documented the table-interpolation policy superseded by PTIMER-128 / PTIMER-140's formula-based prediction model)
- 15761409 — Reciprocity Table Interpolation and Calculation Policy Draft (historical: same status as 15237121)
- 15138817 — Reciprocity Validation Samples (minimum validation matrix, example profiles)
- 16482307 — Film Selection and Reciprocity Calculator UI (workflow direction, state semantics)
