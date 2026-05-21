import XCTest
@testable import PTimer

/// Behavior contract for Rollei's four still-film reciprocity
/// profiles (RPX 100, RPX 400, RETRO 80S, SUPERPAN 200) after
/// conversion from corrected-time tables to formula-based
/// prediction. Locks the invariants:
///
/// - The published threshold band stays unchanged.
/// - Above the threshold and up to and including the highest
///   published row, the formula wins (basis == `.formulaDerived`).
///   Above the upper-published row the formula continues as
///   numeric continuation outside the published source range.
/// - RETRO 80S and SUPERPAN 200 publish corrected exposure as a
///   range at 1 sec and 2 sec. Those range-valued rows live as
///   source-evidence notes — they MUST NOT enter the formula as
///   exact fitting points.
/// - All published rows stay visible as `sourceEvidence`.
final class RolleiFormulaProfileTests: XCTestCase {

    private let evaluator = ReciprocityCalculationPolicyEvaluator()

    private struct RolleiPublishedRow {
        let metered: Double
        let corrected: Double
    }

    private struct RolleiFit {
        let canonicalStockName: String
        let coefficient: Double
        let exponent: Double
        let thresholdMaximumSeconds: Double
        let formulaUpperBoundSeconds: Double
        let quantifiedRows: [RolleiPublishedRow]
        let rangeNoteRows: [(metered: Double, marker: String)]
        let stopTolerancePerQuantifiedRow: Double
    }

    private let rpx100 = RolleiFit(
        canonicalStockName: "RPX 100",
        coefficient: 0.9248,
        exponent: 1.4652,
        thresholdMaximumSeconds: 1,
        formulaUpperBoundSeconds: 30,
        quantifiedRows: [
            RolleiPublishedRow(metered: 2, corrected: 3),
            RolleiPublishedRow(metered: 5, corrected: 8),
            RolleiPublishedRow(metered: 10, corrected: 25),
            RolleiPublishedRow(metered: 20, corrected: 75),
            RolleiPublishedRow(metered: 30, corrected: 150),
        ],
        rangeNoteRows: [],
        stopTolerancePerQuantifiedRow: 0.35
    )

    private let rpx400 = RolleiFit(
        canonicalStockName: "RPX 400",
        coefficient: 1.7708,
        exponent: 1.2404,
        thresholdMaximumSeconds: 0.5,
        formulaUpperBoundSeconds: 20,
        quantifiedRows: [
            RolleiPublishedRow(metered: 1, corrected: 2),
            RolleiPublishedRow(metered: 5, corrected: 10),
            RolleiPublishedRow(metered: 10, corrected: 30),
            RolleiPublishedRow(metered: 15, corrected: 55),
            RolleiPublishedRow(metered: 20, corrected: 80),
        ],
        rangeNoteRows: [],
        stopTolerancePerQuantifiedRow: 0.45
    )

    private let retro80s = RolleiFit(
        canonicalStockName: "RETRO 80S",
        coefficient: 0.9601,
        exponent: 1.5361,
        thresholdMaximumSeconds: 0.5,
        formulaUpperBoundSeconds: 30,
        quantifiedRows: [
            RolleiPublishedRow(metered: 4, corrected: 8),
            RolleiPublishedRow(metered: 8, corrected: 24),
            RolleiPublishedRow(metered: 15, corrected: 60),
            RolleiPublishedRow(metered: 30, corrected: 180),
        ],
        rangeNoteRows: [
            (metered: 1, marker: "1 to 2"),
            (metered: 2, marker: "3 to 4"),
        ],
        stopTolerancePerQuantifiedRow: 0.05
    )

    private let superpan200 = RolleiFit(
        canonicalStockName: "SUPERPAN 200",
        coefficient: 0.9601,
        exponent: 1.5361,
        thresholdMaximumSeconds: 0.5,
        formulaUpperBoundSeconds: 30,
        quantifiedRows: [
            RolleiPublishedRow(metered: 4, corrected: 8),
            RolleiPublishedRow(metered: 8, corrected: 24),
            RolleiPublishedRow(metered: 15, corrected: 60),
            RolleiPublishedRow(metered: 30, corrected: 180),
        ],
        rangeNoteRows: [
            (metered: 1, marker: "1 to 2"),
            (metered: 2, marker: "3 to 4"),
        ],
        stopTolerancePerQuantifiedRow: 0.05
    )

    private var allFits: [RolleiFit] { [rpx100, rpx400, retro80s, superpan200] }

    // MARK: - Formula range — quantified rows are source-backed predictions

