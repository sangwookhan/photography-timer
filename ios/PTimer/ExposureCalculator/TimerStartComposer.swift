import Foundation

/// Pure value composer for a timer start event. Produces the
/// display name, basis summary, and captured-identity metadata
/// that flow into `TimerWorkspaceModel.startTimer(...)`. Holds no
/// child model references; receives every fact through `Input`
/// and a `formatShutter` closure.
struct TimerStartComposer {

    enum Source {
        case digitalResult
        case filmAdjustedShutter
        case filmCorrectedExposure
        case targetShutter
        /// Manual timer entry — a precomputed shutter passed in by
        /// an external caller. Skips identity capture so the timer
        /// neither inherits the active slot nor any exposure source.
        case manual

        /// Public exposure-source axis recorded on the started timer.
        /// `nil` for manual timers so UI surfaces fall back to the
        /// order-based marker.
        var timerExposureSource: ExposureTimerSource? {
            switch self {
            case .digitalResult: return .digitalResult
            case .filmAdjustedShutter: return .filmAdjustedShutter
            case .filmCorrectedExposure: return .filmCorrectedExposure
            case .targetShutter: return .targetShutter
            case .manual: return nil
            }
        }

        /// True when the start path stamps the timer with the active
        /// camera-slot + film + exposure-source identity. Manual
        /// timers explicitly skip identity capture.
        var capturesCalculatorIdentity: Bool {
            switch self {
            case .digitalResult, .filmAdjustedShutter, .filmCorrectedExposure, .targetShutter:
                return true
            case .manual:
                return false
            }
        }
    }

    struct Input {
        let targetDuration: TimeInterval
        let result: ExposureCalculationResult?
        let filmModeResult: FilmModeExposureResultState?
        let source: Source
        let selectedPresetFilm: FilmIdentity?
        let selectedProfileOverride: ReciprocityProfile?
        let activeCameraSlot: CameraSlotIdentity?
        let targetShutterSeconds: TimeInterval?
    }

    struct Payload {
        let name: String
        let basisSummary: String
        let cameraSlot: CameraSlotIdentity?
        let filmDisplayName: String?
        let filmProfileQualifier: String?
        let exposureSource: ExposureTimerSource?
        let isOutsideManufacturerGuidance: Bool
    }

    let formatShutter: (TimeInterval) -> String

    func compose(_ input: Input) -> Payload {
        let name = makeName(input)
        let basisSummary = makeBasisSummary(input)

        let captured = input.source.capturesCalculatorIdentity
        let activeFilm = captured ? input.selectedPresetFilm : nil
        let activeProfile = captured ? input.selectedProfileOverride : nil
        let filmProfileQualifier = activeProfile.flatMap { profile -> String? in
            switch profile.source.authority {
            case .unofficial: return "Unofficial"
            case .official, .userDefined, .unknown: return nil
            }
        }

        // Outside-manufacturer-guidance applies only on the corrected
        // exposure start path. Adjusted-shutter / target-shutter
        // timers reflect calculator inputs, not the reciprocity
        // policy, so they never inherit this basis.
        let isOutsideManufacturerGuidance: Bool
        if input.source == .filmCorrectedExposure {
            isOutsideManufacturerGuidance =
                input.filmModeResult?.correctedExposureAction.isOutsideManufacturerGuidance == true
        } else {
            isOutsideManufacturerGuidance = false
        }

        return Payload(
            name: name,
            basisSummary: basisSummary,
            cameraSlot: captured ? input.activeCameraSlot : nil,
            filmDisplayName: activeFilm?.canonicalStockName,
            filmProfileQualifier: filmProfileQualifier,
            exposureSource: input.source.timerExposureSource,
            isOutsideManufacturerGuidance: isOutsideManufacturerGuidance
        )
    }

    // MARK: - Name

