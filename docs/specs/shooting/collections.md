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
  no partially created Collection or partial membership is presented as
  successfully saved.
- **COLLECTION-005** — A newly created Collection receives a date-based title
  automatically.

### Review and preservation

- **COLLECTION-010** — The user can reach the Collection list from the timer
  workflow, open a Collection, and inspect each included record individually.
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
  from the current shooting setup.
- **COLLECTION-015** — Creating or reviewing a Collection does not stop,
  restart, or modify an active timer. The compact timer presence and timer
  workspace remain available under `timers/workspace.md`.

## Non-goals

- Editing a Collection title or its shooting context.
- Adding, removing, or moving records after Collection creation.
- Hiding or automatic retention cleanup.
- Location capture, field photos, external manually recorded shots, export,
  backup, sharing, and cross-device synchronization.
