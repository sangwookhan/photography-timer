import XCTest
@testable import PTimer

/// Behavior contract for Kodak Tri-X 400's default table-interpolation
/// reciprocity profile and its two alternate models.
///
/// DEFAULT profile (`kodak-tri-x-official-graph-table`, "Official Kodak
/// graph/table"):
/// - Eleven anchors derived from Kodak's E-31 table and published graph
///   samples. The three published rows (1→2, 10→50, 100→1200) are also
///   stored as source evidence; the graph-sampled points are
///   calculation-only anchors, not source evidence.
/// - noCorrectionThroughSeconds = 0.1 (Kodak lists no adjustment through
///   1/10 sec); sourceRangeThroughSeconds = 100.
/// - modelBasis: sourceModel `.manufacturerTable`, calculationModel
///   `.tableLogLogInterpolation`.
///
/// Evaluator invariants (all three models share the same policy):
/// - metered <= 0.1 s → basis `.officialThresholdNoCorrection`, Tc = Tm.
/// - 0.1 < metered <= 100 s → basis `.tableLogLogDerived`; each anchor
///   reproduces exactly; between anchors log-log interpolation applies.
/// - metered > 100 s → basis `.unsupportedOutOfPolicyRange`; corrected
///   is non-nil (log-log extrapolation > 1200 s).
///
/// ALTERNATES (`AlternateReciprocityModels.alternates(forFilmID: "kodak-tri-x-400")`):
/// 1. "Official Kodak table" (`kodak-tri-x-official-table`): 3-anchor
///    table (1→2, 10→50, 100→1200); same noc/sourceRange as default.
/// 2. "App formula" (`kodak-tri-x-app-formula`): formula rule
///    (2 × Tm^1.3891, noc 0.1, sourceRange 100); modelBasis
///    `.manufacturerTable`/`.guardedFormula`; enrolled as app-derived.
final class TriX400TableProfileTests: XCTestCase {

    private let evaluator = ReciprocityCalculationPolicyEvaluator()

    // MARK: - Rule structure

    func testTriX400HasTableInterpolationRuleAndNoFormulaRule() throws {
        let profile = try triX400Profile()

        let tableRule = profile.rules.compactMap { rule -> TableInterpolationReciprocityRule? in
            if case let .tableInterpolation(r) = rule { return r } else { return nil }
        }.first
        XCTAssertNotNil(tableRule, "Tri-X 400 must carry a .tableInterpolation rule after migration.")

        let hasFormulaRule = profile.rules.contains { rule in
            if case .formula = rule { return true } else { return false }
        }
        XCTAssertFalse(hasFormulaRule, "Tri-X 400 must NOT carry a .formula rule after migration to table.")
    }

