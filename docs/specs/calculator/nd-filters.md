<!-- Copyright © 2026 Sangwook Han -->
<!-- SPDX-License-Identifier: Apache-2.0 -->

# ND Filters

| Prefix | Owns |
| --- | --- |
| ND | Core ND ladder, presets, and display notation |
| ND-STACK | Stack composition, the 30-stop cap, and adding a wheel |
| ND-CLEANUP | Zero-stop wheel removal, automatic and manual |
| ND-INTERACT | Commit/epoch behavior, ordering, live preview, total overlay |
| ND-A11Y | Accessibility equivalents |
| ND-PERSIST | Persistence and restore |

## Purpose

The ND control represents fixed ND filters placed in front of the camera.
A photographer may use one filter or stack up to four; exposure calculation
consumes only the stack's sum, never the individual filters.

## Current behavior

The ND input is a stack of one to four wheels, each selecting from a shared
ladder. The stack always keeps a total of 30 stops or fewer, by
construction rather than by clamping after the fact.

## Requirements

### Ladder, presets, and notation

- **ND-001** — Every wheel shall select from the same shipping ladder:
  integer stops in the closed range [0, 30], plus three fixed fractional
  commercial presets — `6.6` (ND100 / OD 2.0), `7.6` (ND200 / OD 2.3), and
  `16.6` (ND100k / OD 5.0) stops. These presets are permanent entries,
  present in every notation, spliced into the ladder in numeric order.
- **ND-002** — The ladder shall not be densified to a continuous
  one-third-stop or 0.1-stop ND scale; rows such as `7 1/3` or `7 2/3` shall
  not exist in the option set.
- **ND-003** — The system shall support exactly three display notations:
  `Stops` (default), `OD`, and `ND` (filter-factor). The active notation is
  a single, app-global, display-only setting; it shall not alter the
  canonical stops value used by exposure calculation, and per-wheel notation
  selection is not offered.
- **ND-004** — One shared formatter shall be the single source for every
  rendering of a stops value in the active notation — the ND picker's
  value/unit band and every other inline occurrence. No call site shall
  re-derive or re-round a notation string independently, and the formatter
  shall be a pure, deterministic function of (stops value, notation mode).
- **ND-005** — In `Stops` notation, a value renders as a bare
  integer/decimal with unit `stops` (e.g. `9 stops`).
- **ND-006** — In `OD` notation, a value renders as `stops × 0.3` to one
  decimal place, with the form `OD <value>` (e.g. 9 stops → `OD 2.7`).
- **ND-007** — In `ND` (filter-factor) notation, an **integer-stop** value
  renders `2^stops` through the tiered policy below.
- **ND-008** — For an integer-stop value where `2^stops < 1000` (0–9 stops),
  the exact factor renders with no unit suffix (`ND1`, `ND8`, `ND512`).
- **ND-009** — For an integer-stop value in the range `1000 ≤ 2^stops ≤
  9999` (10–13 stops), the factor renders in commercial thousands with no
  suffix (`ND1000`, `ND2000`, `ND4000`, `ND8000`).
- **ND-010** — For an integer-stop value where `2^stops ≥ 10000` (14 stops
  and above), the factor renders against the nearest power-of-two unit —
  `K` = 2^10, `M` = 2^20, `G` = 2^30 — uppercase, chosen so the exact stop
  value lands on a clean label (14→`ND16K`, 16→`ND64K`, 20→`ND1M`). A
  lowercase or significant-figure-rounded suffix (e.g. `ND20k`) shall not be
  rendered.
- **ND-011** — The three fractional presets (`6.6`/`7.6`/`16.6`) do **not**
  follow ND-007–ND-010. Their `ND`-notation label uses a fixed commercial
  mapping (`6.6 → ND100`, `7.6 → ND200`, `16.6 → ND100k`), not a `2^stops`
  computation; their `OD` label still follows ND-006 (`stops × 0.3`); their
  `Stops` label follows ND-005 like any other value.
- **ND-012** — The notation control renders as one horizontal row reading
  `ND Filter [Stops | OD | ND]`, directly associated with the ND picker
  header. All three segment labels shall remain legible and unclipped at
  the shipped column width on both platforms.
- **ND-013** — Selecting a notation segment takes effect immediately: the
  picker and every visible notation-aware text re-render in the new
  notation without a screen transition or confirmation step.

### Stack composition and the 30-stop cap

- **ND-STACK-001** — The stack shall contain between one and four wheels.
  One wheel is the normal single-filter case and behaves exactly as before
  stacking existed.
- **ND-STACK-002** — The effective ND value shall be the sum, in stops, of
  every wheel's committed value; only this sum shall be passed into
  exposure calculation.
- **ND-STACK-003** — The stack's sum shall never exceed 30 stops. Each
  wheel's selectable range is truncated to the budget remaining after the
  other wheels' committed values (`30 − sum(others)`), so an over-cap
  combination is unrepresentable through the pickers.
- **ND-STACK-004** — A selection that would exceed the cap once concurrent
  selections settle shall be rejected and the wheel reverted — never
  silently clamped.
- **ND-STACK-005** — Ladder truncation removes values from the top of the
  range first, so a wheel's currently selected row index does not shift
  because of another wheel's change.
- **ND-STACK-006** — Sibling ladders shall be recomputed only at commit
  time, never while another wheel is being actively scrolled.
- **ND-STACK-010** — A wheel may be added only while the stack holds fewer
  than four wheels and the new wheel's budget-truncated ladder contains at
  least one value greater than zero. Availability is judged on committed
  values only; an in-flight, uncommitted selection shall not change it.
