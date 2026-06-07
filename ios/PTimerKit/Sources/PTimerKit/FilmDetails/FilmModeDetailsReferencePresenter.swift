import Foundation
import PTimerCore

/// Pure presenter for the Film Details "Reference" / "Source
/// reference" / "Guidance boundary" / "Sources" sections.
///
/// Owns the rendering policy for manufacturer published data:
/// no-correction band, source-evidence point anchors, range rows,
/// stop-signal boundaries, limited-guidance directives, and the
/// citation footer. Kept distinct from the graph presenter so a new
/// secondary-guidance kind (color filter, development directive,
/// note) can be added with no risk of disturbing the graph geometry.
public struct FilmModeDetailsReferencePresenter {
    public init() {}

    /// Bundle of input passed by the orchestrating presenter. Re-uses
    /// the closure-driven formatters owned by `ReciprocityModel` so
    /// the reference rows agree with the corrected-exposure card on
    /// duration formatting.
    public struct Input {
        public let bindingState: FilmModeReciprocityBindingState
        public let formatDuration: (Double) -> String
        public let formatDurationCoarse: (Double) -> String
        public init(bindingState: FilmModeReciprocityBindingState, formatDuration: @escaping (Double) -> String, formatDurationCoarse: @escaping (Double) -> String) {
            self.bindingState = bindingState
            self.formatDuration = formatDuration
            self.formatDurationCoarse = formatDurationCoarse
        }
    }

    // MARK: - Public entry points

    /// Builds the sections for formula-backed profiles. Splits
    /// manufacturer source-evidence rows into "Source reference"
    /// (quantified anchors + the no-correction band) and "Guidance
    /// boundary" (stop-signal-only rows). Always appends the
    /// "Sources" citation rows when the profile carries any.
    public func formulaSections(for input: Input) -> [FilmModeDetailsSectionState] {
        let evidenceSections = sourceEvidenceSections(for: input)
        let sourceRows = sourceDetailsRows(for: input.bindingState.profile)

        var sections: [FilmModeDetailsSectionState] = []
        sections.append(contentsOf: evidenceSections)
        if !sourceRows.isEmpty {
            sections.append(FilmModeDetailsSectionState(title: "Sources", rows: sourceRows))
        }
        return sections
    }

    /// Builds the sections for non-formula (limited-guidance preset)
    /// profiles: a single "Reference" block plus the citation footer.
    public func limitedGuidanceSections(for input: Input) -> [FilmModeDetailsSectionState] {
        let referenceRows = limitedGuidanceReferenceRows(for: input)
        let sourceRows = sourceDetailsRows(for: input.bindingState.profile)

        return [
            !referenceRows.isEmpty
                ? FilmModeDetailsSectionState(title: "Reference", rows: referenceRows)
                : nil,
            !sourceRows.isEmpty
                ? FilmModeDetailsSectionState(title: "Sources", rows: sourceRows)
                : nil,
        ]
        .compactMap { $0 }
    }

    // MARK: - Source evidence sections

    /// Splits manufacturer source-evidence rows into two display
    /// sections so a published reference point and a published
    /// stop-signal boundary never share the same visual category.
    ///
    /// - "Source reference" carries the threshold no-correction band
    ///   and any evidence row that publishes a quantified adjustment
    ///   (e.g. Provia 100F's 240 s +1/3 stop, 2.5G reference).
    /// - "Guidance boundary" carries evidence rows that publish only a
    ///   not-recommended warning (e.g. Provia 100F's 480 s boundary),
    ///   so the boundary never reads as a formula-fitting point.
    ///
    /// Profiles without `sourceEvidence` (HP5 Plus and the rest of
    /// the formula catalog today) produce neither section, preserving
    /// their existing layout.
    private func sourceEvidenceSections(for input: Input) -> [FilmModeDetailsSectionState] {
        let evidence = input.bindingState.profile.sourceEvidence
        guard !evidence.isEmpty else {
            return []
        }

        // Source reference rows are ordered by `SourceReferenceRowSortKey`
        // — ascending metered-exposure start value, then semantic row
        // kind (`pointAnchor` before `range` before `note`), then
        // catalog declaration order. The rule is shared rather than
        // CMS-specific; the CMS 20 II case where the 1/1000 s point
        // anchor shares a sortValue with the 1/1000 s … 1 s no-correction
        // band is one application of the kind-priority tiebreak, not
        // a CMS-only branch.
        let collected = collectSourceEvidenceRows(for: input)

        let referenceLines = collected.orderedLines
            .sorted { $0.key < $1.key }
            .map(\.columns)

        return buildSourceEvidenceSections(
            referenceLines: referenceLines,
            boundaryLines: collected.boundaryLines,
            hasEvidenceOnlyRows: collected.hasEvidenceOnlyRows
        )
    }

