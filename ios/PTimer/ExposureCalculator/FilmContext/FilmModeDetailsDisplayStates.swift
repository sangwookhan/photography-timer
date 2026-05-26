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
}

/// Stop-spaced / log-based scale tier for the formula reciprocity
/// graph. Tiers exist so the graph never auto-expands to multi-day
/// domains when the current input produces an extreme corrected
/// exposure. Each tier defines a fixed `[1s, upper]` window and a
/// readable tick set; the presenter picks the smallest tier that
/// contains every plotted value (curve samples, current point,
/// source-reference markers, not-recommended boundary).
///
/// - `t1` covers the normal up-to-1h range used by most short
///   exposures.
/// - `t2` extends to 10h for long-exposure work.
/// - `t3` extends to 100h and is the largest visible domain. Values
///   above the `t3` upper bound trigger `isBeyondVisibleRange` on the
///   graph state rather than pushing the domain higher.
enum FilmModeDetailsGraphScaleTier: Equatable {
    case t1
    case t2
    case t3

    var lowerBoundSeconds: Double { 1 }

    var upperBoundSeconds: Double {
        switch self {
        case .t1: return 3_600          // 1 hour
        case .t2: return 36_000         // 10 hours
        case .t3: return 360_000        // 100 hours
        }
    }

    var range: ClosedRange<Double> {
        lowerBoundSeconds...upperBoundSeconds
    }

    /// Tick values + readable labels for an axis at this tier. Both
    /// axes use the same tick set because both render durations.
    /// Label density is calibrated for phone-width plots so the
    /// labels do not overlap.
    var axisTicks: [FilmModeDetailsGraphAxisTick] {
        switch self {
        case .t1:
            return [
                FilmModeDetailsGraphAxisTick(value: 1, label: "1s"),
                FilmModeDetailsGraphAxisTick(value: 4, label: "4s"),
                FilmModeDetailsGraphAxisTick(value: 15, label: "15s"),
                FilmModeDetailsGraphAxisTick(value: 60, label: "1m"),
                FilmModeDetailsGraphAxisTick(value: 240, label: "4m"),
                FilmModeDetailsGraphAxisTick(value: 960, label: "16m"),
                FilmModeDetailsGraphAxisTick(value: 3_600, label: "1h"),
            ]
        case .t2:
            return [
                FilmModeDetailsGraphAxisTick(value: 1, label: "1s"),
                FilmModeDetailsGraphAxisTick(value: 10, label: "10s"),
                FilmModeDetailsGraphAxisTick(value: 60, label: "1m"),
                FilmModeDetailsGraphAxisTick(value: 600, label: "10m"),
                FilmModeDetailsGraphAxisTick(value: 3_600, label: "1h"),
                FilmModeDetailsGraphAxisTick(value: 36_000, label: "10h"),
            ]
        case .t3:
            return [
                FilmModeDetailsGraphAxisTick(value: 1, label: "1s"),
                FilmModeDetailsGraphAxisTick(value: 60, label: "1m"),
                FilmModeDetailsGraphAxisTick(value: 3_600, label: "1h"),
                FilmModeDetailsGraphAxisTick(value: 36_000, label: "10h"),
                FilmModeDetailsGraphAxisTick(value: 360_000, label: "100h"),
            ]
        }
    }
}

/// Pure-value selector for `FilmModeDetailsGraphScaleTier`. Kept as a
/// free-standing enum (rather than a method on the tier) so it is
/// trivially testable in isolation and can be called from the
/// presenter without instantiating a struct.
enum FilmModeDetailsGraphScalePolicy {
    /// Picks the smallest tier whose `upperBoundSeconds` accommodates
    /// every plotted value. Values greater than the `t3` upper bound
    /// still return `t3`; callers should check
    /// `isBeyondVisibleRange(maxPlottedSeconds:)` separately.
    static func selectTier(
        maxPlottedSeconds: Double
    ) -> FilmModeDetailsGraphScaleTier {
        guard maxPlottedSeconds.isFinite, maxPlottedSeconds > 0 else {
            return .t1
        }
        if maxPlottedSeconds <= FilmModeDetailsGraphScaleTier.t1.upperBoundSeconds {
            return .t1
        }
        if maxPlottedSeconds <= FilmModeDetailsGraphScaleTier.t2.upperBoundSeconds {
            return .t2
        }
        return .t3
    }

    /// `true` when at least one plotted value exceeds the `t3` upper
    /// bound. The graph still uses `t3` for its domain; the view
    /// surfaces an overflow indicator instead of expanding into
    /// multi-day labels.
    static func isBeyondVisibleRange(
        maxPlottedSeconds: Double
    ) -> Bool {
        guard maxPlottedSeconds.isFinite else { return false }
        return maxPlottedSeconds > FilmModeDetailsGraphScaleTier.t3.upperBoundSeconds
    }
}

