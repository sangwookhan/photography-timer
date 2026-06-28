# PTIMER Catalog v2 — merged final proposal

Design proposal only. No code, runtime, or Jira changes are implied. Supersedes
the earlier draft of this file and consolidates: ChatGPT proposal v3
([PTIMER-186-catalog-runtime-v2-proposal-v3.md](PTIMER-186-catalog-runtime-v2-proposal-v3.md))
plus the source-verified evidence-grammar completion from the PTIMER-186 review.
The schema here is exercised by a real conversion of all 37 launch films
([PTIMER-186-catalog-v2.sample.json](PTIMER-186-catalog-v2.sample.json)), which
passes an independent v1-equivalence verifier over the full evidence grammar.

## Verdict

PTIMER Catalog v2 is a new, human-readable, data-oriented JSON that the app
decodes directly through an adapter into the existing domain model. Calculation
and persistence behavior are unchanged and pinned by an equivalence test.

Merged decisions:

- New runtime JSON first; authoring source + generator are phase 2.
- `calculation` block groups model parameters; **`model` is the only
  discriminator** (no `calculation.kind`).
- Table anchors are **object rows** (`{ meteredSeconds, correctedSeconds }`) for
  edit safety; they are the single calculation source of truth.
- Table evidence is a separate **index-based `evidence` layer** so non-numeric
  metadata is preserved without restating anchor numbers.
- Formula parameters use the **`coefficient` form** for 1:1 domain mapping.
- The evidence / reference layer covers the **complete published grammar**
  (correctedTime, stopDelta, multiplier, development, colorFilter, warning,
  note, approx, evidence-only, and metered ranges) — see section 9.
- Promoted-unofficial primary is validated by **data rules**, not a hardcoded
  allowlist.
- Custom film export/import is a separate, product-gated track.

## 1. Scope

In scope: define the v2 runtime schema; replace the decoder-shaped launch
catalog; decode via adapter into existing `FilmIdentity` / `ReciprocityProfile`;
preserve decoded values and calculation behavior; represent table/formula/
limited-guidance consistently; preserve all evidence metadata; move code-defined
alternates toward data; replace the promoted-unofficial allowlist with data
rules.

Out of scope: exposure-calculation semantics; reciprocity evaluator; timer;
custom-film persistence keys; user-facing custom export/import; generator tooling
(phase 2); changing any shipped film value.

## 2. Phase plan

Phase 1 — runtime v2: add `LaunchPresetFilmCatalog.v2.json`; iOS/Android v2
decoders; adapter v2 -> existing domain; keep evaluator/presenters/persistence
unchanged; add v1-v2 decoded-domain equivalence tests and golden exposure
equivalence tests; keep v1 as legacy/comparison until cutover is proven.

Phase 2 — authoring source + generator (optional): YAML or split-JSON authoring;
source registry / per-film files if the catalog grows; generator emits runtime
v2 and validation fixtures; dead fixture blocks revived-and-asserted or removed.

## 3. Top level

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

## 4. Source registry

Keyed by a short, stable, human-managed id. Profiles reference `sourceId`. In the
converted sample, 37 inline source blocks dedupe to 26 registry entries.

```json
"sources": {
  "kodak-publication": {
    "publisher": "Kodak",
    "title": "KODAK PROFESSIONAL TRI-X 400 Film — Technical Data",
    "citation": "Publication F-4017",
    "sourceType": "manufacturerPublished",
    "authority": "official",
    "confidence": "high"
  }
}
```

`source.authority` (authority of the cited document) and `profile.authority`
(origin of the profile itself) are distinct: an app-derived profile can cite an
official datasheet while the profile remains `appDerived`.

## 5. Film

```json
{
  "id": "kodak-tri-x-400",
  "canonicalStockName": "Tri-X 400",
  "manufacturer": "Kodak",
  "brandLabel": "KODAK PROFESSIONAL TRI-X 400",
  "aliases": ["Tri-X"],
  "iso": 400,
  "kind": "preset",
  "productionStatus": "current",
  "profiles": []
}
```

`canonicalStockName` keeps its key for restore compatibility. A preset launch
film has exactly one `role: "primary"` profile.

## 6. Profile header

Required: `id`, `label`, `role`, `authority`, `sourceId`, `model`.
Optional: `selectorLabel`, `basis`, `calculation`, `evidence`, `referencePoints`,
`referenceRanges`, `fit`, `notes`.

- `role`: `primary | alternate | derived`. Community is an authority, not a role;
  a community table is `role: "alternate"`, `authority: "community"`.
