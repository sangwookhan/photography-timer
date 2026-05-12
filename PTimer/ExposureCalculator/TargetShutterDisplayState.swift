import Foundation

/// Reason a Target Shutter comparison is unavailable. Tracks whether
/// the photographer simply has not set a target yet, or whether the
/// active workflow does not provide a comparison value (film mode
/// without a quantified corrected exposure).
enum TargetShutterUnavailableReason: Equatable {
    /// Target Shutter is inactive — the photographer has not set a
    /// duration. The UI affords enabling.
    case inactive
    /// Target is set, but the active workflow does not have a
    /// comparison value (e.g. film advisory-only, unsupported
    /// reciprocity, or a calc failure). The UI shows a calm
    /// `Target comparison unavailable` state.
    case noComparisonAvailable
}

/// Comparison value the Target Shutter card is currently evaluating
/// against. Surfaces both the value (so the UI can render it) and
/// the human-readable label (`"Adjusted Shutter"` /
/// `"Corrected Exposure"`).
struct TargetShutterComparison: Equatable {
    let label: String
    let seconds: TimeInterval
}

/// Stop-difference comparison form. `match` is reserved for the
/// near-zero case (within `TargetShutterPresenter.matchEpsilon`)
/// so the UI shows a stable match string instead of `+0.00 stops`.
enum TargetShutterStopDifferenceKind: Equatable {
    case match
    case longerThanComparison
    case shorterThanComparison
}

/// Resolved stop-difference value the UI renders. Carries the raw
/// signed stop number (for tests / VoiceOver) plus the formatted
/// label and a `kind` tag that drives styling and copy.
struct TargetShutterStopDifference: Equatable {
    let stops: Double
    let kind: TargetShutterStopDifferenceKind
    let formattedText: String
}

/// Unified display-state for the Target Shutter card. Either the
/// `available` form (target is set, comparison is meaningful) or the
/// `unavailable` form (inactive, or no comparison value to compare
/// against).
enum TargetShutterDisplayState: Equatable {
    case unavailable(TargetShutterUnavailableReason)
    case available(TargetShutterAvailableState)
}

struct TargetShutterAvailableState: Equatable {
    let targetSeconds: TimeInterval
    /// `nil` when the photographer set a target but no comparison
    /// value exists for the active workflow (film advisory, etc.).
    /// In that case `stopDifference` is also `nil` and the UI shows
    /// `Target comparison unavailable` while keeping the target
    /// visible. The model still reports `isActive == true`.
    let comparison: TargetShutterComparison?
    let stopDifference: TargetShutterStopDifference?
}
