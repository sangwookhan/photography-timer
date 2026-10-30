// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0
import XCTest
@testable import PTimerCore

final class RequiredNDEvaluatorTests: XCTestCase {
    let evaluator = RequiredNDEvaluator()

    func testDigitalTotalFractionAndUnboundedInventoryIndependentValues() throws {
        try assertStops(10, base: 1, target: 1024)
        try assertStops(10.3, base: 1, target: 1260.691879265195)
        try assertStops(40, base: 1, target: 1099511627776)
        try assertStops(0, base: 1, target: 1)
        try assertStops(2000, base: pow(2, -1000), target: pow(2, 1000))
    }

    func testExactForwardMatchUsesZeroAttenuationWithoutInverseRoundoff() throws {
        let profile = try formula(exponent: 2, coefficient: 1, boundary: 0.5)
        XCTAssertEqual(ReciprocityCalculationPolicyEvaluator().evaluate(profile: profile, meteredExposureSeconds: 8).correctedExposureSeconds, 64)
        try assertStops(0, base: 8, target: 64, profile: profile)
        XCTAssertEqual(evaluator.evaluate(baseSeconds: 9, targetSeconds: 64, profile: profile), .unavailable(.negativeAttenuation))
    }

    func testConstantFormulaBoundaryUsesRealForwardToleranceBeforeClaimingUniqueness() throws {
        let forward = ReciprocityCalculationPolicyEvaluator()
        for boundary in [1.0, 1.0000008] {
            let profile = try formula(exponent: 0, boundary: boundary)
            let secondRoot = boundary + (1.000001 - boundary) / 2
            XCTAssertEqual(forward.evaluate(profile: profile, meteredExposureSeconds: 1).correctedExposureSeconds, 1)
            XCTAssertEqual(forward.evaluate(profile: profile, meteredExposureSeconds: secondRoot).correctedExposureSeconds, 1)
            XCTAssertEqual(evaluator.evaluate(baseSeconds: 1, targetSeconds: 1, profile: profile), .unavailable(.multipleSolutions))
        }
        // No formula segment survives beyond this identity boundary.
        try assertStops(0, base: 1, target: 1, profile: formula(exponent: 0, boundary: 1.000002))
    }

    func testInvalidAndNegativeInputsNeverBecomeZeroOrDigitalFallback() {
        for value in [0, -1, Double.nan, .infinity] {
            XCTAssertEqual(evaluator.evaluate(baseSeconds: value, targetSeconds: 1, profile: nil), .unavailable(.invalidInput))
            XCTAssertEqual(evaluator.evaluate(baseSeconds: 1, targetSeconds: value, profile: nil), .unavailable(.invalidInput))
        }
        XCTAssertEqual(evaluator.evaluate(baseSeconds: 2, targetSeconds: 1, profile: nil), .unavailable(.negativeAttenuation))
    }

    func testSelectedHP5FormulaAndInclusiveIdentityBoundary() throws {
        let hp5 = try catalogProfile("ilford-hp5-plus-400")
        try assertStops(10, base: 1, target: 8779.968205097317, profile: hp5)
        try assertStops(1, base: 0.25, target: 0.5, profile: hp5)
    }

    func testFomapanPublishedAnchorAndNumericContinuation() throws {
        let film = try catalogProfile("foma-fomapan-100")
        try assertStops(log2(10), base: 1, target: 80, profile: film)
        let forward = ReciprocityCalculationPolicyEvaluator().evaluate(profile: film, meteredExposureSeconds: 200)
        let target = try XCTUnwrap(forward.correctedExposureSeconds)
        try assertStops(log2(200), base: 1, target: target, profile: film, beyond: true)
    }

    func testLimitedGuidanceStillAllowsItsNoCorrectionSegment() throws {
        let film = try catalogProfile("kodak-portra-400")
        try assertStops(1, base: 0.25, target: 0.5, profile: film)
        XCTAssertEqual(evaluator.evaluate(baseSeconds: 1, targetSeconds: 3600, profile: film), .unavailable(.noQuantifiedInverse))
    }

    func testDiscontinuousFormulaDoesNotInventInverseAcrossGap() throws {
        let profile = try formula(exponent: 2, coefficient: 1, boundary: 2)
        XCTAssertEqual(evaluator.evaluate(baseSeconds: 1, targetSeconds: 3, profile: profile), .unavailable(.noQuantifiedInverse))
    }

    func testConstantAndDecreasingFormulaDetectMultipleSolutionsIncludingSafetyIdentity() throws {
        for (profile, target) in [
            (try formula(exponent: 0, coefficient: 100), 100.0),
            (try formula(exponent: -1, coefficient: 100), 20.0),
        ] {
            XCTAssertEqual(evaluator.evaluate(baseSeconds: 1, targetSeconds: target, profile: profile), .unavailable(.multipleSolutions))
        }
    }