- **ND-STACK-011** — Adding a wheel appends it at zero stops; the
  calculated result shall not change as a result of adding a wheel.

### Zero-stop wheel cleanup

- **ND-CLEANUP-001** — A committed zero-stop wheel in a multi-wheel stack
  is transient: it shall be removed automatically after a short idle
  interval (approximately four seconds).
- **ND-CLEANUP-002** — Automatic cleanup shall be judged at the moment it
  would fire, not at the moment it was scheduled: if any wheel is in motion
  when the interval elapses, cleanup is deferred and a full new interval is
  allowed to pass before it is reconsidered.
- **ND-CLEANUP-003** — When the sum of non-zero wheels already reaches the
  30-stop cap, remaining zero-stop wheels shall be removed immediately, with
  no idle interval — they cannot accept any non-zero value.
- **ND-CLEANUP-004** — When cleanup executes: if at least one non-zero
  wheel exists, every zero-stop wheel is removed; if every wheel is
  zero-stop, exactly one remains.
- **ND-CLEANUP-005** — A wheel holding a non-zero value shall never be
  auto-removed, and the stack shall always retain at least one wheel.
- **ND-CLEANUP-006** — Cleanup eligibility does not depend on how a
  zero-stop wheel came to be zero (freshly added vs. manually zeroed) — both
  are treated identically.
- **ND-CLEANUP-010** — A settled zero-stop wheel may also be removed
  directly through a dedicated removal gesture (an overscroll past the
  wheel's zero end, released past the threshold). The gesture shall arm
  only when the touch begins on a wheel already settled at zero; scrolling a
  wheel down to zero and removing it are always two separate touches.
- **ND-CLEANUP-011** — At most one wheel shall be removed per removal
  gesture, and the last remaining wheel shall never be removed by it.
- **ND-CLEANUP-012** — A wheel shall not be removed — by the automatic timer
  or by the gesture — while any other wheel is still actively being
  interacted with.
- **ND-CLEANUP-013** — Cleanup state (the pending timer, the armed flag) is
  transient session UI state; it is never persisted.

### Commit, ordering, and live preview

- **ND-INTERACT-001** — Several wheels may be mid-gesture at once. While any
  wheel is being touched or is still settling, the committed stack shall not
  change, no wheel shall reorder or reload, and add/remove availability
  shall not flicker under a moving finger.
- **ND-INTERACT-002** — All pending per-wheel selections commit together
  when every wheel has become quiet, applied in the order the wheels
  settled.
- **ND-INTERACT-003** — After a commit, wheels shall reorder themselves
  descending by value, zero-stop wheels last, with equal values keeping
  their existing relative order (stable sort). Each wheel shall keep a
  stable identity through the reorder — presented as that wheel visibly
  moving to its new position, not as values being reassigned to fixed
  positions.
- **ND-INTERACT-004** — Reordering shall never change the effective sum or
  the calculated result.
- **ND-INTERACT-010** — The live, in-progress result preview shall be the
  sum of each actively-moving wheel's current (uncommitted) value plus every
  other wheel's committed value.
- **ND-INTERACT-020** — While two or more wheels are stacked, a transient,
  non-blocking overlay shall show the effective total in stops (`Total N
  stops`), updating live during interaction and fading out shortly after the
  last change. At the 30-stop cap it shall read `Total 30 stops · Maximum`.
  The overlay shall never intercept touch.

### Accessibility

- **ND-A11Y-001** — Each wheel shall be exposed as an adjustable
  accessibility element identifying its position in the stack.
- **ND-A11Y-002** — "Add filter" and "Remove empty filter" shall be exposed
  as assistive-technology actions, each available only while the
  corresponding operation is actually possible (matching ND-STACK-010 and
  ND-CLEANUP-010/011 respectively) — performing "Remove empty filter" runs
  the same cleanup rule as ND-CLEANUP-004 in one action.
- **ND-A11Y-003** — The current effective total shall remain available to
  assistive technology at all times, independent of the total overlay's
  visual fade state.
- **ND-A11Y-004** — The notation selector (ND-012) shall expose each
  segment's label and selected state to assistive technology, not by color
  alone.

## Persistence

- **ND-PERSIST-001** — Each camera slot shall persist its complete committed
  ND stack.
- **ND-PERSIST-002** — On restore, a persisted stack is validated as a
  whole: wheel count in [1, 4], every value on the shipping ladder, and a
  total of 30 stops or fewer. Any violation discards the entire stack —
  never a partial recovery — and falls back to a single legacy ND value.
- **ND-PERSIST-003** — The legacy single-value field is always written
  alongside the stack, carrying the stack's strongest (maximum) wheel value,
  so a build that predates stacking degrades to one valid filter rather than
  rejecting an off-ladder sum outright.
- **ND-PERSIST-004** — A snapshot that predates the ND stack shall continue
  to restore correctly, as a single wheel holding the legacy ND value.

## Non-goals

- A user-defined physical filter inventory ("My Filters") is out of scope
  for this capability; it has not shipped. This file describes only the
  standard-ladder stack that currently exists and is not generalized in
  anticipation of a future capability's requirements — see
  `SpecificationWorkflow.md` §5.
- Restricting duplicate values across wheels in a stack; the same stop value
  may appear on more than one wheel.
- Filter classification (ND / CPL / color) or purchase recommendations.
- Per-wheel notation selection; notation stays app-global (ND-003).
- Pinch gestures and hidden long-press menus are not part of the supported
  interaction model for adding or removing a wheel.
- An alternate large-text/accessibility-size layout redesign of the wheel
  row is a separate capability; the current layout must still remain
  operable and readable at currently supported text sizes.
