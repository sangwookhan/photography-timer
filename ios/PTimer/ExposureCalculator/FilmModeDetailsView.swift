import SwiftUI
import UIKit

/// FilmModeDetailsView contains the bottom-sheet rendering for the
/// film mode reciprocity details surface (UI Spec §2.6). The graph
/// itself lives in `FilmModeDetailsGraphView.swift` with its
/// rendering helpers in `FilmModeDetailsGraphRendering.swift`; this
/// file owns the sheet shell and the non-graph blocks (sticky
/// summary, current result, section cards, legend).
///
/// Only `FilmModeDetailsSheet` is internal — it is the entry point
/// the screen renders. Every other type stays file-private because
/// it is a helper used exclusively by `FilmModeDetailsSheet`.

/// Stable initial detent for the Reciprocity Details bottom sheet.
/// Using a single named constant ensures every profile type (official,
/// unofficial, formula, limited-guidance) presents the sheet at the
/// same initial height.
private let reciprocityDetailsInitialDetent: PresentationDetent = .fraction(0.85)

struct FilmModeDetailsSheet: View {
    let details: FilmModeDetailsDisplayState
    @State private var scrollOffset: CGFloat = 0
    @State private var selectedDetent: PresentationDetent = reciprocityDetailsInitialDetent
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    /// The sheet uses an explicit top-left close button so
    /// dismissal is reachable without the drag-down gesture. The
    /// button replaces no other content — every block below the
    /// navigation bar stays unchanged.
    @Environment(\.dismiss) private var dismiss

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
                    } else if details.summary.tone != .limitedGuidance {
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
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.body.weight(.semibold))
                            .accessibilityLabel("Close")
                    }
                    .accessibilityIdentifier("film-mode-details-close")
                }
            }
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

    /// Sections that describe manufacturer source evidence or
    /// custom-profile provenance. Placed directly under the
    /// reference graph so the user can read each plotted element
    /// (source reference, guidance boundary, the limited-guidance
    /// "Reference" block) or the custom profile metadata
    /// (Source / Formula / Range / Notes / Reference URL) without
    /// scrolling past the profile metadata first.
    private func isEvidenceSection(_ section: FilmModeDetailsSectionState) -> Bool {
        switch section.title {
        case "Source reference", "Guidance boundary", "Reference", "Custom profile":
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
        case .limitedGuidance:
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
        case .limitedGuidance:
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
        case .limitedGuidance:
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
        case .unsupported, .limitedGuidance:
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
