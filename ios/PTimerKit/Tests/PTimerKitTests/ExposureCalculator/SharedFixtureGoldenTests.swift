// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import XCTest
import PTimerCore

/// Cross-platform parity gate on the iOS side. Drives the
/// shipped `ExposureCalculator` and `LaunchPresetFilmCatalogV2` against
/// the golden fixtures under `shared/test-fixtures/`. The same files
/// are intended to be consumed by the future Android port; on iOS they
/// confirm that the spec-derived expectations stay in sync with code
/// and that no contributor mutates a fixture without noticing the
/// effect on the runtime.
@MainActor
final class SharedFixtureGoldenTests: XCTestCase {

    // MARK: - exposure-golden.json

    func testExposureGoldenFixtureCasesMatchCalculator() throws {
        let fixture = try loadExposureGolden()
        let calculator = ExposureCalculator()

        // The fixture's full-stop ladder must match the calculator
        // baseline (otherwise the cases below could pass while the
        // ladder drifted out from under them).
        XCTAssertEqual(fixture.fullStopShutterSpeeds.count, ExposureCalculator.fullStopShutterSpeeds.count)
        for (lhs, rhs) in zip(fixture.fullStopShutterSpeeds, ExposureCalculator.fullStopShutterSpeeds) {
            XCTAssertEqual(lhs, rhs, accuracy: 1e-4)
        }

        for testCase in fixture.cases {
            let computed = try calculator.calculate(
                baseShutterSeconds: testCase.baseShutterSeconds,
                stop: testCase.ndStops
            )
            XCTAssertEqual(
                computed,
                testCase.expectedCalculatedSeconds,
                accuracy: testCase.tolerance,
                "Mismatch for case: \(testCase.description)"
            )
        }
    }

    // MARK: - catalog-validation-cases.json

    func testLaunchCatalogMatchesSharedFixtureExpectations() throws {
        let fixture = try loadCatalogValidationCases()

        let films = LaunchPresetFilmCatalogV2.films
        XCTAssertEqual(films.count, fixture.catalogExpectations.expectedFilmCount)
        XCTAssertEqual(
            films.map(\.canonicalStockName),
            fixture.catalogExpectations.expectedFilmOrder
        )
        XCTAssertEqual(
            films.map(\.id),
            fixture.catalogExpectations.expectedFilmIds
        )
    }

    // MARK: - Fixture loading

    private static let fixturesRoot: URL = SharedFixtureLocator.fixturesRoot()

    private func loadExposureGolden() throws -> ExposureGoldenFixture {
        let url = Self.fixturesRoot.appendingPathComponent("exposure-golden.json")
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(ExposureGoldenFixture.self, from: data)
    }

    private func loadCatalogValidationCases() throws -> CatalogValidationFixture {
        let url = Self.fixturesRoot.appendingPathComponent("catalog-validation-cases.json")
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(CatalogValidationFixture.self, from: data)
    }
}

// MARK: - Fixture types

private struct ExposureGoldenFixture: Decodable {
    let fullStopShutterSpeeds: [Double]
    let cases: [ExposureGoldenCase]
}

private struct ExposureGoldenCase: Decodable {
    let description: String
    let baseShutterSeconds: Double
    let ndStops: Int
    let expectedCalculatedSeconds: Double
    let tolerance: Double
}

private struct CatalogValidationFixture: Decodable {
    let catalogExpectations: CatalogExpectations
}

private struct CatalogExpectations: Decodable {
    let expectedFilmCount: Int
    let expectedFilmOrder: [String]
    let expectedFilmIds: [String]
}