    private struct SourceEvidenceCollected {
        var orderedLines: [ReferenceRow]
        var boundaryLines: [[String]]
        var hasEvidenceOnlyRows: Bool
    }

    private func collectSourceEvidenceRows(for input: Input) -> SourceEvidenceCollected {
        var collected = SourceEvidenceCollected(
            orderedLines: [],
            boundaryLines: [],
            hasEvidenceOnlyRows: false
        )

        // Formula profiles surface their no-correction band from the
        // formula's own `noCorrectionThroughSeconds` guard (the
        // threshold rule was retired from formula profiles in
        // PTIMER-160). The renderer treats the band as a synthetic
        // 0 … noCorrectionThroughSeconds range row so the display
        // shape is unchanged.
        for rule in input.bindingState.profile.rules {
            if case let .formula(formulaRule) = rule {
                let upper = formulaRule.formula.noCorrectionThroughSeconds
                guard upper > 0 else { continue }
                collected.orderedLines.append(
                    ReferenceRow(
                        key: SourceReferenceRowSortKey(
                            sortValue: 0,
                            kind: .range,
                            catalogOffset: collected.orderedLines.count
                        ),
                        columns: sourceReferenceFormulaNoCorrectionColumns(
                            upperBoundSeconds: upper,
                            formatDuration: input.formatDuration
                        )
                    )
                )
            } else if case let .threshold(thresholdRule) = rule {
                collected.orderedLines.append(
                    ReferenceRow(
                        key: SourceReferenceRowSortKey(
                            sortValue: thresholdRule.noCorrectionRange.minimumSeconds,
                            kind: .range,
                            catalogOffset: collected.orderedLines.count
                        ),
                        columns: sourceReferenceThresholdColumns(
                            for: thresholdRule,
                            formatDuration: input.formatDuration
                        )
                    )
                )
            } else if case let .tableInterpolation(tableRule) = rule {
                // The table rule owns its no-correction band, mirroring
                // the formula path so the source-reference shape is the
                // same (a synthetic 0 … noCorrectionThroughSeconds row).
                let upper = tableRule.noCorrectionThroughSeconds
                guard upper > 0 else { continue }
                collected.orderedLines.append(
                    ReferenceRow(
                        key: SourceReferenceRowSortKey(
                            sortValue: 0,
                            kind: .range,
                            catalogOffset: collected.orderedLines.count
                        ),
                        columns: sourceReferenceFormulaNoCorrectionColumns(
                            upperBoundSeconds: upper,
                            formatDuration: input.formatDuration
                        )
                    )
                )
            }
        }

        for evidenceRow in input.bindingState.profile.sourceEvidence {
            guard var columns = compactReferenceColumns(
                meteredExposure: evidenceRow.meteredExposure,
                adjustments: evidenceRow.adjustments,
                formatDuration: input.formatDuration
            ) else {
                continue
            }
            if ReciprocitySourceEvidenceClassifier.isGuidanceBoundary(evidenceRow) {
                collected.boundaryLines.append(columns)
                continue
            }
            if evidenceRow.isSourceEvidenceOnly {
                columns.append(sourceEvidenceOnlyMarker)
                collected.hasEvidenceOnlyRows = true
            }
            let (sortValue, kind) = sortKey(for: evidenceRow.meteredExposure)
            collected.orderedLines.append(
                ReferenceRow(
                    key: SourceReferenceRowSortKey(
                        sortValue: sortValue,
                        kind: kind,
                        catalogOffset: collected.orderedLines.count
                    ),
                    columns: columns
                )
            )
        }
        return collected
    }

    private func sortKey(
        for meteredExposure: MeteredExposureSelector
    ) -> (sortValue: Double, kind: SourceReferenceRowKind) {
        switch meteredExposure {
        case let .exactSeconds(seconds):
            return (seconds, .pointAnchor)
        case let .range(range):
            return (range.minimumSeconds, .range)
        }
    }