enum FilmModeDetailsGraphCurrentPointStyle: Equatable {
    /// Current result sits on the formula curve inside the
    /// manufacturer-supported range.
    case formulaDerived
    /// Current result extends past the manufacturer source range; the
    /// formula still produces a value but the result reads as outside
    /// guidance.
    case beyondSourceRange
    /// Current input falls inside the no-correction threshold range.
    /// The plotted point sits on the identity line because adjusted
    /// shutter equals corrected exposure; the marker is intentionally
    /// distinct from `.formulaDerived` so the user does not read the
    /// no-correction case as a formula prediction.
    case noCorrection
}

struct FilmModeDetailsGraphPoint: Equatable {
    let meteredExposureSeconds: Double
    let correctedExposureSeconds: Double
}

/// Open-ring marker pinned to a manufacturer-published reference
/// point. The label is rendered next to the marker so the user can
/// see which metered exposure (e.g. "240s") the reference matches
/// without consulting an external legend.
struct FilmModeDetailsGraphSourceReference: Equatable {
    let point: FilmModeDetailsGraphPoint
    let label: String
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
    /// Single comparison-card layout used by every reciprocity
    /// state (no correction, formula-derived, beyond source range,
    /// limited guidance, unsupported). Every case reads the same
    /// shape: Adjusted / Corrected / Status.
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
    /// Short, fixed-vocabulary status string rendered next to the
    /// active values. Replaces the big top heading so every case
    /// surfaces the same shape: Adjusted / Corrected / Status.
    let statusText: String
    /// Tone used to color the status text. Mirrors the summary tone
    /// so the colour cue stays consistent if both surfaces show the
    /// same row.
    let statusTone: FilmModeReciprocityStateTone

    init(
        layout: FilmModeDetailsCurrentResultLayout,
        adjustedShutter: FilmModeDetailsCurrentResultValueState,
        correctedExposure: FilmModeDetailsCurrentResultValueState,
        statusText: String = "",
        statusTone: FilmModeReciprocityStateTone = .measured
    ) {
        self.layout = layout
        self.adjustedShutter = adjustedShutter
        self.correctedExposure = correctedExposure
        self.statusText = statusText
        self.statusTone = statusTone
    }
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
    /// Upper bound of the manufacturer-supported region — for formula
    /// graphs this is the formula's
    /// `sourceRangeThroughSeconds` (the source/fitting confidence
    /// boundary), the value above which the result transitions from
    /// `.formulaDerived` to `.unsupportedOutOfPolicyRange` while the
    /// formula keeps producing a numeric prediction. Drives the
    /// dashed boundary guide in the view.
    let supportedRangeUpperBoundSeconds: Double?
    let unsupportedRegionStartSeconds: Double?
    /// Upper bound of the threshold no-correction range, when the
    /// active profile carries one (e.g. Provia 100F's 128 s threshold).
    /// Drives the light-green no-correction shading and the threshold
    /// boundary guide in the formula graph so the user reads the
    /// no-correction region as policy-derived rather than as a formula
    /// prediction outside the source range. `nil` for profiles without
    /// a threshold rule (HP5 Plus etc.).
    let noCorrectionRangeUpperBoundSeconds: Double?
    /// Open-ring markers (with adjacent labels) showing manufacturer
    /// source reference points that anchor a formula curve (e.g.
    /// Provia 100F's 240 s +1/3 stop reference). Distinct from
    /// `sourcePoints` (which holds the formula sample curve) so the
    /// user can read a single published data point versus the
    /// predicted curve passing through it. 480 s "not recommended"
    /// boundary entries are never placed here — see
    /// `notRecommendedBoundarySeconds`.
    let sourceReferenceMarkers: [FilmModeDetailsGraphSourceReference]
    /// Metered-exposure x-position at which the manufacturer signals
    /// "not recommended" (e.g. Provia 100F's 480 s). Drives the red
    /// dashed vertical boundary distinct from the source-reference
    /// markers above.
    let notRecommendedBoundarySeconds: Double?
    /// Metered-exposure x at which the manufacturer-published source
    /// range ends. Drives the persistent pink shading on converted
    /// formula graphs (everything to the right is the formula
    /// prediction outside the published source range). `nil` for
    /// profiles without a defined source range upper bound.
    let beyondSourceRangeStartSeconds: Double?
    /// User-facing formula expression rendered next to the graph
    /// (e.g. "Tc = 128 × (Tm / 128)^1.3676") so the curve is read
    /// alongside its equation.
    let formulaDisplayText: String?
    /// Descriptive bullet-style notes shown below the graph when the
    /// profile pairs a formula curve with manufacturer source-evidence
    /// markers and a not-recommended boundary. Empty when nothing
    /// extra needs to be called out, in which case the view falls back
    /// to the state-aware caption.
    let descriptionLines: [String]
    /// Tier driving `xRange`, `yRange`, and the axis tick set.
    let scaleTier: FilmModeDetailsGraphScaleTier?
    /// `true` when the current input (or its corrected exposure)
    /// exceeds the `t3` upper bound, i.e. > 100h. The graph stays
    /// pinned to `t3` and the view shows an overflow indicator instead
    /// of expanding the domain.
    let isBeyondVisibleRange: Bool
    /// `true` when the current input (or its corrected exposure)
    /// sits below the stable viewport lower bound. The viewport
    /// itself already extends below 1 s so the no-correction band
    /// renders as a visible region; this flag fires only for
    /// inputs that fall below the viewport's leading edge
    /// entirely, in which case the view suppresses the marker
    /// and surfaces an outside-visible-range chip instead.
    let isBelowVisibleRange: Bool
    let xRange: ClosedRange<Double>
    let yRange: ClosedRange<Double>

