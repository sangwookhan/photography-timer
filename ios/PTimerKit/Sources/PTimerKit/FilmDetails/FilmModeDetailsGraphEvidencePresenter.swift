// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import Foundation
import PTimerCore

/// Surfaces the manufacturer-published source-evidence rows on
/// the formula graph: open-ring markers for rows that publish a
/// quantified exposure adjustment, plus the seconds value for
/// the "not-recommended" guidance boundary. Pure value presenter:
/// no state, no model references.
public struct FilmModeDetailsGraphEvidencePresenter {
    public init() {}

    /// Produces markers for manufacturer source-evidence rows that
    /// publish a quantified exposure adjustment (e.g. Provia 100F's
    /// 240 s +1/3 stop reference). Rows whose only adjustment is
    /// a `notRecommended` warning are intentionally excluded so a
    /// stop-signal boundary never reads as a formula fitting
    /// point. Each marker carries an adjacent text label (e.g.
    /// "240s") so the user reads the published metered value
    /// directly off the graph.
    public func markers(
        for profile: ReciprocityProfile,
        formatDuration: (Double) -> String
    ) -> [FilmModeDetailsGraphSourceReference] {
        profile.sourceEvidence.compactMap { row -> FilmModeDetailsGraphSourceReference? in
            guard case let .exactSeconds(meteredExposureSeconds) = row.meteredExposure,
                  meteredExposureSeconds > 0,
                  !ReciprocitySourceEvidenceClassifier.isGuidanceBoundary(row),
                  !row.isSourceEvidenceOnly else {
                return nil
            }
            guard let correctedExposureSeconds = correctedExposureSeconds(
                meteredExposureSeconds: meteredExposureSeconds,
                adjustments: row.adjustments
            ), correctedExposureSeconds > 0 else {
                return nil
            }
            return FilmModeDetailsGraphSourceReference(
                point: FilmModeDetailsGraphPoint(
                    meteredExposureSeconds: meteredExposureSeconds,
                    correctedExposureSeconds: correctedExposureSeconds
                ),
                label: markerLabel(
                    meteredExposureSeconds: meteredExposureSeconds,
                    formatDuration: formatDuration
                )
            )
        }
    }

    /// Returns the seconds value of the manufacturer's
    /// not-recommended boundary if a guidance-boundary row exists
    /// in the profile's source evidence.
    public func notRecommendedBoundarySeconds(for profile: ReciprocityProfile) -> Double? {
        for row in profile.sourceEvidence {
            guard case let .exactSeconds(seconds) = row.meteredExposure,
                  seconds > 0,
                  ReciprocitySourceEvidenceClassifier.isGuidanceBoundary(row) else {
                continue
            }
            return seconds
        }
        return nil
    }

    /// Marker label for a source-reference point. Prefers the bare
    /// "{seconds}s" form for whole-second values so Provia 100F's
    /// 240 s reference reads as "240s" on the graph; falls back to
    /// the standard duration formatter for fractional values.
    private func markerLabel(
        meteredExposureSeconds: Double,
        formatDuration: (Double) -> String
    ) -> String {
        let rounded = meteredExposureSeconds.rounded()
        if abs(meteredExposureSeconds - rounded) < 1e-6, rounded > 0, rounded < 1e9 {
            return "\(Int(rounded))s"
        }
        return formatDuration(meteredExposureSeconds)
    }

    /// Resolves the corrected-exposure y-coordinate for a marker.
    /// Prefers the row's published `correctedTime` over a
    /// stop-delta or multiplier derivation: Kodak (and several
    /// other manufacturers) publish the stop delta as a rounded
    /// quick-reference alongside a separately-published corrected
    /// time, and those two values can disagree by up to a third
    /// of a stop (e.g. Tri-X 400's 10 s row publishes "+2 stops"
    /// and "50 s" even though +2 stops literally derives to 40 s).
    /// Returning the stop-delta derivation here would plot the
    /// marker at the wrong y-coordinate.
    private func correctedExposureSeconds(
        meteredExposureSeconds: Double,
        adjustments: [ReciprocityAdjustment]
    ) -> Double? {
        var stopAdjustment: StopDeltaAdjustment?
        var multiplierAdjustment: MultiplierAdjustment?
        for adjustment in adjustments {
            guard case let .exposure(exposureAdjustment) = adjustment else {
                continue
            }
            switch exposureAdjustment {
            case .correctedTime(let mapping):
                return mapping.correctedSeconds
            case .stopDelta(let value):
                if stopAdjustment == nil { stopAdjustment = value }
            case .multiplier(let value):
                if multiplierAdjustment == nil { multiplierAdjustment = value }
            }
        }
        if let stopAdjustment {
            return meteredExposureSeconds * pow(2, stopAdjustment.stopDelta)
        }
        if let multiplierAdjustment {
            return meteredExposureSeconds * multiplierAdjustment.factor
        }
        return nil
    }
}
