# Task Spec: PTIMER-180 Create an Editable Custom Formula from a Saved Custom Table

> **Policy reset (supersedes the synthetic-model design in PR #14).**
> PTIMER-180 no longer makes the app-derived formula a runtime-selectable
> shooting model attached to a custom table. Instead, the table-derived
> fitted formula seeds a **new, independent, editable Custom Formula
> profile** that the photographer owns. See §3a for what PR #14 work is
> removed.

## Metadata

- Ticket: `PTIMER-180`
- Epic: `PTIMER-14` (Reciprocity Data Management) — verified Jira parent
- Plan story: `PTIMER-165` (slice 3 of 3; PTIMER-178 ✅ custom table
  profiles, PTIMER-179 ✅ inspection-only fitted-formula preview).
- Feature Branch: `feature/PTIMER-14-custom-table-model-selection`
  (Epic-ID prefix per the PTIMER-178/179 convention)
- Target Platform: `iPhone / SwiftUI / Xcode`
- Related Docs:
  - Jira: PTIMER-180, PTIMER-165, PTIMER-14
  - Specs: `docs/specs/DomainSchema.md` §13.4 / §15, `docs/specs/Calculator.md`
    §"User-defined table input" (the PR #14 wording claiming the
    table-derived formula is directly selectable as the active shooting
    calculation must be rewritten — §3a / §4).

---

## 1. Goal

A photographer can turn a saved Custom **Table** into a separate,
editable Custom **Formula**. The table-derived fitted formula
(PTIMER-179) is used only as the **initial seed**. After saving, the
Custom Formula is a normal, independent profile — editable and deletable
on its own — and the original Custom Table is unchanged.

A Custom Formula may **optionally link** to a reference Custom Table for
**comparison / error display / provenance only**. The link never feeds
calculation.

After the change:

- Custom Table and Custom Formula remain **independent, user-owned**
  profiles. A table calculates by table interpolation; a formula
  calculates only from its formula parameters.
- The app-generated formula is **never** auto-selected in shooting and is
  **not** a hidden runtime model attached to the table.
- From a saved Custom Table, `Create Formula` opens the existing Custom
  Formula editor seeded from the fitted formula, optionally pre-linked to
  that table as a reference.

---

## 2. Scope

- **Seed derivation.** From a saved Custom Table, derive initial formula
  parameters using the PTIMER-179 fit + guard
  (`ReciprocityFormulaFitter` / `CustomTableFittedFormulaPresenter`).
  Reuse, do not reimplement.
- **`Create Formula` entry point** on a saved Custom Table that opens the
  **existing** Custom Formula editor (`CustomFilmEditorView` /
  `CustomFilmEditorFormState`) seeded with those parameters.
- **Optional reference-table link** stored on the new Custom Formula
  (comparison/error/provenance only; never calculation). Set at creation
  time to the source table.
- **Reference points in the formula editor** (§6): when a linked table
  exists, merge the table's metered anchors into the existing preview
  list and show formula-vs-table error; otherwise behave exactly as the
  current Custom Formula editor.
- **Save / Cancel** semantics (§7): Save creates a separate editable
  Custom Formula profile; Cancel leaves the saved table untouched.
- **Independent lifecycle**: the saved Custom Formula and the Custom
  Table can be edited and deleted independently (§5).
- **Spec realignment** in `DomainSchema.md` / `Calculator.md` to the new
  policy (replacing the PR #14 "selectable shooting model" wording).
- **Remove / rework** the PR #14 runtime synthetic-model implementation
  (§3a).

---

## 3. Out of Scope

- Runtime "Table / App formula" shooting selection of any kind (removed —
  §3a).
- Auto-updating formula parameters when a linked table changes (errors
  recompute lazily; parameters never auto-change — §5).
- Full reference-table link **management** UI (relink / unlink / pick a
  different table after creation). Creation-time auto-link only;
  relink/unlink is **follow-up** unless trivial (Open decision §11).
- Stop-delta / multiplier row input; catalog / community / preset
  changes; sync / sharing; inventory management.
- Reworking the table editor (PTIMER-178) or the fitter (PTIMER-179)
  beyond reuse.

---

## 3a. PR #14 work to remove or rework

The current branch implements the now-rejected synthetic-model design.
Remove the runtime-selection mechanism entirely; keep only the
fit/guard/comparison building blocks (§"reusable" below).

Remove:

- `CustomFilmDerivedFormulaProfile` **as a runtime shooting profile
  producer** — it exists only for synthetic selection. (Its fit-extraction
  step may be lifted into a seed helper; the `ReciprocityProfile`-wrapping
  and `selectorLabel`/id machinery go.)
- The custom branches added to
  `ExposureCalculatorViewModel.filmDetailsModelSelection` and
  `selectProfileVariant(profileID:)`, and the `.userDefined → "Table"`
  case added to `modelSelectorLabel` — restore these to their pre-180
  (preset-only) behavior.
- The custom derived-profile resolution added to
  `CameraSlotSessionPersistenceController.runtimeSnapshot(from:)` — restore
  to pre-180.
- The synthetic-profile naming added to
  `FilmModeDetailsPresenter.subtitleModelLabel` — restore to pre-180.
- `CustomFilmModelSelectionTests` (runtime-selection tests) — delete or
  rewrite to the new flow.
- The `DomainSchema.md` / `Calculator.md` edits asserting the
  table-derived formula is directly selectable as the active shooting
  calculation from the table profile — rewrite per §4.

Net effect: no `<film> · App formula` runtime identity, no per-slot
`selectedProfileID` carrying a synthetic formula, no restore fallback for
a synthetic profile, no shooting selector for custom tables.

---

## 3b. Reusable from PR #14 / PTIMER-179

Keep / reuse only where it fits the new policy:

- `ReciprocityFormulaFitter` (PTimerCore) + `CustomFilmFormulaGuard` —
  seed derivation and validity.
- `CustomTableFittedFormulaPresenter.outcome(for:)` — fitted parameters,
  per-anchor comparison rows, and stop-error calculation (for both the
  seed and the editor's reference/error display).
- `CustomFilmEditorPreviewPresenter.defaultSampleSeconds`
  (`[1, 10, 60, 300, 1000]`) — the standard preview points to merge with
  linked-table anchors.
- The existing Custom Formula editor (`CustomFilmEditorView`,
  `CustomFilmEditorFormState`, preview/graph presenters).
- Producer-style tests that assert fitted parameters derived from a table
  — repurpose into the seed test.

---

## 4. Protected / Do-Not-Change Areas

- `ExposureCalculator.calculate`, `ReciprocityCalculationPolicyEvaluator`
  (order/semantics), `ReciprocityConfidencePresentation`, `TimerManager`.
- `ReciprocityFormulaFitter`, `CustomFilmFormulaGuard`,
  `CustomTableFittedFormulaPresenter` fit logic — reuse, not change.
- `AlternateReciprocityModels` and preset multi-model selection — restore
  to pre-180; do not extend for custom films.
- **Calculation never reads the reference-table link** (mirrors the
  source-evidence display-only contract, DomainSchema §3.1/§14.2): a
  Custom Formula computes from its formula parameters only.
- Existing Custom Table interpolation and Custom Formula calculation
  behavior — unchanged.

---

## 5. Data / Persistence Policy

- A saved Custom Formula is a normal `FilmIdentity(kind: .custom)` with a
  single `.formula` profile — exactly as PTIMER-178/84 custom formula
  films today. No new profile shape.
- **Reference-table link** is a new **optional** field carrying the
  source table's film id (recommend `UserEditableMetadata.referenceTableFilmID:
  String?`, additive `Codable`, decodes unchanged for existing snapshots;
  film-level vs profile-level placement is Open §11). It is:
  - written at creation time to the source table's id;
  - **never read by calculation** — display/comparison/provenance only.
- **Independent lifecycle:**
  - Editing the formula never changes the linked table; editing the
    linked table never changes the formula's parameters.
  - Errors are **recomputed lazily** from the linked table's *current*
    anchors the next time the editor/Details opens — never written back.
  - Deleting the linked table leaves the formula valid and editable; the
    reference/error UI is hidden or shows a short "reference table
    unavailable" note. Deleting the formula leaves the table untouched.
- No persistence-schema change beyond the additive optional link field.
  No `selectedProfileID` involvement (that path returns to pre-180).

---

## 6. Reference-Points / Error Behavior (formula editor)

- **No linked table** → the editor behaves exactly as today: standard
  preview rows (`[1, 10, 60, 300, 1000]` s) showing metered time +
  formula corrected time. **No reference column, no error column.**
- **Linked table present** → merge the table's metered anchors into the
  same reference list. For each row:
  - **Table-anchor row:** metered time · formula corrected time ·
    reference corrected time (from the table) · error in stops
    (`log2(formula / reference)`, reusing the PTIMER-179 stop-error math).
  - **Standard preview row without a table reference:** metered time ·
    formula corrected time · (no reference, no error).
  - **Overlap dedup:** if a standard preview point coincides with a table
    anchor metered time, render **one** row carrying the table-reference
    information (no duplicate).
- Parameter changes update, live: the graph, the formula preview values,
  and the table-anchor error values (reuse existing live-preview wiring).

---

## 7. Save / Cancel

- **Cancel** discards the formula creation/edit; the saved Custom Table is
  unchanged; no new profile is created.
- **Save** creates a **separate** editable Custom Formula profile (new
  `FilmIdentity`), carrying the optional reference-table link. The source
  Custom Table is unchanged.
- The saved Custom Formula is thereafter editable and deletable
  independently from the Custom Table (§5).

---

## 8. Constraints and Policy

- Smallest change that satisfies the policy; reuse the existing formula
  editor rather than building a new one. No business logic in SwiftUI
  views; presenters stay pure values.
- The seed must reuse the PTIMER-179 fit+guard so the seeded parameters
  equal the inspected preview; if the table cannot be fitted into a usable
  formula, `Create Formula` is unavailable (disabled/hidden) with the
  same not-usable rationale the preview already shows.
- Reference link is provenance/comparison only; never a calculation input
  and never a hidden runtime model.

---

## 9. Test Requirements (subject-owns-the-test placement)

- **Seed (PTimerKitTests):** initial formula parameters derived from a
  saved table equal `CustomTableFittedFormulaPresenter`'s available
  outcome; an un-fittable table yields no seed (Create Formula
  unavailable).
- **Save creates an independent profile:** saving produces a new custom
  formula `FilmIdentity` distinct from the table; the table is unchanged;
  Cancel creates nothing and leaves the table unchanged.
- **Independent lifecycle:** editing/deleting the formula does not change
  the table and vice-versa; deleting the linked table leaves the formula
  valid and clears the reference/error UI.
- **Reference points / error:** with a link, table anchors appear with
  reference corrected time + stop error; standard-only rows have no error;
  overlapping metered points dedup to one table-reference row; without a
  link, no error column.
- **Link persistence:** `referenceTableFilmID` round-trips; legacy
  snapshots without it decode unchanged; calculation ignores it.
- **Regression:** existing Custom Table interpolation, existing Custom
  Formula editor (no link), and preset multi-model selection all unchanged
  after the §3a removals.

### Suggested Commands

```bash
swift test --package-path ios/PTimerKit
swift test --package-path ios/PTimerKit --filter <ClassName>
```

App plan once if SwiftUI editor/entry-point surfaces change:

```bash
cd ios && xcodebuild -project PTimer.xcodeproj -scheme PTimer \
  -testPlan PTimer -destination 'platform=iOS Simulator,name=iPhone 17' test
```

---

## 10. Verification / Definition of Done

- §3a synthetic-model code and tests removed; the four touched files
  (`ExposureCalculatorViewModel`, `CameraSlotSessionPersistenceController`,
  `FilmModeDetailsPresenter`, plus the deleted producer/tests) are back to
  pre-180 behavior for shooting/selection/restore.
- `Create Formula` seeds the existing editor from the table-derived
  formula; Save yields an independent Custom Formula; Cancel leaves the
  table untouched.
- Reference/error display follows §6; calculation never reads the link.
- Specs realigned (no "selectable shooting model" wording).
- Package tests green; app plan green if SwiftUI surfaces changed.
- Final report: files changed, behavior summary, tests, risks, follow-up,
  user test steps.

### User test steps

1. Create and **save** a Custom Table (e.g. 1→2, 10→100, 100→600).
2. From the saved table, tap **Create Formula** → the Custom Formula
   editor opens, fields seeded from the table-derived fit, with the
   table's anchors shown as reference points and per-anchor stop error.
3. Adjust a parameter → graph, preview values, and anchor errors update
   live.
4. **Cancel** → no new profile; the table is unchanged.
5. Repeat 2–3 and **Save** → a new, independent Custom Formula appears in
   the library; it calculates from its formula (not the table).
6. Edit the table's anchors → the formula's parameters are unchanged; on
   reopening the formula editor, errors reflect the new anchors.
7. Delete the table → the formula still works/edits; reference/error UI is
   hidden or shows "reference table unavailable".
8. Confirm there is **no** Table/App-formula shooting selector on a custom
   table anywhere, and no `<film> · App formula` timer identity.

---

## 11. Resolved Decisions (approved 2026-06-15)

1. **`Create Formula` placement.** The table must be **saved first**;
   `Create Formula` is offered on the **saved-table surface / post-save
   table state** and opens the existing Custom Formula editor seeded from
   that saved table.
2. **Link field.** `UserEditableMetadata.referenceTableFilmID` at **film
   level** for this slice.
3. **Relink / unlink.** **Out of scope** — creation-time auto-link only.
   If the linked table is deleted, the formula stays editable and
   calculation continues; the reference/error UI is hidden or shows a
   short "reference table unavailable" note.
4. **Formula naming.** Auto-suggest **"<table name> Formula"**, editable by
   the user before Save.
5. **Dedup.** A standard preview point that overlaps a linked-table anchor
   renders **one** table-reference row (Reference Tc + Error); no duplicate
   rows.
