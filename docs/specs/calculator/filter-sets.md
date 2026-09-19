<!-- Copyright © 2026 Sangwook Han -->
<!-- SPDX-License-Identifier: Apache-2.0 -->

# Filter Sets and Mixed Filter Stack

| Prefix | Owns |
| --- | --- |
| FILTER-SET | Filter-set identity, ordering, color, and management |
| FILTER-ITEM | Physical filter inventory and value conversion |
| FILTER-CPL | CPL exposure-loss choices |
| FILTER-GND | GND recording and per-shot calculation mode |
| FILTER-STACK | Mixed-source stack, ordering, cap, and item exclusivity |
| FILTER-PLUS | Filter-source selection and wheel creation |
| FILTER-PERSIST | Persistence, restoration, and captured snapshots |
| FILTER-A11Y | Accessibility and localized presentation |

## Purpose

A photographer can describe the physical filters they own, organize them into
recognizable filter sets, and combine those filters with the existing Standard
ladder in one exposure stack. The calculator records which physical items are
mounted, prevents one item from being used twice on the same camera, and
applies only the exposure loss selected for the current shot.

## Terminology

- A **Filter Set** is a user-owned, ordered group with a stable id, name, and
  color. It is distinct from a Shooting Collection.
- A **Filter Stack** is the active camera's ordered selection of up to four
  filter wheels.
- A **Filter Source** is either Standard or one Filter Set and determines what
  a newly added wheel can select.
- A **Filter Item** is one physical filter with a stable id. Equal names and
  equal exposure values do not make two physical items the same item.

User-facing copy shall use the complete terms **Filter Set** and **Shooting
Collection**; it shall not use the unqualified word “Set” where the two domains
could be confused.

## Requirements

### Filter-set management

- **FILTER-SET-001** — The user shall be able to create, rename, reorder, edit,
  and delete Filter Sets in one management surface. A persistent entry from
  the ND header shall remain available when the Filter Stack already contains
  four wheels; the same surface shall also be reachable by long-pressing the
  Plus wheel while it is visible.
- **FILTER-SET-002** — Each Filter Set shall have a stable id, a non-empty
  user-defined name, a required color, and a user-defined display position.
  Renaming, recoloring, or reordering a Filter Set shall not change its id.
- **FILTER-SET-003** — Opening creation shall preselect a random suggested
  color different from the color suggested on the immediately preceding
  creation opening. The user may accept or change it. Two or more Filter Sets
  may use the same color; color uniqueness shall not be required.
- **FILTER-SET-004** — Standard is a fixed built-in Filter Source. It shall
  appear before all Filter Sets; Filter Sets shall then appear in their
  user-defined display order. A newly created Filter Set shall be appended to
  that order until the user reorders it.
- **FILTER-SET-005** — Filter-set names and colors are presentation and
  navigation metadata. Calculation and item identity shall never depend on
  either value, and color shall never be the only means of identification.

### Physical filter inventory and conversion

- **FILTER-ITEM-001** — A Filter Set shall contain zero or more physical Filter
  Items. The user shall be able to add, edit, reorder, and delete them.
- **FILTER-ITEM-002** — Every Filter Item shall have a stable item id and a
  non-empty user-defined name. Multiple items may have the same name, kind,
  unit, and value so that two equal physical filters can be mounted together.
- **FILTER-ITEM-003** — The user shall explicitly choose an item's behavior
  kind: Fixed, CPL, or GND. The app shall not infer a kind from the name.
- **FILTER-ITEM-004** — Fixed and GND items shall accept a decimal value in
  Stops, OD, or ND factor and preserve the original value and unit as equipment
  reference metadata. Conversion to canonical stops shall use Stops unchanged
  and `OD / 0.3`. An ND factor that exactly matches a commercial label emitted
  by the shared Standard formatter in `nd-filters.md` shall use that label's
  canonical ladder value; therefore ND1000 is exactly 10 stops, not
  `log2(1000)`. Other positive ND factors shall use `log2(ND factor)` without
  snapping. The result shall be finite, greater than 0, and no greater than
  30 stops.
