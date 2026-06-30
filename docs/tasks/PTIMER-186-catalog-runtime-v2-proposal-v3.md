# PTIMER-186 — Catalog Runtime Schema v2 Proposal, v3

## Verdict

PTIMER Catalog v2는 **새 runtime JSON 포맷**으로 설계한다.

v3는 ChatGPT 제안과 Claude 2차 검토를 병합한 안이다. 핵심은 다음과 같다.

- Runtime v2를 먼저 도입한다.
- Authoring source + generator는 phase 2로 둔다.
- Profile header / calculation / evidence를 분리한다.
- `calculation` 블록을 채택한다.
- `model`과 `calculation.kind` 중복은 만들지 않는다.
- Table anchors는 object 배열로 둔다.
- Table evidence는 손실을 막기 위해 index-based `evidence` 레이어로 유지한다.
- Formula는 domain 1:1 매핑을 위해 `coefficient` 형태를 유지한다.
- Custom film export/import는 별도 product-gated track으로 분리한다.

No code changes are implied by this proposal. This is a design proposal only.

---

## 1. Scope

### In scope

- Define PTIMER Catalog Runtime Schema v2.
- Replace the current decoder-shaped launch catalog JSON with a human-readable, data-oriented runtime JSON.
- Decode v2 through an adapter into the existing domain model.
- Preserve decoded domain values and calculation behavior.
- Represent table, formula, and limited-guidance profiles in one consistent schema.
- Preserve table evidence metadata such as development correction, approximate rows, warnings, and evidence-only rows.
- Move code-defined alternate / app-derived / community profiles toward data representation.
- Replace hardcoded promoted-unofficial allowlist with data validation rules.

### Out of scope

- Changing exposure calculation semantics.
- Changing reciprocity evaluator behavior.
- Changing timer behavior.
- Changing custom-film persistence keys.
- Designing user-facing custom film export/import.
- Adding generator tooling in phase 1.
- Changing film values as part of schema migration.

---

## 2. Phase plan

### Phase 1 — Runtime v2

Phase 1 introduces the new runtime format directly.

- Add `LaunchPresetFilmCatalog.v2.json`.
- Add iOS and Android v2 decoders.
- Add adapter: v2 -> existing `FilmIdentity` / `ReciprocityProfile`.
- Keep evaluator, presenters, and persistence contracts unchanged.
- Add v1-v2 decoded-domain equivalence tests.
- Add golden exposure equivalence tests.
- Keep v1 catalog as legacy fallback or comparison source until cutover is proven.

### Phase 2 — Authoring source + generator

Phase 2 can improve maintenance after runtime v2 is proven.

- Optional YAML or split JSON authoring source.
- Source registry and per-film files if the catalog grows.
- Generator emits runtime v2 JSON and validation fixtures.
- Dead fixture blocks must be revived-and-asserted or removed.

Phase 2 is not required to define the v2 runtime schema.

---

## 3. Top-level schema

```json
{
  "schema": "ptimer.catalog.v2",
  "schemaVersion": 2,
  "catalogVersion": "2026.06",
  "license": "Apache-2.0",
  "copyright": "Copyright © 2026 Sangwook Han",
  "sources": {},
  "films": []
}
```

### Notes

- `schema` and `schemaVersion` are required.
- `catalogVersion` is a data revision label, not app version.
- `sources` is a registry keyed by stable source id.
- `films` contains preset launch films and their profiles.

---

## 4. Source registry

```json
{
  "sources": {
    "kodak-tri-x-f4017": {
      "publisher": "Kodak",
      "title": "KODAK PROFESSIONAL TRI-X 400 Film — Technical Data",
      "citation": "Publication F-4017",
      "sourceType": "manufacturerPublished",
      "authority": "official",
      "confidence": "high"
    },
    "rollei-retro-400s-lafitte": {
      "publisher": "Stéphane Lafitte",
      "title": "Rollei Retro 400S",
      "citation": "Rollei Retro 400S — Réciprocité",
      "sourceType": "thirdPartyPublication",
      "authority": "unofficial",
      "confidence": "medium"
    }
  }
}
```

### Source id policy

Source ids should be short, stable, and human-managed.

