// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import Combine
import PTimerKit
import PTimerCore
import XCTest

/// ViewModel-level coverage for the shipping one-third-stop
/// calculator scale (per `docs/specs/Calculator.md` §1.4). The
/// shipping calculator does not expose a runtime scale selector —
/// the one-third-stop scale is the only user-facing scale, applies
/// to the **Base Shutter ladder only**, and the ND picker stays
/// whole-stop in every shipping mode. The reserved full-stop scale
/// stays in the model only for regression coverage and the future
/// Settings preference; the tests below assert that contract.
///
/// Coverage:
/// 1. Default `scaleMode` is `.oneThirdStop`; out of the box the
///    picker data sources are the 1/3-stop densified shutter ladder
///    paired with the whole-stop ND ladder (`0…30`).
/// 2. The camera-facing shutter label LUT renders sub-1 s rows as
///    `1/N` fractions (including the slow end `1/1.3, 1/1.6, 1/2`)
///    and ≥ 1 s rows as integer / `N.Ns` per the Nikon Z7 ladder.
/// 3. The ND label formatter renders shipping whole-stop values as
///    bare integers; the mixed-fraction renderer is exercised
///    through the reserved fractional path so future custom-ND
///    workflows do not lose the fractional component.
/// 4. Persistence round-trips the scale token; legacy snapshots
///    without the new field restore as `.oneThirdStop` (the
///    shipping default).
final class ExposureScaleModeUITests: XCTestCase {

    // MARK: - Default scale is one-third-stop without any UI flip

    @MainActor
    func testDefaultViewModelExposesOneThirdStopShutterAndWholeStopND() {
        let viewModel = makeViewModel()

        XCTAssertEqual(viewModel.scaleMode, .oneThirdStop)
        XCTAssertEqual(viewModel.exposureScale.mode, .oneThirdStop)

        // Shutter picker is the densified 55-entry ladder.
        XCTAssertEqual(
            viewModel.pickerShutterStepSeconds.count,
            ExposureScale.oneThirdStop.shutterSteps.count
        )

        // ND picker is whole-stop only (per docs/specs/Calculator.md
        // §2.2). One-third-stop applies to the shutter ladder only;
        // the ND picker stays on whole stops because real-world fixed
        // ND filters are sold in whole-stop strengths.
        XCTAssertEqual(viewModel.pickerNDSteps.count, 31)
        XCTAssertEqual(viewModel.pickerNDSteps.map(\.stops), (0...30).map { Double($0) })
        XCTAssertTrue(
            viewModel.pickerNDSteps.allSatisfy { $0.isWholeStop },
            "shipping ND picker must not surface fractional 1/3-stop entries"
        )
        XCTAssertEqual(viewModel.pickerWholeNDStops, Array(0...30))
    }

    @MainActor
    func testShippingNDPickerOptionsAroundSevenAreWholeStopsOnly() {
        // Regression for the reported screenshot: the ND option
        // values straddling the `7-stop` row must be `6, 7, 8` — never
        // `7 1/3` or `7 2/3`. Asserted both by canonical stops and by
        // the formatted picker label.
        let viewModel = makeViewModel()

        let labels = viewModel.pickerNDSteps.map { viewModel.formatNDStop($0) }
        XCTAssertFalse(
            labels.contains("7 1/3"),
            "shipping ND picker must not enumerate `7 1/3`"
        )
        XCTAssertFalse(
            labels.contains("7 2/3"),
            "shipping ND picker must not enumerate `7 2/3`"
        )
        for label in labels {
            XCTAssertFalse(
                label.contains("/"),
                "shipping ND picker label \(label) must not contain a fraction"
            )
        }

        guard let sevenIndex = viewModel.pickerNDSteps.firstIndex(where: { $0.wholeStops == 7 }) else {
            XCTFail("shipping ND ladder must include the 7-stop entry")
            return
        }
        XCTAssertGreaterThan(sevenIndex, 0)
        XCTAssertLessThan(sevenIndex + 1, viewModel.pickerNDSteps.count)
        XCTAssertEqual(viewModel.pickerNDSteps[sevenIndex - 1].wholeStops, 6)
        XCTAssertEqual(viewModel.pickerNDSteps[sevenIndex].wholeStops, 7)
        XCTAssertEqual(viewModel.pickerNDSteps[sevenIndex + 1].wholeStops, 8)
    }

    // MARK: - Snap policy: the shipping scale never snaps

