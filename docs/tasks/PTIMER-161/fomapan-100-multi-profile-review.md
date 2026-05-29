# PTIMER-161 — Fomapan 100 Classic multi-profile reciprocity review

## Metadata

- Ticket: `PTIMER-161` (review-only)
- Parent: `PTIMER-128` (formula-only migration → film-specific
  reciprocity model selection and verification)
- Predecessor: `PTIMER-163` (separated `sourceModel` from
  `calculationModel`)
- Successors:
  - `PTIMER-162` — broader formula/table evaluation methods
  - `PTIMER-159` — multi-profile Details/UI requirements
- Branch: `feature/PTIMER-128-fomapan-100-multi-profile-review`

> This document is decision support. It MUST NOT change shipped
> production behavior. The companion test file at
> `ios/PTimerTests/Reciprocity/Fomapan100ModelReviewTests.swift`
> pins the math used here so the comparison cannot silently drift.

---

## 1. Goal

Use Fomapan 100 Classic as the representative film stock to compare:

1. official FOMA BOHEMIA manufacturer table data,
2. community/blog practical table data,
3. app-derived formula candidates, and
4. UI/model requirements that flow into PTIMER-159.

Surface a recommendation for the Fomapan 100 default behavior and
record the follow-up requirements for PTIMER-162 and PTIMER-159.

---

## 2. Verified data sources

### 2.1 Official FOMA BOHEMIA table

Source material: FOMA BOHEMIA Fomapan 100 Classic technical sheet.
Also captured in:

- repository history of `LaunchPresetFilmCatalog.json` prior to
  PTIMER-128,
- `LaunchPresetFilmCatalog_ori.json` (frozen pre-migration source),
- Confluence page: _FOMA BOHEMIA Reciprocity Data_.

| Metered (sec) | Multiplier | Corrected (sec) |
| ------------- | ---------- | --------------- |
| 1/1000 … 1/2  | 1×         | no correction   |
| 1             | 2×         | 2               |
| 10            | 8×         | 80              |
| 100           | 16×        | 1600            |

Authority: `official` / `manufacturerPublished`.

### 2.2 Current app guarded formula (in-tree)

Catalog: `ios/PTimer/Resources/LaunchPresetFilmCatalog.json`,
profile `foma-fomapan-100-official-formula`.

- `modelBasis.sourceModel = manufacturerTable`
- `modelBasis.calculationModel = guardedFormula`
- formula family: `modifiedSchwarzschild`
- coefficient `a = 2.2457`, exponent `p = 1.4515`
- `noCorrectionThroughSeconds = 0.5`
- `sourceRangeThroughSeconds = 100.0`
- source evidence rows preserved for 1/10/100 sec

Expression: `Tc = 2.2457 × Tm^1.4515` (with `Tc = Tm` below 0.5 sec
and "beyond source range" semantics above 100 sec).

This is an app-derived free log-log fit through FOMA's three
published multiplier rows. It MUST NOT be presented as
manufacturer-published formula guidance.

### 2.3 Ohzart / community practical table

Source material: Confluence page _Communitity Sources Data_,
referencing the blog post at
`https://ohzart1.tistory.com/78`.

| Metered (sec) | Corrected (sec) |
| ------------- | --------------- |
| 1             | 1.9             |
| 2             | 5               |
| 4             | 13              |
| 8             | 35              |
| 15            | 90              |
| 30            | 265             |
| 60            | 795             |

Authority: `unofficial` / practical community guidance. Treat as a
candidate community table, not as FOMA-published data.

### 2.4 Community formula image

Same Confluence page, captured separately from the Ohzart table:

```
FOMAPAN 100:
Te = tm [ (log10 tm)^2 + 5(log10 tm) + 2 ]
with tm in seconds, tm max ≈ 100 sec
```

Authority: `unofficial` / community-derived formula. The image
notes a 100-sec upper bound on `tm`. The formula passes the three
official FOMA anchor rows exactly (see §3.2). The image and the
Ohzart table appear together but they are not the same model — see
§3.3.

---

## 3. Comparison findings

All numbers are pinned by `Fomapan100ModelReviewTests`. Calculations
are reproduced inline in this document for review legibility.

### 3.1 Current app formula vs official FOMA anchors

`Tc = 2.2457 × Tm^1.4515`

