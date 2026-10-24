<!-- Copyright © 2026 Sangwook Han -->
<!-- SPDX-License-Identifier: Apache-2.0 -->

# Custom Reciprocity Profiles

| Prefix | Owns |
| --- | --- |
| CUSTOM | Identity, authority, and profile-type rules |
| CUSTOM-CLASS | Classification editing, defaults, and compatibility |
| CUSTOM-FORMULA | The formula editor |
| CUSTOM-TABLE | The table editor |
| CUSTOM-SEED | Deriving a formula from a saved table |

## Purpose

A photographer can author, save, reuse, edit, and delete personal
reciprocity profiles without modifying the bundled preset catalog.

## Current behavior

A custom profile is always presented as user-authored data, never as
manufacturer guidance. A photographer can author a custom profile as
either a **formula** (four editable terms plus range boundaries) or a
**table** (user-entered metered→corrected anchors, calculated through
log-log interpolation, the same basis a preset table profile uses). From a
saved custom table, the app can derive a fitted-formula preview and, from
that preview, seed the creation of a new, independent custom Formula
profile.

## Requirements

### Identity and authority

- **CUSTOM-001** — A custom film identity shall be created, edited, reused,
  and deleted from the film picker, and shall persist across an app
  restart.
- **CUSTOM-002** — A custom profile's authority shall always be
  user-defined; photographer-supplied source metadata (source kind,
  manufacturer/stock label, reference URL) is preserved verbatim but shall
  never be presented as manufacturer authority. Custom entries render in
  their own picker group with an explicit "Custom" badge, never blended
  into a manufacturer group.
- **CUSTOM-003** — A saved custom profile carries exactly one calculation
  rule — formula or table, never both — and its type does not convert in
  place after saving.
- **CUSTOM-004** — On Android, an in-progress (unsaved) custom profile
  editor draft survives a configuration/Activity recreation (not a full
  app restart), rather than being silently discarded.

### Film classification

The independent attributes and shared identity invariants are owned by
`reciprocity/catalog.md` CATALOG-CLASS-001–005.

- **CUSTOM-CLASS-001** — A newly created Custom Formula or Table shall
  start as **Negative + Black & White**. Both attributes remain independently
  editable before saving.
- **CUSTOM-CLASS-002** — The Custom create/edit identity area shall expose
  two separately labelled choices after ISO and before calculation inputs:
  **Polarity** (Negative / Positive) and **Color** (Black & White / Color).
  The current value and alternatives shall be directly understandable;
  labels and selection state shall be accessible without relying on color.
  Both Formula and Table flows shall offer the same choices, including
  Formula creation seeded from a saved Table.
- **CUSTOM-CLASS-003** — English and Korean shall convey equivalent
  choices: Polarity / 필름 유형, Negative / 네거티브, Positive / 포지티브,
  Color / 색상 for the attribute label, Black & White / 흑백 and
  Color / 컬러 for its values. The controls shall preserve the existing
  identity and calculation editing hierarchy.
- **CUSTOM-CLASS-004** — Saving a valid Custom film shall retain both
  selected attributes through reopening, subsequent edits, and app relaunch.
  Editing retains its film/profile identifiers and existing camera references.
  Cancel or dismissal preserves the saved film.
- **CUSTOM-CLASS-005** — Changing the unsaved Formula/Table input kind,
  correcting validation failures, or using formula-only Reset/Revert shall
  preserve both current classification choices. On Android both choices
  shall survive editor draft recreation under CUSTOM-004.
- **CUSTOM-CLASS-006** — Formula creation from a saved Table shall initially
  inherit both source classifications. The photographer may change either
  in the seeded editor. Saving and later editing/deleting either profile
  follow the independent-profile contract in CUSTOM-SEED-004–005.
- **CUSTOM-CLASS-007** — A valid legacy Custom Formula or Table with a
  missing polarity shall restore as Negative; a missing color classification
  shall restore as Black & White. Each fallback applies independently.
  Explicitly stored values take precedence, including a non-default value
  when the other field is missing, and survive subsequent saves.
- **CUSTOM-CLASS-008** — Missing classification shall preserve an otherwise
  valid legacy record and its identifiers, source metadata, formula
  parameters, table anchors, and reference-table link. Present unrecognized
  values remain governed by the strict decoding, record-isolation, and
  quarantine contract in `cross-cutting/persistence.md`. Compatibility
  defaults describe Custom restoration and initialization, not an inferred
  claim about a physical film stock.

