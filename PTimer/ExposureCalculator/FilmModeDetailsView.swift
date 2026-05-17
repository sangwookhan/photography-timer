import SwiftUI
import UIKit

/// FilmModeDetailsView contains the bottom-sheet rendering for the
/// film mode reciprocity details surface (UI Spec §2.6) plus the
/// supporting graph, summary, and legend nested views. Extracted
/// from `ExposureCalculatorScreen.swift` so that file no longer
/// carries ~1,100 lines of details-sheet rendering inline.
///
/// Only `FilmModeDetailsSheet` is internal — it is the entry point
/// the screen renders. Every other type stays file-private because
/// it is a helper used exclusively by `FilmModeDetailsSheet` and
/// its descendant views.

/// Stable initial detent for the Reciprocity Details bottom sheet.
/// Using a single named constant ensures every profile type (official,
/// unofficial, formula, table, advisory) presents the sheet at the
/// same initial height.
private let reciprocityDetailsInitialDetent: PresentationDetent = .fraction(0.85)

struct FilmModeDetailsSheet: View {
    let details: FilmModeDetailsDisplayState
    @State private var scrollOffset: CGFloat = 0
    @State private var selectedDetent: PresentationDetent = reciprocityDetailsInitialDetent
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    GeometryReader { geometry in
                        Color.clear
                            .preference(
                                key: FilmModeDetailsScrollOffsetPreferenceKey.self,
                                value: geometry.frame(in: .named("film-mode-details-scroll")).minY
                            )
                    }
                    .frame(height: 0)

                    if let subtitle = details.subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("film-mode-details-subtitle")
                    }

                    // Current Result block (Adjusted Shutter,
                    // Corrected Exposure, Status) is the primary
                    // surface. The big top heading from the legacy
                    // summary block is intentionally removed — every
                    // case now reads the same shape.
                    FilmModeDetailsCurrentResultBlock(
                        currentResult: details.currentResult,
                        summary: details.summary
                    )

                    if let graph = details.graph {
                        FilmModeDetailsGraph(graph: graph)
                    } else if details.summary.tone != .advisory {
                        FilmModeDetailsGraphUnavailableNote()
                    }

                    ForEach(details.sections.filter(isEvidenceSection)) { section in
                        FilmModeDetailsSectionCard(
                            title: sectionDisplayTitle(for: section.title),
                            section: section,
                            detailRowText: detailRowText(for:)
                        )
                    }

                    if let legend = details.legend {
                        FilmModeDetailsLegend(legend: legend)
                    }

                    ForEach(details.sections.filter { $0.title == "Sources" }) { section in
                        FilmModeDetailsSectionCard(
                            title: sectionDisplayTitle(for: section.title),
                            section: section,
                            detailRowText: detailRowText(for:)
                        )
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("film-mode-details-sheet-content")
            }
            .coordinateSpace(name: "film-mode-details-scroll")
            .background(Color(.systemGroupedBackground))
            .onPreferenceChange(FilmModeDetailsScrollOffsetPreferenceKey.self) { scrollOffset = $0 }
            .safeAreaInset(edge: .top, spacing: 0) {
                if showsStickySummary {
                    FilmModeDetailsStickySummary(
                        summary: details.summary,
                        currentResult: details.currentResult
                    )
                    .padding(.horizontal, 20)
                    .padding(.top, 6)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .navigationTitle(details.title)
            .navigationBarTitleDisplayMode(.inline)
        }
        .animation(.easeInOut(duration: 0.18), value: showsStickySummary)
        .presentationDetents([reciprocityDetailsInitialDetent, .large], selection: $selectedDetent)
        .presentationDragIndicator(.visible)
    }

    private func detailRowFont(for row: FilmModeDetailsRowState) -> Font {
        switch row.style {
        case .standard:
            return .callout
        case .referenceBlock:
            return .system(.callout, design: .monospaced)
        case .formulaExpression:
            return .callout.weight(.medium)
        }
    }

    @ViewBuilder
    private func detailRowText(for row: FilmModeDetailsRowState) -> some View {
        switch row.style {
        case .formulaExpression:
            formulaExpressionText(row.value)
        case .referenceBlock:
            Text(row.value)
                .font(.system(.footnote, design: .monospaced))
                .minimumScaleFactor(0.75)
                .lineLimit(nil)
        case .standard:
            Text(row.value)
                .font(detailRowFont(for: row))
        }
    }

    private func formulaExpressionText(_ value: String) -> Text {
        guard
            let caretIndex = value.firstIndex(of: "^"),
            value.index(after: caretIndex) < value.endIndex
        else {
            return Text(value)
                .font(.callout.weight(.medium))
        }

        let base = String(value[..<caretIndex])
        let exponent = String(value[value.index(after: caretIndex)...])

        return Text(base)
            .font(.callout.weight(.medium))
        + Text(exponent)
            .font(.caption.weight(.semibold))
            .baselineOffset(7)
    }

    private func sectionDisplayTitle(for title: String) -> String {
        switch title {
        case "Reference":
            return "Reference data"
        default:
            return title
        }
    }

    /// Sections that describe manufacturer source evidence. Placed
    /// directly under the reference graph so the user can read each
    /// plotted element (source reference, guidance boundary, or the
    /// table reference for non-converted profiles) without scrolling
    /// past the profile metadata first.
    private func isEvidenceSection(_ section: FilmModeDetailsSectionState) -> Bool {
        switch section.title {
        case "Source reference", "Guidance boundary", "Reference":
            return true
        default:
            return false
        }
    }

    private var showsStickySummary: Bool {
        verticalSizeClass != .compact && scrollOffset < -110
    }
}

