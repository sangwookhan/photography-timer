<!-- Copyright © 2026 Sangwook Han -->
<!-- SPDX-License-Identifier: Apache-2.0 -->

# Shooting Collections

## Purpose

A photographer can preserve selected timer events together and review each
record after leaving and reopening the app.

## Requirements

### Selection and creation

- **COLLECTION-001** — The user can select one or more completed or canceled
  timer events in History and create a Shooting Collection from them.
- **COLLECTION-002** — A timer event belongs to at most one Shooting
  Collection. An event already included in a Collection cannot also be
  included in another.
- **COLLECTION-003** — The user can cancel selection or creation without
  creating a Collection or changing membership.
- **COLLECTION-004** — If creation cannot be saved, the user is informed and
  no new Collection or membership is committed or presented as successfully
  saved. The selection remains available for retry or cancellation.
- **COLLECTION-005** — A newly created Collection receives a date-based title
  automatically, using the earliest start time among its selected events.
  The date is determined in the device's local time zone at Collection
  creation and retained; later time-zone changes do not rename it.
- **COLLECTION-006** — History events already included in a Collection remain
  visible during selection, identify their Collection, and cannot be selected.
- **COLLECTION-007** — Creation is unavailable with no eligible event selected.
  Creating from a nonempty selection requires no title-entry step and opens
  the newly created Collection's detail only after saving succeeds.

### Suggested selection

- **COLLECTION-SELECT-001** — Selecting an event checks only that event.
  The first currently selected event in selection order is the suggestion
  anchor. If it is deselected, the next remaining selected event becomes
  the anchor. No selection means no suggestion.
- **COLLECTION-SELECT-002** — Suggested events are unselected, uncollected
  completed or canceled events still present in History whose start times
  are within 30 minutes before or after the anchor's start time, including
  both boundaries. This compares actual instants, including across midnight;
  camera and film differences do not exclude an otherwise eligible event.
  Location is not used or inferred.
- **COLLECTION-SELECT-003** — When at least one suggested event exists, the
  selection screen shows a marker immediately below the anchor record,
  with the additional event count and a labelled View action. Suggested
  candidate rows carry a visible time-suggestion badge distinct from their
  checkbox. Neither marker nor badges change selection. No marker is shown
  when there are no additional eligible events.
- **COLLECTION-SELECT-004** — Confirming the preview adds only the chosen
  preview candidates that remain eligible to the existing selection, without
  removing any selection or expanding the time window through additions.
  The user may select or deselect individual events afterward. Counts reflect
  current selection and eligibility. This does not create or save a Collection;
  the explicit creation action remains required.
- **COLLECTION-SELECT-005** — View or a long press on the anchor record opens
  a compact, scrollable suggestion preview. Both routes open the same preview
  without toggling a checkbox. Checking, unchecking, changing the anchor, and
  updating suggestions never automatically open the preview. The visible View
  action remains available so discovery does not depend on a gesture.
- **COLLECTION-SELECT-006** — The preview lists the suggested records, including
  their available captured identity, start times, and start-time differences
  from the anchor. Candidates begin checked within this preview and can be
  individually unchecked before the explicit Select together action. Records
  outside the main list's visible area remain inspectable in the preview.
  With no preview candidates checked, confirmation is unavailable.
- **COLLECTION-SELECT-007** — Closing or dismissing the preview discards its
  working checks and leaves the main selection unchanged. It can be reopened
  on request with the then-current candidates. Confirmation never adds newly
  appeared events that were not shown in that preview or events that have
  since become ineligible. A changed anchor invalidates the earlier preview.

### Review and preservation

- **COLLECTION-010** — The user can reach the Collection list from the timer
  workflow, open a Collection, and inspect each included record individually.
  The list remains reachable when History is empty.
- **COLLECTION-011** — A Collection and its included records remain available
  after app termination and relaunch.
- **COLLECTION-012** — Removing a timer from History, including clearing
  History, does not delete a record already preserved in a Collection.
  Timer workspace removal behavior is defined in `timers/workspace.md`.
- **COLLECTION-013** — Records retain their captured timer state and available
  shooting context; later changes to the active camera, film, or calculator
  do not rewrite captured values. Timer identity is governed by
  `timers/lifecycle.md`.
- **COLLECTION-014** — A record missing information that an earlier version
  did not capture remains inspectable. Missing information is not inferred
  from the current shooting setup or reconstructed by parsing display text.
  Available legacy display text remains inspectable as captured text without
  being treated as evidence of unavailable structured fields. A manual timer
  event remains eligible without borrowing camera, film, or exposure-source
  information from the current shooting setup; this is distinct from a
  manually entered external shooting record.
- **COLLECTION-015** — Creating or reviewing a Collection does not stop,
  restart, or modify an active timer. The compact timer presence and timer
  workspace remain available under `timers/workspace.md`.
