import SwiftUI

/// FilmModeDetailsGraphView owns the reciprocity formula graph that
/// renders inside `FilmModeDetailsSheet`. The struct body keeps the
/// SwiftUI layout (axes, layered ZStack, legend, explanation note)
/// and the value-layer mappings (legend chip → symbol, current state
/// → caption tint). All path geometry and region drawing lives in
/// `FilmModeDetailsGraphRendering.swift` as an extension so the
/// struct body itself stays focused on layout composition.

struct FilmModeDetailsGraph: View {
    let graph: FilmModeDetailsGraphDisplayState

    let graphHeight: CGFloat = 196
    let plotInset: CGFloat = 28
    let yAxisColumnWidth: CGFloat = 28
    let yTickLabelInset: CGFloat = 28

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(graph.title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            if let formulaDisplayText = graph.formulaDisplayText {
                FilmModeDetailsFormulaExpressionText(formulaDisplayText)
                    .accessibilityIdentifier("film-mode-details-graph-formula")
            }

            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 12) {
                    FilmModeDetailsGraphAxisLabel(text: graph.yAxisLabel, vertical: true)
                        .frame(width: yAxisColumnWidth)

                    VStack(alignment: .leading, spacing: 10) {
                        GeometryReader { geometry in
                            let plotSize = CGSize(
                                width: max(geometry.size.width - (plotInset * 2), 1),
                                height: max(geometry.size.height - (plotInset * 2), 1)
                            )

                            ZStack {
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .fill(Color(.secondarySystemBackground))

                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)

                                if let supportedRangeUpperBoundSeconds = graph.supportedRangeUpperBoundSeconds,
                                   graph.usesCurrentInputGuideOnly {
                                    supportedRegion(
                                        endSeconds: supportedRangeUpperBoundSeconds,
                                        in: plotSize
                                    )
                                    .padding(plotInset)
                                }

                                // Shade the no-correction range so it
                                // reads as a policy-controlled band
                                // (Tc = Tm identity through the zone),
                                // distinct from the predicted formula
                                // segment past the threshold.
                                if let noCorrectionUpperBound = graph.noCorrectionRangeUpperBoundSeconds {
                                    noCorrectionRegion(
                                        endSeconds: noCorrectionUpperBound,
                                        in: plotSize
                                    )
                                    .padding(plotInset)
                                }

                                // Pink "beyond manufacturer source
                                // range" region is persistent on
                                // converted formula graphs; the
                                // legacy red unsupported region only
                                // applies to non-converted profiles
                                // and only when the current input
                                // crosses the boundary.
                                if let beyondSourceStart = graph.beyondSourceRangeStartSeconds {
                                    beyondSourceRangeRegion(
                                        startSeconds: beyondSourceStart,
                                        in: plotSize
                                    )
                                    .padding(plotInset)
                                } else if let unsupportedStart = graph.unsupportedRegionStartSeconds {
                                    unsupportedRegion(
                                        startSeconds: unsupportedStart,
                                        in: plotSize
                                    )
                                    .padding(plotInset)
                                }

                                graphGrid(in: plotSize)
                                    .stroke(Color.primary.opacity(0.08), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                                    .padding(plotInset)

                                yAxisTickLabels(in: plotSize)
                                    .padding(plotInset)

                                sourcePath(in: plotSize)
                                    .stroke(
                                        Color.accentColor.opacity(0.9),
                                        style: StrokeStyle(
                                            lineWidth: 2.4,
                                            lineCap: .round,
                                            lineJoin: .round
                                        )
                                    )
                                    .padding(plotInset)

                                // When a profile publishes both a
                                // formula upper-bound and a manufacturer
                                // not-recommended boundary at the same
                                // shutter (e.g. Provia 100F's 480 s),
                                // skip the neutral supported-boundary
                                // line so the red dashed not-recommended
                                // marker is not overlaid by a near-
                                // duplicate gray dash.
                                if let supportedRangeUpperBoundSeconds = graph.supportedRangeUpperBoundSeconds,
                                   !shouldSuppressSupportedBoundary(at: supportedRangeUpperBoundSeconds) {
                                    supportedBoundary(
                                        at: supportedRangeUpperBoundSeconds,
                                        in: plotSize
                                    )
                                    .padding(plotInset)
                                }

                                // Threshold boundary line at the no-
                                // correction upper edge. Distinct dash
                                // pattern from the manufacturer-supported
                                // boundary so the two boundaries read
                                // differently when both are visible.
                                if let noCorrectionUpperBound = graph.noCorrectionRangeUpperBoundSeconds {
                                    noCorrectionBoundary(
                                        at: noCorrectionUpperBound,
                                        in: plotSize
                                    )
                                    .padding(plotInset)
                                }

                                if let notRecommendedBoundarySeconds = graph.notRecommendedBoundarySeconds {
                                    notRecommendedBoundary(
                                        at: notRecommendedBoundarySeconds,
                                        in: plotSize
                                    )
                                    .padding(plotInset)
                                }

                                if !graph.sourceReferenceMarkers.isEmpty {
                                    sourceReferenceMarkers(in: plotSize)
                                        .padding(plotInset)
                                }

                                if graph.usesCurrentInputGuideOnly,
                                   !graph.isBeyondVisibleRange,
                                   !graph.isBelowVisibleRange,
                                   let currentMeteredExposureSeconds = graph.currentMeteredExposureSeconds {
                                    currentInputGuideOnly(
                                        currentMeteredExposureSeconds: currentMeteredExposureSeconds,
                                        in: plotSize
                                    )
                                    .padding(plotInset)
                                } else if let currentPoint = graph.currentPoint,
                                          !graph.isBeyondVisibleRange,
                                          !graph.isBelowVisibleRange {
                                    currentPointGuide(
                                        for: currentPoint,
                                        in: plotSize
                                    )
                                    .padding(plotInset)

                                    currentPointMarker(
                                        for: currentPoint,
                                        in: plotSize
                                    )
                                    .padding(plotInset)
                                }

                                if graph.isBeyondVisibleRange || graph.isBelowVisibleRange {
                                    outsideVisibleRangeIndicator(in: plotSize)
                                        .padding(plotInset)
                                }
                            }
                            .clipShape(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                            )
                        }
                        .frame(height: graphHeight)

                        GeometryReader { geometry in
                            xAxisTickLabels(in: geometry.size.width)
                        }
                        .frame(height: 20)

                        FilmModeDetailsGraphAxisLabel(text: graph.xAxisLabel, vertical: false)
                    }
                }