private struct FilmModeDetailsScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct FilmModeDetailsStickySummary: View {
    let summary: FilmModeDetailsSummaryState
    let currentResult: FilmModeDetailsCurrentResultState

    var body: some View {
        HStack(spacing: 10) {
            Text(summary.badgeText)
                .font(.caption.weight(.semibold))
                .foregroundStyle(badgeForegroundColor)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule(style: .continuous)
                        .fill(badgeBackgroundColor)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(primaryLine)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                if let secondaryLine {
                    Text(secondaryLine)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.05), radius: 10, y: 3)
    }

    private var primaryLine: String {
        if currentResult.layout == .comparison,
           currentResult.correctedExposure.emphasizesValue {
            return "\(currentResult.correctedExposure.valueText) corrected"
        }

        return summary.summaryText
    }

    private var secondaryLine: String? {
        "\(currentResult.adjustedShutter.valueText) adjusted"
    }

    private var badgeBackgroundColor: Color {
        switch summary.tone {
        case .trusted:
            return Color.green.opacity(0.16)
        case .measured:
            return Color.blue.opacity(0.14)
        case .caution:
            return Color.orange.opacity(0.16)
        case .advisory:
            return Color.yellow.opacity(0.18)
        case .unsupported:
            return Color.red.opacity(0.14)
        }
    }

    private var badgeForegroundColor: Color {
        switch summary.tone {
        case .trusted:
            return .green
        case .measured:
            return .blue
        case .caution:
            return .orange
        case .advisory:
            return .yellow.opacity(0.9)
        case .unsupported:
            return .red
        }
    }
}

