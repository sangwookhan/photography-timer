<!-- Copyright © 2026 Sangwook Han -->
<!-- SPDX-License-Identifier: Apache-2.0 -->

# Timer Workspace

| Prefix | Owns |
| --- | --- |
| WORKSPACE | Timer surfaces (compact dock, full-screen workspace) and ordering |
| WORKSPACE-CARD | Card content in the full-screen workspace |
| WORKSPACE-MINI | The compact dock's mini-timer cards |

## Purpose

A photographer needs to keep preparing the next exposure while earlier
timers continue running, and needs a place to inspect and act on every
timer at once. PTimer splits this across two surfaces: a compact dock that
stays on the shooting screen alongside the calculator for a glanceable
read, and a full-screen Timers workspace, reached from that dock, for full
timer management.

## Current behavior

Timers are presented on two surfaces: a compact dock on the shooting
screen (glanceable; the calculator remains the primary content there), and
a full-screen Timers workspace reached from the dock for inspecting and
acting on every timer at once.

## Requirements

### Surfaces and structure

- **WORKSPACE-001** — Timers are presented on two surfaces: a compact dock
  on the shooting screen (a glanceable strip anchored at the bottom;
  calculator remains primary), and a full-screen Timers workspace showing
  the full timer list. The full-screen workspace is a separate destination,
  not a partial-height overlay of the shooting screen.
- **WORKSPACE-002** — Both surfaces are projections of the same runtime
  timer collection; neither shall maintain a separate copy of timer state
  or independently reorder timers.
- **WORKSPACE-003** — Tapping a compact card opens the full-screen Timers
  workspace with that timer's relevant section already in focus (its
  active or terminal group, as applicable). Closing the workspace returns
  to the shooting screen; opening or closing it never itself mutates any
  timer's state.
- **WORKSPACE-004** — On the shooting screen, only the compact dock scrolls
  horizontally; the calculator section above remains pinned. Full-page
  scrolling on the shooting screen is not permitted.

### Ordering

- **WORKSPACE-010** — Active timers (running and paused, not separated from
  each other) order most-recently-created first.
- **WORKSPACE-011** — Terminal timers (completed and canceled) order by
  terminal time, most recent first, and are presented behind the active
  group.
- **WORKSPACE-012** — Ties resolve deterministically so ordering never
  appears unstable to the user.
- **WORKSPACE-013** — Focusing a timer (tapping its card to inspect it more
  closely) is presentation state only; it never reorders, pauses, resumes,
  or otherwise mutates any timer.

### Full-screen workspace actions

- **WORKSPACE-020** — Each row in the full-screen workspace shows state,
  remaining and total time, and state-appropriate inline actions: running
  exposes pause and start-new; paused exposes resume, start-new, cancel,
  and remove; completed/canceled exposes start-again (repeat) and remove.
- **WORKSPACE-021** — *Start new*, from an active row, cancels the current
  timer (keeping it as a terminal canceled record) and starts a fresh timer
  from the same setup and full duration — so no duplicate active timer
  results.
- **WORKSPACE-022** — *Cancel*, from a paused row, stops the timer and
  keeps it as a canceled record; it does not delete it. This is distinct
  from *remove*, which deletes the record entirely.
- **WORKSPACE-023** — *Start again* (repeat), from a terminal row, creates
  a new timer from the record's captured setup and full duration, leaving
  the source terminal record untouched.

### Compact dock

- **WORKSPACE-030** — Compact cards show a primary remaining-time line (the
  dominant signal), a status icon, total duration, and a multi-layered
  progress indicator; they never show a destructive action.
- **WORKSPACE-031** — A layered progress indicator conveys footprint at
  multiple time scales so both a short and a long timer feel responsive; the
  visible layer count is gated by total duration, and only the status icon
  (never a progress bar) may pulse for an active running timer.

## Card content (full-screen workspace)

- **WORKSPACE-CARD-001** — A card's title identifies camera and film; film
  name and duration shall not repeat on the second line.
- **WORKSPACE-CARD-002** — The second line reads "`<source label> <final
  exposure value>`" (e.g. "Reciprocity 01:40.617"), where the source label
  names which exposure value produced the duration (Calculated /
  Adjusted Exposure / Reciprocity / Target Exposure). This surface's
  reciprocity-sourced label reads "Reciprocity," shorter than the "Corrected
  Exposure" label used on the main result card and Reciprocity Details.
- **WORKSPACE-CARD-003** — A basis line shows calculation inputs only
  (e.g. base shutter, ND, adjusted value), rendered in the currently active
  ND notation, and does not repeat the final exposure value already shown on
  the second line.
- **WORKSPACE-CARD-004** — A running or paused timer's primary value is the
  remaining time with a "left" qualifier, right-aligned; it is never shown
  as a slash-separated duration pair.
- **WORKSPACE-CARD-005** — A canceled timer's primary value is the plain
  terminal label "Canceled" — never combined with the remaining-at-cancel
  duration into one string (e.g. not "Canceled · 51s left"). The
  remaining-at-cancel duration is shown separately, as secondary/meta
  information on its own line; both pieces of information remain visible,
  they are just not merged into a single field. The exact typography/layout
  of the secondary line is a presentation design choice, not specified
  further here.
- **WORKSPACE-CARD-006** — A completed timer's primary value reads "Done",
  identically in compact and full-screen presentation.
- **WORKSPACE-CARD-007** — A long primary value (e.g. a multi-hour
  remaining time) remains legible on one line without dominating the card.

## Mini timer (compact dock card)

- **WORKSPACE-MINI-001** — A mini timer card shows, at minimum: a state
  indicator, the primary remaining/terminal value, a film cue, and a camera
  badge. It does not show a calculation basis or ND value — it stays
  compact by design.
- **WORKSPACE-MINI-002** — The state indicator is a meaningful icon
  distinguishing running / paused / done / canceled, with an accessible
  text equivalent — never a plain color dot, so state is not conveyed by
  color alone.
- **WORKSPACE-MINI-003** — While running or paused, the mini shows a thin
  layered progress indicator; a terminal (done/canceled) mini shows none, so
  active-vs-terminal is visually distinguishable from the icon and the
  presence/absence of progress together.
- **WORKSPACE-MINI-004** — A terminal mini shows an explicit "Done" or
  "Canceled" value with a relative-time sub-cue, rather than a raw duration.
- **WORKSPACE-MINI-005** — A long film name truncates with an ellipsis
  rather than wrapping; a timer with no film shows a "No film" fallback.
- **WORKSPACE-MINI-006** — Minis beyond the visible set collapse into one
  compact overflow tile; tapping it opens the full-screen workspace
  scrolled to the relevant section — Active when a running or paused
  timer exists, otherwise History (which covers both completed and
  canceled timers) — rather than focusing a specific hidden timer.
  > ⚠ **Known implementation bug, not fixed in this docs-only change** —
  > the overflow tap's active-vs-history routing currently tests
  > "status is not completed" rather than "status is running or paused,"
  > so a canceled-only overflow can incorrectly route to Active instead
  > of History. Flagged as a follow-up; the intended contract above is
  > what this requirement documents.
- **WORKSPACE-MINI-007** — iOS and Android mini timers present equivalent
  information (icon/state, cues, progress, terminal value, camera badge,
  overflow), even where concrete icon glyphs differ between platforms —
  that glyph difference is an accepted, intentional divergence, not a
  parity gap.

## Non-goals

- Notification grouping or per-timer-kind audio variation for background
  completions; not currently specified (see `timers/alerts.md`).