- `authority`: `official | appDerived | community | unofficial | userDefined`.
- `basis` (optional, header level): names `modelBasis.sourceModel` so it
  round-trips — `manufacturerFormula | manufacturerTable | manufacturerGraphTable
  | manufacturerRangeGuidance | manufacturerLimitedGuidance |
  practicalCommunityGuidance`. Omitted -> adapter infers from (authority, model).
- `model`: `formula | table | limitedGuidance`. The discriminator. `calculation`
  carries model-specific parameters and must NOT repeat a `kind`.

## 7. Table profile

Anchors are object rows and are the calculation source of truth. Evidence is a
separate index-referencing layer (section 9).

```json
{
  "id": "kodak-tri-x-official-graph-table",
  "label": "Official Kodak graph/table",
  "selectorLabel": "Graph table",
  "role": "primary",
  "authority": "official",
  "basis": "manufacturerGraphTable",
  "sourceId": "kodak-publication",
  "model": "table",
  "calculation": {
    "interpolation": "logLog",
    "noCorrectionThroughSeconds": 0.1,
    "sourceRangeThroughSeconds": 100,
    "anchors": [
      { "meteredSeconds": 1, "correctedSeconds": 2 },
      { "meteredSeconds": 10, "correctedSeconds": 50 },
      { "meteredSeconds": 100, "correctedSeconds": 1200 }
    ]
  },
  "evidence": [
    { "anchor": 0, "stopDelta": 1, "development": "-10% development" },
    { "anchor": 2, "development": "-30% development" }
  ]
}
```

## 8. Formula profile

`coefficient` form maps 1:1 to the domain `ReciprocityFormula`. Defaults
(`coefficient = 1`, `referenceMeteredSeconds = 1`, `offsetSeconds = 0`) may be
omitted and must be applied identically on both platforms.

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
    "exponent": 1.31,
    "noCorrectionThroughSeconds": 1
  }
}
```

## 9. Evidence and reference grammar (complete)

This is the piece that earlier drafts and ChatGPT v3 under-specified. The current
catalog's published evidence uses the full grammar below (verified counts across
the launch catalog). The v2 schema must represent all of it or equivalence fails
on slide films, Rollei, and Acros.

| Axis | Variants (verified count) |
| ---- | ------------------------- |
| metered position | exact point (78), **range** (1) |
| adjustment kind | exposure (96), development (3), **colorFilter** (7), warning (3), **note** (4) |
| exposure kind | correctedTime (63), **stopDelta** (20), **multiplier** (13) |

Three carriers, one shared field vocabulary:

- **`evidence`** (table profiles): rows reference an anchor by index and carry
  only non-anchor payload.
  `{ anchor, stopDelta?, multiplier?, development?, colorFilter?, warning?, note?,
  approx?, evidenceOnly? }` — metered/corrected come from the anchor, never
  restated.
- **`referencePoints`** (formula profiles): explicit points (no anchors).
  `{ meteredSeconds, correctedSeconds?, stopDelta?, multiplier?, colorFilter?,
  development?, warning?, note?, approx?, evidenceOnly? }`. `correctedSeconds` is
  omitted when the source publishes guidance but no quantified corrected time.
- **`referenceRanges`** (range-metered guidance, e.g. Acros II 120–1000 s):
  `{ fromSeconds, throughSeconds, stopDelta?, multiplier?, colorFilter?,
  development?, warning?, note? }`, with `fromSeconds < throughSeconds`.

Field meanings: `warning` is `{ severity, message }` with severity
`caution | notRecommended`; `colorFilter` is a published color-compensation
filter name (e.g. `5M`); `note` is a textual reference (e.g. an effective-exposure
range); `approx` marks a rounded/graph-sampled corrected time; `evidenceOnly`
marks a published point excluded from formula-fitting markers.

Verified real rows the schema now preserves (lost by the prior sample):

```json
// range guidance (Acros II)
"referenceRanges": [ { "fromSeconds": 120, "throughSeconds": 1000, "stopDelta": 0.5 } ]

// color-compensation filter point (Velvia 50)
"referencePoints": [ { "meteredSeconds": 4, "stopDelta": 0.3333, "colorFilter": "5M" } ]