### Formula profile

- **CUSTOM-FORMULA-001** — The formula editor exposes the shared guarded
  formula (`Tc = Tc₀ × (Tm / Tm₀)^p + b`) as four editable terms
  (corrected-exposure coefficient, reference metered time, exponent, fixed
  offset) plus two range/policy boundaries: **No correction** (the
  inclusive no-correction upper bound) and **Source data** (the source /
  confidence upper bound past which results present as beyond-source-range;
  calculation still continues past it).
- **CUSTOM-FORMULA-002** — A custom formula profile shall evaluate through
  the same shared guarded-formula path as a preset formula profile.
- **CUSTOM-FORMULA-003** — Invalid formula state (e.g. a non-positive
  anchor exposure, a missing exponent, boundaries in the wrong order) shall
  surface an inline explanation on the offending field and shall suppress
  any preview output that would suggest the invalid state produces a usable
  correction. Such a state shall never be persisted.
- **CUSTOM-FORMULA-004** — The editor offers **Reset** (neutral starter
  values, available when creating or editing) and, only when editing an
  existing profile, **Revert** (restores the values the editor was opened
  with).

### Table profile

- **CUSTOM-TABLE-001** — A custom table profile's calculation anchors are
  direct metered→corrected duration rows: at least two rows, each with
  finite positive values, corrected time never shorter than metered time,
  and metered times strictly ascending across rows.
- **CUSTOM-TABLE-002** — The no-correction boundary is user-editable,
  suggested by default from the first anchor, and validated as finite,
  strictly positive, and strictly below the first anchor's metered time.
- **CUSTOM-TABLE-003** — The source-range boundary is not directly
  user-editable; it is derived from the last anchor's metered time and
  shown read-only.
- **CUSTOM-TABLE-004** — A custom table profile's calculation anchors and
  any displayed evidence copy of those same rows never drift from each
  other.
- **CUSTOM-TABLE-005** — A custom table profile shall evaluate through the
  same log-log table interpolation path as a preset table profile.
- **CUSTOM-TABLE-006** — An invalid or corrupt custom table entry is
  dropped at restore, on the same terms as a malformed custom formula
  entry.

### Deriving a formula from a table

- **CUSTOM-SEED-001** — From a saved custom table, the system shall derive
  an app-derived fitted formula (inspection preview only): fitted
  parameters, a per-anchor comparison of source vs. fitted corrected time
  (percent and stop error), the worst error, and a fit-quality marker. This
  fit is computed deterministically from the table's current anchors and
  is never itself persisted or selectable as the active calculation.
- **CUSTOM-SEED-002** — A fit that would shorten exposure anywhere in
  range is presented as unusable, with no adoption path; a merely poor fit
  warns but does not block inspection.
- **CUSTOM-SEED-003** — A **Create Formula** action, offered only on a
  saved (not in-progress) table, opens the formula editor pre-populated
  with the fitted parameters and an auto-suggested name of the form
  "`<table name> Formula`" (user-editable before save).
- **CUSTOM-SEED-004** — Saving from the seeded editor creates a new,
  independent custom Formula profile, distinct from the source table;
  Cancel creates nothing. There is no runtime selector for choosing
  between a table and a table-derived formula as the active shooting model
  for the same profile — table and formula are always two separate
  profiles.
- **CUSTOM-SEED-005** — The created formula may carry an optional
  reference link back to its seed table, used only for comparison/error
  display and provenance — calculation never reads this link. Editing or
  deleting either side never mutates the other.
- **CUSTOM-SEED-006** — When a formula has a linked reference table, its
  editor merges the table's metered anchors into its standard preview
  list, with each table-anchor row showing the reference corrected time
  and stop error alongside the formula's own preview.

## Timer and details identity

- **CUSTOM-010** — A timer started from a custom profile preserves enough
  identity in its metadata to remain recognizable as custom-sourced even
  after the originating profile is later edited or deleted.

## Non-goals

- Relink/unlink management of an existing formula↔table reference link
  once created; only creation-time auto-linking (CUSTOM-SEED-005) is
  supported.
- User-facing export/import of custom profiles, or any cross-device sync.
