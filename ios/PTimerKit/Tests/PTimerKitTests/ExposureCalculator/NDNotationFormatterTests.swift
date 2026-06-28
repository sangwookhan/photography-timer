// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import XCTest
import PTimerCore
@testable import PTimerKit

/// Locks the deterministic ND-notation conversion + rounding policy
/// described on `NDNotationFormatter`. The canonical input is always
/// stops; these assertions are the contract for every display surface.
final class NDNotationFormatterTests: XCTestCase {
    private func inline(_ stops: Double, _ mode: NDNotationMode) -> String {
        NDNotationFormatter.display(forStops: stops, mode: mode).inline
    }

    func testStopsInlineSingularPlural() {
        XCTAssertEqual(inline(0, .stops), "0 stops")
        XCTAssertEqual(inline(1, .stops), "1 stop")
        XCTAssertEqual(inline(3, .stops), "3 stops")
        XCTAssertEqual(inline(9, .stops), "9 stops")
        XCTAssertEqual(inline(10, .stops), "10 stops")
    }

    func testOpticalDensityInline() {
        XCTAssertEqual(inline(0, .opticalDensity), "OD 0.0")
        XCTAssertEqual(inline(1, .opticalDensity), "OD 0.3")
        XCTAssertEqual(inline(3, .opticalDensity), "OD 0.9")
        XCTAssertEqual(inline(9, .opticalDensity), "OD 2.7")
        XCTAssertEqual(inline(10, .opticalDensity), "OD 3.0")
        XCTAssertEqual(inline(14, .opticalDensity), "OD 4.2")
    }

    /// Full integer-stop factor table — the PTIMER compact ND display
    /// policy (PTIMER-187 follow-up). Exact stops must land on clean
    /// power-of-two labels and never drift to a one-significant-figure
    /// bucket.
    func testFilterFactorIntegerStopTable() {
        let expected: [(Double, String)] = [
            (0, "ND1"), (1, "ND2"), (3, "ND8"), (9, "ND512"),
            (10, "ND1000"), (11, "ND2000"), (12, "ND4000"), (13, "ND8000"),
            (14, "ND16K"), (15, "ND32K"), (16, "ND64K"), (17, "ND128K"),
            (18, "ND256K"), (19, "ND512K"), (20, "ND1M"),
        ]
        for (stops, label) in expected {
            XCTAssertEqual(inline(stops, .filterFactor), label, "stops=\(stops)")
        }
    }

    func testFilterFactorNeverUsesCoarseBuckets() {
        // Regression guards for the coarse one-sig-fig bug.
        XCTAssertNotEqual(inline(14, .filterFactor), "ND20k")
        XCTAssertNotEqual(inline(16, .filterFactor), "ND70k")
        XCTAssertNotEqual(inline(17, .filterFactor), "ND70k")
        // Compact suffix is uppercase.
        XCTAssertEqual(inline(14, .filterFactor), "ND16K")
        XCTAssertEqual(inline(16, .filterFactor), "ND64K")
    }

    func testSurfaceFragmentsAreNotDuplicated() {
        let stops = NDNotationFormatter.display(forStops: 9, mode: .stops)
        XCTAssertEqual(stops.value, "9")
        XCTAssertEqual(stops.unit, "stops")
        XCTAssertEqual(stops.inline, "9 stops")

        let od = NDNotationFormatter.display(forStops: 9, mode: .opticalDensity)
        XCTAssertEqual(od.value, "2.7")
        XCTAssertEqual(od.unit, "OD")
        XCTAssertEqual(od.inline, "OD 2.7")

        let nd = NDNotationFormatter.display(forStops: 9, mode: .filterFactor)
        // Picker value carries no `ND` prefix so the band's unit is not duplicated.
        XCTAssertEqual(nd.value, "512")
        XCTAssertEqual(nd.unit, "ND")
        XCTAssertEqual(nd.inline, "ND512")
    }

    func testReservedFractionalStopsRenderMixedFraction() {
        // The shipping picker emits whole stops only; this guards the
        // reserved fractional path the NDStep type still supports.
        XCTAssertEqual(inline(1.0 / 3.0, .stops), "1/3 stops")
        XCTAssertEqual(inline(4.0 / 3.0, .stops), "1 1/3 stops")
    }
}
