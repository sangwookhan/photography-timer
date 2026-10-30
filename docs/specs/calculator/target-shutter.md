<!-- Copyright © 2026 Sangwook Han -->
<!-- SPDX-License-Identifier: Apache-2.0 -->

# Target Shutter

| Prefix | Owns |
| --- | --- |
| TARGET | Target entry, comparison, identity and persistence |
| TARGET-ND-GUIDE | Read-only required total attenuation during Base interaction |

## Purpose

Target Shutter lets a photographer enter a desired final exposure duration
and compare it against the calculator's current result. During manual Base
Shutter interaction it also shows the total attenuation needed for that
Target, without selecting filters or altering calculation inputs.

## Current behavior

Target Shutter is optional and scoped to the active camera. It sits on
top of the calculator and reciprocity results; enabling, disabling, or
editing it never feeds back into either. Required ND guidance queries the
selected reciprocity evaluation without changing its forward rules.

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
  camera on the same terms as other calculator inputs. Switching the active
  camera shall replace the target along with the rest of the camera's inputs;
  an inactive camera's stored target shall not surface on another camera.
- **TARGET-022** — Per-camera Target Shutter persistence shall not be seeded
  from a session-global "last used target" value; doing so would leak one
  camera's value into another.

## UI presentation

- **TARGET-030** — The main shooting surface shall present an inactive or
  active Target Shutter row. Inactive indicates no committed target and
  opens the input sheet on tap; active shows the target duration, the
  comparison (when available), and a Start Timer action for the target.
- **TARGET-031** — The main row shall not present a destructive Clear
  affordance or an enable/disable switch; removal and disabling live only in
  the input sheet.
- **TARGET-032** — The input sheet opens seeded from the active camera's
  currently committed target when one exists (showing that committed
  value), or from a clean default when none exists — never leaking another
  camera's committed value. From there it edits a draft. Mutations to the
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

## Required ND guidance

### Activation and calculation

- **TARGET-ND-GUIDE-001** — With a committed Target and guidance enabled,
  manual Base Shutter interaction shall display the required total attenuation
  live, independently of whether the available filters can realize that value.
  Target entry and confirmation alone shall not start guidance or change filters.
- **TARGET-ND-GUIDE-002** — Let B be the live Base seconds, T the committed
  Target seconds and M the pre-reciprocity exposure corresponding to T.
  Digital uses M = T. Film obtains M by reversing the selected profile's
  forward evaluation governed by `reciprocity/calculation.md`, including its
  no-correction segments and numeric continuation. Only a unique,
  positive, finite solution verified by the same forward evaluation shall
  supply a numeric result.
- **TARGET-ND-GUIDE-003** — Required total attenuation is R = log2(M / B).
  It includes the mounted auxiliary contribution. It is neither an additional
  amount to add to the current stack nor a suggested physical ND combination.
  The Target row's existing time-ratio comparison shall remain unchanged and
  shall not substitute for this inverse attenuation in film mode.
- **TARGET-ND-GUIDE-004** — The value shall not depend on candidate inventory,
  candidate ranking or an allowed exposure-error interval. A computed value
  shall not be clamped to an available filter strength or the physical stack
  cap. This read-only guidance does not relax the existing filter controls'
  physical limits.

### Shared status position and appearance

- **TARGET-ND-GUIDE-010** — Required ND shall replace the current Total at
  the same trailing position in the existing one-row filter status region.
  Preserve its alignment, baseline, numeric emphasis, padding, row height,
  wheel viewports and neighboring controls. Do not display required and
  current totals side by side, add a second row, move the wheels/results,
  or add an action or touch target. This replacement also applies to a
  Standard-only stack and a single ND wheel during qualifying Base interaction.
- **TARGET-ND-GUIDE-011** — The localized label shall be **Required ND** /
  **필요 ND**, with no colon between label and value. Examples are
  **Required ND 10 stops** / **필요 ND 10스톱**, and
  **Required ND 10.3 stops** / **필요 ND 10.3스톱**. Render whole values
  without a redundant decimal and other values to one decimal place,
  independently of the selected Stops/OD/ND notation. Use precise values
  for calculation; rounding is presentation only.
