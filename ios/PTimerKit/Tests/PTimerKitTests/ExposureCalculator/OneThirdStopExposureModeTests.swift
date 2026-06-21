// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import XCTest
import PTimerKit
import PTimerCore

/// Focused tests for the one-third-stop exposure calculation mode.
/// The shipping calculator runs on `.oneThirdStop` (Base Shutter
/// 1/3-stop ladder, ND whole-stop), without exposing a runtime
/// scale selector. Fractional `NDStep` support is reserved domain
/// infrastructure (per `docs/specs/Calculator.md` §1.4) and is
/// exercised by the tests below that drive `ndStep` directly.
///
/// Coverage:
/// 1. `ExposureCalculator.calculate(baseShutterSeconds:ndStep:)`
///    honors fractional stops without applying the full-stop snap
///    (reserved-path correctness), and keeps whole-stop behavior
///    byte-for-byte for legacy callers.
/// 2. `CalculatorModel` flips ladder data correctly and routes its
///    calc result through `ndStep`; the default full-stop scale
///    behavior stays unchanged for the reserved scale.
/// 3. `ExposureCalculatorViewModel` exposes the shipping default
///    (`.oneThirdStop` Base Shutter, whole-stop ND) without any UI
///    selector; reserved-path fractional ND values flow into timer
///    duration and the basis-summary label without being silently
///    truncated to an integer.
/// 4. Persistence preserves reserved-path fractional ND through a
///    round-trip via the `ndStopThirds` field, with backward-
///    compatible decoding for legacy snapshots that only carry
///    `ndStop`.
final class OneThirdStopExposureModeTests: XCTestCase {

    // MARK: - Engine reserved fractional-ND path: skip snap; whole-stop legacy still snaps

    func testFractionalNDStepDoesNotSnapToFullStopLadder() throws {
        let calculator = ExposureCalculator()
        // Reserved fractional-ND path: each fractional stop applies its
        // exact factor (zero ND returns the base shutter unchanged).
        let cases: [(Double, Double)] = [
            (0, 1.0),
            (1.0 / 3.0, pow(2.0, 1.0 / 3.0)),
            (2.0 / 3.0, pow(2.0, 2.0 / 3.0)),
        ]
        for (ndStops, factor) in cases {
            let result = try calculator.calculate(
                baseShutterSeconds: 1.0 / 30.0,
                ndStep: NDStep(stops: ndStops)
            )
            XCTAssertEqual(result, (1.0 / 30.0) * factor, accuracy: 1e-9)
        }

        // The 1/3-stop result must NOT collapse onto the nearest full-stop
        // ladder entry; that would defeat the purpose of the new mode.
        let oneThird = try calculator.calculate(
            baseShutterSeconds: 1.0 / 30.0,
            ndStep: NDStep(stops: 1.0 / 3.0)
        )
        XCTAssertNotEqual(oneThird, 1.0 / 30.0, accuracy: 1e-12)
        XCTAssertNotEqual(oneThird, 1.0 / 15.0, accuracy: 1e-12)
    }

    func testWholeStopNDStepPreservesLegacySnapToFullStopBehavior() throws {
        let calculator = ExposureCalculator()
        // Whole-stop NDStep input must reach the same byte-for-byte
        // output as the legacy `(stop: Int)` overload — the snap-to-
        // full-stop ladder is part of the protected calculation
        // contract for whole-stop callers.
        XCTAssertEqual(
            try calculator.calculate(
                baseShutterSeconds: 1.0 / 30.0,
                ndStep: NDStep(stops: 6)
            ),
            try calculator.calculate(baseShutterSeconds: 1.0 / 30.0, stop: 6),
            accuracy: 1e-9
        )
        XCTAssertEqual(
            try calculator.calculate(
                baseShutterSeconds: 1.0,
                ndStep: NDStep(stops: 5)
            ),
            try calculator.calculate(baseShutterSeconds: 1.0, stop: 5),
            accuracy: 1e-9
        )
    }