    init(
        kind: FilmModeDetailsGraphKind,
        title: String,
        sourcePoints: [FilmModeDetailsGraphPoint],
        currentPoint: FilmModeDetailsGraphCurrentPoint?,
        currentMeteredExposureSeconds: Double?,
        usesCurrentInputGuideOnly: Bool,
        caption: String,
        unsupportedExplanation: String?,
        xAxisLabel: String,
        yAxisLabel: String,
        xAxisTicks: [FilmModeDetailsGraphAxisTick],
        yAxisTicks: [FilmModeDetailsGraphAxisTick],
        supportedRangeUpperBoundSeconds: Double?,
        unsupportedRegionStartSeconds: Double?,
        noCorrectionRangeUpperBoundSeconds: Double? = nil,
        sourceReferenceMarkers: [FilmModeDetailsGraphSourceReference] = [],
        notRecommendedBoundarySeconds: Double? = nil,
        beyondSourceRangeStartSeconds: Double? = nil,
        formulaDisplayText: String? = nil,
        descriptionLines: [String] = [],
        scaleTier: FilmModeDetailsGraphScaleTier? = nil,
        isBeyondVisibleRange: Bool = false,
        isBelowVisibleRange: Bool = false,
        xRange: ClosedRange<Double>,
        yRange: ClosedRange<Double>
    ) {
        self.kind = kind
        self.title = title
        self.sourcePoints = sourcePoints
        self.currentPoint = currentPoint
        self.currentMeteredExposureSeconds = currentMeteredExposureSeconds
        self.usesCurrentInputGuideOnly = usesCurrentInputGuideOnly
        self.caption = caption
        self.unsupportedExplanation = unsupportedExplanation
        self.xAxisLabel = xAxisLabel
        self.yAxisLabel = yAxisLabel
        self.xAxisTicks = xAxisTicks
        self.yAxisTicks = yAxisTicks
        self.supportedRangeUpperBoundSeconds = supportedRangeUpperBoundSeconds
        self.unsupportedRegionStartSeconds = unsupportedRegionStartSeconds
        self.noCorrectionRangeUpperBoundSeconds = noCorrectionRangeUpperBoundSeconds
        self.sourceReferenceMarkers = sourceReferenceMarkers
        self.notRecommendedBoundarySeconds = notRecommendedBoundarySeconds
        self.beyondSourceRangeStartSeconds = beyondSourceRangeStartSeconds
        self.formulaDisplayText = formulaDisplayText
        self.descriptionLines = descriptionLines
        self.scaleTier = scaleTier
        self.isBeyondVisibleRange = isBeyondVisibleRange
        self.isBelowVisibleRange = isBelowVisibleRange
        self.xRange = xRange
        self.yRange = yRange
    }
}

struct FilmModeDetailsLegendState: Equatable {
    let lines: [String]
}

extension FilmModeDetailsGraphDisplayState {
    /// User-visible legend chip labels in their render order. The
    /// SwiftUI view derives its colored chips from this list so the
    /// chip text exists in a testable, value-only layer instead of
    /// living only in the view tree. Tests assert against this
    /// directly without instantiating the view.
    var legendChipLabels: [String] {
        if usesCurrentInputGuideOnly {
            return ["Calculation curve", "Current input"]
        }
        var items: [String] = ["Calculation curve", "Current result"]
        if !sourceReferenceMarkers.isEmpty {
            items.append("Source reference")
        }
        if noCorrectionRangeUpperBoundSeconds != nil {
            items.append("No-correction range")
        }
        if notRecommendedBoundarySeconds != nil {
            items.append("Not-recommended boundary")
        }
        if beyondSourceRangeStartSeconds != nil {
            items.append("Beyond source range")
        }
        if isBeyondVisibleRange || isBelowVisibleRange {
            items.append("Outside visible range")
        }
        return items
    }
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
                legend?.lines.joined(separator: "|") ?? "no-legend",
            ] + sections.map(\.id)
        ).joined(separator: "|")
    }
}