- **FILTER-ITEM-005** — Editing an item shall update every active camera stack
  that references that stable item id. A save that would make any affected
  stack invalid, exceed 30 stops, or remove a CPL exposure-loss choice currently
  selected on an affected camera shall show the affected cameras and remain
  uncommitted until the conflict is resolved. The system shall not silently
  replace a selected CPL choice with another configured value.
- **FILTER-ITEM-006** — Deleting an item shall first identify affected cameras.
  After confirmation, every wheel that references the item shall become Empty.
  Deleting a Filter Set shall remove its wheels; a camera left with no wheel
  shall receive one Standard 0-stop wheel, and a deleted last-used source shall
  fall back to Standard. Previously captured timer or shooting snapshots shall
  not change.
- **FILTER-ITEM-007** — During one open New/Edit Filter Set session,
  successfully saving a newly created Fixed or GND item shall remember the
  registered-value notation selected in that item editor (Stops, OD, or ND).
  Opening the next new Filter Item from the same Filter Set editor shall
  initialize its notation from that remembered choice instead of resetting to
  Stops. Editing an existing item, saving a new CPL item, canceling, or a failed
  save shall not change the remembered notation. This memory is editor-session
  state only: closing the Filter Set editor or restarting the app shall reset
  the initial notation to Stops. It shall not affect item behavior kind; every
  newly created item shall continue to start as Fixed even when the preceding
  successfully saved new item was GND.

### CPL exposure-loss choices

- **FILTER-CPL-001** — A CPL item shall expose three decimal input fields for
  the exposure-loss choices available while shooting. New CPL items shall
  initialize them to 1, 1.5, and 2 stops.
- **FILTER-CPL-002** — Each non-empty field shall accept one integer digit and
  at most one fractional digit, in the closed range 0.1–9.9 stops. At least one
  field shall be valid. Empty fields omit a choice, and duplicate values shall
  appear only once in the shooting wheel.
- **FILTER-CPL-003** — Focusing any CPL choice field shall request a
  decimal-capable numeric keyboard on iOS and Android. Locale decimal
  separators, pasted text, and hardware-keyboard input shall be normalized and
  validated by the same rules; an integer-only or general alphabetic keyboard
  does not satisfy this requirement.
- **FILTER-CPL-004** — The editor shall explain that these are “Exposure loss
  choices (stops) available from the wheel while shooting.” The English and
  Korean copy shall communicate the same meaning.
- **FILTER-CPL-005** — A CPL item's shooting rows shall consist of its distinct
  configured exposure-loss choices. Selecting any one row mounts that physical
  item. Every row for the same item shall then be disabled in other wheels on
  the same camera, while the owning wheel may switch between that item's rows.

### GND recording and calculation

- **FILTER-GND-001** — A GND item shall preserve its registered full-density
  value while offering two shooting rows: Record only, contributing 0 stops,
  and Apply full value, contributing the registered canonical stops.
- **FILTER-GND-002** — Record only shall be the default when a GND is first
  selected. Switching modes shall affect only that wheel in the active camera;
  it shall not change the inventory default, another camera, or a timer already
  started.
- **FILTER-GND-003** — Applying the full value is intended for a composition in
  which the GND's dark region covers nearly the entire metered frame. The UI
  shall warn that a base shutter metered through the mounted GND may already
  include its attenuation.
- **FILTER-GND-004** — Partial-density estimation is out of scope. GND
  calculation contributes either zero or the complete registered value.

### Mixed stack and filter wheels

- **FILTER-STACK-001** — The Filter Stack shall contain one to four actual
  filter wheels drawn from any mixture of Standard and Filter Set sources. The
  Plus wheel is not an actual filter wheel and does not count toward four.
- **FILTER-STACK-002** — Standard wheels may repeat equal values. One physical
  Filter Item id may appear only once in a camera's stack, although the same
  inventory item may be selected independently by another camera.
- **FILTER-STACK-003** — A Filter Set wheel shall include Empty plus the rows
  belonging to that Filter Set. Empty means no physical item and contributes
  zero stops; Record only is a mounted physical item and also contributes zero.
  Those states shall remain visually and semantically distinct.
