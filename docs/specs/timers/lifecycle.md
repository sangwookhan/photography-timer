<!-- Copyright © 2026 Sangwook Han -->
<!-- SPDX-License-Identifier: Apache-2.0 -->

# Timer Lifecycle

| Prefix | Owns |
| --- | --- |
| TIMER | State machine and time semantics |
| TIMER-IDENTITY | What a timer captures at start time |
| TIMER-PERSIST | Persistence and restoration |

## Purpose

A timer represents one camera exposure once the photographer starts it from
a calculator result, Target Shutter, or an explicit manual duration. Its
state is independent of subsequent calculator changes.

## Current behavior

A timer is in exactly one of four states — running, paused, completed,
canceled — and moves between them only along a fixed set of transitions.

## Requirements

### State machine

- **TIMER-001** — A timer is in exactly one of: running, paused, completed,
  or canceled. Completed and canceled are both terminal and distinct from
  each other (an abandoned shot reads as canceled, never as done).
- **TIMER-002** — The only legal transitions are: running ⇄ paused; running
  → completed (wall clock reaches the end); running → canceled; paused →
  canceled. Paused → completed is not a direct transition — a paused timer
  must resume before it can complete.
- **TIMER-003** — A timer's duration is set at creation and shall be
  strictly positive and finite; non-positive, non-finite, or NaN durations
  are rejected before any state is written.
- **TIMER-004** — A paused timer does not consume wall-clock time toward
  completion; its remaining time is exactly the value frozen at pause.
- **TIMER-005** — Resume computes a new end time as *now + frozen
  remaining*; the original end time is not preserved across a pause.
- **TIMER-006** — A pause whose remaining time has already reached zero
  short-circuits directly to completed rather than entering a
  zero-remaining paused state.
- **TIMER-007** — Remaining time has one runtime source of truth, computed
  from state (running: end − now, clamped at zero; paused: frozen value;
  terminal: fixed). No surface maintains an independent copy.
- **TIMER-008** — Every running timer is re-evaluated against wall clock on
  a frequent periodic tick (about every 100 ms), which updates only
  timer-display state; it shall never rebuild the calculator or any
  non-timer surface.

### Timer identity

A timer's identity is a bundle of associations describing which shot it
belongs to, captured once at start time and frozen thereafter.

- **TIMER-IDENTITY-001** — A timer's identity is the union of: the camera
  slot it started from (id and display label as they stood at start time);
  a film descriptor (canonical stock name and profile qualifier, or an
  explicit "no film" marker); and the exposure source that produced its
  duration.
- **TIMER-IDENTITY-002** — The defined exposure sources are: digital result
  (no film selected); film Adjusted Shutter; film Corrected Exposure;
  Target Shutter; and manual (an externally supplied duration). A manual
  timer does not capture any camera-slot or film identity and presents a
  generic basis label rather than borrowing whatever happens to be active.
- **TIMER-IDENTITY-003** — Identity is captured once, at start time, and is
  invariant for the timer's entire lifetime — across running, paused,
  completed, reordered, focused, inspected, and restored states. Later
  changes to the active camera slot, its display name, the active film, or
  the active reciprocity profile shall not retroactively rewrite an
  existing timer's identity.
- **TIMER-IDENTITY-004** — Changing the active ND display notation
  re-renders the basis text of every existing timer — running, paused, or
  terminal — to the new notation immediately; a timer's calculation
  snapshot (the shutter/ND/film/reciprocity values in effect at creation)
  is never fixed to a single notation at creation time.
- **TIMER-IDENTITY-005** — A timer created before a given piece of identity
  or metadata existed does not fail to restore; it degrades to omitting
  that piece of the display, never to an error.

## Persistence and restoration

- **TIMER-PERSIST-001** — The full timer collection shall persist across
  app termination: for every timer, both its runtime state (identity,
  status, timing) and its display presentation (order, display name, basis
  summary) survive a restart.
- **TIMER-PERSIST-002** — The persisted form shall round-trip losslessly.
  An empty collection removes the persisted data entirely rather than
  writing an empty payload.
- **TIMER-PERSIST-003** — On restore: a running timer whose end time has
  already passed restores as completed, with the original end time as the
  completion timestamp (not the restoration moment); a paused timer
  restores with its frozen remaining time intact; a completed timer
  restores with its recorded completion time; a canceled timer restores
  with its recorded cancellation time, unaffected by wall clock.
  Restoration never fires a completion alert, notification, or other
  user-facing feedback — it is silent state recovery only.
- **TIMER-PERSIST-004** — A persisted paused timer whose freeze metadata is
  missing or inconsistent is treated as corrupted input and surfaces as
  completed rather than fabricating a plausible-looking timestamp.
- **TIMER-PERSIST-005** — Persisted timer shapes evolve only through
  backward-compatible additions; a snapshot written by an older release
  shall continue to restore correctly, including any status token the
  older release used.
- **TIMER-PERSIST-006** — When the app returns to the foreground, a running
  timer reconciles against wall clock and updates its state if it completed
  during the inactive period. This state update is silent; whether and how
  a completion alert may fire is owned by `timers/alerts.md` (ALERT-030),
  not restated here.
- **TIMER-PERSIST-007** — On Android, terminating and relaunching the app
  while a timer is running shall not fail to reopen the app: the running
  timer's state restores on reopen (per TIMER-PERSIST-003), and its
  ongoing-timer notification (`timers/alerts.md`) remains available
  afterward, not merely up to the moment of termination.

## Non-goals

- Multi-timer selection, batch actions, or cross-timer linking are not
  currently specified.
- A defined retention policy for completed timers (e.g. "recent items
  only") does not currently exist.
