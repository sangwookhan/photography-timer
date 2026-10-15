<!-- Copyright © 2026 Sangwook Han -->
<!-- SPDX-License-Identifier: Apache-2.0 -->

# Camera List

## Purpose

A photographer may own more or fewer cameras than the fixed working slots
previously provided, and may use a different subset of those cameras in each
shooting session. The photographer needs a manageable camera list, a shooting
pager that reflects the selected cameras in a deliberate order, and timers
whose identity remains stable after camera-list changes.

## Current behavior

The shooting workspace exposes a managed camera list. The shooting pager uses
the displayed subset in global list order, while every managed camera retains
its independent calculator setup.

## Requirements

### Retired fixed-slot requirements

- **SLOT-001** — RETIRED. The product no longer exposes exactly four fixed
  camera slots. A managed camera list replaces the fixed working set.
- **SLOT-002** — RETIRED. Display names now belong to managed cameras rather
  than fixed slot identities.
- **SLOT-010** — RETIRED. Per-camera calculator state is governed by
  CAMERA-STATE-001.
- **SLOT-011** — RETIRED. Per-camera calculator-state isolation is governed
  by CAMERA-STATE-002.
- **SLOT-SWITCH-001** through **SLOT-SWITCH-004** — RETIRED. Pager behavior
  is governed by CAMERA-PAGER-001 through CAMERA-PAGER-004.
- **SLOT-RENAME-001** through **SLOT-RENAME-004** — RETIRED. Camera naming is
  governed by CAMERA-NAME-001 through CAMERA-NAME-003.
- **SLOT-TIMER-001** — RETIRED. Timer identity capture is governed by
  CAMERA-TIMER-001.
- **SLOT-PERSIST-001** through **SLOT-PERSIST-004** — RETIRED. Camera-list
  persistence and migration are governed by CAMERA-PERSIST-001 through
  CAMERA-PERSIST-008.

### Camera list

- **CAMERA-001** — The user shall be able to add, rename, hide, show, delete,
  and reorder cameras in a managed camera list.
- **CAMERA-002** — The product shall impose no numerical limit on the number
  of cameras retained in the managed list or selected for the shooting pager.
- **CAMERA-003** — A newly added camera shall have a localized `Camera N`
  default name issued by a dedicated, durable automatic-name sequence. The
  initial four cameras consume numbers 1 through 4, so the first added camera
  is `Camera 5`. Each automatic creation reserves its number durably before
  the camera record is committed. A failed or interrupted creation may leave a
  gap, but an issued number shall not be reused while the stored sequence
  remains readable. When it cannot be read, CAMERA-PERSIST-007 restarts normal
  allocation at 5 and may repeat a display name without reusing identity.
  Renaming, hiding, or deleting a camera, and a user manually entering any
  `Camera N` name, shall neither
  release nor advance the sequence. User-entered duplicate names remain
  allowed. The generated name is frozen as stored text after creation. The
  camera shall be included in the shooting pager and shall become active.
- **CAMERA-004** — Each camera shall have a stable identity that is never
  reassigned to a different camera after deletion. Migration shall retain the
  existing raw identities `camera1` through `camera4` verbatim. New identities
  shall be collision-free with every identity ever issued, including deleted
  cameras, and shall not be derived from a list position or display name.
- **CAMERA-005** — Hiding a camera shall preserve its name, calculator state,
  and list position. Showing it again shall restore it to the shooting pager
  at that position.
- **CAMERA-006** — Deleting a camera shall remove its camera-list entry and
  calculator state after the user confirms the deletion. The confirmation
  shall explain that creating or renaming another camera to the same display
  name will not reconnect the deleted camera's state or timers. The product
  provides no timed deletion-undo state.
- **CAMERA-007** — The user shall be able to select several cameras and hide
  or delete the selected cameras in one action. A bulk deletion shall require
  one confirmation that identifies the affected cameras or their count. Bulk
  show is not part of this capability. A bulk action applies to its selected
  identities at confirmation time; entries no longer present are ignored.

### Naming and ordering

- **CAMERA-NAME-001** — Camera names shall be trimmed before saving. A blank
  or whitespace-only submitted name shall be rejected and shall leave the
  stored name unchanged.
- **CAMERA-NAME-002** — A camera rename shall affect that camera's current
  list and pager label only. Reusing a current or historical name shall not
  change camera identity or inherit, reconnect, or merge calculator state or
  timer history.