- **FILTER-STACK-004** — The effective filter value shall equal the sum of all
  selected rows' canonical contributions. It shall remain finite, greater than
  or equal to 0, and no greater than 30 stops. A choice or mode change that
  would exceed 30 shall be rejected with its reason; it shall never be clamped.
- **FILTER-STACK-005** — After all moving wheels settle, actual wheels from
  the same source shall remain contiguous and source groups shall sort by
  registered subtotal descending. A source group's registered subtotal is the
  sum of its rows' sort values: a Standard row's selected stops, a Fixed row's
  registered canonical stops, a CPL row's selected exposure-loss choice, a GND
  row's registered full-density value in both Record only and Apply full value
  modes, and zero for Empty. Within each source group, non-empty rows shall sort
  by the same row value descending and Empty shall sort last. Ties between
  source groups shall put Standard first and then follow Filter Set
  user-defined order; row ties shall retain stable order. Sorting shall occur
  only after every moving wheel settles, preserve wheel identity and effective
  sum, and shall not move a GND merely because its mode changes between Record
  only and Apply full value. When a committed change alters the settled order,
  the wheel row shall make that change perceptible as one coherent transition
  from the complete previous arrangement to the complete new arrangement. It
  shall not animate individual wheel columns through or over one another,
  expose a mixed intermediate order, overlap labels, or make a wheel
  temporarily unreadable. If another committed order arrives before the
  transition completes, the whole-row transition shall restart toward the
  newest complete arrangement; no partial intermediate arrangement shall
  become the settled presentation. FILTER-SET-004 continues to govern
  management and Plus source-browsing order; it does not govern the settled
  stack order. FILTER-A11Y-006 suspends this automatic value-based ordering
  while platform screen-reader touch exploration is active and reconciles to
  this order after that mode is disabled.
- **FILTER-STACK-006** — Standard 0 and Filter Set Empty wheels in a multi-wheel
  stack shall follow the existing idle-cleanup and explicit-removal contract in
  `nd-filters.md`. For this mixed stack, FILTER-STACK-006 narrows the immediate
  30-stop cleanup rule: immediate cleanup applies only when the wheel can accept
  no usable row. A Filter Set Empty wheel with an unmounted, selectable
  Record-only item shall remain available for the normal idle interval. A
  mounted Record-only item shall not be cleaned up.
