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

                    FilmModeDetailsSummary(summary: details.summary)

                    FilmModeDetailsCurrentResultBlock(
                        currentResult: details.currentResult,
                        summary: details.summary
                    )

                    // Evidence sections (Profile, Formula, Reference) before graph
                    ForEach(details.sections.filter { $0.title != "Sources" }) { section in
                        FilmModeDetailsSectionCard(
                            title: sectionDisplayTitle(for: section.title),
                            section: section,
                            detailRowText: detailRowText(for:)
                        )
                    }

                    if let graph = details.graph {
                        FilmModeDetailsGraph(graph: graph)
                    } else if details.summary.tone != .advisory && details.currentResult.layout != .compactValue {
                        FilmModeDetailsGraphUnavailableNote()
                    }

                    // Sources section after graph
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
        switch currentResult.layout {
        case .compactValue:
            return nil
        case .compactPair, .comparison:
            return "\(currentResult.adjustedShutter.valueText) adjusted"
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
        Group {
            switch currentResult.layout {
            case .compactValue:
                compactValueBody
            case .compactPair:
                compactPairBody
            case .comparison:
                comparisonBody
            }
        }
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

    private var compactValueBody: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let note = currentResult.correctedExposure.detailText, !note.isEmpty {
                Text(note)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private var compactPairBody: some View {
        VStack(alignment: .leading, spacing: 10) {
            compactLine(
                title: currentResult.adjustedShutter.title,
                value: currentResult.adjustedShutter.valueText,
                valueColor: .primary
            )

            compactLine(
                title: currentResult.correctedExposure.title,
                value: currentResult.correctedExposure.valueText,
                valueColor: secondaryValueColor(for: currentResult.correctedExposure)
            )

            if let detailText = currentResult.correctedExposure.detailText, !detailText.isEmpty {
                Text(detailText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private var comparisonBody: some View {
        HStack(spacing: 12) {
            valueColumn(for: currentResult.adjustedShutter)

            Divider()

            valueColumn(for: currentResult.correctedExposure)
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

    private func compactLine(
        title: String,
        value: String,
        valueColor: Color
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(value)
                .font(.headline.weight(.semibold))
                .foregroundStyle(valueColor)
                .monospacedDigit()
                .minimumScaleFactor(0.8)
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

            Text("Corrected exposure vs adjusted shutter")
                .font(.subheadline)
                .foregroundStyle(.secondary)

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

                                if let unsupportedStart = graph.unsupportedRegionStartSeconds {
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

                                if let supportedRangeUpperBoundSeconds = graph.supportedRangeUpperBoundSeconds {
                                    supportedBoundary(
                                        at: supportedRangeUpperBoundSeconds,
                                        in: plotSize
                                    )
                                    .padding(plotInset)
                                }

                                if graph.kind == .table {
                                    tableAnchorMarkers(in: plotSize)
                                        .padding(plotInset)
                                }

                                if graph.usesCurrentInputGuideOnly,
                                   let currentMeteredExposureSeconds = graph.currentMeteredExposureSeconds {
                                    currentInputGuideOnly(
                                        currentMeteredExposureSeconds: currentMeteredExposureSeconds,
                                        in: plotSize
                                    )
                                    .padding(plotInset)
                                } else if let currentPoint = graph.currentPoint {
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
                            }
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

                FilmModeDetailsGraphStateNote(
                    symbol: graphExplanationSymbol,
                    tint: graphExplanationTint,
                    text: graphExplanationText
                )
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

        switch currentPoint.style {
        case .exact:
            Circle()
                .fill(Color.green)
                .frame(width: 14, height: 14)
                .overlay {
                    Circle()
                        .stroke(Color(.systemBackground), lineWidth: 2)
                }
                .position(plotted)
        case .estimated:
            Diamond()
                .fill(Color.blue)
                .frame(width: 15, height: 15)
                .overlay {
                    Diamond()
                        .stroke(Color.blue.opacity(0.25), lineWidth: 5)
                }
                .overlay {
                    Diamond()
                        .stroke(Color(.systemBackground), lineWidth: 2)
                }
                .position(plotted)
        case .extrapolated:
            Triangle()
                .fill(Color.orange)
                .frame(width: 16, height: 15)
                .overlay {
                    Triangle()
                        .stroke(Color(.systemBackground), lineWidth: 2)
                }
                .position(plotted)
        case .formulaDerived:
            Circle()
                .fill(Color.accentColor)
                .frame(width: 15, height: 15)
                .overlay {
                    Circle()
                        .stroke(Color(.systemBackground), lineWidth: 2)
                }
                .overlay {
                    Circle()
                        .stroke(Color.accentColor.opacity(0.3), lineWidth: 5)
                }
                    .position(plotted)
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
                return "Current point extrapolated"
            case .formulaDerived:
                return "Current point on formula curve"
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
            return [
                ("line.horizontal.3", .accentColor, "Formula curve"),
                ("circle.fill", .accentColor, "Current point")
            ]
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
            return ("triangle.fill", .orange, "Extrapolated")
        case .formulaDerived:
            return ("circle.fill", .accentColor, "Current point")
        }
    }

    private var graphExplanationSymbol: String {
        if graph.usesCurrentInputGuideOnly {
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
        case .none:
            return "info.circle"
        }
    }

    private var graphExplanationTint: Color {
        if graph.usesCurrentInputGuideOnly {
            return .orange
        }

        switch graph.currentPoint?.style {
        case .exact:
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
        if let unsupportedExplanation = graph.unsupportedExplanation {
            return unsupportedExplanation
        }

        return graph.caption
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