    private func buildSourceEvidenceSections(
        referenceLines: [[String]],
        boundaryLines: [[String]],
        hasEvidenceOnlyRows: Bool
    ) -> [FilmModeDetailsSectionState] {
        var sections: [FilmModeDetailsSectionState] = []
        if !referenceLines.isEmpty {
            var value = formattedReferenceBlock(from: referenceLines)
            if hasEvidenceOnlyRows {
                value += "\n\n\(sourceEvidenceOnlyFootnoteText)"
            }
            sections.append(
                FilmModeDetailsSectionState(
                    title: "Source reference",
                    rows: [
                        FilmModeDetailsRowState(
                            title: "",
                            value: value,
                            style: .referenceBlock
                        ),
                    ]
                )
            )
        }
        if !boundaryLines.isEmpty {
            sections.append(
                FilmModeDetailsSectionState(
                    title: "Guidance boundary",
                    rows: [
                        FilmModeDetailsRowState(
                            title: "",
                            value: formattedReferenceBlock(from: boundaryLines),
                            style: .referenceBlock
                        ),
                    ]
                )
            )
        }
        return sections
    }

    /// Internal carrier used while sorting Source reference rows.
    /// Pairs the rendered columns with their `SourceReferenceRowSortKey`
    /// so the sort is driven by semantic row type (`pointAnchor`,
    /// `range`, …) instead of by label text or column width.
    private struct ReferenceRow {
        let key: SourceReferenceRowSortKey
        let columns: [String]
    }

    /// Marker appended as a final column to a Source reference row
    /// whose origin is `isSourceEvidenceOnly` — i.e. preserved as
    /// published evidence but not used as a calculation anchor.
    private var sourceEvidenceOnlyMarker: String { "*" }

    /// Footnote rendered below the Source reference block when at
    /// least one row carries the `*` marker. Worded for ADOX CMS 20
    /// II's 1/1000 sec evidence row: the manufacturer publishes it
    /// as +1/2 stop, but the calculation path stays no-correction
    /// across the entire sub-1 sec band.
    private var sourceEvidenceOnlyFootnoteText: String {
        "* Source evidence only. Not used as a fitting point; the calculation path stays no-correction across the sub-1s band."
    }

    // MARK: - Limited-guidance reference rows

    /// Reference rows shown for profiles that do not use a formula
    /// rule — today this is the limited-guidance preset path (Kodak
    /// Portra / Ektar / Ektachrome / Gold / Ultra Max). The block
    /// surfaces the manufacturer's threshold range plus any
    /// limited-guidance directive, then a generic "no quantified data
    /// published" line for the case where the input lands beyond the
    /// threshold.
    private func limitedGuidanceReferenceRows(for input: Input) -> [FilmModeDetailsRowState] {
        var lines: [[String]] = []

        for rule in input.bindingState.profile.rules {
            switch rule {
            case .threshold(let thresholdRule):
                lines.append(
                    compactThresholdReferenceColumns(
                        for: thresholdRule,
                        formatDuration: input.formatDuration
                    )
                )
            case .limitedGuidance(let rule):
                if let columns = compactLimitedGuidanceRuleColumns(
                    for: rule,
                    formatDuration: input.formatDuration
                ) {
                    lines.append(columns)
                }
            case .formula, .tableInterpolation:
                continue
            }
        }

        if !lines.isEmpty {
            return [
                FilmModeDetailsRowState(
                    title: "",
                    value: formattedReferenceBlock(from: lines),
                    style: .referenceBlock
                ),
            ]
        }

        if input.bindingState.presentation.category == .limitedGuidance
            || input.bindingState.presentation.category == .unsupported {
            return [
                FilmModeDetailsRowState(
                    title: "",
                    value: "Manufacturer does not publish quantified reciprocity data",
                    style: .referenceBlock
                ),
            ]
        }

        return []
    }

    // MARK: - Source citation rows

