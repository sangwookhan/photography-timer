// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import XCTest
import PTimerKit
import PTimerCore

/// PTIMER-199: consumes `shared/test-fixtures/nd-stack-golden.json`
/// so stack summation, the post-commit sort order, and the resulting
/// calculation stay in lockstep across the iOS and Android ports.
@MainActor
final class NDStackGoldenTests: XCTestCase {
    func testNDStackGoldenFixtureCasesMatchDomainAndCalculator() throws {
        let fixture = try loadFixture()
        let calculator = ExposureCalculator()

        for testCase in fixture.cases {
            let stack = NDFilterStack(
                entries: testCase.wheelStops.map(NDStep.init(stops:))
            )

            XCTAssertEqual(
                stack.effectiveStep.stops,
                testCase.expectedEffectiveStops,
                accuracy: 1e-9,
                "Effective sum mismatch: \(testCase.description)"
            )

            XCTAssertEqual(
                stack.sortedForCommit().entries.map(\.stops),
                testCase.expectedSortedStops,
                "Sort order mismatch: \(testCase.description)"
            )

            // Shipping one-third-stop scale: the effective value feeds
            // the engine unsnapped.
            let computed = try calculator.calculate(
                baseShutterSeconds: testCase.baseShutterSeconds,
                ndStep: stack.effectiveStep,
                scaleMode: .oneThirdStop
            )
            XCTAssertEqual(
                computed,
                testCase.expectedCalculatedSeconds,
                accuracy: testCase.tolerance,
                "Calculation mismatch: \(testCase.description)"
            )
        }
    }

    // MARK: - Fixture loading

    private func loadFixture() throws -> NDStackGoldenFixture {
        let url = SharedFixtureLocator.fixturesRoot()
            .appendingPathComponent("nd-stack-golden.json")
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(NDStackGoldenFixture.self, from: data)
    }
}

// MARK: - Fixture types

private struct NDStackGoldenFixture: Decodable {
    let cases: [NDStackGoldenCase]
}

private struct NDStackGoldenCase: Decodable {
    let description: String
    let baseShutterSeconds: Double
    let wheelStops: [Double]
    let expectedSortedStops: [Double]
    let expectedEffectiveStops: Double
    let expectedCalculatedSeconds: Double
    let tolerance: Double
}