    func testEngineFractionalShutterInOneThirdStopDoesNotSnap() throws {
        // In the shipping 1/3-stop scale the calc engine must not
        // collapse a fractional shutter back to the nearest full-stop
        // entry, regardless of the whole-stop ND applied (including 0).
        let calculator = ExposureCalculator()

        struct Case {
            let shutterStops: Double
            let ndStops: Double
            let accuracy: Double
        }
        let cases = [
            Case(shutterStops: 1.0 / 3.0, ndStops: 0, accuracy: 1e-12),
            Case(shutterStops: 2.0 / 3.0, ndStops: 10, accuracy: 1e-6),
        ]

        for testCase in cases {
            let fractionalShutter = (1.0 / 30.0) * pow(2.0, testCase.shutterStops)
            let result = try calculator.calculate(
                baseShutterSeconds: fractionalShutter,
                ndStep: NDStep(stops: testCase.ndStops),
                scaleMode: .oneThirdStop
            )
            XCTAssertEqual(
                result,
                fractionalShutter * pow(2.0, testCase.ndStops),
                accuracy: testCase.accuracy
            )
        }

        // The zero-ND fractional shutter must not collapse onto the
        // nearest full-stop entry.
        let zeroNDShutter = (1.0 / 30.0) * pow(2.0, 1.0 / 3.0)
        XCTAssertNotEqual(
            try calculator.calculate(
                baseShutterSeconds: zeroNDShutter,
                ndStep: NDStep(stops: 0),
                scaleMode: .oneThirdStop
            ),
            1.0 / 30.0,
            accuracy: 1e-12
        )
    }

    func testEngineWholeStopCallsStillSnapInReservedFullStopMode() throws {
        // The legacy `calculate(baseShutterSeconds:stop:)` overload and
        // the explicit `.fullStop` `ndStep` overload must continue to
        // apply snap-to-full-stop, byte-for-byte. Snap is now a
        // characteristic of the reserved full-stop scale only.
        let calculator = ExposureCalculator()

        XCTAssertEqual(
            try calculator.calculate(baseShutterSeconds: 1.0 / 30.0, stop: 6),
            2,
            accuracy: 1e-9
        )
        XCTAssertEqual(
            try calculator.calculate(
                baseShutterSeconds: 1.0 / 30.0,
                ndStep: NDStep(stops: 6),
                scaleMode: .fullStop
            ),
            2,
            accuracy: 1e-9
        )
    }

    @MainActor
    func testViewModelReservedFractionalPathsCalculateWithoutSnapping() {
        // Drives the reserved fractional paths directly through the
        // ViewModel boundary (the shipping ND picker emits whole stops
        // only; these cases exercise the reserved infrastructure so a
        // future custom-ND workflow stays calc-correct). A fractional
        // base shutter with zero ND passes through unsnapped, and a
        // fractional ND applies its exact factor.
        let fractionalShutter = (1.0 / 30.0) * pow(2.0, 1.0 / 3.0)

        struct Case {
            let baseShutter: Double
            let ndStep: NDStep
            let expected: Double
            let expectedNDStep: NDStep?
        }
        let cases = [
            Case(
                baseShutter: fractionalShutter,
                ndStep: NDStep(stops: 0),
                expected: fractionalShutter,
                expectedNDStep: nil
            ),
            Case(
                baseShutter: 1.0,
                ndStep: NDStep(stops: 1.0 / 3.0),
                expected: pow(2.0, 1.0 / 3.0),
                expectedNDStep: NDStep(stops: 1.0 / 3.0)
            ),
        ]

        for testCase in cases {
            let viewModel = makeViewModel()
            viewModel.baseShutter = testCase.baseShutter
            viewModel.ndStep = testCase.ndStep

            guard case .success(let result) = viewModel.calculationResult else {
                XCTFail("reserved fractional path should succeed for ndStep \(testCase.ndStep).")
                return
            }
            XCTAssertEqual(result.resultShutterSeconds, testCase.expected, accuracy: 1e-9)
            if let expectedNDStep = testCase.expectedNDStep {
                XCTAssertEqual(result.ndStep, expectedNDStep)
            }
        }
    }

    // MARK: - Camera-facing shutter labels (Nikon Z7 LUT)

