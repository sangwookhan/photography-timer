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
        // The reserved third-stop path (still supported by NDStep) keeps
        // its mixed-fraction rendering; only the off-grid commercial
        // presets render as decimals (see the PTIMER-209 tests below).
        XCTAssertEqual(inline(1.0 / 3.0, .stops), "1/3 stops")
        XCTAssertEqual(inline(4.0 / 3.0, .stops), "1 1/3 stops")
    }

    // MARK: - PTIMER-209 commercial fractional presets

    /// The three permanent Stops-wheel presets map to their marketed
    /// labels across all three notations. Stops render as a decimal
    /// (not a third-stop mixed fraction); OD falls out of `stops × 0.3`;
    /// the filter factor uses the commercial label, not `2^stops`.
    func testCommercialPresetsRenderInEveryNotation() {
        struct PresetCase {
            let stops: Double
            let stopsLabel: String
            let od: String
            let nd: String
        }
        let cases: [PresetCase] = [
            PresetCase(stops: 6.6, stopsLabel: "6.6", od: "OD 2.0", nd: "ND100"),
            PresetCase(stops: 7.6, stopsLabel: "7.6", od: "OD 2.3", nd: "ND200"),
            PresetCase(stops: 16.6, stopsLabel: "16.6", od: "OD 5.0", nd: "ND100k"),
        ]
        for testCase in cases {
            XCTAssertEqual(
                NDNotationFormatter.display(forStops: testCase.stops, mode: .stops).value,
                testCase.stopsLabel, "stops value for \(testCase.stops)"
            )
            XCTAssertEqual(inline(testCase.stops, .stops), "\(testCase.stopsLabel) stops")
            XCTAssertEqual(inline(testCase.stops, .opticalDensity), testCase.od, "OD for \(testCase.stops)")
            XCTAssertEqual(inline(testCase.stops, .filterFactor), testCase.nd, "ND for \(testCase.stops)")
        }
    }

    /// Drift guard for the split product definition (stop values live in
    /// `ExposureScale`, factor labels live in the formatter). Every
    /// domain preset must resolve to a commercial factor label — i.e.
    /// an override, not the raw `2^stops` rounding — and the labels must
    /// be distinct. Adding a ladder preset without a matching formatter
    /// label (or vice versa) fails here.
    func testEveryDomainPresetHasADistinctOverriddenFactorLabel() {
        var labels: [String] = []
        for stops in ExposureScale.commercialFractionalNDStops {
            let label = NDNotationFormatter.display(forStops: stops, mode: .filterFactor).value
            XCTAssertNotEqual(
                label, "\(Int(pow(2.0, stops).rounded()))",
                "preset \(stops) must use a commercial label, not the 2^stops value"
            )
            labels.append(label)
        }
        XCTAssertEqual(
            Set(labels).count, ExposureScale.commercialFractionalNDStops.count,
            "each domain preset must map to a distinct commercial label"
        )
    }

    /// Each preset's OD and ND label is unique across the whole ND
    /// ladder, so selecting `ND100k` in one notation and switching to
    /// another round-trips back to the same wheel row — no integer stop
    /// aliases the preset's label.
    func testCommercialPresetLabelsDoNotCollideWithIntegerStops() {
        let ladder = ExposureScale.oneThirdStop.ndSteps.map(\.stops)
        for preset in ExposureScale.commercialFractionalNDStops {
            for mode in [NDNotationMode.opticalDensity, .filterFactor] {
                let presetLabel = NDNotationFormatter.display(forStops: preset, mode: mode).value
                let aliases = ladder.filter { other in
                    abs(other - preset) > ExposureCalculator.stabilityEpsilon
                        && NDNotationFormatter.display(forStops: other, mode: mode).value == presetLabel
                }
                XCTAssertTrue(
                    aliases.isEmpty,
                    "\(mode) label \(presetLabel) for preset \(preset) also produced by stops \(aliases)"
                )
            }
        }
    }
}