    func testFractionalNDStepRejectsNonPositiveInputsLikeWholeStopOverload() {
        let calculator = ExposureCalculator()
        XCTAssertThrowsError(
            try calculator.calculate(
                baseShutterSeconds: 0,
                ndStep: NDStep(stops: 1.0 / 3.0)
            )
        ) { error in
            XCTAssertEqual(error as? ExposureCalculatorError, .nonPositiveBaseShutter)
        }
        XCTAssertThrowsError(
            try calculator.calculate(
                baseShutterSeconds: 1.0 / 30.0,
                ndStep: NDStep(stops: -1.0 / 3.0)
            )
        ) { error in
            XCTAssertEqual(error as? ExposureCalculatorError, .nonPositiveND)
        }
    }

    func testExposureCalculationResultStopAccessorRoundsFractionalToNearestInt() {
        let result = ExposureCalculationResult(
            baseShutterSeconds: 1.0 / 30.0,
            ndStep: NDStep(stops: 1.0 / 3.0),
            resultShutterSeconds: 0
        )
        // The legacy `stop: Int` accessor returns the rounded integer
        // for fractional inputs so any caller that still treats it as
        // truth gets a defined value, but the canonical identity stays
        // on `ndStep` (verified by the equality check below).
        XCTAssertEqual(result.stop, 0)
        XCTAssertEqual(result.ndStep.stops, 1.0 / 3.0, accuracy: 1e-9)
        XCTAssertNil(result.ndStep.wholeStops)
    }

    // MARK: - CalculatorModel: scale-mode flip routes through ndStep

    @MainActor
    func testCalculatorModelOnReservedFractionalNDPathDoesNotSnap() {
        // Reserved-path coverage: drives a fractional `NDStep`
        // directly into the model on the shipping `.oneThirdStop`
        // scale (the value never comes from the shipping ND picker,
        // which enumerates whole stops only — see
        // docs/specs/Calculator.md §2.2). Asserts the calc engine
        // honors the fractional value without snapping back to a
        // full-stop ladder.
        let model = CalculatorModel(calculator: ExposureCalculator())
        XCTAssertEqual(model.scaleMode, .oneThirdStop)

        model.ndStep = NDStep(stops: 1.0 / 3.0)

        guard case .success(let result) = model.calculationResult else {
            XCTFail("reserved fractional-ND calculation must succeed for the default base.")
            return
        }

        XCTAssertEqual(
            result.resultShutterSeconds,
            (1.0 / 30.0) * pow(2.0, 1.0 / 3.0),
            accuracy: 1e-9
        )
        XCTAssertEqual(result.ndStep, NDStep(stops: 1.0 / 3.0))
        XCTAssertNil(result.ndStep.wholeStops)
    }

    @MainActor
    func testCalculatorModelReservedFullStopScaleStillSnaps() {
        // The reserved full-stop scale (kept on the model only for
        // tests and the future Settings preference) must continue to
        // apply snap-to-full-stop, byte-for-byte. The shipping
        // calculator never enters this branch through the UI; the
        // tests do, by passing the scale explicitly.
        let model = CalculatorModel(
            calculator: ExposureCalculator(),
            exposureScale: .fullStop
        )

        model.ndStop = 6
        guard case .success(let result) = model.calculationResult else {
            XCTFail("Whole-stop calculation must succeed for the default base.")
            return
        }
        XCTAssertEqual(result.resultShutterSeconds, 2, accuracy: 1e-9)
        XCTAssertEqual(result.ndStep, NDStep(stops: 6))
        XCTAssertEqual(result.stop, 6)
    }

    @MainActor
    func testCalculatorModelScaleModeFlipReSnapsCommittedNDOntoActiveLadder() {
        // A model-level scale flip must collapse a fractional ND value
        // onto the nearest whole-stop boundary when leaving the
        // shipping 1/3-stop scale, so a future Settings preference (or
        // a test harness) cannot leave the model holding a value that
        // is illegal on the active ladder.
        let model = CalculatorModel(calculator: ExposureCalculator())
        model.ndStep = NDStep(stops: 1.0 / 3.0)

        model.scaleMode = .fullStop
        XCTAssertTrue(model.ndStep.isWholeStop)
        XCTAssertEqual(model.ndStep.wholeStops, 0)
    }

    // MARK: - ViewModel: shipping scale is one-third-stop out of the box

