# Domain Schema Spec

**Domain**: The data model behind film identities, reciprocity profiles, manufacturer rules, and the launch preset catalog.

This document specifies the **shape and meaning** of the domain — what fields exist, what they mean, what invariants hold. The encoding format (JSON, with a `kind` discriminator on union types) is a serialization detail recorded in §10; the spec body is platform- and serializer-neutral.

---

## 1. Top-level entities

The domain has three primary types:

- **Film identity** — a stable identifier for a film stock plus its identity-level metadata.
- **Reciprocity profile** — a manufacturer-published or user-defined dataset describing how that film responds at long exposure times. A film carries one or more profiles; the launch dataset ships exactly one profile per film.
- **Launch preset catalog** — the bundled collection of film identities shipped with the app.

Calculation results (the output of evaluating a profile against a metered exposure) are also part of the domain because they are persisted and round-tripped; they are specified in §6.

---

## 2. Film identity

### 2.1 Required fields

- **id** — non-empty string, unique within the catalog. Stable identifier; the user-facing UI never displays it. It is the key for persistence references.
- **kind** — one of:
  - `preset` — bundled launch dataset entry.
  - `custom` — user-defined entry (deferred; see §11).
  - `unknown` — present for forward-compatible decoding only; never written.
- **canonicalStockName** — non-empty, unique within the catalog. The display-default name for the film. Examples: `"Kodak TRI-X 400"`, `"ILFORD HP5 Plus"`.
- **manufacturer** — original manufacturer string when known. Repackaged brand labels (a film sold under different labels) shall not appear here; they go in `brandLabel`.
- **productionStatus** — one of `current`, `discontinued`, `unknown`. Launch dataset entries shall have `current`.
- **profiles** — array of [reciprocity profiles](#3-reciprocity-profile). The launch dataset shall contain exactly one entry per identity.

### 2.2 Optional fields

- **brandLabel** — string for the secondary brand under which the film is sold (e.g. a manufacturer-rebranded variant).
- **aliases** — array of strings; alternate names known to refer to the same film.
- **userMetadata** — user-editable metadata (see §2.3); absent for preset entries.

### 2.3 User-editable metadata

For non-preset (or user-augmented) identities:

- **displayNameOverride** — optional string overriding `canonicalStockName` in UI.
- **tags** — array of strings.
- **notes** — array of free-form note strings.

Preset launch entries shall not carry user metadata.

---

## 3. Reciprocity profile

A profile describes how a film stock responds to long-exposure metered values.

### 3.1 Required fields

- **id** — non-empty string, unique within the parent identity's profile array.
- **name** — non-empty string. Display label when surfacing the profile (e.g. "Manufacturer table").
- **source** — provenance metadata (see §4).
- **rules** — array of [reciprocity rules](#5-reciprocity-rules) — at least one entry. The order matters only insofar as the calculation policy's evaluation order is defined separately ([Calculator Spec](Calculator.md) §3.2).
- **notes** — array of free-form note strings (rendered as supporting copy).

### 3.2 Optional fields

- **userMetadata** — user-editable fields parallel to §2.3, scoped to this profile. Absent for preset profiles.

---

## 4. Source provenance

Every reciprocity profile carries provenance:

- **kind** — one of `manufacturer_published`, `manufacturer_secondary` (e.g. data sheets reissued through licensees), `vendor_published`, `community_field_tested`, `historical_archive`. The launch dataset shall use only `manufacturer_published`.
- **authority** — one of `official`, `field_tested`, `anecdotal`. The launch dataset shall use only `official`.
- **confidence** — one of `unknown`, `high`, `medium`, `low`. The default for omitted is `unknown`. The launch dataset uses `high`.
- **publisher** — required non-empty string (the entity that published the data, e.g. `"Kodak"`, `"ILFORD HARMAN"`).
- **title** — optional string referring to a specific document or page.
- **citation** — optional string with a more precise reference (URL, page number).
- **sourceVersion** — optional string identifying the published edition or revision.

The provenance fields shall be preserved verbatim from the source. The system shall not synthesize provenance to fill gaps; missing optional fields shall stay absent. (Wiki 13172737)

---

## 5. Reciprocity rules

A profile's behavior is expressed as one or more rules. Rules are a tagged union with four variants:

### 5.1 Threshold rule

Indicates a region within which no correction is applied.

- **noCorrectionRange** — a [time range](#7-reciprocity-time-range) describing the metered values for which the corrected time equals the metered time.
- **adjustments** — array of guidance-only adjustments outside the threshold band (informational; the calculation policy shall not interpret them as quantified rules).
- **notes** — array of free-form notes.

Example: `Kodak PORTRA 400` reports no correction below ~1 s; beyond, manufacturer guidance is "test under your conditions" (advisory, not quantified).

### 5.2 Formula rule

Indicates a closed-form correction.

- **meteredRange** — optional [time range](#7-reciprocity-time-range) constraining the formula's domain. Open-ended `meteredRange` shall mean "applies wherever the calculation policy reaches the formula step".
- **formula** — the only defined formula form is the **exponent power** form: `T_c = T_m^P` with optional coefficient and offset (`T_c = coefficient × T_m^exponent + offsetSeconds`). The structure shall include the source's published equation string for transparency.
- **additionalAdjustments** — array of supplementary adjustments (e.g. development-time hints) that the calculation does not consume.
- **notes** — array of free-form notes.

Example: `ILFORD HP5 Plus` uses `T_c = T_m^1.31` for `T_m > 1 s`.

### 5.3 Table rule

Indicates a discrete set of metered → corrected sample points.

- **entries** — non-empty array of entries, each with:
  - **meteredExposure** — a [metered exposure selector](#8-metered-exposure-selector) (an exact seconds value or a range).
  - **adjustments** — non-empty array of [exposure adjustments](#9-exposure-adjustment) describing the correction at that point.
  - **notes** — array of free-form notes attached to that table row.

Adjustments at a single entry shall not mix estimation families: a row shall use either `correctedTime`-style adjustments or `stopDelta`/`multiplier`-style adjustments, not both. ([Calculator Spec](Calculator.md) §3.3)

Example: `Kodak TRI-X 400` table: 1 s → +1 stop (corrected 2 s, dev −10%); 10 s → +2 stops (corrected 50 s, dev −20%); 100 s → +3 stops (corrected 1200 s, dev −30%).

### 5.4 Advisory rule

Indicates a region with non-quantified guidance only.

- **range** — a [time range](#7-reciprocity-time-range) the advisory applies to.
- **severity** — one of `caution`, `not_recommended`. `not_recommended` is a stop signal (see [Calculator Spec](Calculator.md) §3.2 step 3).
- **guidanceText** — non-empty string carrying the manufacturer's advisory wording.

Example: `Fujifilm Velvia 50` carries a `not_recommended` advisory at 64 s.

---

## 6. Calculation result (persisted)

When the calculation policy produces a result, the result is part of the domain because it can be round-tripped through persistence. ([Calculator Spec](Calculator.md) §3.5)

A result is one of three mutually exclusive forms:

- **Quantified** — a corrected exposure was produced. Carries the metadata block (see below) plus a `correctedExposure` payload (a reciprocity time value in seconds).
- **Advisory-only** — guidance is available but no quantified time. Carries the metadata block; no `correctedExposure` field.
- **Unsupported** — guidance is not available for this metered point. Carries the metadata block; no `correctedExposure` field.

The metadata block carried by every form contains:

- **calculationBasis** — one of: `exact_table_point`, `interpolated_within_table`, `extrapolated_beyond_table`, `official_threshold_no_correction`, `advisory_only_beyond_official_range`, `unsupported_out_of_policy_range`, `formula_derived`.
- **sourceAuthorityImpact** — derived from the profile's provenance.
- **rangeStatus** — `within_table`, `extrapolated`, `threshold_only`, `beyond_guidance`.
- **warningLevel** — `none`, `caution`, `advisory`, `not_recommended`.
- **supportingNotes** — array of human-readable strings.
- **usedReferencePoints** — array of references to the rows or formula coefficients that informed the result.

The presence of `correctedExposure` is determined structurally by the form (Quantified vs Advisory-only/Unsupported); a result whose form claims a corrected exposure but lacks the payload (or vice versa) is by construction unrepresentable.

---

## 7. Reciprocity time range

A range bounds metered exposure values:

- **minimumSeconds** — non-negative finite number.
- **maximumSeconds** — non-negative finite number, or absent / null to indicate "no upper bound".

When `maximumSeconds` is present, it shall be `≥ minimumSeconds`. The boundary semantics (closed vs open) follow the natural reading: a metered value `t` is in the range iff `minimumSeconds ≤ t` and (`maximumSeconds` is absent or `t ≤ maximumSeconds`).

---

## 8. Metered exposure selector

Used inside table rule entries to identify which metered values a row applies to. A tagged union with two variants:

- **exact** — a single non-negative finite seconds value. The row matches that value exactly.
- **range** — a [time range](#7-reciprocity-time-range). The row matches any metered value in the range.

A row's metered selector shall not overlap with another row's metered selector inside the same table rule.

---

## 9. Exposure adjustment

A tagged union describing how an entry corrects exposure. The variants are:

- **correctedTime** — `{ meteredSeconds?, correctedSeconds }`. `meteredSeconds` is optional context (the original metered point); `correctedSeconds` is the corrected exposure. Drives **log-log** estimation when interpolating between points.
- **stopDelta** — `{ stops }`. The correction is a positive number of stops to add. Drives **stop-space** estimation when interpolating.
- **multiplier** — `{ factor }`. The correction is a positive scalar multiplier on the metered time. Drives **stop-space** estimation when interpolating.

A single table row's adjustments shall use only one estimation family at a time. ([Calculator Spec](Calculator.md) §3.3)

---

## 10. Encoding (informative)

The current serialization is JSON with field names in `camelCase`. Tagged unions use a `kind` discriminator field; the variant payload sits in a sibling field whose name matches the variant. Example shapes:

```jsonc
// Reciprocity rule (variant: threshold)
{ "kind": "threshold", "threshold": { "noCorrectionRange": { ... }, ... } }

// Exposure adjustment (variant: correctedTime)
{ "kind": "correctedTime", "correctedTime": { "correctedSeconds": 2.0 } }
```

Field omission and explicit `null` shall be treated as equivalent on decode. The encoder shall omit absent optional fields rather than write `null`. The on-disk format may evolve; the spec body (§§1–9) is the contract, the encoding is not.

---

## 11. Catalog validation rules

A bundled launch catalog shall pass these checks before the runtime accepts it.

1. The film identity array is non-empty.
2. Every identity has a non-empty `id`, unique across the catalog.
3. Every identity has a non-empty `canonicalStockName`, unique across the catalog.
4. Every identity has `kind = "preset"`.
5. Every identity has `productionStatus = "current"`.
6. Every identity has exactly **one** profile.
7. Every profile's source has `kind = "manufacturer_published"`.
8. Every profile's source has `authority = "official"`.
9. Every profile has at least one rule, and every rule decodes to a known variant (no `unknown` `kind` values).

A catalog that fails any of these checks shall produce a clear decode diagnostic and shall not be loaded.

---

## 12. Launch dataset scope

The bundled launch catalog ships the **34-film launch-ready scope** (wiki 13172737, PTIMER-86 preset dataset policy outcome). Each shipped identity carries exactly one primary profile sourced from current official manufacturer documentation with `kind = "manufacturer_published"`, `authority = "official"`, and `confidence = "high"`. The validation matrix in wiki 15138817 specifies the seven scenarios that must be covered by validation samples (official formula, official table, color guidance, threshold-only advisory, archival official, user-defined, multi-profile support); the launch dataset itself is restricted to current official scope and excludes archival, user-defined, and multi-profile entries.

### 12.1 Launch-ready manufacturer breakdown

| Manufacturer       | Count | Method family            |
|--------------------|------:|--------------------------|
| ILFORD / HARMAN    |    12 | Exponent formula `Tc = Tm^P` |
| Kodak Still Film   |     9 | Table, threshold-only, advisory |
| Fujifilm           |     4 | Table with color-filter / stop-signal notes |
| FOMA BOHEMIA       |     3 | Multiplier table |
| Rollei             |     4 | Corrected-time table |
| ADOX               |     2 | Multiplier / stop-delta table |
| **Total**          |  **34** | |

ILFORD/HARMAN films share the exponent-formula method with film-specific exponents and a common no-correction threshold at ≤ 1 sec. Kodak black-and-white films (TRI-X 400, T-MAX 100, T-MAX 400) ship as quantified tables that may also carry development-time guidance; Kodak color-negative films (Ektar 100, Portra 160 / 400, Gold 200, Ultra Max 400) ship as official threshold-only profiles with advisory continuation beyond the stated range; Ektachrome E100 ships as a threshold profile with a 120 sec CC10R filtration advisory. Fujifilm reversal films preserve published color-filtration values per row and explicit stop-signal rows where the manufacturer marks an exposure "not recommended". FOMA, Rollei, and ADOX films use multiplier or corrected-time tables; where the source publishes a corrected exposure as a range (e.g. "1 to 2 sec"), the row is recorded with the source text in `notes` rather than synthesised into a single corrected value.

### 12.2 Excluded from the launch dataset

The following classes are intentionally outside the launch catalog (PTIMER-86 source-priority policy):

- Kodak Motion Picture Film (Vision3, Ektachrome 100D, Double-X) — still-photography-first scope.
- AgfaPhoto current films — current official reciprocity extraction is still pending.
- ORWO, Bergger, Film Ferrania — current product line confirmed but reciprocity extraction is too thin.
- Archival-only Agfa / AgfaPhoto / Kodak Ektachrome E100G–E100GX entries — kept out so archival data is not promoted as current shipping data.
- Any unofficial practical formula. In particular, the unofficial `T_c = T_m^1.34` Portra approximation is bundled outside the launch catalog (see §12.3) and shall not appear as the primary shipped Portra profile.
- Films from the launch-ready manufacturer groups that the source list still classifies as `NV` (Fomapan R100, Cine 100, Cine 400, Cine Ortho 400; Rollei RPX 25, RETRO 400S, INFRARED, ORTHO 25 plus, PAUL & REINHOLD, BLACKBIRD, CROSSBIRD, REDBIRD; ADOX HR-50, Scala 50).

### 12.3 Non-launch profiles bundled outside the catalog

### 12.4 Non-launch profiles bundled outside the catalog

The system may bundle additional **non-launch profiles** *outside* the launch catalog file, registered separately at runtime. These shall:

- follow the same domain shape (§§1–9) as launch profiles;
- carry honest provenance — for example, an unofficial practical formula must declare `kind = "community_field_tested"` (or equivalent) and `authority = "unofficial"`, not pretend to be official;
- be selectable by the user as a *secondary alternative* on a film identity that already has a launch (official) primary profile;
- not pass through the §11 launch-catalog validator (validation rules in §11 apply only to the launch catalog file).

Example: an unofficial practical formula `T_c = T_m^1.34` for Kodak PORTRA 400 is bundled outside the launch catalog as a secondary alternative to PORTRA 400's official threshold-only profile.

The presentation contract for these profiles lives in [UI Spec](UI.md) §2.1 (explicit "Official guidance" / "Unofficial practical" subtitles) and §2.6 (Authority row visible in details sheet for all profiles).

---

## 13. Forbidden patterns

The domain shall **not**:

1. Encode interpolation or extrapolation policy in any rule's data shape. Domain stores manufacturer points verbatim; calculation policy decides interpretation.
2. Synthesize provenance fields to fill gaps. Missing optional fields stay absent.
3. Mix repackaged-brand identities with original-manufacturer identities under one entry. Repackaging is a `brandLabel` annotation on the original identity, not a parallel record.
4. Allow a calculation result that claims a corrected exposure without carrying the value, or carries a corrected-exposure value without claiming one. The contradictory pairing is unrepresentable by the result's form.
5. Allow a single table row to mix estimation families *for the purpose of interpolation*. Interpolation reads exactly one estimation family per row: when both `correctedTime` and `stopDelta`/`multiplier` are recorded, calculation policy selects `correctedTime` and treats the others as supplementary annotations (development advisories, color-filter notes) rather than alternative estimation paths. A row that records only secondary annotations (e.g. `stopDelta` plus a development adjustment) keeps the stop-delta family. The forbidden case is *ambiguous interpolation* — two competing primary estimation families on the same row with no precedence rule. (Calculator Spec §3.3)
6. Allow a launch preset profile to carry user metadata.
7. Ignore catalog validation. A failing catalog is a load-time error, not a soft-warn.
8. Collapse multiple official profiles for one film into one record. (Wiki 15138817 reserves multi-profile support; in launch, only one profile is shipped per identity.)

---

## 14. Drift and open questions

- **User-defined film schema.** Wiki 15138817 lists user-defined films as a validation requirement; the entry/edit UX, validation rules, and persistence boundary are not specified.
- **Multi-profile support.** Reserved by domain (an identity may carry multiple profiles) but the selection mechanism (which profile is "active" at a given metered exposure, push/pull semantics, developer-time variants) is not specified.
- **Color correction metadata.** Velvia-style "M color correction" is mentioned in wiki 15138817 but has no schema entry. Currently captured (if at all) as free-form `notes`.
- **Development-time adjustments.** Development-time adjustment metadata (e.g. Tri-X-style "dev −10%" from wiki guidance) is not represented as a first-class schema field.
- **Next-wave catalog growth.** The bundled catalog covers the 34-film launch-ready scope; the next-wave candidates listed in PTIMER-86 (Kodak Motion Picture, NV-status films from the launch-ready manufacturer groups, deferred AgfaPhoto / ORWO / Bergger / Film Ferrania) have no prioritized work plan in spec form.
- **Repackaging links.** The schema accepts `brandLabel` and `aliases` but does not formalize a "this brand X is the same film as identity Y" link suitable for runtime equivalence checks.
- **Encoding versioning.** The encoding (JSON with `kind` discriminator) is informative-only in this spec, but no version field exists in the catalog. A future format change has no defined migration story.

---

## 15. Sources of intent (reference)

These are *reference material*, not normative.

**Wiki (Confluence pages cited by page id)**
- 13172737 — Reciprocity Film Research List (launch scope, method keys, provenance rules, repackaging policy)
- 15138817 — Reciprocity Validation Samples (minimum validation matrix, example profiles)
- 15237121 — Reciprocity Table Calculation Policy Notes (responsibility split, deferred items)
- 15761409 — Reciprocity Table Interpolation and Calculation Policy Draft (responsibility split, metadata, policy direction)

