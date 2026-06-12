# PTIMER-122 — Add newly promoted reciprocity films to the shipped catalog

Parent epic: PTIMER-14 Reciprocity Data Management.
Branch: `feature/PTIMER-14-newly-promoted-reciprocity-films`.

## Background

The Confluence source-of-truth pages are synchronized for the Rollei
next-wave promotion set (`Next-wave Candidate Eligibility Review`,
`Rollei Reciprocity Data`, `Reciprocity Manufacturer Inventory and
Source Notes`, `Rollei Reciprocity Sources`). The promotion set is:

- Rollei RPX 25 — official manufacturer table profile
- Rollei ORTHO 25 plus — official manufacturer table profile
- Rollei RETRO 400S — unofficial practical profile (NOT official
  Rollei reciprocity guidance)

All table/formula values below were extracted from the official
Rollei EN data sheets (R210701) and the Lafitte source page and
verified on 2026-06-12.

## Objective

Add the promoted Rollei films to the shipped launch catalog while
preserving source authority, source shape, calculation model, and
presentation semantics. Small, reviewable, limited to PTIMER-122.
Execution is single-ticket, two steps: official films first, then
RETRO 400S behind a narrow validator extension.

## Scope — Step 1: official table films (pure data addition)

Add to `ios/PTimerKit/Sources/PTimerCore/Catalog/LaunchPresetFilmCatalog.json`
following the existing `rollei-rpx-100` table-profile pattern
(`tableLogLogInterpolation` + `manufacturerTable`, anchors +
sourceEvidence rows, no-correction guard, source-range guard).
Do not introduce new architecture for these two films.

### Rollei RPX 25

- film id: `rollei-rpx-25`, ISO 25, kind preset, production current
- authority official, source kind manufacturerPublished
- `noCorrectionThroughSeconds: 1.0`, `sourceRangeThroughSeconds: 50.0`

| Metered | Corrected |
| --- | --- |
| 1/1000 sec to 1 sec | no correction |
| 2 sec | 3 sec |
| 10 sec | 20 sec |
| 20 sec | 50 sec |
| 50 sec | 180 sec |

### Rollei ORTHO 25 plus

- film id: `rollei-ortho-25-plus`, ISO 25, kind preset, production current
- authority official, source kind manufacturerPublished
- `noCorrectionThroughSeconds: 1.0`, `sourceRangeThroughSeconds: 50.0`

| Metered | Corrected |
| --- | --- |
| 1/1000 sec to 1 sec | no correction |
| 5 sec | 7.5 sec |
| 10 sec | 20 sec |
| 20 sec | 50 sec |
| 30 sec | 75 sec |
| 40 sec | 100 sec |
| 50 sec | 150 sec |

## Scope — Step 2: RETRO 400S as unofficial practical primary

- film id: `rollei-retro-400s`, ISO 400, kind preset, production current
- authority unofficial; source kind third-party publication (or the
  closest existing practical source kind)
- publisher: Stéphane Lafitte; populate citation/title metadata where
  the schema supports it (unlike Portra 400, this source IS verified,
  so do not use the empty-publisher "source pending verification"
  pattern)
- formula: `Ta = Tm^1.62`, applies only when `Tm > 1 sec`
- `noCorrectionThroughSeconds: 1.0` (closed boundary; at exactly 1 sec
  the formula is identity anyway)
- source range: cover the published anchors (~15 sec) only if the
  current formula-rule schema supports a source-range field; if the
  schema has no such field for formula rules (as in the Portra
  precedent), record the anchors as source evidence/notes instead
- Lafitte published anchors (record as source evidence):
  5 sec → 13.5 sec, 10 sec → 41 sec, 15 sec → 80 sec
- context note: long exposure with a B+W 10-stop ND filter
- note: official Rollei page/PDF are product identity sources only;
  the official EN data sheet (re-verified 2026-06-12) contains no
  Schwarzschild/reciprocity table

### Narrow validator extension