                FilmModeDetailsLegendFlow(items: graphLegendItems)

                if !graphExplanationText.isEmpty {
                    FilmModeDetailsGraphStateNote(
                        symbol: graphExplanationSymbol,
                        tint: graphExplanationTint,
                        text: graphExplanationText
                    )
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(graphAccessibilityLabel)
            .accessibilityValue(graphAccessibilityValue)
        }
    }

    var graphAccessibilityLabel: String {
        "Reciprocity formula graph"
    }

    var graphAccessibilityValue: String {
        let sourceDescription = "Shows calculation curve and current point"

        let pointDescription = graph.currentPoint.map {
            switch $0.style {
            case .formulaDerived:
                return "Current point on calculation curve"
            case .beyondSourceRange:
                return "Current point beyond manufacturer source range"
            case .noCorrection:
                return "Current input in no-correction range"
            }
        } ?? (graph.usesCurrentInputGuideOnly ? "Current input shown as x position only" : "No current point")

        return "\(graph.caption). \(sourceDescription). \(pointDescription)."
    }

    /// Renders the legend chips. The label text is owned by the
    /// display state (`legendChipLabels`); this method only maps
    /// each user-visible label to its accompanying SF Symbol and
    /// accent color, so the wording is testable in the value
    /// layer instead of living inside the SwiftUI tree.
    private var graphLegendItems: [FilmModeDetailsLegendFlowItem] {
        graph.legendChipLabels.map { label in
            let symbolAndColor = symbolAndColor(forLegendLabel: label)
            return FilmModeDetailsLegendFlowItem(
                symbol: symbolAndColor.symbol,
                color: symbolAndColor.color,
                text: label
            )
        }
    }

    func symbolAndColor(
        forLegendLabel label: String
    ) -> (symbol: String, color: Color) {
        switch label {
        case "Calculation curve":
            return ("line.horizontal.3", .accentColor)
        case "Current result":
            return ("circle.fill", .blue)
        case "Current input":
            return ("line.diagonal", .red)
        case "Source reference":
            return ("circle", .green)
        case "No-correction range":
            return ("square.fill", .green.opacity(0.5))
        case "Not-recommended boundary":
            return ("minus", .red)
        case "Beyond source range":
            return ("triangle.fill", .orange)
        case "Outside visible range":
            return ("triangle.fill", .orange)
        default:
            return ("circle", .secondary)
        }
    }

    var graphExplanationSymbol: String {
        if graph.usesCurrentInputGuideOnly {
            return "info.circle"
        }

        if shouldRenderDescriptionLines {
            return "info.circle"
        }

        switch graph.currentPoint?.style {
        case .formulaDerived:
            return "function"
        case .beyondSourceRange:
            return "arrow.up.forward.circle"
        case .noCorrection:
            return "checkmark.circle"
        case .none:
            return "info.circle"
        }
    }

    var graphExplanationTint: Color {
        if graph.usesCurrentInputGuideOnly {
            return .orange
        }

        if shouldRenderDescriptionLines {
            return .secondary
        }

        switch graph.currentPoint?.style {
        case .noCorrection:
            return .green
        case .formulaDerived:
            return .blue
        case .beyondSourceRange:
            return .orange
        case .none:
            return .secondary
        }
    }

    var graphExplanationText: String {
        if shouldRenderDescriptionLines {
            return graph.descriptionLines.joined(separator: "\n")
        }
        // Formula graphs route every state-specific note through
        // `descriptionLines`; if that list is empty, the curve and
        // legend already convey enough — no caption needed.
        return ""
    }

    var shouldRenderDescriptionLines: Bool {
        !graph.descriptionLines.isEmpty
    }
}

