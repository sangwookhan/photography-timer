# PTIMER-186 — Catalog structure analysis

Analysis-only review of the PTimer film catalog and custom-film data
formats, evaluating evidence-based directions for long-term,
human-editable profile management. No source files were modified; no
builds or tests were run beyond read-only inspection commands.

## What is verified

**Source files inspected:**

- `ios/PTimerKit/Sources/PTimerCore/Catalog/LaunchPresetFilmCatalog.json` (3818 lines)
- `android/core/src/main/resources/LaunchPresetFilmCatalog.json` (3818 lines)
- `ios/PTimerKit/Sources/PTimerCore/Catalog/PresetFilmCatalog.swift` (loader + validator)
- `android/core/src/main/kotlin/com/sangwook/ptimer/core/catalog/LaunchPresetFilmCatalog.kt` (loader + validator)
- `ios/PTimerKit/Sources/PTimerKit/Persistence/PersistentCustomFilmLibrary.swift`
- `ios/PTimer/ExposureCalculator/FilmContext/UserDefaultsCustomFilmLibraryStore.swift`
- `android/core/src/main/kotlin/com/sangwook/ptimer/core/persistence/CustomFilmLibraryPersistence.kt`
- `ios/PTimerKit/Sources/PTimerCore/Reciprocity/AlternateReciprocityModels.swift` (500 lines)
- `android/core/src/main/kotlin/com/sangwook/ptimer/core/reciprocity/AlternateReciprocityModels.kt` (443 lines)
- `ios/PTimerKit/Sources/PTimerCore/Reciprocity/ReciprocityDomain.swift` (domain shape, `UserEditableMetadata`)
- `shared/test-fixtures/catalog-validation-cases.json`, `shared/test-fixtures/exposure-golden.json`
- `docs/specs/DomainSchema.md` (sections 3, 11, 12, 13)
- `AGENTS.md`, `CLAUDE.md`, `README.md`, `CONTRIBUTING.md` (preflight)

**Commands run** (read-only; no build/test executed):

- `diff -q` / `diff` / `md5` on the two catalogs
- `wc -l`, `grep -rln`, `sed -n`, `head`
- Several `python3` JSON-parse passes (counts, key maps, anchor-vs-evidence
  overlap, publisher repetition, fixture-vs-catalog id coverage)

**Catalog facts (verified):**

- Top level: `{ "_meta": { copyright, license }, "films": [ ... ] }`. No
  version field on the document.
- 37 films, 37 profiles — exactly one profile per film (loader hard-requires
  `profiles.count == 1`).
- All films `kind = "preset"`, `productionStatus = "current"`.
- Rule-kind distribution across profiles: formula 20, tableInterpolation 11,
  threshold 6, limitedGuidance 6 (43 rule objects; the 6 guidance films carry
  a threshold + limitedGuidance pair).
- All formula rules use `formulaFamily = "modifiedSchwarzschild"`.
- `source.kind`: 36 `manufacturerPublished` + 1 `thirdPartyPublication`.
  `authority`: 36 `official` + 1 `unofficial`. `confidence`: 36 `high` +
  1 `medium` (the single promoted Rollei Retro 400S practical profile).
- Profile keys present: `id`/`name`/`notes`/`rules`/`source` on all 37;
  `modelBasis` on 26; `sourceEvidence` on 19; `selectorLabel` on 1.
- iOS and Android launch catalogs are semantically identical (sorted-key JSON
  dumps match exactly). The only byte difference is the closing of the
  document (lines 3817–3819): iOS ends `]`, blank, `}` with no trailing
  newline; Android ends `  ]`, `}`. All 3816 content lines are byte-identical.
  They are two physical copies kept in sync by copy, and already show trivial
  tail-formatting drift.

**Custom-film facts (verified):**

- iOS `PersistentCustomFilmLibrarySnapshot` = `{ schemaVersion: Int = 1,
  films: [FilmIdentity] }`, stored in UserDefaults key
  `ptimer.exposure-calculator.custom-films.snapshot`. `loadSnapshot()` uses
  `try?` and does not inspect `schemaVersion`.
- Android `PersistentCustomFilmLibrarySnapshot` = `{ films, schemaVersion = 1 }`,
  stored via DataStore. `CustomFilmLibraryCodec.decode` returns `null` when
  `schemaVersion != CURRENT_SCHEMA_VERSION` (strict version gate).
- Both wrap the same `FilmIdentity` domain type used by presets, so a custom
  entry is structurally a preset entry with a `.userDefined` profile.
