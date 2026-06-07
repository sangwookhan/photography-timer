import XCTest
import PTimerKit
import PTimerCore
@testable import PTimer

/// Behavior contract for Rollei still-film reciprocity profiles.
///
/// **RPX 100 / RPX 400** (PTIMER-168): migrated from a formula fit to
/// a `.tableInterpolation` rule backed by the manufacturer's published
/// corrected-time table. Anchors reproduce exactly; log-log
/// interpolation is used between anchors; inputs above the last anchor
/// are classified `.unsupportedOutOfPolicyRange` with a non-nil
/// log-log-extrapolated value.
///
/// **RETRO 80S / SUPERPAN 200**: still use the original
/// formula-based profile (`.formula` rule, `isConvertedFormulaProfile`
/// == true). Range-valued rows at 1 s and 2 s live as source-evidence
/// notes and must never enter the formula as exact fitting points.
final class RolleiFormulaProfileTests: XCTestCase {

    private let evaluator = ReciprocityCalculationPolicyEvaluator()

    // MARK: - Shared data types

    private struct RolleiPublishedRow {
        let metered: Double
        let corrected: Double
    }

    // MARK: - RPX table profiles (PTIMER-168)

    private struct RPXTableFit {
        let canonicalStockName: String
        let profileID: String
        let noCorrectionThroughSeconds: Double
        let sourceRangeThroughSeconds: Double
        let anchors: [RolleiPublishedRow]
    }

    private let rpx100Table = RPXTableFit(
        canonicalStockName: "RPX 100",
        profileID: "rollei-rpx-100-official-table",
        noCorrectionThroughSeconds: 1.0,
        sourceRangeThroughSeconds: 30,
        anchors: [
            RolleiPublishedRow(metered: 2, corrected: 3),
            RolleiPublishedRow(metered: 5, corrected: 8),
            RolleiPublishedRow(metered: 10, corrected: 25),
            RolleiPublishedRow(metered: 20, corrected: 75),
            RolleiPublishedRow(metered: 30, corrected: 150),
        ]
    )

    private let rpx400Table = RPXTableFit(
        canonicalStockName: "RPX 400",
        profileID: "rollei-rpx-400-official-table",
        noCorrectionThroughSeconds: 0.5,
        sourceRangeThroughSeconds: 20,
        anchors: [
            RolleiPublishedRow(metered: 1, corrected: 2),
            RolleiPublishedRow(metered: 5, corrected: 10),
            RolleiPublishedRow(metered: 10, corrected: 30),
            RolleiPublishedRow(metered: 15, corrected: 55),
            RolleiPublishedRow(metered: 20, corrected: 80),
        ]
    )

    private var allRPXFits: [RPXTableFit] { [rpx100Table, rpx400Table] }

    // MARK: - Formula profiles (unchanged from PTIMER-168 scope)

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

    private var allFormulaFits: [RolleiFit] { [retro80s, superpan200] }

    // MARK: - PTIMER-168 migration invariant

    /// RPX 100 and RPX 400 were migrated to table interpolation.
    /// RETRO 80S and SUPERPAN 200 were NOT — they must still be
    /// converted-formula profiles, not table-interpolation profiles.
    func testRPXProfilesAreNowTableInterpolationAndRetroRemainsFormula() throws {
        for fit in allRPXFits {
            let profile = try rpxProfile(for: fit)
            XCTAssertTrue(
                profile.usesTableInterpolation,
                "\(fit.canonicalStockName) must be a table-interpolation profile after PTIMER-168."
            )
            XCTAssertFalse(
                profile.isConvertedFormulaProfile,
                "\(fit.canonicalStockName) must not still read as a converted-formula profile."
            )
        }

        // At least RETRO 80S remains formula-based (out of scope for PTIMER-168).
        let retro80sProfile = try profile(for: retro80s)
        XCTAssertTrue(
            retro80sProfile.isConvertedFormulaProfile,
            "RETRO 80S must remain a converted-formula profile; PTIMER-168 only migrated RPX."
        )
        XCTAssertFalse(
            retro80sProfile.usesTableInterpolation,
            "RETRO 80S must not be a table profile."
        )
    }

    // MARK: - RPX table rule structure

