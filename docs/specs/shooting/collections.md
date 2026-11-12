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

## Non-goals

- Editing a Collection title or its shooting context.
- Adding, removing, or moving records after Collection creation.
- Hiding or automatic retention cleanup.
- Location capture, field photos, external manually recorded shots, export,
  backup, sharing, and cross-device synchronization.
