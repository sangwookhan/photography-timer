// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import XCTest
@testable import PTimerCore

final class ReciprocityInverseTests: XCTestCase {
    private let inverse = ReciprocityInverse()
    private let source = ReciprocitySourceProvenance(kind: .userDefined, authority: .userDefined, confidence: .high, publisher: "Test")

    private func profile(_ rule: ReciprocityRule) -> ReciprocityProfile {
        .init(id: "custom", name: "Custom", source: source, rules: [rule])
    }
    private func formula(_ coefficient: Double = 1, _ exponent: Double = 2, boundary: Double = 1, upper: Double? = 10) -> ReciprocityProfile {
        profile(.formula(.init(formula: .init(coefficientSeconds: coefficient, exponent: exponent, noCorrectionThroughSeconds: boundary, sourceRangeThroughSeconds: upper))))
    }
    private func assertMetered(_ profile: ReciprocityProfile, _ target: Double, _ expected: Double, warning: Bool = false, file: StaticString = #filePath, line: UInt = #line) {
        guard case .available(let metered, let forward) = inverse.evaluate(profile: profile, targetSeconds: target) else {
            XCTFail("Expected unique inverse for T=\(target)", file: file, line: line); return
        }
        XCTAssertEqual(metered, expected, accuracy: max(1e-10, expected * 1e-10), file: file, line: line)
        XCTAssertEqual(forward.metadata.rangeStatus != .withinStatedRange, warning, file: file, line: line)
        XCTAssertEqual(forward.correctedExposureSeconds!, target, accuracy: max(1e-10, target * 1e-10), file: file, line: line)
    }

    func testFormulaIdentityInverseAndContinuation() {
        assertMetered(formula(), 1, 1)
        assertMetered(formula(), 16, 4)
        assertMetered(formula(), 400, 20, warning: true)
        XCTAssertEqual(inverse.evaluate(profile: formula(2), targetSeconds: 1.5), .unavailable(.noQuantifiedSolution))
    }
    func testRealAcrosStrictBoundaryAndGap() throws {
        let acros = try XCTUnwrap(LaunchPresetFilmCatalogV2.films.first { $0.canonicalStockName == "Acros II" }?.profiles.first)
        assertMetered(acros, 119.999999, 119.999999)
        XCTAssertEqual(inverse.evaluate(profile: acros, targetSeconds: 150), .unavailable(.noQuantifiedSolution))
        let target = try XCTUnwrap(ReciprocityCalculationPolicyEvaluator().evaluate(profile: acros, meteredExposureSeconds: 120).correctedExposureSeconds)
        assertMetered(acros, target, 120)
    }
    func testDecreasingAndConstantFormulaRejectMultipleSolutions() {
        XCTAssertEqual(inverse.evaluate(profile: formula(10, -1), targetSeconds: 5), .unavailable(.multipleSolutions))
        XCTAssertEqual(inverse.evaluate(profile: formula(5, 0), targetSeconds: 5), .unavailable(.multipleSolutions))
        assertMetered(formula(5, 0), 0.5, 0.5)
        XCTAssertEqual(inverse.evaluate(profile: formula(1, 0), targetSeconds: 1), .unavailable(.multipleSolutions), "The unchanged 1e-6 formula guard admits a flat interval just above the threshold.")
    }
    func testTableToleranceGapAnchorsAndContinuation() {
        let table = profile(.tableInterpolation(.init(anchors: [.init(meteredSeconds: 1, correctedSeconds: 2), .init(meteredSeconds: 10, correctedSeconds: 80), .init(meteredSeconds: 100, correctedSeconds: 1600)], noCorrectionThroughSeconds: 0.1, sourceRangeThroughSeconds: 100)))
        assertMetered(table, 0.11, 0.11)
        XCTAssertEqual(inverse.evaluate(profile: table, targetSeconds: 0.112), .unavailable(.noQuantifiedSolution))
        assertMetered(table, 80, 10)
        assertMetered(table, 32000, 1000, warning: true)
    }
    func testFlatAndDecreasingTablesEnumerateAllSolutions() {
        let flat = profile(.tableInterpolation(.init(anchors: [.init(meteredSeconds: 1, correctedSeconds: 10), .init(meteredSeconds: 10, correctedSeconds: 10)], noCorrectionThroughSeconds: 0.1, sourceRangeThroughSeconds: 10)))
        XCTAssertEqual(inverse.evaluate(profile: flat, targetSeconds: 10), .unavailable(.multipleSolutions))
        let decreasing = profile(.tableInterpolation(.init(anchors: [.init(meteredSeconds: 1, correctedSeconds: 100), .init(meteredSeconds: 10, correctedSeconds: 20)], noCorrectionThroughSeconds: 0.1, sourceRangeThroughSeconds: 10)))
        XCTAssertEqual(inverse.evaluate(profile: decreasing, targetSeconds: 50), .unavailable(.multipleSolutions))
    }
    func testThresholdAndNonQuantifiedGuidanceDoNotInventAnInverse() {
        let threshold = profile(.threshold(.init(noCorrectionRange: .init(minimumSeconds: 0.0001, maximumSeconds: 1))))
        assertMetered(threshold, 1, 1)
        XCTAssertEqual(inverse.evaluate(profile: threshold, targetSeconds: 2), .unavailable(.noQuantifiedSolution))
        XCTAssertEqual(inverse.evaluate(profile: profile(.limitedGuidance(.init())), targetSeconds: 1), .unavailable(.noQuantifiedSolution))
    }
    func testInvalidAndNumericallyUnrepresentableInputs() {
        XCTAssertEqual(inverse.evaluate(profile: formula(), targetSeconds: .infinity), .unavailable(.invalidInput))
        XCTAssertEqual(inverse.evaluate(profile: formula(0), targetSeconds: 16), .unavailable(.invalidProfile))
        XCTAssertEqual(inverse.evaluate(profile: formula(1e300, 0.001, boundary: 0, upper: nil), targetSeconds: 1), .unavailable(.numericalFailure))
        XCTAssertEqual(inverse.evaluate(profile: formula(1e-300, -0.001, boundary: 0, upper: nil), targetSeconds: 1e300), .unavailable(.numericalFailure), "An identity root cannot prove uniqueness while another active branch is numerically unresolved.")
    }
    func testEveryPresetAndAlternateReturnsOnlyForwardVerifiedRoots() {
        let evaluator = ReciprocityCalculationPolicyEvaluator()
        for film in LaunchPresetFilmCatalogV2.films {
            for profile in film.profiles + AlternateReciprocityModels.alternates(forFilmID: film.id) {
                for metered in [0.01, 0.1, 1, 10, 120, 1000] {
                    guard let target = evaluator.evaluate(profile: profile, meteredExposureSeconds: metered).correctedExposureSeconds else { continue }
                    let inverseResult = inverse.evaluate(profile: profile, targetSeconds: target)
                    if case .available(let root, let result) = inverseResult {
                        XCTAssertTrue(root.isFinite && root > 0)
                        XCTAssertEqual(result, evaluator.evaluate(profile: profile, meteredExposureSeconds: root))
                        XCTAssertEqual(result.correctedExposureSeconds!, target, accuracy: max(1e-9, target * 1e-10))
                    } else {
                        XCTAssertEqual(inverseResult, .unavailable(.multipleSolutions), "A known forward point must have an inverse: \(profile.id), M=\(metered), T=\(target)")
                    }
                }
            }
        }
    }
}
