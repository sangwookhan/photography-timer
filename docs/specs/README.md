<!-- Copyright © 2026 Sangwook Han -->
<!-- SPDX-License-Identifier: Apache-2.0 -->

# Living Specifications

These files are the current product behavior contracts. They are the first
artifact changed when a new requirement is proposed — see
`docs/development/SpecificationWorkflow.md` for the process and
`docs/requirements/Requirements.md` for the layer above this one (the
user-scenario / persona-level product requirements that these files
refine, without duplicating their level of detail).

They are organized by product capability, not by ticket, delivery order, or
implementation layer. They are not work logs, prompts, implementation
reports, PR descriptions, or architecture inventories — those live in
`docs/architecture/` and `docs/development/`, or in the PR/ticket system
itself.

## Capability map

| New requirement concerns | Update |
|---|---|
| Base shutter, exposure math, duration formatting | `calculator/exposure.md` |
| ND values, the filter stack, notation | `calculator/nd-filters.md` |
| Target Shutter | `calculator/target-shutter.md` |
| Multiple cameras, slot switching, camera names | `shooting/camera-slots.md` |
| Reset behavior | `shooting/reset.md` |
| Reciprocity evaluation and result categories | `reciprocity/calculation.md` |
| Preset film dataset and catalog policy | `reciprocity/catalog.md` |
| User-authored reciprocity profiles | `reciprocity/custom-profiles.md` |
| Reciprocity Details, source/reference presentation | `reciprocity/details-and-guidance.md` |
| Timer states, pause/resume/cancel/repeat | `timers/lifecycle.md` |
| Compact dock, full-screen Timers workspace, and ordering | `timers/workspace.md` |
| Pre-alerts, completion alerts, lock-screen surface | `timers/alerts.md` |
| Schema evolution, decode isolation, quarantine | `cross-cutting/persistence.md` |
| Orientation, shooting-screen structure, density, accessibility, touch targets | `cross-cutting/presentation.md` |
| English/Korean product terminology | `cross-cutting/localization.md` |

A new independent capability (for example, a future physical-filter
inventory) gets a new file in the appropriate directory when it actually
ships — not before, and not as a speculative placeholder.

## What belongs elsewhere

- **`docs/requirements/Requirements.md`** — the layer above this one:
  user-scenario and persona-level product intent.
- **`docs/architecture/`** — module boundaries, dependency direction,
  state ownership, and other structural/implementation concerns. A
  capability file may describe a genuine cross-platform *behavior*
  difference; it never describes *how* either platform is internally
  structured to produce that behavior.
- **`docs/development/SpecificationWorkflow.md`** — the process by which
  these files are created, changed, and implemented (Spec PR / Code PR
  model, the truth hierarchy for reconciling historical material, ID
  conventions, and the spec-feedback protocol).

## Reading a capability file

Each file uses only the sections its capability actually needs, but
generally in this shape: Purpose, Current behavior, Requirements (grouped
under semantic, stable IDs), Invariants/Non-goals, and, where relevant,
Accessibility and Persistence. See
`docs/development/SpecificationWorkflow.md` §4 for the ID conventions and
§7 for what may appear in an optional Product research references section.