    func testTriX400TableRuleParametersMatchPublishedAnchors() throws {
        let profile = try triX400Profile()
        XCTAssertEqual(profile.id, "kodak-tri-x-official-graph-table",
            "Default profile id must be 'kodak-tri-x-official-graph-table'.")
        XCTAssertEqual(profile.name, "Official Kodak graph/table",
            "Default profile name must be 'Official Kodak graph/table'.")

        let tableRule = try XCTUnwrap(
            profile.rules.compactMap { rule -> TableInterpolationReciprocityRule? in
                if case let .tableInterpolation(r) = rule { return r } else { return nil }
            }.first,
            "tableInterpolation rule must be present."
        )

        XCTAssertEqual(tableRule.noCorrectionThroughSeconds, 0.1, accuracy: 1e-9,
            "noCorrectionThroughSeconds must be 0.1 (Kodak E-31 lists no adjustment through 1/10 sec).")
        XCTAssertEqual(tableRule.sourceRangeThroughSeconds, 100, accuracy: 1e-6,
            "sourceRangeThroughSeconds must be 100.")

        // 11 anchors: 3 published rows + 8 graph-sampled points.
        XCTAssertEqual(tableRule.anchors.count, 11,
            "Default graph/table profile must carry 11 anchors (3 published + 8 graph samples).")

        // The three published rows must be present.
        let anchors = Dictionary(uniqueKeysWithValues: tableRule.anchors.map { ($0.meteredSeconds, $0.correctedSeconds) })
        XCTAssertEqual(anchors[1] ?? -1, 2, accuracy: 1e-4, "Published anchor: 1 s → 2 s.")
        XCTAssertEqual(anchors[10] ?? -1, 50, accuracy: 1e-4, "Published anchor: 10 s → 50 s.")
        XCTAssertEqual(anchors[100] ?? -1, 1200, accuracy: 1e-4, "Published anchor: 100 s → 1200 s.")

        // The graph-sampled points must also be present.
        XCTAssertEqual(anchors[2] ?? -1, 5, accuracy: 1e-4, "Graph sample: 2 s → 5 s.")
        XCTAssertEqual(anchors[3] ?? -1, 10, accuracy: 1e-4, "Graph sample: 3 s → 10 s.")
        XCTAssertEqual(anchors[5] ?? -1, 20, accuracy: 1e-4, "Graph sample: 5 s → 20 s.")
        XCTAssertEqual(anchors[7] ?? -1, 32, accuracy: 1e-4, "Graph sample: 7 s → 32 s.")
        XCTAssertEqual(anchors[20] ?? -1, 120, accuracy: 1e-4, "Graph sample: 20 s → 120 s.")
        XCTAssertEqual(anchors[30] ?? -1, 200, accuracy: 1e-4, "Graph sample: 30 s → 200 s.")
        XCTAssertEqual(anchors[50] ?? -1, 420, accuracy: 1e-4, "Graph sample: 50 s → 420 s.")
        XCTAssertEqual(anchors[70] ?? -1, 720, accuracy: 1e-4, "Graph sample: 70 s → 720 s.")
    }

    func testTriX400ModelBasisIsManufacturerTableLogLogInterpolation() throws {
        let profile = try triX400Profile()
        let basis = try XCTUnwrap(profile.modelBasis,
            "Tri-X 400 profile must carry a modelBasis after migration.")
        XCTAssertEqual(basis.sourceModel, .manufacturerTable)
        XCTAssertEqual(basis.calculationModel, .tableLogLogInterpolation)
    }

    // MARK: - No-correction boundary (inclusive at 1/10 sec)

    func testTriX400AtAndBelowTenthSecondReturnsOfficialNoCorrection() throws {
        let profile = try triX400Profile()
        for metered in [0.01, 0.05, 0.1] {
            let result = evaluator.evaluate(profile: profile, meteredExposureSeconds: metered)
            XCTAssertEqual(
                result.metadata.basis,
                .officialThresholdNoCorrection,
                "\(metered) sec is within the 1/10 sec no-correction band and must not pick up a table correction."
            )
            let corrected = try XCTUnwrap(result.correctedExposureSeconds)
            XCTAssertEqual(corrected, metered, accuracy: 1e-6)
        }
    }

    /// PTIMER-168 boundary tolerance: a nominal 1/10 sec UI input can
    /// evaluate to ~0.102 sec after Base Shutter / ND stop arithmetic.
    /// It must classify as No correction, while values clearly above
    /// 1/10 sec (0.12 / 0.15 sec) stay table-derived and corrected.
    func testTriX400NominalTenthSecondToleranceClassifiesNoCorrection() throws {
        let profile = try triX400Profile()

        // Nominal 1/10 sec drifted upward by stop arithmetic.
        let nominal = evaluator.evaluate(profile: profile, meteredExposureSeconds: 0.102)
        XCTAssertEqual(
            nominal.metadata.basis,
            .officialThresholdNoCorrection,
            "Nominal 1/10 sec (~0.102 sec) must read as No correction, not table-derived."
        )
        XCTAssertEqual(try XCTUnwrap(nominal.correctedExposureSeconds), 0.102, accuracy: 1e-6)

        // Values clearly above 1/10 sec must remain corrected.
        for metered in [0.12, 0.15] {
            let result = evaluator.evaluate(profile: profile, meteredExposureSeconds: metered)
            XCTAssertEqual(
                result.metadata.basis,
                .tableLogLogDerived,
                "\(metered) sec is clearly above the 1/10 sec band and must stay table-derived."
            )
            XCTAssertGreaterThan(try XCTUnwrap(result.correctedExposureSeconds), metered)
        }
    }