    @MainActor
    func testDefaultShutterPickerKeepsAllSubSecondValuesAsFractions() {
        let viewModel = makeViewModel()

        // The 1/3-stop intermediates above 1/30 are canonically
        // `(1/30) · 2^(1/3) ≈ 0.042` and `(1/30) · 2^(2/3) ≈ 0.053`.
        // The camera-facing labels are the dial values the photographer
        // actually selects (`1/25`, `1/20`), not `0.042s`.
        let cameraLower = (1.0 / 30.0) * pow(2.0, 1.0 / 3.0)
        let cameraUpper = (1.0 / 30.0) * pow(2.0, 2.0 / 3.0)
        XCTAssertEqual(viewModel.formatShutterStepLabel(cameraLower), "1/25")
        XCTAssertEqual(viewModel.formatShutterStepLabel(cameraUpper), "1/20")

        // Sub-1s values stay in `1/N` notation across the whole slow
        // range — the picker should never render `0.5s` for the
        // 1/2-second anchor. Above 1s the convention switches to
        // decimal seconds (`1s, 1.3s, 1.6s`).
        let oneThird     = 0.25 * pow(2.0, 1.0 / 3.0)  // (1/4)·2^(1/3) ≈ 0.315
        let oneOverTwoP5 = 0.25 * pow(2.0, 2.0 / 3.0)  // (1/4)·2^(2/3) ≈ 0.397
        let oneHalf      = 0.5                         // 1/2 anchor
        let oneOverOneP6 = 0.5 * pow(2.0, 1.0 / 3.0)   // (1/2)·2^(1/3) ≈ 0.63
        let oneOverOneP3 = 0.5 * pow(2.0, 2.0 / 3.0)   // (1/2)·2^(2/3) ≈ 0.794
        let oneSecond    = 1.0
        let onePoint3    = 1.0 * pow(2.0, 1.0 / 3.0)
        let onePoint6    = 1.0 * pow(2.0, 2.0 / 3.0)

        XCTAssertEqual(viewModel.formatShutterStepLabel(oneThird), "1/3")
        XCTAssertEqual(viewModel.formatShutterStepLabel(oneOverTwoP5), "1/2.5")
        XCTAssertEqual(viewModel.formatShutterStepLabel(oneHalf), "1/2")
        XCTAssertEqual(viewModel.formatShutterStepLabel(oneOverOneP6), "1/1.6")
        // The 0.794s position uses the Nikon Z7-derived `1/1.3` label.
        XCTAssertEqual(viewModel.formatShutterStepLabel(oneOverOneP3), "1/1.3")
        XCTAssertEqual(viewModel.formatShutterStepLabel(oneSecond), "1s")
        XCTAssertEqual(viewModel.formatShutterStepLabel(onePoint3), "1.3s")
        XCTAssertEqual(viewModel.formatShutterStepLabel(onePoint6), "1.6s")
    }

    @MainActor
    func testDefaultShutterLabelSequenceMatchesNikonLadderAroundOneSecond() {
        let viewModel = makeViewModel()

        // Walk a 23-row window of the ladder around the 1-second
        // anchor in step order (slow → fast). The labels must follow
        // the Nikon Z7 sequence below verbatim. Pulling values straight
        // off the canonical ladder keeps this test honest about the
        // labels-track-canonical-seconds invariant.
        let ladder = viewModel.pickerShutterStepSeconds
        guard let fifteenSecondIndex = ladder.firstIndex(where: {
            abs($0 - 15.0) <= 1e-9
        }) else {
            XCTFail("1/3-stop shutter ladder must include the 15s anchor")
            return
        }

        let expected: [String] = [
            "15s", "13s", "10s",
            "8s", "6s", "5s",
            "4s", "3s", "2.5s",
            "2s", "1.6s", "1.3s",
            "1s", "1/1.3", "1/1.6",
            "1/2", "1/2.5", "1/3",
            "1/4", "1/5", "1/6",
            "1/8", "1/10",
        ]

        // The 15s anchor is at the slow end; ladder indices ascend
        // with seconds, so slow→fast = stepping down by one index.
        let slowToFastIndices = (0..<expected.count).map { fifteenSecondIndex - $0 }
        let firstIndex = slowToFastIndices.last ?? 0
        XCTAssertGreaterThanOrEqual(firstIndex, 0)
        XCTAssertLessThan(fifteenSecondIndex, ladder.count)

        let labels = slowToFastIndices.map {
            viewModel.formatShutterStepLabel(ladder[$0])
        }

        XCTAssertEqual(
            labels,
            expected,
            "labels around 1s must follow the Nikon Z7 sequence (slow→fast)"
        )
    }

