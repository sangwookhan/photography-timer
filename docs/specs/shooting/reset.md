<!-- Copyright © 2026 Sangwook Han -->
<!-- SPDX-License-Identifier: Apache-2.0 -->

# Reset

## Purpose

Reset clears the active camera slot's shooting setup. Because this is
destructive, a single accidental tap must never clear it.

## Current behavior

Reset is reached from the active camera slot's header row. Activating it
opens a confirmation surface offering two explicit destructive choices plus
Cancel; nothing is cleared until one of the two choices is chosen.

## Requirements

### Confirmation gate

- **RESET-001** — The system shall present a single Reset entry point on the
  active camera slot's page.
- **RESET-002** — Activating Reset shall not clear any shooting setup
  immediately. It shall first present a confirmation surface offering two
  explicit destructive choices and a Cancel option.
- **RESET-003** — Canceling, or dismissing the confirmation surface without
  choosing an option, shall leave the active slot's setup unchanged.
- **RESET-004** — The Reset entry point shall be shown only while the active
  slot has something a reset would clear — a non-default film, ND, base
  shutter, or Target Shutter, or a custom camera name. While the slot is
  already at defaults with no custom name, Reset shall not be shown.

### The two destructive choices

- **RESET-010** — The confirmation surface shall offer exactly two
  destructive choices, worded identically on both platforms: **"Reset
  settings"** and **"Reset settings and name"**.
- **RESET-011** — Choosing "Reset settings" shall clear the active slot's
  selected film and reciprocity profile, ND filter stack, base/adjusted
  shutter, exposure scale mode, and Target Shutter, restoring each to the
  shipping default. The slot's custom camera name, if any, shall be
  preserved.
- **RESET-012** — Choosing "Reset settings and name" shall perform the same
  clearing as RESET-011 and additionally clear the slot's custom camera
  name, restoring the slot's canonical default name.
- **RESET-013** — Both destructive choices shall be presented with a
  destructive (warning/error) visual treatment, consistent with other
  destructive confirmations in the app.

### Platform parity

- **RESET-020** — iOS and Android shall expose identical reset semantics: a
  settings-only path that preserves the camera name, and a settings-and-name
  path that clears it. Neither platform shall offer a reset capability the
  other does not.
- **RESET-021** — The two choice labels shall be identical text on both
  platforms.
- **RESET-022** — The Reset entry point's visibility rule (RESET-004) shall
  be identical on both platforms.

## Scope

- Reset acts on the active camera slot only; other slots are unchanged.
- Existing running, paused, completed, or canceled timers are unchanged by
  Reset.
- Reset does not delete custom reciprocity profiles or global preferences.

## Non-goals

- An undo-after-reset affordance. The confirmation step is the only
  mitigation for an accidental tap.
- Expanding what a reset clears beyond the fields in RESET-011/RESET-012.
- A shared cross-platform localization resource for the two choice labels
  (RESET-021 only requires the literal text to match; how it is delivered
  is an implementation concern).