Preferred examples:

```text
ilford-reciprocity
kodak-tri-x-f4017
kodak-tmax-100-f4016
foma-fomapan-100-sheet
rollei-retro-400s-lafitte
```

Avoid generated title slugs that are long and fragile.

### Authority distinction

`source.authority` and `profile.authority` are separate concepts.

- `source.authority`: authority of the cited source document.
- `profile.authority`: authority or origin of the profile itself.

Example: an app-derived formula may use an official datasheet source, while the profile itself remains `appDerived`.

---

## 5. Film object

```json
{
  "id": "kodak-tri-x-400",
  "canonicalStockName": "Tri-X 400",
  "manufacturer": "Kodak",
  "brandLabel": "KODAK PROFESSIONAL TRI-X 400",
  "aliases": ["TRI-X", "TX 400"],
  "iso": 400,
  "kind": "preset",
  "productionStatus": "current",
  "profiles": []
}
```

### Notes

- `canonicalStockName` is kept to reduce migration and restore risk.
- `profiles` can contain primary, alternate, derived, community, or unofficial profiles.
- Preset launch films must have exactly one `role: "primary"` profile.

---

## 6. Profile common header

```json
{
  "id": "kodak-tri-x-official-graph-table",
  "label": "Official Kodak graph/table",
  "selectorLabel": "Graph table",
  "role": "primary",
  "authority": "official",
  "basis": "manufacturerGraphTable",
  "sourceId": "kodak-tri-x-f4017",
  "model": "table",
  "calculation": {},
  "evidence": [],
  "referencePoints": [],
  "notes": []
}
```

### Required profile fields

- `id`
- `label`
- `role`
- `authority`
- `sourceId`
- `model`

### Optional profile fields

- `selectorLabel`
- `basis`
- `calculation`
- `evidence`
- `referencePoints`
- `fit`
- `notes`

### Role enum

```text
primary | alternate | derived
```

`community` is not a role. A community table should be represented as:

```json
{
  "role": "alternate",
  "authority": "community"
}
```

### Authority enum

```text
official | appDerived | community | unofficial | userDefined
```

### Basis enum

`basis` is optional but should be present when needed to round-trip `modelBasis.sourceModel`.

```text
manufacturerFormula
manufacturerTable
manufacturerGraphTable
manufacturerRangeGuidance
manufacturerLimitedGuidance
practicalCommunityGuidance
```

---

## 7. Discriminator rule

Do not duplicate the discriminator.

v3 uses:

```json
{
  "model": "table",
  "calculation": {
    "interpolation": "logLog",
    "anchors": []
  }
}
```

Do not use:

```json
{
  "model": "table",
  "calculation": {
    "kind": "table",
    "anchors": []
  }
}
```

`model` is the discriminator. `calculation` contains the model-specific parameters.

---

## 8. Table profile

### Rule

- Table calculation anchors are the calculation source of truth.
- Anchors are object rows, not positional pairs.
- Evidence metadata is kept in a separate `evidence` layer referencing anchor index.
- `sourceEvidence` from v1 is not stored directly.

### Example

```json
{
  "id": "kodak-tri-x-official-graph-table",
  "label": "Official Kodak graph/table",
  "selectorLabel": "Graph table",
  "role": "primary",
  "authority": "official",
  "basis": "manufacturerGraphTable",
  "sourceId": "kodak-tri-x-f4017",
  "model": "table",
  "calculation": {
    "interpolation": "logLog",
    "noCorrectionThroughSeconds": 0.1,
    "sourceRangeThroughSeconds": 100,
    "anchors": [
      { "meteredSeconds": 1, "correctedSeconds": 2 },
      { "meteredSeconds": 2, "correctedSeconds": 5 },
      { "meteredSeconds": 3, "correctedSeconds": 10 },
      { "meteredSeconds": 5, "correctedSeconds": 20 },
      { "meteredSeconds": 7, "correctedSeconds": 32 },
      { "meteredSeconds": 10, "correctedSeconds": 50 },
      { "meteredSeconds": 20, "correctedSeconds": 120 },
      { "meteredSeconds": 30, "correctedSeconds": 200 },
      { "meteredSeconds": 50, "correctedSeconds": 420 },
      { "meteredSeconds": 70, "correctedSeconds": 720 },
      { "meteredSeconds": 100, "correctedSeconds": 1200 }
    ]
  },
  "evidence": [
    { "anchor": 0, "development": "-10% development" },
    { "anchor": 1, "approx": true },
    { "anchor": 2, "approx": true },
    { "anchor": 3, "approx": true },
    { "anchor": 4, "approx": true },
    { "anchor": 5, "development": "-20% development" },
    { "anchor": 6, "approx": true },
    { "anchor": 7, "approx": true },
    { "anchor": 8, "approx": true },
    { "anchor": 9, "approx": true },
    { "anchor": 10, "development": "-30% development" }
  ],
  "notes": [
    "Published rows combined with graph-sampled points."
  ]
}
```

