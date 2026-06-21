// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import Foundation
import PTimerCore

/// Pure presenter for the "App-derived comparison" section in
/// Reciprocity Details (PTIMER-159).
///
/// For a formula profile that also carries manufacturer
/// source-evidence anchors with a published corrected time, it
/// compares the app's guarded-formula output against each published
/// anchor and reports the percent and stop difference.
///
/// This is APP-DERIVED data, kept strictly separate from the
/// source-only "Source reference" section: the published anchors stay
/// source material; these deltas are the app's own comparison and are
/// never presented as manufacturer-published guidance.
///
/// Returns `nil` when the profile has no formula rule or no
/// corrected-time anchors. The section is rendered only for models
/// enrolled in `AlternateReciprocityModels.isAppDerivedModel` (the
/// gate lives in `FilmModeDetailsPresenter`), so it appears solely on
/// approved app-derived models with source anchors.
public struct ReciprocityModelComparisonPresenter {
    public init() {}

    public static let sectionTitle = "App-derived comparison"

    public func comparisonSection(
        for profile: ReciprocityProfile,
        formatDuration: (Double) -> String
    ) -> FilmModeDetailsSectionState? {
        guard let formula = formula(in: profile) else { return nil }

        let dataRows = profile.sourceEvidence.compactMap { evidence in
            comparisonColumns(for: evidence, formula: formula, formatDuration: formatDuration)
        }
        guard !dataRows.isEmpty else { return nil }

        let table = Self.formattedTable(
            header: ["Metered", "Source", "App", "Error"],
            rows: dataRows
        )
        return FilmModeDetailsSectionState(
            title: Self.sectionTitle,
            rows: [
                // Aligned monospaced table so the user can scan
                // metered / source / app / error at a glance.
                FilmModeDetailsRowState(title: "", value: table, style: .referenceBlock),
                FilmModeDetailsRowState(
                    title: "",
                    value: "App-derived comparison against published source points. Not manufacturer-published guidance."
                ),
            ]
        )
    }

    /// One table row: [Metered, Source, App, Error]. `nil` when the
    /// anchor lacks a published corrected time or a usable app value.
    private func comparisonColumns(
        for evidence: ReciprocitySourceEvidenceRow,
        formula: ReciprocityFormula,
        formatDuration: (Double) -> String
    ) -> [String]? {
        guard case let .exactSeconds(meteredSeconds) = evidence.meteredExposure,
              let publishedSeconds = publishedCorrectedSeconds(for: evidence, meteredSeconds: meteredSeconds),
              publishedSeconds > 0,
              let appSeconds = formulaCorrectedSeconds(formula, meteredSeconds: meteredSeconds) else {
            return nil
        }
        let percentDelta = (appSeconds - publishedSeconds) / publishedSeconds * 100
        let stopDelta = log2(appSeconds / publishedSeconds)
        return [
            formatDuration(meteredSeconds),
            formatDuration(publishedSeconds),
            formatDuration(appSeconds),
            "\(signedPercent(percentDelta)), \(signedStops(stopDelta))",
        ]
    }

    /// Left-aligns every column to the widest cell (header included)
    /// so the monospaced reference-block renders as an aligned table.
    /// The trailing (Error) column is not padded.
    public static func formattedTable(header: [String], rows: [[String]]) -> String {
        let allRows = [header] + rows
        let columnCount = header.count
        var widths = [Int](repeating: 0, count: columnCount)
        for row in allRows {
            for (index, cell) in row.enumerated() where index < columnCount {
                widths[index] = max(widths[index], cell.count)
            }
        }
        func render(_ row: [String]) -> String {
            row.enumerated().map { index, cell in
                index == columnCount - 1
                    ? cell
                    : cell.padding(toLength: widths[index], withPad: " ", startingAt: 0)
            }
            .joined(separator: "  ")
        }
        return allRows.map(render).joined(separator: "\n")
    }

    private func formula(in profile: ReciprocityProfile) -> ReciprocityFormula? {
        for rule in profile.rules {
            if case let .formula(formulaRule) = rule {
                return formulaRule.formula
            }
        }
        return nil
    }

    /// Corrected exposure the app's shared evaluator produces, so the
    /// comparison uses identical math to the runtime and the graph.
    private func formulaCorrectedSeconds(
        _ formula: ReciprocityFormula,
        meteredSeconds: Double
    ) -> Double? {
        switch formula.evaluate(meteredExposureSeconds: meteredSeconds) {
        case let .withinSourceRange(correctedExposureSeconds),
             let .beyondSourceRange(correctedExposureSeconds):
            return correctedExposureSeconds
        case .noCorrection:
            return meteredSeconds
        case .invalidInput, .invalidFormula, .formulaOutputUnusable, .unsafeShorteningFormula:
            return nil
        }
    }

    /// Published corrected time for a source row. Prefers an explicit
    /// corrected time, then a published multiplier, then a stop delta —
    /// the same source data the "Source reference" section renders, read
    /// here only to anchor the app-derived comparison.
    ///
    /// The priority is applied across ALL of the row's exposure
    /// adjustments, not first-match: rows like T-MAX 100's
    /// "10 s → +1/2 stop, corrected 15 s" list the stop delta before
    /// the corrected time, and the comparison must anchor on the
    /// published 15 s — not the 2^0.5-derived 14.1 s.
    private func publishedCorrectedSeconds(
        for evidence: ReciprocitySourceEvidenceRow,
        meteredSeconds: Double
    ) -> Double? {
        var multiplierSeconds: Double?
        var stopDeltaSeconds: Double?
        for adjustment in evidence.adjustments {
            guard case let .exposure(exposure) = adjustment else { continue }
            switch exposure {
            case let .correctedTime(mapping):
                return mapping.correctedSeconds
            case let .multiplier(multiplier):
                if multiplierSeconds == nil {
                    multiplierSeconds = meteredSeconds * multiplier.factor
                }
            case let .stopDelta(stop):
                if stopDeltaSeconds == nil {
                    stopDeltaSeconds = meteredSeconds * pow(2, stop.stopDelta)
                }
            }
        }
        return multiplierSeconds ?? stopDeltaSeconds
    }

    private func signedPercent(_ value: Double) -> String {
        String(format: "%+.1f%%", value)
    }

    private func signedStops(_ value: Double) -> String {
        "\(String(format: "%+.3f", value)) stop"
    }
}
