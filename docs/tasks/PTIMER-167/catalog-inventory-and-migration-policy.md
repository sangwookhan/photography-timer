# PTIMER-167 Catalog Inventory and Migration Policy

## Purpose

PTIMER-167 creates a catalog-wide inventory and migration policy before changing more reciprocity film data.

This task does not change shipped catalog values, refit formulas, add new sources, or migrate production behavior. It classifies the current launch catalog by source authority, source shape, current calculation model, and target migration group so follow-up tickets can make smaller, verifiable implementation changes.

## Inputs reviewed

Verified inputs:

- Pre-PTIMER-128 catalog: `LaunchPresetFilmCatalog_ori.json`
  - 34 films / 34 profiles
  - Old rule shapes: threshold, table, formula, advisory
- Current source snapshot: `ptimerv1-ios-0137.zip`
  - Current launch catalog: `ios/PTimer/Resources/LaunchPresetFilmCatalog.json`
  - Current alternate models: `ios/PTimer/Reciprocity/AlternateReciprocityModels.swift`
  - Current domain vocabulary includes source/calculation separation and `tableLogLogInterpolation`
- Confluence research pages under `Reciprocity Film Research List`
  - Manufacturer data pages
  - Source registry child pages
  - Dataset policy page
  - Candidate eligibility review page

Important correction from review:

- Ohzart Fomapan 100 is present in the current source.
- It is not stored in `LaunchPresetFilmCatalog.json`.
- It is implemented as an alternate model under Fomapan 100 Classic in `AlternateReciprocityModels.swift`.

## Classification policy

Source shape is decided from the source evidence.

Current calculation model is decided from the current source.

Target migration group is decided by source shape, not by the current formula implementation.

A profile currently using a formula rule is not automatically a manufacturer formula. If the manufacturer source is table-shaped, range-shaped, or limited-guidance-only, the profile must be classified by that source shape.

## Migration principles

- Keep true manufacturer formula profiles as formula profiles.
- Move official table-origin profiles back to source-table based default calculation.
- Preserve official source anchors as source data.
- Keep limited official guidance separate from quantified prediction.
- Route range rules, not-recommended boundaries, range-valued rows, and sparse/special source shapes to special-case handling.
- Treat app-derived fitted formulas as optional non-source candidate models.
- Do not mix community or unofficial data into official manufacturer profiles.
- Do not remove launch films from the film selector as part of table migration.

## PTIMER-168 policy

PTIMER-168 should use Option A: migrate straightforward official table-origin profiles first.

PTIMER-168 must not remove films from the film selector.

For selected official table-origin profiles, PTIMER-168 should replace current formula-default behavior with source-table based calculation, preferably table/log-log interpolation where valid.

The official source anchors remain the source of truth.

Existing fitted formula behavior must not remain the default manufacturer model for those table-origin profiles. If any fitted formula values remain useful for later comparison, preserve them in test fixtures for PTIMER-170 app-derived formula evaluation, not as production default behavior.

Shared formula infrastructure remains because it is still required for true manufacturer formula profiles, custom formulas, and approved app-derived formula candidates.

## Migration groups

### 1. Keep as manufacturer formula

These profiles are official manufacturer formula profiles and should not be migrated by PTIMER-168.

| Film/Profile | Source shape | Current model | Target group | Follow-up |
|---|---|---|---|---|
| ILFORD Pan F Plus | manufacturer formula | formula | keep formula | no migration |
| ILFORD FP4 Plus | manufacturer formula | formula | keep formula | no migration |
| ILFORD Delta 100 | manufacturer formula | formula | keep formula | no migration |
| ILFORD Delta 400 | manufacturer formula | formula | keep formula | no migration |
| ILFORD Delta 3200 | manufacturer formula | formula | keep formula | no migration |
| ILFORD HP5 Plus | manufacturer formula | formula | keep formula | no migration |
| ILFORD XP2 Super | manufacturer formula | formula | keep formula | no migration |
| ILFORD SFX 200 | manufacturer formula | formula | keep formula | no migration |
| ILFORD Ortho Plus | manufacturer formula | formula | keep formula | no migration |
| Kentmere 100 | manufacturer formula | formula | keep formula | no migration |
| Kentmere 200 | manufacturer formula | formula | keep formula | no migration |
| Kentmere 400 | manufacturer formula | formula | keep formula | no migration |