### Why evidence is separate

The table anchors carry calculation numbers.

The evidence layer preserves display/provenance metadata that cannot be derived from anchors:

- development correction
- approximate graph-sampled row
- warning
- evidence-only status
- published-row distinction, if needed

This avoids the v1 problem of duplicating metered/corrected numbers in both anchors and `sourceEvidence`, while still preserving non-numeric evidence metadata.

### Why evidence uses anchor index

`evidence[].anchor` references the anchor row by index.

Reason:

- It avoids retyping metered/corrected numbers.
- It avoids typo drift in evidence rows.
- It preserves one numeric source of truth.

Required validation:

- `evidence[].anchor` must be an integer.
- `evidence[].anchor` must be within `calculation.anchors.indices`.
- When anchors are reordered, validation/equivalence tests must catch mismatched evidence semantics.

---

## 9. Formula profile

### Rule

Formula parameters should map closely to the existing domain model.

Use `coefficient`, not `referenceCorrectedSeconds`, as the stored field.

Reason:

- The domain has coefficient/reference metered fields.
- `referenceCorrectedSeconds` can be a derived value when exponent and offset are involved.
- Storing derived fields can introduce contradictions.

### Example

```json
{
  "id": "ilford-hp5-plus-400-official-formula",
  "label": "Official formula",
  "role": "primary",
  "authority": "official",
  "basis": "manufacturerFormula",
  "sourceId": "ilford-reciprocity",
  "model": "formula",
  "calculation": {
    "family": "modifiedSchwarzschild",
    "coefficient": 1,
    "referenceMeteredSeconds": 1,
    "exponent": 1.31,
    "offsetSeconds": 0,
    "noCorrectionThroughSeconds": 1,
    "sourceRangeThroughSeconds": 100
  }
}
```

### Defaults

To reduce noise, defaults may be omitted:

```json
{
  "calculation": {
    "family": "modifiedSchwarzschild",
    "exponent": 1.31,
    "noCorrectionThroughSeconds": 1
  }
}
```

Default interpretation:

```text
coefficient = 1
referenceMeteredSeconds = 1
offsetSeconds = 0
```

The adapter must apply these defaults consistently on both platforms.

---

## 10. Formula reference points

Formula profiles may carry display-only reference points.

```json
{
  "referencePoints": [
    {
      "meteredSeconds": 5,
      "correctedSeconds": 13.5
    },
    {
      "meteredSeconds": 10,
      "correctedSeconds": 41
    },
    {
      "meteredSeconds": 15,
      "correctedSeconds": 80
    }
  ]
}
```

Rules:

- `referencePoints` are not calculation anchors.
- `referencePoints` are display/provenance data.
- `meteredSeconds` must be present.
- `correctedSeconds` may be omitted when the source provides guidance but not a quantified corrected time.
- Avoid explicit `null` unless the decoder contract requires it.
- A reference point with neither metered nor corrected value is invalid.

Example warning-only point:

```json
{
  "meteredSeconds": 480,
  "warning": {
    "severity": "notRecommended",
    "message": "8 min is not recommended."
  }
}
```

Example evidence-only point:

```json
{
  "meteredSeconds": 0.001,
  "evidenceOnly": true
}
```

---

## 11. Range guidance for formula profiles

Some film guidance describes a range rather than a single point.