- `referenceTableFilmID` lives under `userMetadata` (`UserEditableMetadata`,
  PTIMER-180) — a cross-film link from a custom fitted-formula film to its
  source table film.
- No export / import / share / file feature exists for custom films on either
  platform (grep for `fileExporter`, `ShareLink`, `ACTION_SEND`,
  "export"/"import" found only unrelated SwiftUI layout comments). The
  custom-film JSON is internal persistence only.

**Fixture facts (verified):**

- `exposure-golden.json`: keys `fullStopShutterSpeeds`, `cases`,
  `timeDisplayCases`, `shutterFormatCases`, `errorCases`. Read by iOS
  `SharedFixtureGoldenTests` and Android `ExposureGoldenTest` — live.
- `catalog-validation-cases.json`: keys `catalogExpectations`,
  `launchCatalogValidationRules`, `perFilmExpectations`, `rejectionCases`.
  The file is read by iOS `SharedFixtureGoldenTests` and Android
  `LaunchPresetFilmCatalogTest`, but only the `catalogExpectations` block
  (`expectedFilmCount`, `expectedFilmOrder`, `expectedFilmIds`) is asserted.
  Correction to an earlier draft of this report: `perFilmExpectations`,
  `rejectionCases`, and `launchCatalogValidationRules` have zero consumers on
  either platform (verified by grep) — the bulk of the 1175-line fixture is
  dead content that no test reads.
- It restates catalog facts: `expectedFilmCount = 37`, full `expectedFilmOrder`
  (37 names), and `perFilmExpectations` that re-list filmId,
  canonicalStockName, manufacturer, brandLabel, aliases, iso, kind,
  productionStatus, profileId, source kind/authority/confidence/publisher,
  ruleKinds, formulaFamily.
- Coverage gap: `perFilmExpectations` pins only 34 of 37 films. The three
  unpinned are `rollei-rpx-25`, `rollei-ortho-25-plus`, `rollei-retro-400s`.
  `DomainSchema.md` section 13.4 still describes a "34-film launch-ready scope"
  while the catalog and `expectedFilmCount` ship 37 — a spec/text drift.

## Current format summary

- **Launch catalog:** A single JSON document per platform (two physical
  copies), acting as both runtime payload and authoring format. Deeply nested
  tagged-union encoding: a rule is `{ "kind": "formula", "formula": { ...
  "formula": { formulaFamily, exponent, ... } } }` (the word "formula" nests
  three deep); source-evidence rows are `{ meteredExposure: {kind,
  exactSeconds}, adjustments: [ { kind:"exposure", exposure: {
  kind:"correctedTime", correctedTime: { meteredSeconds, correctedSeconds } }
  } ] }`. The `kind` discriminator always duplicates the name of its sibling
  payload key.
- **iOS custom film:** `{ schemaVersion, films:[FilmIdentity] }` in
  UserDefaults; version ignored on load.
- **Android custom film:** `{ films, schemaVersion }` in DataStore; unknown
  version rejected to empty.
- **Alternate profiles:** Community, app-derived, and alternate-official
  profiles are code-defined, not in the catalog JSON — `AlternateReciprocityModels`
  in Swift (500 lines) and Kotlin (443 lines), hand-duplicated. Verified
  entries: `foma-fomapan-100-ohzart-community-table` (community),
  `foma-fomapan-100-app-formula`, `kodak-tri-x-official-table`,
  `kodak-tri-x-app-formula`, `kodak-tmax-100-app-formula`,
  `adox-chs-100-ii-app-formula`. Their anchor evidence is hardcoded the same
  way as in the catalog.
- **Shared fixtures:** Two JSON files at `shared/test-fixtures/`; the catalog
  one mirrors catalog facts as a cross-platform contract test.

## Problems found

1. **Anchor data is duplicated between calculation rules and `sourceEvidence`.**
   Verified: for all 11 table profiles carrying `sourceEvidence`, the
   `tableInterpolation.anchors` pairs are reproduced 100% as
   `sourceEvidence[].adjustments[].exposure.correctedTime` pairs (e.g. Tri-X:
   11/11 identical). The spec frames this as intentional (calc vs display
   separation), but it is still two hand-maintained copies of the same numbers
   in one file — edit one, forget the other, and they silently diverge.