- **CAMERA-NAME-003** — Camera names need not be unique. Camera management
  shall provide enough row context to distinguish current duplicate names
  without exposing the raw camera identity as the ordinary user-facing label.
- **CAMERA-NAME-004** — The automatic-name sequence is independent of camera
  identities, display names, list order, list count, and timer records. Its
  next value shall never be reconstructed from any of those current values.
- **CAMERA-ORDER-001** — The managed list shall have one global user-defined
  order. Hiding a camera shall not change that order.
- **CAMERA-ORDER-002** — Reordering a camera shall update the global order
  and shall not alter its calculator state or timer history.

### Shooting pager and management

- **CAMERA-PAGER-001** — The shooting pager shall display only cameras
  included in the pager, in global camera-list order.
- **CAMERA-PAGER-002** — The main shooting workspace shall retain the Settings
  route to camera management and shall also provide direct `Manage cameras`
  and `Add camera` actions while timers are running.
- **CAMERA-PAGER-003** — Hiding or deleting the active camera shall activate
  the next displayed camera in the resulting global order; when no later
  displayed camera exists, the first displayed camera in that resulting list
  shall become active. When no camera is displayed, no camera is active. If a
  hidden camera is shown while no camera is active, that shown camera becomes
  active.
- **CAMERA-PAGER-004** — When no camera is included in the shooting pager,
  including when the managed list is empty, the shooting workspace shall show
  the same camera icon, title `No cameras shown`, explanation `Show or add a
  camera to calculate exposures. Running timers are not affected.`, and
  `Manage cameras` then `Add camera` action order on iOS and Android. Existing
  timers and the independent manual-timer path remain available; a calculator-
  bound timer cannot start until a displayed active camera exists.
- **CAMERA-PAGER-005** — In normal mode, an individual camera row shall use
  the same visible interaction hierarchy on iOS and Android: tapping the name
  opens rename, the trailing eye/eye-slash control directly hides or shows the
  camera, and a trailing swipe reveals `Delete`. Delete is not persistently
  visible on the row and shall require confirmation before removing data.
  The visible row presents the stored name plus global-order position and
  shown/hidden state in the same order on both platforms.
- **CAMERA-PAGER-006** — Camera-management actions shall be available through
  accessible controls in addition to gesture-only interaction. Edit mode shows
  a drag handle and supports drag reordering on both platforms; non-drag
  `Move up` and `Move down` alternatives remain available in edit mode to
  VoiceOver and TalkBack without permanently displaying arrow buttons in each
  row. Each
  row's accessible label shall include its name, shown/hidden state, and
  global-order position. After a confirmed deletion or active-camera change,
  iOS shall move VoiceOver focus and announce the resulting camera or empty
  state. Android shall announce that result through TalkBack; moving TalkBack
  accessibility focus to a specific Compose row is not required. Management
  controls shall accommodate long names at supported Dynamic Type and Android
  font-scale sizes.
- **CAMERA-PAGER-007** — When at least one camera is displayed, the shooting
  pager shall place one utility page immediately after the last camera. Normal
  pager movement, including an accessibility next-page action from the last
  camera, may reveal and settle on this page; no separate short/long gesture
  threshold is introduced. The standard page indicator includes this utility
  page, while camera position labels and camera counts exclude it. On arrival,
  accessibility identifies it as `Camera management`. The page shows the same
  camera icon, title `Camera management`, explanation `Manage existing cameras
  or add a new one.`, and `Manage cameras` then `Add camera` action order on
  iOS and Android. It shall not change the active camera,
  calculator state, or any running timer. Reversing the pager returns to the
  last displayed camera. Adding a camera settles on the new active camera.
  When camera management was opened from the utility page, closing it after
  other management edits returns to the utility page while at least one camera
  remains displayed; otherwise the empty state replaces it. When camera
  management was opened from Settings, closing it returns to the current active
  camera, or to the empty state when no camera is displayed. Utility-page
  position is transient and relaunch returns to the active camera. When no
  camera is displayed, CAMERA-PAGER-004 supplies the same two actions.
- **CAMERA-PAGER-008** — Camera management shall have two explicit modes. In
  normal mode, the leading action is an X icon with accessible name `Close`
  and the trailing action is `Edit`. In edit mode, the leading close action
  is absent, interactive dismissal is unavailable, and the trailing action is
  `Done`. `Done` clears selection and returns to normal mode; it does not
  save or roll back changes. Normal mode shows one visibly labelled
  `Add camera` action in the bottom action area. Edit mode replaces it with
  reordering plus side-by-side multi-select `Hide` and `Delete` actions.
  Confirmed actions apply immediately.