private struct FilmModeDetailsLegendFlowItem: Equatable {
    let symbol: String
    let color: Color
    let text: String
}

private struct FilmModeDetailsLegendChip: View {
    let symbol: String
    let color: Color
    let text: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(color)

            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(
            Capsule(style: .continuous)
                .fill(Color(.tertiarySystemBackground))
        )
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(Color.primary.opacity(0.05), lineWidth: 1)
        )
    }
}

private struct FilmModeDetailsLegendFlow: View {
    let items: [FilmModeDetailsLegendFlowItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(rows.indices, id: \.self) { rowIndex in
                HStack(spacing: 8) {
                    ForEach(rows[rowIndex], id: \.text) { item in
                        FilmModeDetailsLegendChip(
                            symbol: item.symbol,
                            color: item.color,
                            text: item.text
                        )
                    }
                }
            }
        }
    }

    private var rows: [[FilmModeDetailsLegendFlowItem]] {
        guard !items.isEmpty else {
            return []
        }

        var result: [[FilmModeDetailsLegendFlowItem]] = []
        var currentRow: [FilmModeDetailsLegendFlowItem] = []

        for item in items {
            if currentRow.count == 2 {
                result.append(currentRow)
                currentRow = [item]
            } else {
                currentRow.append(item)
            }
        }

        if !currentRow.isEmpty {
            result.append(currentRow)
        }

        return result
    }
}

/// Renders a formula reference string with the same superscript
/// styling as the Formula section row. Reused inside the Reference
/// Graph card so the curve and its equation read together. Now
/// also used by the custom-film editor's Calculation Basis block
/// so the editor preview and Details surfaces render the
/// expression in the same shape.
///
/// Splitting policy (see `split(_:)`): only the exponent *token*
/// is superscripted. Anything after the first whitespace following
/// `^` — typically the ` + 0.3s` offset segment the Advanced
/// formula prints — renders at the normal baseline so the
/// expression stays readable.
struct FilmModeDetailsFormulaExpressionText: View {
    private let value: String

    init(_ value: String) {
        self.value = value
    }

    /// Result of splitting a `Tc = … ^p [ + b]` expression at the
    /// caret. `remainder` is empty when the formula ends with the
    /// exponent.
    struct ExponentParts: Equatable {
        let base: String
        let exponent: String
        let remainder: String
    }

    /// Pure splitter exposed for tests so the superscript scope is
    /// pinned to whitespace-bounded exponent tokens. `nil` when
    /// the input does not contain a usable `^…` token (no caret,
    /// or caret at the end).
    static func split(_ value: String) -> ExponentParts? {
        guard let caretIndex = value.firstIndex(of: "^") else {
            return nil
        }
        let afterCaret = value.index(after: caretIndex)
        guard afterCaret < value.endIndex else { return nil }
        let exponentEnd = value[afterCaret...].firstIndex(of: " ") ?? value.endIndex
        return ExponentParts(
            base: String(value[..<caretIndex]),
            exponent: String(value[afterCaret..<exponentEnd]),
            remainder: String(value[exponentEnd...])
        )
    }

    var body: some View {
        text
            .foregroundStyle(.primary.opacity(0.84))
    }

    private var text: Text {
        guard let parts = Self.split(value) else {
            return Text(value).font(.callout.weight(.medium))
        }
        let head = Text(parts.base).font(.callout.weight(.medium))
            + Text(parts.exponent)
                .font(.caption.weight(.semibold))
                .baselineOffset(7)
        if parts.remainder.isEmpty {
            return head
        }
        return head + Text(parts.remainder).font(.callout.weight(.medium))
    }
}

private struct FilmModeDetailsGraphAxisLabel: View {
    let text: String
    let vertical: Bool

    var body: some View {
        Text(text)
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
            .rotationEffect(vertical ? .degrees(-90) : .zero)
            .fixedSize()
            .frame(
                width: vertical ? 24 : nil,
                height: vertical ? 196 : nil,
                alignment: .center
            )
    }
}

private struct FilmModeDetailsGraphStateNote: View {
    let symbol: String
    let tint: Color
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: symbol)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(tint)
                .padding(.top, 1)

            Text(text)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
