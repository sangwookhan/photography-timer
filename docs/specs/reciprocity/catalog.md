<!-- Copyright © 2026 Sangwook Han -->
<!-- SPDX-License-Identifier: Apache-2.0 -->

# Reciprocity Preset Catalog

| Prefix | Owns |
| --- | --- |
| CATALOG | Film identity, source provenance, and the bundled dataset |
| CATALOG-SHAPE | The on-disk catalog encoding |
| CATALOG-VALID | Validation rules a catalog must pass to load |
| CATALOG-PICKER | The film picker sheet |

## Purpose

The preset catalog is the bundled, source-traceable film-reciprocity dataset
shared by iOS and Android. It is data, not hand-coded per-platform rules.

## Current behavior

One canonical shared catalog file backs both platforms. It currently ships
40 film identities, each with exactly one primary reciprocity profile.

## Requirements

### Film identity and provenance

- **CATALOG-001** — Each film identity shall carry: a stable, catalog-unique
  id (never shown to the user); a unique canonical stock name; a
  manufacturer; a positive ISO; a production status; and an array of one or
  more reciprocity profiles. The launch dataset ships exactly one **primary**
  profile per identity; zero or more alternate/derived profiles (CATALOG-012)
  may additionally exist for a given identity.
- **CATALOG-002** — Every reciprocity profile shall carry honest source
  provenance: a source type, an authority level, a confidence level, and
  (for official profiles) a publisher. Provenance shall be preserved
  verbatim; missing optional fields stay absent rather than being
  synthesized.
- **CATALOG-003** — A profile header shall separate **role** (`primary` /
  `alternate` / `derived`) from **authority** (`official` / `appDerived` /
  `community` / `unofficial` / `userDefined`). A film's official-authority
  default profile shall never itself be a community, app-derived, or
  user-defined profile — those are always `alternate` or `derived`,
  regardless of how closely they agree numerically with the official
  source.
- **CATALOG-004** — Official manufacturer data and third-party/community
  data shall never be merged into one provenance record.

### Allowed profile shapes

- **CATALOG-010** — A primary profile matches exactly one of three
  calculation shapes, independent of authority: (a) a quantified
  **formula** (owns its own no-correction and source-range guards); (b) a
  **table** log-log interpolation (owns its own no-correction band and
  source range, with published anchors reproduced exactly); or (c)
  **limited guidance** (a no-correction threshold plus qualitative
  guidance above it, no quantified continuation). A bare, un-anchored
  generic table-lookup model is not a supported shape and is rejected at
  load. A primary profile carries official authority by default;
  CATALOG-011 defines the sole exception.
- **CATALOG-011** — A film whose only usable quantified guidance is a
  verified third-party (non-manufacturer) publication may ship with an
  unofficial-authority primary profile, honestly labeled with that source's
  confidence level. This class exists in the bundled data but is not yet
  opened to the user-facing picker in the current release — the
  user-selectable set is filtered to films carrying an official source with
  a source-page reference. Rollei RETRO 400S is the current sole member of
  this class.
- **CATALOG-012** — Secondary (alternate/derived) models may be registered
  outside a film's primary profile. They follow the same shape rules, carry
  their own honest provenance, attach to an existing film identity rather
  than becoming a duplicate top-level entry, and never silently replace the
  primary profile. An app-derived or community model is never promoted to
  manufacturer authority.

### Per-film model-selection policy

- **CATALOG-020** — When a film's manufacturer source itself publishes
  discrete metered→corrected anchors, that film's default calculation shall
  be table/log-log interpolation directly over those anchors — not an
  app-derived formula fit through them.
- **CATALOG-021** — Currently, twelve launch profiles default to table/
  log-log interpolation under this policy: Kodak Tri-X 400, Kodak T-MAX 100,
  Kodak T-MAX 400, Fomapan 100 Classic, Fomapan 200 Creative, Fomapan 400
  Action, Rollei RPX 25, Rollei RPX 100, Rollei RPX 400, Rollei ORTHO 25
  plus, ADOX CHS 100 II, and BERGGER Pancro 400.
- **CATALOG-022** — An app-derived formula fit through an official table's
  anchors may ship only as a non-default, explicitly labeled alternate —
  never the default — and only when it passes the fit-quality gate
  (CATALOG-023). Currently Kodak Tri-X 400, Fomapan 100 Classic, Kodak
  T-MAX 100, and ADOX CHS 100 II ship such an alternate; other table-default
  films' fits did not pass the gate and are table-only.
- **CATALOG-023** — A generated app-derived formula alternate ships only
  when its worst absolute per-anchor stop error is at or below the shipping
  threshold; a fit whose worst error exceeds the threshold by a wide margin
  is rejected as unsafe and not shipped, and a borderline fit is documented
  but not shipped.