    @MainActor
    func testDefaultShutterLadderIndexAdvanceMatchesStopArithmetic() {
        let viewModel = makeViewModel()

        // In the shipping 1/3-stop scale, scale movement advances by
        // stop-step index. One whole stop equals three 1/3-stop
        // increments, so `1/10 + 3 stops` is `1/10 + 9 ladder
        // positions`, which must land on the row labeled `1/1.3`.
        let ladder = viewModel.pickerShutterStepSeconds
        guard let oneOverTenIndex = ladder.firstIndex(where: {
            viewModel.formatShutterStepLabel($0) == "1/10"
        }) else {
            XCTFail("1/3-stop ladder must include a 1/10 row")
            return
        }

        let advancedIndex = oneOverTenIndex + 9
        XCTAssertLessThan(advancedIndex, ladder.count)
        XCTAssertEqual(
            viewModel.formatShutterStepLabel(ladder[advancedIndex]),
            "1/1.3"
        )
    }

    @MainActor
    func testDefaultShutterLabelsContainNoDecimalSecondsBelowOne() {
        let viewModel = makeViewModel()

        // Catch any future LUT regression that re-introduces a sub-1s
        // decimal-seconds label like `0.5s`.
        for seconds in viewModel.pickerShutterStepSeconds where seconds < 1 {
            let label = viewModel.formatShutterStepLabel(seconds)
            XCTAssertTrue(
                label.hasPrefix("1/"),
                "sub-1s label \(label) for seconds=\(seconds) should be a fraction"
            )
            XCTAssertFalse(
                label.contains("s"),
                "sub-1s label \(label) for seconds=\(seconds) must not include the seconds suffix"
            )
        }
    }

    // MARK: - SwiftUI redraw via objectWillChange

    @MainActor
    func testFractionalNDStepWriteEmitsObjectWillChange() {
        // Reserved-path coverage: a fractional `NDStep` write must
        // still emit `objectWillChange` even though the shipping ND
        // picker only emits whole-stop values, so a future custom /
        // variable-ND workflow that drives `ndStep` directly does not
        // skip a SwiftUI redraw.
        let viewModel = makeViewModel()
        var emissionCount = 0
        let cancellable = viewModel.objectWillChange.sink { _ in emissionCount += 1 }

        viewModel.ndStep = NDStep(stops: 1.0 / 3.0)

        XCTAssertGreaterThan(
            emissionCount,
            0,
            "fractional NDStep reserved-path write must emit objectWillChange so the result card refreshes."
        )
        cancellable.cancel()
    }

    // MARK: - ND label formatter

    @MainActor
    func testFormatNDStopRendersWholeAndReservedFractionalValues() {
        // Whole-stop values render as bare integers; the reserved
        // fractional path (the shipping ND picker emits whole stops
        // only) must still render mixed fractions so a future custom-ND
        // workflow that drives `formatNDStop` does not lose the
        // fractional component.
        let viewModel = makeViewModel()
        let cases: [(NDStep, String)] = [
            (NDStep(stops: 0), "0"),
            (NDStep(stops: 1), "1"),
            (NDStep(stops: 6), "6"),
            (NDStep(stops: 1.0 / 3.0), "1/3"),
            (NDStep(stops: 2.0 / 3.0), "2/3"),
            (NDStep(stops: 1.0 + 1.0 / 3.0), "1 1/3"),
            (NDStep(stops: 1.0 + 2.0 / 3.0), "1 2/3"),
        ]
        for (ndStep, expected) in cases {
            XCTAssertEqual(viewModel.formatNDStop(ndStep), expected)
        }
    }

    // MARK: - Live preview round-trip via NDStep

    @MainActor
    func testUpdateLiveNDStepDrivesEffectiveCalculationWithoutMutatingCommitted() {
        // Live-preview reserved-path coverage: writing a fractional
        // `NDStep` to the live overlay drives the calc result while
        // leaving the committed `ndStep` at zero. The shipping ND
        // picker writes whole-stop values; this test pins the
        // reserved fractional path so it stays calc-correct.
        let viewModel = makeViewModel()
        viewModel.ndStep = NDStep(stops: 0)

        viewModel.updateLiveNDStep(NDStep(stops: 1.0 / 3.0))

        guard case .success(let result) = viewModel.calculationResult else {
            XCTFail("reserved fractional ND live preview should drive a successful calc.")
            return
        }
        XCTAssertEqual(
            result.resultShutterSeconds,
            (1.0 / 30.0) * pow(2.0, 1.0 / 3.0),
            accuracy: 1e-9
        )
        // Committed `ndStep` must remain at zero — the live preview
        // is ephemeral state for the in-flight wheel drag.
        XCTAssertEqual(viewModel.ndStep, NDStep(stops: 0))
    }

    // MARK: - Persistence round-trip + legacy decode