| Tm (sec) | Official Tc | App Tc       | Δ %     | Δ stop  |
| -------- | ----------- | ------------ | ------- | ------- |
| 1        | 2           | 2.2457       | +12.3%  | +0.167  |
| 10       | 80          | 63.5114      | −20.6%  | −0.333  |
| 100      | 1600        | 1796.1878    | +12.3%  | +0.167  |

The published FOMA rows do not lie on a single power law, so any
single log-log fit must split its residual across the three anchors.
The current fit accepts ~⅙ stop at 1 sec and 100 sec to cap the
worst-case error at the 10 sec row to ~⅓ stop. The published rows
remain visible as source evidence so a photographer can see where
the prediction deviates from FOMA's table.

### 3.2 Community formula vs official FOMA anchors

`Te = tm × ((log10 tm)² + 5 log10 tm + 2)`

| Tm (sec) | Official Tc | Community Te | Δ %    | Δ stop  |
| -------- | ----------- | ------------ | ------ | ------- |
| 1        | 2           | 2.000000     | 0.000% | 0.000   |
| 10       | 80          | 80.000000    | 0.000% | 0.000   |
| 100      | 1600        | 1600.000000  | 0.000% | 0.000   |

This is a log-quadratic multiplier model: at the three anchor
inputs the bracketed term collapses to the FOMA multipliers
`(0² + 0 + 2) = 2`, `(1² + 5 + 2) = 8`, `(2² + 10 + 2) = 16`.

That makes the community formula an exact pass through FOMA's
anchors — but it remains community-derived (it is published in a
community-sources image, not on the FOMA technical sheet) and the
image annotates a 100-sec upper bound for `tm`.

### 3.3 Community formula vs Ohzart practical table

| Tm (sec) | Ohzart | Community Te | Δ %    | Δ stop  |
| -------- | ------ | ------------ | ------ | ------- |
| 2        | 5      | 7.1915       | +43.8% | +0.524  |
| 4        | 13     | 21.4911      | +65.3% | +0.725  |
| 8        | 35     | 58.6482      | +67.6% | +0.745  |
| 15       | 90     | 138.9547     | +54.4% | +0.627  |
| 30       | 265    | 347.0248     | +31.0% | +0.389  |
| 60       | 795    | 843.1547     | +6.1%  | +0.085  |

The community formula image and the Ohzart table do NOT describe
the same correction curve. The community formula clears the
official 1/10/100 sec anchors and the Ohzart table sits roughly ⅓
to ¾ stop shorter than the community formula at every intermediate
point checked. They are two separate community-derived candidates;
treating them as a single model would silently bake the larger
Ohzart correction into the community formula's outputs (or vice
versa).

### 3.4 Current app formula vs Ohzart practical table

(For context — not a recommendation to replace either model.)

| Tm (sec) | Ohzart | App Tc       | Δ %    | Δ stop  |
| -------- | ------ | ------------ | ------ | ------- |
| 1        | 1.9    | 2.2457       | +18.2% | +0.241  |
| 2        | 5      | 6.1418       | +22.8% | +0.297  |
| 4        | 13     | 16.7974      | +29.2% | +0.370  |
| 8        | 35     | 45.9396      | +31.3% | +0.392  |
| 15       | 90     | 114.4058     | +27.1% | +0.346  |
| 30       | 265    | 312.8911     | +18.1% | +0.240  |
| 60       | 795    | 855.7330     | +7.6%  | +0.106  |

The app's anchor-fit formula and the Ohzart community table also
disagree — by ~¼ to ~⅖ stop across the relevant working range —
which is the expected outcome when one curve is fit to FOMA's
published anchors and the other reports darkroom-practical
behavior. This reinforces that the two are separate models.

---

## 4. Recommendation

For Fomapan 100 Classic:

1. **Default for the photographer remains the official FOMA
   source-anchor model.** PTIMER-161 must not change this. The
   current ship state already carries the official three multiplier
   rows as `sourceEvidence` and labels the profile as
   `sourceModel = manufacturerTable`.

2. **Keep the current app guarded formula classified as
   app-derived, not as manufacturer formula guidance.** The catalog
   already carries `calculationModel = guardedFormula` with a note
   describing the residuals. The formula's residual budget
   (~⅙ stop above the 1/100 anchors and ~⅓ stop below the 10 sec
   anchor) is acceptable for an anchor-fit predictor but must
   remain visible to the user as a derived approximation.

