# Task Spec: PTIMER-178 Create and Use Custom Reciprocity Table Profiles

## Metadata

- Ticket: `PTIMER-178`
- Epic: `PTIMER-14` (Reciprocity Data Management) — verified Jira parent
- Plan story: `PTIMER-165` (this is slice 1 of 3; PTIMER-179 fitted
  formula generation and PTIMER-180 model selection follow)
- Feature Branch: `feature/PTIMER-14-custom-table-profiles`
  (Epic-ID prefix per Jira ticket instruction — not a typo)
- Target Platform: `iPhone / SwiftUI / Xcode`
- Related Docs:
  - Jira: PTIMER-178, PTIMER-165, PTIMER-14
  - Specs: `docs/specs/DomainSchema.md` §13.4 / §14 (must be updated
    by this ticket), `docs/specs/UI.md` §4.1.1 / §4.2 (reference)

---

## 1. Goal

A photographer can author a custom reciprocity profile from Tm/Tc
table anchors, save it locally, select it in shooting mode, get
corrected exposure through the existing table log-log interpolation
path, and start a timer whose identity shows it came from a custom
table profile. No fitted-formula generation yet.

After the change:

- The custom film editor offers a creation-time choice: Formula
  profile or Table profile. Saved profiles never convert between the
  two types.
- A custom table profile holds exactly one
  `.tableInterpolation(TableInterpolationReciprocityRule)` rule
  (formula XOR tableInterpolation per profile).
- Custom table profiles survive relaunch; invalid/corrupt entries are
  dropped at restore exactly like malformed formula entries today.
- Existing custom formula profiles keep working unchanged.

---

## 2. Scope

Ordered implementation steps (each with its verification checkpoint):

1. **Spec alignment** — update `docs/specs/DomainSchema.md`:
   - §13.4: custom profiles may now carry either the shared guarded
     formula model **or** a single table-interpolation rule authored
     in the editor; describe the boundary-derivation policy (§5
     below).
   - §14 "User-defined table input" future-scope bullet: narrow it to
     what remains future scope (point fitting, stop-delta/multiplier
     input, model selection — PTIMER-179/180).
   - Touch only those paragraphs; no broader document rework.
   - Verify: cross-references still point at English paths; no other
     spec sections contradict the new wording.
2. **Library acceptance** — extend the `CustomFilmLibrary` sanitizer
   (`isWellFormedCustomFilm`) to accept a 1-rule profile that is
   either the existing formula shape (unchanged guards) or a table
   shape validated by
   `TableInterpolationReciprocityRule.hasValidParameters` **plus**
   the stricter custom-profile rule `noCorrectionThroughSeconds > 0`
   (see §5.2). Malformed table profiles are dropped at restore.
   - Verify: sanitizer unit tests — valid table accepted, each
     invalid-anchor case rejected, formula regression suite green.
3. **Form state** — add a calculation input kind (`formula` /
   `table`) to `CustomFilmEditorFormState`; keep all existing formula
   fields untouched; model table rows as a separate value type
   (Tm text / Tc text per row); `validate()` / `buildFilmIdentity`
   produce the `.tableInterpolation` rule for table mode.
   - Verify: form-state validation tests covering the §5.2 matrix.
