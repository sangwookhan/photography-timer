// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

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
public enum ReciprocitySourceEvidenceClassifier {
    public static func isGuidanceBoundary(_ row: ReciprocitySourceEvidenceRow) -> Bool {
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

    /// Manufacturer stop-signal messages whose boundary the metered
    /// exposure has reached or exceeded (PTIMER-169). Scans the
    /// profile's guidance-boundary rows (see `isGuidanceBoundary`) and
    /// returns their `notRecommended` warning messages so the
    /// calculation-result presentation can surface the manufacturer's
    /// own stop signal — e.g. Velvia 50's "64 sec is not recommended."
    /// — at the point of use instead of only inside Film Details.
    ///
    /// Presentation-only, like the rest of this classifier: callers
    /// enrich result text with the returned messages; the calculation
    /// policy never reads them and no corrected exposure changes.
    public static func reachedStopSignalMessages(
        in profile: ReciprocityProfile,
        meteredExposureSeconds: Double
    ) -> [String] {
        guard meteredExposureSeconds.isFinite else { return [] }
        return profile.sourceEvidence
            .filter(isGuidanceBoundary)
            .filter { boundarySeconds(of: $0) <= meteredExposureSeconds }
            .flatMap { row in
                row.adjustments.compactMap { adjustment -> String? in
                    guard case let .warning(warning) = adjustment,
                          warning.severity == .notRecommended else { return nil }
                    return warning.message
                }
            }
    }

    private static func boundarySeconds(of row: ReciprocitySourceEvidenceRow) -> Double {
        switch row.meteredExposure {
        case let .exactSeconds(seconds):
            return seconds
        case let .range(range):
            return range.minimumSeconds
        }
    }

    /// Recognizes a graph-sampled support row (PTIMER-168 follow-up):
    /// a row whose only exposure fact is an APPROXIMATE corrected
    /// time. Rows that carry a published stop delta, multiplier,
    /// development, or color guidance are published table rows and
    /// never match — T-MAX 100's ≈1.26 s stop-conversion row carries
    /// a stop delta, so it is excluded by shape, not by film.
    /// Callers pair this with the profile's `manufacturerGraphTable`
    /// source declaration (e.g. the Details legend) so a plain-table
    /// profile never picks up graph-sampled wording.
    public static func isGraphSampledSupportRow(_ row: ReciprocitySourceEvidenceRow) -> Bool {
        var hasApproximateCorrectedTime = false
        for adjustment in row.adjustments {
            switch adjustment {
            case let .exposure(exposure):
                switch exposure {
                case let .correctedTime(mapping):
                    if mapping.isApproximate {
                        hasApproximateCorrectedTime = true
                    } else {
                        return false
                    }
                case .stopDelta, .multiplier:
                    return false
                }
            case .development, .colorFilter:
                return false
            case .warning, .note:
                continue
            }
        }
        return hasApproximateCorrectedTime
    }
}