Use `referenceRanges` for this instead of null-valued reference points.

```json
{
  "referenceRanges": [
    {
      "fromSeconds": 120,
      "throughSeconds": 1000,
      "stopDelta": 0.5,
      "message": "Constant correction across the published range."
    }
  ]
}
```

Rules:

- `fromSeconds` and `throughSeconds` must be present.
- `fromSeconds < throughSeconds`.
- Range guidance is display/provenance data unless explicitly mapped by calculation fields.

---

## 12. Limited guidance profile

The old threshold + limitedGuidance pair becomes one model.

```json
{
  "id": "kodak-ektar-100-official-threshold",
  "label": "Official threshold guidance",
  "role": "primary",
  "authority": "official",
  "basis": "manufacturerLimitedGuidance",
  "sourceId": "kodak-ektar-e4046",
  "model": "limitedGuidance",
  "calculation": {
    "noCorrectionRange": [0.0001, 1],
    "guidance": [
      {
        "fromSeconds": 1,
        "message": "Longer exposures: test under your conditions."
      }
    ]
  }
}
```

Rules:

- `noCorrectionRange` is `[minSeconds, maxSeconds]`.
- The lower bound must be preserved.
- Guidance entries must be sorted by `fromSeconds`.
- This model cannot carry table anchors or formula parameters.

---

## 13. App-derived profile

```json
{
  "id": "foma-fomapan-100-app-formula",
  "label": "App-derived formula",
  "role": "derived",
  "authority": "appDerived",
  "basis": "manufacturerTable",
  "sourceId": "foma-fomapan-100-sheet",
  "derivedFromProfileId": "foma-fomapan-100-official-table",
  "model": "formula",
  "calculation": {
    "family": "modifiedSchwarzschild",
    "coefficient": 2.2457,
    "referenceMeteredSeconds": 1,
    "exponent": 1.4515,
    "offsetSeconds": 0,
    "noCorrectionThroughSeconds": 0.5,
    "sourceRangeThroughSeconds": 100
  },
  "fit": {
    "method": "logLogLeastSquares",
    "from": "officialTableAnchors"
  }
}
```

Rules:

- `role` should be `derived`.
- `authority` should be `appDerived`.
- `derivedFromProfileId` should identify the source profile when applicable.
- The profile source can still be an official source document.

---

## 14. Community profile

```json
{
  "id": "foma-fomapan-100-ohzart-community-table",
  "label": "Ohzart community table",
  "role": "alternate",
  "authority": "community",
  "basis": "practicalCommunityGuidance",
  "sourceId": "ohzart-fomapan-100",
  "model": "table",
  "calculation": {
    "interpolation": "logLog",
    "anchors": [
      { "meteredSeconds": 1, "correctedSeconds": 2 },
      { "meteredSeconds": 10, "correctedSeconds": 70 }
    ]
  }
}
```

Rules:

- Community is an authority, not a role.
- A community profile normally uses `role: "alternate"`.
- A community or unofficial profile may be primary only when promoted by explicit data rules.

---

## 15. Promoted unofficial primary

```json
{
  "id": "rollei-retro-400s-unofficial-practical",
  "label": "Unofficial practical approximation",
  "role": "primary",
  "authority": "unofficial",
  "basis": "practicalCommunityGuidance",
  "sourceId": "rollei-retro-400s-lafitte",
  "model": "formula",
  "calculation": {
    "family": "modifiedSchwarzschild",
    "exponent": 1.62,
    "noCorrectionThroughSeconds": 1,
    "sourceRangeThroughSeconds": 15
  },
  "referencePoints": [
    { "meteredSeconds": 5, "correctedSeconds": 13.5 },
    { "meteredSeconds": 10, "correctedSeconds": 41 },
    { "meteredSeconds": 15, "correctedSeconds": 80 }
  ],
  "notes": [
    "Unofficial practical approximation. Not manufacturer-published reciprocity guidance."
  ]
}
```

Validation rule:

```text
If role == primary and authority in {community, unofficial}:
- sourceId must exist.
- source confidence must not be high unless explicitly allowed.
- basis must explain practical/community guidance.
- calculation must be guarded.
- referencePoints must be non-empty.
```

