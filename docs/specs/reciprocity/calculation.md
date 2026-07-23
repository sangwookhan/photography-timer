<!-- Copyright © 2026 Sangwook Han -->
<!-- SPDX-License-Identifier: Apache-2.0 -->

# Reciprocity Calculation

| Prefix | Owns |
| --- | --- |
| RECIP-CALC | Evaluation order and result forms |
| RECIP-CONF | Confidence/status presentation |

## Purpose

When a film is selected, reciprocity evaluation converts the ND-adjusted
exposure into a film-specific Corrected Exposure, where the film's published
data supports a quantified prediction.

## Current behavior

Reciprocity is strictly post-processing: it consumes the Adjusted Shutter
and never feeds back into base exposure or ND calculation.

## Requirements

### Data integrity and presentation honesty

- **RECIP-CALC-001** — Manufacturer-published data and its provenance are
  never altered or reinterpreted by calculation: a profile's rules and
  source facts are consumed as published, and a result is always traceable
  back to the specific rule and data that produced it.
- **RECIP-CALC-002** — Presentation never invents a numeric value: a result
  the calculation marks as non-quantified is never displayed as a number,
  and status/badge text always reflects the calculation's own result form
  (§ Result forms) rather than a separately-decided presentation guess.

### Evaluation order

- **RECIP-CALC-010** — For a metered exposure and an active profile, the
  policy shall evaluate, in order, stopping at the first that applies: a
  formula rule; a table-interpolation rule; a standalone no-correction
  threshold; a limited-guidance rule; otherwise, unsupported.
- **RECIP-CALC-011** — A formula rule shall return the identity (corrected
  = metered) at or below its no-correction boundary; a quantified,
  formula-derived result within its source range; and, above the source
  range, a numeric continuation reclassified as beyond-source-range rather
  than suppressed.
- **RECIP-CALC-012** — A table-interpolation rule shall return the identity
  at or below its no-correction boundary; a quantified, table-derived
  result — piecewise-linear in log–log space, reproducing every published
  anchor exactly — within its published range; and, above the last anchor,
  a numeric continuation (extrapolated from the final log–log segment)
  reclassified as beyond-source-range.
- **RECIP-CALC-013** — A limited-guidance rule, when it applies to the
  metered exposure, shall return a non-quantified result with no numeric
  corrected exposure.
- **RECIP-CALC-014** — The source/fitting-range boundary (on a formula or a
  table rule) is a confidence boundary, not a calculation hard stop: a
  formula or table keeps producing a numeric value past it, presented as
  outside the manufacturer's supported range rather than suppressed.
- **RECIP-CALC-015** — **Correction invariant**: a reciprocity correction
  shall never shorten the exposure below the metered value. Any evaluation
  path that would yield a corrected value shorter than the metered value is
  replaced by the identity.
- **RECIP-CALC-016** — A user-defined custom profile (see
  `reciprocity/custom-profiles.md`) flows through the same evaluation order
  and the same routing above as a preset profile; the calculation does not
  distinguish a custom profile from a preset one, only its provenance
  differs for presentation.

### Result forms

- **RECIP-CALC-020** — Every evaluation produces exactly one of three
  mutually exclusive forms: **quantified** (a numeric corrected exposure,
  basis one of no-correction / formula-derived / table-derived);
  **limited-guidance** (no numeric value, guidance text only); or
  **unsupported** (outside the supported range; may optionally carry a
  numeric continuation past the range, marked as such). A result can never
  claim a numeric value while lacking one, or vice versa, except the
  explicitly allowed unsupported-with-continuation case.
- **RECIP-CALC-021** — Every result carries: a calculation basis; a
  source-authority impact (derived from profile provenance); a range status
  (within range / beyond last representative point / beyond policy limit);
  a warning level (none / note / caution / strong warning); and free-form
  notes.
- **RECIP-CALC-022** — Reciprocity evaluation shall be deterministic: the
  same profile and metered value always produce the same result form,
  corrected value, and status.

## Confidence / status presentation

- **RECIP-CONF-001** — Every result shall map to one of these user-facing
  categories, and no other primary status wording shall surface (in
  particular not `Exact` / `Estimated` / `Interpolated` /
  `Extrapolated` / `Advisory`, which encoded a retired model):
  - **No correction** — corrected equals metered.
  - **Formula-derived** / **Table-derived** — a quantified result on the
    active formula curve or interpolated from a table in log–log space,
    respectively.
  - **Custom formula** / **Custom table** — the same two calculation
    bases, badged distinctly only when the active profile is user-defined
    (`reciprocity/custom-profiles.md`); an official or unofficial-source
    profile with the same calculation basis reads as plain
    **Formula-derived** / **Table-derived** — the badge text itself does
    not distinguish official from unofficial (or archival) source
    authority.
  - **Beyond source range** — a numeric continuation from a converted
    formula or a table-log-log model, past its supported boundary.
  - **Outside guidance** — a numeric continuation that is none of the
    above.
  - **No quantified prediction** — limited-guidance, no number.
  - **No corrected value** — unsupported, with no numeric continuation
    available at all.

  Source authority (official / unofficial / archival / user-defined) is
  never encoded as a distinct badge-text variant beyond the
  formula-vs-table/custom-vs-not split above; it is instead communicated
  through separate surfaces — the model/profile label, an unofficial-source
  caveat, and the Source metadata (`reciprocity/details-and-guidance.md`)
  — never by adding new primary status wording.
- **RECIP-CONF-002** — Badge tone shall follow calculation status, not
  source authority: **No correction** always uses the success tone,
  regardless of source; **Formula-derived** / **Table-derived** in-range
  results use the normal (non-warning) tone and are not downgraded merely
  for being unofficial, app-derived, or lower-confidence; **Beyond source
  range** uses the warning tone; **No quantified prediction** and
  unsupported use the limited/unsupported tone. Source authority is
  communicated separately (see `reciprocity/details-and-guidance.md`), never
  through badge color.

## Non-goals

- A profile-independent ceiling capping how far a formula or table
  continuation may extend past its source range is not currently defined.
- Selection among multiple official profiles for one film (different
  developers, push/pull variants) is not currently specified; the launch
  catalog ships one primary profile per identity.
