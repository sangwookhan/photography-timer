import Foundation
import PTimerKit

/// Pure-value transform from raw Target Shutter inputs (target seconds
/// + active comparison form) into the display-state the SwiftUI card
/// consumes. Lives in the `ExposureCalculator/` directory because the
/// inputs are calculator-domain values; no lifecycle, no async
/// dependency.
///
/// The presenter applies the canonical stop-difference formula:
///
///     stopDifference = log2(targetSeconds / comparisonSeconds)
///
/// Positive stop difference means the target is longer than the
/// comparison value; negative means shorter. Values within
/// `matchEpsilon` collapse to `Target matches calculated exposure`
/// so a 0.0001-stop drift never renders as `+0.00 stops`.
enum TargetShutterPresenter {
    /// Threshold below which a stop difference is considered a match.
    /// Reserved for backwards compatibility with callers that read
    /// `matchEpsilon` directly; the canonical match check inside the
    /// presenter is "does the magnitude round to zero thirds?", which
    /// gives a slightly larger match band (≈ 0–1/6 stop) and
    /// eliminates the awkward `+0 stops` / `−0 stops` outputs that
    /// happen when an off-match value still rounds to 0 thirds.
    static let matchEpsilon = 1.0 / 24.0

    /// Source for the comparison value the presenter receives from
    /// the facade. Carrying the source as input (not `nil` /
    /// `Optional<TimeInterval>`) lets the presenter emit a precise
    /// `available(comparison: nil)` state when the photographer has
    /// set a target but no comparison is meaningful, distinct from
    /// the inactive state.
    enum ComparisonSource: Equatable {
        /// Digital workflow — compare against Adjusted Shutter.
        case adjustedShutter(TimeInterval)
        /// Film workflow with a quantified corrected exposure.
        case correctedExposure(TimeInterval)
        /// No comparison value is available (film limited-guidance,
        /// unsupported, or calc failure). Distinct from the inactive
        /// case so the UI can keep the target visible.
        case unavailable
    }

    /// Builds the display state from the optional target plus the
    /// active workflow's comparison source. `targetSeconds == nil`
    /// produces the inactive form; a finite positive target with
    /// `unavailable` produces the `noComparisonAvailable` state with
    /// the target preserved; otherwise the available form with a
    /// quantified stop difference.
    static func makeDisplayState(
        targetSeconds: TimeInterval?,
        comparisonSource: ComparisonSource
    ) -> TargetShutterDisplayState {
        guard let target = targetSeconds, target.isFinite, target > 0 else {
            return .unavailable(.inactive)
        }

        switch comparisonSource {
        case .unavailable:
            return .available(
                TargetShutterAvailableState(
                    targetSeconds: target,
                    comparison: nil,
                    stopDifference: nil
                )
            )
        case .adjustedShutter(let seconds):
            return makeAvailable(
                target: target,
                comparisonLabel: "Adjusted Shutter",
                comparisonSeconds: seconds
            )
        case .correctedExposure(let seconds):
            return makeAvailable(
                target: target,
                comparisonLabel: "Corrected Exposure",
                comparisonSeconds: seconds
            )
        }
    }

    /// Formats a raw signed stop number into a readable string. Public
    /// because tests cover formatting directly without going through
    /// the full display-state composition.
    ///
    /// Match shape is `"0 stops"` so the inline result section can
    /// pair the number with the `equal` arrow and stay compact; the
    /// long-sentence "Target matches calculated exposure" is no
    /// longer the canonical form.
    static func formatStopDifference(_ stops: Double) -> TargetShutterStopDifference {
        guard stops.isFinite else {
            return TargetShutterStopDifference(
                stops: 0,
                kind: .match,
                formattedText: "0 stops"
            )
        }

        // The match zone is "anything that rounds to 0 thirds." This
        // is the same boundary the third-snap formatter uses, so a
        // 0.14-stop drift cannot leak out of the kind = .match path
        // and emit a signed `+0 stops` / `−0 stops` string. The view
        // pairs `.match` with the equal arrow and the bare `0 stops`
        // text without an arrow direction.
        let snappedTotalThirds = Int(max(0, (abs(stops) * 3).rounded()))
        if snappedTotalThirds == 0 {
            return TargetShutterStopDifference(
                stops: stops,
                kind: .match,
                formattedText: "0 stops"
            )
        }

        let kind: TargetShutterStopDifferenceKind = stops > 0
            ? .longerThanComparison
            : .shorterThanComparison

        return TargetShutterStopDifference(
            stops: stops,
            kind: kind,
            formattedText: formattedStopText(stops)
        )
    }