- **CAMERA-PAGER-009** — In camera management, creation shall not outweigh
  orientation and management. The top actions (`Close` and `Edit` in normal
  mode, `Done` in edit mode) shall keep the platform's standard toolbar
  appearance, the same as the app's other sheets, with the platform's standard
  high-contrast foreground color. Text labels shall reach at least 4.5:1 and
  icon glyphs at least 3:1 against their background in every appearance that
  the platform supports. Touch targets shall be at least 44 by 44 points
  (48 by 48 dp on Android), and `Done` shall use the platform's emphasized
  text-action weight. In normal mode `Add camera` shall remain in the bottom
  action area as a bordered button without a fill. Its border shall reach at
  least 3:1 against the surrounding surface, its label shall use the
  platform's standard high-contrast text color, and only its leading plus
  glyph may use the accent color at a contrast of at least 3:1. Its visible
  height shall be 44 to 48 points (44 to 48 dp on Android). This secondary
  emphasis shall come from the outlined color treatment and never from
  lowered opacity, so the action still reads as enabled. The same hierarchy
  applies on iOS and Android. Android currently supports dark appearance only;
  its contrast evidence therefore covers dark appearance.
- **CAMERA-PAGER-010** — Every `Add camera` action (camera management, the
  pager utility page, and the all-hidden empty state) shall show a leading
  plus glyph before its visible label on iOS and Android. The glyph is
  decorative: it is hidden from assistive technology and the accessible name
  remains `Add camera`.

### Per-camera calculator state

- **CAMERA-STATE-001** — Each camera shall own an independent calculator
  setup: selected film and reciprocity profile, base shutter, Filter Sets,
  Filter Stack, mounted auxiliary selections, last-used filter source,
  exposure scale mode, and Target Shutter state.
- **CAMERA-STATE-002** — A calculator input change on the active camera shall
  affect only that camera. Switching, hiding, reordering, or renaming a
  camera shall preserve every other camera's calculator state.
- **CAMERA-STATE-003** — A newly added camera shall start with the same
  calculator defaults as a fresh shooting context.

### Timer identity

- **CAMERA-TIMER-001** — A timer shall capture the camera identity and camera
  name that existed when the timer started.
- **CAMERA-TIMER-002** — Renaming, hiding, reordering, or deleting a camera
  shall not interrupt an active timer or alter an active or completed timer's
  captured camera name on any timer surface, including in-app views, Live
  Activities, notifications, and restored timers after relaunch.
- **CAMERA-TIMER-003** — Active and completed timer entries shall remain
  renderable without resolving their captured camera identity against the
  current camera list.

### Persistence and migration

- **CAMERA-PERSIST-001** — The managed camera list, its global order, pager
  inclusion, active camera or explicit absence of an active camera, names, and
  per-camera calculator state shall survive an app restart. The next automatic-
  name number shall survive independently in a dedicated versioned sequence
  store rather than as a value derived from, or owned by, the managed-list
  payload. A fresh installation shall durably persist sequence value 5 before
  committing the managed-list payload that seeds `camera1` through `camera4`,
  in that order and shown in the pager, with localized `Camera 1` through
  `Camera 4` names frozen as stored text. The seeded managed-list payload
  becomes authoritative only after the sequence write succeeds. An explicit
  empty persisted managed list remains empty and is never reseeded; the
  independent sequence remains monotonic.
- **CAMERA-PERSIST-002** — This release supports the fixed-slot storage shapes
  represented by the official 0.8.0 platform fixtures and the latest
  pre-PTIMER-234 official 0.9.1 platform fixtures identified by
  `docs/verification/Strategy.md`. Each migration shall
  preserve the four camera identities, stored or resolved names, calculator
  states, order, pager inclusion, and active camera. It shall persist sequence
  value 5 before committing the managed-list payload, regardless of current
  display names. Sequence initialization and migration are advance-only: a
  retry shall never lower or replace a valid persisted sequence value with a
  smaller value. If the process stops between those writes, retrying the
  migration remains idempotent; a reserved number may be skipped but cannot be
  reused. A legacy slot with no custom name migrates to its resolved current
  display string at migration time; later locale changes do not rename it.
- **CAMERA-PERSIST-003** — Existing camera identities shall remain stable
  across migration so timer metadata captured before migration remains
  meaningful.