- **TARGET-ND-GUIDE-012** — Ordinary numeric Required ND guidance shall use
  blue, visually distinct from the ordinary current Total, in light and dark
  themes. The different text label shall also distinguish its meaning without
  relying on color. Restore the ordinary Total label and color when guidance
  ends; ordinary status behavior remains owned by the filter contracts.
- **TARGET-ND-GUIDE-013** — Numeric continuation beyond the selected profile's
  source range shall remain displayable. It shall use a warning tone distinct
  from ordinary blue guidance and an explicit **Beyond source range** /
  **출처 범위 밖** warning in the same status row. The required numeric value
  takes layout priority over leading text, but shortening or truncation shall
  never remove all readable warning words. A concise textual source-range
  warning shall remain visible alongside the number; warning color or an icon
  alone is insufficient. Fit this within the unchanged row geometry under
  TARGET-ND-GUIDE-010. Complete warning meaning shall remain available to
  accessibility. Existing forward-result warnings and categories shall remain
  unchanged.
- **TARGET-ND-GUIDE-014** — No quantified inverse, multiple solutions,
  invalid/non-finite inputs and numerical failure shall show concise unavailable
  guidance in the same status region, with the complete reason available to
  accessibility. A negative required total shall explain that attenuation
  cannot reach this Target. Do not fabricate a numeric value, clamp to zero,
  silently change profile or fall back to Digital. A valid no-correction
  segment remains eligible even if longer exposures are non-quantified.
- **TARGET-ND-GUIDE-015** — While Required ND or unavailable guidance replaces
  the visual Total, the actual current effective total shall remain available
  to assistive technology under `nd-filters.md` ND-A11Y-003, identified
  separately from the required total. The required value, source-range warning
  and complete unavailable reason shall be distinguishable by their accessible
  meaning, without relying on color or adding a second visual total.

- **TARGET-ND-GUIDE-016** — For ordinary numeric guidance, retain the ordinary
  leading source summary and replace only the trailing Total with Required ND.
  For beyond-source numeric guidance, replace the leading summary with the
  concise textual source-range warning and keep Required ND at the trailing
  position. For unavailable guidance, replace the leading summary with its
  concise reason and show **Required ND —** / **필요 ND —** at the trailing
  position, without a fabricated number. A negative required total uses a
  reason explaining that attenuation cannot reach this Target; it shall remain
  distinguishable from an unavailable inverse. Complete reasons and actual
  current Total remain accessible under TARGET-ND-GUIDE-014/015. On restoration,
  both sides resume the ordinary status appropriate to the current stack.
  These content changes shall preserve the single-row geometry.


### Interaction and state protection

- **TARGET-ND-GUIDE-020** — Guidance shall follow the live Base value while
  the user holds the control and throughout any motion after release,
  including inertia and final snap. Keep Required ND visible and updating
  until touch has ended, all wheel motion has stopped and the final Base
  value has been committed. Touch release alone shall not start restoration.
  An accessibility adjustment without touch shall use its final settled
  commitment as the restoration trigger.

- **TARGET-ND-GUIDE-021** — A new Base interaction shall use current inputs.
  ND or auxiliary interaction, selected-Set/inventory change, film/profile
  change, Target change, camera switch, disabling guidance or leaving Main
  shall end the previous guidance and restore ordinary status. Old results or
  delayed restoration callbacks shall not overwrite a newer interaction.
  Transient guidance shall not be persisted or restored after relaunch.
- **TARGET-ND-GUIDE-022** — Guidance shall not select or apply filters, change
  Base beyond the user's existing manual operation, mutate Target or auxiliary
  choices, change selected Filter Sets or Plus memory, or alter other cameras,
  captured timers or persistence contracts. It shall expose no Apply action,
  candidate offer, automatic Base adjustment or dedicated wheel animation.
- **TARGET-ND-GUIDE-023** — Settings shall provide an app-global
  **Show required ND** / **필요 ND 표시** choice, initially enabled and retained
  across camera switches and relaunch. Turning it off shall immediately restore
  ordinary status without changing shooting inputs. The explanation shall
  describe displaying required total attenuation while adjusting Base.
