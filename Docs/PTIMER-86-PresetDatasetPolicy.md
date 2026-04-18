# PTIMER-86 Preset Reciprocity Dataset Policy

## Purpose

This document defines the initial preset reciprocity dataset scope for PTIMER
and the source-trust, conflict-resolution, attribution, and versioning policy
that should govern preset entries.

This is a dataset policy document, not a UI spec and not a schema redesign.

Related work:

* PTIMER-17 defines the shared reciprocity schema and provenance fields.
* PTIMER-89 defines the confidence-presentation contract that consumes
  calculation metadata rather than replacing provenance.
* PTIMER-90 defines table-based calculation policy and result-basis handling.
* PTIMER-87 collected the research inputs used to classify preset candidates.

## Policy anchors

This policy assumes the existing PTIMER-17 schema remains unchanged.

The implementation-facing expectations below map directly onto the existing
domain model:

* film identity remains represented by `FilmIdentity`
* preset and non-preset entries continue to share the same schema
* source provenance continues to use `ReciprocitySourceProvenance`
* source kind continues to use:
  `manufacturerPublished`, `manufacturerArchive`,
  `thirdPartyPublication`, `userDefined`
* authority continues to use:
  `official`, `unofficial`, `userDefined`
* source confidence continues to use:
  `high`, `medium`, `low`, `unknown`

This policy also assumes PTIMER-89 and PTIMER-90 remain the source of truth
for:

* source-authority impact on calculation metadata
* exact / interpolated / extrapolated / advisory-only result handling
* warning and confidence presentation behavior

PTIMER-86 only decides which source classes are eligible for preset shipping
data and how conflicting preset references should be handled.

## Launch policy summary

PTIMER should ship an initial preset reciprocity dataset using a conservative
default rule:

* include only current-production films with direct current official source
  support for reciprocity guidance
* allow both quantified profiles and official limited-guidance profiles
* exclude archival-only, unofficial-only, and unresolved-conflict entries from
  the first shipped preset set
* preserve deferred candidates in research/docs for later waves rather than
  forcing them into launch presets

This keeps the first preset dataset reviewable, attributable, and consistent
with PTIMER-89/PTIMER-90 authority distinctions.

## Launch-readiness checklist

A film should be treated as launch-ready for the first shipped preset dataset
only when all of the following are true:

* current-production status is confirmed
* a Level 1 current official source is confirmed for the shipping profile
* required PTIMER-17 provenance fields can be populated completely
* reciprocity guidance has been extracted into PTIMER-17 shape without schema
  workaround or guessed normalization
* no unresolved source conflict remains after applying the PTIMER-86 priority
  rules
* threshold-only, advisory-only, and stop-signal notes are preserved when they
  exist in the source

## Initial preset scope

### Must-include launch presets

These films are recommended for the first shipped preset dataset because they
meet all of the following conditions:

* current-production stock
* direct official manufacturer source confirmed
* reciprocity guidance already extracted with enough specificity to map into
  PTIMER-17 without schema workarounds
* no unresolved source-authority conflict that would block a reviewable preset

#### ILFORD / HARMAN

Launch all current confirmed official formula-based entries:

* Pan F Plus
* FP4 Plus
* Delta 100
* Delta 400
* Delta 3200
* HP5 Plus
* XP2 Super
* SFX 200
* Ortho Plus
* Kentmere 100
* Kentmere 200
* Kentmere 400

Reason:

* current official source
* consistent formula pattern
* strong launch coverage for black-and-white still film

#### Kodak still film

Launch all current confirmed official still-film entries already extracted in
the research:

* TRI-X 400
* T-MAX 100
* T-MAX 400
* EKTAR 100
* EKTACHROME E100
* PORTRA 160
* PORTRA 400
* GOLD 200
* ULTRA MAX 400

Reason:

* current official source
* includes both quantified table profiles and official limited-guidance cases
* gives the preset dataset good coverage of common Kodak still-film workflows

#### Fujifilm

Launch the current confirmed official still-film entries:

* Acros II
* Velvia 50
* Velvia 100
* Provia 100F

Reason:

* current official source
* strong representation of threshold, table, color-filter, and explicit
  stop-signal cases

#### FOMA BOHEMIA

Launch the current confirmed official quantified still-film entries:

* Fomapan 100 Classic
* Fomapan 200 Creative
* Fomapan 400 Action

Reason:

* current official source
* directly quantified data
* practical still-photography coverage without waiting for cine-line cleanup

#### Rollei

