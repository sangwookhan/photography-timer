import XCTest
@testable import PTimer

/// Catalog-wide invariant for the Film Details graph kind.
///
/// PTIMER-139 introduced a per-film CMS 20 II conversion. The risk is
/// that a future change accidentally silently demotes a formula
/// profile to a table-preview graph (or vice versa) without surfacing
/// in the per-film unit tests. This file pins the graph kind for
/// every canonical stock in the launch catalog so any drift requires
/// an explicit update here.
///
/// Rules of thumb:
/// - Formula profiles render as `.formula` Detail graphs (calculation
///   curve through the no-correction band, source-reference markers,
///   optional manufacturer not-recommended boundary).
/// - Pure table profiles (CHS 100 II today) render as `.table` Detail
///   graphs.
/// - Advisory-only / threshold-only profiles whose Detail graph
///   cannot be plotted return no graph at all.
///
/// CMS 20 II MUST sit in the `.formula` bucket here. If a future
/// commit pushes it into `.table` or removes its graph, this file is
/// the test that catches it.
@MainActor
final class FilmDetailsGraphKindInvariantTests: XCTestCase {

    enum ExpectedGraphKind: Equatable, CustomStringConvertible {
        case formula
        case table
        case absent

        var description: String {
            switch self {
            case .formula: return "formula"
            case .table: return "table"
            case .absent: return "absent"
            }
        }
    }

    /// Canonical stock → expected Detail graph kind.
    ///
    /// Adding a film: append it here with the expected kind. Removing
    /// a film: remove its entry. Converting a film from table to
    /// formula (or vice versa): update its entry.
    private let expectations: [(stock: String, kind: ExpectedGraphKind, sampleMeteredSeconds: Double)] = [
        // ADOX
        ("CHS 100 II", .formula, 8),
        ("CMS 20 II", .formula, 5),

        // Fujifilm
        ("Acros II", .formula, 60),
        ("Velvia 50", .formula, 30),
        ("Velvia 100", .formula, 30),
        ("Provia 100F", .formula, 240),

        // FOMA
        ("Fomapan 100 Classic", .formula, 10),
        ("Fomapan 200 Creative", .formula, 10),
        ("Fomapan 400 Action", .formula, 10),

        // Kodak — B/W formula films
        ("Tri-X 400", .formula, 10),
        ("T-MAX 100", .formula, 10),
        ("T-MAX 400", .formula, 10),

        // Kodak — color / slide threshold + advisory profiles (no
        // formula curve and no quantified table; the Detail graph
        // does not render for these films).
        ("Ektachrome E100", .absent, 5),
        ("Ektar 100", .absent, 0.5),
        ("Gold 200", .absent, 0.5),
        ("Portra 160", .absent, 0.5),
        ("Portra 400", .absent, 0.5),
        ("Ultra Max 400", .absent, 0.5),

        // ILFORD / HARMAN
        ("HP5 Plus", .formula, 10),
        ("Pan F Plus", .formula, 10),
        ("FP4 Plus", .formula, 10),
        ("Delta 100", .formula, 10),
        ("Delta 400", .formula, 10),
        ("Delta 3200", .formula, 10),
        ("XP2 Super", .formula, 10),
        ("SFX 200", .formula, 10),
        ("Ortho Plus", .formula, 10),
        ("Kentmere 100", .formula, 10),
        ("Kentmere 200", .formula, 10),
        ("Kentmere 400", .formula, 10),

        // Rollei
        ("RPX 100", .formula, 10),
        ("RPX 400", .formula, 10),
        ("RETRO 80S", .formula, 10),
        ("SUPERPAN 200", .formula, 10),
    ]

    func testEveryCatalogStockHasAGraphKindExpectation() throws {
        let expectedNames = Set(expectations.map(\.stock))
        let catalogNames = Set(LaunchPresetFilmCatalog.films.map(\.canonicalStockName))
        let missing = catalogNames.subtracting(expectedNames)
        let stale = expectedNames.subtracting(catalogNames)
        XCTAssertTrue(
            missing.isEmpty,
            "Catalog stocks missing from FilmDetailsGraphKindInvariantTests.expectations: \(missing.sorted()). Add them with the expected graph kind."
        )
        XCTAssertTrue(
            stale.isEmpty,
            "Expectations reference stocks no longer in the launch catalog: \(stale.sorted()). Remove them or restore the missing catalog entries."
        )
    }

    func testEachStockRendersTheExpectedDetailGraphKind() throws {
        for expectation in expectations {
            let displayState = try makeDisplayState(
                stock: expectation.stock,
                meteredExposureSeconds: expectation.sampleMeteredSeconds
            )

            switch expectation.kind {
            case .formula:
                let graph = try XCTUnwrap(
                    displayState.graph,
                    "\(expectation.stock) must render a Detail graph at \(expectation.sampleMeteredSeconds) s; got nil."
                )
                XCTAssertEqual(
                    graph.kind,
                    .formula,
                    "\(expectation.stock) must render as a formula Detail graph; got \(graph.kind)."
                )
            case .table:
                let graph = try XCTUnwrap(
                    displayState.graph,
                    "\(expectation.stock) must render a Detail graph at \(expectation.sampleMeteredSeconds) s; got nil."
                )
                XCTAssertEqual(
                    graph.kind,
                    .table,
                    "\(expectation.stock) must render as a table Detail graph; got \(graph.kind)."
                )
            case .absent:
                XCTAssertNil(
                    displayState.graph,
                    "\(expectation.stock) must not render a Detail graph at \(expectation.sampleMeteredSeconds) s; got \(String(describing: displayState.graph))."
                )
            }
        }
    }