    func testRolleiProfilesQuantifiedPublishedRowsAreFormulaDerived() throws {
        for fit in allFits {
            let profile = try profile(for: fit)
            for row in fit.quantifiedRows {
                let result = evaluator.evaluate(profile: profile, meteredExposureSeconds: row.metered)
                XCTAssertEqual(
                    result.metadata.basis,
                    .formulaDerived,
                    "\(fit.canonicalStockName) at quantified row \(row.metered) s must be formula-derived, never resurrected as an exact-table point."
                )
            }
        }
    }

    func testRolleiProfilesFormulaTracksPublishedQuantifiedRowsWithinDocumentedTolerance() throws {
        for fit in allFits {
            let profile = try profile(for: fit)
            for row in fit.quantifiedRows {
                let result = evaluator.evaluate(profile: profile, meteredExposureSeconds: row.metered)
                let corrected = try XCTUnwrap(result.correctedExposureSeconds)
                let stopError = log2(corrected / row.corrected)
                XCTAssertEqual(
                    stopError,
                    0,
                    accuracy: fit.stopTolerancePerQuantifiedRow,
                    "\(fit.canonicalStockName) at \(row.metered) s formula prediction (\(corrected) s) must stay within \(fit.stopTolerancePerQuantifiedRow) stop of Rollei's published row (\(row.corrected) s); got error \(stopError) stop."
                )
            }
        }
    }

    func testRolleiProfilesFormulaUsesFreeLogLogCoefficient() throws {
        for fit in allFits {
            let profile = try profile(for: fit)
            let formulaRule = try XCTUnwrap(profile.rules.compactMap { rule -> FormulaReciprocityRule? in
                guard case let .formula(rule) = rule else { return nil }
                return rule
            }.first)

            XCTAssertEqual(formulaRule.formula.kind, .exponentPower)
            XCTAssertEqual(formulaRule.formula.exponent, fit.exponent, accuracy: 1e-3, "\(fit.canonicalStockName) exponent mismatch")
            let coefficient = try XCTUnwrap(formulaRule.formula.coefficient)
            XCTAssertEqual(coefficient, fit.coefficient, accuracy: 1e-3, "\(fit.canonicalStockName) coefficient mismatch")

            let note = try XCTUnwrap(formulaRule.notes.first)
            XCTAssertTrue(
                note.lowercased().contains("log-log"),
                "\(fit.canonicalStockName) formula note must label the fit as log-log; got: \(note)"
            )
            XCTAssertTrue(
                note.lowercased().contains("numeric continuation"),
                "\(fit.canonicalStockName) formula note must describe values above the upper row as numeric continuation; got: \(note)"
            )
        }
    }

    // MARK: - Beyond the published source range (continuation)

    func testRolleiProfilesAboveUpperPublishedRowBecomesBeyondSourceNumericGuidance() throws {
        for fit in allFits {
            let profile = try profile(for: fit)
            let metered = fit.formulaUpperBoundSeconds * 3
            let result = evaluator.evaluate(profile: profile, meteredExposureSeconds: metered)
            XCTAssertEqual(
                result.metadata.basis,
                .unsupportedOutOfPolicyRange,
                "\(fit.canonicalStockName) at \(metered) s sits above the published \(fit.formulaUpperBoundSeconds) s upper row and must be marked outside manufacturer guidance."
            )
            let corrected = try XCTUnwrap(
                result.correctedExposureSeconds,
                "\(fit.canonicalStockName) at \(metered) s must keep a numeric continuation past the source range."
            )
            let expected = fit.coefficient * pow(metered, fit.exponent)
            XCTAssertEqual(corrected, expected, accuracy: expected * 0.01)
        }
    }

    // MARK: - Range-valued rows stay source-only (RETRO 80S / SUPERPAN 200)

    func testRetro80SAndSuperpan200RangeValuedRowsAreSourceEvidenceNotFormulaFittingPoints() throws {
        for fit in [retro80s, superpan200] {
            let profile = try profile(for: fit)
            // Each range-valued row is preserved as a sourceEvidence
            // row carrying ONLY a .note adjustment — never as a
            // quantified exposure adjustment that the formula could
            // pick up as a fitting point.
            for rangeRow in fit.rangeNoteRows {
                let evidenceRow = try XCTUnwrap(
                    profile.sourceEvidence.first(where: { row in
                        if case let .exactSeconds(seconds) = row.meteredExposure {
                            return abs(seconds - rangeRow.metered) < 1e-6
                        }
                        return false
                    }),
                    "\(fit.canonicalStockName) must preserve the \(rangeRow.metered) s range-valued row as source evidence."
                )

                let hasQuantifiedExposure = evidenceRow.adjustments.contains { adjustment in
                    switch adjustment {
                    case .exposure: return true
                    default: return false
                    }
                }
                XCTAssertFalse(
                    hasQuantifiedExposure,
                    "\(fit.canonicalStockName) range-valued row at \(rangeRow.metered) s must not carry a quantified exposure adjustment (the corrected exposure is a range, not a single value)."
                )

                let hasMatchingNote = evidenceRow.adjustments.contains { adjustment in
                    if case let .note(note) = adjustment {
                        return note.text.contains(rangeRow.marker)
                    }
                    return false
                }
                XCTAssertTrue(
                    hasMatchingNote,
                    "\(fit.canonicalStockName) range-valued row at \(rangeRow.metered) s must preserve the published \(rangeRow.marker) sec range as a note."
                )
            }
        }
    }

