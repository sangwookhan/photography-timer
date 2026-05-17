import Foundation
import XCTest
@testable import PTimer

/// Shared fixtures for the per-film formula-profile test suites.
/// Kept in one place so each per-film test file (Velvia 50,
/// Velvia 100, Acros II, Tri-X 400, T-MAX 100, T-MAX 400, …) can
/// stay focused on its own behavior contract without duplicating
/// the catalog-lookup and display-state plumbing.
enum FormulaProfileTestSupport {

    static func profile(
        for canonicalStockName: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> ReciprocityProfile {
        let film = try XCTUnwrap(
            LaunchPresetFilmCatalog.films.first { $0.canonicalStockName == canonicalStockName },
            "\(canonicalStockName) must remain in the launch catalog.",
            file: file,
            line: line
        )
        return try XCTUnwrap(film.profiles.first, file: file, line: line)
    }

    @MainActor
    static func makeDisplayState(
        film canonicalStockName: String,
        meteredExposureSeconds: Double,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> FilmModeDetailsDisplayState {
        let film = try XCTUnwrap(
            LaunchPresetFilmCatalog.films.first { $0.canonicalStockName == canonicalStockName },
            "\(canonicalStockName) must remain in the launch catalog.",
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
