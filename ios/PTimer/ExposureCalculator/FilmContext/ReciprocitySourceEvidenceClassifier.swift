import Foundation

/// Presentation-only classifier for `ReciprocitySourceEvidenceRow`.
/// Recognizes the manufacturer stop-signal pattern — a row whose only
/// guidance is a `notRecommended` warning with no exposure adjustment
/// (e.g. Provia 100F's 480 s boundary). Reference and graph
/// presenters share this rule so the same source-evidence row never
/// surfaces in one channel as a quantified reference and in the other
/// as a stop-signal boundary.
///
/// Kept distinct from the reciprocity domain so domain rules are not
/// expanded for presentation needs.
enum ReciprocitySourceEvidenceClassifier {
    static func isGuidanceBoundary(_ row: ReciprocitySourceEvidenceRow) -> Bool {
        let hasNotRecommendedWarning = row.adjustments.contains { adjustment in
            if case let .warning(warning) = adjustment, warning.severity == .notRecommended {
                return true
            }
            return false
        }
        let hasExposureAdjustment = row.adjustments.contains { adjustment in
            if case .exposure = adjustment { return true }
            return false
        }
        return hasNotRecommendedWarning && !hasExposureAdjustment
    }
}
