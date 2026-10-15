<!-- Copyright © 2026 Sangwook Han -->
<!-- SPDX-License-Identifier: Apache-2.0 -->

# Reset

## Purpose

Reset clears the active camera's shooting setup. Because this is
destructive, a single accidental tap must never clear it.

## Current behavior

Reset is reached from the active camera's header row. Activating it
opens a confirmation surface offering one explicit destructive choice,
`Reset settings`, plus Cancel; nothing is cleared until the destructive
choice is chosen.

## Requirements

### Confirmation gate

- **RESET-001** — The system shall present a single Reset entry point on the
  active camera's page.
- **RESET-002** — Activating Reset shall not clear any shooting setup
  immediately. It shall first present a confirmation surface offering one
  explicit destructive choice and a Cancel option.
- **RESET-003** — Canceling, or dismissing the confirmation surface without
  choosing an option, shall leave the active camera's setup unchanged.
- **RESET-004** — The Reset entry point shall be shown only while the active
  camera has something a reset would clear — a non-default film, ND, base
  shutter, or Target Shutter, any mounted auxiliary filter (including a
  zero-contribution Record-only GND), or a non-default calculator input. Camera names and camera-list membership
  shall not make Reset visible. Selected Filter Sets alone shall not make Reset
  visible. Empty and Standard 0 ND wheels alone shall not make Reset visible.
  While the camera's calculator state is already at defaults with no auxiliary
  selection, Reset shall not be shown.

- **RESET-005** — Reset shall have a visible button surface (background or
  border), not plain action text alone. Reset and the adjacent global menu
  shall form a compact control group with distinct non-overlapping targets
  and an ordinary gap; an extra wide spacer shall not separate them.
  The existing confirmation and visibility rules remain unchanged.

### Reset choice

- **RESET-010** — The confirmation surface shall offer one destructive choice,
  worded identically on both platforms: **"Reset settings"**.
- **RESET-011** — Choosing "Reset settings" shall clear the active camera's
  selected film and reciprocity profile, ND filter stack, every auxiliary
  filter selection, base/adjusted shutter, exposure scale mode, and Target
  Shutter, restoring each to the shipping default. Auxiliary selections shall
  clear regardless of contribution, including Record-only GND. The camera's
  selected Filter Sets shall remain selected; Reset shall not delete or modify
  global Filter Sets or Filter Items. The remembered Plus Filter Source shall
  remain unchanged while that source exists. The camera name, list position,
  pager inclusion, and identity shall be preserved.
- **RESET-012** — RETIRED. Reset does not change a managed camera's name.
- **RESET-013** — The destructive choice shall use a destructive
  (warning/error) visual treatment, consistent with other destructive
  confirmations in the app.

### Platform parity

- **RESET-020** — iOS and Android shall expose identical reset semantics: one
  settings-only path that preserves camera-list state and names. Neither
  platform shall offer a reset capability the other does not.
- **RESET-021** — The Reset choice label shall be identical text on both
  platforms.
- **RESET-022** — The Reset entry point's visibility rule (RESET-004) shall
  be identical on both platforms.

## Scope

- Reset acts on the active camera only; other cameras are unchanged.
- Existing running, paused, completed, or canceled timers are unchanged by
  Reset.
- Reset does not delete custom reciprocity profiles or global preferences.

## Non-goals

- An undo-after-reset affordance. The confirmation step is the only
  mitigation for an accidental tap.
- Expanding what a reset clears beyond the fields in RESET-011.
- A shared cross-platform localization resource for the Reset choice label
  (RESET-021 only requires the literal text to match; how it is delivered
  is an implementation concern).