private struct FilmModeDetailsSectionCard<RowContent: View>: View {
    let title: String
    let section: FilmModeDetailsSectionState
    let detailRowText: (FilmModeDetailsRowState) -> RowContent

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 12) {
                ForEach(section.rows) { row in
                    VStack(alignment: .leading, spacing: 4) {
                        if !row.title.isEmpty {
                            Text(row.title)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }

                        if let destinationURL = row.destinationURL {
                            Link(destination: destinationURL) {
                                detailRowText(row)
                                    .foregroundStyle(.tint)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        } else {
                            detailRowText(row)
                                .foregroundStyle(.primary.opacity(0.84))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 2)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(row.title.isEmpty ? section.title : row.title)
                    .accessibilityValue(row.value)

                    if row.id != section.rows.last?.id {
                        Divider()
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

private struct FilmModeDetailsGraphUnavailableNote: View {
    var body: some View {
        Text("No quantified reference graph is available.")
            .font(.footnote)
            .foregroundStyle(.secondary)
    }
}

private struct FilmModeDetailsSummary: View {
    let summary: FilmModeDetailsSummaryState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(summary.badgeText)
                .font(.caption.weight(.semibold))
                .foregroundStyle(badgeForegroundColor)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule(style: .continuous)
                        .fill(badgeBackgroundColor)
                )

            Text(summary.summaryText)
                .font(.headline.weight(.semibold))
                .foregroundStyle(.primary)

            if let detailText = summary.detailText {
                Text(detailText)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var badgeBackgroundColor: Color {
        switch summary.tone {
        case .trusted:
            return Color.green.opacity(0.16)
        case .measured:
            return Color.blue.opacity(0.14)
        case .caution:
            return Color.orange.opacity(0.16)
        case .advisory:
            return Color.yellow.opacity(0.18)
        case .unsupported:
            return Color.red.opacity(0.14)
        }
    }

    private var badgeForegroundColor: Color {
        switch summary.tone {
        case .trusted:
            return .green
        case .measured:
            return .blue
        case .caution:
            return .orange
        case .advisory:
            return .yellow.opacity(0.9)
        case .unsupported:
            return .red
        }
    }
}

private struct FilmModeDetailsCurrentResultBlock: View {
    let currentResult: FilmModeDetailsCurrentResultState
    let summary: FilmModeDetailsSummaryState

    var body: some View {
        comparisonBody
    }

    private func valueColumn(
        for value: FilmModeDetailsCurrentResultValueState
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(value.valueText)
                .font(value.emphasizesValue ? .system(.title2, design: .rounded).weight(.semibold) : .title3.weight(.semibold))
                .foregroundStyle(value.emphasizesValue ? .primary : secondaryValueColor(for: value))
                .minimumScaleFactor(0.75)
                .lineLimit(2)

            if let detailText = value.detailText {
                Text(detailText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var comparisonBody: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                valueColumn(for: currentResult.adjustedShutter)

                Divider()

                valueColumn(for: currentResult.correctedExposure)
            }

            statusLine

            summaryDetailLine
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }

    /// Authority/policy caveat carried in `summary.detailText`. Placed
    /// directly under the Status line so the user reads it as part of
    /// the same summary card — never below the graph. For unofficial
    /// practical formula profiles this is the
    /// "Not a Kodak-published profile" note that must be visible
    /// before the user trusts the corrected exposure.
    @ViewBuilder
    private var summaryDetailLine: some View {
        if let detailText = summary.detailText, !detailText.isEmpty {
            Text(detailText)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier("film-mode-details-summary-detail")
        }
    }

    /// Compact "Status: …" line driven by
    /// `currentResult.statusText`. Replaces the legacy big top
    /// summary heading; every case (no correction, formula-derived,
    /// beyond source range, beyond visible range, …) reads through
    /// this single short row.
    @ViewBuilder
    private var statusLine: some View {
        let text = currentResult.statusText
        if !text.isEmpty {
            HStack(spacing: 6) {
                Text("Status")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Text(text)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(statusTone)
                    .minimumScaleFactor(0.8)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Status: \(text)")
        }
    }

    private var statusTone: Color {
        switch currentResult.statusTone {
        case .trusted:
            return .green
        case .measured:
            return .blue
        case .caution:
            return .orange
        case .advisory:
            return .yellow.opacity(0.9)
        case .unsupported:
            return .red
        }
    }

    private func secondaryValueColor(
        for value: FilmModeDetailsCurrentResultValueState
    ) -> Color {
        guard value.title == "Corrected Exposure" else {
            return .primary
        }

        switch summary.tone {
        case .unsupported, .advisory:
            return .orange
        case .trusted, .measured, .caution:
            return .primary
        }
    }
}

private struct FilmModeDetailsLegend: View {
    let legend: FilmModeDetailsLegendState

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(legend.lines.enumerated()), id: \.offset) { _, line in
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "info.circle")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.top, 2)
                    Text(line)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(line)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("film-mode-details-legend")
    }
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
    let items: [(symbol: String, color: Color, text: String)]

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

    private var rows: [[(symbol: String, color: Color, text: String)]] {
        guard !items.isEmpty else {
            return []
        }

        var result: [[(symbol: String, color: Color, text: String)]] = []
        var currentRow: [(symbol: String, color: Color, text: String)] = []

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
/// Graph card so the curve and its equation read together.
private struct FilmModeDetailsFormulaExpressionText: View {
    private let value: String

    init(_ value: String) {
        self.value = value
    }

    var body: some View {
        text
            .foregroundStyle(.primary.opacity(0.84))
    }

    private var text: Text {
        guard
            let caretIndex = value.firstIndex(of: "^"),
            value.index(after: caretIndex) < value.endIndex
        else {
            return Text(value).font(.callout.weight(.medium))
        }

        let base = String(value[..<caretIndex])
        let exponent = String(value[value.index(after: caretIndex)...])

        return Text(base)
            .font(.callout.weight(.medium))
        + Text(exponent)
            .font(.caption.weight(.semibold))
            .baselineOffset(7)
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

private struct FilmModeDetailsGraph: View {
    let graph: FilmModeDetailsGraphDisplayState

    private let graphHeight: CGFloat = 196
    private let plotInset: CGFloat = 28
    private let yAxisColumnWidth: CGFloat = 28
    private let yTickLabelInset: CGFloat = 28

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
                                // reads as policy-controlled, not as a
                                // missing chunk of the formula curve.
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
                                        graph.kind == .formula ? Color.accentColor.opacity(0.9) : Color.secondary.opacity(0.82),
                                        style: StrokeStyle(
                                            lineWidth: graph.kind == .formula ? 2.4 : 1.8,
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

                                if graph.kind == .table {
                                    tableAnchorMarkers(in: plotSize)
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

    private func graphGrid(in size: CGSize) -> Path {
        Path { path in
            let horizontalFractions: [CGFloat] = [0.25, 0.5, 0.75]
            let verticalFractions: [CGFloat] = [0.25, 0.5, 0.75]

            for fraction in horizontalFractions {
                let y = size.height * fraction
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
            }

            for fraction in verticalFractions {
                let x = size.width * fraction
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
            }
        }
    }

    private func sourcePath(in size: CGSize) -> Path {
        Path { path in
            for (index, point) in graph.sourcePoints.enumerated() {
                let plotted = plottedPoint(for: point, in: size)
                if index == 0 {
                    path.move(to: plotted)
                } else {
                    path.addLine(to: plotted)
                }
            }
        }
    }

    private func unsupportedRegion(
        startSeconds: Double,
        in size: CGSize
    ) -> some View {
        let x = scaledValue(startSeconds, within: graph.xRange, size: size.width)

        return Rectangle()
            .fill(Color.red.opacity(0.08))
            .frame(width: max(size.width - x, 0), height: size.height)
            .position(x: x + max(size.width - x, 0) / 2, y: size.height / 2)
    }

    private func supportedRegion(
        endSeconds: Double,
        in size: CGSize
    ) -> some View {
        let x = scaledValue(endSeconds, within: graph.xRange, size: size.width)

        return Rectangle()
            .fill(Color.green.opacity(0.06))
            .frame(width: max(x, 0), height: size.height)
            .position(x: max(x, 0) / 2, y: size.height / 2)
    }

    /// Persistent pink band marking the metered-exposure region
    /// where the formula extrapolates past the published manufacturer
    /// source range. Shown for converted formula profiles regardless
    /// of where the current input lands, so the user can always see
    /// which portion of the curve is past the published reference.
    private func beyondSourceRangeRegion(
        startSeconds: Double,
        in size: CGSize
    ) -> some View {
        let x = scaledValue(startSeconds, within: graph.xRange, size: size.width)

        return Rectangle()
            .fill(Color.pink.opacity(0.10))
            .frame(width: max(size.width - x, 0), height: size.height)
            .position(x: x + max(size.width - x, 0) / 2, y: size.height / 2)
    }

    private func supportedBoundary(
        at seconds: Double,
        in size: CGSize
    ) -> some View {
        let x = scaledValue(seconds, within: graph.xRange, size: size.width)

        return Path { path in
            path.move(to: CGPoint(x: x, y: 0))
            path.addLine(to: CGPoint(x: x, y: size.height))
        }
        .stroke(Color.primary.opacity(0.22), style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
    }

    /// Light-green band covering the no-correction shutter range —
    /// e.g. Provia 100F's 0…128 s. Marks the policy zone where
    /// adjusted shutter equals corrected exposure so the user reads
    /// the area under no-correction guidance, not as a missing portion
    /// of the formula curve.
    private func noCorrectionRegion(
        endSeconds: Double,
        in size: CGSize
    ) -> some View {
        let x = scaledValue(endSeconds, within: graph.xRange, size: size.width)

        return Rectangle()
            .fill(Color.green.opacity(0.10))
            .frame(width: max(x, 0), height: size.height)
            .position(x: max(x, 0) / 2, y: size.height / 2)
    }

    /// Dashed vertical at the no-correction upper edge. Uses a tighter
    /// dash than the supported-range boundary so the two boundaries
    /// read distinctly when a profile (e.g. Provia 100F) carries both
    /// a 128 s threshold and a 480 s formula upper bound.
    private func noCorrectionBoundary(
        at seconds: Double,
        in size: CGSize
    ) -> some View {
        let x = scaledValue(seconds, within: graph.xRange, size: size.width)

        return Path { path in
            path.move(to: CGPoint(x: x, y: 0))
            path.addLine(to: CGPoint(x: x, y: size.height))
        }
        .stroke(Color.green.opacity(0.45), style: StrokeStyle(lineWidth: 1.5, dash: [2, 3]))
    }

    @ViewBuilder
    private func tableAnchorMarkers(in size: CGSize) -> some View {
        ZStack {
            ForEach(Array(graph.sourcePoints.enumerated()), id: \.offset) { _, point in
                Circle()
                    .fill(Color(.systemBackground))
                    .frame(width: 8, height: 8)
                    .overlay {
                        Circle()
                            .stroke(Color.secondary.opacity(0.8), lineWidth: 1.5)
                    }
                    .position(plottedPoint(for: point, in: size))
            }
        }
    }

    /// Small open green rings (with attached labels) drawn over the
    /// formula curve for each manufacturer source-reference point.
    /// The ring is roughly half the size of the current-result blue
    /// dot so visual priority always sits with the current result,
    /// not the static reference. The label hugs the ring (right
    /// above by default, beside it as a fallback) so the "240s" tag
    /// reads as a piece of the marker rather than a stray annotation.
    @ViewBuilder
    private func sourceReferenceMarkers(in size: CGSize) -> some View {
        ZStack {
            ForEach(Array(graph.sourceReferenceMarkers.enumerated()), id: \.offset) { _, marker in
                let plotted = plottedPoint(for: marker.point, in: size)
                let labelPosition = sourceReferenceLabelPosition(
                    for: plotted,
                    in: size
                )

                Circle()
                    .fill(Color(.systemBackground))
                    .frame(width: 6, height: 6)
                    .overlay {
                        Circle()
                            .stroke(Color.green, lineWidth: 1)
                    }
                    .position(plotted)

                Text(marker.label)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color.green)
                    .padding(.horizontal, 3)
                    .padding(.vertical, 0.5)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color(.systemBackground).opacity(0.9))
                    )
                    .fixedSize()
                    .position(labelPosition)
            }
        }
    }

    /// Anchors a source-reference label tight against its small
    /// green ring. The label sits directly above the marker by
    /// default so it reads as part of the marker; it falls back to
    /// directly beside the marker when the marker hugs the top
    /// edge, and it gets pushed inward at the plot's right edge so
    /// the text never clips. The compact offset prevents the label
    /// from drifting onto the formula curve or into the area where
    /// the current-result blue dot could be misread as the labeled
    /// point.
    private func sourceReferenceLabelPosition(
        for plotted: CGPoint,
        in size: CGSize
    ) -> CGPoint {
        let verticalOffset: CGFloat = 10
        let sideOffset: CGFloat = 14
        let topGuard: CGFloat = verticalOffset + 6
        let edgePadding: CGFloat = 18

        if plotted.y < topGuard {
            // Marker pinned near the top — place the label beside
            // the marker instead of below, so it does not float
            // onto the curve.
            let x: CGFloat
            if plotted.x + sideOffset + edgePadding > size.width {
                x = max(plotted.x - sideOffset, edgePadding)
            } else {
                x = plotted.x + sideOffset
            }
            return CGPoint(x: x, y: plotted.y)
        }

        let clampedX = max(edgePadding, min(plotted.x, size.width - edgePadding))
        return CGPoint(x: clampedX, y: plotted.y - verticalOffset)
    }

    /// Red dashed vertical at the manufacturer not-recommended
    /// boundary (e.g. Provia 100F's 480 s). Stays visually distinct
    /// from the neutral supported-range boundary so the user reads it
    /// as a stop-signal, not as a generic upper bound.
    private func notRecommendedBoundary(
        at seconds: Double,
        in size: CGSize
    ) -> some View {
        let x = scaledValue(seconds, within: graph.xRange, size: size.width)

        return Path { path in
            path.move(to: CGPoint(x: x, y: 0))
            path.addLine(to: CGPoint(x: x, y: size.height))
        }
        .stroke(Color.red.opacity(0.75), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
    }

    private func shouldSuppressSupportedBoundary(at seconds: Double) -> Bool {
        guard let notRecommendedBoundarySeconds = graph.notRecommendedBoundarySeconds else {
            return false
        }
        let supportedLog = log10(max(seconds, 0.000_001))
        let boundaryLog = log10(max(notRecommendedBoundarySeconds, 0.000_001))
        return abs(supportedLog - boundaryLog) < 0.02
    }

    @ViewBuilder
    private func currentPointGuide(
        for currentPoint: FilmModeDetailsGraphCurrentPoint,
        in size: CGSize
    ) -> some View {
        if graph.kind == .table,
           currentPoint.style == .extrapolated,
           let lastSourcePoint = graph.sourcePoints.last {
            Path { path in
                path.move(to: plottedPoint(for: lastSourcePoint, in: size))
                path.addLine(to: plottedPoint(for: currentPoint.point, in: size))
            }
            .stroke(
                Color.orange.opacity(0.7),
                style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [5, 4])
            )
        }
    }

    private func currentInputGuideOnly(
        currentMeteredExposureSeconds: Double,
        in size: CGSize
    ) -> some View {
        let x = scaledValue(currentMeteredExposureSeconds, within: graph.xRange, size: size.width)

        return ZStack {
            Rectangle()
                .fill(Color.red.opacity(0.08))
                .frame(width: 14, height: size.height)
                .position(x: x, y: size.height / 2)

            Path { path in
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
            }
            .stroke(Color.red.opacity(0.7), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [6, 5]))
        }
    }

    @ViewBuilder
    private func currentPointMarker(
        for currentPoint: FilmModeDetailsGraphCurrentPoint,
        in size: CGSize
    ) -> some View {
        let plotted = plottedPoint(for: currentPoint.point, in: size)

        switch graph.kind {
        case .formula:
            // Every in-range current result on a formula graph is a
            // filled blue dot regardless of policy basis (exact,
            // estimated, formula-derived, no-correction, extrapolated).
            // The status line, region shading, and source-reference
            // marker carry the state-specific meaning; the current
            // marker stays one consistent shape so it never reads
            // as a source reference.
            Circle()
                .fill(Color.blue)
                .frame(width: 13, height: 13)
                .overlay {
                    Circle()
                        .stroke(Color(.systemBackground), lineWidth: 2)
                }
                .position(plotted)
        case .table:
            tableCurrentPointMarker(for: currentPoint, plotted: plotted)
        }
    }

    /// Legacy per-policy marker styling preserved for non-converted
    /// table profiles. Formula graphs route to the blue-dot rule
    /// above.
    @ViewBuilder
    private func tableCurrentPointMarker(
        for currentPoint: FilmModeDetailsGraphCurrentPoint,
        plotted: CGPoint
    ) -> some View {
        switch currentPoint.style {
        case .exact:
            Circle()
                .fill(Color.green)
                .frame(width: 14, height: 14)
                .overlay { Circle().stroke(Color(.systemBackground), lineWidth: 2) }
                .position(plotted)
        case .estimated:
            Diamond()
                .fill(Color.blue)
                .frame(width: 15, height: 15)
                .overlay { Diamond().stroke(Color.blue.opacity(0.25), lineWidth: 5) }
                .overlay { Diamond().stroke(Color(.systemBackground), lineWidth: 2) }
                .position(plotted)
        case .extrapolated:
            Triangle()
                .fill(Color.orange)
                .frame(width: 16, height: 15)
                .overlay { Triangle().stroke(Color(.systemBackground), lineWidth: 2) }
                .position(plotted)
        case .formulaDerived:
            Circle()
                .fill(Color.accentColor)
                .frame(width: 15, height: 15)
                .overlay { Circle().stroke(Color(.systemBackground), lineWidth: 2) }
                .overlay { Circle().stroke(Color.accentColor.opacity(0.3), lineWidth: 5) }
                .position(plotted)
        case .noCorrection:
            Circle()
                .stroke(Color.green, lineWidth: 2)
                .frame(width: 14, height: 14)
                .background(
                    Circle().fill(Color(.systemBackground)).frame(width: 14, height: 14)
                )
                .position(plotted)
        }
    }

    /// Edge-anchored orange triangle that signals the current
    /// result sits outside the visible graph range. The triangle's
    /// orientation matches whether the value spilled past the right
    /// edge (beyond visible) or the left edge (below visible).
    @ViewBuilder
    private func outsideVisibleRangeIndicator(in size: CGSize) -> some View {
        if graph.isBeyondVisibleRange {
            Triangle()
                .fill(Color.orange)
                .frame(width: 14, height: 12)
                .overlay { Triangle().stroke(Color(.systemBackground), lineWidth: 2) }
                .rotationEffect(.degrees(90))
                .position(x: size.width - 10, y: size.height / 2)
                .accessibilityIdentifier("film-mode-details-graph-outside-visible")
        } else if graph.isBelowVisibleRange {
            Triangle()
                .fill(Color.orange)
                .frame(width: 14, height: 12)
                .overlay { Triangle().stroke(Color(.systemBackground), lineWidth: 2) }
                .rotationEffect(.degrees(-90))
                .position(x: 10, y: size.height / 2)
                .accessibilityIdentifier("film-mode-details-graph-outside-visible")
        }
    }

    @ViewBuilder
    private func yAxisTickLabels(in size: CGSize) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(graph.yAxisTicks) { tick in
                Text(tick.label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(width: yTickLabelInset, alignment: .leading)
                    .position(
                        x: yTickLabelInset / 2,
                        y: size.height - scaledValue(tick.value, within: graph.yRange, size: size.height)
                    )
            }
        }
    }

    private func xAxisTickLabels(in width: CGFloat) -> some View {
        ZStack(alignment: .leading) {
            ForEach(graph.xAxisTicks) { tick in
                Text(tick.label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .position(
                        x: scaledValue(tick.value, within: graph.xRange, size: width),
                        y: 7
                    )
            }
        }
    }

    private func plottedPoint(
        for point: FilmModeDetailsGraphPoint,
        in size: CGSize
    ) -> CGPoint {
        let x = scaledValue(
            point.meteredExposureSeconds,
            within: graph.xRange,
            size: size.width
        )
        let y = size.height - scaledValue(
            point.correctedExposureSeconds,
            within: graph.yRange,
            size: size.height
        )

        return CGPoint(x: x, y: y)
    }

    private func scaledValue(
        _ value: Double,
        within range: ClosedRange<Double>,
        size: CGFloat
    ) -> CGFloat {
        let lowerLog = log10(range.lowerBound)
        let upperLog = log10(range.upperBound)
        let valueLog = log10(max(value, range.lowerBound))
        let progress = (valueLog - lowerLog) / max(upperLog - lowerLog, 0.000_001)
        return CGFloat(progress) * size
    }

    private var graphAccessibilityLabel: String {
        switch graph.kind {
        case .formula:
            return "Reciprocity formula graph"
        case .table:
            return "Reciprocity reference table graph"
        }
    }

    private var graphAccessibilityValue: String {
        let sourceDescription: String
        switch graph.kind {
        case .formula:
            sourceDescription = "Shows formula curve and current point"
        case .table:
            sourceDescription = "Shows neutral reference anchors and current point"
        }

        let pointDescription = graph.currentPoint.map {
            switch $0.style {
            case .exact:
                return "Current point exact"
            case .estimated:
                return "Current point estimated"
            case .extrapolated:
                return "Current point extrapolated outside manufacturer guidance"
            case .formulaDerived:
                return "Current point on formula curve"
            case .noCorrection:
                return "Current input in no-correction range"
            }
        } ?? (graph.usesCurrentInputGuideOnly ? "Current input shown as x position only" : "No current point")

        return "\(graph.caption). \(sourceDescription). \(pointDescription)."
    }

    private var graphLegendItems: [(symbol: String, color: Color, text: String)] {
        switch graph.kind {
        case .formula:
            if graph.usesCurrentInputGuideOnly {
                return [
                    ("line.horizontal.3", .accentColor, "Formula curve"),
                    ("line.diagonal", .red, "Current input")
                ]
            }
            var items: [(symbol: String, color: Color, text: String)] = [
                ("line.horizontal.3", .accentColor, "Formula curve"),
                ("circle.fill", .blue, "Current result")
            ]
            if !graph.sourceReferenceMarkers.isEmpty {
                items.append(("circle", .green, "Source reference"))
            }
            if graph.noCorrectionRangeUpperBoundSeconds != nil {
                items.append(("square.fill", .green.opacity(0.5), "No-correction range"))
            }
            if graph.notRecommendedBoundarySeconds != nil {
                items.append(("minus", .red, "Not-recommended boundary"))
            }
            if graph.beyondSourceRangeStartSeconds != nil {
                items.append(("square.fill", .pink.opacity(0.5), "Beyond source range"))
            }
            if graph.isBeyondVisibleRange || graph.isBelowVisibleRange {
                items.append(("triangle.fill", .orange, "Outside visible range"))
            }
            return items
        case .table:
            var items: [(symbol: String, color: Color, text: String)] = [
                ("circle", .secondary, "Reference")
            ]

            if graph.usesCurrentInputGuideOnly {
                items.append(("square.fill", .green.opacity(0.5), "Range limit"))
                items.append(("line.diagonal", .red, "Current input"))
                return items
            }

            if let currentPoint = graph.currentPoint {
                items.append(currentPointLegendItem(for: currentPoint.style))
            }

            return items
        }
    }

    private func currentPointLegendItem(
        for style: FilmModeDetailsGraphCurrentPointStyle
    ) -> (symbol: String, color: Color, text: String) {
        switch style {
        case .exact:
            return ("circle.fill", .green, "Exact")
        case .estimated:
            return ("diamond.fill", .blue, "Estimated")
        case .extrapolated:
            // Converted formula profiles (formula + source evidence)
            // present the same orange triangle marker but read as
            // beyond the manufacturer source range. Non-converted
            // table profiles keep the legacy "Extrapolated" label so
            // their wording is unchanged.
            let isConvertedFormulaProfile = graph.kind == .formula
                && !graph.sourceReferenceMarkers.isEmpty
            let label = isConvertedFormulaProfile ? "Beyond source range" : "Extrapolated"
            return ("triangle.fill", .orange, label)
        case .formulaDerived:
            return ("circle.fill", .accentColor, "Current result")
        case .noCorrection:
            return ("circle", .green, "No correction")
        }
    }

    private var graphExplanationSymbol: String {
        if graph.usesCurrentInputGuideOnly {
            return "info.circle"
        }

        if shouldRenderDescriptionLines {
            return "info.circle"
        }

        switch graph.currentPoint?.style {
        case .exact:
            return "checkmark.circle"
        case .estimated:
            return "slider.horizontal.below.square.and.square.filled"
        case .extrapolated:
            return "arrow.up.forward.circle"
        case .formulaDerived:
            return "function"
        case .noCorrection:
            return "checkmark.circle"
        case .none:
            return "info.circle"
        }
    }

    private var graphExplanationTint: Color {
        if graph.usesCurrentInputGuideOnly {
            return .orange
        }

        if shouldRenderDescriptionLines {
            return .secondary
        }

        switch graph.currentPoint?.style {
        case .exact, .noCorrection:
            return .green
        case .estimated, .formulaDerived:
            return .blue
        case .extrapolated:
            return .orange
        case .none:
            return .secondary
        }
    }

    private var graphExplanationText: String {
        if shouldRenderDescriptionLines {
            return graph.descriptionLines.joined(separator: "\n")
        }
        if graph.kind == .formula {
            // Formula graphs route every state-specific note through
            // `descriptionLines`; if that list is empty, the curve
            // and legend already convey enough — no caption needed.
            return ""
        }
        if let unsupportedExplanation = graph.unsupportedExplanation {
            return unsupportedExplanation
        }
        return graph.caption
    }

    private var shouldRenderDescriptionLines: Bool {
        !graph.descriptionLines.isEmpty
    }
}

private struct Diamond: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.midX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
            path.closeSubpath()
        }
    }
}

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.midX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.closeSubpath()
        }
    }
}