- **CATALOG-024** — A film whose manufacturer source itself publishes a
  formula (not a table) remains formula-default; the table-migration policy
  (CATALOG-020) does not apply to it.
- **CATALOG-025** — A film whose manufacturer source is limited/qualitative
  guidance only remains `limitedGuidance` and never presents a quantified
  prediction.
- **CATALOG-026** — A community-sourced alternate table or formula (for
  example, a community-derived comparison for a film that also has an
  official model) remains classified as `community` authority and is never
  merged with, or relabeled as, the official model.

## On-disk shape (informative)

The bundled catalog is one flat, `model`-discriminated JSON document
(`schema: "ptimer.catalog.v2"`). Its top level carries `schema`,
`schemaVersion`, `catalogVersion`, `license`, `copyright`, a deduplicated
`sources` registry keyed by a short stable id, and a `films` array.

Each profile's `model` field (`formula` | `table` | `limitedGuidance`) is
the sole calculation-shape discriminator; the nested `calculation` block
does not repeat a second discriminator. A profile references its source
provenance by `sourceId` into the `sources` registry rather than repeating
publisher/citation/authority inline. Table-profile calculation anchors are
authored as `{ meteredSeconds, correctedSeconds }` object rows and are the
single source of truth for that profile's calculation — non-numeric
evidence (development note, color-filter note, warning, free-text note,
approximate/evidence-only marker) lives in a separate array that references
its anchor by index rather than restating its numbers. Formula profiles may
similarly carry display-only reference points that are never consumed as
calculation anchors.

Both platforms load the same shared file and adapt it into the same
in-memory film-identity and reciprocity-profile shape described above. The
platform copies are expected to be byte-identical.

## Validation

- **CATALOG-VALID-001** — A bundled catalog is rejected at load (not
  soft-warned) if it fails structural validation: non-empty, catalog-unique
  film ids and canonical names; a positive ISO on every film; exactly one
  primary profile per film; a supported `model` value with no unrecognized
  calculation keys; and a primary profile matching one of the three allowed
  shapes (CATALOG-010).
- **CATALOG-VALID-002** — A promoted, non-official-authority primary
  profile (CATALOG-011) is accepted only when its cited source resolves,
  its confidence is not overstated, its calculation passes the same
  guarded-parameter contract as any formula/table profile, and it carries
  at least one reference point. There is no separate per-film allowlist
  mechanism for this acceptance.

## Film picker

- **CATALOG-PICKER-001** — Film selection opens a dedicated modal sheet,
  never an inline dropdown competing with the calculator for screen room.
  A row tap immediately applies the selection and dismisses the sheet; a
  separate Cancel action exits without changing the selection.
- **CATALOG-PICKER-002** — Preset films are grouped visually by
  manufacturer; within a group, films order alphabetically by canonical
  stock name.
- **CATALOG-PICKER-003** — Custom profiles (see `reciprocity/custom-
  profiles.md`) present in their own group, separate from manufacturer
  groups, each row carrying a visible "Custom" indicator so a user-defined
  entry can never visually pose as a manufacturer-published row.
- **CATALOG-PICKER-004** — Each row shows the film's canonical name and a
  compact ISO chip; an unofficial-authority profile's row carries an
  explicit qualifier on the name side (not the ISO side, since ISO is
  identical between an official row and its unofficial sibling for the
  same stock).
- **CATALOG-PICKER-005** — The collapsed film selection on the calculator
  screen carries an authority subtitle — "Official guidance" /
  "Unofficial practical" / "Custom" — present for every supported
  authority, so the active profile's authority is never left ambiguous by
  omission. Exception: an app-derived alternate model (CATALOG-022) shows
  its own name (e.g. "App-derived formula") instead of "Official
  guidance," so an app-fitted alternate can never be mistaken for the
  official primary it was fitted from.
- **CATALOG-PICKER-006** — Reopening the picker with a film already
  selected scrolls to the currently selected row on appear, distinguishing
  an official selection from its unofficial sibling row when both exist for
  the same film.

## Non-goals

- A generic, un-anchored table-lookup calculation model; only the anchored
  table/log-log shape is supported.
- Opening unofficial-primary films (CATALOG-011) to the user-facing picker;
  intentionally deferred, allowed by policy but unscheduled.
- Dedicated handling for films whose source shape doesn't fit the shapes
  above (range-valued guidance, a stand-alone stop-signal boundary, sparse
  anchors) beyond their current formula-era treatment.
- A catalog-authoring source format (e.g. YAML) and a generator that
  produces the runtime JSON from it; the runtime schema itself does not
  require or imply one.
- A second formula family beyond the current guarded power-law family.
