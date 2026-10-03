<!-- Copyright © 2026 Sangwook Han -->
<!-- SPDX-License-Identifier: Apache-2.0 -->

# Filter Sets and Shooting Filter Stack

| Prefix | Owns |
| --- | --- |
| FILTER-SET | Filter-set identity, ordering, color, and management |
| FILTER-ITEM | Physical filter inventory and value conversion |
| FILTER-CPL | CPL exposure-loss choices |
| FILTER-GND | GND recording and per-shot calculation mode |
| FILTER-STACK | ND wheels, combined exposure cap, and item exclusivity |
| FILTER-CAMERA | Per-camera candidate Filter Sets |
| FILTER-AUX | Mounted auxiliary filters and shooting popup |
| FILTER-COLOR | Optical color, effect identity, and visual color semantics |
| FILTER-FLOW | Main-screen and setup navigation |
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

- A **Filter Set** is a user-owned, ordered group of physically compatible
  filters for one mounting arrangement, with a stable id, name, and color.
  It is distinct from a Shooting Collection. A Filter Set can later be made
  available to another camera explicitly; the app does not infer compatibility.
- A **Filter Stack** is the active camera's ND wheels together with its
  mounted auxiliary filters. Wheel count is not physical filter count.
- **Auxiliary filters** are mounted CPL, GND, Color, or Effect items. They
  share one summary space; they are not scrolling wheels.
- **Candidate Filter Sets** are the Filter Sets explicitly selected for a camera.
  A camera may select more than one. Availability does not mean mounted, and
  does not certify compatibility.
- A **Filter Source** is either Standard or one Filter Set and determines what
  a newly added ND wheel can select. Only its ND items appear in that wheel.
- A **Filter Item** is one physical filter with a stable id. Equal names and
  equal exposure values do not make two physical items the same item.

User-facing copy shall use the complete terms **Filter Set** and **Shooting
Collection**; it shall not use the unqualified word “Set” where the two domains
could be confused.

## Requirements

### Filter-set management

- **FILTER-SET-001** — Shooting Filters shall present Filter Sets in two
  sections: **Selected Sets** and **Available Sets**. A selected Set shall use
  one compact header row: a leading remove control, its color and name as the
  central edit target, and, when the Set contains at least one Filter Item, a
  trailing add-filter control that creates a new Filter Item directly in that
  Set. The header may show the Set's auxiliary-item count inline, but shall not
  add a second inventory-detail line. If a selected Set contains no Filter
  Items, the trailing add-filter control shall be omitted and one compact
  full-width **Add Filter** row shall appear beneath the header instead. A
  non-empty selected Set shall present auxiliary items in one horizontally
  scrollable strip of equal-width controls directly beneath the header. On the
  iPhone shooting surface at default text size, the strip shall size ordinary
  item controls so at least three complete item controls are visible at once.
  An item's name may wrap to at most two lines inside its control; its item type
  remains independently visible. The strip shall be visually indented from the
  Set header so Set ownership is immediately clear. An available Set shall use
  one compact row: its color/name as the edit target and one trailing add
  control that moves it into working Selected Sets. Removing a selected Set
  moves it into Available Sets without committing camera state until Apply.
  Shooting Filters shall not expose Filter Set reorder handles. A separate
  pencil-style edit icon shall not be required. The final inventory action shall
  remain **Add Filter Set**. A delete confirmation shall name the targeted set
  and remain bound to its stable id.

- **FILTER-SET-002** — The app shall provide one built-in **Default Filter Set**
  with a stable id. It is a real inventory Filter Set, is selected for a newly
  created / fresh camera by default, and is the initially selected Filter Set
  when a new Filter Item is created, so first-time filter registration does not
  require creating or naming a Filter Set first. The user may later remove
  Default from that camera's working Selected Sets like any other Set. Its
  contents, display name, and color may be edited like other Filter Sets, but
  the built-in set itself shall remain present and shall not be deleted.
- **FILTER-SET-003** — Each user-created Filter Set shall have a stable id, a
  non-empty user-defined name, and a required color. Opening creation shall
  preselect a random suggested color different from the color suggested on the
  immediately preceding creation opening. The user may accept or change it.
  Two or more Filter Sets may use the same color; color uniqueness shall not be
  required. Renaming or recoloring a Filter Set shall not change its id.
- **FILTER-SET-004** — Standard is a fixed built-in Filter Source for ND wheels
  and is not a Filter Set. Shooting Filters shall not provide manual Filter Set
  reordering. Selected Sets shall retain their working selection/addition order;
  Default starts first on a fresh camera. Available Sets shall be sorted by
  display name using the platform's ordinary locale-aware alphabetical order.
  Adding an Available Set appends it to Selected Sets; removing a Selected Set
  places it back into the alphabetically sorted Available Sets. In Main's ND
  source browsing, Standard shall appear before eligible selected Filter Sets.
- **FILTER-SET-005** — Filter-set names and colors are presentation and
  navigation metadata. Calculation and item identity shall never depend on
  either value, and color shall never be the only means of identification.
