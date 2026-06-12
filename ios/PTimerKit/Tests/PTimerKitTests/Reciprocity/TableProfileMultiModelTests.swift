import XCTest
import PTimerKit
import PTimerCore

/// Kodak Tri-X 400 is a table-log-log reciprocity profile. Its
/// archetype-shared behavior — the eleven-anchor table (3 published rows
/// 1→2 / 10→50 / 100→1200 plus 8 graph samples), the 0.1 s no-correction
/// threshold and nominal tolerance, table-derived / beyond-source
/// classification, source-evidence rows with their development
/// adjustments, and Details / graph markers — is verified across films
/// in `TableProfileSourceDataContractTests` and
/// `TableLogLogReciprocityContractTests`.
///
/// This suite holds only Tri-X 400's genuinely film-specific behavior:
/// the sub-1 s interpolation from the 0.1 s knee toward the 1 s → 2 s
/// anchor, the "No correction range" source-reference row wording, the
/// development-adjustment legend, and the two alternate models (the
/// 3-anchor official table and the app-derived formula). The film is the
/// `profileUnderTest()` constant, so no film name appears in a
/// test-function name.
final class TableProfileMultiModelTests: XCTestCase {

    private let evaluator = ReciprocityCalculationPolicyEvaluator()

    // MARK: - Rule structure

    // MARK: - No-correction boundary (inclusive at 1/10 sec)