    func testRPXProfilesHaveTableInterpolationRuleAndNoFormulaRule() throws {
        for fit in allRPXFits {
            let profile = try rpxProfile(for: fit)

            let hasFormula = profile.rules.contains { rule in
                if case .formula = rule { return true }
                return false
            }
            XCTAssertFalse(
                hasFormula,
                "\(fit.canonicalStockName) must have no .formula rule after migration."
            )

            let tableRule = profile.rules.compactMap { rule -> TableInterpolationReciprocityRule? in
                if case let .tableInterpolation(r) = rule { return r }
                return nil
            }.first
            XCTAssertNotNil(
                tableRule,
                "\(fit.canonicalStockName) must carry a .tableInterpolation rule."
            )
        }
    }

    func testRPXTableRuleNoCorrectionAndSourceRangeBoundaries() throws {
        for fit in allRPXFits {
            let profile = try rpxProfile(for: fit)
            let rule = try XCTUnwrap(
                profile.rules.compactMap { rule -> TableInterpolationReciprocityRule? in
                    if case let .tableInterpolation(r) = rule { return r }
                    return nil
                }.first,
                "\(fit.canonicalStockName) must have a tableInterpolation rule."
            )

            XCTAssertEqual(
                rule.noCorrectionThroughSeconds,
                fit.noCorrectionThroughSeconds,
                accuracy: 1e-9,
                "\(fit.canonicalStockName) noCorrectionThroughSeconds mismatch."
            )
            XCTAssertEqual(
                rule.sourceRangeThroughSeconds,
                fit.sourceRangeThroughSeconds,
                accuracy: 1e-9,
                "\(fit.canonicalStockName) sourceRangeThroughSeconds mismatch."
            )
            XCTAssertEqual(
                rule.anchors.count,
                fit.anchors.count,
                "\(fit.canonicalStockName) must have \(fit.anchors.count) anchors."
            )
        }
    }

    func testRPXTableRuleModelBasis() throws {
        for fit in allRPXFits {
            let profile = try rpxProfile(for: fit)
            let basis = try XCTUnwrap(
                profile.modelBasis,
                "\(fit.canonicalStockName) must declare an explicit modelBasis."
            )
            XCTAssertEqual(
                basis.sourceModel,
                .manufacturerTable,
                "\(fit.canonicalStockName) sourceModel must be .manufacturerTable."
            )
            XCTAssertEqual(
                basis.calculationModel,
                .tableLogLogInterpolation,
                "\(fit.canonicalStockName) calculationModel must be .tableLogLogInterpolation."
            )
        }
    }

    func testRPXProfileIDAndName() throws {
        let rpx100 = try rpxProfile(for: rpx100Table)
        XCTAssertEqual(rpx100.id, "rollei-rpx-100-official-table")
        XCTAssertEqual(rpx100.name, "Official Rollei table")

        let rpx400 = try rpxProfile(for: rpx400Table)
        XCTAssertEqual(rpx400.id, "rollei-rpx-400-official-table")
        XCTAssertEqual(rpx400.name, "Official Rollei table")
    }

    // MARK: - RPX evaluator: no-correction boundary

    func testRPXNoCorrectionBelowAndAtThreshold() throws {
        for fit in allRPXFits {
            let profile = try rpxProfile(for: fit)

            let atThreshold = evaluator.evaluate(
                profile: profile,
                meteredExposureSeconds: fit.noCorrectionThroughSeconds
            )
            XCTAssertEqual(
                atThreshold.metadata.basis,
                .officialThresholdNoCorrection,
                "\(fit.canonicalStockName) at \(fit.noCorrectionThroughSeconds) s must be .officialThresholdNoCorrection."
            )
            XCTAssertEqual(
                try XCTUnwrap(atThreshold.correctedExposureSeconds),
                fit.noCorrectionThroughSeconds,
                accuracy: 1e-9,
                "\(fit.canonicalStockName) corrected must equal metered within no-correction band."
            )

            let belowThreshold = evaluator.evaluate(
                profile: profile,
                meteredExposureSeconds: fit.noCorrectionThroughSeconds * 0.5
            )
            XCTAssertEqual(
                belowThreshold.metadata.basis,
                .officialThresholdNoCorrection,
                "\(fit.canonicalStockName) below threshold must also be .officialThresholdNoCorrection."
            )
        }
    }

    // MARK: - RPX evaluator: anchor rows reproduce exactly

