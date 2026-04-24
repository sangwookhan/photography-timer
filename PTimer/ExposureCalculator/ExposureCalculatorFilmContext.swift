import Foundation

struct ActiveExposureCalculatorContext: Equatable {
    var selectedPresetFilm: FilmIdentity?

    init(
        selectedPresetFilm: FilmIdentity? = nil
    ) {
        self.selectedPresetFilm = selectedPresetFilm
    }
}

struct PersistentExposureCalculatorContextSnapshot: Codable, Equatable {
    let selectedPresetFilmID: String?
    let baseShutterSeconds: Double?
    let ndStop: Int?
}

protocol ExposureCalculatorContextPersistenceStoring {
    func loadSnapshot() -> PersistentExposureCalculatorContextSnapshot?
    func saveSnapshot(_ snapshot: PersistentExposureCalculatorContextSnapshot)
    func clearSnapshot()
}

struct NoOpExposureCalculatorContextPersistenceStore: ExposureCalculatorContextPersistenceStoring {
    func loadSnapshot() -> PersistentExposureCalculatorContextSnapshot? { nil }
    func saveSnapshot(_ snapshot: PersistentExposureCalculatorContextSnapshot) {}
    func clearSnapshot() {}
}

struct UserDefaultsExposureCalculatorContextPersistenceStore: ExposureCalculatorContextPersistenceStoring {
    private let userDefaults: UserDefaults
    private let snapshotKey: String
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(
        userDefaults: UserDefaults = .standard,
        snapshotKey: String = "ptimer.exposure-calculator.context.snapshot"
    ) {
        self.userDefaults = userDefaults
        self.snapshotKey = snapshotKey
    }

    func loadSnapshot() -> PersistentExposureCalculatorContextSnapshot? {
        guard let data = userDefaults.data(forKey: snapshotKey) else {
            return nil
        }

        return try? decoder.decode(PersistentExposureCalculatorContextSnapshot.self, from: data)
    }

    func saveSnapshot(_ snapshot: PersistentExposureCalculatorContextSnapshot) {
        guard let data = try? encoder.encode(snapshot) else {
            return
        }

        userDefaults.set(data, forKey: snapshotKey)
    }

    func clearSnapshot() {
        userDefaults.removeObject(forKey: snapshotKey)
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

enum FilmModeDetailsGraphKind: Equatable {
    case formula
    case table
}

enum FilmModeDetailsGraphCurrentPointStyle: Equatable {
    case exact
    case estimated
    case extrapolated
    case formulaDerived
}

struct FilmModeDetailsGraphPoint: Equatable {
    let meteredExposureSeconds: Double
    let correctedExposureSeconds: Double
}

struct FilmModeDetailsGraphCurrentPoint: Equatable {
    let point: FilmModeDetailsGraphPoint
    let style: FilmModeDetailsGraphCurrentPointStyle
}

struct FilmModeDetailsGraphAxisTick: Equatable, Identifiable {
    let value: Double
    let label: String

    var id: String {
        "\(value)|\(label)"
    }
}

struct FilmModeDetailsSummaryState: Equatable {
    let badgeText: String
    let tone: FilmModeReciprocityStateTone
    let summaryText: String
    let detailText: String?
}

enum FilmModeDetailsCurrentResultLayout: Equatable {
    case compactValue
    case compactPair
    case comparison
}

struct FilmModeDetailsCurrentResultValueState: Equatable {
    let title: String
    let valueText: String
    let detailText: String?
    let emphasizesValue: Bool
}

struct FilmModeDetailsCurrentResultState: Equatable {
    let layout: FilmModeDetailsCurrentResultLayout
    let adjustedShutter: FilmModeDetailsCurrentResultValueState
    let correctedExposure: FilmModeDetailsCurrentResultValueState
}

struct FilmModeDetailsGraphDisplayState: Equatable {
    let kind: FilmModeDetailsGraphKind
    let title: String
    let sourcePoints: [FilmModeDetailsGraphPoint]
    let currentPoint: FilmModeDetailsGraphCurrentPoint?
    let currentMeteredExposureSeconds: Double?
    let usesCurrentInputGuideOnly: Bool
    let caption: String
    let unsupportedExplanation: String?
    let xAxisLabel: String
    let yAxisLabel: String
    let xAxisTicks: [FilmModeDetailsGraphAxisTick]
    let yAxisTicks: [FilmModeDetailsGraphAxisTick]
    let supportedRangeUpperBoundSeconds: Double?
    let unsupportedRegionStartSeconds: Double?
    let xRange: ClosedRange<Double>
    let yRange: ClosedRange<Double>
}

struct FilmModeDetailsDisplayState: Equatable, Identifiable {
    let title: String
    let summary: FilmModeDetailsSummaryState
    let currentResult: FilmModeDetailsCurrentResultState
    let sections: [FilmModeDetailsSectionState]
    let graph: FilmModeDetailsGraphDisplayState?

    var id: String {
        let graphID = graph.map {
            "\($0.kind)|\($0.sourcePoints.count)|\($0.currentPoint.map { String(describing: $0.style) } ?? "none")"
        } ?? "no-graph"
        return (
            [
                title,
                summary.badgeText,
                summary.summaryText,
                String(describing: currentResult.layout),
                currentResult.adjustedShutter.valueText,
                currentResult.correctedExposure.valueText,
                graphID
            ] + sections.map(\.id)
        ).joined(separator: "|")
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