    /// Specific CMS 20 II regression: the formula curve must remain
    /// visible through the no-correction band so the user reads the
    /// green band as a continuous segment of the calculation curve
    /// rather than a gap. This is the Sub-1 s / formula handoff
    /// invariant that the dropped commits violated.
    func testCms20IICalculationCurveExtendsThroughNoCorrectionBand() throws {
        let displayState = try makeDisplayState(
            stock: "CMS 20 II",
            meteredExposureSeconds: 0.5
        )
        let graph = try XCTUnwrap(displayState.graph)
        XCTAssertEqual(graph.kind, .formula)

        let threshold = try XCTUnwrap(
            graph.noCorrectionRangeUpperBoundSeconds,
            "CMS 20 II must surface a no-correction band upper bound."
        )

        let belowOrAtThreshold = graph.sourcePoints.filter { $0.meteredExposureSeconds <= threshold }
        XCTAssertFalse(
            belowOrAtThreshold.isEmpty,
            "Calculation curve must sample inside the no-correction band so the green band is not a visual gap."
        )
        for point in belowOrAtThreshold {
            XCTAssertEqual(
                point.correctedExposureSeconds,
                point.meteredExposureSeconds,
                accuracy: 1e-6,
                "Identity-segment samples must produce corrected == metered through the no-correction zone; got \(point)."
            )
        }
    }

    /// Specific Fomapan / HP5 Plus regression: each formula profile
    /// keeps the calculation curve through its own no-correction band
    /// too. This catches a future "tidy" pass that accidentally
    /// removes the identity segment when refactoring the curve
    /// sampler.
    func testEveryFormulaProfileWithNoCorrectionBandSamplesIdentityThroughIt() throws {
        let formulaWithBand = expectations.filter { $0.kind == .formula }
        for expectation in formulaWithBand {
            // Pick an input inside the no-correction band so the
            // identity segment is the visible portion of the graph.
            // 0.25 s sits inside every catalog film's no-correction
            // band (Velvia 50 has the highest minimum at 0.5 s, so
            // we use 0.1 s to clear all of them).
            let metered = 0.1
            let displayState = try makeDisplayState(
                stock: expectation.stock,
                meteredExposureSeconds: metered
            )
            let graph = try XCTUnwrap(displayState.graph, "\(expectation.stock): missing graph for sub-1 s metered.")
            guard let threshold = graph.noCorrectionRangeUpperBoundSeconds else {
                continue
            }
            let bandSamples = graph.sourcePoints.filter { $0.meteredExposureSeconds <= threshold }
            XCTAssertFalse(
                bandSamples.isEmpty,
                "\(expectation.stock): formula curve must sample inside its own no-correction band."
            )
            for point in bandSamples {
                XCTAssertEqual(
                    point.correctedExposureSeconds,
                    point.meteredExposureSeconds,
                    accuracy: 1e-6,
                    "\(expectation.stock): identity samples must lie on Tc = Tm inside the no-correction band; got \(point)."
                )
            }
        }
    }

    // MARK: - Helpers

    private func makeDisplayState(
        stock: String,
        meteredExposureSeconds: Double,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> FilmModeDetailsDisplayState {
        let film = try XCTUnwrap(
            LaunchPresetFilmCatalog.films.first { $0.canonicalStockName == stock },
            "\(stock) must remain in the launch catalog.",
            file: file,
            line: line
        )
        let profile = try XCTUnwrap(film.profiles.first, file: file, line: line)
        let model = ReciprocityModel()
        let policyResult = model.evaluate(
            profile: profile,
            meteredExposureSeconds: meteredExposureSeconds
        )
        let bindingState = FilmModeReciprocityBindingState(
            film: film,
            profile: profile,
            policyResult: policyResult,
            presentation: policyResult.confidencePresentation
        )
        let calculationResult: Result<ExposureCalculationResult, ExposureCalculatorError> = .success(
            ExposureCalculationResult(
                baseShutterSeconds: meteredExposureSeconds,
                stop: 0,
                resultShutterSeconds: meteredExposureSeconds
            )
        )
        return try XCTUnwrap(
            model.makeDetailsDisplayState(
                input: FilmModeDetailsPresenterInput(
                    bindingState: bindingState,
                    calculationResult: calculationResult,
                    filmModeExposureResultState: nil,
                    formatDuration: { String(format: "%.1fs", $0) },
                    formatDurationCoarse: { String(format: "%.1fs", $0) },
                    formatAxisDuration: { "\($0)s" }
                )
            ),
            file: file,
            line: line
        )
    }
}