- **FILTER-SET-006** — Every user-created Filter Set editor shall expose a
  destructive **Delete Filter Set** action. The built-in Default Filter Set
  shall not expose this action. Delete shall require confirmation that names the
  Filter Set and makes the global scope clear: the Set and its Filter Items are
  removed from inventory, and references to that Set are reconciled across all
  cameras under FILTER-ITEM-006. Cancel or dismiss shall preserve the Set and
  all camera state. The delete action belongs to the Filter Set editor; Shooting
  Filters shall not add a destructive delete affordance directly to a Set row.

### Physical filter inventory and conversion

- **FILTER-ITEM-001** — A Filter Set shall contain zero or more physical Filter
  Items. The user shall be able to add, edit, move between Filter Sets, and
  delete them. Manual Filter Item reordering shall not be provided. Lists shall
  use the fixed kind order ND, Color, Effect, CPL, GND and sort items
  alphabetically by display name within each kind using the platform's ordinary
  locale-aware ordering. The Filter Set editor shall offer one Add Filter action
  rather than separate add actions by kind.
- **FILTER-ITEM-002** — Every Filter Item shall have a stable item id and a
  non-empty user-defined name. Multiple items may have the same name, kind,
  unit, and value so that two equal physical filters can be mounted together.
- **FILTER-ITEM-003** — The user shall explicitly identify ND, CPL, GND, Color,
  or Effect behavior; the app shall not infer behavior from a name. New Filter
  shall open one editor with ND preselected, and the user may change its type
  inside that editor before entering the type-specific fields. Existing Fixed
  items retain their ND behavior and identity. Color and Effect items belong
  to Shooting Filters, not the ND wheels. The internal representation of these
  kinds is not a cross-platform requirement.
- **FILTER-ITEM-009** — New Filter shall always show an enabled Filter Set
  field. When opened from Shooting Filters it initially selects the built-in
  Default Filter Set; when opened from a specific Filter Set it initially
  selects that containing Set. The user may select any existing Filter Set
  before saving. The same field shall offer **Add Filter Set**; creating a set
  there shall return to the in-progress Filter Item editor with the new set
  selected, without discarding the entered Filter Item values. Filter Set
  creation shall also remain available independently of creating a Filter Item.
  Editing an existing Filter Item shall keep the Filter Set field enabled so the
  item may be moved to another existing Set. Moving an item preserves its stable
  item id. Every camera that currently references that item shall preserve the
  reference under the destination Set and shall add the destination Set to its
  selected/candidate Sets if needed; the source Set shall not be implicitly
  removed from that camera's selected/candidate Sets. The ordinary edit
  validation and affected-camera rules in FILTER-ITEM-005 still apply.

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
  After confirmation, each referencing ND wheel shall become Empty and each
  referencing mounted auxiliary item shall be removed. Deleting a Filter Set
  shall remove its ND wheels, mounted auxiliary items, and camera candidate
  references. A camera left with no ND wheel shall receive one Standard 0-stop
  wheel. A deleted last-used source shall fall back to Standard. Removing the
  last auxiliary item shall hide the summary. Previously captured timer or
  shooting snapshots shall not change. This is inventory deletion, not merely
  excluding an existing set from a camera's candidates.

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
  appear only once in the shooting popup.
- **FILTER-CPL-003** — Focusing any CPL choice field shall request a
  decimal-capable numeric keyboard on iOS and Android. Locale decimal
  separators, pasted text, and hardware-keyboard input shall be normalized and
  validated by the same rules; an integer-only or general alphabetic keyboard
  does not satisfy this requirement.
- **FILTER-CPL-004** — The editor shall explain that these are “Exposure loss
  choices (stops) available in the filter selection popup while shooting.” The English and
  Korean copy shall communicate the same meaning.
- **FILTER-CPL-005** — A CPL item shall offer its distinct configured exposure-loss
  choices in the auxiliary popup. It shall be mounted once with exactly one
  selected choice; changing that choice shall update the same mounted item.
  Its current contribution shall remain immediately readable on the main
  summary without opening the popup.

### GND recording and calculation

- **FILTER-GND-001** — A GND item shall preserve its registered full-density
  value while offering two shooting modes in the auxiliary popup: Record only, contributing 0 stops,
  and Apply full value, contributing the registered canonical stops.
- **FILTER-GND-002** — Record only shall be the default when a GND is first
  selected. Switching modes shall affect only that mounted item in the active camera;
  it shall not change the inventory default, another camera, or a timer already
  started.
- **FILTER-GND-003** — Applying the GND's registered value is intended for a
  composition in which the dark region covers nearly the entire metered frame.
  Shooting Filters shall distinguish the two modes by their effect rather than
  by ambiguous short labels: **Record only** contributes 0 stops, while
  **Apply to exposure** contributes the complete registered value. Choosing
  either mode is an immediate reversible working-state change and shall not
  require an additional confirmation popup. The current mode and resulting
  contribution shall remain visible in the Selected filters panel.
- **FILTER-GND-004** — Partial-density estimation is out of scope. GND
  calculation contributes either zero or the complete registered value.

### Mixed stack and filter wheels

- **FILTER-STACK-001** — The main row shall contain Base Shutter, then the
  auxiliary summary when any auxiliary item is mounted, then ND-only wheels,
  then Plus when another ND wheel can fit. With no mounted auxiliary items,
  one to four ND wheels are allowed. With any mounted auxiliary item, one to
  three ND wheels are allowed. The summary occupies one space regardless of
  its item count. Base Shutter and Plus do not count toward these limits.
  A mounted Record-only GND counts as auxiliary presence even at zero stops.

