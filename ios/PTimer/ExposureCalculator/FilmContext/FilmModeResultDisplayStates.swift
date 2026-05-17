import Foundation

enum FilmModeReciprocityStateTone: Equatable {
    case trusted
    case measured
    case caution
    case advisory
    case unsupported
}

struct FilmModeReciprocityStateDisplayState: Equatable {
    let badgeText: String
    let tone: FilmModeReciprocityStateTone
    let infoText: String
    let showsInfoAffordance: Bool
}

struct FilmModeTimerActionState: Equatable {
    let targetSeconds: TimeInterval?
    let canStartTimer: Bool
    /// True when the timer would start from a formula-extrapolated
    /// corrected exposure that sits outside the manufacturer's
    /// supported guidance. The play-button presenter renders a
    /// warning-oriented treatment when this flag is set, but the
    /// timer still starts because the user has a numeric value to
    /// commit to.
    let isOutsideManufacturerGuidance: Bool
    let accessibilityLabel: String
    let accessibilityHint: String

    init(
        targetSeconds: TimeInterval?,
        canStartTimer: Bool,
        isOutsideManufacturerGuidance: Bool = false,
        accessibilityLabel: String,
        accessibilityHint: String
    ) {
        self.targetSeconds = targetSeconds
        self.canStartTimer = canStartTimer
        self.isOutsideManufacturerGuidance = isOutsideManufacturerGuidance
        self.accessibilityLabel = accessibilityLabel
        self.accessibilityHint = accessibilityHint
    }
}

enum FilmModeCorrectedExposureDisplayKind: Equatable {
    case quantified
    case advisory
    case unsupported
    case noFilmSelected
}

struct FilmModeCorrectedExposureDisplayState: Equatable {
    let kind: FilmModeCorrectedExposureDisplayKind
    let correctedExposureSeconds: TimeInterval?
    let primaryText: String
    let secondaryText: String
    let usesNumericExposure: Bool
}

struct FilmModeExposureResultState: Equatable {
    let adjustedShutterSeconds: TimeInterval
    let reciprocityState: FilmModeReciprocityStateDisplayState
    let adjustedShutterAction: FilmModeTimerActionState
    let correctedExposure: FilmModeCorrectedExposureDisplayState
    let correctedExposureAction: FilmModeTimerActionState

    var hasQuantifiedCorrectedExposure: Bool {
        correctedExposure.usesNumericExposure
    }
}
