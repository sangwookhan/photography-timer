import XCTest
import PTimerKit
import PTimerCore

/// Catalog-wide invariant for the Film Details graph kind.
///
/// Every launch-preset film must produce either a formula Detail
/// graph or no graph at all (limited-guidance profiles never plot a
/// calculation curve). PTIMER-140 removed the table graph kind so
/// this file pins each stock to one of those two outcomes.
@MainActor
final class FilmDetailsGraphKindInvariantTests: XCTestCase {

    enum ExpectedGraphKind: Equatable, CustomStringConvertible {
        case formula
        case absent

        var description: String {
            switch self {
            case .formula: return "formula"
            case .absent: return "absent"
            }
        }
    }

    /// Canonical stock → expected Detail graph kind.
    ///
    /// Adding a film: append it here with the expected kind. Removing
    /// a film: remove its entry. Converting a film from table to
    /// formula (or vice versa): update its entry.
    private struct GraphKindExpectation {
        let stock: String
        let kind: ExpectedGraphKind
        let sampleMeteredSeconds: Double
    }

    private let expectations: [GraphKindExpectation] = [
        // ADOX
        .init(stock: "CHS 100 II", kind: .formula, sampleMeteredSeconds: 8),
        .init(stock: "CMS 20 II", kind: .formula, sampleMeteredSeconds: 5),

        // Fujifilm
        .init(stock: "Acros II", kind: .formula, sampleMeteredSeconds: 60),
        .init(stock: "Velvia 50", kind: .formula, sampleMeteredSeconds: 30),
        .init(stock: "Velvia 100", kind: .formula, sampleMeteredSeconds: 30),
        .init(stock: "Provia 100F", kind: .formula, sampleMeteredSeconds: 240),

        // FOMA — all three Fomapan stocks use the log-log table model
        // (Fomapan 100 via PTIMER-159; 200/400 via PTIMER-168). Table
        // models still render a graph of kind .formula sampled from the
        // table curve rather than a closed-form formula.
        .init(stock: "Fomapan 100 Classic", kind: .formula, sampleMeteredSeconds: 10),
        .init(stock: "Fomapan 200 Creative", kind: .formula, sampleMeteredSeconds: 10),
        .init(stock: "Fomapan 400 Action", kind: .formula, sampleMeteredSeconds: 10),

        // Kodak — B/W table-origin films (PTIMER-168); the table model
        // renders a graph of kind .formula sampled from the table curve.
        .init(stock: "Tri-X 400", kind: .formula, sampleMeteredSeconds: 10),
        .init(stock: "T-MAX 100", kind: .formula, sampleMeteredSeconds: 10),
        .init(stock: "T-MAX 400", kind: .formula, sampleMeteredSeconds: 10),

        // Kodak — color / slide threshold + limited-guidance profiles
        // (no formula curve and no quantified continuation; the
        // Detail graph does not render for these films).
        .init(stock: "Ektachrome E100", kind: .absent, sampleMeteredSeconds: 5),
        .init(stock: "Ektar 100", kind: .absent, sampleMeteredSeconds: 0.5),
        .init(stock: "Gold 200", kind: .absent, sampleMeteredSeconds: 0.5),
        .init(stock: "Portra 160", kind: .absent, sampleMeteredSeconds: 0.5),
        .init(stock: "Portra 400", kind: .absent, sampleMeteredSeconds: 0.5),
        .init(stock: "Ultra Max 400", kind: .absent, sampleMeteredSeconds: 0.5),

        // ILFORD / HARMAN
        .init(stock: "HP5 Plus", kind: .formula, sampleMeteredSeconds: 10),
        .init(stock: "Pan F Plus", kind: .formula, sampleMeteredSeconds: 10),
        .init(stock: "FP4 Plus", kind: .formula, sampleMeteredSeconds: 10),
        .init(stock: "Delta 100", kind: .formula, sampleMeteredSeconds: 10),
        .init(stock: "Delta 400", kind: .formula, sampleMeteredSeconds: 10),
        .init(stock: "Delta 3200", kind: .formula, sampleMeteredSeconds: 10),
        .init(stock: "XP2 Super", kind: .formula, sampleMeteredSeconds: 10),
        .init(stock: "SFX 200", kind: .formula, sampleMeteredSeconds: 10),
        .init(stock: "Ortho Plus", kind: .formula, sampleMeteredSeconds: 10),
        .init(stock: "Kentmere 100", kind: .formula, sampleMeteredSeconds: 10),
        .init(stock: "Kentmere 200", kind: .formula, sampleMeteredSeconds: 10),
        .init(stock: "Kentmere 400", kind: .formula, sampleMeteredSeconds: 10),

        // Rollei
        .init(stock: "RPX 100", kind: .formula, sampleMeteredSeconds: 10),
        .init(stock: "RPX 400", kind: .formula, sampleMeteredSeconds: 10),
        .init(stock: "RETRO 80S", kind: .formula, sampleMeteredSeconds: 10),
        .init(stock: "SUPERPAN 200", kind: .formula, sampleMeteredSeconds: 10),
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
