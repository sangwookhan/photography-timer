# Domain Schema Spec

**Domain**: The data model behind film identities, reciprocity profiles, manufacturer rules, and the launch preset catalog.

This document specifies the **shape and meaning** of the domain — what fields exist, what they mean, what invariants hold. The encoding format (JSON, with a `kind` discriminator on union types) is a serialization detail recorded in §11; the spec body is platform- and serializer-neutral.

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
  - `custom` — user-defined identity authored by the photographer through the custom profile editor (see §13.4). The launch catalog never ships a `custom` identity; the runtime resolves custom identities from a separate user library.
  - `unknown` — present for forward-compatible decoding only; never written.
- **canonicalStockName** — non-empty, unique within the catalog. The display-default name for the film. Examples: `"Kodak TRI-X 400"`, `"ILFORD HP5 Plus"`.
- **manufacturer** — original manufacturer string when known. Repackaged brand labels (a film sold under different labels) shall not appear here; they go in `brandLabel`.
- **iso** — positive integer; the film's box-speed ISO. Required on every identity.
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
- **name** — non-empty string. Display label when surfacing the profile (e.g. "Official formula").
- **source** — provenance metadata (see §4).
- **rules** — array of [reciprocity rules](#5-reciprocity-rules) — at least one entry. The order matters only insofar as the calculation policy's evaluation order is defined separately ([Calculator Spec](Calculator.md) §3.2).
- **notes** — array of free-form note strings (rendered as supporting copy).
- **sourceEvidence** — optional array of [source-evidence rows](#33-source-evidence-rows). Display-only manufacturer reference points carried by formula profiles so users can verify a formula prediction against the published data. The calculation policy never consumes these rows; they cannot enter the calculation as anchors. Absent or empty for profiles without published reference points.

### 3.2 Optional fields

- **userMetadata** — user-editable fields parallel to §2.3, scoped to this profile. Absent for preset profiles.
- **selectorLabel** — optional short label for the **compact model selectors** (main-screen and Details segmented controls), where the full `name` would truncate. When present it is preferred; otherwise the UI derives a label from authority / calculation (e.g. "Official table", "App formula", "Official", "Unofficial"). Source-named unofficial / community / custom models (e.g. a future "Ohzart" practical table whose `name` is "Ohzart practical table") **should** set an explicit `selectorLabel` ("Ohzart") so the selector reads the source name. `selectorLabel` is **not** a source title or URL — those live in `source` (§4) and the Sources presentation. Absent for the shipping Fomapan / Portra models, which use derived labels.

### 3.3 Source-evidence rows

A profile may carry display-only manufacturer reference points alongside its calculation rules. Source-evidence rows let presentation surfaces show users where a formula prediction lines up against the published data without ever letting that data enter the calculation as an anchor.

Each row carries:

- **meteredExposure** — a [metered exposure selector](#9-metered-exposure-selector); the metered value the manufacturer published a reference for.
- **adjustments** — array of [exposure adjustments](#10-exposure-adjustment) describing the published reference (corrected time, stop delta, color-filter recommendation, etc.).
- **notes** — array of free-form notes.
- **isSourceEvidenceOnly** — optional boolean (default `false`). When `true`, the row is preserved as published evidence but the presentation layer omits it from formula-fitting markers and prefixes it with a footnote marker (`*`) so users can tell it is not a calculation anchor. Used by ADOX CMS 20 II's `1/1000 s +1/2 stop` reference, where the manufacturer publishes a sub-1s point but the calculation path stays no-correction across the whole sub-1s band.

Source-evidence rows shall never be promoted to calculation rules. The calculation policy is intentionally unaware of this array.

---

## 4. Source provenance

Every reciprocity profile carries provenance:

- **kind** — one of `manufacturerPublished`, `manufacturerArchive` (a manufacturer's own archived / superseded documentation), `thirdPartyPublication` (a non-manufacturer publication such as a community-tested practical formula), `userDefined`, `unknown`. The launch dataset shall use only `manufacturerPublished`. User-defined custom profiles (§13.4) use `userDefined`.
- **authority** — one of `official`, `unofficial`, `userDefined`, `unknown`. The launch dataset shall use only `official`. Supplementary non-launch profiles (§13.3) use `unofficial`. User-defined custom profiles (§13.4) use `userDefined` and shall not be presented as manufacturer authority.
- **confidence** — one of `high`, `medium`, `low`, `unknown`. The default for omitted is `unknown`. The launch dataset uses `high`.
- **publisher** — the entity that published the data, e.g. `"Kodak"`, `"Ilford Photo"`. Required non-empty string for launch (official) profiles. Supplementary unofficial profiles (§13.3) may leave this empty as the documented "source pending verification" marker; presentation suppresses the Sources section in that case and conveys the disclosure through the unofficial-authority subtitle plus the profile's caveat note.
- **title** — optional string referring to a specific document or page.
- **citation** — optional string with a more precise reference (URL, page number).
- **sourceVersion** — optional string identifying the published edition or revision.

The provenance fields shall be preserved verbatim from the source. The system shall not synthesize provenance to fill gaps; missing optional fields shall stay absent. (Wiki 13172737)

---

## 5. Reciprocity rules

A profile's behavior is expressed as one or more rules. Rules are a tagged union with three variants:

### 5.1 Threshold rule

Indicates a region within which no correction is applied.

- **noCorrectionRange** — a [time range](#8-reciprocity-time-range) describing the metered values for which the corrected time equals the metered time.
- **adjustments** — array of guidance-only adjustments outside the threshold band (informational; the calculation policy shall not interpret them as quantified rules).
- **notes** — array of free-form notes.

Example: `Kodak PORTRA 400` reports no correction below ~1 s; beyond, manufacturer guidance is "test under your conditions" (limited-guidance rule, see §5.3).

### 5.2 Formula rule

Indicates a closed-form correction. The rule wraps a single shared `ReciprocityFormula` value that owns the formula math AND its no-correction / source-range guards — PTIMER-160 retired the companion threshold rule that formula profiles previously carried.

- **formula** — a `ReciprocityFormula` value (§5.2.1).
- **additionalAdjustments** — array of supplementary adjustments (e.g. development-time hints) that the calculation does not consume.
- **notes** — array of free-form notes.

Manufacturer reference points associated with a formula profile (e.g. Provia 100F's published `240 s +1/3 stop` row) live on the profile's `sourceEvidence` array (§3.1, §3.3), not as data on the formula rule itself.

Example: `ILFORD HP5 Plus` uses `T_c = T_m^1.31` for `T_m > 1 s`.

#### 5.2.1 ReciprocityFormula (shared guarded model)

The shared guarded reciprocity formula is the contract every formula profile uses — shipped catalog entries today, and the PTIMER-84 custom profile / PTIMER-159 verification UI / PTIMER-161 table-converted refit / PTIMER-162 next formula family work later.

Display form (Modified Schwarzschild family):

`T_c = a × (T_m / T_ref)^p + b`

- **formulaFamily** — required. A discriminator enum. PTIMER-160 ships exactly one case, `modifiedSchwarzschild`, with the display form above. PTIMER-162 will add the next family case alongside. Consumers must switch on this enum exhaustively (no default branch) so adding a future case surfaces as a compile error.
- **coefficientSeconds** (`a`, seconds) — scale coefficient. At `T_m = T_ref` the power term equals `a`; the corrected exposure there is `a + b`. Default `1`. `a` is NOT the corrected time when `b ≠ 0`.
- **referenceMeteredTimeSeconds** (`T_ref`, seconds) — reference metered time used to scale the input. Default `1 s` reduces the display form to the legacy power form `T_c = a × T_m^p + b`.
- **exponent** (`p`) — drives curve steepness. Required.
- **offsetSeconds** (`b`, seconds) — constant offset added after the power term. Default `0`.
- **noCorrectionThroughSeconds** — inclusive upper bound of the no-correction band. For `T_m ≤ noCorrectionThroughSeconds` the formula returns the identity (`T_c = T_m`). The value mirrors the manufacturer-published no-correction marker. An ε-encoded value (e.g. `0.999999` for Tri-X's open boundary at `1 s`, `119.999999` for Acros II's open boundary at `120 s`) signals the source's open-boundary semantic ("Tm strictly below X is no-correction; Tm at exactly X activates the formula"); the policy note renders that as `< X sec` while inclusive integers render as `≤ X sec`.
- **sourceRangeThroughSeconds** — optional. Inclusive upper bound of the source / fitting confidence range — typically the last quantified source-backed anchor. **It is a confidence boundary, not a calculation stop.** Inputs strictly above the boundary still compute a corrected exposure; the policy classifies them as `unsupportedOutOfPolicyRange` (beyond source range) and the presentation surfaces the value as a formula-derived continuation rather than manufacturer guidance. `nil` means the formula carries no published source boundary and every formula-domain input stays classified as within the stated range.

The formula's `evaluate(meteredExposureSeconds:)` returns one of five outcomes — `noCorrection`, `withinSourceRange(corrected)`, `beyondSourceRange(corrected)`, `invalidInput` (bad metered input), `invalidFormula` (parameter-contract violation), `formulaOutputUnusable` (non-finite / non-positive output), or `unsafeShorteningFormula` (output would shorten the exposure). The first three are normal evaluation paths; the last four are distinct failure modes the policy routes to different presentations so a user-defined custom formula never silently masquerades as "no correction needed".

### 5.3 Limited-guidance rule

Indicates a region where the manufacturer publishes only qualitative guidance — no quantified corrected exposure. The calculation result for this region is structurally non-quantified (§6).

- **appliesWhenMetered** — optional [time range](#8-reciprocity-time-range) restricting the region the rule covers. Open-ended means "everywhere the calculation policy reaches this step".
- **adjustments** — array of qualitative adjustments (color-filter recommendations, free-form notes). The calculation policy surfaces these as supporting guidance but does not derive a corrected exposure from them.
- **notes** — array of free-form notes.

Example: `Kodak Ektachrome E100` carries a limited-guidance rule above 10 s with a `CC10R` color-filter recommendation at 120 s. The result for any metered value in the region is non-quantified.

---

## 6. Calculation result (persisted)

When the calculation policy produces a result, the result is part of the domain because it can be round-tripped through persistence. ([Calculator Spec](Calculator.md) §3.3)

A result is one of three mutually exclusive forms:

- **Quantified** — a corrected exposure was produced. Carries the metadata block (see below) plus a `correctedExposure` payload (a reciprocity time value in seconds).
- **Limited-guidance** — the manufacturer publishes only qualitative guidance for this region; no corrected exposure is produced. Carries the metadata block; no `correctedExposure` field.
- **Unsupported** — the metered exposure is outside the profile's supported range. Carries the metadata block; an optional `correctedExposure` field is present only when a formula- or table-backed profile produced a numeric continuation outside the supported range, in which case the presenter marks the value as outside manufacturer guidance.

The metadata block carried by every form contains:

- **calculationBasis** — one of: `officialThresholdNoCorrection`, `formulaDerived`, `limitedGuidanceNoQuantifiedPrediction`, `unsupportedOutOfPolicyRange`.
- **sourceAuthorityImpact** — derived from the profile's provenance.
- **rangeStatus** — `withinStatedRange`, `beyondLastRepresentativePoint`, `beyondPolicyLimit`.
- **warningLevel** — `none`, `note`, `caution`, `strongWarning`.
- **notes** — array of token-tagged human-readable strings.

The presence of `correctedExposure` is determined structurally by the form (Quantified vs Limited-guidance vs Unsupported); a result whose form claims a corrected exposure but lacks the payload (or vice versa) is by construction unrepresentable.

---

## 7. Calculator working context (persisted)

The calculator's working context — the inputs the user has set on the calculator screen — is part of the domain because it is round-tripped through persistence to survive an app restart. ([Calculator Spec](Calculator.md) §5; [Requirements](../requirements/Requirements.md) FR-5.2)

A working-context snapshot carries:

- **filmId** — optional string identifying the selected film. Resolves against the catalog (§2). Absent ⇒ digital workflow.
- **baseShutterSeconds** — non-negative finite number; the committed Base Shutter value. Sanitized on restore against the active exposure scale's shutter ladder (§7.1).
- **ndStop** — optional non-negative integer in `[0, 30]`; a whole-stop ND value. Present whenever the persisted ND lies on a whole-stop boundary; absent when the persisted ND is fractional (§7.2).
- **ndStopThirds** — optional non-negative integer; the persisted ND value expressed as a count of one-third-stops (so `0 ⇒ 0 stops`, `1 ⇒ 1/3 stop`, `3 ⇒ 1 stop`, `4 ⇒ 1 1/3 stop`, …). Present when the persisted ND is fractional; may also be present (and equivalent to `ndStop × 3`) for whole-stop values written by a release that always emits the field.
- **exposureScaleMode** — optional string token identifying the active exposure scale (§7.3). Absent ⇒ the shipping one-third-stop scale.
- **activeCameraSlotIDRaw** — optional string carrying the raw identifier of the camera slot whose calculator state this snapshot describes. Forward-compatibility annotation only: present so an older release that only reads this single-context shape can still recover the right slot association when the multi-slot session snapshot (§7.4) is unavailable. Absent ⇒ default-slot association. The active source of truth for slot session state is §7.4; the context snapshot's annotation is a fallback.

### 7.1 Schema evolution and backward compatibility

The snapshot shape evolves only via backward-compatible additions ([Requirements](../requirements/Requirements.md) NFR-S.2). Older snapshots that predate `ndStopThirds` or `exposureScaleMode` shall continue to restore correctly:

- A snapshot without `ndStopThirds` shall fall back to `ndStop` for the persisted ND value, treating it as a whole-stop count on the active scale's ND ladder.
- A snapshot without `exposureScaleMode` shall fall back to the **shipping one-third-stop scale**. The shipping shutter ladder is a strict superset of the legacy full-stop ladder, so a legacy whole-stop shutter value remains a valid ladder entry without rewriting it.
- A snapshot whose `exposureScaleMode` is present but unrecognized shall fall back to the shipping one-third-stop scale rather than fail to decode.

### 7.2 Fractional ND identity (reserved)

The persistence layer represents fractional ND through `ndStopThirds` (an integer count of one-third-stops) rather than persisting the ND value as a `Double`. This is **reserved domain infrastructure**: the shipping ND picker enumerates whole stops only ([Calculator Spec](Calculator.md) §2.2), so a steady-state shipping snapshot does not write `ndStopThirds`. The field exists so a future custom / variable-ND workflow can persist fractional ND with integer identity rather than `Double` drift; the decoder shall prefer `ndStopThirds` over `ndStop` when both are present, treating `ndStop` as a legacy hint.

### 7.3 Exposure scale token

`exposureScaleMode` is a string token enumerating the active exposure scale. The launch tokens are `"oneThirdStop"` (the shipping default) and `"fullStop"` (reserved for the future Settings preference described in [Calculator Spec](Calculator.md) §1.4). Other tokens are reserved.

### 7.4 Camera slot session snapshot

A shooting session may carry multiple camera slots ([Requirements](../requirements/Requirements.md) §3.8; [Calculator Spec](Calculator.md) §1.5). The slot-session snapshot captures every slot's calculator state plus the active-slot id so a relaunch restores the full session, not just the active slot.

A slot-session snapshot carries:

- **schemaVersion** — non-negative integer identifying the on-disk format. The current shipping value is `1`. The decoder rejects unknown schema versions and falls back to the legacy single-context restore path (§7) so a snapshot written by a future format the current release does not understand cannot poison the session.
- **activeSlotID** — string carrying the raw identifier of the slot that was active at save time. The runtime resolves it through the same slot-id alphabet used elsewhere (`camera1` … `camera4` in the current release, [Calculator Spec](Calculator.md) §1.5); an unrecognised value falls back to the canonical first slot rather than failing the load.
- **slots** — array of per-slot snapshots, one entry per slot the user has visited (and optionally entries for slots whose only state is a custom label, see below). Order on disk is sorted by slot id for determinism; the runtime does not depend on order.

Each per-slot snapshot carries:

- **slotIDRaw** — string identifier matching the slot's stable id alphabet. Unknown ids are silently skipped on decode; persistence does not pretend a slot exists that the runtime cannot resolve.
- **selectedPresetFilmID** — optional string; the catalog id of the slot's selected film, if any. Resolved against the catalog (§2); an id that no longer matches any catalog entry restores as **No film** (digital workflow) rather than crashing or fabricating a film identity.
- **selectedProfileID** — optional string; the id of an active reciprocity profile override on the selected film. Resolved against the film's profile array (and the bundled non-launch profile registry, §13.3). An id that no longer resolves drops the override silently and the slot restores to the film's primary profile.
- **baseShutterSeconds** — optional non-negative finite number; the slot's committed Base Shutter value. Sanitized on restore against the active exposure scale's shutter ladder; an absent or invalid value restores to the shipping default Base Shutter.
- **ndStop** / **ndStopThirds** — same convention and precedence as §7 / §7.2 for the calculator working context: the fractional-aware `ndStopThirds` field is preferred when present, with `ndStop` treated as a legacy hint.
- **exposureScaleMode** — optional string token following the same convention as §7.3; absent ⇒ shipping one-third-stop scale.
- **customDisplayName** — optional photographer-supplied display label for the slot. Trimmed at write time; an empty / whitespace-only value persists as absent so the restored slot falls back to its canonical *Camera N* default. Renaming a slot changes only this field; the slot's stable id and per-slot calculator inputs are not affected.
- **targetShutterSeconds** — optional positive finite number; the slot's committed Target Shutter duration ([Calculator Spec](Calculator.md) §3.6). An absent, non-finite, zero, or negative persisted value restores as no target on the slot. Per-slot target persistence shall not be seeded from session-global last-used target memory; doing so would surface one slot's value on another slot.

#### 7.4.1 Migration from the legacy single-context snapshot

The slot session snapshot (§7.4) is the source of truth on restore. The legacy single-context snapshot (§7) is read once at first launch after upgrade as a migration source so a session that predates the multi-slot schema does not reset:

- When no slot session snapshot exists, the runtime restores from the legacy single-context snapshot. Its `activeCameraSlotIDRaw` annotation, when present, names the slot the legacy values belong to; absent ⇒ the canonical default slot.
- The first save after the migration writes a slot session snapshot. Subsequent launches read the new snapshot and ignore the legacy single-context store for slot-session purposes.
- If the slot session store contains a snapshot whose `schemaVersion` the current release does not recognise, the load returns nothing and the runtime falls back to the legacy migration path; the next save re-writes the snapshot under the current schema.

#### 7.4.2 Schema evolution

The slot-session snapshot evolves only via backward-compatible additions ([Requirements](../requirements/Requirements.md) NFR-S.2). Adding an Optional field — for example the `customDisplayName` or `targetShutterSeconds` fields above — is permitted without bumping `schemaVersion`; an older snapshot that lacks the field decodes unchanged, with the field treated as absent. A breaking change (renaming an existing field, dropping a required field, or changing the meaning of an existing field) is not permitted without a coordinated `schemaVersion` increment and a documented migration step.

---

## 8. Reciprocity time range

A range bounds metered exposure values:

- **minimumSeconds** — non-negative finite number.
- **maximumSeconds** — non-negative finite number, or absent / null to indicate "no upper bound".

When `maximumSeconds` is present, it shall be `≥ minimumSeconds`. The boundary semantics (closed vs open) follow the natural reading: a metered value `t` is in the range iff `minimumSeconds ≤ t` and (`maximumSeconds` is absent or `t ≤ maximumSeconds`).

---

## 9. Metered exposure selector

Used inside source-evidence rows (§3.3) and limited-guidance rules (§5.3) to identify which metered values an entry applies to. A tagged union with two variants:

- **exact** — a single non-negative finite seconds value. The entry matches that value exactly.
- **range** — a [time range](#8-reciprocity-time-range). The entry matches any metered value in the range.

---

## 10. Exposure adjustment

A tagged union describing a single piece of guidance attached to a rule's `adjustments` array or a source-evidence row's `adjustments` array. The variants are:

- **correctedTime** — `{ meteredSeconds?, correctedSeconds, isApproximate? }`. `meteredSeconds` is optional context (the original metered point); `correctedSeconds` is the corrected exposure. `isApproximate` (default `false`) marks values the catalog stores as a rounded display of an irrational conversion — typically a corrected time derived from a fractional `stopDelta` (`metered × 2^stopDelta`) on a row whose source published only the stop delta. Multiplier-derived corrected times (`metered × multiplier`) are exact arithmetic and are not marked, even though they are similarly catalog-derived. The presentation layer surfaces approximate values distinctly (for example with a leading "≈") so users can tell published or exactly-converted anchors from rounded ones at a glance.
- **stopDelta** — `{ stops }`. The published correction is a number of stops to add at the row's metered point.
- **multiplier** — `{ factor }`. The published correction is a scalar multiplier on the metered time at the row's metered point.
- **colorFilter** — `{ filterName, note? }`. A color-correction filter recommendation (e.g. `5M`, `CC10R`).
- **development** — `{ instruction, note? }`. A development-time adjustment hint (e.g. `-10% development`).
- **warning** — `{ severity, message }`. `severity` is one of `caution` or `notRecommended`. `notRecommended` on a formula's source-evidence row marks the manufacturer's stop-signal boundary. The calculation policy itself reads the source/fitting confidence boundary from the formula's `sourceRangeThroughSeconds`; the warning row is preserved as published-evidence display data and does NOT act as a corrected-time anchor (e.g. CMS 20 II's 100 s "Not recommended" row sits above the 10 s `sourceRangeThroughSeconds`).
- **note** — `{ text }`. Free-form supplementary guidance.

Exposure adjustments are display-only data attached to threshold / limited-guidance rules and source-evidence rows. The calculation policy reads no quantified prediction from them; corrected exposure values come from the threshold (identity) or formula (closed-form) rules only.

---

## 11. Encoding (informative)

The current serialization is JSON with field names in `camelCase`. Tagged unions use a `kind` discriminator field; the variant payload sits in a sibling field whose name matches the variant. Example shapes:

```jsonc
// Reciprocity rule (variant: threshold)
{ "kind": "threshold", "threshold": { "noCorrectionRange": { ... }, ... } }

// Exposure adjustment (variant: correctedTime)
{ "kind": "correctedTime", "correctedTime": { "correctedSeconds": 2.0 } }
```

Field omission and explicit `null` shall be treated as equivalent on decode. The encoder shall omit absent optional fields rather than write `null`. The on-disk format may evolve; the spec body (§§1–10) is the contract, the encoding is not.

The current `kind` discriminator values are: `threshold`, `formula`, `limitedGuidance` on reciprocity rules; `correctedTime`, `stopDelta`, `multiplier`, `colorFilter`, `development`, `warning`, `note` on exposure adjustments; `exactSeconds`, `range` on metered exposure selectors.

---

## 12. Catalog validation rules

A bundled launch catalog shall pass these checks before the runtime accepts it.

1. The film identity array is non-empty.
2. Every identity has a non-empty `id`, unique across the catalog.
3. Every identity has a non-empty `canonicalStockName`, unique across the catalog.
4. Every identity has `kind = "preset"`.
5. Every identity has `productionStatus = "current"`.
6. Every identity has a positive `iso` (box-speed ISO).
7. Every identity has exactly **one** profile.
8. Every profile's source has `kind = "manufacturerPublished"`.
9. Every profile's source has `authority = "official"`.
10. Every profile has at least one rule, and every rule decodes to a known variant (no `unknown` `kind` values).
11. Every profile matches one of the three allowed launch shapes (§13): (a) a formula rule alone (the formula owns its no-correction guard; no companion threshold), with optional `sourceEvidence`; (b) a `tableInterpolation` rule alone (it owns its own no-correction band and source range), with optional `sourceEvidence`; or (c) a threshold rule plus a limited-guidance rule with no formula/table rule and an empty `sourceEvidence` array. A bare threshold rule or any other combination is rejected; the reserved `tableLookup` calculation model is rejected at load.

A catalog that fails any of these checks shall produce a clear decode diagnostic and shall not be loaded.

---

## 13. Launch dataset scope

The bundled launch catalog ships the **34-film launch-ready scope** (wiki 13172737, PTIMER-86 preset dataset policy outcome). Each shipped identity carries exactly one primary profile sourced from current official manufacturer documentation with `kind = "manufacturerPublished"`, `authority = "official"`, and `confidence = "high"`.

Every launch preset profile matches exactly one of three allowed shapes:

1. **Official quantified formula** — formula rule only (the shared `ReciprocityFormula` owns its no-correction and source-range guards; PTIMER-160 retired the companion threshold rule), with optional `sourceEvidence` rows preserving the manufacturer's published reference points. Calculation produces `officialThresholdNoCorrection` for `T_m ≤ noCorrectionThroughSeconds`, `formulaDerived` for inputs above that boundary up through `sourceRangeThroughSeconds`, and `unsupportedOutOfPolicyRange` (carrying a numeric continuation) for inputs above the source range.
2. **Official table log-log** (PTIMER-159) — a `tableInterpolation` rule that converts a manufacturer reciprocity *table* into a corrected exposure by piecewise log-log interpolation between published anchors, with `sourceEvidence` rows preserving those anchors. The rule owns its own no-correction band and source range. Calculation produces `officialThresholdNoCorrection` below the band, `tableLogLogDerived` within the published range, and `unsupportedOutOfPolicyRange` (carrying a numeric continuation, extrapolated from the last log-log segment) above the last anchor. Fomapan 100 Classic is the current launch profile of this shape; its app-derived power-law formula is preserved as a non-default alternate (§13.3).
3. **Official limited guidance** — threshold rule plus limited-guidance rule (§5.3) for the region above the threshold. Calculation produces `officialThresholdNoCorrection` inside the threshold band and `limitedGuidanceNoQuantifiedPrediction` above it; no quantified continuation.

Unofficial practical profiles (`authority = "unofficial"`) are bundled outside the launch catalog file and are documented in §13.3.

The only calculation table rule allowed on launch preset profiles is the **official table log-log** shape above (an explicit, anchored interpolation). A broad arbitrary table-interpolation engine is *not* implied; the reserved `tableLookup` calculation model remains unimplemented and is rejected at load.

### 13.1 Launch-ready manufacturer breakdown

| Manufacturer       | Count | Profile shape |
|--------------------|------:|---------------|
| ILFORD / HARMAN    |    12 | Formula (`Tc = Tm^p`) |
| Kodak Still Film   |     9 | Formula with `sourceEvidence` reference rows (B/W: Tri-X 400, T-MAX 100/400) or threshold + limited-guidance (color negatives, Ektachrome E100) |
| Fujifilm           |     4 | Formula with `sourceEvidence` reference rows |
| FOMA BOHEMIA       |     3 | Formula with `sourceEvidence` reference rows |
| Rollei             |     4 | Formula with `sourceEvidence` reference rows |
| ADOX               |     2 | Formula with `sourceEvidence` reference rows (CMS 20 II's 100 s "Not recommended" row is preserved as a published warning marker above the 10 s `sourceRangeThroughSeconds`) |
| **Total**          |  **34** | |

ILFORD/HARMAN films share the exponent-formula method with film-specific exponents and a common no-correction threshold at ≤ 1 sec. Kodak black-and-white films (TRI-X 400, T-MAX 100, T-MAX 400) ship as converted formula profiles whose `sourceEvidence` array preserves the published 1 / 10 / 100 sec reference rows for verification; Kodak color-negative films (Ektar 100, Portra 160 / 400, Gold 200, Ultra Max 400) ship as threshold + limited-guidance profiles — the manufacturer publishes only a no-correction range, with qualitative guidance ("test under your conditions") above it. Ektachrome E100 ships as a threshold + limited-guidance profile carrying a 120 sec CC10R color-filter recommendation as a `colorFilter` adjustment on its limited-guidance rule. Fujifilm, FOMA, Rollei, and ADOX films ship as converted formula profiles whose `sourceEvidence` array preserves the original manufacturer reference rows (with color-filter and corrected-time data attached) so users can see the formula curve passes through the published anchors.

### 13.2 Excluded from the launch dataset

The following classes are intentionally outside the launch catalog (PTIMER-86 source-priority policy):

- Kodak Motion Picture Film (Vision3, Ektachrome 100D, Double-X) — still-photography-first scope.
- AgfaPhoto current films — current official reciprocity extraction is still pending.
- ORWO, Bergger, Film Ferrania — current product line confirmed but reciprocity extraction is too thin.
- Archival-only Agfa / AgfaPhoto / Kodak Ektachrome E100G–E100GX entries — kept out so archival data is not promoted as current shipping data.
- Any unofficial practical formula. In particular, the unofficial `T_c = T_m^1.34` Portra approximation is bundled outside the launch catalog (see §13.3) and shall not appear as the primary shipped Portra profile.
- Films from the launch-ready manufacturer groups that the source list still classifies as `NV` (Fomapan R100, Cine 100, Cine 400, Cine Ortho 400; Rollei RPX 25, RETRO 400S, INFRARED, ORTHO 25 plus, PAUL & REINHOLD, BLACKBIRD, CROSSBIRD, REDBIRD; ADOX HR-50, Scala 50).

### 13.3 Non-launch profiles bundled outside the catalog

The system may bundle additional **non-launch profiles** *outside* the launch catalog file, registered separately at runtime. These shall:

- follow the same domain shape (§§1–10) as launch profiles;
- carry honest provenance — for example, an unofficial practical formula must declare `kind = "thirdPartyPublication"` and `authority = "unofficial"`, not pretend to be official;
- be selectable by the user as a *secondary alternative* on a film identity that already has a launch (official) primary profile;
- not pass through the §12 launch-catalog validator (validation rules in §12 apply only to the launch catalog file).

Example: an unofficial practical formula `T_c = T_m^1.34` for Kodak PORTRA 400 is bundled outside the launch catalog as a secondary alternative to PORTRA 400's official threshold + limited-guidance profile.

The presentation contract for these profiles lives in [UI Spec](UI.md) §2.1 (explicit "Official guidance" / "Unofficial practical" subtitles) and §2.6 (Authority subtitle visible in details sheet for all profiles).

### 13.4 User-defined custom profiles

User-defined custom profiles are reciprocity profiles the photographer authors through the custom profile editor ([UI Spec](UI.md) §4.2). They are first-class shooting data:

- The film identity uses `kind = "custom"` (§2.1) and is created, edited, deleted, and reused by the photographer from the film picker (selector treatment in [UI Spec](UI.md) §4.1.1; editor surface in [UI Spec](UI.md) §4.2). Custom identities are persisted in a separate user library and survive an app restart.
- Each custom identity carries exactly one profile whose `source.kind = "userDefined"` and `source.authority = "userDefined"`. The profile carries exactly one calculation rule: either the **shared guarded reciprocity formula model** (§5.2.1) or a **table log-log interpolation rule** (§13 shape (b)) built from photographer-entered metered/corrected anchors. A saved profile never converts between the two calculation types; threshold-rule and limited-guidance-rule variants are not authored through the editor.
- Photographer-supplied source metadata — source kind (user-defined / personal-test / community reference / unknown), manufacturer / stock label, reference URL — is preserved verbatim. The runtime shall **never** treat user-supplied source metadata as manufacturer authority; presentation surfaces ([UI Spec](UI.md) §2.1, §2.6) keep the "Custom" subtitle and a dedicated metadata card so a user-defined profile cannot visually pose as a manufacturer-published row.
- The formula fields the photographer edits (§5.2.1) map to the editor vocabulary as `coefficientSeconds = Tc₀`, `referenceMeteredTimeSeconds = Tm₀`, `exponent = p`, `offsetSeconds = b`, `noCorrectionThroughSeconds = No correction`, `sourceRangeThroughSeconds = Source data`. The semantics — including `sourceRangeThroughSeconds` as a **source/confidence boundary, not a calculation cutoff** — are identical to a preset formula profile.
- For a custom **table** profile, the photographer-entered metered/corrected rows are the calculation anchors and live on the `tableInterpolation` rule itself. `noCorrectionThroughSeconds` is editable and must be positive, finite, and strictly below the first anchor's metered time (stricter than the domain contract's `≥ 0`, because the table evaluator feeds the no-correction knee into log-log interpolation). `sourceRangeThroughSeconds` is not edited directly: it is derived from the last anchor's metered time at save. The profile's `sourceEvidence` carries display-only copies of the same rows — regenerated from the editor rows on every save, never separately editable, and never read by calculation; if the two ever diverge, the rule anchors are authoritative.
- Custom profiles do not enter the §12 launch-catalog validator. They are validated at editor commit time against the same parameter contracts the shared formula model enforces.
- Timer and details surfaces preserve enough custom-profile identity for the photographer to tell that the result came from a user-defined profile after the original profile is selected, used, or even later deleted; the persisted identity blob includes a custom-profile summary alongside the standard timer metadata.

Fitted-formula generation from custom table anchors (point fitting), table-vs-fitted-formula model selection, stop-delta / multiplier row input, and remote sharing / sync / inventory management remain **future scope** — they are not part of the custom profile workflows described above.

---

## 14. Forbidden patterns

The domain shall **not**:

1. Reintroduce a broad, arbitrary table-interpolation engine. The only table calculation rule allowed is the **table log-log** shape (PTIMER-159, §13) with explicit anchors — published anchors for shipped profiles, photographer-entered anchors validated at editor commit for custom profiles (§13.4); the reserved `tableLookup` model remains out of scope.
2. Promote source-evidence rows (§3.3) into calculation anchors. The calculation policy reads only threshold, formula, table-interpolation, and limited-guidance rules; source-evidence is display-only reference data and is never read by calculation (table-model profiles — shipped or custom — carry their own anchors inside the `tableInterpolation` rule).
3. Synthesize provenance fields to fill gaps. Missing optional fields stay absent.
4. Mix repackaged-brand identities with original-manufacturer identities under one entry. Repackaging is a `brandLabel` annotation on the original identity, not a parallel record.
5. Allow a calculation result that claims a corrected exposure without carrying the value, or carries a corrected-exposure value without claiming one (with the single allowed exception of `unsupportedOutOfPolicyRange` carrying a formula- or table-derived numeric continuation outside the supported range, past the source-range boundary). The contradictory pairings are unrepresentable by the result's form.
6. Allow a launch preset profile to carry user metadata.
7. Ignore catalog validation. A failing catalog is a load-time error, not a soft-warn.
8. Collapse multiple official profiles for one film into one record. (Wiki 15138817 reserves multi-profile support; in launch, only one profile is shipped per identity.)
9. Surface `Exact`, `Estimated`, `Interpolated`, `Extrapolated`, or `Advisory` as primary user-facing status / badge wording on launch preset reciprocity presentation. Those terms encoded the legacy arbitrary-table model; the current vocabulary is `No correction` / `Formula-derived` / `Table-derived` / `Beyond source range` / `No quantified prediction` / `Outside guidance` ([Calculator Spec](Calculator.md) §3.5, [UI Spec](UI.md) §2.3).

---

## 15. Drift and open questions

- **Custom table fitting and model selection.** User-defined *formula* and *table* profiles are implemented (§13.4). Fitted-formula generation from custom table anchors and table-vs-fitted-formula model selection remain future scope; the fitting policy and selection persistence for those workflows are not specified.
- **Multi-profile support.** Reserved by domain (an identity may carry multiple profiles) but the selection mechanism (which profile is "active" at a given metered exposure, push/pull semantics, developer-time variants) is not specified.
- **Color correction metadata.** Velvia-style "M color correction" is captured via the `colorFilter` exposure adjustment (§10) on source-evidence rows. A first-class color-correction policy distinct from per-row annotations has no schema entry.
- **Development-time adjustments.** Development-time adjustment metadata (e.g. Tri-X-style "dev −10%" from wiki guidance) is captured via the `development` exposure adjustment (§10) on source-evidence rows; a first-class development-time policy is not modeled.
- **Next-wave catalog growth.** The bundled catalog covers the 34-film launch-ready scope; the next-wave candidates listed in PTIMER-86 (Kodak Motion Picture, NV-status films from the launch-ready manufacturer groups, deferred AgfaPhoto / ORWO / Bergger / Film Ferrania) have no prioritized work plan in spec form.
- **Repackaging links.** The schema accepts `brandLabel` and `aliases` but does not formalize a "this brand X is the same film as identity Y" link suitable for runtime equivalence checks.
- **Encoding versioning.** The encoding (JSON with `kind` discriminator) is informative-only in this spec, but no version field exists in the catalog. A future format change has no defined migration story.

---

## 16. Sources of intent (reference)

These are *reference material*, not normative.

**Wiki (Confluence pages cited by page id)**
- 13172737 — Reciprocity Film Research List (launch scope, method keys, provenance rules, repackaging policy)
- 15138817 — Reciprocity Validation Samples (minimum validation matrix, example profiles)
- 15237121 — Reciprocity Table Calculation Policy Notes (historical: documented the table-interpolation policy superseded by PTIMER-128 / PTIMER-140's formula-based prediction model)
- 15761409 — Reciprocity Table Interpolation and Calculation Policy Draft (historical: same status as 15237121)

