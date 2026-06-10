import XCTest
import PTimerKit
import PTimerCore

/// Direct regression tests for `FilmModeDetailsGraphPresenter`.
/// Existing graph coverage runs indirectly through profile-level
/// suites (Provia 100F, HP5 Plus, etc.) and through
/// `ReciprocityModel.makeDetailsDisplayState(...)`, which composes
/// the graph presenter with surrounding presenters. These tests
/// pin the presenter's IO directly so a future helper extraction
/// inside the presenter cannot drift past the profile-level tests
/// for unrelated reasons.
final class FilmModeDetailsGraphPresenterTests: XCTestCase {

    // MARK: - Formula profile with source evidence (Provia 100F)

    @MainActor
    func testFormulaProfileGraphReturnsFormulaKindAndFormulaDerivedCurrentPointAtFormulaInput() throws {
        let graph = try presenterGraph(forFilm: "Provia 100F", meteredSeconds: 240)
        XCTAssertEqual(graph.kind, .formula)
        let currentPoint = try XCTUnwrap(graph.currentPoint)
        XCTAssertEqual(currentPoint.style, .formulaDerived)
        XCTAssertEqual(currentPoint.point.meteredExposureSeconds, 240, accuracy: 1e-6)
    }

    @MainActor
    func testFormulaProfileGraphMarksCurrentPointNoCorrectionInsideThreshold() throws {
        let graph = try presenterGraph(forFilm: "Provia 100F", meteredSeconds: 60)
        XCTAssertEqual(graph.currentPoint?.style, .noCorrection)
        XCTAssertEqual(
            graph.caption,
            "Adjusted shutter equals corrected exposure within the no-correction range"
        )
    }

    @MainActor
    func testFormulaProfileGraphMarksCurrentPointBeyondSourceRangeAtUnsupportedNumeric() throws {
        let graph = try presenterGraph(forFilm: "Provia 100F", meteredSeconds: 600)
        XCTAssertEqual(graph.currentPoint?.style, .beyondSourceRange)
        // PTIMER-160: beyond-source region starts at the 240 s
        // source-backed anchor; the separate 480 s row remains a
        // not-recommended warning marker.
        XCTAssertEqual(graph.beyondSourceRangeStartSeconds ?? 0, 240, accuracy: 1e-6)
        XCTAssertEqual(graph.notRecommendedBoundarySeconds ?? 0, 480, accuracy: 1e-6)
        XCTAssertEqual(graph.descriptionLines.count, 1)
        let line = try XCTUnwrap(graph.descriptionLines.first)
        XCTAssertTrue(
            line.lowercased().contains("source range"),
            "Beyond-source description must surface the source-range wording; got: \(line)"
        )
        let explanation = try XCTUnwrap(graph.unsupportedExplanation)
        XCTAssertTrue(
            explanation.lowercased().contains("source range"),
            "Unsupported explanation must surface the source-range wording; got: \(explanation)"
        )
        XCTAssertEqual(
            graph.caption,
            "Formula prediction outside the manufacturer-supported boundary"
        )
    }

    @MainActor
    func testFormulaProfileSourceReferenceMarkersIncludePublished240SecondAnchor() throws {
        let graph = try presenterGraph(forFilm: "Provia 100F", meteredSeconds: 240)
        let marker = try XCTUnwrap(
            graph.sourceReferenceMarkers.first {
                abs($0.point.meteredExposureSeconds - 240) < 1e-6
            },
            "Provia 100F graph must surface the 240 s manufacturer reference marker."
        )
        XCTAssertEqual(marker.label, "240s")
        // Source-evidence carries +1/3 stop at 240 s → 302.4 s corrected.
        XCTAssertEqual(marker.point.correctedExposureSeconds, 302.4, accuracy: 1.0)
    }

    @MainActor
    func testFormulaProfileSourceReferenceMarkersExcludeNotRecommendedBoundary() throws {
        let graph = try presenterGraph(forFilm: "Provia 100F", meteredSeconds: 240)
        for marker in graph.sourceReferenceMarkers {
            XCTAssertNotEqual(
                marker.point.meteredExposureSeconds, 480, accuracy: 1e-6,
                "The 480 s not-recommended boundary must not appear as a source-reference marker."
            )
        }
    }

    @MainActor
    func testFormulaEquationTextRendersFourDecimalExponentAndAnchor() throws {
        let graph = try presenterGraph(forFilm: "Provia 100F", meteredSeconds: 240)
        let formula = try XCTUnwrap(graph.formulaDisplayText)
        XCTAssertTrue(
            formula.contains("1.3676"),
            "Formula exponent must render at 4-decimal precision; got: \(formula)"
        )
        XCTAssertTrue(
            formula.contains("128"),
            "Formula expression must surface the 128 s anchor; got: \(formula)"
        )
    }

    @MainActor
    func testFormulaProfileSupportedInputHasNoDescriptionLines() throws {
        let graph = try presenterGraph(forFilm: "Provia 100F", meteredSeconds: 240)
        XCTAssertTrue(
            graph.descriptionLines.isEmpty,
            "Supported-range cases must not surface description lines; got: \(graph.descriptionLines)"
        )
    }

    // MARK: - Formula profile without source evidence (HP5 Plus)