// note-only point (Rollei Retro 80S)
"referencePoints": [ { "meteredSeconds": 1, "note": "Effective exposure 1 to 2 sec ..." } ]
```

## 10. Limited-guidance profile

The v1 threshold + limited-guidance pair becomes one model; the lower bound is
preserved.

```json
{
  "id": "kodak-ektar-100-official-threshold",
  "label": "Official threshold guidance",
  "role": "primary",
  "authority": "official",
  "basis": "manufacturerLimitedGuidance",
  "sourceId": "kodak-publication",
  "model": "limitedGuidance",
  "calculation": {
    "noCorrectionRange": [0.0001, 1],
    "guidance": [
      { "fromSeconds": 1, "message": "Longer exposures: test under your conditions." }
    ]
  }
}
```

## 11. Alternates, app-derived, community, promoted-unofficial as data

Coexist in one film's `profiles[]`, removing the code-defined Swift/Kotlin
alternates and the hardcoded allowlist.

```json
{ "id": "foma-fomapan-100-app-formula", "label": "App-derived formula",
  "role": "derived", "authority": "appDerived", "basis": "manufacturerTable",
  "sourceId": "foma-fomapan", "derivedFromProfileId": "foma-fomapan-100-official-table",
  "model": "formula",
  "calculation": { "family": "modifiedSchwarzschild", "coefficient": 2.2457, "exponent": 1.4515,
                   "noCorrectionThroughSeconds": 0.5, "sourceRangeThroughSeconds": 100 },
  "fit": { "method": "logLogLeastSquares", "from": "officialTableAnchors" } }
```

Promoted-unofficial primary is accepted by a data rule, not inline numeric
comparison:

```text
If role == primary and authority in {community, unofficial}:
  - sourceId exists
  - source.confidence != high (unless explicitly allowed)
  - basis describes practical/community guidance
  - formula passes the guarded-parameter contract
  - referencePoints is non-empty
```

## 12. Validation rules

Catalog: `schema`/`schemaVersion == 2`; film/profile/source ids unique; every
`sourceId` resolves; preset launch film has exactly one `primary`.
Profile: `role`, `authority`, `model`, `basis` (if present) in enum; calculation
block matches `model`.
Table: anchors >= 1; metered > 0; corrected >= metered; strictly ascending
metered, no duplicates; `evidence[].anchor` indices in range;
`noCorrectionThroughSeconds` below the first anchor.
Formula: family supported; exponent > 0; coefficient/referenceMetered > 0; offset
finite; corrected >= metered; sourceRange >= noCorrection.
Limited-guidance: `noCorrectionRange` has two values, min < max; guidance sorted;
no anchors/formula params.

## 13. Equivalence requirements (gate before cutover)

v2 must reproduce, on both platforms: film count/ids/order; decoded
`FilmIdentity` and `ReciprocityProfile`; source metadata; `modelBasis`;
calculation model; table anchors; formula parameters; limited guidance; and
**every source-evidence row's full grammar**; plus identical golden exposure
values and restore identity. No cutover before these pass.

Status of the sample in this repo: an independent verifier (parsing v1 and v2
separately, comparing the full evidence grammar as a multiset) reports PASS over
all 37 films. This is data-level equivalence; the in-app golden/restore checks
remain required at implementation time.

## 14. Fixture policy

`catalogExpectations`: keep/regenerate for v2. `perFilmExpectations`,
`rejectionCases`, `launchCatalogValidationRules`: revive-and-assert or remove.
Rule: no generated dead fixture content; any retained block must be asserted by a
test.

## 15. File layout

Phase 1: single `shared/catalog/LaunchPresetFilmCatalog.v2.json` copied to the
iOS and Android resource paths, with a byte-identity CI check. Phase 2: optional
split into `sources.json` + `films/<id>.json` via a generator.

## 16. Custom film (separate track)

The custom editor can reuse the v2 profile grammar, but export/import format,
`schemaVersion` alignment (Android rejects unknown versions; iOS ignores the
field), `referenceTableFilmID` placement and dangling-reference behavior, and
persistence migration are deferred to a product-gated ticket.

## What this closes (verified problems and review gaps)

Analysis problems 1 (anchor/evidence duplication), 2 (nesting), 3 (two hand-synced
files), 4 (code-defined alternates), 5 (hardcoded allowlist), 6 (source
repetition), 7 (fixture coverage/dead blocks). Review gaps G1 (table evidence
loss), G2 (modelBasis round-trip), G3 (formula parameterization), G4 (threshold
lower bound), G5 (correct examples). Plus the late-found evidence grammar gap
(colorFilter, note-only rows, discrete stopDelta/multiplier, metered ranges) that
both the prior sample and ChatGPT v3 had missed.
