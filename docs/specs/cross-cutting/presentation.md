<!-- Copyright © 2026 Sangwook Han -->
<!-- SPDX-License-Identifier: Apache-2.0 -->

# App Shell Presentation

| Prefix | Owns |
| --- | --- |
| SHELL | Orientation, screen structure, density tiers, accessibility, and touch targets |

## Purpose

A few presentation rules apply to the whole app rather than to any single
capability — orientation, how the shooting screen shares room between the
calculator and a compact timer presence, how all app surfaces adapt to
available width, height, system-reserved space, and font scale, and baseline accessibility/
interaction guarantees. This file exists so those rules have a clear owner
instead of being attached to whichever capability happened to be
documented last.

## Current behavior

The app retains portrait on phones and folded outer displays where the
operating system permits it, and adapts to tablet, unfolded, and
system-controlled window configurations. The shooting screen is the app's primary
screen: it hosts the calculator plus a compact timer presence (see
`timers/workspace.md`) without a screen transition. Full timer management
is a separate full-screen destination, reached deliberately from that
compact presence, not folded into the shooting screen itself.

## Requirements

### Orientation and screen structure

- **SHELL-001** — Phones and folded outer displays shall retain portrait
  orientation where the operating system permits it. Tablets, unfolded
  displays, and operating-system-controlled window shapes shall adapt to
  their available width and height without depending on that lock. The
  app shall not require a user to rotate a system-controlled window to
  reach a function. Voluntarily enabling landscape on otherwise
  portrait-lockable phone or outer displays is outside this contract.
- **SHELL-002** — The shooting screen hosts both exposure calculation and a
  compact timer presence as one primary surface: the user adjusts exposure
  and starts, glances at, or manages the compact set of running timers
  without a screen transition. Full timer management (the full-screen
  Timers workspace, `timers/workspace.md`) is a separate navigational
  destination, deliberately reached from the compact presence rather than
  folded into the shooting screen.

### Layout density

- **SHELL-010** — Layout shall adapt to the width and height actually
  available to its content, including changes during use. Related controls
  and content may move, wrap, or change presentation while preserving
  their meaning and information hierarchy.
- **SHELL-011** — RETIRED: height-only selection among three fixed density
  tiers is superseded by adaptation to available width and height.
- **SHELL-012** — The space needed by each layout arrangement shall account
  for its simultaneously visible content, spacing, readable values, and
  interactive targets. An arrangement that cannot fit shall be reworked to preserve readable
  content and usable targets. It shall not silently fall back to vertical
  scrolling of the main shooting content in ordinary supported conditions.
  Extra space shall not force controls or text into unbounded stretching.

### Adaptive access and continuity

- **SHELL-050** — Every app function shall remain reachable on narrow,
  wide, short, and tall supported windows. This applies to shooting,
  selection, management, editing, details, settings, and timer surfaces.
  Secondary destinations may use deliberate navigation and scrolling.
  Main shooting content is governed by SHELL-057; reachability alone shall
  not be used to bypass its no-vertical-scrolling requirement.
- **SHELL-051** — System bars, display cutouts, reserved camera regions,
  separating or occluding folds/hinges, and window controls shall not hide
  required content or interactive targets without a way to reach and use
  them. Decorative backgrounds may extend into system areas.
- **SHELL-052** — When the keyboard is shown, the active input and its
  required validation and commit/cancel actions shall remain reachable.
  Resizing or scrolling to reach them shall not commit or discard input.
- **SHELL-053** — Resizing, rotating, folding, or unfolding shall preserve
  the active camera, its shooting settings, uncommitted edits, and the
  user's current task. An open selection, editor, sheet, or dialog may
  change presentation but shall not silently dismiss, confirm, or cancel
  its task. The currently relevant item and focus shall remain reachable.
- **SHELL-054** — A layout transition shall not itself start, duplicate,
  pause, resume, cancel, remove, or reset a timer, nor alter its captured
  identity, ordering, or completion behavior. Timer runtime behavior is
  governed by `timers/lifecycle.md`.
- **SHELL-055** — Layout changes shall retain related control groupings
  and a predictable reading and interaction order. Returning to a previous
  window configuration shall restore the applicable arrangement without
  discarding the user's task or creating duplicate state.