This replaces a hardcoded allowlist in platform loaders.

---

## 16. Validation rules

### Catalog

- `schema == "ptimer.catalog.v2"`
- `schemaVersion == 2`
- film ids unique
- profile ids unique
- source ids unique
- every `sourceId` exists
- preset launch film has exactly one `role: "primary"` profile

### Film

- `id` non-empty
- `canonicalStockName` non-empty
- `iso > 0`
- `kind in {preset, custom, imported}`
- `productionStatus` valid
- `profiles` non-empty

### Profile

- `role in {primary, alternate, derived}`
- `authority in {official, appDerived, community, unofficial, userDefined}`
- `model in {formula, table, limitedGuidance}`
- `basis` valid when present
- model-specific calculation block must match `model`

### Table

- `calculation.anchors.count >= 1`
- `meteredSeconds > 0`
- `correctedSeconds >= meteredSeconds`
- anchors strictly ascending by `meteredSeconds`
- no duplicate `meteredSeconds`
- interpolation valid
- `evidence[].anchor` indices valid
- `noCorrectionThroughSeconds` must be less than or equal to the first correction range boundary

### Formula

- formula family supported
- exponent > 0
- coefficient > 0
- referenceMeteredSeconds > 0
- offsetSeconds finite
- corrected result must not go below metered time
- sourceRangeThroughSeconds, when present, must be >= noCorrectionThroughSeconds

### Limited guidance

- `noCorrectionRange` has two values
- min < max
- guidance entries sorted
- no table anchors or formula parameters

---

## 17. Equivalence requirements

Before cutover, v2 must pass equivalence checks against v1.

Required checks:

- film count unchanged
- film ids unchanged
- profile ids unchanged, except explicitly moved alternates if included
- decoded `FilmIdentity` equivalent
- decoded `ReciprocityProfile` equivalent
- source metadata equivalent
- modelBasis equivalent
- calculation model equivalent
- table anchors equivalent
- formula parameters equivalent
- limited guidance equivalent
- source evidence / display evidence equivalent
- golden exposure values unchanged
- restore identity behavior unchanged

No runtime cutover should occur before these checks pass on both iOS and Android.

---

## 18. Fixture policy

Current fixture status must be handled explicitly.

- `catalogExpectations`: keep and regenerate or update for v2.
- `perFilmExpectations`: either revive and assert, or remove.
- `rejectionCases`: either revive and assert, or remove.
- `launchCatalogValidationRules`: either revive and assert, or remove.

Rule:

```text
No generated dead fixture content.
Any fixture block kept in the repository must be consumed by tests.
```

---

## 19. File layout

### Phase 1

Use a single v2 runtime file.

```text
shared/catalog/LaunchPresetFilmCatalog.v2.json
ios/PTimerKit/Sources/PTimerCore/Catalog/LaunchPresetFilmCatalog.v2.json
android/core/src/main/resources/LaunchPresetFilmCatalog.v2.json
```

The platform copies must be byte-identical or checked by a sync script.

### Phase 2

If needed:

```text
shared/catalog/v2/
  sources.json
  films/
    kodak-tri-x-400.json
    foma-fomapan-100.json
```

Phase 2 may introduce generator output, but phase 1 does not depend on this split.

---

## 20. Custom film policy

Runtime v2 grammar should be reusable by custom film editor output.

However, user-facing custom film export/import is not designed here.

Deferred decisions:

- whether product scope includes custom film export/import
- portable custom film package format
- schemaVersion policy alignment
- `referenceTableFilmID` location and dangling reference behavior
- iOS/Android persistence migration policy

---

## 21. Final merged decision

```text
PTIMER Catalog v2 is a new human-readable runtime JSON format.

Adopt the calculation block, but use top-level model as the discriminator and
do not repeat calculation.kind.

Use object anchors for editing safety.

Preserve table evidence through an index-based evidence layer so development
corrections, approximate rows, warnings, and evidence-only rows are not lost.

Use coefficient-based formula parameters for domain 1:1 mapping.

Keep runtime v2 first. Treat authoring source and generator as phase 2.

Keep custom film export/import as a separate product-gated track.
```
