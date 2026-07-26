<!-- Copyright © 2026 Sangwook Han -->
<!-- SPDX-License-Identifier: Apache-2.0 -->

# Target Shutter

## Purpose

Target Shutter lets a photographer enter a desired final exposure duration
and compare it against the calculator's current result, without altering
exposure or reciprocity calculation.

## Current behavior

Target Shutter is optional and scoped to the active camera slot. It sits on
top of the calculator and reciprocity results; enabling, disabling, or
editing it never feeds back into either.

## Requirements

### Comparison basis

- **TARGET-001** — The system shall support an optional Target Shutter
  comparing a photographer-entered duration against the calculator's current
  result.
- **TARGET-002** — In digital workflow, the comparison value shall be the
  Adjusted Shutter. In film workflow with a quantified Corrected Exposure,
  the comparison value shall be the Corrected Exposure. In film workflow
  without a quantified Corrected Exposure, no comparison value shall be
  available.
- **TARGET-003** — The system shall not fabricate a stop difference when no
  comparison value is available; the row shall surface a calm unavailable
  indicator while the target itself remains visible.

### Stop-difference reporting

- **TARGET-010** — When a comparison value is available, the system shall
  report the stop difference between the target and the comparison value,
  rounded to the app's stop-display granularity.
- **TARGET-011** — A difference that rounds to zero shall be presented as a
  match, not as a signed zero.

### Target stability and scope

- **TARGET-020** — The target duration shall remain fixed while base
  shutter, ND, film selection, or reciprocity results change; only editing
  the target shall mutate it.
- **TARGET-021** — Target Shutter state shall be scoped to the active camera
  slot on the same terms as other calculator inputs. Switching the active
  slot shall replace the target along with the rest of the slot's inputs;
  an inactive slot's stored target shall not surface on another slot.
- **TARGET-022** — Per-slot Target Shutter persistence shall not be seeded
  from a session-global "last used target" value; doing so would leak one
  slot's value into another.

## UI presentation

- **TARGET-030** — The main shooting surface shall present an inactive or
  active Target Shutter row. Inactive indicates no committed target and
  opens the input sheet on tap; active shows the target duration, the
  comparison (when available), and a Start Timer action for the target.
- **TARGET-031** — The main row shall not present a destructive Clear
  affordance or an enable/disable switch; removal and disabling live only in
  the input sheet.
- **TARGET-032** — The input sheet opens seeded from the active slot's
  currently committed target when one exists (showing that committed
  value), or from a clean default when none exists — never leaking another
  slot's committed value. From there it edits a draft. Mutations to the
  draft shall not affect the committed target until the user confirms;
  Confirm commits the draft, Cancel discards it, and any dismissal that is
  not an explicit Confirm (drag, tap-outside) shall behave as Cancel,
  preserving whatever was previously committed.
- **TARGET-033** — Duration entry shall offer two complementary surfaces —
  quick presets and fine h/m/s entry — sharing one draft target, so
  switching between them does not lose work done in the other.
- **TARGET-034** — The sheet's disable ("Switch Off") control is itself
  part of the draft, not an immediate action: switching it off only clears
  the draft and does not by itself remove the committed target. Confirming
  while switched off removes the committed target; canceling or dismissing
  after switching it off preserves the previously committed target
  unchanged, on the same terms as TARGET-032.

## Timer creation

- **TARGET-040** — Starting a timer from Target Shutter shall use the
  target duration itself as the timer's duration.
- **TARGET-041** — A Target-Shutter-started timer shall remain identifiable
  as such for its entire lifetime, distinguishable from a digital-result,
  Adjusted-Shutter, or Corrected-Exposure timer, even if calculator inputs or
  the target later change.

## Persistence

- **TARGET-050** — Target Shutter shall be persisted per camera slot.
- **TARGET-051** — A missing, non-finite, zero, or negative persisted target
  shall restore as no target.

## Non-goals

- Target Shutter does not alter exposure or reciprocity calculation; it is
  a comparison layer only.