- **TARGET-ND-GUIDE-024** — Once the conditions in TARGET-ND-GUIDE-020
  are satisfied, update guidance to the final committed Base value and begin
  a crossfade to ordinary source/actual Total without an additional hold.
  Both layers shall exist at the same row position for the transition:
  outgoing Required ND starts at opacity 1 and ordinary content at opacity 0.
  Over one shared interval, Required ND fades 1→0 while ordinary content
  simultaneously fades 0→1. The total duration shall be approximately
  400–600 ms, initially 500 ms; it is not two sequential half-duration phases.
  There shall be no blank interval, delayed insertion or abrupt full-opacity
  appearance of the returning Total. Remove outgoing content after completion.
  Numeric, source-range warning and unavailable guidance use the same
  transition. Preserve the final required value as the outgoing content and
  current actual stack as the ordinary content. Duplicate settlement shall
  not restart the crossfade. The two temporary layers shall share the existing
  baseline and geometry without adding a row, moving controls, animating
  wheels, stealing touches or creating duplicate accessibility focus targets.
  A new touch cancels the crossfade and immediately shows current guidance
  at full opacity with the ordinary layer hidden. Old completion callbacks
  shall not affect newer state. Context invalidation under TARGET-ND-GUIDE-021
  cancels to current valid ordinary content at full opacity with guidance
  hidden. Reduced-motion settings shall preserve the same semantics with an
  allowed brief opacity transition or immediate restoration.


### Verification examples

These examples exercise the total-attenuation contract independently of
available filters. Values below are in seconds unless stated otherwise.

| Workflow and selected profile | Base B | Target T | Expected guidance and forward check |
| --- | --- | --- | --- |
| Digital | 1 | 1024 | M = 1024; R = log2(1024/1) = 10; **필요 ND 10스톱**. Forward: 1 × 2^10 = 1024. |
| Digital, with 2 stops of mounted auxiliary attenuation | 1 | 1024 | The same required total, **필요 ND 10스톱**, not 8 or 12. Auxiliary attenuation is already part of the total; it is not added to or subtracted from the displayed requirement. No mounted filter changes. |
| Digital | 1 | 1260.691879265195 | R = 10.3; **필요 ND 10.3스톱**. The precise Target is 2^10.3; display rounding does not alter calculation. |
| ILFORD HP5 Plus, selected Official formula (exponent 1.31) | 1 | 8779.968205097317 | M = 1024; R = 10; **필요 ND 10스톱**. Forward evaluation of the selected profile gives 1024^1.31 = T, with a formula-derived result. |
| The same selected HP5 Plus profile, no-correction segment | 0.25 | 0.5 | M = 0.5; R = 1; **필요 ND 1스톱**. Forward evaluation at the inclusive 0.5-second no-correction boundary returns 0.5. |

For any selected film profile, verify an inverse using the unrounded
M = B × 2^R through that same profile's forward evaluation; do not feed the
rounded displayed R back into this check. Formula and table profiles,
selected alternate profiles, no-correction boundaries, source-range numeric
continuation, non-quantified guidance, multiple solutions, numerical failure,
and negative required totals shall be checked under TARGET-ND-GUIDE-002/013/014.
The formula example is not a substitute for testing those other result forms.

## Timer creation

- **TARGET-040** — Starting a timer from Target Shutter shall use the
  target duration itself as the timer's duration.
- **TARGET-041** — A Target-Shutter-started timer shall remain identifiable
  as such for its entire lifetime, distinguishable from a digital-result,
  Adjusted-Shutter, or Corrected-Exposure timer, even if calculator inputs or
  the target later change.

## Persistence

- **TARGET-050** — Target Shutter shall be persisted per camera.
- **TARGET-051** — A missing, non-finite, zero, or negative persisted target
  shall restore as no target.

## Non-goals

- Automatic ND combination selection, Apply offers and automatic Base adjustment.
- Allowed-error evaluation or medium-specific candidate ranking for read-only guidance.
- Altering reciprocity source data, forward calculation rules or timer behavior.