4. **Editor UI** — creation flow offers Formula/Table; edit flow
   fixes the saved profile's type; table mode renders row add/delete,
   Tm/Tc duration inputs, the editable no-correction field, and the
   read-only derived source range ("Source data through: last
   anchor"). Preview/graph must not break; no polish.
   - Verify: state-oriented view-model tests; manual editor pass.
5. **Selection + calculation** — confirm custom table profiles appear
   in the film picker with the existing "Custom" treatment and that
   shooting-mode corrected exposure flows through the existing
   `ReciprocityCalculationPolicyEvaluator` table path unchanged.
   - Verify: view-model tests for select → calculate covering exact
     anchors, interpolated input, beyond-source input.
6. **Details + timer identity** — Details shows `Custom table`
   (profile/source subtitle) and reuses existing `Table-derived` /
   `Beyond source range` vocabulary; timer
   `customProfileSummary` gains a table variant (e.g.
   `Custom table · 3 anchors`) while film label / ISO / source-type
   fields are preserved as today.
   - Verify: presenter tests for both wordings; timer-identity test
     for the table summary string.
7. **Tests** — see §7.

---

## 3. Out of Scope

- Fitted formula generation (PTIMER-179).
- Table vs fitted-formula model selection or its persistence
  (PTIMER-180).
- Stop-delta or multiplier anchor input — direct Tm/Tc seconds only.
- Converting a saved profile between formula and table types.
- Custom table graph/source presentation polish beyond existing or
  default rendering.
- Community catalog presets; shipped manufacturer catalog changes.
- Remote sync or sharing.
- No changes to `docs/specs/UI.md` (any editor-surface spec drift is
  reported as a follow-up candidate, not fixed here).

---

## 4. Protected / Do-Not-Change Areas

- `ExposureCalculator.calculate`, snap-to-full-stop,
  `stabilityEpsilon`.
- `ReciprocityCalculationPolicyEvaluator` — evaluation order and
  result semantics. Custom table profiles must ride the **existing**
  `.tableInterpolation` path; do not modify the evaluator.
- `TableInterpolationReciprocityRule` evaluator and
  `hasValidParameters` domain contract (the stricter `> 0`
  no-correction rule lives in editor validation and the custom-film
  sanitizer, **not** in the domain type — shipped catalog profiles
  must be unaffected).
- `ReciprocityConfidencePresentation` mapping.
- Timer runtime semantics (`TimerManager`, pause/resume/complete).
- Persistence and restore contracts: `PersistentCustomFilmLibrary`
  stays at `schemaVersion = 1` (the snapshot already encodes
  `.tableInterpolation` rules via the existing Codable enum — no
  schema change, no migration).

---

## 5. Constraints and Policy (decided — do not re-open)

### 5.1 sourceRangeThroughSeconds

- Not user-editable in this slice. Derive it as the last anchor's
  metered time (`max(anchor.meteredSeconds)`).
- Show it read-only in the editor ("Source data through: last
  anchor" style); advanced editing is deferred to PTIMER-180+.

### 5.2 noCorrectionThroughSeconds

- User-editable. Default suggestion: `firstAnchorMetered / 10`
  (first anchor 1 s → default 0.1 s; 10 s → 1 s). Re-derive the
  suggestion when the first anchor changes, but never overwrite a
  value the user already edited.
- Editor + sanitizer validation (stricter than the domain's `>= 0`):
  finite, **strictly positive**, and strictly below the first
  anchor's metered time. Rationale: the table evaluator feeds the
  no-correction knee into log-log interpolation; a `0` knee makes
  `log10(0)` poison the first segment (NaN → `.invalidRule`), so a
  custom editor must never save 0.
- Full anchor validation per the ticket: at least two rows; positive
  finite values; strictly ascending metered times; corrected ≥
  metered per row; boundary rules above.

### 5.3 Editor structure

- One custom profile carries exactly one calculation rule:
  formula XOR tableInterpolation.
- Creation offers Formula / Table; editing keeps the saved type.
  Formula↔Table conversion is out of scope (table→formula is
  PTIMER-179's fitting scope).

### 5.4 Anchor rows

- Direct Tm/Tc duration inputs only. Minimum two rows; Add row /
  Delete row affordances.
- No hard product limit on row count. A soft UI cap (~20 rows) is
  permitted as an editor affordance if needed — it is not a
  validation rule and not a product feature.

### 5.5 Anchors vs source evidence

- Calculation anchors live **only** in
  `TableInterpolationReciprocityRule.anchors`. The policy/evaluator
  never reads `sourceEvidence` (display-only contract,
  DomainSchema §3.1).
- **Do** populate `sourceEvidence` with display-only copies of the
  anchors — one row per anchor in the shipped table-profile shape
  (`meteredExposure: .exactSeconds(Tm)`, one
  `.exposure(.correctedTime(...))` adjustment carrying Tc) — so the
  existing Sources presentation and graph anchor markers render for
  custom table profiles without new presentation code. Keep the two
  representations derived from the same editor rows at build time so
  they cannot drift.

### 5.6 Labels

- Details: profile/source subtitle `Custom table`; calculation basis
  reuses existing `Table-derived`; out-of-range reuses existing
  `Beyond source range`. No new vocabulary beyond `Custom table`.
- Timer identity: table variant of `customProfileSummary`, e.g.
  `Custom table · 3 anchors`; keep film label / ISO / source-type
  composition consistent with the formula variant.

### 5.7 General

- Smallest change that satisfies the ticket; match surrounding style;
  no business logic in SwiftUI views; presenters stay pure values.
- Every changed line traces to this scope. Opportunistic cleanup is
  reported, not performed.

---

## 6. Expected Approach

Follow the §2 step order (spec → sanitizer → form state → editor UI →
selection/calculation → details/identity → tests). Domain and policy
layers need no new calculation code — PTIMER-159's
`TableInterpolationReciprocityRule` + evaluator and the policy's
existing table branch are reused as-is. The work concentrates in
`PTimerKit`: `CustomFilm/` (form state, library sanitizer, editor
support), film-picker/Details presenters, and the timer identity
summary. The persistence layer is untouched except that restored
snapshots may now legitimately contain table rules.

---

## 7. Test Requirements

### Required (all in the SwiftPM package; no simulator needed)

- Sanitizer: valid table profile accepted; each invalid case (one
  anchor, non-finite, non-ascending, shortening Tc, zero/oversized
  no-correction, boundary violations) rejected; existing custom
  formula acceptance unchanged.
- Persistence: custom table profile snapshot round-trip restores
  byte-equal anchors and boundaries.
- Calculation (view-model level): exact anchor inputs reproduce
  entered Tc; between-anchor input interpolates; beyond-source input
  is marked and still usable for timer start.
- Editor form state: validation matrix per §5.2; mode fixing on edit;
  derived source range and default no-correction behavior; built
  `FilmIdentity` carries rule anchors + matching sourceEvidence copies.
- Presenters: `Custom table` subtitle, `Table-derived`,
  `Beyond source range` states; timer summary table variant.
- Full existing suite stays green (custom formula regression is an
  explicit acceptance criterion).

### Suggested Commands

```bash
swift test --package-path ios/PTimerKit
# focused runs while iterating:
swift test --package-path ios/PTimerKit --filter <ClassName>
```

App-hosted `PTimerTests` impact is expected to be small. If SwiftUI
editor files are changed, run the app test plan once before final
report:

```bash
cd ios && xcodebuild -project PTimer.xcodeproj -scheme PTimer \
  -testPlan PTimer \
  -destination 'platform=iOS Simulator,name=iPhone 17' test
```

### Manual Checks

- Create a table profile (e.g. Fomapan-like 1→2, 10→80, 100→1600),
  relaunch, confirm it restores and calculates.
- Select it in shooting mode; verify corrected exposure, Details
  states (within range / beyond source range), timer start, and the
  timer card summary.
- Edit and delete the profile; confirm picker/selection fallback
  behaves like custom formula profiles today.

---

## 8. Definition of Done

- All ticket acceptance criteria met (create / validate / persist /
  select / calculate / beyond-source marking / timer start / timer
  identity / formula regression).
- `DomainSchema.md` §13.4 and §14 updated; no other docs touched.
- Protected areas untouched; persistence schema version unchanged.
- Package tests green; app-hosted plan run once and green.
- Final report lists files changed, behavior summary, tests run,
  remaining risks, and follow-up candidates.

---

## 9. Review Checkpoints

1. Evaluator and domain `hasValidParameters` diff-free?
2. Sanitizer change purely additive for the formula path?
3. Exactly one rule per custom profile; no conversion path leaked in?
4. Anchors in the rule; sourceEvidence copies display-only and
   derived from the same editor rows?
5. Stricter `> 0` no-correction rule enforced in editor + sanitizer
   only (domain contract unchanged)?
6. Vocabulary reused rather than duplicated?
7. Spec wording matches what shipped?

---

## 10. Delivery Notes

Report must include user test steps (create table → select → calculate
→ start timer) per the PTIMER-165 delivery convention. Name any
`docs/specs/UI.md` §4.2 drift observed as a follow-up candidate.

---

## 11. Open Questions

None. The three UX decisions (source-range derivation, no-correction
default/validation, creation-mode structure) and the sourceEvidence
display-copy policy were decided by ChatGPT review on 2026-06-12 and
are recorded in §5.
