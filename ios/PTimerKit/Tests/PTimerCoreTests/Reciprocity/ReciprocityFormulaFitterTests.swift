import XCTest
import PTimerCore

/// PTIMER-179 contract for the runtime power-law fitter.
///
/// Locks the deterministic `Tc = a × Tm^p` fit, the boundary input
/// rejections (insufficient / non-positive / degenerate anchors), and
/// the round-trip that a clean power-law table reproduces its own
/// generating constants.
final class ReciprocityFormulaFitterTests: XCTestCase {

    private func anchor(_ metered: Double, _ corrected: Double) -> TableAnchor {
        TableAnchor(meteredSeconds: metered, correctedSeconds: corrected)
    }

    private func fit(_ anchors: [TableAnchor]) throws -> ReciprocityFormulaFitter.PowerLawFit {
        try ReciprocityFormulaFitter.fit(anchors: anchors).get()
    }

    // MARK: - Deterministic fit

    func testTwoAnchorPowerLawRecoversGeneratingConstants() throws {
        // Tc = 2 × Tm^1.4 sampled at 1s and 100s.
        let a = 2.0
        let p = 1.4
        let anchors = [1.0, 100.0].map { tm in
            anchor(tm, a * pow(tm, p))
        }
        let result = try fit(anchors)
        XCTAssertEqual(result.coefficient, a, accuracy: 1e-9)
        XCTAssertEqual(result.exponent, p, accuracy: 1e-9)
    }

    func testMultiAnchorCleanPowerLawRecoversConstants() throws {
        let a = 1.2102
        let p = 1.3423
        let anchors = [2.0, 4.0, 8.0, 15.0].map { tm in
            anchor(tm, a * pow(tm, p))
        }
        let result = try fit(anchors)
        XCTAssertEqual(result.coefficient, a, accuracy: 1e-6)
        XCTAssertEqual(result.exponent, p, accuracy: 1e-6)
    }

    func testFitIsDeterministicAcrossRepeatedCalls() throws {
        let anchors = [anchor(1, 2), anchor(10, 50), anchor(100, 1_600)]
        let first = try fit(anchors)
        let second = try fit(anchors)
        XCTAssertEqual(first, second)
    }

    func testFitIsIndependentOfAnchorOrder() throws {
        let ascending = [anchor(1, 2), anchor(10, 50), anchor(100, 1_600)]
        let shuffled = [anchor(100, 1_600), anchor(1, 2), anchor(10, 50)]
        XCTAssertEqual(try fit(ascending), try fit(shuffled))
    }

    // MARK: - Unavailable inputs

    func testSingleAnchorIsInsufficient() {
        XCTAssertEqual(
            ReciprocityFormulaFitter.fit(anchors: [anchor(1, 2)]),
            .failure(.insufficientAnchors)
        )
    }

    func testEmptyAnchorsAreInsufficient() {
        XCTAssertEqual(
            ReciprocityFormulaFitter.fit(anchors: []),
            .failure(.insufficientAnchors)
        )
    }

    func testNonPositiveMeteredIsRejected() {
        XCTAssertEqual(
            ReciprocityFormulaFitter.fit(anchors: [anchor(0, 2), anchor(10, 50)]),
            .failure(.nonPositiveAnchors)
        )
    }

    func testNonFiniteCorrectedIsRejected() {
        XCTAssertEqual(
            ReciprocityFormulaFitter.fit(anchors: [anchor(1, .nan), anchor(10, 50)]),
            .failure(.nonPositiveAnchors)
        )
    }

    func testDegenerateEqualMeteredAnchorsAreRejected() {
        XCTAssertEqual(
            ReciprocityFormulaFitter.fit(anchors: [anchor(10, 20), anchor(10, 40)]),
            .failure(.degenerateAnchors)
        )
    }
}