- **FILTER-STACK-007** — Every filter wheel shall keep its scrolling
  viewport visually quiet at rest and while moving: numeric values remain
  centered at the established size, and candidate rows shall not contain
  repeated type words. A persistent full type and mode label shall remain
  immediately above the viewport for the candidate at the touch center:
  Fixed and Standard use `ND`; CPL uses `CPL`; GND uses `GND` with
  `REC` or `FULL`; Empty uses `EMPTY` while its centered value uses the
  same canonical-zero numeric rendering as Standard zero.

  Each visible candidate row shall carry a narrow type-color rail at one fixed
  edge of the row. The rail moves with its candidate so nearby rows can be
  recognized before reaching the touch center without adding text beside the
  numeric value. The app-defined semantic palette shall be stable across
  Filter Sets, cameras, and platforms: ND uses blue, CPL uses amber/orange,
  GND uses a green-leaning teal, and Empty uses neutral gray. The GND hue shall
  remain visibly distinct from ND blue even on faded adjacent rows. GND Record
  only and Apply full value share the GND hue; the persistent text label
  communicates `REC` or `FULL`. The palette shall remain distinguishable in
  light and dark appearances, but exact platform color tokens are presentation
  details.

  Filter Set color and type color have separate meanings and locations.
  Filter Set color identifies the source and shall appear as the source cue
  adjacent to the persistent label and on the Plus source control. The
  type-color rail identifies only the candidate's ND, CPL, GND, or Empty
  behavior. Neither color may be derived from the other, and no uniqueness or
  collision-avoidance rule is required between the user-selected Filter Set
  color and the fixed type palette. Text and accessibility information remain
  authoritative; both colors are redundant cues and shall never be the only
  means of identification.

  Fixed and GND numeric values shall follow the app-global Stops / OD / ND
  notation through the same formatter and rounding policy as Standard,
  showing only the numeric value component: for example, canonical 10 stops
  renders `10`, `3.0`, or `1000`; canonical 3 stops renders
  `3`, `0.9`, or `8`. A Record-only GND shall display its
  registered full-density value while `REC` communicates that its active
  contribution is zero. CPL choices are exposure loss in stops and shall
  remain `1`, `1.5`, or `2` independently of the global
  notation. Empty shall use the shared Standard formatter for canonical zero,
  rendering `0` in Stops, `0.0` in OD, and `1` in ND notation.
  Its `EMPTY` label and status text shall continue to mean that no physical
  filter is mounted; this visual alignment shall not merge Empty with the
  distinct Standard-zero domain state.

  Type rails and Filter Set source cues shall not reduce the established
  numeric-value hierarchy used before this capability for the same density
  tier and actual-wheel count. On iOS, a single wheel keeps the full-width
  reference size of 32 / 26 / 19 points in Regular / Compact / Dense. For
  two / three / four actual wheels, the reference sizes are Regular
  28 / 24 / 20 points, Compact 23 / 20 / 17 points, and Dense
  18 / 16 / 14 points. Base Shutter and every filter wheel in the row shall
  use the same numeric size. In particular, four wheels in Dense shall use
  14-point values. These sizes are tier references, not permission to select a
  denser tier from an obsolete content-height budget. The density decision
  shall be derived from the geometry actually rendered after FILTER-STACK-008
  reduces the status region to one row. On an iPhone 17 Pro at the default
  content size, the worst supported film-result and active-Target-Shutter
  composition shall fit the Compact tier after that reclaimed height; it shall
  not remain Dense solely because the removed second status line is still
  counted. Thus a one-filter row on that device uses the Compact 26-point
  reference rather than the Dense 19-point reference, and the same tier's
  references apply as wheels are added.

  The Base Shutter column shall reserve the same persistent-label-row height
  as the filter columns, even though that reserved label row is visually
  empty. Its picker viewport top and bottom, selected-row band, selected-value
  baseline, and vertical touch center shall align with those of every filter
  wheel in the row. Adding or removing wheels, changing notation, moving a
  wheel, settling a reorder, or changing status content shall not break that
  shared vertical axis.

  The type rail shall fit inside the existing row geometry without reducing
  the numeric column, changing wheel width, reflowing the row, moving its
  touch center, or changing the picker bounds. It shall not create a foreground
  expansion card, dim sibling wheels, or depend on touch, drag, deceleration,
  grace-period, or commit-barrier presentation state. It shall not change
  wheel identity, option order, availability, selection, contribution,
  source-group ordering, or commit behavior, and shall not introduce an
  overlay or separate status bubble. For every allowed composition, including
  three actual wheels with Plus and four actual wheels, the persistent
  type/mode label, numeric value, source cue, and type rail shall remain
  legible without ellipsis at the default and every supported standard text
  size. While moving, the stable non-blocking region from FILTER-STACK-008
  shall expose the full item name, original registered representation, and
  active contribution in canonical stops without moving the touch center.
  Long visual detail may truncate at its trailing edge, but shall not be
  inferred or silently rewritten; the complete detail shall remain available
  to accessibility. During touch, drag, and inertial settling, the centered
  numeric row and its type rail, the persistent type/mode label, and the detailed
  status text shall identify the same visual-center candidate. They shall not
  mix a passing candidate with the previously committed candidate.