- **FILTER-STACK-002** — Standard wheels may repeat equal values. One physical
  Filter Item id may appear only once in a camera's stack, although the same
  inventory item may be selected independently by another camera.
- **FILTER-STACK-003** — A Filter Set ND wheel shall include Empty plus only that
  set's ND items. CPL, GND, Color, and Effect shall never appear as ND-wheel
  candidates. Empty means no physical item and contributes zero stops; a
  Record-only GND is mounted in the auxiliary summary and also contributes
  zero. These states shall remain visually and semantically distinct.

- **FILTER-STACK-004** — The effective filter value shall equal the sum of all
  ND-wheel and mounted auxiliary-item canonical contributions. It shall remain finite, greater than
  or equal to 0, and no greater than 30 stops. A choice or mode change that
  would exceed 30 shall be rejected with its reason; it shall never be clamped.
  When a sighted touch gesture on a Filter Set wheel settles with an unavailable
  row at the touch center, that unavailable row shall never commit. Instead,
  the wheel shall scan back through the rows the gesture just traversed, from
  the unavailable final row toward the previously committed row, and commit the
  first selectable row it encounters. It shall not search beyond the attempted
  final row or wrap around the wheel. If no selectable row exists on that
  traversed interval, the previously committed selection shall remain and the
  actual rejection reason shall be shown. When a fallback row is committed, the
  status region shall present that committed row and updated Total rather than
  leaving the rejected candidate's reason as the settled state.
- **FILTER-STACK-005** — After all moving wheels settle, actual wheels from
  the same source shall remain contiguous and source groups shall sort by
  registered subtotal descending. A source group's registered subtotal is the
  sum of its ND rows' sort values: a Standard row's selected stops, an ND
  item's registered canonical stops, and zero for Empty. Auxiliary contributions
  shall not participate in ND source-group sorting. Within each source group, non-empty rows shall sort
  by the same row value descending and Empty shall sort last. Ties between
  source groups shall put Standard first and then follow Filter Set
  user-defined order; row ties shall retain stable order. Sorting shall occur
  only after every moving wheel settles, preserve wheel identity and effective
  sum. The auxiliary summary shall stay immediately after Base Shutter;
  changing a GND mode or CPL choice shall not reorder ND wheels. When a committed change alters the settled order,
  every wheel shall remain visible and each stable wheel identity shall animate
  directly from its current position to its new position. Its numeric value,
  type or mode label, source cue, and accessibility identity shall remain
  attached to that wheel throughout the movement. This presentation movement
  shall not change a committed selection, effective sum, persisted order, or
  accessibility focus. If another committed order arrives before movement
  completes, the row may retarget the same stable identities to the newest
  arrangement; only that newest arrangement shall become settled.
  FILTER-SET-004 continues to govern
  management and Plus source-browsing order; it does not govern the settled
  stack order. FILTER-A11Y-006 suspends this automatic value-based ordering
  while platform screen-reader touch exploration is active and reconciles to
  this order after that mode is disabled.
- **FILTER-STACK-006** — Standard 0 and Filter Set Empty ND wheels in a multi-wheel
  stack shall follow the idle-cleanup contract in `nd-filters.md`, including
  immediate cleanup when the combined 30-stop cap leaves no usable non-zero
  ND choice. Cleanup shall retain at least one ND wheel. Mounted auxiliary
  items, including Record-only GNDs, shall never be removed by wheel cleanup.
  Automatic cleanup does not require a separate assistive-technology Remove
  action. An actual removal during screen-reader use shall be announced once
  as removal of an empty ND wheel, not of a zero-contribution mounted item.

- **FILTER-STACK-007** — Every ND wheel shall keep numeric-only scrolling rows,
  a persistent ND or EMPTY label, and its source identity. ND values shall
  remain readable at rest and while moving; auxiliary detail shall not take
  over or hide ND numeric values. ND values shall follow the app-global
  Stops / OD / ND formatter: 10 stops renders 10 / 3.0 / 1000; 3 stops
  renders 3 / 0.9 / 8. Empty renders canonical zero (0 / 0.0 / 1) while
  retaining its distinct no-mounted-item meaning.

  Source cues and the auxiliary summary shall not reduce the established
  numeric-value hierarchy used before this capability for the same density
  tier and occupied filter-space count (ND wheels plus the auxiliary summary). On iOS, a single occupied filter space keeps the full-width
  reference size of 32 / 26 / 19 points in Regular / Compact / Dense. For
  two / three / four occupied filter spaces, the reference sizes are Regular
  28 / 24 / 20 points, Compact 23 / 20 / 17 points, and Dense
  18 / 16 / 14 points. Base Shutter and every ND wheel in the row shall
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

  Source cues shall fit the existing wheel geometry without moving the touch
  center, clipping numeric values, expanding a foreground card, or dimming
  siblings. During movement, the centered candidate and status detail shall
  identify the same item. The status region shall expose its full item name,
  original registered representation, and contribution in stops. Long visual
  detail may truncate at the trailing edge; full detail remains accessible.