    private static func makeAvailable(
        target: TimeInterval,
        comparisonLabel: String,
        comparisonSeconds: TimeInterval
    ) -> TargetShutterDisplayState {
        guard comparisonSeconds.isFinite, comparisonSeconds > 0 else {
            return .available(
                TargetShutterAvailableState(
                    targetSeconds: target,
                    comparison: nil,
                    stopDifference: nil
                )
            )
        }

        let stops = log2(target / comparisonSeconds)
        return .available(
            TargetShutterAvailableState(
                targetSeconds: target,
                comparison: TargetShutterComparison(
                    label: comparisonLabel,
                    seconds: comparisonSeconds
                ),
                stopDifference: formatStopDifference(stops)
            )
        )
    }

    /// Formats a non-zero stop difference. Snaps to the nearest 1/3
    /// stop when the raw value sits within `thirdSnapEpsilon` of a
    /// 1/3-stop boundary so common cases render as `+⅓ stop`,
    /// `−⅔ stop`, `+1⅔ stops`; otherwise falls back to the same
    /// snapped form rounded to the nearest third (the photographer's
    /// natural read in the field is third-stop, not 0.14).
    ///
    /// Sign is the Unicode minus `−` (U+2212) for negative magnitudes
    /// so the typography matches the digit width and reads cleanly
    /// at the size the result section renders.
    private static func formattedStopText(_ stops: Double) -> String {
        let sign = stops > 0 ? "+" : "\u{2212}"
        let magnitude = abs(stops)
        let snapped = snappedToThirdStop(magnitude)
        let unit = snapped.isPlural ? "stops" : "stop"
        return "\(sign)\(snapped.text) \(unit)"
    }

    private static let thirdSnapEpsilon = 0.05

    /// Snapped third-stop magnitude. The text uses Unicode vulgar
    /// fractions (`⅓`, `⅔`) so the value reads compactly inline; the
    /// `isPlural` flag drives the singular/plural unit suffix
    /// downstream — `stop` for sub-1.0 magnitudes (e.g. `+⅓ stop`),
    /// `stops` for magnitudes ≥ 1 and the exact whole-stop case
    /// `+1 stops` is intentionally plural because the value crosses
    /// the 1.0 boundary and reads more naturally that way in the
    /// shooting context.
    private struct SnappedThirdStop {
        let text: String
        let isPlural: Bool
    }

    private static func snappedToThirdStop(_ magnitude: Double) -> SnappedThirdStop {
        let totalThirds = max(0, (magnitude * 3).rounded())
        let totalThirdsInt = Int(totalThirds)
        let wholePart = totalThirdsInt / 3
        let fractionalThirds = totalThirdsInt % 3

        let text: String
        switch fractionalThirds {
        case 1:
            text = wholePart == 0 ? "\u{2153}" : "\(wholePart)\u{2153}"
        case 2:
            text = wholePart == 0 ? "\u{2154}" : "\(wholePart)\u{2154}"
        default:
            text = "\(wholePart)"
        }

        // Plural rule:
        //   - whole-stop magnitudes ≥ 1 → "stops"
        //   - sub-1.0 fractional magnitudes → singular "stop"
        // The exact-zero case is handled upstream by the match path,
        // so this function never sees magnitude 0.
        let isPlural = wholePart >= 1
        return SnappedThirdStop(text: text, isPlural: isPlural)
    }
}
