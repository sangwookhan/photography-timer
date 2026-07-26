<!-- Copyright © 2026 Sangwook Han -->
<!-- SPDX-License-Identifier: Apache-2.0 -->

# App Shell Presentation

| Prefix | Owns |
| --- | --- |
| SHELL | Orientation, screen structure, density tiers, accessibility, and touch targets |

## Purpose

A few presentation rules apply to the whole app rather than to any single
capability — orientation, how the shooting screen shares room between the
calculator and a compact timer presence, how that screen adapts to
available height and system font scale, and baseline accessibility/
interaction guarantees. This file exists so those rules have a clear owner
instead of being attached to whichever capability happened to be
documented last.

## Current behavior

The app runs in portrait only. The shooting screen is the app's primary
screen: it hosts the calculator plus a compact timer presence (see
`timers/workspace.md`) without a screen transition. Full timer management
is a separate full-screen destination, reached deliberately from that
compact presence, not folded into the shooting screen itself.

## Requirements

### Orientation and screen structure

- **SHELL-001** — The app shall run in portrait orientation only, enforced
  at the app entry point; no screen shall opt out of this constraint.
- **SHELL-002** — The shooting screen hosts both exposure calculation and a
  compact timer presence as one primary surface: the user adjusts exposure
  and starts, glances at, or manages the compact set of running timers
  without a screen transition. Full timer management (the full-screen
  Timers workspace, `timers/workspace.md`) is a separate navigational
  destination, deliberately reached from the compact presence rather than
  folded into the shooting screen.

### Layout density

- **SHELL-010** — The primary screen shall adapt to available vertical
  room without changing its structure — the same sections are present at
  every density tier, only spacing and sizing change.
- **SHELL-011** — Three density tiers are supported: Regular (standard
  spacing), Compact (reduced spacing on shorter viewports), and Dense
  (minimum padding so the layout remains stable on the smallest supported
  viewport). Tier selection is a function of available height only.

### Large text and constrained height

- **SHELL-020** — Required shooting-flow controls and corrected-exposure
  content remain reachable and readable when the system font scale is set
  large and the available height is constrained, rather than becoming
  unreachable or clipped. A platform may cap how far specific, non-primary
  chrome (e.g. a compact toggle's label) scales, but that cap shall not
  apply to primary readable content or to required controls.
- **SHELL-021** — On Android, a shooting-screen sheet or dialog that was
  open before a configuration/Activity recreation (not a full app restart)
  reopens automatically afterward, rather than silently closing.

### Touch targets

- **SHELL-030** — Primary shooting/timer action controls and ND notation
  controls provide a comfortably tappable interactive area, independent of
  their drawn visual size — a visually compact icon or label is not
  permitted to also have a cramped hit area. On Android this is enforced
  as a minimum 48dp interactive target. Visual size may stay smaller than
  the interactive area; this requirement concerns usable interactive area,
  not identical visual size across platforms.

### Accessibility semantics

- **SHELL-040** — Core shooting/timer controls remain operable and
  understandable through the platform's screen reader (VoiceOver on iOS,
  TalkBack on Android) without relying on color alone to convey state.

## Non-goals

- Landscape support of any kind.
