# Error Model Guide

## Mechanism Selection by Layer

| Layer | Primary mechanism | Rationale |
|---|---|---|
| **Domain / Policy** | `throws` for recoverable input errors; `Optional` return for "no result available"; `precondition` for invariant violations | Domain functions validate inputs and throw typed errors. Policy evaluators always return a result (including `.unsupported`), so they never throw. |
| **ViewModel** | `Result<T, E>` for bridging domain throws into view-consumable state; `Optional` for absent context | The ViewModel catches domain `throws` and wraps them into `Result` properties that views pattern-match on. Optional fields represent legitimately absent state (e.g., no film selected). |
| **View** | None -- views do not introduce error handling | Views consume display-state structs and `Result` properties. They switch on success/failure; they never call throwing functions directly. |
| **Persistence** | `Optional` return for missing data; silent `try?` for encode/decode failures | Persistence load returns `nil` when no snapshot exists. Encode/decode failures are silently absorbed because the app can always start from defaults. |

## When to Use Each Mechanism

### `Optional`

Use when absence is a valid domain state, not an error condition.

- `reconstructedStop(...)` returns `nil` when no stop value matches -- this is a normal "not found" result, not an error.
- `loadSnapshot()` returns `nil` when no persisted data exists.
- A policy result's quantified form carries a corrected exposure; the limited-guidance form has no such field at all and the unsupported form treats it as optional (carries a numeric continuation only when a formula keeps producing a value past its supported boundary). Absence is encoded in the case rather than as `nil`. Consumers of the convenience `correctedExposureSeconds` accessor still observe `nil` for the non-quantified forms (and for value-less unsupported results).
- `selectedPresetFilm` is `nil` when the user has not chosen a film.

### `throws`

Use when the caller must handle a failure that represents invalid or unprocessable input.

- `ExposureCalculator.parseBaseShutter(_:)` throws typed `ExposureCalculatorError` cases for empty, unparseable, or non-positive input.
- `ExposureCalculator.calculate(baseShutterSeconds:stop:)` throws for non-positive inputs and overflow.
- `LaunchPresetFilmCatalogLoader.loadBundledCatalog(...)` throws for missing resources, malformed JSON, or catalog validation failures.
- `Codable` `init(from:)` implementations throw `DecodingError` for schema violations.

### `Result<T, E>`

Use when the ViewModel needs to bridge a `throws` call into a stored/computed property that views can pattern-match on without `try/catch`.

- `ExposureCalculatorViewModel.calculationResult` is `Result<ExposureCalculationResult, ExposureCalculatorError>`. It wraps the throwing `calculate(...)` call so views can switch on `.success`/`.failure` directly.

### `precondition` / `preconditionFailure`

Use exclusively for programmer errors -- states that indicate a logic bug rather than a runtime condition. These must never be reachable from user input.

- `ReciprocityResult` payload-struct initializers (`QuantifiedPayload.init(...)` etc.) use `precondition` to enforce structural invariants (e.g., a quantified payload must carry a non-NaN, finite, non-negative `correctedExposureSeconds`). The case-form pairing itself (quantified ↔ corrected exposure) is now structurally unrepresentable rather than runtime-checked.
- `ReciprocityConfidencePresentation.init(...)` uses `precondition` to enforce that category, badge style, and result form remain internally consistent.

### `assert`

Use for debug-only invariant checks on values that should always hold but are not worth crashing release builds over.

- `TimerState.remainingTime` and `RunningTimerItem.remainingTime` use `assert` to verify duration is finite/positive and remaining time is not NaN.

## Anti-patterns

- **Optional to hide errors.** Do not return `nil` when the caller needs to distinguish between different failure reasons. If the caller must react differently to "empty input" vs. "malformed input", use `throws` with a typed error enum.
- **`throws` for expected domain states.** Do not throw when a "no result" outcome is a normal part of the domain. The reciprocity evaluator always returns a result (including `.unsupported`) rather than throwing -- absence of a correction is a valid policy answer.
- **`try?` in domain logic.** Silent `try?` is appropriate in persistence (where fallback to defaults is correct) but not in domain or policy code where swallowed errors hide bugs.
- **`fatalError` in reachable code.** Prefer `preconditionFailure` over `fatalError` -- `precondition` is stripped in release-unchecked builds, making intent clearer. Neither should be reachable from user-driven paths.
- **Untyped errors.** Domain `throws` should use a project-specific `Error` enum (e.g., `ExposureCalculatorError`, `LaunchPresetFilmCatalogLoaderError`) rather than generic `Error` or raw string messages.
