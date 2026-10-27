<!-- Copyright © 2026 Sangwook Han -->
<!-- SPDX-License-Identifier: Apache-2.0 -->

# Target Shutter

| Prefix | Owns |
| --- | --- |
| TARGET | Target entry, comparison, identity and persistence |
| TARGET-ND | Suggestion activation and allowance settings |
| TARGET-ND-CALC | Required attenuation, inverse and error semantics |
| TARGET-ND-SELECT | Candidate inventory, validity and ranking |
| TARGET-ND-UI | Interaction, lifetime and explicit application |

## Purpose

Target Shutter lets a photographer enter a desired final exposure duration,
compare it against the calculator's current result, and explicitly apply an
ND suggestion after manually adjusting Base Shutter.

## Current behavior

Target Shutter is optional and scoped to the active camera. Enabling,
disabling or editing the Target preserves Base and filters. ND suggestions
use that fixed Target and require a separate Apply action to change ND.

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

### ND suggestions after Base Shutter adjustment

The exposure error used to choose filters is distinct from the Target row's
time-ratio comparison (TARGET-010). Filter-stack invariants and ordering are
owned by `filter-sets.md` and `nd-filters.md`; the requirements below inherit
them rather than define a second stack model.

#### Activation and settings

- **TARGET-ND-001** — With a committed Target and ND suggestions enabled,
  manual Base Shutter interaction shall show the required total attenuation
  live. Target entry, Quick/Fine, Confirm, Cancel and Switch Off retain
  TARGET-032–034; confirming a Target alone shall not select filters.
- **TARGET-ND-002** — Settings shall offer a Target Shutter section with
  **Suggest ND selection** / **ND 자동 선택 제안**, initially on. Its
  explanation shall communicate that adjusting Base shows required ND and
  an Apply action. The setting is app-global, shared across cameras and
  retained after relaunch. Turning it off immediately removes guidance,
  suggestions and failure messages while preserving current inputs.
- **TARGET-ND-003** — The same Settings section shall offer **Allowed exposure
  error** / **허용 노출 오차**, with independent **Default** / **Extended**
  choices for Negative, Positive and Digital. Each initially uses Default
  and persists app-globally. The selected film's explicit polarity selects
  the film allowance; its color classification does not alter it. No film
  selects Digital. The intervals are inclusive:

  | Medium | Default | Extended |
  | --- | --- | --- |
  | Negative | −0.5 to +1 stop | −0.5 to +2 stops |
  | Positive | −1/3 to +1/3 stop | −0.5 to +0.5 stop |
  | Digital | −1 to 0 stop | −2 to 0 stops |

  Settings shall identify these as app selection allowances rather than
  guaranteed film/sensor limits, and explain the RAW-processing assumption
  for Digital Extended.

#### Required attenuation and exposure error

- **TARGET-ND-CALC-001** — Let B be the current Base seconds, T the fixed
  Target seconds, and M the metered/pre-reciprocity seconds corresponding to
  T. Digital uses M = T. Film obtains M by reversing the selected profile's
  existing forward evaluation, including its no-correction bands, formula
  or table, boundary policies and permitted numeric continuation. Only a
  unique, positive, finite solution verified through that forward evaluation
  supplies a numeric suggestion.
- **TARGET-ND-CALC-002** — Required total attenuation is R = log2(M / B).
  It includes the fixed mounted auxiliary contribution A. For a candidate
  with ND subtotal N, its total is D = N + A and its remaining exposure
  error is E = R − D. Negative E denotes underexposure, positive E
  overexposure relative to the user's Base reference. Calculations and
  eligibility shall use precise values; displayed rounding shall not decide
  validity. Base and Target shall remain fixed throughout evaluation.
- **TARGET-ND-CALC-003** — During Base interaction, required attenuation
  shall be labeled **Required ND** / **필요 ND**, rendered as a single total
  in stops to one decimal place, independent of global ND notation. It is
  not an increment to the mounted filters. This live guidance replaces the
  ordinary status content, including the current Total. The existing Target
  row continues to display its time-ratio comparison; that value shall not
  be reused as the film ND adjustment or the candidate's remaining error.
- **TARGET-ND-CALC-004** — No quantified inverse, multiple inverse solutions,
  invalid/non-finite calculation, and a negative required total shall produce
  understandable unavailable guidance and no Apply action. A negative total
  shall explain that attenuation cannot reach this Target. The app shall not
  invent a numeric inverse, silently change profile, or fall back to Digital.
  A profile's valid no-correction segment remains eligible even if its
  longer-exposure guidance is non-quantified.
- **TARGET-ND-CALC-005** — Numeric continuation beyond a profile's source
  range remains eligible. If the inverse or chosen candidate relies on
  out-of-source-range evaluation, the candidate-total action shall use a
  warning color distinct from the ordinary action and the status row shall
  show a short explicit **Beyond source range** / **출처 범위 밖** warning.
  Color shall not be the only warning cue; the action's complete meaning
  and source warning shall remain accessible. Existing forward result
  categories and warnings remain authoritative.
#### Candidate selection

- **TARGET-ND-SELECT-001** — If the active camera's selected Filter Sets
  contain any ND items, search their union of physical ND items only.
  Available/unselected Sets and Standard shall not supplement that search.
  If the selected Sets contain no ND items, including no selected Sets,
  search a replacement single Standard wheel from the canonical integer
  ladder 0–30 in ND-001, limited only by the unchanged auxiliary contribution.
  ND wheels being replaced shall not consume that replacement budget.
  Retained legacy fractional Standard values remain current state until
  Apply but shall not become new automatic-selection candidates.
  This fallback shall not change selected Filter Sets or Plus source memory.
