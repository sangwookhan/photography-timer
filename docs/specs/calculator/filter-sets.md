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
  Stops, OD, or ND factor and preserve the original value and unit for display.
  Conversion to canonical stops shall use: Stops unchanged, `OD / 0.3`, and
  `log2(ND factor)`. The result shall be finite, greater than 0, and no greater
  than 30 stops; the calculator shall not snap it to the Standard ladder.
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
- **FILTER-STACK-005** — After all moving wheels settle, actual wheels shall
  sort by source: Standard first, then Filter Sets in user-defined order.
  Within one source, non-empty rows shall sort by canonical registered value
  descending with stable order for ties; Empty shall sort last. A CPL row's
  sort value is its selected exposure-loss choice. A GND row's sort value is
  its registered full-density value in both Record only and Apply full value
  modes, so changing mode does not move the wheel. Reordering shall preserve
  wheel identity and the effective sum.
- **FILTER-STACK-006** — Standard 0 and Filter Set Empty wheels in a multi-wheel
  stack shall follow the existing idle-cleanup and explicit-removal contract in
  `nd-filters.md`. For this mixed stack, FILTER-STACK-006 narrows the immediate
  30-stop cleanup rule: immediate cleanup applies only when the wheel can accept
  no usable row. A Filter Set Empty wheel with an unmounted, selectable
  Record-only item shall remain available for the normal idle interval. A
  mounted Record-only item shall not be cleaned up.
- **FILTER-STACK-007** — A filter wheel shall show compact value, Filter Set
  color, and calculation mode while idle. A Filter Item's compact value shall
  preserve its registered representation independently of the app-global
  Standard notation: for example `ND1000`, `OD 0.9`, `3 stops`, or
  `CPL 1.5`. While moving, a larger non-blocking label shall expose the full
  item name, registered representation, and active contribution in canonical
  stops without moving the touch center. Long names shall remain readable
  without being inferred or silently rewritten.

### Plus wheel and per-camera source memory

- **FILTER-PLUS-001** — The Plus wheel shall remain at the end of the row while
  fewer than four actual wheels exist. Moving it vertically shall select among
  Standard and the Filter Sets in FILTER-SET-004 order; it shall not browse
  filter values.
- **FILTER-PLUS-002** — While the Plus wheel moves, an expanded, non-blocking
  label shall display the complete candidate source name. At rest the compact
  Plus control shall show the candidate source's color as a secondary cue.
- **FILTER-PLUS-003** — Tapping Plus shall add a Standard 0-stop wheel or a
  Filter Set Empty wheel for the settled source. Merely changing the source
  shall not mutate the existing stack or calculation.
- **FILTER-PLUS-004** — Each camera shall remember its last settled Filter
  Source across camera switches and app restarts. A fresh camera and a camera
  whose remembered source no longer exists shall use Standard.
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

- **FILTER-A11Y-001** — Every wheel shall be an adjustable accessibility
  element announcing source, full item name or Empty, contribution, calculation
  mode, position, and disabled reason. Add, remove, source selection, and Filter
  Set management shall have explicit assistive-technology actions.
- **FILTER-A11Y-002** — Color shall be redundant with accessible text and
  state. Required controls and expanded labels shall remain reachable and
  readable under the large-text and constrained-height rules in
  `cross-cutting/presentation.md`.
- **FILTER-A11Y-003** — English and Korean shall expose equivalent terminology,
  validation, calculation modes, and disabled reasons on iOS and Android.

## Verification examples

1. Register two separate 3-stop items in one Filter Set, select both, and
   observe a 6-stop contribution while a second selection of either id is
   unavailable.
2. Combine Standard 2, one Filter Set item at 3, and another Filter Set item at
   4; observe 9 stops before and after source-order sorting.
3. Move Plus from Standard to a Filter Set, observe the expanded source name,
   add Empty, select an item, switch cameras, and verify each camera restores
   its own last source and stack.
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

## Non-goals

- Automatic compatibility checks between holders, filter sizes, lenses, or
  Filter Sets, and recommendations about which physical filters to combine.
- Inferring Fixed, CPL, or GND behavior from a product name.
- Estimating a CPL's current loss from rotation angle or a GND's partial-frame
  coverage.
- Cross-device inventory synchronization, import, export, and purchase advice.
- A Shooting Collection editor or general photographic-equipment inventory.