2. **Serialization artifacts hostile to hand-editing.** Triple-nested
   `formula.formula.formulaFamily`, four-level
   `adjustments[].exposure.correctedTime.correctedSeconds`, and `kind`
   discriminators that restate the sibling key. These exist only to satisfy
   `Codable`/`kotlinx.serialization` tagged-union decoding. A human editing a
   single corrected-time row must navigate about five nesting levels with
   redundant `kind` strings.

3. **The catalog is physically duplicated as two ~3818-line files**, synced by
   copy with no generation step. They already differ at the tail. Any future
   film edit must be applied to both trees identically.

4. **Alternate / community / app-derived profiles live in code, in two
   languages.** About 500 lines of Swift and 443 of Kotlin define profiles that
   are conceptually catalog data. They are invisible to any catalog editor and
   must be edited twice (Swift + Kotlin) with hand-matched anchor evidence.

5. **A hardcoded special-case allowlist in both loaders does not scale.**
   `isPromotedUnofficialPracticalPrimary` pins one film's identity, formula
   parameters, and exact evidence numbers (`5 -> 13.5`, `10 -> 41`,
   `15 -> 80`) inline in Swift and Kotlin. Adding any second non-official
   primary requires editing both loaders, not the data.

6. **Source metadata is repeated across films.** Verified: 7 distinct
   publishers across 37 profiles (Ilford Photo x12, Kodak x9, Rollei x6, ...);
   `citation: "Technical information sheet"` x12 and `title: "Reciprocity
   characteristics"` x12 are re-typed per film. No shared source registry.

7. **The cross-platform fixture under-covers the catalog and a spec text is
   stale.** `perFilmExpectations` pins 34/37 films; the 3 newest Rollei films
   are unverified by the contract test. `DomainSchema.md` section 13.4 still
   says "34-film launch-ready scope" while 37 ship.

## Human-editability assessment

- **Easy:** Top-level film fields (`id`, `iso`, `manufacturer`, `brandLabel`,
  `aliases`, `canonicalStockName`), `notes` arrays, and `source` string fields
  read cleanly.
- **Hard:** Anything inside `rules` and `sourceEvidence` — the triple/quadruple
  nesting and repeated `kind` discriminators. Distinguishing a calculation
  anchor from a display-only evidence row requires understanding that
  `tableInterpolation.anchors` is authoritative while `sourceEvidence` is
  display, despite identical numbers.
- **Error-prone:** Keeping `anchors` and `sourceEvidence` in sync (problem 1);
  editing a film in two physical catalog files (problem 3); editing an
  alternate profile in two languages (problem 4); re-typing publisher/citation
  strings (problem 6).
- **Missing metadata:** No catalog-document `version`/`generatedFrom`/
  `schemaVersion` field (the catalog has none; only custom-film snapshots carry
  one). No explicit per-row marker that `sourceEvidence` mirrors the anchors.
  No machine-checkable link from an app-derived/community profile back to the
  official film it augments (that relationship is implicit in code).
- **Drift risks:** anchors vs evidence; iOS vs Android catalog copies; catalog
  vs `catalog-validation-cases.json`; catalog vs code-defined alternates;
  catalog vs `DomainSchema.md` film count; custom-film schemaVersion semantics
  iOS vs Android.

## Cross-platform risks

- **Verified divergence — custom-film version handling:** Android rejects any
  `schemaVersion != 1` (reads as empty); iOS ignores `schemaVersion` entirely
  and decodes whatever it can. If a future schema 2 ships, the two platforms
  behave differently on the same payload. This matters the moment custom films
  become shareable.
- **Verified — two catalog copies, already drifting at the tail.** Low impact
  today (semantically equal) but structurally fragile; there is no generator or
  checksum guarding equality.
- **Verified — alternate profiles duplicated in Swift and Kotlin.** Numeric
  parity is currently maintained by parallel tests, but the numbers themselves
  are typed twice.
- **Likely risk (not a current bug) — portability of `referenceTableFilmID`.**
  A custom fitted-formula film links to its source table film by id. An
  exported custom film whose referenced table is absent in the importer's
  library would dangle. There is no export path today, so this is latent, not
  active.
- **Verified — fixture coverage asymmetry:** the Android catalog test and iOS
  golden test both consume `catalog-validation-cases.json`, but its
  `perFilmExpectations` omits 3 shipped films, so that cross-platform guarantee
  is weaker than it appears.

## Format options