Launch the current confirmed official quantified entries:

* RPX 100
* RPX 400
* RETRO 80S
* SUPERPAN 200

Reason:

* current official source
* quantified table data already extracted
* clean fit for preset-first calculator integration

#### ADOX

Launch the current confirmed official quantified entries:

* CHS 100 II
* CMS 20 II

Reason:

* current official source
* already extracted into reviewable reciprocity form

### Good candidates for the next wave

These entries are still reasonable preset candidates, but they should not block
the first shipping preset set.

#### Current official but lower launch priority

* Vision3 50D
* Vision3 250D
* Vision3 200T
* EKTACHROME 100D
* Double-X

Reason:

* current official support exists
* the current guidance is limited and motion-film oriented
* the first launch preset scope is intentionally still-photography-first even
  where some motion-film sources are current official
* these are better treated as a follow-up expansion after still-film launch
  coverage is stable

#### Current official with extraction work still incomplete

* Vision3 500T
* Fomapan R100
* Fomapan Cine 100
* Fomapan Cine 400
* FOMA Cine Ortho 400
* RPX 25
* RETRO 400S
* INFRARED
* ORTHO 25 plus
* HR-50
* Scala 50

Reason:

* official source path is known or partially confirmed
* reciprocity extraction is still incomplete or not yet specific enough for a
  clean preset entry

### Deferred due to weak or ambiguous source quality

These stay in research scope, but should not ship as presets until the source
quality improves.

* AgfaPhoto APX 100
* AgfaPhoto APX 400
* AgfaPhoto Colour 400
* ORWO current lineup
* Bergger Pancro 400
* Film Ferrania P30
* Film Ferrania Orto
* Rollei PAUL & REINHOLD
* Rollei BLACKBIRD
* Rollei CROSSBIRD
* Rollei REDBIRD

Reason:

* current product presence may be confirmed
* direct official reciprocity extraction is still missing, weak, or ambiguous
* unofficial/community material may exist, but should not silently become
  shipping preset truth

### Excluded for now

These are intentionally excluded from the first preset dataset policy even
though the shared schema can represent them.

#### Legacy archival films

Examples:

* Agfapan APX 100
* Agfapan APX 400
* Agfa Scala 200x
* Agfacolor Optima line
* Agfachrome RSX II line
* EKTACHROME E100G / E100GX
* older Kodak, Fujifilm, ILFORD, and similar archive-only stocks

Reason:

* archival official data remains useful and reviewable
* however, launch presets should stay focused on current-production defaults
* legacy presets can be added later as an explicit expansion rather than
  silently mixed into the first shipping set

#### Unofficial-only or community-only entries

Examples:

* blog-derived practical tables
* forum field reports
* community spreadsheets
* user-defined/manual-research entries

Reason:

* these can support research and later custom/manual workflows
* they should not become launch shipping presets unless a future story
  explicitly approves provisional preset behavior

## Source-trust policy

### Source hierarchy

PTIMER should use the following preset-data source priority order.

#### Level 1: current official manufacturer documentation

Examples:

* current manufacturer technical sheet
* current official product PDF
* current manufacturer support page

PTIMER-17 mapping:

* `kind = manufacturerPublished`
* `authority = official`
* default launch confidence target: `high`

Preset policy:

* allowed for shipped launch presets
* preferred source class for all default preset entries

#### Level 2: archival official manufacturer documentation

Examples:

* archived technical sheet
* museum/archive-hosted original manufacturer publication
* older official PDF for discontinued stock

PTIMER-17 mapping:

* `kind = manufacturerArchive`
* `authority = official`
* default confidence target: `medium`

Preset policy:

* not allowed for the first launch preset set for current-production defaults
* allowed as documented follow-up material for legacy expansion stories
* may be stored later as explicit legacy presets if the product chooses to ship
  archival packs or legacy entries with stronger warning treatment

#### Level 3: trusted secondary published references

Examples:

* published technical article
* structured secondary reference that cites manufacturer material

PTIMER-17 mapping:

* `kind = thirdPartyPublication`
* `authority = unofficial`
* default confidence target: `medium` or `low`

Preset policy:

* not allowed as the sole basis for launch shipping presets
* may be used as supporting review material
* may coexist as a separate non-primary profile only in a later story that
  intentionally supports provisional presets

#### Level 4: community or field-report references

Examples:

* forum threads
* blog field reports
* local community posts

PTIMER-17 mapping:

* `kind = thirdPartyPublication`
* `authority = unofficial`
* confidence typically `low`