- **COLLECTION-016** — Collection list entries identify the Collection by its
  title and open its detail. Collections order most-recently-created first;
  included records order earliest-started first. Ties resolve deterministically.
  An empty Collection list shows an explanatory empty state.
- **COLLECTION-017** — Each record's detail shows its captured terminal state,
  start and terminal times, configured duration, and remaining time at
  cancellation when available. It also shows the captured camera and film,
  exposure source, base shutter, ND attenuation, adjusted shutter, filter
  record, and additional profile or model information when available.
  Unavailable values are omitted, subject to COLLECTION-014.
- **COLLECTION-018** — Collection membership and captured records survive
  independently of their History entries. Restarting a timer from an existing
  event creates a different event under `timers/workspace.md`; it does not
  inherit the original event's Collection membership.

### Removing and moving preserved records

- **COLLECTION-MEMBERSHIP-001** — The user can request removal or movement of
  one or more preserved records from a Collection's record list. Removing a record
  changes only its Collection membership; it does not delete the captured
  record or its original History event. It must not hide, filter out, or
  remove that event from the Timer list. Only the Collection membership and
  its membership indication change; Timer-list contents and order remain
  unchanged.
- **COLLECTION-MEMBERSHIP-002** — Before removal, confirmation identifies the
  record or selected record count and explains that captured information
  remains preserved without
  a Collection. Canceling or dismissing confirmation changes nothing. A
  successfully removed record remains individually inspectable in an
  uncollected-record view reachable from the Collection list, including when
  its original History entry has already been removed.
- **COLLECTION-MEMBERSHIP-003** — The user can move one or more records to a
  different existing Collection by choosing the destination and explicitly confirming
  the move. The source Collection is not a valid destination. Canceling or
  dismissing the destination choice changes nothing. If no valid destination
  exists, the user is informed and no move occurs.
- **COLLECTION-MEMBERSHIP-004** — A move preserves the record's identity and
  captured information and commits the source removal and destination addition
  together for the entire chosen selection. At no committed point may the record belong to two Collections
  or disappear between them. A preserved uncollected record can use the same
  destination-selection flow to join an existing Collection.
- **COLLECTION-MEMBERSHIP-005** — Removal and movement take effect only after
  saving succeeds. A failed save retains the previous content, membership and
  current destination, informs the user, and permits retry. An unreadable
  archive must not be overwritten. Relaunch preserves successful changes.
- **COLLECTION-MEMBERSHIP-006** — Removing or moving the last record leaves
  the source Collection in the list with an explanatory empty detail state.
  It does not delete or hide that Collection. A destination Collection keeps
  its title and creation time; included records follow COLLECTION-016.
- **COLLECTION-MEMBERSHIP-007** — These operations do not modify Timer runtime
  or History. Recollecting an original event still present in History must
  reuse its preserved identity and captured record rather than create a
  second independent record. History entries already removed are not
  recreated, and an event continues to belong to at most one Collection.

- **COLLECTION-MEMBERSHIP-008** — Normal mode keeps the existing record-row
  height and information, without permanently visible per-row removal or
  movement controls. A trailing swipe reveals labelled Move and Remove
  actions for that record. Edit enters a selection mode with row selection
  indicators and side-by-side Move and Remove actions in the bottom action
  area; both require a nonempty selection. Done clears selection and exits
  editing without rolling back committed actions. Removing or moving a
  selection uses the same confirmation and failure rules as a single record.
  Failure retains the selection for retry. Edit mode disables interactive
  dismissal and swipe actions. Existing chronological record ordering remains
  unchanged; editing does not introduce drag reordering.

- **COLLECTION-MEMBERSHIP-009** — Movement destinations show the Collection
  title, record count, earliest captured start and latest available captured
  terminal time, location information when recorded, and a representative
  camera. Missing time, location or camera information is indicated without
  inference from current settings. A partial set of terminal times is labelled
  as incomplete. The representative camera is the captured camera identity
  used by the most records; ties choose the camera whose first record starts
  earliest, then stable record identity. Its displayed name comes from that
  camera's earliest available captured name. Other captured camera identities
  are counted separately, and records missing camera information are indicated.
  Location capture is not introduced by destination presentation. Destination
  metadata uses the row's available horizontal space and does not change the
  normal Timer or Collection record-row summaries.

## Non-goals

- Editing a Collection title or its shooting context.
- Adding new History events to an existing Collection, apart from assigning
  an already-preserved uncollected record.
- Permanent deletion of Collections or preserved records.
- Hiding or automatic retention cleanup.
- Group selection without preview confirmation, or opening the preview
  automatically while checking records.
- Location capture, field photos, external manually recorded shots, export,
  backup, sharing, and cross-device synchronization.