- **TARGET-ND-SELECT-002** — Automatic selection shall preserve every mounted
  auxiliary item and its exact current CPL choice, GND mode and contribution.
  Physical item exclusivity, the total cap, the auxiliary-dependent ND-wheel
  limit and settled ordering follow the owning filter contracts. The search
  may choose no mounted ND when auxiliary attenuation suffices; represent
  that result with one legal zero/Empty wheel. Empty wheels are not physical
  filters and do not count in candidate filter-count comparisons.
- **TARGET-ND-SELECT-003** — A valid candidate must be representable by the
  actual filter controls, have a usable numeric film evaluation when
  applicable, and have E inside the configured interval. When no valid
  candidate exists, show a clear no-combination message while preserving
  the current stack. Insufficient inventory, stack limits and fixed auxiliary loss shall
  not be bypassed by fabricating filters, changing Base, or clamping.
- **TARGET-ND-SELECT-004** — First obtain the minimum |E| among valid
  candidates. Treat every valid candidate whose |E| is no more than
  0.1 stop above that minimum as equivalent for accuracy. Among those
  candidates choose fewer mounted ND filters, then fewer removals/additions
  relative to the currently mounted ND selections, then stable source/item
  identity order (canonical numeric order for Standard). Changed-item count
  includes removals plus additions; empty-wheel arrangement is ignored.
  This equivalence band shall never expand the allowed-error interval.
- **TARGET-ND-SELECT-005** — If the chosen result has the same ND selections
  as the current configuration, show **Current filters are suitable** /
  **현재 필터가 적정합니다** without Apply. Otherwise offer Apply even when
  the current configuration is already within the allowed interval. A
  candidate in the equivalent-accuracy group may be chosen for fewer filters
  even if its absolute error is slightly larger than the current error.

#### Interaction, presentation and application

- **TARGET-ND-UI-001** — During Base interaction, hide any preceding Apply
  and update required-ND guidance using the live Base. Offer a result only
  after touch release, inertial scrolling, final snap and value commitment
  have finished, and filter controls are quiet. A gesture that returns to
  its initial Base still qualifies. Accessibility adjustment shall use the
  same value-commit rule.
- **TARGET-ND-UI-002** — After settlement and evaluation, a valid changed
  candidate shall replace the ordinary current Total with one right-aligned
  candidate-total action: **Apply total <value> stops** / **합계 <value> 스톱
  적용**. Its value is the proposed combined total, including unchanged
  auxiliary attenuation, expressed in stops independently of ND notation.
  Format actual fractional totals faithfully using the ordinary Total's
  numeric presentation. Preserve the existing hierarchy of caption words
  and emphasized numeric value on one baseline. The entire phrase is one
  action; do not show a separate Apply beside the currently mounted total.
  The ordinary proposal has no leading text; an out-of-source proposal
  shows the short warning from TARGET-ND-CALC-005 on the leading side.
  Individual candidate ND composition and numeric residual shall not appear
  in this visual status row. Precise error evaluation and ranking remain
  unchanged. No-combination, already-suitable and inverse-unavailable results
  shall show short accurate explanations with no Apply. Complete action
  meaning and reasons remain accessible without another navigation flow.
- **TARGET-ND-UI-003** — The settled result/action shall remain for five
  seconds from when the result is ready, then return to the ordinary
  status presentation. A new qualifying interaction starts a fresh result
  lifetime; an earlier timeout shall not dismiss a later result. While a
  screen reader focuses the action, expiry shall be suspended so it can be
  activated. Transient proposals shall not be persisted or restored.
- **TARGET-ND-UI-004** — Use the existing single visual status row
  immediately below the Base/ND wheels. Preserve its baseline, typography
  hierarchy, padding, height, card height, wheel viewports and touch centers,
  and neighboring result/timer positions. Live Base guidance occupies this
  row without a competing current Total. A settled proposal uses the
  candidate-total action in TARGET-ND-UI-002 where the ordinary Total sat;
  its accent or warning color and light border or compact cue distinguish
  it as actionable. Do not add a second line, a tall standalone action,
  a panel or a detail route, shrink established wheel numerals, or expand
  the shooting page. The usable action hit region shall remain within the
  existing status space and shall not overlap or steal touches from wheels,
  Plus, results or timers. Appearance, expiry and failure shall not move
  surrounding controls. Restore ordinary status behavior after the
  transient state ends. FILTER-STACK-008 governs the ordinary status;
  these Target ND states replace its current-total presentation.
- **TARGET-ND-UI-005** — Base reinteraction, ND/auxiliary/selected-Set or
  inventory change, film/profile or classification change, Target change,
  allowance change, camera switch, feature disable, and leaving Main shall
  invalidate the pending proposal. Re-evaluation uses current inputs;
  only a new settled manual Base interaction opens a new five-second
  offer. A late result from earlier inputs shall not reappear.
- **TARGET-ND-UI-006** — Apply shall revalidate the proposal against the
  current camera, settings, inventory and committed inputs and commit the
  chosen ND stack as one action. Reject a stale/invalid proposal with its
  reason and preserve the prior stack. Prevent duplicate application.
  Success preserves Base, Target, auxiliary selections, selected Filter Sets,
  Plus memory, other cameras and captured timers; persist the resulting
  stack under the existing camera contract and briefly acknowledge success
  before ordinary status resumes.

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

- Automatic Base adjustment, Target-entry optimization checkboxes, and
  applying filters merely because an input changed.
- Altering reciprocity source data or the forward calculation rules.