| Option | Pros | Cons | Validation impact | Human editability | Recommendation level |
| ------ | ---- | ---- | ----------------- | ----------------- | -------------------- |
| Keep JSON, simplify structure (flatten tagged unions, drop redundant `kind`, derive evidence from anchors) | Minimal tooling change; reuses existing decoders with a thin shim; removes the worst duplication | Still verbose; comments not allowed in strict JSON; doesn't fix the two-copy problem | Low — existing validators adapt to flatter shapes | Moderately improved | High (incremental) |
| Split human authoring format -> generated runtime JSON | Authoring file optimized for humans; runtime JSON optimized for decoders; single source of truth; generator can emit both platforms identically and dedupe anchors/source | Requires a build/generation step and a generator to maintain; two artifacts to reason about | Validation moves to generation time; runtime keeps a cheap shape check | Large improvement | High (strategic) |
| YAML | Comments, anchors/aliases, far less punctuation noise; good for nested data | Whitespace-significant (easy to break); needs a YAML parser on both platforms (extra dependency); still nested | Comparable to JSON once parsed | Good | Medium |
| TOML | Very readable for flat key/value + tables; comments | Poor fit for deeply nested arrays-of-objects (anchors, adjustments) — gets awkward fast; parser dependency | Moderate | Good for metadata, poor for rule trees | Low–Medium |
| Markdown + tables | Most readable for source rows/anchors; doubles as documentation | Loose structure; hard to validate reliably; lossy for tagged-union rule params; parser is bespoke | High difficulty | Excellent to read, risky to parse | Low (except as generated docs) |
| CSV/TSV tables + metadata sidecar | Anchors/evidence are literally tables — CSV is ideal for them; trivial diff/review; spreadsheet-editable | Splits one film across files; rule params and unions don't fit tabular cells; join logic needed | Moderate (per-file plus cross-file) | Excellent for anchors, poor for profiles | Medium (for the anchor/evidence layer only) |
| SQLite / structured DB | Strong integrity constraints; dedup via foreign keys (source registry) | Binary, not diff-reviewable, not hand-editable in a text editor — directly against the stated goal; heavyweight | Strong at query time, but opaque in PRs | Poor | Low (no strong reason here) |
| Mixed: source registry + film files + generated platform catalog | Dedupes source metadata; one file per film keeps diffs small; generator emits both platform JSONs and the validation fixture; anchors authored once | Most upfront design; needs a generator and a directory convention | Validation centralizes in the generator; runtime keeps a shape check | Best overall | High (target architecture) |

## Recommended direction

> Post-review update. The product owner directed that the runtime catalog be
> rebuilt (not frozen). After two review rounds with ChatGPT, the agreed
> direction is **PTIMER Catalog v2** — a single human-readable, data-oriented
> JSON that the app decodes directly through an adapter, with calculation and
> persistence behavior held equivalent. The full consolidated design is in
> [PTIMER-186-catalog-v2-proposal.md](PTIMER-186-catalog-v2-proposal.md). Two
> corrections to this report surfaced during review: (1) the options-table
> rating of "Keep JSON, simplify structure" as High was inconsistent with the
> decision to rebuild the runtime — superseded by the v2 proposal; (2) the
> fixture is only partially live (see the corrected Fixture facts above). The
> original split authoring -> generated direction below is retained for context.

- **Primary recommendation:** Move toward a split authoring -> generated
  runtime model (option 2), structured as a mixed layout (option 7): a small
  shared source registry (publisher/title/citation/version keyed by id), one
  authoring file per film with anchors authored once, and a generator that
  emits the two platform `LaunchPresetFilmCatalog.json` copies and the
  `catalog-validation-cases.json` fixture. Keep the authoring file in JSON or
  YAML; do not adopt TOML/CSV/SQLite as the primary store.
- **Why:** It directly removes the four highest-impact verified problems —
  anchor/evidence duplication (derive evidence from anchors at generation), the
  two hand-synced catalog copies (generate both), per-film source repetition
  (registry), and the fixture coverage gap (generate the fixture from the same
  source). It preserves the existing runtime decode path and protected
  calculation behavior because the generated runtime artifact can remain the
  current schema.
- **What should remain runtime-only:** The flattened, decoder-shaped JSON the
  loaders consume; the `kind`-discriminated union encoding; the custom-film
  UserDefaults/DataStore snapshot schema and keys. These are persistence/restore
  contracts (Protected Area) and should change only behind their own ticket.
- **What should become authoring-friendly:** Anchors authored once per profile;
  source metadata referenced from a registry; alternate/community/app-derived
  profiles expressed as data alongside the official profile rather than as
  Swift/Kotlin literals.