    /// Regression for the manual-test failure: inputs between 1/10 sec
    /// and 1 sec used to read as No correction (when the band ran to
    /// ~1 sec). They must now be table-derived — interpolated from the
    /// 0.1 sec knee toward the 1 sec → 2 sec anchor, and longer than the
    /// metered value (no vertical step at 1 sec).
    func testTriX400BetweenTenthAndOneSecondIsTableDerivedNotNoCorrection() throws {
        let profile = try triX400Profile()
        for metered in [0.2, 0.5, 0.672, 0.9] {
            let result = evaluator.evaluate(profile: profile, meteredExposureSeconds: metered)
            XCTAssertEqual(
                result.metadata.basis,
                .tableLogLogDerived,
                "\(metered) sec sits above the 0.1 sec no-correction knee and must be table-derived, not No correction."
            )
            let corrected = try XCTUnwrap(result.correctedExposureSeconds)
            XCTAssertGreaterThan(
                corrected,
                metered,
                "\(metered) sec must receive a reciprocity correction (corrected > metered)."
            )
            XCTAssertLessThan(
                corrected,
                2,
                "Between 0.1 sec and 1 sec the value must interpolate below the 1 sec → 2 sec anchor."
            )
        }

        // Explicit pin for the exact manual-test value.
        let result = evaluator.evaluate(profile: profile, meteredExposureSeconds: 0.672)
        XCTAssertNotEqual(result.metadata.basis, .officialThresholdNoCorrection,
            "0.672 sec must NOT return No correction.")
        XCTAssertEqual(try XCTUnwrap(result.correctedExposureSeconds), 1.192, accuracy: 0.01,
            "0.672 sec interpolates to ≈ 1.19 sec from the 0.1 sec knee toward the 1 sec → 2 sec anchor.")
    }

    func testTriX400BoundaryAt1SecondAppliesTableAnchorWithoutStep() throws {
        // 1 sec is a published anchor (→ 2 sec). With the no-correction
        // band ending at 0.1 sec, the curve rises smoothly to it (the
        // approach from 0.9 sec is just under 2 sec), so 1 sec is
        // table-derived and reproduces 2 sec exactly — no vertical jump.
        let profile = try triX400Profile()
        let result = evaluator.evaluate(profile: profile, meteredExposureSeconds: 1)

        XCTAssertEqual(
            result.metadata.basis,
            .tableLogLogDerived,
            "1 sec is a published anchor and must be table-derived, not No correction."
        )
        let corrected = try XCTUnwrap(result.correctedExposureSeconds)
        XCTAssertEqual(corrected, 2, accuracy: 1e-4,
            "Table anchor at 1 sec must reproduce Kodak's published 2 sec corrected exposure exactly.")
    }

    // MARK: - Table range (1 sec … 100 sec, source-backed)

    func testTriX400InsideTableRangeIsTableLogLogDerivedAcrossPublishedRows() throws {
        let profile = try triX400Profile()
        for metered in [1.0, 5.0, 10.0, 25.0, 50.0, 100.0] {
            let result = evaluator.evaluate(profile: profile, meteredExposureSeconds: metered)
            XCTAssertEqual(
                result.metadata.basis,
                .tableLogLogDerived,
                "Metered \(metered) s sits inside the published 1–100 sec range and must be table-log-log-derived."
            )
        }
    }

    func testTriX400TableReproducesAllElevenAnchorsExactly() throws {
        let profile = try triX400Profile()
        // All 11 anchors: 3 published rows + 8 graph samples.
        let allAnchors: [(Double, Double)] = [
            (1, 2), (2, 5), (3, 10), (5, 20), (7, 32),
            (10, 50), (20, 120), (30, 200), (50, 420), (70, 720), (100, 1200),
        ]
        for (metered, published) in allAnchors {
            let result = evaluator.evaluate(profile: profile, meteredExposureSeconds: metered)
            let corrected = try XCTUnwrap(result.correctedExposureSeconds)
            XCTAssertEqual(
                corrected,
                published,
                accuracy: 1e-4,
                "Anchor at metered \(metered) s must reproduce corrected time \(published) s exactly."
            )
        }
    }

    // MARK: - Beyond the published source range (> 100 sec)

