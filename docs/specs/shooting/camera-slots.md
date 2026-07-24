<!-- Copyright © 2026 Sangwook Han -->
<!-- SPDX-License-Identifier: Apache-2.0 -->

# Camera Slots

## Purpose

A photographer running two to four cameras through the same shooting session
(for example a digital body alongside a film body, or two film bodies loaded
with different stocks) needs each camera's calculator setup preserved
independently, and needs to switch between them without rebuilding the
calculator or losing a running timer's identity.

## Current behavior

The shooting workspace exposes four fixed camera slots. Each slot owns a
complete, independent calculator setup; switching the active slot swaps
which setup drives the screen without touching any other slot's state.

## Requirements

### Slot identity

- **SLOT-001** — The system shall expose exactly four camera slots, each
  with a stable identity and a canonical default display label ("Camera 1"
  through "Camera 4").
- **SLOT-002** — Each slot shall additionally support an optional
  photographer-supplied display name that overrides its canonical label.
  Changing the display name shall not change the slot's stable identity.

### Per-slot state

- **SLOT-010** — Each slot shall own its own: selected film and active
  reciprocity profile, base shutter, ND filter stack, and exposure scale
  mode, plus Target Shutter state. The reciprocity result the user sees is
  recomputed from that stored state whenever the slot is active, not
  stored as its own field. Digital-vs-film workflow is derived entirely
  from whether the slot has a selected film (see `calculator/exposure.md`,
  EXPOSURE-002); it is not an
  independently owned or persisted field.
- **SLOT-011** — A calculator input mutation on the active slot — moving
  base shutter, changing ND, picking a different film, swapping profiles,
  enabling/editing Target Shutter — shall affect only the active slot's
  state.

### Switching slots

- **SLOT-SWITCH-001** — Switching the active slot shall replace the active
  input set with the destination slot's own preserved state; it shall not
  mutate the departing slot's state.
- **SLOT-SWITCH-002** — Switching slots shall not invoke any reset or clear
  path on the calculator, film selection, or reciprocity result of either
  the departing or the arriving slot.
- **SLOT-SWITCH-003** — A slot that has never been visited shall arrive with
  the same defaults a fresh app launch would expose; visiting it shall not
  consume state from another slot.
- **SLOT-SWITCH-004** — The user shall be able to switch the active slot
  from the main shooting workspace through a single, glanceable action, not
  a settings detour.

### Rename

- **SLOT-RENAME-001** — The active slot's display name shall be renamable
  from the slot title in the main shooting workspace.
- **SLOT-RENAME-002** — Leading/trailing whitespace shall be trimmed from a
  submitted name; empty or whitespace-only input shall be treated as a
  request to reset to the canonical default label.
- **SLOT-RENAME-003** — An explicit "reset to canonical name" action shall
  be available to return a renamed slot to its default label.
- **SLOT-RENAME-004** — Renaming a slot shall affect only its display
  identity: it shall not change the slot's stable id, calculator state, film
  selection, reciprocity result, any other slot's state, or the slot label
  already captured on a timer that started before the rename.

### Timer identity capture

- **SLOT-TIMER-001** — A timer captures the camera slot identity (stable id
  and display label as they stood at start time) at creation time. Renaming
  the camera afterward, or switching the active slot, shall not retroactively
  change an already-created timer's captured identity.

## Persistence

- **SLOT-PERSIST-001** — The active slot id, every visited slot's calculator
  state, and any custom slot display names shall survive an app restart.
- **SLOT-PERSIST-002** — An unknown or unresolvable persisted slot id shall
  be skipped safely rather than fabricate a phantom slot.
- **SLOT-PERSIST-003** — A snapshot written before the multi-slot session
  existed shall continue to restore correctly: the legacy single-context
  shape seeds the first multi-slot session after upgrade, and the next save
  writes the multi-slot shape.
- **SLOT-PERSIST-004** — Persisted slot state shall evolve only through
  backward-compatible additions; a snapshot that predates a since-added
  optional field (such as a custom display name or a Target Shutter value)
  shall continue to restore correctly, with the missing field treated as
  absent.

## Non-goals

- Configurable slot count. The current product exposes exactly four fixed
  slots; it is not a user-configurable number.
- Broad camera/film inventory management (bulk import, tagging, per-camera
  notes) beyond the four-slot working set. Beyond four simultaneous cameras
  the feature would become an inventory manager, which is out of scope.
