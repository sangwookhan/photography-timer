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
    let accessibilityLabel: String
    let accessibilityHint: String
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