- **SHELL-056** — iOS and Android shall provide equivalent functions,
  information hierarchy, and task continuity for equivalent available
  space. Native navigation, modal presentation, system bars, icons, and
  accessibility mechanisms may differ. Both platforms remain subject to
  the reachability and accessibility contracts in this file.

- **SHELL-057** — At device-default font size, ordinary shooting on every
  supported window shall show the current camera and film context, base
  shutter and filter controls, applicable exposure results and start
  actions, and compact timer presence without vertical scrolling of the
  main shooting content or its individual regions. Reflow shall preserve
  readable values and usable interactive targets rather than hide, clip,
  or excessively shrink them. Secondary selection, management, editing,
  details, and full timer destinations may retain their own scrolling.
- **SHELL-058** — Insufficient space shall not automatically enable main
  shooting vertical scrolling or silently exclude a supported display.
  The minimum supported window and any exceptional condition permitting
  such scrolling require an explicit product decision. Keyboard-visible
  input remains subject to SHELL-052; it does not by itself authorize a
  general scrolling fallback for ordinary shooting.
  The Android portrait app-window configuration of 360 × 640dp, measured
  before system-bar and compact-timer reservations, is outside the supported
  ordinary-shooting window set. This exclusion does not establish a general
  minimum width or height, exclude other windows merely because they are
  360dp wide, or exempt a fold region within a supported window. Supported
  phone, foldable, and tablet windows retain SHELL-057 and SHELL-061/062;
  this exclusion does not introduce a new scrolling mode.

### Arrangement and reserved-space rules

- **SHELL-059** — Use a bounded single-column shooting arrangement when
  only one readable input/result column fits. When both groups fit side
  by side, place shooting inputs in the leading column and exposure
  results with their start actions in the trailing column. Arrangement
  selection shall account for the actual content and compact timer
  placement, not a device-name lookup or width threshold alone. Content
  shall not stretch without bound on a larger window. Changing result
  categories, supported filter counts, or Target Shutter visibility shall
  not make required shooting content inaccessible.
- **SHELL-060** — Selection, management, editing, and details shall use
  bounded modal presentations on wide windows rather than stretching
  ordinary form controls across the window. Compact presentations may
  use sheets. Presentation changes shall preserve task semantics,
  Apply/Save/Cancel behavior, and the content hierarchy owned by each
  capability spec. This does not authorize permanently embedding those
  tasks into the shooting screen.
- **SHELL-061** — When an active or separating fold divides usable space,
  position the book arrangement's column gap or the tabletop arrangement's
  horizontal gap on the reported fold region. Required labels, camera
  page indicators, values, timer cards, and interactive targets shall
  remain within usable regions rather than span the fold. Decorative
  backgrounds may span it. A line-shaped fold still requires clearance
  sufficient to keep targets readable and operable; a fixed angle or
  assumed screen midpoint shall not determine the fold boundary.
- **SHELL-062** — In tabletop presentation, place camera/film context and
  exposure results with their start actions above the fold, and shooting
  inputs below it. In book presentation, keep camera/film context and
  inputs in the leading region and results in the trailing region.
  Compact timer placement follows `timers/workspace.md` and shall also
  clear the fold. Transitions preserve the same shot and timer state.
  One limitation is accepted by product decision for a single case only:
  tabletop presentation on an Android foldable inner display of about
  704 × 933dp in portrait, as measured on the Galaxy Fold8-class
  substitute emulator with the fold reported at the panel centre, with a
  film offering a model choice, an active Target Shutter, three filter
  wheels with auxiliary filters, and three result rows. There the inputs
  need about 380.2dp below the fold while about 378.5dp is available, even
  with the compact timers kept above the fold, so the stacked arrangement
  that is used instead crosses the fold. This records a measured shortfall
  on the substitute emulator, not a physical-device result or a fold-safe
  outcome. It is separate from the 360 × 640dp exclusion in SHELL-058 and
  does not exempt lighter content, book presentation, other foldables, or
  other postures from SHELL-061 and this requirement.

### Large text and constrained height