    @MainActor
    func testViewModelDefaultScaleModeIsOneThirdStop() {
        let viewModel = ExposureCalculatorViewModel(
            calculator: ExposureCalculator(),
            timerManager: FakeTimerManaging()
        )

        XCTAssertEqual(viewModel.scaleMode, .oneThirdStop)
        XCTAssertEqual(viewModel.exposureScale.mode, .oneThirdStop)

        // Whole-stop arithmetic continues to work — the shipping scale
        // is a strict superset of the legacy full-stop ladder.
        viewModel.baseShutter = 1.0 / 30.0
        viewModel.ndStop = 6
        guard case .success(let result) = viewModel.calculationResult else {
            XCTFail("Whole-stop calculation must succeed in the shipping scale.")
            return
        }
        XCTAssertEqual(
            result.resultShutterSeconds,
            (1.0 / 30.0) * pow(2.0, 6),
            accuracy: 1e-9
        )
        XCTAssertEqual(result.ndStep, NDStep(stops: 6))
    }

    @MainActor
    func testViewModelReservedFractionalNDPathRoutesIntoCalculation() {
        // Reserved-path coverage: a fractional `NDStep` written
        // directly to the ViewModel boundary (the shipping ND picker
        // emits whole stops only — see docs/specs/Calculator.md
        // §2.2). The calc engine must honor the fractional value
        // verbatim through this future-custom / variable-ND path.
        let viewModel = ExposureCalculatorViewModel(
            calculator: ExposureCalculator(),
            timerManager: FakeTimerManaging()
        )

        viewModel.baseShutter = 1.0 / 30.0
        viewModel.ndStep = NDStep(stops: 2.0 / 3.0)

        guard case .success(let result) = viewModel.calculationResult else {
            XCTFail("reserved fractional-ND ViewModel calculation must succeed.")
            return
        }
        XCTAssertEqual(
            result.resultShutterSeconds,
            (1.0 / 30.0) * pow(2.0, 2.0 / 3.0),
            accuracy: 1e-9
        )
        XCTAssertEqual(result.ndStep, NDStep(stops: 2.0 / 3.0))
    }

    @MainActor
    func testViewModelReservedFractionalNDTimerDurationMatchesResult() throws {
        // Reserved-path coverage: when a fractional `NDStep` reaches
        // the ViewModel through the future-custom path (not the
        // shipping ND picker), the timer duration produced by
        // `startTimer` must equal the fractional result, not get
        // truncated to a whole-stop equivalent.
        let viewModel = ExposureCalculatorViewModel(
            calculator: ExposureCalculator(),
            timerManager: FakeTimerManaging()
        )

        viewModel.baseShutter = 1.0
        viewModel.ndStep = NDStep(stops: 1.0 / 3.0)

        viewModel.startTimer()
        let timer = try XCTUnwrap(viewModel.timers.first)
        XCTAssertEqual(timer.duration, pow(2.0, 1.0 / 3.0), accuracy: 1e-9)
    }

    @MainActor
    func testViewModelReservedFractionalNDTimerLabelPreservesFraction() throws {
        // Reserved-path coverage: the fractional-stop component of a
        // future-custom-driven `NDStep` must survive into the
        // human-readable metadata the timer card renders (basis summary
        // and name), including the mixed-fraction form ("1 2/3").
        // Truncating to "0/1 stops" would erase the only hint that the
        // timer was driven by the reserved fractional path. The shipping
        // ND picker emits whole stops only, so these labels never appear
        // for shipping-driven values.
        struct Case {
            let ndStep: NDStep
            let label: String
            let checkName: Bool
        }
        let cases = [
            Case(ndStep: NDStep(stops: 1.0 / 3.0), label: "1/3", checkName: true),
            Case(ndStep: NDStep(stops: 1.0 + 2.0 / 3.0), label: "1 2/3", checkName: false),
        ]

        for testCase in cases {
            let viewModel = ExposureCalculatorViewModel(
                calculator: ExposureCalculator(),
                timerManager: FakeTimerManaging()
            )

            viewModel.baseShutter = 1.0
            viewModel.ndStep = testCase.ndStep

            viewModel.startTimer()
            let timer = try XCTUnwrap(viewModel.timers.first)
            XCTAssertTrue(
                timer.basisSummary.contains(testCase.label),
                "basisSummary should retain reserved ND label \(testCase.label), got: \(timer.basisSummary)"
            )
            if testCase.checkName {
                XCTAssertTrue(
                    timer.name.contains(testCase.label),
                    "timer name should retain reserved ND label \(testCase.label), got: \(timer.name)"
                )
            }
        }
    }