    func testTriX400Above100SecondsBecomesBeyondSourceNumericGuidance() throws {
        let profile = try triX400Profile()
        for metered in [150.0, 300.0, 1000.0] {
            let result = evaluator.evaluate(profile: profile, meteredExposureSeconds: metered)
            XCTAssertEqual(
                result.metadata.basis,
                .unsupportedOutOfPolicyRange,
                "Metered \(metered) s sits above Kodak's 100 sec upper published row and must be marked outside manufacturer guidance."
            )
            let corrected = try XCTUnwrap(
                result.correctedExposureSeconds,
                "Metered \(metered) s must keep a log-log extrapolation value past the source range."
            )
            XCTAssertGreaterThan(corrected, 1200,
                "Extrapolated value past 100 sec must exceed the last anchor corrected time of 1200 sec.")
        }
    }

    // MARK: - Source evidence preservation (corrected time + stop delta + development)

    func testTriX400SourceEvidencePreservesPublishedRowsWithDevelopmentAdjustments() throws {
        let profile = try triX400Profile()

        // Source evidence carries only the 3 published rows, not the 8
        // graph-sampled calculation-only anchors.
        let exactRows = profile.sourceEvidence.compactMap { row -> (Double, ReciprocitySourceEvidenceRow)? in
            guard case let .exactSeconds(seconds) = row.meteredExposure else { return nil }
            return (seconds, row)
        }
        XCTAssertEqual(
            exactRows.map { $0.0 },
            [1, 10, 100],
            "Tri-X 400 must keep Kodak's three published rows (1/10/100 sec) as source evidence."
        )

        let expectedDevelopment: [Double: String] = [
            1: "-10% development",
            10: "-20% development",
            100: "-30% development",
        ]
        let expectedStops: [Double: Double] = [1: 1, 10: 2, 100: 3]
        let expectedCorrected: [Double: Double] = [1: 2, 10: 50, 100: 1200]

        for (metered, row) in exactRows {
            // Stop delta — Kodak publishes a numeric +N stops anchor
            // alongside the corrected time on every row.
            let stopDelta = row.adjustments.compactMap { adjustment -> Double? in
                guard case let .exposure(.stopDelta(value)) = adjustment else { return nil }
                return value.stopDelta
            }.first
            XCTAssertEqual(stopDelta ?? -1, expectedStops[metered] ?? -1, accuracy: 1e-6, "Stop delta mismatch at \(metered) s")

            // Corrected time — used as the table fitting basis.
            let correctedSeconds = row.adjustments.compactMap { adjustment -> Double? in
                guard case let .exposure(.correctedTime(mapping)) = adjustment else { return nil }
                return mapping.correctedSeconds
            }.first
            XCTAssertEqual(correctedSeconds ?? -1, expectedCorrected[metered] ?? -1, accuracy: 1e-6, "Corrected time mismatch at \(metered) s")

            // Development adjustment — Tri-X publishes -10/-20/-30%.
            let devInstruction = row.adjustments.compactMap { adjustment -> String? in
                guard case let .development(dev) = adjustment else { return nil }
                return dev.instruction
            }.first
            XCTAssertEqual(
                devInstruction,
                expectedDevelopment[metered],
                "Development instruction at \(metered) s must remain visible as published — Tri-X conversion must not silently drop it."
            )
        }
    }

    // MARK: - Three models

    func testTriX400HasThreeModels() throws {
        let alternates = AlternateReciprocityModels.alternates(forFilmID: "kodak-tri-x-400")
        XCTAssertEqual(alternates.count, 2,
            "alternates(forFilmID:) must return exactly 2 non-default models for Tri-X 400.")
        XCTAssertEqual(alternates[0].id, "kodak-tri-x-official-table",
            "First alternate must be the 3-anchor official table.")
        XCTAssertEqual(alternates[1].id, "kodak-tri-x-app-formula",
            "Second alternate must be the app-derived formula.")

        // The default (catalog primary) is the graph/table model.
        let defaultProfile = try triX400Profile()
        XCTAssertEqual(defaultProfile.id, "kodak-tri-x-official-graph-table",
            "Default profile must be the 11-anchor graph/table model.")
    }