Follow-up note:

Current source has partial explicit `modelBasis` coverage. A later metadata consistency pass should make source/calculation basis explicit where useful, but PTIMER-167 does not perform that work.

### 2. PTIMER-168 primary target: straightforward official table-origin profiles

These profiles are the confirmed PTIMER-168 Option A target list.

| Film/Profile | Source shape | Current model | Target model | Follow-up | Reason |
|---|---|---|---|---|---|
| Kodak Tri-X 400 | official table | formula | table/log-log interpolation | PTIMER-168 | Source has 1s/10s/100s rows and development adjustments |
| Kodak T-MAX 100 | official table | formula | table/log-log interpolation | PTIMER-168 | Source has adjusted-time rows |
| Kodak T-MAX 400 | official table | formula | table/log-log interpolation | PTIMER-168 | Source has adjusted-time rows |
| Fomapan 200 Creative | official multiplier table | formula | table/log-log interpolation | PTIMER-168 | Source has 1s/10s/100s multiplier rows |
| Fomapan 400 Action | official multiplier table | formula | table/log-log interpolation | PTIMER-168 | Source has 1s/10s/100s multiplier rows |
| Rollei RPX 100 | official corrected-time table | formula | table/log-log interpolation | PTIMER-168 | Source has exact corrected-time rows |
| Rollei RPX 400 | official corrected-time table | formula | table/log-log interpolation | PTIMER-168 | Source has exact corrected-time rows |
| ADOX CHS 100 II | official quantified table | formula | table/log-log interpolation | PTIMER-168 | Source has quantified multiplier/corrected-time rows |

PTIMER-168 must preserve:

- same film identity
- same film selector presence
- official source anchors
- source/reference presentation

PTIMER-168 must replace:

- official default formula behavior for these table-origin profiles

PTIMER-168 must not remove:

- film entries
- source anchors
- shared formula infrastructure

### 3. Already handled representative multi-model case

Fomapan 100 Classic is the current source’s strongest representative multi-model case.

| Film/Profile | Source shape | Current model | Target group | Follow-up |
|---|---|---|---|---|
| Fomapan 100 Classic — Official FOMA table | official multiplier table | tableInterpolation | already table-based default | use as reference case |
| Fomapan 100 Classic — App-derived formula | app-derived from official FOMA table | alternate formula model | app-derived candidate/model | PTIMER-170 broader policy |
| Fomapan 100 Classic — Ohzart community table | unofficial practical/community table | alternate tableInterpolation | keep as unofficial alternate | PTIMER-171 identity verification |

Handling rule:

- Official FOMA source data remains official source evidence.
- Ohzart community data remains unofficial practical guidance.
- App-derived formula output is not source evidence.
- Fomapan 100 can be used immediately for multi-model identity verification.

### 4. PTIMER-169 target: special, range, and limited-guidance cases

These profiles should not be forced into the first PTIMER-168 batch.