    // MARK: - Persistence: reserved fractional-ND round-trip + legacy decode

    @MainActor
    func testPersistedSnapshotEncodesReservedFractionalAndWholeStopND() {
        // Reserved fractional ND survives via the integer `ndStopThirds`
        // field (no `Double` drift); whole-stop saves keep the legacy
        // `ndStop` field (and leave `ndStopThirds` nil) so PTIMER-79-era
        // persisted data round-trips byte-for-byte. The shipping default
        // is one-third-stop, so a steady-state save omits the scale
        // field; the decoder defaults a missing value to `.oneThirdStop`.
        struct Case {
            let apply: (ExposureCalculatorViewModel) -> Void
            let expected: PersistentCalculatorContextSnapshot
        }
        let cases = [
            Case(
                apply: { $0.ndStep = NDStep(stops: 1.0 / 3.0) },
                expected: PersistentCalculatorContextSnapshot(
                    selectedPresetFilmID: nil,
                    baseShutterSeconds: 1.0 / 30.0,
                    ndStop: nil,
                    ndStopThirds: 1,
                    exposureScaleMode: nil
                )
            ),
            Case(
                apply: { $0.ndStop = 6 },
                expected: PersistentCalculatorContextSnapshot(
                    selectedPresetFilmID: nil,
                    baseShutterSeconds: 1.0 / 30.0,
                    ndStop: 6,
                    ndStopThirds: nil
                )
            ),
        ]

        for testCase in cases {
            let store = InMemoryStore()
            let viewModel = ExposureCalculatorViewModel(
                calculator: ExposureCalculator(),
                timerManager: FakeTimerManaging(),
                contextPersistenceStore: store
            )

            viewModel.baseShutter = 1.0 / 30.0
            testCase.apply(viewModel)

            XCTAssertEqual(store.snapshot, testCase.expected)
        }
    }

    @MainActor
    func testRelaunchRestoresNDFromThirdStopCountOrLegacyInteger() throws {
        // A snapshot whose `ndStopThirds` encodes a fractional value
        // (the shipping ND picker would never write this) restores
        // through the reserved fractional `NDStep` path without `Double`
        // drift. An old PTIMER-79 snapshot that predates `ndStopThirds`
        // falls back to the legacy integer field and restores a
        // whole-stop NDStep so existing user data continues to restore.
        struct Case {
            let snapshot: PersistentCalculatorContextSnapshot
            let expectedNDStep: NDStep
            let expectedNDStop: Int?
        }
        let cases = [
            Case(
                snapshot: PersistentCalculatorContextSnapshot(
                    selectedPresetFilmID: nil,
                    baseShutterSeconds: 1.0 / 30.0,
                    ndStop: nil,
                    ndStopThirds: 2
                ),
                expectedNDStep: NDStep.fromThirdStopCount(2),
                expectedNDStop: nil
            ),
            Case(
                snapshot: PersistentCalculatorContextSnapshot(
                    selectedPresetFilmID: nil,
                    baseShutterSeconds: 1.0 / 30.0,
                    ndStop: 4
                ),
                expectedNDStep: NDStep(stops: 4),
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

            XCTAssertEqual(viewModel.ndStep, testCase.expectedNDStep)
            if let expectedNDStop = testCase.expectedNDStop {
                XCTAssertEqual(viewModel.ndStop, expectedNDStop)
            }
        }
    }

    @MainActor
    func testRelaunchDecodesPTIMER79JSONPayloadWithoutThirdStopField() throws {
        // Goes one level lower than the in-memory store: take the raw
        // JSON shape PTIMER-79 wrote (no `ndStopThirds` key) and feed
        // it through `JSONDecoder` directly. This confirms the
        // backward-compatible decode is real and not just a happy path
        // the in-memory store sets up for us.
        let legacyJSON = Data("""
        {"selectedPresetFilmID":null,"baseShutterSeconds":1.0,"ndStop":4}
        """.utf8)

        let snapshot = try JSONDecoder().decode(
            PersistentCalculatorContextSnapshot.self,
            from: legacyJSON
        )

        XCTAssertEqual(snapshot.ndStop, 4)
        XCTAssertNil(snapshot.ndStopThirds)
        XCTAssertEqual(snapshot.restoredNDStep, NDStep(stops: 4))
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