- **FILTER-STACK-008** — The mixed-stack interaction shall use one stable
  status region for source identity, the current item or source, rejection
  reason, and live total required by `nd-filters.md` ND-INTERACT-020. For a
  stack containing any Filter Set ND wheel or mounted auxiliary item, the idle region shall persistently
  show a visually secondary source summary and the current total rather than
  becoming empty. Idle content shall always use exactly one visual row at every
  supported text size: the source summary aligned to the leading side and the
  localized total aligned to the trailing side. Total is a primary reading,
  not secondary caption text: its numeric stops value shall be at least the
  size of the selected ND numeric values in the same layout, with sufficient
  emphasis to read directly in the field. The layout shall provide that space
  without reducing the established ND numeric size, forcing a denser tier, or
  clipping the existing results and controls. The total shall remain visible
  and untruncated. When both cannot fit, the leading source summary shall yield
  space first and truncate at its trailing edge; it shall not wrap or move the
  total to a second line. The complete source summary shall remain available to
  accessibility. The region shall reserve only the height required for one
  visual row plus its normal vertical padding. It shall not retain capacity for
  the removed second line. This reclaimed height shall be returned to the wheel
  row and included in the density-tier fit calculation. Status-state changes
  shall remain geometry-stable within that one-row region.

  The source summary shall list each source once in main-row order (auxiliary
  sources first, then settled ND groups), append an ND-wheel count when a source owns
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

- **FILTER-PLUS-001** — Plus shall remain at the right end while the applicable
  ND-wheel limit permits another wheel: four without auxiliary items, three
  with them. Its vertical choices shall be Standard, the active camera's
  candidate Filter Sets containing ND items in FILTER-SET-004 order, and an
  Auxiliary filters action. That action is not a source or a filter value.
  The persistent ND-header entry shall still reach auxiliary selection when
  Plus is absent. A management long press succeeds only within stationary
  tolerance; crossing the drag threshold cancels it for that gesture.

- **FILTER-PLUS-002** — While the Plus wheel moves, an expanded, non-blocking
  label shall display the complete candidate source name. At rest the compact
  Plus control shall show the candidate source's color as a secondary cue.
- **FILTER-PLUS-003** — Plus shall create a wheel with one direct gesture.
  With an ND source displayed, tapping Plus shall add a Standard 0-stop wheel or a Filter Set Empty wheel
  for the currently displayed source exactly once. When a drag or fling crosses
  the source-browsing threshold and finally snaps to a different source, the
  system shall wait for deceleration, final snap, and the existing commit
  barrier, then add exactly one ND wheel from that final source without requiring
  another tap. Passing intermediate sources shall never create wheels. If the
  gesture settles back on its starting source, it shall create no wheel; the
  ordinary tap remains the explicit add gesture for that source. Once browsing
  wins, the pending management long press shall remain cancelled for the rest
  of that gesture.
  Settling on the Auxiliary filters action shall instead open the shooting
  popup after the same gesture barrier, without creating an ND wheel. Tapping
  that action, when presented as a selectable control, shall do the same.
  Closing the popup shall return Plus to its preceding ND source; auxiliary
  selection shall not change last-successful-ND-source memory.
- **FILTER-PLUS-004** — Each camera shall remember the Filter Source of its
  last successful Plus addition across camera switches and app restarts. A
  rejected or unavailable addition shall not change the remembered source. A
  fresh camera and a camera whose remembered source no longer exists shall use
  Standard. Shooting Filters shall not add or select ND wheels.
- **FILTER-PLUS-005** — When an ND source cannot add a usable row, browsing and
  the Auxiliary filters action shall remain available while Plus is present;
  adding an ND wheel shall be disabled with a reason. At a 30-stop total,
  mounting a Record-only GND shall remain possible within the composition
  limits, while a change to non-zero contribution that exceeds 30 is rejected.
  Neither a rejection nor cancellation shall remove an existing ND selection.

### Camera candidates and shooting workflow

- **FILTER-CAMERA-001** — A camera may have multiple selected Filter Sets and
  shall remember that selection per camera. The same physical set may be
  selected for multiple cameras. Selection is an explicit statement that the
  set is available to that camera; diameter, holder, body name, and adapter
  compatibility shall not be inferred. A fresh/new camera starts with the
  built-in Default Filter Set selected; after that, Default follows the same
  per-camera add/remove rules as any other Filter Set.
- **FILTER-CAMERA-002** — Standard shall always remain available for ND without
  selecting a Filter Set. Filter Set selection shall not mount any item.
  Camera selection shall restore that camera's context, not force a setup
  wizard. Film selection and Filter Set selection are independent; neither
  custom inventory nor auxiliary filters are prerequisites for film reciprocity
  calculation.
- **FILTER-CAMERA-003** — Shooting Filters shall keep both Selected Sets and
  Available Sets visible while choosing auxiliary filters. Multiple Filter Sets
  may be selected simultaneously. Adding or removing a Set changes working
  state only until Apply. Removing a Set moves it to Available Sets and hides
  its auxiliary rows without immediately changing the camera's committed
  candidate Sets, mounted auxiliary filters, ND wheels, calculation, or Main
  summary. Auxiliary working selections belonging to a removed Set shall be
  retained for the lifetime of that Shooting Filters session so adding the Set
  again restores the same working selections. Apply commits the resulting Set
  selection and auxiliary selection together and removes any committed
  auxiliary references and ND wheels whose Set is no longer selected,
  preserving a valid ND stack with Standard 0 as the fallback when necessary.
  Apply shall not ask for an additional confirmation. Cancel or dismissing
  Shooting Filters shall preserve the complete camera shooting state from
  before the surface opened. This camera-only selection is distinct from global
  inventory deletion under FILTER-ITEM-006.