- **FILTER-STACK-008** — The mixed-stack interaction shall use one stable
  status region for source identity, the current item or source, rejection
  reason, and live total required by `nd-filters.md` ND-INTERACT-020. For a
  stack containing any Filter Set wheel, the idle region shall persistently
  show a visually secondary source summary and the current total rather than
  becoming empty. Idle content shall always use exactly one visual row at every
  supported text size: the source summary aligned to the leading side and the
  localized total aligned to the trailing side. The total shall remain visible
  and untruncated. When both cannot fit, the leading source summary shall yield
  space first and truncate at its trailing edge; it shall not wrap or move the
  total to a second line. The complete source summary shall remain available to
  accessibility. The region shall reserve only the height required for one
  visual row plus its normal vertical padding. It shall not retain capacity for
  the removed second line. This reclaimed height shall be returned to the wheel
  row and included in the density-tier fit calculation. Status-state changes
  shall remain geometry-stable within that one-row region.

  The source summary shall list each source once in the same left-to-right
  order as the settled source groups, append a wheel count when a source owns
  more than one actual wheel (for example
  `NiSi kit · Lee holder ×2 · Standard`), and identify sources by text rather
  than color alone. Each Filter Set name shall also carry its user-selected
  source-color cue so the summary maps names back to the source cues above the
  wheels. Standard remains explicitly identified by text and does not acquire
  a user-selected color.

  While a wheel or Plus is moving, the region shall replace the idle content
  with exactly one visual row: current item or source detail aligned to the
  leading side and the current live total aligned to the trailing side. A
  rejection shall use the same row for its reason and unchanged total. In every
  state the total shall remain visible and untruncated; leading detail or reason
  shall yield space first and truncate at its trailing edge without wrapping.
  The complete item detail, source name, contribution, and rejection reason
  shall remain available to accessibility. After the existing transient
  interval following settlement or rejection, the persistent idle source
  summary and total shall return. These states shall replace or combine content
  within the one region rather than stack separate bubbles. The region shall
  reserve stable layout geometry so content changes never move a picker or its
  touch center. A Standard-only stack retains the existing status behavior in
  `nd-filters.md`.

### Plus wheel and per-camera source memory

- **FILTER-PLUS-001** — The Plus wheel shall remain at the end of the row while
  fewer than four actual wheels exist. Moving it vertically shall select among
  Standard and the Filter Sets in FILTER-SET-004 order; it shall not browse
  filter values. Its management long press shall succeed only while the pointer
  or touch remains within the stationary gesture tolerance. Crossing the normal
  drag activation threshold shall cancel any pending long press immediately and
  give the vertical drag priority; a successful source-browsing drag shall
  never open Filter Set management when released.
- **FILTER-PLUS-002** — While the Plus wheel moves, an expanded, non-blocking
  label shall display the complete candidate source name. At rest the compact
  Plus control shall show the candidate source's color as a secondary cue.
- **FILTER-PLUS-003** — Plus shall create a wheel with one direct gesture.
  Tapping Plus shall add a Standard 0-stop wheel or a Filter Set Empty wheel
  for the currently displayed source exactly once. When a drag or fling crosses
  the source-browsing threshold and finally snaps to a different source, the
  system shall wait for deceleration, final snap, and the existing commit
  barrier, then add exactly one wheel from that final source without requiring
  another tap. Passing intermediate sources shall never create wheels. If the
  gesture settles back on its starting source, it shall create no wheel; the
  ordinary tap remains the explicit add gesture for that source. Once browsing
  wins, the pending management long press shall remain cancelled for the rest
  of that gesture.
- **FILTER-PLUS-004** — Each camera shall remember the Filter Source of its
  last successful Plus addition across camera switches and app restarts. A
  rejected or unavailable addition shall not change the remembered source. A
  fresh camera and a camera whose remembered source no longer exists shall use
  Standard.
- **FILTER-PLUS-005** — When the selected source cannot currently add a usable
  row, source browsing shall remain enabled but adding shall be disabled with a
  reason. A Record-only item remains addable at a 30-stop total if a wheel slot
  and an unmounted physical item remain available.

### Persistence and captured context

- **FILTER-PERSIST-001** — The inventory, Filter Set order and colors, every
  camera's mixed stack and per-row calculation mode, and every camera's last
  Filter Source shall survive app restart through backward-compatible additive
  persistence. A legacy Standard-only snapshot shall continue to restore. When
  writing a mixed stack, the additive mixed-stack field is authoritative for
  new builds; pre-Filter-Set stack and scalar fields shall describe only its
  Standard wheels, using one Standard 0 wheel when none exist, so older builds
  restore a valid Standard-only projection.
- **FILTER-PERSIST-002** — Inventory records shall decode independently under
  `cross-cutting/persistence.md`. An unresolved Filter Set or item reference in
  a camera stack shall be skipped safely; a CPL selection whose configured
  exposure-loss choice no longer exists shall restore that wheel as Empty
  rather than selecting another choice. The restored stack shall still end in
  a valid one-to-four-wheel state, falling back to Standard 0 when necessary.