Preset policy:

* not allowed as shipping preset truth for launch
* useful only as supporting research, validation context, or future
  manual/custom guidance

#### Level 5: user-defined or manual research

PTIMER-17 mapping:

* `kind = userDefined`
* `authority = userDefined`

Preset policy:

* never part of shipped preset data
* reserved for custom/manual-entry follow-up stories

### Source rules for launch presets

For the first preset dataset, a film should ship only when:

* the primary shipping profile is based on Level 1 current official material
* the source is attributable enough to populate publisher, title/citation, and
  source version fields
* the guidance can be expressed without inventing data shape not present in the
  source
* no unresolved conflict remains inside the Level 1 source set

Official limited-guidance entries are allowed for launch presets if the source
explicitly provides a bounded no-correction range or advisory-only continuation
statement.

Examples:

* PORTRA 400 threshold-only no-correction guidance
* EKTAR 100 official range plus test-under-your-conditions note

That means launch presets may include:

* quantified official formula profiles
* quantified official table profiles
* official threshold-only profiles
* official advisory-only notes tied to a current official threshold profile

## Primary shipping profile rule

For the first preset dataset, PTIMER should ship one primary preset profile per
film identity.

That primary shipping profile should be:

* the highest-priority launch-eligible profile after applying the source
  hierarchy
* the single preset profile that later calculator integration and first-pass UI
  integration can rely on by default

For launch scope, lower-priority alternatives should remain out of the shipped
preset bundle, including:

* archival official alternatives
* unofficial secondary alternatives
* conflicting alternates that have not been fully resolved

The PTIMER-17 schema still allows multiple profiles on one film identity, but
multi-profile preset shipping is intentionally deferred to a later story so the
first preset launch does not force early multi-profile preset-selection logic.

## Conflict-resolution policy

### Primary rule

When sources disagree, PTIMER should prefer the highest-priority source class
and keep lower-priority material separate rather than blending them into a
single unreviewable preset entry.

### Resolution order

1. Prefer current official over archival official.
2. Prefer official over unofficial.
3. Prefer film-specific documentation over generic manufacturer-wide notes.
4. Prefer a source that directly states reciprocity guidance over a source that
   requires inference from charts, commentary, or guessed formulas.
5. Prefer preserved original data shape over transformed derived values.

### Practical conflict rules

#### Current official vs archival official

* current official wins for current-production presets
* archival official material may remain attached as research context, but it
  must not overwrite the current official shipping profile

#### Dedicated film sheet vs generic family or master note

* use the dedicated film sheet as the preset primary source
* keep generic master references only as supporting context

Example:

* a dedicated EKTACHROME E100 publication outranks a broader Kodak family or
  master reciprocity note when both exist

#### Official quantified data vs official limited guidance

* if the current official source only provides threshold-only or advisory-only
  guidance, PTIMER should preserve that limited guidance as-is
* PTIMER should not replace official limited guidance with secondary quantified
  guesses in the launch preset set

Example:

* PORTRA 400 should remain an official limited-guidance preset in launch scope,
  not a secretly promoted unofficial quantified preset

#### Official table vs unofficial formula guess

* preserve the official table as the primary preset truth
* do not collapse it into an unofficial fitted formula for shipping data

This stays aligned with PTIMER-17 and PTIMER-90, which preserve source shape
and keep policy interpretation separate from stored provenance.

#### Explicit source stop signal vs generic extrapolation

* explicit stop or not-recommended guidance must be preserved
* later calculation policy may still interpret table rows where allowed, but
  the preset entry must record the stop signal explicitly

Example:

* Velvia 50 `64 sec -> not recommended` must remain a stop signal and must not
  be erased by generic interpolation policy

### Unresolved conflicts

If disagreement remains between candidate shipping sources after applying the
priority rules above:

* do not include the film in the launch preset set
* move it to deferred status
* record the conflict reason in notes so the preset decision remains reviewable

PTIMER should prefer a smaller clean launch set over a larger ambiguous one.

### Multiple profiles on one film identity

The PTIMER-17 schema already allows multiple profiles on one film identity.
PTIMER-86 should use that capability only when it improves reviewability.

Launch rule:

* ship one primary preset profile per film identity in the first preset dataset
* lower-priority profiles must not silently replace the primary official one

For the first preset dataset, default behavior should be:

* ship only the primary current official profile
* keep unofficial or archival alternatives out of the launch preset bundle
  unless a future story explicitly approves them