`PresetFilmCatalog.swift` currently rejects non-official primary
launch profiles via `invalidPrimaryProfileSource`. Add the narrowest
possible validation path for explicitly promoted unofficial practical
primary profiles. The validator must still reject arbitrary
unofficial or malformed primary profiles.

Acceptable narrow conditions may include:

- authority `.unofficial` with third-party/practical source kind
- exactly the expected practical formula shape
- non-empty publisher/citation metadata
- explicit film-id/profile-id allowlist if that is the safest narrow path
- no limited-guidance rule mixed into the practical profile

Do not allow: arbitrary unofficial primaries, user-defined/unknown
sources in the launch catalog, official-looking metadata on
RETRO 400S, or an empty-publisher pattern for RETRO 400S.

Known-good presentation fact: `FilmSelectorSupportPresenter` already
maps `.unofficial` authority to `.unofficialPractical`, including for
`film.profiles.first` — no selector vocabulary change is expected.

### Stop condition

Stop and report before implementing RETRO 400S if the narrow
validator support requires broad changes to: DomainSchema /
source-authority contracts, selector support semantics,
protected-area confidence semantics, Details metadata vocabulary, or
unrelated launch catalog invariants. In that case complete
RPX 25 / ORTHO 25 plus only and recommend splitting RETRO 400S into a
follow-up ticket.

## Protected areas (do not modify)

- `ExposureCalculator.calculate`, snap-to-full-stop, `stabilityEpsilon`
- `ReciprocityCalculationPolicyEvaluator` evaluation order/semantics
- `ReciprocityConfidencePresentation` mapping
- Timer runtime semantics, persistence/restore contracts

## Tests

Existing templates: `TableProfileSourceDataContractTests`,
`UnofficialPracticalProfilesShapeTests`,
`OfficialTableMigrationInvariantTests` (update its invariant only if
it asserts catalog-wide official-only and Step 2 is implemented).

- Catalog decodes; RPX 25 / ORTHO 25 plus exist; RETRO 400S exists if
  implemented; no duplicate film/profile ids.
- RPX 25: official, manufacturerPublished, manufacturerTable +
  tableLogLogInterpolation, guards 1.0/50.0, anchors reproduce
  2→3, 10→20, 20→50, 50→180.
- ORTHO 25 plus: same shape, anchors reproduce 5→7.5, 10→20, 20→50,
  30→75, 40→100, 50→150.
- RETRO 400S (if implemented): accepted by loader; validator still
  rejects arbitrary unofficial primaries (negative test); authority
  unofficial; publisher identifies Lafitte; exponent 1.62;
  1 sec → no correction; 5 sec ≈ 13.5, 10 sec ≈ 41, 15 sec ≈ 80;
  selector support state is `.unofficialPractical`; Details/source
  metadata does not read as official manufacturer table.
- Exclusions not added: Rollei INFRARED, PAUL & REINHOLD, BLACKBIRD,
  CROSSBIRD, REDBIRD; Fomapan R100 / Cine 100 / Cine 400 / FOMA Cine
  Ortho 400; ADOX HR-50 / Scala 50; Kodak motion-picture family.

## Verification

```bash
swift test --package-path ios/PTimerKit
```

App-hosted tests are not expected to be affected (no OS-boundary
change); state explicitly in the report if they were not run.

## PR requirements

PR description must include user test steps:

1. Film selector shows RPX 25; Details shows official Rollei table;
   representative values 10 sec → 20 sec, 50 sec → 180 sec.
2. Film selector shows ORTHO 25 plus; Details shows official Rollei
   table; representative values 5 sec → 7.5 sec, 50 sec → 150 sec.
3. RETRO 400S (if implemented) appears as unofficial practical
   guidance, never as official Rollei guidance; representative values
   5 sec ≈ 13.5, 10 sec ≈ 41, 15 sec ≈ 80.
4. Deferred Rollei films (especially INFRARED) are not added.

## Jira close condition

Do not close PTIMER-122 until the implementation is actually complete,
tests are run (or unrun checks documented), the PR includes user test
steps, and a Jira comment records what changed / why / verification /
follow-up. No commit IDs in Jira comments unless requested.
