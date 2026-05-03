# PTIMER-88 — Define Color-Correction Presentation Formatter for Reciprocity Guidance

Feature branch: `feature/PTIMER-14-color-correction-presentation`

Status: Implementation spec  
Scope type: Small implementation + formatter contract + tests  
Commit policy: Do not commit

## 1. Goal

Define and implement a presentation-layer formatter contract for reciprocity secondary guidance.

The formatter converts existing stored reciprocity guidance such as color-correction notation, development adjustment, warning notes, and ambiguous free-text guidance into display-ready presentation models.

The formatter must not change:

- reciprocity domain schema
- launch catalog schema
- calculation policy
- confidence presentation policy
- UI layout

Exposure-time output remains the primary calculator result. Color correction, development adjustment, and warning notes are secondary guidance.

## 2. Background

PTIMER already separates reciprocity responsibilities:

- PTIMER-17: reciprocity domain model
- PTIMER-89: confidence/result presentation
- PTIMER-90: reciprocity calculation policy
- PTIMER-103: expanded launch preset catalog

PTIMER-88 fills a narrower presentation gap: how secondary guidance stored in film data is presented to the user without normalizing or reinterpreting the original source notation.

Representative stored guidance includes:

- Fujifilm color-correction notation: `5M`, `7.5M`, `10M`, `12.5M`, `2.5G`
- Kodak color-correction notation: `CC10R`
- Development adjustment: `-10%`, `-20%`, `-30%`
- Stop/warning notes: `not recommended`
- Advisory/free-text notes: `test under your conditions`, `may require compensation and filtration`, `additional yellow / cyan correction`

## 3. Scope

### In scope

- Add a pure presentation-layer formatter.
- Define a small display model for secondary reciprocity guidance.
- Preserve original stored notation in display output.
- Separate guidance categories:
  - color correction
  - development adjustment
  - warning / stop-signal
  - generic note / ambiguous guidance
- Add focused unit tests for formatter behavior.
- Add minimal documentation only if there is a suitable existing docs/specs location.

### Out of scope

- Domain schema redesign.
- LaunchPresetFilmCatalog.json schema redesign.
- Calculation policy changes.
- Confidence presentation behavior changes.
- UI redesign.
- Timer behavior changes.
- Localization infrastructure.
- Numeric color science interpretation.
- Converting all filter notation into a canonical standard.
- Commit creation.

## 4. Design Principles

### 4.1 Presentation-layer only

The formatter is a presentation concern. It must not participate in exposure calculation, policy decisions, confidence mapping, or timer enablement.

Recommended file location:

```text
PTimer/ReciprocitySecondaryGuidancePresentation.swift
```

If the current project structure clearly keeps presentation contracts elsewhere, choose the nearest existing presentation-layer location. Do not implement this as an inline SwiftUI helper.

### 4.2 Preserve stored notation

The formatter must preserve the stored value exactly.

| Stored value | Display value |
|---|---|
| `5M` | `5M` |
| `7.5M` | `7.5M` |
| `2.5G` | `2.5G` |
| `CC10R` | `CC10R` |
| `-10%` | `-10%` |

Do not rewrite `7.5M` as `7½M`, `CC10R` as `10R`, or `5M` as `CC05M`.

### 4.3 Separate categories

Color correction, development adjustment, warning/stop-signal notes, and free-text notes must not be mixed.

Recommended model shape:

```swift
struct ReciprocitySecondaryGuidancePresentation: Equatable {
    enum Kind: Equatable {
        case colorCorrection
        case developmentAdjustment
        case warning
        case note
    }

    enum Severity: Equatable {
        case neutral
        case caution
        case stop
    }

    let kind: Kind
    let title: String
    let valueText: String?
    let detailText: String
    let severity: Severity
}
```

The exact names may be adjusted to match existing project style, but the category separation must remain explicit.

### 4.4 Keep PTIMER-89 separate

Do not move or duplicate PTIMER-89 confidence presentation responsibilities.

PTIMER-88 must not decide:

- exact / estimated / extrapolated
- advisory-only / unsupported
- official / unofficial confidence
- corrected exposure availability
- timer action enablement

PTIMER-88 only formats already-existing secondary guidance.

### 4.5 Avoid false precision

Free-text guidance must not be converted into numeric filter values or quantified correction.

Examples:

- `additional yellow / cyan correction` should remain free-text guidance.
- `may require compensation and filtration` should remain advisory guidance.
- `test under your conditions` should remain advisory guidance.

### 4.6 Treat stop signals as warnings

`not recommended` must not be displayed as color correction.

Expected category:

```text
kind: warning
severity: stop
```