    private func makeName(_ input: Input) -> String {
        guard let result = input.result else {
            return "Timer - \(formatShutter(input.targetDuration))"
        }

        let targetLabel = formatShutter(input.targetDuration)
        switch input.source {
        case .filmCorrectedExposure:
            guard input.filmModeResult?.hasQuantifiedCorrectedExposure == true,
                  let film = input.selectedPresetFilm else {
                return "\(ndStopLabel(for: result.ndStep)) - \(targetLabel)"
            }
            return "\(film.canonicalStockName) - \(targetLabel)"
        case .targetShutter:
            // Target Shutter timers stamp a `Target` prefix so the
            // dock title distinguishes the photographer-supplied
            // duration from the calculated paths. When a film is
            // selected the film name precedes the `Target` segment,
            // matching the corrected-exposure shape.
            if let film = input.selectedPresetFilm {
                return "\(film.canonicalStockName) · Target - \(targetLabel)"
            }
            return "Target - \(targetLabel)"
        case .digitalResult, .filmAdjustedShutter, .manual:
            // Manual timers reuse the ND-prefixed shape; without a
            // deliberate calculator-origin tag we still render the
            // matched calc result when one is available.
            return "\(ndStopLabel(for: result.ndStep)) - \(targetLabel)"
        }
    }

    // MARK: - Basis summary

    private func makeBasisSummary(_ input: Input) -> String {
        guard let result = input.result else {
            return "Manual timer"
        }

        let adjustedShutter = formatShutter(result.resultShutterSeconds)
        let baseSummary = "Base \(formatShutter(result.baseShutterSeconds)) · \(ndStopLabel(for: result.ndStep))"

        // Target Shutter timers append a `Target <duration>` segment
        // so the dock subtitle reads e.g. `Base 1/30s · 6 stops ·
        // Target 20m` even in the digital workflow. The film-mode
        // block below still adds Adjusted / film-name segments when
        // relevant.
        var targetSegment: String?
        if input.source == .targetShutter,
           let target = input.targetShutterSeconds {
            targetSegment = "Target \(formatShutter(target))"
        }

        guard let filmModeResult = input.filmModeResult else {
            if let targetSegment {
                return "\(baseSummary) · \(targetSegment)"
            }
            return baseSummary
        }

        var segments = [
            baseSummary,
            "Adjusted \(adjustedShutter)",
        ]

        if let film = input.selectedPresetFilm {
            segments.append(film.canonicalStockName)
        }

        if input.source == .filmCorrectedExposure,
           let correctedExposureSeconds = filmModeResult.correctedExposure.correctedExposureSeconds {
            segments.append("Corrected \(formatShutter(correctedExposureSeconds))")
        }

        if let targetSegment {
            segments.append(targetSegment)
        }

        return segments.joined(separator: " · ")
    }

    // MARK: - ND label

    /// Whole-stop values render byte-for-byte as "N stops" / "1 stop"
    /// (the shipping ND picker only emits whole stops); fractional
    /// values render as mixed fractions ("1/3 stop", "2/3 stop",
    /// "1 1/3 stops") so a future fractional-ND surface preserves
    /// the fractional component on timer names and basis summaries.
    private func ndStopLabel(for ndStep: NDStep) -> String {
        if let wholeStops = ndStep.wholeStops {
            return wholeStops == 1 ? "1 stop" : "\(wholeStops) stops"
        }

        let totalThirds = Int((ndStep.stops * 3).rounded())
        let wholePart = totalThirds / 3
        let fractionalThirds = totalThirds % 3
        let fractionLabel = fractionalThirds == 1 ? "1/3" : "2/3"

        let valueText: String
        if wholePart == 0 {
            valueText = fractionLabel
        } else {
            valueText = "\(wholePart) \(fractionLabel)"
        }

        // Singular only for an exact "1 stop" boundary (impossible
        // here because `wholeStops == nil` implies a fractional
        // component).
        return "\(valueText) stops"
    }
}