    func testRetro80SAndSuperpan200FormulaIsFitOnlyFromQuantifiedRows() throws {
        // The formula coefficient/exponent must match the fit
        // through the four quantified rows (4/8/15/30 sec). If the
        // range-valued rows had been forced into the fit, the
        // exponent and coefficient would drift visibly. This locks
        // the contract that range rows stay source-only.
        for fit in [retro80s, superpan200] {
            let profile = try profile(for: fit)
            let formulaRule = try XCTUnwrap(profile.rules.compactMap { rule -> FormulaReciprocityRule? in
                guard case let .formula(rule) = rule else { return nil }
                return rule
            }.first)
            XCTAssertEqual(formulaRule.formula.exponent, 1.5361, accuracy: 1e-3)
            XCTAssertEqual(formulaRule.formula.coefficient ?? 0, 0.9601, accuracy: 1e-3)
        }
    }

    // MARK: - Source-evidence preservation

    func testRolleiProfilesSourceEvidencePreservesEveryPublishedRowInOrder() throws {
        for fit in allFits {
            let profile = try profile(for: fit)
            let exactMetereds = profile.sourceEvidence.compactMap { row -> Double? in
                if case let .exactSeconds(seconds) = row.meteredExposure { return seconds }
                return nil
            }
            let expected = (fit.rangeNoteRows.map { $0.metered } + fit.quantifiedRows.map { $0.metered }).sorted()
            XCTAssertEqual(
                exactMetereds.sorted(),
                expected,
                "\(fit.canonicalStockName) must keep every Rollei-published row as source evidence (quantified and range-valued combined)."
            )
        }
    }

    func testRolleiProfilesSourceEvidenceQuantifiedRowsKeepCorrectedTime() throws {
        for fit in allFits {
            let profile = try profile(for: fit)
            let expected = Dictionary(uniqueKeysWithValues: fit.quantifiedRows.map { ($0.metered, $0.corrected) })
            for row in profile.sourceEvidence {
                guard case let .exactSeconds(metered) = row.meteredExposure else { continue }
                guard let expectedCorrected = expected[metered] else { continue }
                let correctedSeconds = row.adjustments.compactMap { adjustment -> Double? in
                    guard case let .exposure(.correctedTime(mapping)) = adjustment else { return nil }
                    return mapping.correctedSeconds
                }.first
                XCTAssertEqual(
                    correctedSeconds ?? -1,
                    expectedCorrected,
                    accuracy: 1e-6,
                    "\(fit.canonicalStockName) source evidence at \(metered) s must keep the published corrected time (\(expectedCorrected) s)."
                )
            }
        }
    }

    func testRolleiProfilesKeepOfficialManufacturerPublishedSource() throws {
        for fit in allFits {
            let profile = try profile(for: fit)
            XCTAssertEqual(profile.source.kind, .manufacturerPublished)
            XCTAssertEqual(profile.source.authority, .official)
            XCTAssertEqual(profile.source.publisher, "Rollei")
        }
    }

    // MARK: - UI surfacing

    @MainActor
    func testRolleiProfilesDetailsSurfaceShowsSourceReferenceWithCorrectedTimeRows() throws {
        for fit in allFits {
            let displayState = try makeDisplayState(
                film: fit.canonicalStockName,
                meteredExposureSeconds: fit.quantifiedRows.first?.metered ?? 4
            )

            let sourceReferenceSection = try XCTUnwrap(
                displayState.sections.first(where: { $0.title == "Source reference" }),
                "\(fit.canonicalStockName) must surface a Source reference section after conversion."
            )
            let sourceBlock = try XCTUnwrap(sourceReferenceSection.rows.first?.value)

            for row in fit.quantifiedRows {
                let correctedToken = formatDurationToken(row.corrected)
                XCTAssertTrue(
                    sourceBlock.contains(correctedToken),
                    "\(fit.canonicalStockName) source block must surface the published corrected time '\(correctedToken)'. Got:\n\(sourceBlock)"
                )
            }
            XCTAssertFalse(
                displayState.sections.contains(where: { $0.title == "Reference" }),
                "Converted \(fit.canonicalStockName) must not surface the legacy Reference section."
            )
            XCTAssertFalse(
                displayState.sections.contains(where: { $0.title == "Guidance boundary" }),
                "Rollei profiles publish no not-recommended row; Guidance boundary section must be absent."
            )
        }
    }