- **FILTER-FLOW-001** — Main shall retain the existing camera/film controls,
  Target Shutter, wheel region, result rows, camera paging, and timers. The
  new interaction shall use the existing wheel region and Shooting Filters,
  not a new permanent vertical panel. No empty auxiliary placeholder shall
  consume space.
- **FILTER-FLOW-002** — ND selection and ND-wheel creation shall remain on
  Main. Shooting Filters shall not present an ND tab, ND-source browser, or
  add-ND-wheel action. The persistent ND-header entry, the Auxiliary filters
  action in Plus, and tapping a mounted auxiliary summary may open Shooting
  Filters; each route opens the same auxiliary-selection surface.
- **FILTER-FLOW-003** — Shooting Filters shall use a dense shooting-oriented
  layout with two stable information zones. At the top, a fixed-height
  **Selected filters** panel shall show the working selected-filter count and
  current auxiliary exposure reduction prominently, followed by a vertically
  scrollable list containing every working selected auxiliary Filter Item; no
  selected item may be replaced by ellipsis-only summary or a **+N more**
  placeholder. Each selected-item row shall keep the user-defined item name
  (one line, ellipsized only when necessary), item type, and current
  contribution or mode visible. The panel's outer height shall not change as
  selections change. Below it, each Selected Set uses one compact header
  followed by one indented horizontal Filter Item strip; a Set shall not consume
  one vertical row per Filter Item. Horizontal overflow is local to that Set's
  strip, uses free scrolling without snapping item names or recentering after a
  selection, and shall preserve scroll position across selection and choice
  changes. Selecting an item shall not insert or remove a per-Set explanatory
  row or otherwise change that Set's vertical footprint. Explanatory footer
  paragraphs shall not occupy the shooting surface. Available Sets and Add
  Filter Set follow in compact rows. Auxiliary selection is multi-select:
  the user may mount more than one auxiliary Filter Item, including items from
  different selected Filter Sets. Apply/Cancel governs the complete
  camera-specific Shooting Filters working state: selected Filter Sets and
  mounted auxiliary choices. Apply is enabled when either part differs from the
  committed camera state and commits them together. Cancel or dismissal
  discards both kinds of working changes. Inventory edits such as creating,
  editing, moving, or globally deleting Filter Sets / Filter Items remain
  explicit inventory operations and are not rolled back by Shooting Filters
  Cancel.
- **FILTER-FLOW-004** — First-time registration shall be filter-first rather
  than Filter-Set-first. Because the built-in Default Filter Set always exists
  and starts selected for a fresh camera, Shooting Filters shall not replace its
  ordinary layout with an empty-inventory setup state. A selected Set that has
  existing inventory items exposes a compact trailing add-filter control in its
  Set header. A selected Set with no Filter Items instead exposes a full-width
  **Add Filter** row in its content area and omits that trailing add-filter
  control. Either path opens New Filter directly in that Set. The user may save
  there, choose another existing Filter Set, or create a new Filter Set inline.
- **FILTER-FLOW-005** — Selected Sets and Available Sets shall remain visible
  regardless of how many Sets are selected or how many auxiliary filters are
  mounted. Set names open the Set editor. The leading remove control on a
  Selected Set moves it to Available Sets; the trailing add control on an
  Available Set appends it to Selected Sets. Shooting Filters shall not provide
  Filter Set reorder, a separate **Manage Filter Sets** destination, or a hidden
  Plus/long-press management route. **Add Filter Set** remains available after
  the Set sections. Creating a Filter Set adds it to inventory and returns to
  Shooting Filters; it does not mount a filter. Global deletion remains an
  explicit destructive inventory action inside the Filter Set editor and shall
  not be conflated with removing that Set from the active camera.

### Mounted auxiliary filters

- **FILTER-AUX-001** — A non-scrolling summary shall appear immediately after
  Base Shutter only while at least one auxiliary item is mounted. Removing the
  last item shall hide it and return that space to ND use. A Record-only GND
  shall keep it visible. Its position shall not change with exposure value.
- **FILTER-AUX-002** — Main shall show every mounted auxiliary item's identity
  and current contribution in stops, without requiring a tap or cycling through
  items. A combined total, count, color dot, or generic GND label alone is
  insufficient. Registered GND density shall be explicitly distinguished from
  its current contribution and Record only / Apply full value mode. Equal-value
  Hard, Soft, and Reverse GNDs shall be distinguishable by their registered
  names in both selection and the summary. CPL choice and Color/Effect loss
  shall be immediately readable. The summary shall not replace ND numeric
  values or increase the main screen's vertical content budget.
- **FILTER-AUX-003** — Opening Shooting Filters shall initialize its working
  auxiliary selection and working Filter Set selection from this camera's
  committed state. Apply shall atomically validate and commit the working
  Filter Set selection, auxiliary mounting, CPL choices, and GND modes,
  including removal of ND wheels that belong to Filter Sets excluded by the
  applied working selection. Cancel or surface dismissal shall preserve the
  prior selected Sets, mounted auxiliary state, ND wheels, calculation, and
  summary visibility. An invalid Apply shall explain the constraint and leave
  the committed state unchanged. Rechecking a Set within the same session shall
  restore that Set's retained auxiliary working selections.