    func testRPXAnchorsAreReproducedExactlyWithTableLogLogDerivedBasis() throws {
        for fit in allRPXFits {
            let profile = try rpxProfile(for: fit)
            for anchor in fit.anchors {
                let result = evaluator.evaluate(
                    profile: profile,
                    meteredExposureSeconds: anchor.metered
                )
                XCTAssertEqual(
                    result.metadata.basis,
                    .tableLogLogDerived,
                    "\(fit.canonicalStockName) at anchor \(anchor.metered) s must be .tableLogLogDerived."
                )
                let corrected = try XCTUnwrap(
                    result.correctedExposureSeconds,
                    "\(fit.canonicalStockName) corrected exposure must be non-nil at anchor \(anchor.metered) s."
                )
                XCTAssertEqual(
                    corrected,
                    anchor.corrected,
                    accuracy: 1e-4,
                    "\(fit.canonicalStockName) anchor at \(anchor.metered) s must reproduce \(anchor.corrected) s exactly."
                )
            }
        }
    }

    // MARK: - RPX evaluator: beyond source range

    func testRPXAboveSourceRangeIsBeyondPolicyWithNonNilExtrapolatedValue() throws {
        for fit in allRPXFits {
            let profile = try rpxProfile(for: fit)
            let metered = fit.sourceRangeThroughSeconds * 3
            let result = evaluator.evaluate(profile: profile, meteredExposureSeconds: metered)

            XCTAssertEqual(
                result.metadata.basis,
                .unsupportedOutOfPolicyRange,
                "\(fit.canonicalStockName) at \(metered) s must be classified .unsupportedOutOfPolicyRange."
            )
            let corrected = try XCTUnwrap(
                result.correctedExposureSeconds,
                "\(fit.canonicalStockName) corrected must be non-nil (log-log extrapolation) past source range."
            )
            let lastAnchorCorrected = fit.anchors.last!.corrected
            XCTAssertGreaterThan(
                corrected,
                lastAnchorCorrected,
                "\(fit.canonicalStockName) beyond-range extrapolation must exceed the last anchor corrected time."
            )
        }
    }

    // MARK: - RETRO 80S / SUPERPAN 200: formula range (unchanged)

    func testFormulaProfilesQuantifiedPublishedRowsAreFormulaDerived() throws {
        for fit in allFormulaFits {
            let p = try profile(for: fit)
            for row in fit.quantifiedRows {
                let result = evaluator.evaluate(profile: p, meteredExposureSeconds: row.metered)
                XCTAssertEqual(
                    result.metadata.basis,
                    .formulaDerived,
                    "\(fit.canonicalStockName) at quantified row \(row.metered) s must be formula-derived."
                )
            }
        }
    }

    func testFormulaProfilesFormulaTracksPublishedQuantifiedRowsWithinDocumentedTolerance() throws {
        for fit in allFormulaFits {
            let p = try profile(for: fit)
            for row in fit.quantifiedRows {
                let result = evaluator.evaluate(profile: p, meteredExposureSeconds: row.metered)
                let corrected = try XCTUnwrap(result.correctedExposureSeconds)
                let stopError = log2(corrected / row.corrected)
                XCTAssertEqual(
                    stopError,
                    0,
                    accuracy: fit.stopTolerancePerQuantifiedRow,
                    "\(fit.canonicalStockName) at \(row.metered) s formula prediction (\(corrected) s) must stay within \(fit.stopTolerancePerQuantifiedRow) stop of \(row.corrected) s; got error \(stopError) stop."
                )
            }
        }
    }