    @MainActor
    func testRetro80SAndSuperpan200SourceReferenceSurfacesPublishedRangeNotes() throws {
        // RETRO 80S and SUPERPAN 200 publish corrected exposure as a
        // range at 1 sec ("1 to 2 sec") and 2 sec ("3 to 4 sec").
        // Those rows live as note-only source evidence and never
        // enter the formula as exact fitting points, but the
        // published range guidance must still be visible to the user
        // in the Source reference block.
        for fit in [retro80s, superpan200] {
            let displayState = try makeDisplayState(
                film: fit.canonicalStockName,
                meteredExposureSeconds: 4
            )
            let sourceReferenceSection = try XCTUnwrap(
                displayState.sections.first(where: { $0.title == "Source reference" }),
                "\(fit.canonicalStockName) must surface a Source reference section that includes the range-valued rows."
            )
            let sourceBlock = try XCTUnwrap(sourceReferenceSection.rows.first?.value)

            for rangeRow in fit.rangeNoteRows {
                XCTAssertTrue(
                    sourceBlock.contains(rangeRow.marker),
                    "\(fit.canonicalStockName) source block must surface the published '\(rangeRow.marker) sec' range note for the \(rangeRow.metered) sec row. Got:\n\(sourceBlock)"
                )
            }

            let meteredOneSecToken = formatDurationToken(1)
            XCTAssertTrue(
                sourceBlock.contains(meteredOneSecToken),
                "\(fit.canonicalStockName) source block must surface the 1 sec metered row that carries the range note. Got:\n\(sourceBlock)"
            )
        }
    }

    @MainActor
    func testRolleiProfilesGraphCarriesSourceReferenceMarkersAtQuantifiedRows() throws {
        for fit in allFits {
            let displayState = try makeDisplayState(
                film: fit.canonicalStockName,
                meteredExposureSeconds: fit.quantifiedRows.first?.metered ?? 4
            )
            let graph = try XCTUnwrap(displayState.graph)
            XCTAssertEqual(graph.kind, .formula, "\(fit.canonicalStockName) must render the formula graph kind after conversion.")

            let markerMetereds = graph.sourceReferenceMarkers.map { $0.point.meteredExposureSeconds.rounded() }
            // Only the quantified rows surface as graph markers (the
            // range-valued rows have no single corrected exposure to
            // plot and must never be invented as exact fitting points).
            XCTAssertEqual(
                Set(markerMetereds),
                Set(fit.quantifiedRows.map { $0.metered }),
                "\(fit.canonicalStockName) graph must mark Rollei's quantified rows and exclude range-valued rows."
            )

            XCTAssertNil(
                graph.notRecommendedBoundarySeconds,
                "\(fit.canonicalStockName) has no published not-recommended boundary."
            )

            let beyondStart = try XCTUnwrap(
                graph.beyondSourceRangeStartSeconds,
                "\(fit.canonicalStockName) graph must shade the region above the published \(fit.formulaUpperBoundSeconds) s upper row."
            )
            XCTAssertEqual(beyondStart, fit.formulaUpperBoundSeconds + 1e-6, accuracy: 1e-3)
        }
    }

    // MARK: - Helpers

    private func profile(for fit: RolleiFit) throws -> ReciprocityProfile {
        try FormulaProfileTestSupport.profile(for: fit.canonicalStockName)
    }

    @MainActor
    private func makeDisplayState(
        film canonicalStockName: String,
        meteredExposureSeconds: Double
    ) throws -> FilmModeDetailsDisplayState {
        try FormulaProfileTestSupport.makeDisplayState(
            film: canonicalStockName,
            meteredExposureSeconds: meteredExposureSeconds
        )
    }

    /// Matches the presenter's compact-duration formatter used in the
    /// Source reference column. Whole-second values render as "Ns",
    /// fractional ones as "N.Ns". The shared test-support layer passes
    /// "%.1fs" to the presenter, so a corrected time of 8 renders as
    /// "8.0s". Match that to keep the assertion exact.
    private func formatDurationToken(_ seconds: Double) -> String {
        String(format: "%.1fs", seconds)
    }
}