- **FILTER-AUX-004** — Physical-item exclusivity and the 30-stop cap shall cover
  ND and auxiliary selections together. A zero-contribution mounted item is
  still present and cannot be mounted twice. The wheel limit shall not be
  interpreted as a maximum count of physical auxiliary items.

### Color and effect filters

- **FILTER-COLOR-001** — A Color item shall record an optical color separately
  from its user-defined name and exposure loss. Red, Orange, Yellow, Green, and
  Yellow-green shall be representable without pretending they are ND, CPL, or
  GND. For example, a named red filter with registered loss 2 stops shall show
  both its Red identity and 2-stop contribution. No exposure loss shall be
  inferred from the optical color, product name, or camera.
- **FILTER-COLOR-002** — Effect items, including a night light-pollution filter,
  shall be usable as mounted auxiliary filters on digital and film cameras.
  Their exposure contribution shall be explicitly user-supplied, not an
  app-estimated correction. Color and Effect inventory shall participate in
  item identity, per-camera state, total validation, and captured context.
- **FILTER-COLOR-003** — Source-set color, filter behavior type, and a Color
  filter's optical color are different information. Each shall be identifiable
  by text and shall not overwrite the other. Color-code presentation shall
  preserve these meanings across iOS and Android, light and dark appearances.
  Source recoloring shall not change a filter's optical color or calculation.

### Approved field-feedback revision (2026-10-01)

The following requirements supersede conflicting earlier text in this document.

- **FILTER-AUX-005** — There is no maximum count of mounted auxiliary items. The three visible Main lines are a presentation guarantee, not a selection limit. Main shall show the first three mounted items, distributing one, two, or three compact rows through the available summary height rather than packing them at its top, and then `+ N more` when further items are mounted. Main shall not scroll or fade; tapping its summary opens the complete scrollable list.
- **FILTER-AUX-006** — Shooting Filters shall group offered auxiliary items by
  selected Filter Set, in Selected Set order. Within each Set, items shall
  follow Color → Effect → CPL → GND and alphabetical order within kind. The
  Filter Set name belongs to the compact Set header and shall not be repeated on
  Filter Item controls. Each item in the horizontal strip shall be an
  equal-width selectable control whose whole primary surface toggles
  mounted/unmounted state; selected state shall be obvious without relying on
  color alone. The item control shall show the user-defined item name and its
  type separately, because names such as **72mm** do not imply CPL, GND, Color,
  or Effect. The name may use at most two lines in the selection control. The
  strip shall not create a post-selection detail row. For a selected CPL or GND,
  the compact item control shall provide a distinct, directly reachable
  secondary choice affordance so changing CPL loss or GND mode does not require
  unmounting the item first. Main retains its existing fixed auxiliary summary
  order and concise identity-plus-contribution presentation.
- **FILTER-AUX-007** — Shooting Filters shall not show the whole-stack Total
  because ND configuration remains on Main. It shall show the selected
  auxiliary filters' exposure contribution as **Exposure reduction** (localized
  equivalently, e.g. Korean **노출 감소량**) in stops. The combined
  ND-plus-auxiliary 30-stop cap remains mandatory. A change that would exceed
  30 shall be rejected without removing an existing selection.
- **FILTER-ITEM-008** — All user-facing instances of `Fixed` shall be renamed `ND`. Existing persisted Fixed items retain their stable identities and ND behavior. An item editor shall permit correction between ND and Color even when mounted, preserving the committed camera selection only if the resulting stack is valid.
- **FILTER-COLOR-004** — The shared selectable optical-color palette shall be ordered Red, Red-orange, Orange, Yellow-orange, Yellow, Yellow-green, Green, Teal, Blue, Purple, Pink. This keeps the existing intermediate hues while adding the common photographic Red↔Orange↔Yellow transitions. Each option shall render as a clear recognizable hue in light and dark appearance: Yellow shall be a bright photographic yellow rather than a muted mustard/brown; Yellow-green shall remain visibly between Yellow and Green; Red-orange and Yellow-orange shall remain visibly between their neighbors. Duplicate blue-family options are not required. A Color item uses this common palette and must not render its choices as black or generic markers.
### Persistence and captured context

- **FILTER-PERSIST-001** — The inventory, Filter Set order and colors, every
  camera's ND wheels, candidate Filter Sets, mounted auxiliary items and
  per-item calculation mode, and every camera's last ND Filter Source shall survive app restart through backward-compatible additive
  persistence. A legacy Standard-only snapshot shall continue to restore. When
  writing a mixed stack, the additive mixed-stack field is authoritative for
  new builds; pre-Filter-Set stack and scalar fields shall describe only its
  Standard wheels, using one Standard 0 wheel when none exist, so older builds
  restore a valid Standard-only projection.
