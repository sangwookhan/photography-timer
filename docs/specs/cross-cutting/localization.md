<!-- Copyright © 2026 Sangwook Han -->
<!-- SPDX-License-Identifier: Apache-2.0 -->

# Localization

| Prefix | Owns |
| --- | --- |
| L10N | Copy source of truth, scope, and parity |

## Purpose

The app ships in English and Korean. Localization must not change what any
feature actually does — only how its text reads.

## Current behavior

The app supports English and Korean. The same user-facing concept reads
with equivalent wording on both platforms unless it is intentionally
platform-specific.

## Requirements

### Parity

- **L10N-001** — When the same concept appears on both platforms, English
  and Korean wording shall be identical on both, unless the concept is
  explicitly designated platform-specific. This applies to less-common
  paths (e.g. an unsupported-by-policy explanation) exactly as it does to
  primary flows — parity is not relaxed for rarely-seen text.

### Scope boundary

- **L10N-010** — Visible app text and accessibility descriptions (screen
  reader labels; see `cross-cutting/presentation.md`, SHELL-040) across the
  shooting/timer flow, the timer workspace, the exposure calculator,
  reciprocity/film details, custom film authoring, About/legal/version, and
  notification text are translated.
- **L10N-011** — The following remain English/symbolic in every locale and
  are never translated: product names, technical notation (ND, OD, ISO,
  and the shared formula's symbolic terms), formula expressions, numeric
  source values, source URLs, film/manufacturer names (catalog data), and
  graph/table technical column and axis labels.
- **L10N-012** — Localizing reciprocity confidence-presentation text is
  presentation-only: it shall never change the confidence mapping,
  evaluation order, or result semantics described in
  `reciprocity/calculation.md`.

### Locale-sensitive formatting

- **L10N-013** — Android's timer end-of-exposure display and iOS's
  pre-alert notification body text (the "ends at ..." text shown ahead of
  completion) both format using the active system locale rather than a
  fixed pattern or a hardcoded locale. iOS's completion notification
  itself carries no end-time text to localize. This is a known
  cross-platform gap, not a design choice: iOS's in-app running-timer
  panel and Timers workspace still format their end-of-exposure text with
  a hardcoded locale and fixed pattern, unlike the Android surface it
  mirrors.

## Non-goals

- Languages beyond English and Korean.
- Translating any of the excluded categories in L10N-011.
- `docs/translations/ko/` (a human-reference Korean translation of the
  spec documents themselves) is a distinct artifact from the in-app copy
  source above; the two are not synchronized by any mechanism, and neither
  substitutes for the other.
