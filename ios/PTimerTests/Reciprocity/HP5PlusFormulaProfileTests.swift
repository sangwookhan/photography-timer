import XCTest
@testable import PTimer

/// Regression coverage for the legacy source-less HP5 Plus formula
/// profile. Confirms the converted-formula presentation surfaces
/// (Source reference section, not-recommended boundary, beyond-source
/// region) do NOT activate for profiles without source evidence.
final class HP5PlusFormulaProfileTests: XCTestCase {
    @MainActor
    func testHP5PlusFormulaProfileKeepsLegacyWordingAndTierBasedScale() throws {
        let displayState = try makeHP5PlusDisplayState(meteredExposureSeconds: 8)

        XCTAssertEqual(
            displayState.summary.summaryText,
            "Formula-based correction on the active curve",
            "Source-less formula profiles must keep the existing summary wording."
        )

        let graph = try XCTUnwrap(displayState.graph)
        XCTAssertTrue(graph.sourceReferenceMarkers.isEmpty)
        XCTAssertNil(graph.notRecommendedBoundarySeconds)
        // HP5 Plus at 8 s with no upper formula bound still snaps to
        // a tier; the curve's intrinsic upper of 120 s (canonical
        // fallback) and corrected ~14 s both fit comfortably in T1.
        XCTAssertEqual(graph.scaleTier, .t1)
    }

    @MainActor
    func testHP5PlusFormulaGraphCarriesFormulaDisplayTextWithoutSourceReferenceArtifacts() throws {
        let displayState = try makeHP5PlusDisplayState(meteredExposureSeconds: 8)

        let graph = try XCTUnwrap(displayState.graph)
        XCTAssertNotNil(
            graph.formulaDisplayText,
            "Source-less formula profiles still surface the formula expression near the graph."
        )
        XCTAssertNil(
            graph.beyondSourceRangeStartSeconds,
            "Profiles without source evidence must not render a pink beyond-source region."
        )
    }

    @MainActor
    func testHP5PlusFormulaGraphCarriesNoSourceReferenceArtifacts() throws {
        let displayState = try makeHP5PlusDisplayState(meteredExposureSeconds: 8)

        let graph = try XCTUnwrap(displayState.graph)
        XCTAssertTrue(
            graph.sourceReferenceMarkers.isEmpty,
            "HP5 Plus carries no published source evidence, so the formula graph must not invent markers."
        )
        XCTAssertNil(
            graph.notRecommendedBoundarySeconds,
            "HP5 Plus carries no not-recommended boundary."
        )
        XCTAssertTrue(
            graph.descriptionLines.isEmpty,
            "Profiles without source-reference markers stay on the existing state-aware caption rather than introducing description lines."
        )
        XCTAssertFalse(
            displayState.sections.contains(where: { $0.title == "Source reference" }),
            "HP5 Plus must not surface a Source reference section."
        )
        XCTAssertFalse(
            displayState.sections.contains(where: { $0.title == "Guidance boundary" }),
            "HP5 Plus must not surface a Guidance boundary section."
        )
    }

    @MainActor
    private func makeHP5PlusDisplayState(
        meteredExposureSeconds: Double
    ) throws -> FilmModeDetailsDisplayState {
        let film = try XCTUnwrap(
            LaunchPresetFilmCatalog.films.first { $0.canonicalStockName == "HP5 Plus" },
            "HP5 Plus must remain in the launch catalog."
        )
        let profile = try XCTUnwrap(film.profiles.first)
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
        return try XCTUnwrap(
            model.makeDetailsDisplayState(
                input: FilmModeDetailsPresenterInput(
                    bindingState: bindingState,
                    calculationResult: .success(
                        ExposureCalculationResult(
                            baseShutterSeconds: meteredExposureSeconds,
                            stop: 0,
                            resultShutterSeconds: meteredExposureSeconds
                        )
                    ),
                    filmModeExposureResultState: nil,
                    formatDuration: { String(format: "%.1fs", $0) },
                    formatDurationCoarse: { String(format: "%.1fs", $0) },
                    formatAxisDuration: { "\($0)s" }
                )
            )
        )
    }
}