| Film/Profile | Source shape | Current model | Target group | Follow-up | Reason |
|---|---|---|---|---|---|
| Fujifilm Acros II | published range rule | formula | range-rule guidance | PTIMER-169 | 120–1000s +1/2 stop is range guidance, not a continuous formula source |
| Fujifilm Velvia 50 | table + not-recommended boundary | formula | Fujifilm slide-film table/color guidance | PTIMER-169 before/with migration | Preserve 64s not-recommended boundary and color guidance |
| Fujifilm Velvia 100 | table + color guidance | formula | Fujifilm slide-film table/color guidance | PTIMER-169 with Velvia 50 | Handle together with Velvia 50 to keep slide-film table/color guidance policy consistent |
| Fujifilm Provia 100F | table + not-recommended boundary | formula | Fujifilm slide-film table/color guidance | PTIMER-169 before/with migration | Preserve 8min not-recommended boundary and color guidance |
| Rollei RETRO 80S | table with range-valued rows | formula | range-valued table policy | PTIMER-169 | Rows such as `1 to 2 sec` are not exact anchors |
| Rollei SUPERPAN 200 | table with range-valued rows | formula | range-valued table policy | PTIMER-169 | Rows such as `1 to 2 sec` are not exact anchors |
| ADOX CMS 20 II | sparse/special official anchors | formula | special source shape | PTIMER-169 | Includes unusual short-exposure correction and sparse anchors |

Fujifilm slide-film handling:

- Velvia 50, Velvia 100, and Provia 100F should be handled together.
- The policy should preserve table rows, color guidance, long no-correction ranges, and not-recommended boundaries consistently.

Rollei handling:

- Rollei RPX 100 and Rollei RPX 400 are PTIMER-168 targets.
- Rollei RETRO 80S and Rollei SUPERPAN 200 need PTIMER-169 range-valued row policy first.
- Rollei RETRO 400S is an unofficial practical candidate, not an official table migration target.

### 5. Keep as limited official guidance

These profiles should remain limited guidance and must not become fake quantified prediction profiles.

| Film/Profile | Source shape | Current model | Target group | Follow-up |
|---|---|---|---|---|
| Kodak Ektar 100 | limited official guidance | threshold+limitedGuidance | keep limited guidance | PTIMER-169 / no table migration |
| Kodak Portra 160 | limited official guidance | threshold+limitedGuidance | keep limited guidance | PTIMER-169 / no table migration |
| Kodak Portra 400 official | limited official guidance | threshold+limitedGuidance | keep limited guidance | PTIMER-169 / no table migration |
| Kodak Gold 200 | limited official guidance | threshold+limitedGuidance | keep limited guidance | PTIMER-169 / no table migration |
| Kodak Ultra Max 400 | limited official guidance | threshold+limitedGuidance | keep limited guidance | PTIMER-169 / no table migration |
| Kodak Ektachrome E100 | limited guidance + filtration note | threshold+limitedGuidance | keep limited guidance + note | PTIMER-169 |

Policy:

Limited guidance must remain visibly different from table-derived quantified prediction.

### 6. Unofficial practical and community material

Current-source implemented alternate models may be inventoried. Research-only community material should stay in an appendix/future-candidate list.

| Profile/source | Current source status | Target group | Follow-up |
|---|---|---|---|
| Fomapan 100 Ohzart community table | implemented alternate model | keep as unofficial practical alternate | PTIMER-171 |
| Portra Flickr practical reference | wiki research only, not current source profile | appendix/future candidate | not PTIMER-168 |
| Rollei RETRO 400S Lafitte formula | wiki candidate, not current launch profile | appendix/future candidate | future practical-profile ticket |
| Community formula table page | wiki research only | appendix/future candidate | not current launch migration |

Policy:

Community data must not be mixed into official profiles.

Already implemented community alternates may be inventoried.

Research-only community sources stay in appendix/future candidate lists.

## Follow-up ticket target lists

### PTIMER-168 — official table-origin migration

Confirmed Option A target list:

- Kodak Tri-X 400
- Kodak T-MAX 100
- Kodak T-MAX 400
- Fomapan 200 Creative
- Fomapan 400 Action
- Rollei RPX 100
- Rollei RPX 400
- ADOX CHS 100 II

Required behavior:

- preserve film selector entries
- preserve official source anchors
- use table/log-log interpolation where valid
- remove formula-default behavior for these table-origin profiles
- do not remove shared formula infrastructure
- preserve useful fitted formula values only in test fixtures for PTIMER-170

### PTIMER-169 — range, limited guidance, and special source shapes

Target list:

- Fujifilm Acros II
- Fujifilm Velvia 50
- Fujifilm Velvia 100
- Fujifilm Provia 100F
- Rollei RETRO 80S
- Rollei SUPERPAN 200
- ADOX CMS 20 II
- Kodak Ektar 100
- Kodak Portra 160
- Kodak Portra 400 official
- Kodak Gold 200
- Kodak Ultra Max 400
- Kodak Ektachrome E100

Internal categories:

- limited guidance
- range-rule guidance
- not-recommended boundary
- range-valued table rows
- sparse/special official anchors
- Fujifilm slide-film table/color guidance

PTIMER-167 keeps PTIMER-169 as one ticket. Actual split, if any, should be decided when PTIMER-169 starts.

### PTIMER-170 — app-derived formula candidate evaluation

PTIMER-170 should evaluate app-derived formula candidates only after source data is preserved.

Primary candidates:

- Kodak Tri-X 400
- Kodak T-MAX 100
- Kodak T-MAX 400
- Fomapan 100 Classic app-derived official-table formula
- Fomapan 200 Creative
- Fomapan 400 Action
- Rollei RPX 100
- Rollei RPX 400
- ADOX CHS 100 II

Conditional candidates:

- Fujifilm Velvia 50
- Fujifilm Velvia 100
- Fujifilm Provia 100F
- Rollei RETRO 80S
- Rollei SUPERPAN 200
- ADOX CMS 20 II

Not candidates for official-derived formula fitting:

- Kodak Ektar 100
- Kodak Portra 160
- Kodak Portra 400 official
- Kodak Gold 200
- Kodak Ultra Max 400
- Kodak Ektachrome E100 official

Storage decision:

Existing fitted formula values removed from production default behavior should be preserved in test fixtures for PTIMER-170 evaluation, not in user-visible official default paths.

### PTIMER-171 — selected model identity in timers

Use Fomapan 100 Classic as the primary test case:

- Official FOMA table
- App-derived formula
- Ohzart community table

PTIMER-171 should verify selected model identity across:

- timer start metadata
- timer card identity
- timer detail
- restore after app relaunch
- duplicate/restart flows
- Live Activity/widget metadata where exposed

## Metadata consistency follow-up

Current source has partial explicit `modelBasis` coverage.

PTIMER-167 recommends a later metadata consistency pass to make source/calculation basis explicit and predictable across profiles, but this work should not be part of PTIMER-167.

## Documentation and Jira handling

PTIMER-167 should leave this repo document as the primary durable artifact.

Jira should receive a short summary comment only, covering:

- purpose
- inputs reviewed
- confirmed migration policy
- PTIMER-168/169/170/171 target lists
- explicit follow-up decisions

## Final decision summary

Resolved decisions:

- PTIMER-167 artifact: repo document.
- Jira: summary comment only.
- PTIMER-168 scope: Option A.
- PTIMER-168 must not remove films from the selector.
- PTIMER-168 replaces formula-default behavior with table/log-log interpolation for selected official table-origin profiles.
- Rollei RPX 100 and RPX 400: PTIMER-168.
- Rollei RETRO 80S and SUPERPAN 200: PTIMER-169 first.
- Velvia 50, Velvia 100, and Provia 100F: handle together as Fujifilm slide-film special handling in PTIMER-169.
- Existing fitted formulas removed from default behavior: preserve in test fixtures for PTIMER-170.
- PTIMER-169 remains one ticket for now.
- Metadata consistency pass: later follow-up.
- Community data scope: current-source inventory first, future candidates as appendix.
- Ohzart status: current source alternate model under Fomapan 100 Classic.

Final policy:

PTIMER-168 should preserve film identity and source evidence while replacing formula-default behavior for selected official table-origin profiles with table/source-anchor based calculation.

PTIMER-169 should handle source shapes that need explicit special-case policy, including the Fujifilm slide-film group.

PTIMER-170 should evaluate app-derived formulas only after source tables are preserved.

PTIMER-171 can use Fomapan 100 Classic as the primary multi-model timer identity test case.