- **What can be generated:** Both platform catalogs, the validation fixture,
  and (optionally) human-readable Markdown tables for review.
- **What should not be changed yet:** `ExposureCalculator.calculate`, the
  reciprocity policy evaluation order, table/formula calculation semantics, and
  the custom-film schema/keys. No format change should alter the decoded domain
  values; equivalence must be proven by the existing golden/contract tests
  before any cutover.

## Candidate follow-up tickets

These are candidates only — analysis-only task; nothing is filed.

1. **Generate platform catalogs and the validation fixture from one source.**
   - Problem: Two 3818-line catalog copies plus a hand-maintained fixture drift
     independently (tail drift already present; fixture pins 34/37).
   - Why it matters: Manual multi-file sync is the largest ongoing maintenance
     and correctness risk.
   - Suggested scope: Author format + generator that emits
     `ios/.../LaunchPresetFilmCatalog.json`,
     `android/.../LaunchPresetFilmCatalog.json`, and
     `catalog-validation-cases.json`; CI/check that generated == committed.
   - Out of scope: Changing decoded values, runtime decode schema, calculation
     behavior.
   - Verification needed: Golden + catalog-shape tests pass byte-for-byte
     against generated output on both platforms.

2. **Derive `sourceEvidence` anchors from `tableInterpolation.anchors` (stop
   storing both).**
   - Problem: 11/11 table profiles duplicate anchors verbatim into
     `sourceEvidence`.
   - Why it matters: Two copies of the same numbers in one file invite silent
     divergence.
   - Suggested scope: In the authoring format, author anchors once; generate
     evidence rows; keep runtime shape unchanged.
   - Out of scope: Formula-profile `sourceEvidence` that has no anchor
     counterpart; display semantics.
   - Verification needed: Reference-presenter and table tests unchanged;
     generated runtime evidence equals today's.

3. **Reconcile custom-film `schemaVersion` handling across platforms.**
   - Problem: Android rejects unknown versions; iOS ignores the field.
   - Why it matters: Becomes a correctness/portability bug the moment custom
     films are shared or the schema bumps.
   - Suggested scope: Define one forward-compat policy; align both stores;
     document it.
   - Out of scope: Adding an export/import UI.
   - Verification needed: Round-trip and version-mismatch tests on both
     platforms.

4. **Close the validation-fixture / spec film-count gap.**
   - Problem: `perFilmExpectations` covers 34/37; `DomainSchema.md` section 13.4
     says "34" while 37 ship.
   - Why it matters: Weakened cross-platform guarantee and a stale spec.
   - Suggested scope: Pin all 37 films (ideally via ticket 1's generator);
     update the spec count and its source-of-truth note.
   - Out of scope: Changing catalog contents.
   - Verification needed: Fixture covers 37; spec review.

A possible 5th — moving code-defined alternates into data and replacing the
hardcoded allowlist — should wait until the authoring/generation model from
ticket 1 exists, since it depends on that representation.

## What is unknown

- Whether the product owner wants user-facing export/import of custom films at
  all. That single decision determines how much of the portability work
  (referenceTableFilmID resolution, schemaVersion policy) is urgent versus
  latent.
- Whether a build-time generation step is acceptable in this project's
  toolchain (no generator exists today; CI platform is explicitly undecided per
  AGENTS.md). The recommended direction assumes one can be added.
- Exact intended scope boundary between "launch catalog" (37, in JSON) and
  "code-defined alternates" — whether keeping official primaries in data while
  alternates stay in code is a deliberate policy or an artifact of incremental
  tickets (PTIMER-159/160/168). No doc stating the rule was found; the loader
  enforces "exactly one official primary," but the rationale for
  alternates-in-code is not documented.
- No `swift test`, `xcodebuild`, or `./gradlew` was run — no build/test
  verification was performed, only static inspection.

## Final verdict

The launch catalog is a single, deeply nested, decoder-shaped JSON that is
simultaneously the authoring surface and the runtime payload, physically
duplicated across iOS and Android and partially shadowed by code-defined
alternate profiles and a restating test fixture — so the same facts (anchors,
source metadata, film lists) exist in three-to-four hand-synced places. The
highest-leverage, evidence-backed direction is not a new file format per se but
a separation of an authoring source from generated runtime artifacts, organized
as a source registry plus per-film authoring files with anchors authored once,
from which both platform catalogs and the validation fixture are generated; the
runtime decode schema and all calculation/persistence contracts (Protected
Areas) stay frozen and are proven unchanged by the existing golden and contract
tests before any cutover.
