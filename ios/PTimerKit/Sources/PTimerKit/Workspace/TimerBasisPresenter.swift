// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import Foundation
import PTimerCore

/// Builds a timer card's basis line from structured exposure inputs
/// in the current ND notation mode, instead of reading a precomposed
/// string (PTIMER-187).
///
/// The basis line shows calculation *inputs* only — the final
/// exposure value is the timer's duration, already shown elsewhere on
/// the card, so it is never repeated here:
/// - Digital / adjusted-shutter: `Base <base> · <ND>` (for the
///   adjusted-shutter source the adjusted value *is* the duration, so
///   there is no `Adj` segment).
/// - Corrected / target: `Base <base> · <ND> · Adj <adjusted>` — the
///   adjusted shutter is an intermediate distinct from the final
///   corrected/target duration.
///
/// Templates are positional `String(format:)` strings so number/label
/// placement can move when localized.
public enum TimerBasisPresenter {
    public static func basisText(
        ndStops: Double?,
        baseShutterSeconds: TimeInterval?,
        adjustedShutterSeconds: TimeInterval?,
        exposureSource: ExposureTimerSource?,
        notationMode: NDNotationMode,
        formatShutter: (TimeInterval) -> String
    ) -> String? {
        guard let ndStops, let baseShutterSeconds else {
            return nil
        }

        let ndText = NDNotationFormatter.display(forStops: ndStops, mode: notationMode).inline
        let baseText = formatShutter(baseShutterSeconds)

        if includesAdjustedSegment(for: exposureSource),
           let adjustedShutterSeconds {
            return String(
                format: Template.baseNDAdjusted,
                baseText,
                ndText,
                formatShutter(adjustedShutterSeconds)
            )
        }

        return String(format: Template.baseND, baseText, ndText)
    }

    public static func basisText(
        for timer: RunningTimerItem,
        notationMode: NDNotationMode,
        formatShutter: (TimeInterval) -> String
    ) -> String? {
        basisText(
            ndStops: timer.ndStops,
            baseShutterSeconds: timer.baseShutterSeconds,
            adjustedShutterSeconds: timer.adjustedShutterSeconds,
            exposureSource: timer.exposureSource,
            notationMode: notationMode,
            formatShutter: formatShutter
        )
    }

    /// The adjusted shutter is a distinct intermediate only for the
    /// corrected and target sources. For the adjusted-shutter source
    /// it equals the timer duration, and the digital source has no
    /// reciprocity step, so neither shows an `Adj` segment.
    private static func includesAdjustedSegment(for source: ExposureTimerSource?) -> Bool {
        switch source {
        case .filmCorrectedExposure, .targetShutter:
            return true
        case .digitalResult, .filmAdjustedShutter, .none:
            return false
        }
    }

    private enum Template {
        static let baseND = String(localized: "Base %1$@ · %2$@")
        static let baseNDAdjusted = String(localized: "Base %1$@ · %2$@ · Adj %3$@")
    }
}