    /// Sources rows are rendered as an unlabeled list (one item per
    /// row) so the section reads like "Fujifilm · FUJICHROME PROVIA
    /// 100F — Long exposure guide / Provia 100F support page"
    /// without an extra Reference / Citation subdivision.
    private func sourceDetailsRows(for profile: ReciprocityProfile) -> [FilmModeDetailsRowState] {
        let source = profile.source
        var rows: [FilmModeDetailsRowState] = []

        let referenceComponents = [
            normalizedDetailText(source.publisher),
            normalizedDetailText(source.title),
            normalizedDetailText(source.sourceVersion).map { "Version \($0)" },
        ]
        .compactMap { $0 }

        if !referenceComponents.isEmpty {
            rows.append(
                FilmModeDetailsRowState(
                    title: "",
                    value: referenceComponents.joined(separator: " · ")
                )
            )
        }

        if let citationText = normalizedDetailText(source.citation) {
            rows.append(
                FilmModeDetailsRowState(
                    title: "",
                    value: citationText,
                    destinationURL: parseUsableURL(citationText)
                )
            )
        }

        return rows
    }

    // MARK: - Column formatting

    private func compactThresholdReferenceColumns(
        for rule: ThresholdReciprocityRule,
        formatDuration: (Double) -> String
    ) -> [String] {
        let upperBound = rule.noCorrectionRange.maximumSeconds
        let lowerBound = rule.noCorrectionRange.minimumSeconds

        if lowerBound <= 0, let upperBound {
            return ["<= \(formatDuration(upperBound))", "No correction"]
        }

        if let upperBound {
            return ["\(formatDuration(lowerBound))-\(formatDuration(upperBound))", "No correction"]
        }

        return [">= \(formatDuration(lowerBound))", "No correction"]
    }

    /// Threshold row formatter for the formula "Source reference"
    /// section. Mirrors `compactThresholdReferenceColumns` but uses
    /// the user-facing "No correction range" wording from the design
    /// so the row reads as a published reference band rather than a
    /// single boundary. The limited-guidance "Reference" path keeps
    /// the shorter "No correction" label.
    private func sourceReferenceThresholdColumns(
        for rule: ThresholdReciprocityRule,
        formatDuration: (Double) -> String
    ) -> [String] {
        let upperBound = rule.noCorrectionRange.maximumSeconds
        let lowerBound = rule.noCorrectionRange.minimumSeconds

        if lowerBound <= 0, let upperBound {
            return [
                sourceReferenceThresholdUpperBoundLabel(
                    for: upperBound,
                    formatDuration: formatDuration
                ),
                "No correction range",
            ]
        }

        if let upperBound {
            return ["\(formatDuration(lowerBound))-\(formatDuration(upperBound))", "No correction range"]
        }

        return [">= \(formatDuration(lowerBound))", "No correction range"]
    }

    /// Upper-bound label for the Source reference threshold row.
    /// Threshold rules that sit one ε below a round value (e.g. Acros
    /// II's 119.999999, used so the +1/2 stop formula fires at
    /// exactly 120 s) render as strict "< 120s" rather than the
    /// literal "<= 119.999999s". Rules whose upper bound is the round
    /// value itself (Provia 100F's 128 s, Velvia 50's 1 s) keep the
    /// inclusive "<= X" wording so the boundary value still reads as
    /// no-correction.
    private func sourceReferenceThresholdUpperBoundLabel(
        for upperBound: Double,
        formatDuration: (Double) -> String
    ) -> String {
        let ceiling = ceil(upperBound)
        let gap = ceiling - upperBound
        if gap > 0, gap < 1e-3 {
            return "< \(formatDuration(ceiling))"
        }
        return "<= \(formatDuration(upperBound))"
    }

    /// Formula no-correction band row for the formula "Source
    /// reference" section. The formula owns its `noCorrectionThroughSeconds`
    /// guard inclusively, so the row reads as "<= upper, No correction
    /// range" mirroring the legacy threshold-rule row format.
    private func sourceReferenceFormulaNoCorrectionColumns(
        upperBoundSeconds: Double,
        formatDuration: (Double) -> String
    ) -> [String] {
        let label = sourceReferenceThresholdUpperBoundLabel(
            for: upperBoundSeconds,
            formatDuration: formatDuration
        )
        return [label, "No correction range"]
    }