    func testTablePlateauAndNonmonotonicSegmentsAreNotReportedAsUnique() throws {
        for anchors in [
            [TableAnchor(meteredSeconds: 1, correctedSeconds: 4), TableAnchor(meteredSeconds: 2, correctedSeconds: 4)],
            [TableAnchor(meteredSeconds: 1, correctedSeconds: 10), TableAnchor(meteredSeconds: 2, correctedSeconds: 8), TableAnchor(meteredSeconds: 4, correctedSeconds: 16)],
        ] {
            let profile = try replacingRules([.tableInterpolation(.init(anchors: anchors, noCorrectionThroughSeconds: 0.5, sourceRangeThroughSeconds: anchors.last!.meteredSeconds))])
            let target = anchors.count == 2 ? 4.0 : 9.0
            XCTAssertEqual(evaluator.evaluate(baseSeconds: 0.25, targetSeconds: target, profile: profile), .unavailable(.multipleSolutions))
        }
    }

    func testTableIdentityToleranceUsesExistingForwardPolicy() throws {
        let profile = try replacingRules([.tableInterpolation(.init(anchors: [.init(meteredSeconds: 1, correctedSeconds: 2), .init(meteredSeconds: 10, correctedSeconds: 80)], noCorrectionThroughSeconds: 0.5, sourceRangeThroughSeconds: 10))])
        try assertStops(log2(0.54 / 0.25), base: 0.25, target: 0.54, profile: profile)
    }

    func testScaledOffsetFormulaUsesItsOwnReferenceAndRange() throws {
        let profile = try replacingRules([.formula(.init(formula: .init(coefficientSeconds: 2, referenceMeteredTimeSeconds: 10, exponent: 2, offsetSeconds: 3, noCorrectionThroughSeconds: 0.5, sourceRangeThroughSeconds: 100)))])
        try assertStops(log2(800), base: 0.25, target: 803, profile: profile, beyond: true)
    }

    func testFormulaRuleRetainsPrecedenceOverTableAndThreshold() throws {
        let profile = try replacingRules([
            .tableInterpolation(.init(anchors: [.init(meteredSeconds: 1, correctedSeconds: 2), .init(meteredSeconds: 10, correctedSeconds: 80)], noCorrectionThroughSeconds: 0.5, sourceRangeThroughSeconds: 10)),
            .formula(.init(formula: .init(exponent: 2, noCorrectionThroughSeconds: 1))),
        ])
        try assertStops(4, base: 1, target: 256, profile: profile)
    }

    func testMalformedFormulaIsNumericalFailure() throws {
        let profile = try formula(exponent: .nan)
        XCTAssertEqual(evaluator.evaluate(baseSeconds: 1, targetSeconds: 100, profile: profile), .unavailable(.numericalFailure))
    }

    private func assertStops(_ expected: Double, base: Double, target: Double,
                             profile: ReciprocityProfile? = nil, beyond: Bool = false,
                             file: StaticString = #filePath, line: UInt = #line) throws {
        guard case let .value(stops, actualBeyond) = evaluator.evaluate(baseSeconds: base, targetSeconds: target, profile: profile) else {
            return XCTFail("Expected numeric inverse", file: file, line: line)
        }
        XCTAssertEqual(stops, expected, accuracy: 1e-8, file: file, line: line)
        XCTAssertEqual(actualBeyond, beyond, file: file, line: line)
        if let profile {
            let m = base * pow(2, stops)
            let forward = ReciprocityCalculationPolicyEvaluator().evaluate(profile: profile, meteredExposureSeconds: m)
            XCTAssertEqual(try XCTUnwrap(forward.correctedExposureSeconds), target, accuracy: target * 1e-9, file: file, line: line)
        }
    }

    private func catalogProfile(_ filmID: String) throws -> ReciprocityProfile {
        try XCTUnwrap(LaunchPresetFilmCatalogV2.films.first { $0.id == filmID }?.profiles.first)
    }

    private func formula(exponent: Double, coefficient: Double = 1, boundary: Double = 0.5) throws -> ReciprocityProfile {
        try replacingRules([.formula(.init(formula: .init(coefficientSeconds: coefficient, exponent: exponent, noCorrectionThroughSeconds: boundary)))])
    }

    private func replacingRules(_ rules: [ReciprocityRule]) throws -> ReciprocityProfile {
        let source = try catalogProfile("ilford-hp5-plus-400").source
        return .init(id: "inverse-fixture", name: "Inverse fixture", source: source, rules: rules)
    }
}
