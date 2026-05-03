import Foundation

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

struct FilmModeDetailsLegendState: Equatable {
    let lines: [String]
}

struct FilmModeDetailsDisplayState: Equatable, Identifiable {
    let title: String
    let subtitle: String?
    let summary: FilmModeDetailsSummaryState
    let currentResult: FilmModeDetailsCurrentResultState
    let sections: [FilmModeDetailsSectionState]
    let graph: FilmModeDetailsGraphDisplayState?
    let legend: FilmModeDetailsLegendState?

    init(
        title: String,
        subtitle: String? = nil,
        summary: FilmModeDetailsSummaryState,
        currentResult: FilmModeDetailsCurrentResultState,
        sections: [FilmModeDetailsSectionState],
        graph: FilmModeDetailsGraphDisplayState? = nil,
        legend: FilmModeDetailsLegendState? = nil
    ) {
        self.title = title
        self.subtitle = subtitle
        self.summary = summary
        self.currentResult = currentResult
        self.sections = sections
        self.graph = graph
        self.legend = legend
    }

    var id: String {
        let graphID = graph.map {
            "\($0.kind)|\($0.sourcePoints.count)|\($0.currentPoint.map { String(describing: $0.style) } ?? "none")"
        } ?? "no-graph"
        return (
            [
                title,
                subtitle ?? "no-subtitle",
                summary.badgeText,
                summary.summaryText,
                String(describing: currentResult.layout),
                currentResult.adjustedShutter.valueText,
                currentResult.correctedExposure.valueText,
                graphID,
                legend?.lines.joined(separator: "|") ?? "no-legend"
            ] + sections.map(\.id)
        ).joined(separator: "|")
    }
}
