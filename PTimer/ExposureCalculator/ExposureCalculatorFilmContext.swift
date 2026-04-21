import Foundation

struct ActiveExposureCalculatorContext: Equatable {
    var selectedPresetFilm: FilmIdentity?

    init(
        selectedPresetFilm: FilmIdentity? = nil
    ) {
        self.selectedPresetFilm = selectedPresetFilm
    }
}

struct FilmSelectorEntry: Equatable, Identifiable {
    let id: String
    let primaryText: String
    let secondaryText: String?
    let film: FilmIdentity?
}

struct FilmSelectionDisplayState: Equatable {
    let primaryText: String
    let secondaryText: String?
}

struct FilmModeReciprocityBindingState: Equatable {
    let film: FilmIdentity
    let profile: ReciprocityProfile
    let policyResult: ReciprocityCalculationPolicyResult
    let presentation: ReciprocityConfidencePresentation
}

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

enum FilmModeDetailsRowStyle: Equatable {
    case standard
    case referenceBlock
    case formulaExpression
}

struct FilmModeDetailsRowState: Equatable, Identifiable {
    let title: String
    let value: String
    let destinationURL: URL?
    let style: FilmModeDetailsRowStyle

    init(
        title: String,
        value: String,
        destinationURL: URL? = nil,
        style: FilmModeDetailsRowStyle = .standard
    ) {
        self.title = title
        self.value = value
        self.destinationURL = destinationURL
        self.style = style
    }

    var id: String {
        [title, value, destinationURL?.absoluteString ?? "", String(describing: style)].joined(separator: "|")
    }
}

struct FilmModeDetailsSectionState: Equatable, Identifiable {
    let title: String
    let rows: [FilmModeDetailsRowState]

    var id: String {
        ([title] + rows.map(\.id)).joined(separator: "|")
    }
}

struct FilmModeDetailsDisplayState: Equatable, Identifiable {
    let title: String
    let sections: [FilmModeDetailsSectionState]
    let showsGraphPlaceholder: Bool

    var id: String {
        ([title, showsGraphPlaceholder ? "graph" : "no-graph"] + sections.map(\.id)).joined(separator: "|")
    }
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