## Attribution and versioning policy

### Required attribution fields per shipped preset profile

Every shipped preset profile must populate the PTIMER-17 provenance fields
clearly enough for later review:

* `source.kind`
* `source.authority`
* `source.confidence`
* `source.publisher`
* `source.title` or equivalent document label
* `source.citation`
* `source.sourceVersion` when the source exposes a version, publication code,
  revision marker, or date

Minimum review expectation:

* a reviewer should be able to identify which document or page the preset came
  from without redoing the full research pass

### Required note expectations

A shipped preset should carry notes when any of the following are true:

* the profile is threshold-only rather than quantified
* the official source explicitly says to test under user conditions
* the profile contains a manufacturer stop signal or not-recommended row
* the source required clarification between current naming and legacy naming
* the source quality is lower than current official
* a conflict was reviewed and resolved rather than absent

### Confidence expectations for shipped presets

PTIMER-86 should not redefine PTIMER-89 confidence presentation, but it should
set baseline provenance expectations:

* launch shipping presets should generally target `high` confidence only when
  they are current official and directly attributable
* archival official presets should default lower than current official when
  later shipped
* unofficial and user-defined profiles should not be silently labeled as
  equivalent to current official presets

### Versioning expectations

Preset entries should remain reviewable over time at two levels:

#### Per-profile source version

Use the existing `sourceVersion` field for:

* manufacturer publication code
* revision number
* issue date
* archive revision marker

#### Dataset revision

When preset data is later mapped into app code, the preset bundle should also
track a dataset revision outside the domain schema, such as:

* preset dataset version string
* updated-on date
* release-note summary of added, changed, or removed presets

This dataset-level revision should live in implementation/docs, not by
redesigning PTIMER-17.

### Reviewability rule

Any future preset update should be reviewable by answering:

* which film changed
* which source changed
* whether the source class changed
* whether the data shape changed
* whether the confidence expectation changed
* whether the change affects launch scope or only deferred candidates

## Implementation-facing recommendations

### Recommended launch dataset boundary

Treat the first preset dataset as:

* current-production
* still-photography first
* official-source first
* reviewable and bounded

That means the first shipping preset set should include:

* ILFORD / HARMAN current official formula films
* Kodak current official still films already extracted
* Fujifilm current official still films already extracted
* FOMA current official quantified still films already extracted
* Rollei current official quantified films already extracted
* ADOX current official quantified films already extracted

### Recommended non-launch boundary

Do not include in the first shipped preset set:

* motion-picture expansion entries
* archival legacy entries
* current films without extracted official reciprocity guidance
* unofficial-only quantified estimates
* user-defined/manual-research entries

### Canonical identity rule

Preset films should continue to follow the research-page manufacturer-first
grouping:

* map repackaged or alias branding back to the original stock identity when
  identifiable
* avoid duplicate presets for current-label and legacy-label ambiguity until
  canonical identity is clear

## Intentionally deferred

The following remain outside PTIMER-86:

* UI for choosing or presenting presets
* custom/manual-entry workflow design
* full app-code population of every preset
* motion-picture-specific preset UX
* archival legacy preset product strategy
* localization or final user-facing copy
* any PTIMER-89 or PTIMER-90 policy redesign
* any PTIMER-17 schema redesign

## Concise decision summary

### Proposed initial preset scope

Ship a bounded launch set of current-production, current-official, already
extracted still-film presets:

* ILFORD / HARMAN: 12 films
* Kodak still film: 9 films
* Fujifilm: 4 films
* FOMA BOHEMIA: 3 films
* Rollei: 4 films
* ADOX: 2 films

Total recommended launch presets: 34 film identities.

### Source-trust rules

* current official manufacturer material is the only allowed primary source for
  launch shipping presets
* archival official material is valid research and valid future legacy input,
  but not part of the first launch preset set
* trusted secondary and community sources may inform review, but do not define
  launch shipping presets
* user-defined data is never shipping preset data

### Conflict-resolution rules

* prefer current official over archival official
* prefer official over unofficial
* prefer dedicated film documents over generic family notes
* prefer preserved original source shape over derived guessed formulas
* defer launch inclusion when a conflict remains unresolved

### Attribution and versioning rules

* every shipped preset profile must retain PTIMER-17 provenance fields
* lower-authority or limited-guidance cases must carry explicit notes
* per-profile source version belongs in `sourceVersion`
* dataset revision should be tracked in implementation/docs alongside the
  future preset bundle, not by redesigning the schema