    /// Shared formatter for the source-evidence reference block. Keeps
    /// the metered-exposure + secondary-guidance layout consistent for
    /// formula-backed profiles with manufacturer reference points.
    private func compactReferenceColumns(
        meteredExposure: MeteredExposureSelector,
        adjustments: [ReciprocityAdjustment],
        formatDuration: (Double) -> String
    ) -> [String]? {
        let meteredText = meteredExposureSelectorText(meteredExposure, formatDuration: formatDuration)

        // Combined stop/multiplier · correctedTime cell. When a row
        // carries both a stopDelta (or multiplier) and a correctedTime
        // — as Kodak's TRI-X / T-MAX tables and the FOMA / ADOX
        // multiplier tables do — both facts are shown together so
        // neither half of the published source is hidden. correctedTime
        // values flagged `isApproximate` — rounded fractional-stop
        // derivations like T-MAX 100 1 sec — are prefixed with "≈".
        // Multiplier-derived corrected times are exact arithmetic and
        // render without the marker.
        let exposureText = combinedExposureColumn(
            adjustments: adjustments,
            formatDuration: formatDuration
        )

        let developmentText = adjustments.compactMap { adjustment -> String? in
            guard case let .development(development) = adjustment else {
                return nil
            }

            return compactDevelopmentReferenceText(from: development.instruction)
        }.first

        // Surface color filter notation and stop-signal warnings alongside the
        // source-row metered text so the rendered reference block preserves the
        // mapping between metered exposure and secondary guidance.
        let colorCorrectionText = adjustments.compactMap { adjustment -> String? in
            guard case let .colorFilter(filter) = adjustment else { return nil }
            return filter.filterName
        }.first

        let stopSignalText: String? = adjustments.contains { adjustment in
            if case let .warning(warning) = adjustment, warning.severity == .notRecommended {
                return true
            }
            return false
        } ? "Not recommended" : nil

        if let exposureText {
            // Existing rule: development beats color correction when both exist on
            // the same entry (the launch catalog never mixes them today; preference
            // is documented to keep behavior deterministic).
            let secondaryText = developmentText ?? colorCorrectionText
            let detailColumns = [exposureText, secondaryText].compactMap { $0 }
            return [meteredText] + detailColumns
        }

        // Warning-only entries (Velvia 50's "64 sec is not recommended.") have no
        // exposure adjustment; surface them with the metered row so the user can
        // see WHICH metered exposure the source flags.
        if let stopSignalText {
            return [meteredText, stopSignalText]
        }

        // Note-only entries (RETRO 80S / SUPERPAN 200 range-valued rows where the
        // data sheet specifies the corrected exposure as a range like "1 to 2 sec")
        // carry only a `.note(text:)` adjustment so the range never enters the
        // formula as an exact fitting point. Surface the published note text
        // alongside the metered exposure so the user still sees the source
        // guidance for that row.
        let noteText = adjustments.compactMap { adjustment -> String? in
            guard case let .note(note) = adjustment else { return nil }
            return note.text
        }.first
        if let noteText {
            return [meteredText, noteText]
        }

        return nil
    }

    /// Limited-guidance rules (e.g. Ektachrome E100's CC10R at 10s+)
    /// expose published reference guidance for a metered range.
    /// Surface them in the Reference data block so the user sees WHICH
    /// metered exposure the guidance applies to, instead of hiding the
    /// rule.
    private func compactLimitedGuidanceRuleColumns(
        for rule: LimitedGuidanceReciprocityRule,
        formatDuration: (Double) -> String
    ) -> [String]? {
        guard let appliesRange = rule.appliesWhenMetered else { return nil }
        let meteredText = meteredExposureSelectorText(.range(appliesRange), formatDuration: formatDuration)

        if let colorRow = rule.adjustments.compactMap({ adjustment -> (String, String?)? in
            guard case let .colorFilter(filter) = adjustment else { return nil }
            return (filter.filterName, filter.note)
        }).first {
            let trimmedNote = colorRow.1?.trimmingCharacters(in: .whitespacesAndNewlines)
            let value: String
            if let trimmedNote, !trimmedNote.isEmpty {
                value = "\(colorRow.0) — \(trimmedNote)"
            } else {
                value = colorRow.0
            }
            return [meteredText, "Color correction", value]
        }

        if rule.adjustments.contains(where: { adjustment in
            if case let .warning(warning) = adjustment, warning.severity == .notRecommended {
                return true
            }
            return false
        }) {
            return [meteredText, "Not recommended"]
        }

        if let developmentRow = rule.adjustments.compactMap({ adjustment -> String? in
            guard case let .development(development) = adjustment else { return nil }
            return development.instruction
        }).first {
            return [meteredText, "Development adjustment", developmentRow]
        }

        return nil
    }