- **FILTER-PERSIST-003** — Starting a timer shall capture an immutable
  calculation record containing the effective canonical total in stops and
  each row's actual contributed stops and selected calculation mode. The Timer
  list shall present that canonical total as its primary filter value and a
  human-readable reference string generated at start time from the Filter Set
  and Filter Item names, registered representations, and modes. The reference
  string is descriptive only: Filter Set identity, color, later inventory
  lookup, rename, reorder, edit, or deletion shall not drive calculation or
  rewrite an already captured Timer list entry.
- **FILTER-PERSIST-004** — A broader Shooting Collection or record-management
  workflow is outside this capability. It may consume the same immutable
  summary later but shall not redefine Filter Set behavior.

### Accessibility and localization

- **FILTER-A11Y-001** — Every wheel shall be one adjustable accessibility
  element with a stable label that identifies its position and source, separate
  from a concise dynamic value that identifies the current item or Empty, type
  or calculation mode, and current canonical value or contribution. Moving
  focus to another wheel may announce that wheel's label and value, but changing
  a selection shall not repeat the stable label or an app-authored usage hint.
  The complete registered representation and calculation detail shall remain
  reachable through the status region. Add, remove, source selection, and Filter
  Set management shall have explicit assistive-technology actions.
- **FILTER-A11Y-002** — Color shall be redundant with accessible text and
  state. Required controls, persistent labels, and type cues shall remain
  reachable and readable under the large-text and constrained-height rules in
  `cross-cutting/presentation.md`.
- **FILTER-A11Y-003** — English and Korean shall expose equivalent terminology,
  validation, calculation modes, and disabled reasons on iOS and Android.
- **FILTER-A11Y-004** — An assistive-technology increment or decrement on a
  Filter Set wheel shall scan the wheel's existing row order in the requested
  direction and skip candidates that are unavailable because the same physical
  item is mounted in another wheel, the 30-stop cap would be exceeded, or
  another selection rule rejects the candidate. It shall commit and announce
  the first available candidate exactly once instead of stopping at the first
  unavailable adjacent row. The scan shall not wrap past the end of the wheel.
  If no available candidate exists before that boundary, the current selection
  shall remain unchanged and the localized unavailability reason shall be
  announced.
- **FILTER-A11Y-005** — A successful wheel increment or decrement shall update
  the element's dynamic accessibility value and announce the newly committed
  value exactly once. If adjustment begins while VoiceOver is still speaking
  the wheel label, value, trait, or system guidance, that speech shall yield to
  the changed value. Rapid consecutive adjustments may interrupt intermediate
  speech, but after adjustment stops the final committed value shall be heard.
  A rejected or boundary adjustment shall announce only its localized reason
  and shall not re-announce the unchanged value. Filter wheels shall provide no
  app-authored usage hint; platform guidance for the adjustable trait remains
  under the user's assistive-technology verbosity settings.
- **FILTER-A11Y-006** — While the platform screen reader or touch-exploration
  mode is active (VoiceOver on iOS; touch exploration used by TalkBack or
  another Android screen reader), the Filter Stack shall freeze its current
  complete wheel order. Selection and mode changes shall continue to update
  values, contributions, and totals, but shall not run the automatic
  value-based ordering in FILTER-STACK-005 or move accessibility focus to a
  different wheel position. Enabling the mode shall preserve the complete
  order currently shown and cancel any pending reorder without exposing a
  partial arrangement. If the app starts with the mode active, it shall restore
  the persisted wheel order without an automatic value-based reorder.
  Explicit wheel addition or removal may still change membership and the
  unavoidable positions around that change; it shall not trigger an additional
  subtotal-based reorder.

  When the mode becomes inactive, the stack shall reconcile exactly once to
  the current FILTER-STACK-005 order after all wheel movement and the current
  commit barrier have settled. The reconciliation may change positions but
  shall preserve every wheel's stable identity, committed selection, effective
  total, and per-camera persistence. Implementations shall detect the platform
  capability rather than a particular Android accessibility-service package,
  so compatible screen readers receive the same behavior. Ordinary touch and
  ordering behavior while the mode is inactive remain unchanged.

## Verification examples

