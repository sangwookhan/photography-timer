<!-- Copyright © 2026 Sangwook Han -->
<!-- SPDX-License-Identifier: Apache-2.0 -->

# Reciprocity Details and Secondary Guidance

| Prefix | Owns |
| --- | --- |
| DETAILS | The Reciprocity Details sheet |
| GUIDANCE | Secondary guidance (color/development/warning/note) formatting |

## Purpose

The main calculator stays concise; the Reciprocity Details sheet gives the
photographer enough source and model context to understand where a
corrected exposure came from, without cluttering the primary result.

## Requirements

### Reference data presentation

- **DETAILS-001** — A source-evidence row that carries both a stop
  correction (or multiplier) and an adjusted/corrected time shall surface
  both facts, combined into one compact cell when both exist (e.g. `+0.5
  stops · 15s`).
- **DETAILS-002** — A corrected-time value the catalog marks as
  approximate (a rounded display of a fractional-stop-derived conversion)
  shall be visually distinguished (e.g. a leading "≈"); a multiplier-derived
  corrected time is exact arithmetic and shall not be marked approximate.
- **DETAILS-003** — A source-evidence row marked evidence-only shall render
  with a footnote marker and shall be excluded from formula-fitting
  comparison markers.
- **DETAILS-004** — The reference panel shall not introduce new calculation
  policy; it presents data the calculation policy already consumes
  (threshold/limited-guidance boundaries) or intentionally ignores
  (source-evidence rows).

### Details sheet structure

- **DETAILS-010** — The sheet presents, in a fixed order that is the same
  shape for every profile type: header (model identity), current result
  card, a compact reciprocity-model summary (with a model selector shown
  only when the film has more than one selectable model), the reciprocity
  graph, source reference data (an app-derived comparison block appears
  only for explicitly app-derived models), and a Sources section
  (omitted for user-defined profiles, which carry their own dedicated
  custom-profile metadata card instead).
- **DETAILS-011** — The sheet shall open at a stable initial height
  regardless of profile shape.
- **DETAILS-012** — The reciprocity graph shall use a stable scale tier so
  it does not visibly rescale around the current metered input; only the
  current-result marker moves as the input changes.
- **DETAILS-013** — When a film exposes more than one selectable model, a
  compact model selector shows a short label per model — an explicit
  configured label when the profile provides one, otherwise a label derived
  from authority/calculation. A community/custom model should carry its own
  short label (e.g. a source name) rather than a generic fallback.

## Secondary guidance formatting

- **GUIDANCE-001** — Stored secondary guidance (color-correction notation,
  development-adjustment notes, warnings, free-text notes) is formatted for
  presentation only; it never changes calculation policy, the reciprocity
  domain data, or the confidence-presentation mapping.
- **GUIDANCE-002** — Stored notation is preserved exactly as published
  (e.g. `5M`, `7.5M`, `2.5G`, `CC10R`, `-10%`) — never rewritten, rounded,
  or re-derived into a different notation.
- **GUIDANCE-003** — Guidance classifies into exactly four, never-mixed
  categories: color correction, development adjustment, warning, and note.
- **GUIDANCE-004** — A stop-signal phrase (e.g. "not recommended") always
  classifies as a warning, never as a color-correction value.
- **GUIDANCE-005** — Ambiguous free-text guidance classifies as a note; it
  is never converted into a fabricated numeric or color-filter value.
- **GUIDANCE-006** — Missing or empty stored guidance produces no
  secondary-guidance row at all.
- **GUIDANCE-007** — Development-time hints and color-filter suggestions
  are presented as separate cells/notes, never folded into the
  corrected-exposure column; they are documentation, not calculation
  inputs.

## Non-goals

- A first-class color-correction or development-time policy beyond display
  formatting of the stored notation (GUIDANCE-001–007); the app does not
  interpret or canonicalize the notation numerically.