    func testFormulaProfilesFormulaUsesFreeLogLogCoefficient() throws {
        for fit in allFormulaFits {
            let p = try profile(for: fit)
            let formulaRule = try XCTUnwrap(p.rules.compactMap { rule -> FormulaReciprocityRule? in
                guard case let .formula(rule) = rule else { return nil }
                return rule
            }.first)

            XCTAssertEqual(formulaRule.formula.exponent, fit.exponent, accuracy: 1e-3, "\(fit.canonicalStockName) exponent mismatch")
            let coefficient = formulaRule.formula.coefficientSeconds
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

    // MARK: - Beyond the published source range — formula profiles

    func testFormulaProfilesAboveUpperPublishedRowBecomesBeyondSourceNumericGuidance() throws {
        for fit in allFormulaFits {
            let p = try profile(for: fit)
            let metered = fit.formulaUpperBoundSeconds * 3
            let result = evaluator.evaluate(profile: p, meteredExposureSeconds: metered)
            XCTAssertEqual(
                result.metadata.basis,
                .unsupportedOutOfPolicyRange,
                "\(fit.canonicalStockName) at \(metered) s must be marked outside manufacturer guidance."
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
            let p = try profile(for: fit)
            for rangeRow in fit.rangeNoteRows {
                let evidenceRow = try XCTUnwrap(
                    p.sourceEvidence.first(where: { row in
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
                    "\(fit.canonicalStockName) range-valued row at \(rangeRow.metered) s must not carry a quantified exposure adjustment."
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
        for fit in [retro80s, superpan200] {
            let p = try profile(for: fit)
            let formulaRule = try XCTUnwrap(p.rules.compactMap { rule -> FormulaReciprocityRule? in
                guard case let .formula(rule) = rule else { return nil }
                return rule
            }.first)
            XCTAssertEqual(formulaRule.formula.exponent, 1.5361, accuracy: 1e-3)
            XCTAssertEqual(formulaRule.formula.coefficientSeconds, 0.9601, accuracy: 1e-3)
        }
    }

    // MARK: - Source-evidence preservation (all four Rollei films)

    func testRPXProfilesSourceEvidencePreservesEveryAnchorInOrder() throws {
        for fit in allRPXFits {
            let p = try rpxProfile(for: fit)
            let exactMetereds = p.sourceEvidence.compactMap { row -> Double? in
                if case let .exactSeconds(seconds) = row.meteredExposure { return seconds }
                return nil
            }
            let expected = fit.anchors.map { $0.metered }.sorted()
            XCTAssertEqual(
                exactMetereds.sorted(),
                expected,
                "\(fit.canonicalStockName) must keep every published anchor row as source evidence."
            )
        }
    }

    func testRPXProfilesSourceEvidenceAnchorRowsKeepCorrectedTime() throws {
        for fit in allRPXFits {
            let p = try rpxProfile(for: fit)
            let expected = Dictionary(uniqueKeysWithValues: fit.anchors.map { ($0.metered, $0.corrected) })
            for row in p.sourceEvidence {
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

    func testFormulaProfilesSourceEvidencePreservesEveryPublishedRowInOrder() throws {
        for fit in allFormulaFits {
            let p = try profile(for: fit)
            let exactMetereds = p.sourceEvidence.compactMap { row -> Double? in
                if case let .exactSeconds(seconds) = row.meteredExposure { return seconds }
                return nil
            }
            let expected = (fit.rangeNoteRows.map { $0.metered } + fit.quantifiedRows.map { $0.metered }).sorted()
            XCTAssertEqual(
                exactMetereds.sorted(),
                expected,
                "\(fit.canonicalStockName) must keep every Rollei-published row as source evidence."
            )
        }
    }

    func testFormulaProfilesSourceEvidenceQuantifiedRowsKeepCorrectedTime() throws {
        for fit in allFormulaFits {
            let p = try profile(for: fit)
            let expected = Dictionary(uniqueKeysWithValues: fit.quantifiedRows.map { ($0.metered, $0.corrected) })
            for row in p.sourceEvidence {
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

    func testAllRolleiProfilesKeepOfficialManufacturerPublishedSource() throws {
        for fit in allRPXFits {
            let p = try rpxProfile(for: fit)
            XCTAssertEqual(p.source.kind, .manufacturerPublished)
            XCTAssertEqual(p.source.authority, .official)
            XCTAssertEqual(p.source.publisher, "Rollei")
        }
        for fit in allFormulaFits {
            let p = try profile(for: fit)
            XCTAssertEqual(p.source.kind, .manufacturerPublished)
            XCTAssertEqual(p.source.authority, .official)
            XCTAssertEqual(p.source.publisher, "Rollei")
        }
    }

    // MARK: - UI surfacing — RPX table profiles

    @MainActor
    func testRPXProfilesDetailsSurfaceShowsSourceReferenceWithCorrectedTimeRows() throws {
        for fit in allRPXFits {
            let displayState = try makeDisplayState(
                film: fit.canonicalStockName,
                meteredExposureSeconds: fit.anchors.first?.metered ?? 2
            )

            let sourceReferenceSection = try XCTUnwrap(
                displayState.sections.first(where: { $0.title == "Source reference" }),
                "\(fit.canonicalStockName) must surface a Source reference section."
            )
            let sourceBlock = try XCTUnwrap(sourceReferenceSection.rows.first?.value)

            for anchor in fit.anchors {
                let correctedToken = formatDurationToken(anchor.corrected)
                XCTAssertTrue(
                    sourceBlock.contains(correctedToken),
                    "\(fit.canonicalStockName) source block must surface the published corrected time '\(correctedToken)'. Got:\n\(sourceBlock)"
                )
            }
            XCTAssertFalse(
                displayState.sections.contains(where: { $0.title == "Reference" }),
                "\(fit.canonicalStockName) must not surface the legacy Reference section."
            )
            XCTAssertFalse(
                displayState.sections.contains(where: { $0.title == "Guidance boundary" }),
                "RPX profiles publish no not-recommended row; Guidance boundary section must be absent."
            )
        }
    }

    @MainActor
    func testRPXProfilesInRangeSummaryTextIsLogLogInterpolationOfOfficialTable() throws {
        for fit in allRPXFits {
            let displayState = try makeDisplayState(
                film: fit.canonicalStockName,
                meteredExposureSeconds: fit.anchors.first?.metered ?? 2
            )
            XCTAssertEqual(
                displayState.summary.summaryText,
                "Log-log interpolation of the official table",
                "\(fit.canonicalStockName) within-range summary text mismatch."
            )
        }
    }

    @MainActor
    func testRPXProfilesAboveSourceRangeSummaryTextIsBeyondSourceRange() throws {
        for fit in allRPXFits {
            let metered = fit.sourceRangeThroughSeconds * 2
            let displayState = try makeDisplayState(
                film: fit.canonicalStockName,
                meteredExposureSeconds: metered
            )
            XCTAssertEqual(
                displayState.summary.summaryText,
                "Beyond source range",
                "\(fit.canonicalStockName) beyond-range summary text mismatch."
            )
        }
    }

    @MainActor
    func testRPXProfilesGraphCarriesSourceReferenceMarkersAtAnchorRowsAndFormulaKind() throws {
        for fit in allRPXFits {
            let displayState = try makeDisplayState(
                film: fit.canonicalStockName,
                meteredExposureSeconds: fit.anchors.first?.metered ?? 2
            )
            let graph = try XCTUnwrap(displayState.graph)
            XCTAssertEqual(
                graph.kind,
                .formula,
                "\(fit.canonicalStockName) table models must render as the .formula graph kind."
            )

            let markerMetereds = graph.sourceReferenceMarkers.map { $0.point.meteredExposureSeconds.rounded() }
            XCTAssertEqual(
                Set(markerMetereds),
                Set(fit.anchors.map { $0.metered }),
                "\(fit.canonicalStockName) graph must mark all published anchor rows."
            )

            XCTAssertNil(
                graph.notRecommendedBoundarySeconds,
                "\(fit.canonicalStockName) has no published not-recommended boundary."
            )

            let beyondStart = try XCTUnwrap(
                graph.beyondSourceRangeStartSeconds,
                "\(fit.canonicalStockName) graph must shade the region above the published \(fit.sourceRangeThroughSeconds) s upper row."
            )
            XCTAssertEqual(beyondStart, fit.sourceRangeThroughSeconds, accuracy: 1e-3)
        }
    }

    // MARK: - UI surfacing — RETRO 80S / SUPERPAN 200 (formula, unchanged)

    @MainActor
    func testFormulaProfilesDetailsSurfaceShowsSourceReferenceWithCorrectedTimeRows() throws {
        for fit in allFormulaFits {
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
    func testFormulaProfilesGraphCarriesSourceReferenceMarkersAtQuantifiedRows() throws {
        for fit in allFormulaFits {
            let displayState = try makeDisplayState(
                film: fit.canonicalStockName,
                meteredExposureSeconds: fit.quantifiedRows.first?.metered ?? 4
            )
            let graph = try XCTUnwrap(displayState.graph)
            XCTAssertEqual(graph.kind, .formula, "\(fit.canonicalStockName) must render the formula graph kind.")

            let markerMetereds = graph.sourceReferenceMarkers.map { $0.point.meteredExposureSeconds.rounded() }
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

    private func rpxProfile(for fit: RPXTableFit) throws -> ReciprocityProfile {
        try FormulaProfileTestSupport.profile(for: fit.canonicalStockName)
    }

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