    func testTriX400OfficialTableAlternate() throws {
        let alternates = AlternateReciprocityModels.alternates(forFilmID: "kodak-tri-x-400")
        let officialTable = try XCTUnwrap(
            alternates.first(where: { $0.id == "kodak-tri-x-official-table" }),
            "kodak-tri-x-official-table must be registered as an alternate."
        )

        let tableRule = try XCTUnwrap(
            officialTable.rules.compactMap { rule -> TableInterpolationReciprocityRule? in
                if case let .tableInterpolation(r) = rule { return r } else { return nil }
            }.first,
            "Official table alternate must carry a .tableInterpolation rule."
        )
        XCTAssertEqual(tableRule.noCorrectionThroughSeconds, 0.1, accuracy: 1e-9)
        XCTAssertEqual(tableRule.anchors.count, 3, "Official table alternate has only the 3 published anchors.")

        let anchors = Dictionary(uniqueKeysWithValues: tableRule.anchors.map { ($0.meteredSeconds, $0.correctedSeconds) })
        XCTAssertEqual(anchors[1] ?? -1, 2, accuracy: 1e-4, "Official table alternate: 1 s → 2 s.")
        XCTAssertEqual(anchors[10] ?? -1, 50, accuracy: 1e-4, "Official table alternate: 10 s → 50 s.")
        XCTAssertEqual(anchors[100] ?? -1, 1200, accuracy: 1e-4, "Official table alternate: 100 s → 1200 s.")

        let basis = try XCTUnwrap(officialTable.modelBasis)
        XCTAssertEqual(basis.sourceModel, .manufacturerTable)
        XCTAssertEqual(basis.calculationModel, .tableLogLogInterpolation)

        // Evaluate via the alternate — each anchor must be exact.
        let samples: [(Double, Double)] = [(1, 2), (10, 50), (100, 1200)]
        for (metered, expected) in samples {
            let result = evaluator.evaluate(profile: officialTable, meteredExposureSeconds: metered)
            let corrected = try XCTUnwrap(result.correctedExposureSeconds)
            XCTAssertEqual(corrected, expected, accuracy: 1e-4,
                "Official table alternate at \(metered) s must reproduce \(expected) s exactly.")
            XCTAssertEqual(result.metadata.basis, .tableLogLogDerived,
                "Official table alternate anchor at \(metered) s must be table-log-log-derived.")
        }
    }

    func testTriX400AppFormulaAlternate() throws {
        let alternates = AlternateReciprocityModels.alternates(forFilmID: "kodak-tri-x-400")
        let appFormula = try XCTUnwrap(
            alternates.first(where: { $0.id == "kodak-tri-x-app-formula" }),
            "kodak-tri-x-app-formula must be registered as an alternate."
        )

        let hasFormulaRule = appFormula.rules.contains { rule in
            if case .formula = rule { return true } else { return false }
        }
        XCTAssertTrue(hasFormulaRule, "App-formula alternate must carry a .formula rule.")

        // 1 s → 2 s (formula coefficient).
        let result1 = evaluator.evaluate(profile: appFormula, meteredExposureSeconds: 1)
        XCTAssertEqual(try XCTUnwrap(result1.correctedExposureSeconds), 2.0, accuracy: 0.01,
            "App formula at 1 s must return ≈ 2 s (coefficient seconds).")

        // 10 s → ≈ 49 s (2 × 10^1.3891).
        let result10 = evaluator.evaluate(profile: appFormula, meteredExposureSeconds: 10)
        XCTAssertEqual(try XCTUnwrap(result10.correctedExposureSeconds), 49.0, accuracy: 0.5,
            "App formula at 10 s must return ≈ 49 s (2 × 10^1.3891).")

        // 100 s → ≈ 1200 s.
        let result100 = evaluator.evaluate(profile: appFormula, meteredExposureSeconds: 100)
        XCTAssertEqual(try XCTUnwrap(result100.correctedExposureSeconds), 1200.0, accuracy: 5,
            "App formula at 100 s must return ≈ 1200 s.")

        // 0.05 s → no correction (within noCorrectionThroughSeconds = 0.1).
        let resultNoCorr = evaluator.evaluate(profile: appFormula, meteredExposureSeconds: 0.05)
        let corrNoCorr = try XCTUnwrap(resultNoCorr.correctedExposureSeconds)
        XCTAssertEqual(corrNoCorr, 0.05, accuracy: 1e-6,
            "App formula at 0.05 s must return no correction (Tc = Tm).")

        // isAppDerivedModel must return true.
        XCTAssertTrue(
            AlternateReciprocityModels.isAppDerivedModel(id: "kodak-tri-x-app-formula"),
            "isAppDerivedModel(id:) must return true for kodak-tri-x-app-formula."
        )
    }