    @MainActor
    func testRelaunchRestoresScaleAndNDFromSnapshot() {
        // A snapshot that carries the scale token plus a reserved
        // fractional ND restores both. An older snapshot (pre-default-
        // flip) that omits the `exposureScaleMode` field must restore as
        // the shipping `.oneThirdStop` scale (per docs/specs/Calculator.md
        // §5) and accept a legacy whole-stop ND value, because the
        // shipping ladder is a strict superset.
        struct Case {
            let snapshot: PersistentCalculatorContextSnapshot
            let expectedNDStep: NDStep?
            let expectedNDStop: Int?
        }
        let cases = [
            Case(
                snapshot: PersistentCalculatorContextSnapshot(
                    selectedPresetFilmID: nil,
                    baseShutterSeconds: 1.0 / 30.0,
                    ndStop: nil,
                    ndStopThirds: 1,
                    exposureScaleMode: ExposureScaleMode.oneThirdStop.rawValue
                ),
                expectedNDStep: NDStep.fromThirdStopCount(1),
                expectedNDStop: nil
            ),
            Case(
                snapshot: PersistentCalculatorContextSnapshot(
                    selectedPresetFilmID: nil,
                    baseShutterSeconds: 1.0 / 30.0,
                    ndStop: 4,
                    ndStopThirds: nil,
                    exposureScaleMode: nil
                ),
                expectedNDStep: nil,
                expectedNDStop: 4
            ),
        ]

        for testCase in cases {
            let store = InMemoryStore()
            store.saveSnapshot(testCase.snapshot)
            let viewModel = ExposureCalculatorViewModel(
                calculator: ExposureCalculator(),
                timerManager: FakeTimerManaging(),
                contextPersistenceStore: store
            )

            XCTAssertEqual(viewModel.scaleMode, .oneThirdStop)
            XCTAssertEqual(viewModel.baseShutter, 1.0 / 30.0, accuracy: 1e-9)
            if let expectedNDStep = testCase.expectedNDStep {
                XCTAssertEqual(viewModel.ndStep, expectedNDStep)
            }
            if let expectedNDStop = testCase.expectedNDStop {
                XCTAssertEqual(viewModel.ndStop, expectedNDStop)
            }
        }
    }

    func testRelaunchDecodesLegacyJSONWithoutScaleModeFieldAsOneThirdStop() throws {
        // Goes through the raw decoder so we are testing the schema
        // change end-to-end rather than relying on the in-memory store
        // to set up the right shape.
        let legacyJSON = Data("""
        {"selectedPresetFilmID":null,"baseShutterSeconds":1.0,"ndStop":4}
        """.utf8)

        let snapshot = try JSONDecoder().decode(
            PersistentCalculatorContextSnapshot.self,
            from: legacyJSON
        )

        XCTAssertNil(snapshot.exposureScaleMode)
        XCTAssertEqual(snapshot.restoredScaleMode, .oneThirdStop)
    }

    // MARK: - Reset returns to the shipping default

    @MainActor
    func testResetFilmModeWorkingContextRestoresShippingOneThirdStop() {
        // `canReset` should report true when the working context
        // drifts from the shipping default. Here the drift is
        // produced by a **reserved-path fractional ND write** —
        // the shipping ND picker emits whole stops only, so this
        // setup exercises the reserved fractional `NDStep` write
        // surface directly. The reset must drop the film, clear ND
        // (including any reserved-path fractional drift), and
        // leave the model on the shipping `.oneThirdStop` scale.
        let viewModel = makeViewModel()
        viewModel.ndStep = NDStep(stops: 2.0 / 3.0)
        XCTAssertTrue(viewModel.canResetFilmModeWorkingContext)

        viewModel.resetFilmModeWorkingContext()

        XCTAssertEqual(viewModel.scaleMode, .oneThirdStop)
        XCTAssertEqual(viewModel.ndStop, 0)
        XCTAssertEqual(viewModel.ndStep, NDStep(stops: 0))
        XCTAssertFalse(viewModel.canResetFilmModeWorkingContext)
    }

    @MainActor
    private func makeViewModel() -> ExposureCalculatorViewModel {
        ExposureCalculatorViewModel(
            calculator: ExposureCalculator(),
            timerManager: FakeTimerManaging()
        )
    }
}

private final class InMemoryStore: ExposureCalculatorContextStoring {
    private(set) var snapshot: PersistentCalculatorContextSnapshot?

    func loadSnapshot() -> PersistentCalculatorContextSnapshot? {
        snapshot
    }

    func saveSnapshot(_ snapshot: PersistentCalculatorContextSnapshot) {
        self.snapshot = snapshot
    }

    func clearSnapshot() {
        snapshot = nil
    }
}