    /// Combined "stop or multiplier · corrected time" column.
    ///
    /// The reference table's value column is intentionally compact; on
    /// rows where the source publishes (or the catalog stores) both a
    /// stop/multiplier directive and a corrected-time mapping, the user
    /// benefits from seeing both — the stop/multiplier names what the
    /// source said, and the corrected time names the resulting exposure
    /// value the photographer will actually use.
    ///
    /// - When only one form is present, returns that form alone.
    /// - When both are present, joins them with `" · "`.
    /// - When the corrected time is `isApproximate` (a rounded display
    ///   of an irrational fractional-stop derivation), prefixes its
    ///   formatted value with `"≈"`. Multiplier-derived corrected
    ///   times are exact arithmetic and are not marked.
    private func combinedExposureColumn(
        adjustments: [ReciprocityAdjustment],
        formatDuration: (Double) -> String
    ) -> String? {
        var stopOrMultiplierText: String?
        var correctedTimeText: String?

        for adjustment in adjustments {
            guard case let .exposure(exposureAdjustment) = adjustment else { continue }
            switch exposureAdjustment {
            case .correctedTime(let mapping):
                let formatted = formatDuration(mapping.correctedSeconds)
                correctedTimeText = mapping.isApproximate ? "≈\(formatted)" : formatted
            case .stopDelta(let adjustment):
                if stopOrMultiplierText == nil {
                    stopOrMultiplierText = formattedStopDelta(adjustment.stopDelta)
                }
            case .multiplier(let adjustment):
                if stopOrMultiplierText == nil {
                    stopOrMultiplierText = "\(formatCompactNumber(adjustment.factor))x"
                }
            }
        }

        switch (stopOrMultiplierText, correctedTimeText) {
        case let (.some(stop), .some(corrected)):
            return "\(stop) · \(corrected)"
        case let (.some(stop), .none):
            return stop
        case let (.none, .some(corrected)):
            return corrected
        case (.none, .none):
            return nil
        }
    }

    private func compactDevelopmentReferenceText(from instruction: String) -> String {
        let trimmedInstruction = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        let pattern = #"^([+-]?\d+%)\s+development$"#

        if let range = trimmedInstruction.range(of: pattern, options: .regularExpression) {
            let matched = String(trimmedInstruction[range])
            let percentage = matched.replacingOccurrences(
                of: pattern,
                with: "$1",
                options: .regularExpression
            )
            return "Dev \(percentage)"
        }

        return trimmedInstruction
    }

    private func formattedReferenceBlock(from lines: [[String]]) -> String {
        let columnCount = lines.map(\.count).max() ?? 0
        let spacing = "    "
        let widths = (0..<max(columnCount - 1, 0)).map { columnIndex in
            lines
                .compactMap { $0.indices.contains(columnIndex) ? $0[columnIndex] : nil }
                .map(\.count)
                .max() ?? 0
        }

        return lines.map { columns in
            columns.enumerated().map { index, column in
                guard index < widths.count else {
                    return column
                }

                let paddingWidth = max(widths[index] - column.count, 0)
                return column + String(repeating: " ", count: paddingWidth) + spacing
            }
            .joined()
            .trimmingCharacters(in: .whitespaces)
        }
        .joined(separator: "\n")
    }

    private func meteredExposureSelectorText(
        _ selector: MeteredExposureSelector,
        formatDuration: (Double) -> String
    ) -> String {
        switch selector {
        case .exactSeconds(let seconds):
            return formatDuration(seconds)
        case .range(let range):
            let lower = formatDuration(range.minimumSeconds)
            if let maximumSeconds = range.maximumSeconds {
                return "\(lower)-\(formatDuration(maximumSeconds))"
            }
            return "\(lower)+"
        }
    }

    private func formattedStopDelta(_ value: Double) -> String {
        let absolute = abs(value)
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 0
        let magnitude = formatter.string(from: NSNumber(value: absolute)) ?? String(absolute)
        let sign = value >= 0 ? "+" : "-"
        return "\(sign)\(magnitude) stop" + (abs(absolute - 1) < ExposureCalculator.stabilityEpsilon ? "" : "s")
    }

    private func formatCompactNumber(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = value >= 10 ? 1 : 2
        formatter.minimumFractionDigits = 0
        formatter.decimalSeparator = "."
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "%.1f", value)
    }

    private func normalizedDetailText(_ text: String?) -> String? {
        guard let text else {
            return nil
        }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func parseUsableURL(_ value: String) -> URL? {
        guard let url = URL(string: value),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              url.host != nil else {
            return nil
        }

        return url
    }
}