1. Register two separate 3-stop items in one Filter Set, select both, and
   observe a 6-stop contribution while a second selection of either id is
   unavailable.
2. Combine NiSi ND1000 (10), Lee ND8 plus CPL 1 (registered subtotal
   4), and Standard 2. After every wheel settles, observe contiguous source
   groups ordered NiSi, Lee, Standard with the effective total unchanged.
   Switch a Lee GND between Record only and Apply full value and verify its
   registered subtotal and group position do not change; verify equal
   subtotals use Standard first and then Filter Set user-defined order. Trigger
   a subtotal reorder and verify the complete row transitions between coherent
   before/after arrangements without overlapping wheel columns or labels.
   Commit another reorder before that transition completes and verify the
   whole-row transition restarts toward only the newest complete arrangement.
3. Tap Plus and verify the currently displayed source is added exactly once.
   Drag slowly and fling quickly from Standard to a Filter Set; verify no
   intermediate source creates a wheel and exactly one Empty wheel from the
   final snapped source is added after settlement without another tap. Return
   to the starting source and verify no wheel is added. Verify a rejected add
   preserves the stack, total, and remembered source. Begin with a stationary
   press and then cross the drag threshold; verify source browsing wins and
   management never opens. Separately hold without crossing the threshold and
   verify the management surface opens without creating a wheel. Switch
   cameras and restart the app; verify each camera restores the source of its
   last successful Plus addition and its own stack.
4. Select GND 2 as Record only and observe a mounted item with contribution 0;
   switch to Apply full value and observe 2 stops without changing another
   camera or a running timer.
5. Configure one CPL with 1, 1.5, and 2; select 1.5 and verify every row for that
   item is unavailable in sibling wheels. Verify decimal keyboards and rejection
   of 0, 10, and 1.25 on both platforms. Attempt to remove the selected 1.5
   choice in the editor; verify save remains blocked and identifies every
   affected camera until its wheel selection is changed.
6. At a 30-stop total, add a Record-only item when a slot is free; then verify
   that enabling its non-zero contribution is rejected without changing state.
7. Rename, recolor, and reorder a Filter Set; verify stable ids, active stacks,
   accessible names, and captured timer summaries remain correct.
8. Start a timer from a mixed stack; verify the Timer list leads with the
   canonical total in stops and preserves its start-time Filter Set reference
   string after the source inventory is renamed, edited, reordered, or deleted.
9. Register ND1000 and verify its canonical value, contribution, 30-stop
   cap behavior, persisted state, and Timer record all use exactly 10 stops.
   Switch the app-global notation and verify its numeric wheel value becomes
   `10`, `3.0`, and `1000`; verify a 3-stop Fixed or GND value becomes
   `3`, `0.9`, and `8`, while CPL 1.5 remains `1.5`. Compare Standard
   zero with a Filter Set Empty row and verify both numeric values become
   `0`, `0.0`, and `1`, while their labels and source semantics remain
   `ND`/Standard and `EMPTY`/no filter mounted.
10. At rest and while moving, verify every wheel keeps centered numeric-only
    rows and a full persistent `ND`, `CPL`, `GND REC`, `GND FULL`,
    or `EMPTY` label above the touch-center candidate. Verify each visible
    row carries only its narrow fixed-edge type-color rail: blue for ND,
    amber/orange for CPL, green-leaning teal for both GND modes, and neutral
    gray for Empty.
    Drag slowly and fling quickly through a mixed-type Filter Set wheel; verify
    the rail travels with each candidate and the centered number, persistent
    label, and detailed status text always identify that same candidate; verify
    none retains the previously committed candidate while another advances.
    Confirm the wheel never expands or dims its siblings. Confirm the Filter Set source-color cue stays in its
    separate label/Plus location and can duplicate a type hue without changing
    either meaning. Repeat with three wheels plus Plus and four wheels; verify
    no numeric value, Base Shutter, notation, Plus, or status control is
    displaced or obscured.