3. **Treat the Ohzart table as a separate unofficial practical
   candidate**, not as an upgrade path on the official model. It
   does not match the official anchors at 1/10/100 sec, so it
   cannot replace the official source without losing fidelity to
   FOMA's published data.

4. **Treat the community formula image as a separate
   community-derived formula candidate.** It passes the official
   1/10/100 sec anchors exactly, which makes it a useful comparison
   model, but its provenance is a community page and its image
   notes a 100-sec upper bound. It is not manufacturer-published
   guidance and is not the same model as the Ohzart table.

5. **Do not merge the Ohzart table with the community formula
   image.** §3.3 shows they diverge by roughly ⅓ to ¾ stop in the
   2–30 sec band. Any future UI that surfaces them must keep them
   visibly separate.

---

## 5. Follow-up requirements

### 5.1 PTIMER-162 — broader evaluation methods

PTIMER-162 should compare candidate calculation models in one
place, using Fomapan 100 as one representative dataset:

- direct table (no interpolation; lookup only at published rows),
- linear interpolation between published rows,
- log–log interpolation between published rows,
- guarded formula (current `modifiedSchwarzschild` family with
  `noCorrectionThroughSeconds` / `sourceRangeThroughSeconds`
  guards),
- log-quadratic multiplier style (the community formula in §2.4 is
  one instance of this style).

Constraints inherited from PTIMER-161:

- PTIMER-162 MUST NOT change shipped catalog constants unless a
  separate implementation ticket explicitly authorises it.
- PTIMER-162 MUST NOT enable `tableLookup` or interpolation as
  production calculation behavior. These remain reserved
  `calculationModel` values until a dedicated implementation
  ticket lands.
- The evaluation should report per-candidate residuals against
  both the official anchors and (where applicable) the unofficial
  Ohzart table, so the gap between official and community data
  stays visible.
- Log-quadratic / community formula candidates need the existing
  FOMA `noCorrectionThroughSeconds` guard at or below 0.5 sec: the
  raw community formula returns `Te < tm` below ≈ 0.619 sec, and
  its multiplier becomes negative below ≈ 0.364 sec. PTIMER-162
  candidate models inherit the existing guard / unsafe-shortening
  safety net rather than re-deriving it.

### 5.2 PTIMER-159 — multi-profile Details / UI

PTIMER-159 should make the Details / profile surface
multi-profile aware, with these invariants for Fomapan 100:

- The main film selector keeps a single Fomapan 100 entry. The
  user does not pick between "official" and "community" at the
  main selector; selection happens inside Details.
- Details / profile UI should allow more than one profile / model
  under the same film stock (e.g. "Official anchor fit",
  "Community Ohzart table", "Community log-quadratic formula"),
  driven by the catalog data model already in place after
  PTIMER-163.
- The Source Reference section MUST show source material only —
  for the official profile this is FOMA's three multiplier rows;
  for the community formula it is the formula image; for the
  Ohzart table it is the table rows. Derived predictions MUST NOT
  appear inside Source Reference.
- Derived formula output and its source-anchor error must be
  surfaced as a separate comparison block, distinct from Source
  Reference. The derived numbers must be visibly attributed to the
  app's fit, not to FOMA.
- Official and unofficial data MUST remain visibly separated — for
  example via section grouping, badge, or authority label — so a
  user cannot mistake an Ohzart / community result for FOMA
  guidance.

PTIMER-159 inherits the PTIMER-161 constraints: do not change
production calculation behavior, do not migrate the full FOMA
group, do not enable `tableLookup` / interpolation as production
calculation behavior.

---

## 6. Out of scope for PTIMER-161

- No production catalog behavior changes for Fomapan 100 or any
  other film.
- No migration of the wider FOMA group beyond the existing
  per-film formula profiles.
- No refit of launch profile coefficients.
- No enabling of `tableLookup` / interpolation as production
  calculation behavior. These remain reserved enum cases.
- No PTIMER-84 custom formula behavior changes.

---

## 7. Definition of Done

- Review document exists at this path with the comparison tables
  above.
- Companion test file
  `ios/PTimerTests/Reciprocity/Fomapan100ModelReviewTests.swift`
  pins the published table, the Ohzart table, the current app
  formula outputs, the residuals against official anchors, and the
  community formula's behavior at both the official anchors and
  the Ohzart intermediate points.
- Required checks (`git diff --check`, reciprocity test suite,
  `swiftlint`) recorded in the delivery report.
- No production source files changed.