    /// Regression for the manual-test failure: inputs between 1/10 sec
    /// and 1 sec used to read as No correction (when the band ran to
    /// ~1 sec). They must now be table-derived — interpolated from the
    /// 0.1 sec knee toward the 1 sec → 2 sec anchor, and longer than the
    /// metered value (no vertical step at 1 sec).
    func testBetweenTenthAndOneSecondIsTableDerivedNotNoCorrection() throws {
        let profile = try profileUnderTest()
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

    // MARK: - Table range (1 sec … 100 sec, source-backed)

    // MARK: - Beyond the published source range (> 100 sec)

    // MARK: - Source evidence preservation (corrected time + stop delta + development)

    // MARK: - Three models

    func testHasThreeModels() throws {
        let alternates = AlternateReciprocityModels.alternates(forFilmID: "kodak-tri-x-400")
        XCTAssertEqual(alternates.count, 2,
            "alternates(forFilmID:) must return exactly 2 non-default models for Tri-X 400.")
        XCTAssertEqual(alternates[0].id, "kodak-tri-x-official-table",
            "First alternate must be the 3-anchor official table.")
        XCTAssertEqual(alternates[1].id, "kodak-tri-x-app-formula",
            "Second alternate must be the app-derived formula.")

        // The default (catalog primary) is the graph/table model.
        let defaultProfile = try profileUnderTest()
        XCTAssertEqual(defaultProfile.id, "kodak-tri-x-official-graph-table",
            "Default profile must be the 11-anchor graph/table model.")
    }

    /// Segmented-picker labels and order must distinguish the two
    /// table-based models (PTIMER-168 follow-up to the ambiguous
    /// "Table" label): the published-rows-only "Official table" leads,
    /// the graph-extended default reads "Graph table" second — and
    /// stays the default because selection is by id, independent of
    /// display order.
    @MainActor
    func testModelPickerOrderAndLabelsDistinguishTableModels() throws {
        let defaultProfile = try profileUnderTest()
        let ordered = AlternateReciprocityModels.modelPickerOrder(
            primary: defaultProfile,
            forFilmID: "kodak-tri-x-400"
        )
        XCTAssertEqual(
            ordered.map(\.id),
            ["kodak-tri-x-official-table", "kodak-tri-x-official-graph-table", "kodak-tri-x-app-formula"]
        )
        XCTAssertEqual(
            ordered.map { ExposureCalculatorViewModel.modelSelectorLabel(for: $0) },
            ["Official table", "Graph table", "App formula"]
        )
    }

    /// The two table-based models stay HUMANLY distinguishable on the
    /// Details graph by marker COUNT: the graph-extended default
    /// carries all eleven anchors as source-reference rows (published
    /// rows plus graph-sampled rows, the latter marked
    /// "(graph-sampled)" in their notes), the published-rows-only
    /// alternate carries three.
    func testGraphTableShowsElevenSourceMarkersOfficialTableThree() throws {
        let evidencePresenter = FilmModeDetailsGraphEvidencePresenter()
        let format: (Double) -> String = { "\($0)s" }

        let graphTable = try profileUnderTest()
        XCTAssertEqual(
            evidencePresenter.markers(for: graphTable, formatDuration: format).count,
            11,
            "Graph table must mark every anchor, including the 8 graph-sampled rows."
        )
        XCTAssertEqual(
            graphTable.sourceEvidence.filter { row in
                row.notes.contains { $0.contains("(graph-sampled)") }
            }.count,
            8,
            "Graph-sampled rows must say so in their notes — they are not published table rows."
        )

        let officialTable = try XCTUnwrap(
            AlternateReciprocityModels.alternates(forFilmID: "kodak-tri-x-400")
                .first { $0.id == "kodak-tri-x-official-table" }
        )
        XCTAssertEqual(
            evidencePresenter.markers(for: officialTable, formatDuration: format).count,
            3,
            "Official table must keep only the published 1/10/100 sec rows."
        )

        // The graph-sampled provenance legend appears on the graph
        // table only: the published-rows alternate has no ≈ rows, and
        // a plain-table profile whose ≈ is a stop-conversion
        // derivation (T-MAX 100's 1 s row) must not pick up the graph
        // wording.
        let graphLegendLine = "Graph-sampled rows are points read from the published Kodak graph."
        let legendPresenter = FilmModeDetailsLegendPresenter()
        XCTAssertTrue(
            legendPresenter.legendDisplayState(for: graphTable)?.lines.contains(graphLegendLine) == true,
            "Graph table must carry the graph-sampled legend line."
        )
        XCTAssertFalse(
            legendPresenter.legendDisplayState(for: officialTable)?.lines.contains(graphLegendLine) == true,
            "Official table has no graph-sampled rows."
        )
        let tmax = try XCTUnwrap(
            LaunchPresetFilmCatalog.films.first { $0.id == "kodak-tmax-100" }?.profiles.first
        )
        XCTAssertFalse(
            legendPresenter.legendDisplayState(for: tmax)?.lines.contains(graphLegendLine) == true,
            "T-MAX 100's ≈ is a stop-conversion derivation, not a graph sample."
        )
    }

    func testOfficialTableAlternate() throws {
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

    func testAppFormulaAlternate() throws {
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

    func testAppFormulaIsNotLabeledManufacturerFormula() throws {
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

        // modelBasis: source is .manufacturerGraphTable (the
        // graph-extended Kodak data set it was derived from),
        // calculation is .guardedFormula (app-fitted).
        let basis = try XCTUnwrap(appFormula.modelBasis)
        XCTAssertEqual(basis.sourceModel, .manufacturerGraphTable,
            "App-derived formula's source is the Kodak graph/table data set it was fitted against.")
        XCTAssertEqual(basis.calculationModel, .guardedFormula,
            "App-derived formula must use .guardedFormula, not .tableLogLogInterpolation or .manufacturerFormula.")

        // Enrolled as app-derived.
        XCTAssertTrue(AlternateReciprocityModels.isAppDerivedModel(id: appFormula.id),
            "App formula must be enrolled as an app-derived model.")
    }

    // MARK: - UI surfacing

    @MainActor
    func testSourceReferenceNoCorrectionRowEndsAtTenthSecond() throws {
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
    func testDevelopmentLegendStillSurfacesAfterMigration() throws {
        let displayState = try makeDisplayState(meteredExposureSeconds: 10)
        let legend = try XCTUnwrap(displayState.legend)
        XCTAssertTrue(
            legend.lines.contains { $0 == "Development adjustment: Dev -10% means adjust development time by -10%." },
            "Tri-X 400 migration must keep the development-adjustment legend line. Got: \(legend.lines)"
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

    private func profileUnderTest() throws -> ReciprocityProfile {
        try FormulaProfileTestSupport.profile(for: "Tri-X 400")
    }
}