    @MainActor
    func testFormulaProfileWithoutSourceEvidenceLeavesSourceArtifactsEmpty() throws {
        let graph = try presenterGraph(forFilm: "HP5 Plus", meteredSeconds: 8)
        XCTAssertEqual(graph.kind, .formula)
        XCTAssertTrue(graph.sourceReferenceMarkers.isEmpty)
        XCTAssertNil(graph.notRecommendedBoundarySeconds)
        XCTAssertNil(graph.beyondSourceRangeStartSeconds)
        XCTAssertTrue(graph.descriptionLines.isEmpty)
        XCTAssertEqual(
            graph.caption,
            "Adjusted shutter vs corrected exposure on the active calculation curve"
        )
    }

    @MainActor
    func testFormulaEquationTextRendersExponentOnlyForSourcelessFormulaProfile() throws {
        let graph = try presenterGraph(forFilm: "HP5 Plus", meteredSeconds: 8)
        let formula = try XCTUnwrap(graph.formulaDisplayText)
        XCTAssertEqual(formula, "Tc = Tm^1.31")
    }

    // MARK: - Limited-guidance profile (Portra 400 official) — no formula rule

    @MainActor
    func testLimitedGuidanceProfileReturnsNilGraph() throws {
        let graph = try makePresenterGraph(forFilm: "Portra 400", meteredSeconds: 15)
        XCTAssertNil(
            graph,
            "Profiles without a formula rule must not produce a graph display state."
        )
    }

    // MARK: - Input-boundary guards

    @MainActor
    func testFailureCalculationResultReturnsNilGraph() throws {
        let film = try unwrapFilm(named: "Provia 100F")
        let profile = try XCTUnwrap(film.profiles.first)
        let policyResult = ReciprocityModel().evaluate(profile: profile, meteredExposureSeconds: 1)
        let binding = FilmModeReciprocityBindingState(
            film: film,
            profile: profile,
            policyResult: policyResult,
            presentation: policyResult.confidencePresentation
        )

        let presenter = FilmModeDetailsGraphPresenter()
        let result = presenter.graphDisplayState(
            for: FilmModeDetailsGraphPresenter.Input(
                bindingState: binding,
                calculationResult: .failure(.nonPositiveBaseShutter),
                formatDuration: Self.formatDuration
            )
        )
        XCTAssertNil(result, "A failed calculation result must produce no graph display state.")
    }

    @MainActor
    func testZeroResultShutterCalculationReturnsNilGraph() throws {
        let film = try unwrapFilm(named: "Provia 100F")
        let profile = try XCTUnwrap(film.profiles.first)
        let policyResult = ReciprocityModel().evaluate(profile: profile, meteredExposureSeconds: 1)
        let binding = FilmModeReciprocityBindingState(
            film: film,
            profile: profile,
            policyResult: policyResult,
            presentation: policyResult.confidencePresentation
        )

        let presenter = FilmModeDetailsGraphPresenter()
        let result = presenter.graphDisplayState(
            for: FilmModeDetailsGraphPresenter.Input(
                bindingState: binding,
                calculationResult: .success(
                    ExposureCalculationResult(
                        baseShutterSeconds: 1,
                        stop: 0,
                        resultShutterSeconds: 0
                    )
                ),
                formatDuration: Self.formatDuration
            )
        )
        XCTAssertNil(result, "A zero result shutter must produce no graph display state.")
    }

    // MARK: - Helpers

    private static let formatDuration: (Double) -> String = {
        String(format: "%.1fs", $0)
    }

    @MainActor
    private func presenterGraph(
        forFilm name: String,
        meteredSeconds: Double,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> FilmModeDetailsGraphDisplayState {
        try XCTUnwrap(
            try makePresenterGraph(forFilm: name, meteredSeconds: meteredSeconds),
            "\(name) at \(meteredSeconds) s must produce a graph display state.",
            file: file,
            line: line
        )
    }

    @MainActor
    private func makePresenterGraph(
        forFilm name: String,
        meteredSeconds: Double,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> FilmModeDetailsGraphDisplayState? {
        let film = try unwrapFilm(named: name, file: file, line: line)
        let profile = try XCTUnwrap(film.profiles.first, file: file, line: line)
        let policyResult = ReciprocityModel().evaluate(
            profile: profile,
            meteredExposureSeconds: meteredSeconds
        )
        let binding = FilmModeReciprocityBindingState(
            film: film,
            profile: profile,
            policyResult: policyResult,
            presentation: policyResult.confidencePresentation
        )
        let calc: Result<ExposureCalculationResult, ExposureCalculatorError> = .success(
            ExposureCalculationResult(
                baseShutterSeconds: meteredSeconds,
                stop: 0,
                resultShutterSeconds: meteredSeconds
            )
        )
        let presenter = FilmModeDetailsGraphPresenter()
        return presenter.graphDisplayState(
            for: FilmModeDetailsGraphPresenter.Input(
                bindingState: binding,
                calculationResult: calc,
                formatDuration: Self.formatDuration
            )
        )
    }

    private func unwrapFilm(
        named name: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> FilmIdentity {
        try XCTUnwrap(
            LaunchPresetFilmCatalog.films.first { $0.canonicalStockName == name },
            "\(name) must remain in the launch catalog.",
            file: file,
            line: line
        )
    }
}