    func testTriX400AppFormulaIsNotLabeledManufacturerFormula() throws {
        let alternates = AlternateReciprocityModels.alternates(forFilmID: "kodak-tri-x-400")
        let appFormula = try XCTUnwrap(
            alternates.first(where: { $0.id == "kodak-tri-x-app-formula" }),
            "kodak-tri-x-app-formula must be registered as an alternate."
        )

        // Name must not read as "Official ...".
        XCTAssertFalse(
            appFormula.name.hasPrefix("Official"),
            "App formula name must not start with 'Official'; got '\(appFormula.name)'."
        )
        XCTAssertTrue(
            appFormula.name.contains("App"),
            "App formula name must contain 'App'; got '\(appFormula.name)'."
        )

        // modelBasis: source is .manufacturerTable (the table it was
        // derived from), calculation is .guardedFormula (app-fitted).
        let basis = try XCTUnwrap(appFormula.modelBasis)
        XCTAssertEqual(basis.sourceModel, .manufacturerTable,
            "App-derived formula's source is still the manufacturer table it was fitted against.")
        XCTAssertEqual(basis.calculationModel, .guardedFormula,
            "App-derived formula must use .guardedFormula, not .tableLogLogInterpolation or .manufacturerFormula.")

        // Enrolled as app-derived.
        XCTAssertTrue(AlternateReciprocityModels.isAppDerivedModel(id: appFormula.id),
            "App formula must be enrolled as an app-derived model.")
    }

    // MARK: - UI surfacing

    @MainActor
    func testTriX400DetailsSurfaceShowsSourceReferenceRowsWithDevelopmentText() throws {
        let displayState = try makeDisplayState(meteredExposureSeconds: 10)

        let sourceReferenceSection = try XCTUnwrap(
            displayState.sections.first(where: { $0.title == "Source reference" }),
            "Tri-X 400 must surface a Source reference section for its table-origin profile."
        )
        let sourceBlock = try XCTUnwrap(sourceReferenceSection.rows.first?.value)
        for stop in ["-10%", "-20%", "-30%"] {
            XCTAssertTrue(
                sourceBlock.contains(stop),
                "Source reference block must surface Kodak's development adjustment \(stop). Got block:\n\(sourceBlock)"
            )
        }
        XCTAssertFalse(
            displayState.sections.contains(where: { $0.title == "Reference" }),
            "Tri-X 400 must not surface the legacy Reference section."
        )
        XCTAssertFalse(
            displayState.sections.contains(where: { $0.title == "Guidance boundary" }),
            "Tri-X 400 has no published not-recommended row; Guidance boundary section must be absent."
        )
    }

    @MainActor
    func testTriX400SourceReferenceNoCorrectionRowEndsAtTenthSecond() throws {
        let displayState = try makeDisplayState(meteredExposureSeconds: 10)
        let sourceReferenceSection = try XCTUnwrap(
            displayState.sections.first(where: { $0.title == "Source reference" })
        )
        let sourceBlock = try XCTUnwrap(sourceReferenceSection.rows.first?.value)

        XCTAssertTrue(
            sourceBlock.contains("No correction range"),
            "Tri-X 400 source reference must surface a No correction range row. Got:\n\(sourceBlock)"
        )
        // The no-correction band ends at 1/10 sec; with the test's
        // "%.1fs" formatter that renders inclusively as "<= 0.1s"
        // (the production formatter renders it as "<= 1/10s").
        XCTAssertTrue(
            sourceBlock.contains("<= 0.1s"),
            "No correction range must end inclusively at 1/10 sec ('<= 0.1s'). Got:\n\(sourceBlock)"
        )
        XCTAssertFalse(
            sourceBlock.contains("< 1s"),
            "Tri-X 400 must no longer display the stale '< 1s No correction range'. Got:\n\(sourceBlock)"
        )
    }