- **CAMERA-PERSIST-004** — After stored content is read successfully, a keyed
  camera record with missing fields uses these defaults: a missing identity gets
  a new opaque identity; a missing name uses localized `Camera`; missing pager
  inclusion uses shown; missing calculator state uses fresh-camera defaults; and
  a missing or unusable active identity selects the first shown restored camera,
  or none when no camera is shown. The first occurrence of a duplicate identity
  keeps it and each later occurrence gets a new opaque identity. Surviving
  entries retain stored order; a value that is not a keyed camera record is
  skipped. If the successfully read camera collection, version, or whole managed
  payload cannot be decoded, the app atomically replaces it with the four
  default names and calculator states using newly generated opaque identities,
  shown in order with the first active. The replacement sequence is
  `max(5, readableStoredSequence)`; it uses 5 only when the independent
  sequence is absent or unreadable. The replacement deletes
  the unreadable managed data without exposing an absent-payload interval or
  running legacy migration. Timer records and their captured identity and name
  snapshots remain unchanged. A successfully normalized list is persisted as
  the current shape. If the storage read itself fails and supplies no content,
  the app neither deletes nor writes camera state and retries initialization on
  the next launch.
- **CAMERA-PERSIST-005** — A camera-list edit that affects multiple cameras
  shall apply and persist as one all-or-nothing resulting state: list entries,
  global order, pager inclusion, active camera, and calculator states change
  together. An interrupted save shall not modify timer records. An orphaned
  calculator state is ignored; a valid restored camera without calculator
  state receives fresh calculator defaults.
- **CAMERA-PERSIST-006** — A valid managed-camera payload takes precedence over
  every remaining legacy payload. Legacy migration runs only when no managed-
  camera payload exists. Migration is idempotent: it shall not duplicate
  cameras when retried, and the legacy source remains usable until the complete
  managed-camera state has been persisted successfully. Successfully read but
  undecodable managed data follows CAMERA-PERSIST-004's atomic replacement and
  never exposes an absent-payload state from which stale legacy migration could
  run. A storage read failure performs no deletion, write, or legacy fallback.
  During that launch the camera surface is unavailable, camera actions are
  disabled, and the same explanation appears on both platforms:
  `Camera data couldn't be loaded. Restart the app.` Localized equivalents
  shall carry the same meaning. Initialization is retried on the next launch.
- **CAMERA-PERSIST-007** — Beginning with the first official release that
  writes managed-camera data, each later official managed-camera schema shall
  add an explicit, ordered migration path to the current schema. The migration
  carries the stored next value before activating the newer managed-list
  payload. When no next value can be read, the next `Add camera` action runs the
  normal allocator with 5, durably advances it to 6, and then commits the new
  camera as `Camera 5`; it does not inspect current cameras, names, order, count,
  or timers. Later additions continue from the newly stored value.
- **CAMERA-PERSIST-008** — RETIRED. Development-only Draft and contaminated
  data are cleared instead of entering the product migration contract.
- **CAMERA-PERSIST-009** — RETIRED. Missing sequence state uses the normal
  allocation fallback in CAMERA-PERSIST-007, so no blocked Add state exists.

### Release migration verification

The release-fixture matrix, exact fixture contents, migration routes, and
installed-data upgrade procedure are owned by
[`docs/verification/Strategy.md`](../../verification/Strategy.md). This
contract requires both platforms to satisfy that strategy without duplicating
its version-specific test data here.

### Platform parity

- **CAMERA-PARITY-001** — iOS and Android shall implement the same camera-list
  data guarantees, automatic-name sequence, pager utility and empty-state
  content, management modes, visible action hierarchy, row layout, labels,
  swipe-to-delete discovery, drag-reorder discovery, bottom actions,
  running-timer isolation, and post-action accessibility announcement. iOS
  additionally moves VoiceOver focus as required by CAMERA-PAGER-006; Android
  retains TalkBack's current focus while announcing the result. Platform-native
  modal containers, system typography and spacing, selection
  indicators, confirmation-dialog presentation, and equivalent icon artwork
  may differ without changing that shared interaction design.

## Non-goals

- Camera body, lens, serial number, notes, or other equipment metadata.
- Navigation from a timer entry to a current camera-list entry.
- A persistent relationship that requires timers to resolve against current
  camera records.
- Timed deletion undo or an undo history.
- Changes to exposure calculation or timer behavior.