## 5. Expected Implementation

### 5.1 Inspect first

Before editing, inspect:

```text
PTimer/ReciprocityDomain.swift
PTimer/ReciprocityCalculationPolicy.swift
PTimer/ReciprocityConfidencePresentation.swift
PTimer/ExposureCalculator/ExposureCalculatorViewModel.swift
PTimer/ExposureCalculator/LaunchPresetFilmCatalog.json
PTimerTests/ReciprocityConfidencePresentationTests.swift
PTimerTests/ReciprocityCalculationPolicyTests.swift
```

Also search for existing reciprocity details/presentation tests.

### 5.2 Add formatter

Add a pure Swift formatter that can accept guidance values already available from the catalog/domain layer.

The exact input shape should follow existing data structures. If the existing domain already distinguishes note types, use that. If existing data is plain text, keep the first implementation conservative and deterministic.

Possible API shape:

```swift
enum ReciprocitySecondaryGuidanceFormatter {
    static func format(_ guidance: [String]) -> [ReciprocitySecondaryGuidancePresentation]
}
```

or, if existing domain objects exist:

```swift
enum ReciprocitySecondaryGuidanceFormatter {
    static func format(_ guidance: ReciprocityGuidance) -> [ReciprocitySecondaryGuidancePresentation]
}
```

Prefer the API that minimizes changes outside the formatter.

### 5.3 Classification guidance

Suggested conservative classification rules:

- `not recommended` or equivalent stop phrase:
  - kind: `.warning`
  - severity: `.stop`
- percent development adjustment such as `-10%`, `-20%`, `-30%`:
  - kind: `.developmentAdjustment`
  - severity: `.neutral` or `.caution`
- color notation such as `5M`, `7.5M`, `10M`, `12.5M`, `2.5G`, `CC10R`:
  - kind: `.colorCorrection`
  - severity: `.neutral`
- ambiguous free text:
  - kind: `.note`
  - severity: `.caution` if advisory
  - preserve text without inventing valueText

Do not overbuild a large parser. This story is about a stable presentation contract, not full color science interpretation.

## 6. Tests

Add focused formatter tests.

Recommended file:

```text
PTimerTests/ReciprocitySecondaryGuidancePresentationTests.swift
```

Required test cases:

1. `5M` formats as color correction and preserves `5M`.
2. `7.5M` preserves decimal notation exactly.
3. `2.5G` preserves green notation exactly.
4. `CC10R` preserves Kodak CC notation exactly.
5. `-10%` formats as development adjustment, not color correction.
6. `not recommended` formats as warning/stop-signal, not color correction.
7. `additional yellow / cyan correction` or similar free text does not invent a numeric value.
8. Missing or empty guidance returns no secondary presentation rows.

Regression tests:

- Existing reciprocity confidence presentation tests still pass.
- Existing reciprocity calculation policy tests still pass.
- Existing catalog loading tests still pass if affected.

Suggested command:

```bash
xcodebuild -project PTimer.xcodeproj \
  -scheme PTimer \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing PTimerTests/ReciprocitySecondaryGuidancePresentationTests \
  test
```

Suggested regression command:

```bash
xcodebuild -project PTimer.xcodeproj \
  -scheme PTimer \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing PTimerTests/ReciprocityConfidencePresentationTests \
  -only-testing PTimerTests/ReciprocityCalculationPolicyTests \
  test
```

If the simulator name differs locally, use the nearest available iPhone simulator and report the substitution.

## 7. Documentation

Docs changes are optional and should remain small.

If updating docs, prefer a concise section in one of:

```text
docs/specs/Calculator.md
docs/specs/DomainSchema.md
```

Document only the contract:

- secondary guidance is presentation-layer only
- stored notation is preserved
- color correction, development adjustment, and warnings are separate categories
- exposure-time result remains primary

Do not create a broad design rewrite.

## 8. Definition of Done

PTIMER-88 is done when:

- A presentation-layer formatter contract exists in code.
- Stored notation is preserved exactly.
- Color correction, development adjustment, warning/stop-signal, and note guidance are separated.
- Formatter tests cover representative notation and warnings.
- Existing PTIMER-89 confidence presentation behavior is unchanged.
- Existing PTIMER-90 calculation policy behavior is unchanged.
- No domain schema redesign occurred.
- No launch catalog schema redesign occurred.
- No UI redesign occurred.
- No commit was created.

## 9. Final Report Requirements

Codex final report must include:

1. Files changed
2. Formatter contract summary
3. How existing catalog notation is handled
4. Tests added
5. Test commands and results
6. Confirmation that no domain schema, calculation policy, UI redesign, or commit was performed