    @MainActor
    func testTriX400DevelopmentLegendStillSurfacesAfterMigration() throws {
        let displayState = try makeDisplayState(meteredExposureSeconds: 10)
        let legend = try XCTUnwrap(displayState.legend)
        XCTAssertTrue(
            legend.lines.contains { $0 == "Development adjustment: Dev -10% means adjust development time by -10%." },
            "Tri-X 400 migration must keep the development-adjustment legend line. Got: \(legend.lines)"
        )
    }

    @MainActor
    func testTriX400SummaryTextIsLogLogInterpolationInsideRange() throws {
        let displayState = try makeDisplayState(meteredExposureSeconds: 10)
        XCTAssertEqual(
            displayState.summary.summaryText,
            "Log-log interpolation of the official table",
            "Summary inside the source range must describe table log-log interpolation."
        )
    }

    @MainActor
    func testTriX400SummaryTextIsBeyondSourceRangeAbove100Seconds() throws {
        let displayState = try makeDisplayState(meteredExposureSeconds: 300)
        XCTAssertEqual(
            displayState.summary.summaryText,
            "Beyond source range",
            "Summary above 100 sec must read 'Beyond source range'."
        )
    }

    @MainActor
    func testTriX400GraphCarriesSourceReferenceMarkersAtPublishedCorrectedTimes() throws {
        let displayState = try makeDisplayState(meteredExposureSeconds: 10)
        let graph = try XCTUnwrap(displayState.graph)
        XCTAssertEqual(graph.kind, .formula,
            "Table models render as .formula graph kind (matching Fomapan 100 Classic behavior).")

        // Graph markers must be at the 3 published source rows only
        // (not at the 8 graph-sampled calculation-only anchors).
        let markerMetereds = graph.sourceReferenceMarkers.map { $0.point.meteredExposureSeconds.rounded() }
        XCTAssertEqual(
            Set(markerMetereds),
            Set([1, 10, 100]),
            "Tri-X 400 graph must mark Kodak's three published source rows."
        )

        let markerByMetered = Dictionary(
            uniqueKeysWithValues: graph.sourceReferenceMarkers.map { ($0.point.meteredExposureSeconds.rounded(), $0.point.correctedExposureSeconds) }
        )
        XCTAssertEqual(markerByMetered[1] ?? 0, 2, accuracy: 1e-3, "Marker at 1 sec must plot the published 2 sec corrected exposure.")
        XCTAssertEqual(markerByMetered[10] ?? 0, 50, accuracy: 1e-3, "Marker at 10 sec must plot the published 50 sec corrected exposure.")
        XCTAssertEqual(markerByMetered[100] ?? 0, 1200, accuracy: 1e-2, "Marker at 100 sec must plot the published 1200 sec corrected exposure.")

        XCTAssertNil(
            graph.notRecommendedBoundarySeconds,
            "Tri-X 400 has no published not-recommended boundary."
        )

        let beyondStart = try XCTUnwrap(
            graph.beyondSourceRangeStartSeconds,
            "The graph must shade the region above 100 sec so the user sees where source-backed guidance ends."
        )
        XCTAssertEqual(beyondStart, 100.000001, accuracy: 1e-3)
    }

    /// Past 100 sec the graph note must surface "source range"
    /// wording so the value never reads as manufacturer-supported.
    @MainActor
    func testTriX400Above100SecondsGraphExplanationSurfacesSourceRangeWording() throws {
        let displayState = try makeDisplayState(meteredExposureSeconds: 300)
        let graph = try XCTUnwrap(displayState.graph)
        let explanation = try XCTUnwrap(graph.unsupportedExplanation)
        XCTAssertTrue(
            explanation.lowercased().contains("source table"),
            "Graph explanation must surface source-table wording past 100 sec; got: \(explanation)"
        )
    }

    // MARK: - Helpers

    @MainActor
    private func makeDisplayState(
        meteredExposureSeconds: Double
    ) throws -> FilmModeDetailsDisplayState {
        try FormulaProfileTestSupport.makeDisplayState(
            film: "Tri-X 400",
            meteredExposureSeconds: meteredExposureSeconds
        )
    }

    private func triX400Profile() throws -> ReciprocityProfile {
        try FormulaProfileTestSupport.profile(for: "Tri-X 400")
    }
}
