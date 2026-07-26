<!-- Copyright © 2026 Sangwook Han -->
<!-- SPDX-License-Identifier: Apache-2.0 -->

# Exposure Calculator

## Purpose

The calculator converts a camera-metered Base Shutter and an ND value into
the shutter duration the photographer should use, in stop-space arithmetic.
Film reciprocity is applied afterward and is specified separately in
`reciprocity/calculation.md`.

## Current behavior

The current release scope covers two of the model's four possible exposure
variables — Shutter and ND. Aperture and ISO are out of scope for the
current release (see Non-goals).

## Requirements

### Domain model

- **EXPOSURE-001** — The system shall maintain two distinct shutter values:
  Base Shutter (the metered exposure, before any adjustment) and Output
  Shutter (the value after ND adjustment and, when a film is selected,
  reciprocity correction). Timer creation shall use the Output Shutter (or,
  in film workflow, the further-corrected value); Base Shutter is never used
  directly to start a timer.
- **EXPOSURE-002** — Workflow mode shall be determined entirely by film
  selection state, with no separate mode toggle: no film selected is digital
  workflow (the ND-adjusted Output Shutter is the final shooting value,
  reciprocity inactive); a film selected is film workflow (the
  reciprocity-corrected exposure becomes the primary shooting value).
- **EXPOSURE-003** — In film workflow, the Corrected Exposure row shall
  remain visible in every state, including states that carry non-quantified
  guidance rather than a number.
- **EXPOSURE-004** — A Clear action removes the film selection (returning
  to digital workflow) without altering Base Shutter or ND. It lives on the
  calculator screen's own header/mode strip, not inside the film picker
  sheet, and does not appear when no film is already selected.

### Stop-based math

- **EXPOSURE-010** — All exposure adjustment shall be computed in stop space
  (base-2 logarithmic): `output_seconds = base_seconds × 2^stops`.
- **EXPOSURE-011** — ND adjustment shall support both directions: forward
  (given Base Shutter and a stop count, compute Output Shutter) and reverse
  (given Base Shutter and a target Output Shutter, compute the required stop
  count). Both directions shall use the same stop-space math.
- **EXPOSURE-012** — The system shall reject calculation inputs that would
  produce a non-finite result (overflow / NaN), surfacing a typed failure
  rather than a number that could mislead.

### Base Shutter values

- **EXPOSURE-020** — Base Shutter shall be entered only from a fixed
  one-third-stop densified ladder (55 entries spanning 1/8000 s to 30 s),
  rendered with conventional camera-facing labels: sub-1 s values as
  reciprocal fractions (never carrying an "s" suffix), values at or above
  1 s as integer or decimal seconds. Free-form numeric entry shall not be
  accepted.
- **EXPOSURE-021** — The calculated (precise) output value and the
  displayed (conventional) notation shall be kept distinct: below 1 s the
  system may show rounded reciprocal notation while retaining the exact
  value for timer use; at or above 1 s the calculated value shall not be
  rounded for timer use even though the display may show a conventional
  form.

### Snap-to-full-stop rule

- **EXPOSURE-030** — In the shipping one-third-stop exposure scale, no
  snapping to a coarser ladder shall occur; the calculated value is reported
  directly. No other exposure scale is user-facing in the current release
  (see Non-goals).

### Timer eligibility

- **EXPOSURE-040** — In digital workflow, a Start Timer action is available
  whenever the calculator holds a quantified result with a positive, finite
  duration.
- **EXPOSURE-041** — In film workflow, Start Timer eligibility on the
  Corrected Exposure follows the reciprocity result form
  (`reciprocity/calculation.md`): disabled with a guidance hint for a
  non-quantified result with no numeric continuation; enabled, with a
  warning-toned treatment, for a result carrying a numeric continuation
  outside the supported range.
- **EXPOSURE-042** — Changing calculator inputs after a timer has started
  shall not mutate that already-created timer.

### Duration display

- **EXPOSURE-060** — A calculated duration displays through one shared
  hierarchy by range: under 1 s, reciprocal notation when conventional
  (e.g. `1/30`), decimal otherwise; 1 s up to 60 s, seconds with adaptive
  precision; 60 s up to 1 hour, `MM:SS`; 1 hour up to 1 day, `HH:MM:SS`; at
  or above 1 day, a day-scale presentation.
- **EXPOSURE-061** — At the day-scale boundary, calculator result rows
  (both workflows) and the Reciprocity Details current-result card share
  one coarsened bucket policy, not a raw day count, so the primary value
  isn't dominated by sub-day noise: 1–29 days shows a plain day count
  (e.g. `29d`); 30–364 days coarsens to whole months, with a
  remainder-day suffix when non-zero (e.g. `≈1mo`, `≈12mo 25d`); 365 days
  and above coarsens to whole years only, with no day-level remainder
  (e.g. `≈68y`). Month/year buckets use fixed 30-day/365-day
  approximations and are marked with a leading `≈` since they don't align
  to calendar months. Reciprocity Details does not use a separate,
  more-precise formatter for this value — it renders the identical
  coarse string as the calculator result row. A running timer's own
  countdown display uses a different, uncoarsened formatter instead: a
  year/month/day-plus-clock decomposition that omits any zero-value
  larger unit (e.g. a 388-day-remaining timer reads `1y 23d HH:MM:SS`,
  never a flat day count), so a timer reader can verify the exact
  remaining time down to the second. Ranges under 1 day are unaffected by
  either distinction.
- **EXPOSURE-062** — Between 60 s and 1 day, the primary duration is
  accompanied by a subdued whole-seconds comparison on the same row (e.g.
  `24:40` with `1480s`), so a long exposure can be checked against
  manufacturer source rows that are usually published in seconds. Under
  60 s, no seconds comparison is shown (the primary value already reads as
  concise seconds); at or above 1 day, the seconds comparison is hidden (a
  raw seconds count stops being a useful comparison at that scale).
- **EXPOSURE-063** — The displayed (notation) value and the calculated
  (precise) value remain distinct internally (see EXPOSURE-021); downstream
  timer logic always uses the precise value.

## Persistence

- **EXPOSURE-050** — The selected film identity, Base Shutter, ND, and
  exposure scale token are part of each camera slot's persisted state (see
  `shooting/camera-slots.md`).
- **EXPOSURE-051** — On restore, a persisted film id that no longer matches
  any catalog entry drops the selection and falls back to digital workflow,
  rather than crashing or fabricating a film identity. A persisted
  reciprocity-profile override that no longer resolves drops silently and
  the film's primary profile is used instead.
- **EXPOSURE-052** — On restore, Base Shutter and ND values are sanitized
  against the active exposure scale's ladders; an out-of-range or
  unresolvable value falls back to the shipping default rather than
  crashing or silently drifting.
- **EXPOSURE-053** — A snapshot written before the exposure-scale token
  existed continues to restore correctly, defaulting to the shipping
  one-third-stop scale.

## Non-goals

- Aperture and ISO as exposure variables, and the associated Fixed/Derived
  multi-variable state machine, are out of scope for the current release.
- Free-form numeric entry for Base Shutter or ND is not supported; the
  picker ladders are the only entry path.
- A user-facing exposure-scale selector (Full / 1/2 / 1/3 stop). The
  shipping calculator runs only on the one-third-stop scale (EXPOSURE-030);
  a reserved full-stop scale is not user-facing in the current release and
  is not asserted as current behavior here.