- **FILTER-PERSIST-002** — Inventory records shall decode independently under
  `cross-cutting/persistence.md`. An unresolved Filter Set or item reference in
  a camera stack shall be skipped safely; a CPL selection whose configured
  exposure-loss choice no longer exists shall restore that wheel as Empty
  rather than selecting another choice. For an auxiliary CPL reference, the
  invalid selection shall be unmounted rather than substituted. The restored
  state shall respect the conditional ND-wheel limits and contain at least one
  ND wheel, falling back to Standard 0 when necessary. Legacy mixed-stack
  migration shall preserve physical identities, CPL choices, GND modes, and
  effective total: its ND rows become ND wheels and its CPL/GND rows become
  auxiliary selections. Candidate sets shall include the referenced legacy
  sets so restored mounted items remain reachable. A legacy stack containing
  only auxiliary items shall receive one Standard 0 ND wheel. Existing timer
  records shall not be rewritten.
- **FILTER-PERSIST-003** — Starting a timer shall capture an immutable
  calculation record containing the effective canonical total in stops and
  each ND wheel's and mounted auxiliary item's actual contributed stops and selected calculation mode. The Timer
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
  reachable through the status region. Add and ND source selection shall have
  explicit assistive-technology actions on the focusable Plus control,
  including a distinct Open auxiliary filters action. Filter Set selection,
  editing, creation, and user-created Set deletion shall remain directly
  reachable from Shooting Filters and the Filter Set editor rather than through
  a separate Plus management action. Set and Filter Item reordering actions are
  not required because their presentation order is deterministic. The summary shall be a button
  that exposes all mounted identities, modes, and contributions
  and opens the shooting popup; it shall not pretend to be an adjustable ND
  wheel. Automatic cleanup governed by FILTER-STACK-006 need not expose
  a separate Remove action.
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
  shall remain unchanged. The announcement shall identify the actual rejected
  candidate when one or more unavailable candidates prevented progress; when
  the current row is simply at the end, it shall instead announce a localized
  boundary reason.
- **FILTER-A11Y-005** — A successful wheel increment or decrement shall update
  the element's dynamic accessibility value and announce the newly committed
  value exactly once. If adjustment begins while VoiceOver is still speaking
  the wheel label, value, trait, or system guidance, that speech shall yield to
  the changed value. Rapid consecutive adjustments may interrupt intermediate
  speech, but after adjustment stops the final committed value shall be heard.
  A rejected or boundary adjustment shall announce only its localized reason
  and shall not re-announce the unchanged value. Filter wheels shall provide no
  app-authored usage hint; platform guidance for the adjustable trait remains
  under the user's assistive-technology verbosity settings. After a successful
  wheel adjustment, the spoken dynamic value shall identify the newly committed
  item or Empty, its type or calculation mode, its current canonical value or
  contribution, and the current complete Total in that order. For example, an
  ND 3 item at a 21.6-stop combined total may be announced as
  "ND, 3 stops, Total 21.6 stops". Rapid consecutive
  adjustments may interrupt intermediate speech, but after adjustment stops the
  final committed value and current Total shall be heard exactly once. Rejected
  or boundary adjustments shall continue to announce only their localized
  reason. The complete Total shall also remain a separate focusable
  accessibility target in the status region, reachable directly without first
  listening through the source summary or item-detail text.
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

## Screens and navigation

The numbered screens describe roles within the existing main-screen structure;
they do not prescribe native navigation components or a new app shell.

| Screen | Contents and primary task |
| --- | --- |
| 1. Main | Existing camera/film and Target controls; Base Shutter → optional auxiliary summary → ND wheels → Plus; one status row with prominent Total; existing results and timers. ND selection and ND-wheel creation stay here. |
| 2. Shooting Filters | Fixed-height Selected filters panel with selected count, exposure reduction, and a vertically scrollable complete selected-item list; Selected Sets with one compact header and one indented free-scrolling strip of equal-width Filter Item controls per Set; item name and type shown separately; direct CPL/GND secondary choices; Available Sets alphabetically with name-to-edit and trailing add-to-selected; Add Filter Set; Apply/Cancel for the whole working session. No ND tab, ND-wheel-add action, manual Set/item reorder, or separate Manage Filter Sets entry. |
| 3. Filter Set editor | Name and source color; one physical-item list ordered ND, Color, Effect, CPL, GND and alphabetically within kind; Add Filter; delete items; destructive Delete Filter Set for user-created Sets only. |
| 4. Filter Item editor | Name, explicit kind, registered exposure metadata, and enabled Filter Set selection for both new and existing items; inline Add Filter Set; optical color for Color, CPL choices, or GND full density as applicable. |

```mermaid
flowchart TD
  M["1. Main: ND wheels and optional auxiliary summary"] -->|"Header / Plus auxiliary / mounted summary"| P["2. Shooting Filters"]
  P -->|"Apply / Cancel auxiliary"| M
  P -->|"Add / remove Selected Sets"| P
  P -->|"Add Filter in selected Set"| I["4. Filter Item editor"]
  P -->|"Edit Filter Set"| E["3. Filter Set editor"]
  P -->|"Add Filter Set"| E
  E -->|"Add / edit item"| I
  I -->|"Choose / move to / create Filter Set"| I
  I -->|"Save / cancel"| P
  E -->|"Done"| P
```

ND remains on Main throughout this flow. Selecting Filter Sets changes which
auxiliary items Shooting Filters offers; it does not mount those items. Popup
structure and system dismissal gestures may follow each platform; the committed
behavior and availability of these paths shall match.