- **SHELL-020** — Required shooting-flow controls and corrected-exposure
  content shall remain reachable, legible, and operable when the system font
  scale is large and the available height is constrained. To preserve a
  usable layout, a platform may cap the effective font scale for the shooting
  surface or specific areas, including primary content, and use different
  caps in different areas. The resulting presentation shall not clip or
  obscure required values or controls, and the capped text shall remain
  readable; where room permits, text may grow with the system setting up to
  its area's cap. Verify both at the cap and with the system setting above it.
- **SHELL-021** — On Android, an open shooting task shall survive
  configuration/Activity recreation (not a full app restart), as governed
  by SHELL-053. This includes details, selection, editing, and timer
  destinations rather than only sheets and dialogs.

### Android typography

- **SHELL-022** — On Android, labels on the Main shooting screen shall
  remain legible at the standard system font scale and grow with increased
  system font scale where the established layout has room. The auxiliary-filter
  wheel/box region shall retain its existing size and arrangement as font
  scale changes. Enlarging labels shall not displace or obscure required
  shooting values and controls.

- **SHELL-023** — On Android, compact Mini Timer, full-screen Timers, and
  Reciprocity Details shall limit effective text enlargement where otherwise
  required time values, labels, units, descriptions, or actions would be
  truncated, obscured, or made difficult to use. Each surface shall preserve
  readable required information and operable controls at the maximum system
  font scale. Unaffected screens shall retain their established presentation.

### Android phone shooting balance

- **SHELL-024** — On regular Android phones in portrait at default display
  and font settings, the Main shooting surface shall use readable baseline
  typography throughout its labels, auxiliary descriptions, selected wheel
  values, and exposure results. The camera/film header, Target Shutter,
  shutter/filter controls, and result rows shall have heights and internal
  spacing that support that typography and a visual scale comparable to
  equivalent iPhone shooting content. Selected values and results shall
  remain visually prominent.
- **SHELL-025** — With a film and an active Target Shutter, the Main shooting
  surface shall simultaneously show Target Shutter, the ND-adjusted shutter,
  Reciprocity status with its Details entry, and Corrected Exposure, together
  with camera/film context, any applicable model selection, shutter/filter
  controls, and compact timer presence, subject to SHELL-057. Existing
  capability-owned visibility and action rules continue to apply.
- **SHELL-026** — Available vertical space shall support balanced component
  heights and internal spacing across the shooting surface, reducing
  excessive unused space below the results. Space allocation shall account
  for the complete applicable content, including additional result rows and
  compact timers. It shall not hide content, reduce text to an unreadable
  size, or create oversized gaps or unbounded stretching merely to fill
  the viewport.
- **SHELL-027** — Horizontal margins may bound the regular-phone shooting
  column to improve its visual proportions, provided that all supported
  filter configurations retain readable values and usable controls.
  The font-scale, touch-target, and no-vertical-scrolling contracts in
  this file continue to apply.

### Touch targets

- **SHELL-030** — Primary shooting/timer action controls and ND notation
  controls provide a comfortably tappable interactive area, independent of
  their drawn visual size — a visually compact icon or label is not
  permitted to also have a cramped hit area. On Android this is enforced
  as a minimum 48dp interactive target. Visual size may stay smaller than
  the interactive area; this requirement concerns usable interactive area,
  not identical visual size across platforms. The approved compact Android
  Main header is an exception for the Stops / OD / ND notation selector:
  retain its accepted layout, including approximately 42.7dp-wide segments
  in English at a 360dp viewport. This exception does not reduce the minimum
  target for other controls or claim that the selector satisfies 48dp.

### Accessibility semantics

- **SHELL-040** — Core shooting/timer controls remain operable and
  understandable through the platform's screen reader (VoiceOver on iOS,
  TalkBack on Android) without relying on color alone to convey state.

### Graphic resource parity

- **SHELL-041** — Native SF Symbols on iOS and Material icons on Android may
  differ in shape. Any separately supplied app-specific image or icon shall
  use the same original graphic on both platforms, with consistent visual
  proportions and meaning. Native icon differences shall not justify two
  separately drawn versions of an app-specific graphic.

## Non-goals

- New exposure, timer-runtime, or persistence semantics introduced solely
  to accommodate a different screen shape.
- A separate feature set for tablet or foldable users.