11. With Filter Set and Standard sources mixed, verify the idle status region
   always presents exactly one visual row: source names in settled left-to-right
   order at the leading side, each Filter Set accompanied by its source-color
   cue, and the complete current total at the trailing side. Verify long names
   and larger supported text truncate only the trailing edge of the source
   summary while the total remains visible; no state shall wrap or use a
   second line. Verify accessibility exposes the complete source
   summary and transient detail.
   Move a Filter Set wheel and Plus, trigger both a valid total update and a
   rejection, and verify each uses the same one-row leading-detail / trailing-
   total layout before returning to the idle presentation. Repeat the palette
   and summary checks in light and dark appearances.
12. On iPhone 17 Pro at the default content size, exercise the worst supported
    film-result and active-Target-Shutter composition and verify that reclaiming
    the removed status line allows the Compact tier rather than Dense. Verify a
    one-filter row uses 26-point Base Shutter and filter values, then repeat with
    three wheels plus Plus and four wheels using the Compact reference sizes.
    Measure the Base Shutter and filter picker viewport bounds, selected-row
    bands, selected-value baselines, and touch centers; each pair shall share
    the same vertical axis. Repeat the alignment check at XXXL and on iPhone 17
    Pro Max, and verify no label, rail, source cue, Plus control, status total,
    or numeric value is clipped or displaced.
13. Compare numeric values with the pre-capability reference hierarchy at the
   same density and wheel count. On iOS, verify a single wheel uses
   32 / 26 / 19 points in Regular / Compact / Dense and that two / three / four
   wheels use the specified table. Verify four wheels in Dense use 14-point
   values while settled and moving, and Base Shutter uses the same size.
   Confirm the type rail leaves long candidates such as `1000` complete without
   shrinking or shifting the numeric column.
14. In one Filter Set editing session, save consecutive new Fixed or GND items
   after choosing Stops, OD, and ND and verify each following new item starts
   with the most recently saved notation while its kind still starts as Fixed.
   Edit an existing item, save a new CPL item, cancel, and attempt a failed
   save; verify none changes the remembered notation. Close and reopen the
   Filter Set editor and restart the app; verify a new item starts with Stops
   because notation memory is intentionally session-scoped.
15. Create a Filter Set containing ND 3, ND 6, ND 10, and CPL. Mount ND 10 in
   the first wheel and CPL 1 in the second. With VoiceOver focused on the second
   wheel, adjust it toward the ND rows. Verify the adjustment skips ND 10
   because that physical item is already mounted and selects ND 6 rather than
   repeatedly announcing the ND 10 conflict. Repeat at a boundary where no
   candidate in that direction is available; verify the current selection and
   total remain unchanged and the localized reason is announced.
16. Focus each wheel with VoiceOver and verify its stable label identifies only
   position and source while its dynamic value identifies the item or Empty,
   type or mode, and current canonical value. Begin adjusting before the focus
   description finishes; verify that speech yields to the newly committed value
   and that the stable label and usage guidance are not repeated. Adjust rapidly
   through at least four available rows and stop; intermediate speech may be
   interrupted, but the final committed value shall be announced exactly once.
   Repeat a rejected and a boundary adjustment; verify only the localized reason
   is announced and the value, stack, and total remain unchanged. Repeat in
   English and Korean.
17. Create a Filter Set containing ND 3, ND 6, ND 10, and CPL. Set wheel 1 to
   ND 6 and wheel 2 to ND 3, then enable VoiceOver and focus wheel 2. Adjust
   wheel 2 to ND 10 and verify the value is announced while wheel 2 remains in
   the second position, focus stays on that same wheel, and the total updates.
   Disable VoiceOver and verify that, after settlement, the stack reconciles
   once to the normal FILTER-STACK-005 order with ND 10 in the first position,
   without changing either wheel's identity, selection, or total. Re-enable
   VoiceOver and verify the newly shown order freezes. Repeat the equivalent
   flow on Android with TalkBack touch exploration, including app launch with
   touch exploration already active.

## Non-goals

- Automatic compatibility checks between holders, filter sizes, lenses, or
  Filter Sets, and recommendations about which physical filters to combine.
- Inferring Fixed, CPL, or GND behavior from a product name.
- Estimating a CPL's current loss from rotation angle or a GND's partial-frame
  coverage.
- Cross-device inventory synchronization, import, export, and purchase advice.
- A Shooting Collection editor or general photographic-equipment inventory.