## Verification examples

| Scenario | Actions and expected main-screen result |
| --- | --- |
| Digital, Standard only | Start from a fresh digital camera, set Base Shutter and Standard ND, add another ND with Plus. No inventory setup or auxiliary placeholder; calculated exposure remains available. |
| Film, Standard only | Select film and Standard ND directly. Film/model and corrected result remain in their existing positions; custom inventory is not required. |
| Inventory preparation | Start with Add Filter and save the first item into Default without creating a Filter Set first. Add another filter, create a 52 mm Filter Set from the Filter Set field, and return with it selected. Create additional 67/72 mm, 82 mm, and shared sets as needed. Mixed sets do not need splitting. |
| Digital with auxiliary | From initial Main open Shooting Filters. Select two Filter Sets at once and verify the auxiliary list becomes their union. Mount CPL from one and Record-only GND from the other, Apply, then add/select ND on Main. Summary appears left of ND and shows both contributions; Total includes CPL and zero GND. |
| Film with auxiliary | Select film, mount Red from the camera's Color set, select ND from a separate shared set. Main retains film results, individual auxiliary loss, and ND values. |
| Field maximum | Register and mount Red plus ND400, ND4, and ND16. Main shows one auxiliary summary and all three ND wheels. The ND400 conversion follows FILTER-ITEM-004 rather than a fabricated Standard preset. A fourth ND cannot be added until auxiliary items are removed. |
| Four ND without auxiliary | Reach four ND wheels. The persistent header still opens auxiliary selection; no ND is silently removed to accommodate it. Return with Cancel and verify unchanged values. |
| GND identity and mode | Register Hard 2, Soft 2, Soft 3, and Reverse 3 with distinguishing names. Select the intended item, then switch Record only / Apply full value. Both registered density and current contribution remain distinguishable on Main. Mount two distinct GND items and verify both identities and contributions are readable. |
| Removal and cancellation | Remove all auxiliary selections and Cancel: Main is unchanged. Repeat and Apply: the summary disappears and capacity returns to four ND. A sole Record-only GND still keeps the summary visible. |
| Camera and restart | Use different candidate sets, mounted items, and last ND sources on two cameras; switch and restart. Each restores independently. Assigning the same physical set to both is allowed. |
| Combined cap | At 30 total stops with no more than three ND wheels, mount Record-only GND. Enabling its non-zero contribution is rejected; Cancel or rejected Apply cannot change the committed stack. CPL/Color/Effect all share the same total budget. |

Additional regression checks:

1. Two distinct equal-strength ND items may both be selected; the same item id
   cannot. A sighted unavailable-row fallback uses only the traversed interval.
   Screen-reader adjustment skips unavailable candidates without wrapping.
2. ND source groups sort by ND subtotal, preserving identity and effective total.
   Auxiliary changes do not move them. Screen-reader mode freezes ND order;
   disabling it reconciles once after settlement. Reorders animate stable items.
3. Tap Plus adds its displayed ND source once. A changed final ND source adds
   once after settling; intermediate sources or returning to the starting source
   add nothing. The auxiliary action only opens the popup. Drag cancels long
   press; a stationary long press opens management. Failed additions do not
   change source memory. Verify header entry with Plus absent.
4. CPL decimal input supports locale separators and rejects 0, 10, and 1.25.
   Editing away a choice mounted on any camera is blocked with affected cameras
   identified. Consecutive new Fixed/GND items retain session notation; cancel,
   edits, and CPL creation do not change that memory.
5. Switch global notation: ND1000 uses 10 / 3.0 / 1000 and exactly 10 canonical
   stops; Empty uses 0 / 0.0 / 1. Auxiliary current contributions remain labeled
   stops and distinguishable from original registered metadata.
6. At the most constrained supported film/Target layout, verify ND-only four
   spaces and auxiliary-plus-three-ND. Summary, Base Shutter, numeric ND values,
   labels, Total, existing results, and controls remain readable without adding
   a vertical panel. Total yields no space to a long source caption. Repeat in
   light/dark, Korean/English, and supported text sizes on both platforms.
7. Exercise inventory rename, recolor, deterministic ordering, Filter Item
   movement between Sets, item edit, and targeted deletion. A moved item's
   stable identity and every referencing camera stay correct; the destination
   Set becomes selected for an affected camera when needed. Captured timer
   names, modes, contributions, and totals remain immutable. Source color never
   changes an optical color.
8. Restore legacy Standard and legacy mixed snapshots, including CPL/GND-only
   stacks and unresolved item references. Verify the new presentation retains
   valid committed contributions and does not reinterpret GND recording as loss.
9. Verify actual empty-wheel cleanup announces once, never removes mounted
   Record-only GND, and keeps one ND wheel. Auxiliary summary and popup controls
   remain accessible with their current state and explicit actions.

## Non-goals

- Automatic compatibility checks between holders, filter sizes, lenses, or
  Filter Sets, and recommendations about which physical filters to combine.
- Inferring filter behavior, optical color, or exposure loss from a product name.
- A separate memo feature or additional permanent main-screen information panel.
- Estimating a CPL's current loss from rotation angle or a GND's partial-frame
  coverage.
- Cross-device inventory synchronization, import, export, and purchase advice.
- A Shooting Collection editor or general photographic-equipment inventory.
