// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import XCTest
import PTimerCore
@testable import PTimerKit

/// PTIMER-187: the timer card renders its basis from structured ND
/// metadata in the current notation mode, shows the final exposure
/// value on the second line, and never repeats a duration in the
/// right column.
final class NDNotationTimerCardTests: XCTestCase {
    /// Deterministic shutter formatter for assertions: `1/30s`, `8s`.
    private let formatShutter: (TimeInterval) -> String = { seconds in
        if seconds < 1 {
            return "1/\(Int((1 / seconds).rounded()))s"
        }
        return "\(Int(seconds.rounded()))s"
    }

    private func timer(
        source: ExposureTimerSource,
        ndStops: Double?,
        baseShutterSeconds: TimeInterval?,
        adjustedShutterSeconds: TimeInterval?,
        duration: TimeInterval = 100,
        status: TimerStatus = .running
    ) -> RunningTimerItem {
        let now = Date(timeIntervalSince1970: 1_000)
        return RunningTimerItem(
            id: UUID(),
            order: 1,
            name: "Timer - 100s",
            basisSummary: "",
            duration: duration,
            startDate: now,
            endDate: now.addingTimeInterval(duration),
            pausedRemainingTime: nil,
            pausedAt: nil,
            status: status,
            referenceDate: now,
            cameraSlot: CameraSlotIdentity(id: .camera1, displayName: "Camera 1"),
            filmDisplayName: "Tri-X 400",
            exposureSource: source,
            ndStops: ndStops,
            baseShutterSeconds: baseShutterSeconds,
            adjustedShutterSeconds: adjustedShutterSeconds
        )
    }

    // MARK: - Basis presenter (notation-aware, inputs only)

    func testBasisRendersInEachNotationModeForAdjustedTimer() {
        let item = timer(
            source: .filmAdjustedShutter,
            ndStops: 9,
            baseShutterSeconds: 1.0 / 30.0,
            adjustedShutterSeconds: 100
        )

        XCTAssertEqual(
            TimerBasisPresenter.basisText(for: item, notationMode: .stops, formatShutter: formatShutter),
            "Base 1/30s · 9 stops"
        )
        XCTAssertEqual(
            TimerBasisPresenter.basisText(for: item, notationMode: .opticalDensity, formatShutter: formatShutter),
            "Base 1/30s · OD 2.7"
        )
        XCTAssertEqual(
            TimerBasisPresenter.basisText(for: item, notationMode: .filterFactor, formatShutter: formatShutter),
            "Base 1/30s · ND512"
        )
    }

    func testAdjustedSegmentOnlyForCorrectedAndTarget() {
        // Adjusted-shutter / digital: no Adj (adjusted == final duration).
        XCTAssertEqual(
            TimerBasisPresenter.basisText(
                for: timer(source: .filmAdjustedShutter, ndStops: 6, baseShutterSeconds: 1.0 / 30.0, adjustedShutterSeconds: 8),
                notationMode: .stops,
                formatShutter: formatShutter
            ),
            "Base 1/30s · 6 stops"
        )
        // Corrected: Adj is a distinct intermediate.
        XCTAssertEqual(
            TimerBasisPresenter.basisText(
                for: timer(source: .filmCorrectedExposure, ndStops: 6, baseShutterSeconds: 1.0 / 30.0, adjustedShutterSeconds: 8),
                notationMode: .stops,
                formatShutter: formatShutter
            ),
            "Base 1/30s · 6 stops · Adj 8s"
        )
        // Target: Adj kept too.
        XCTAssertEqual(
            TimerBasisPresenter.basisText(
                for: timer(source: .targetShutter, ndStops: 6, baseShutterSeconds: 1.0 / 30.0, adjustedShutterSeconds: 8),
                notationMode: .filterFactor,
                formatShutter: formatShutter
            ),
            "Base 1/30s · ND64 · Adj 8s"
        )
    }

    func testBasisNilWithoutStructuredFields() {
        XCTAssertNil(
            TimerBasisPresenter.basisText(
                for: timer(source: .digitalResult, ndStops: nil, baseShutterSeconds: nil, adjustedShutterSeconds: nil),
                notationMode: .stops,
                formatShutter: formatShutter
            )
        )
    }

    // MARK: - Snapshot factory (second line, no duration pair, re-render)

    private func makeSnapshot(
        _ timers: [RunningTimerItem],
        mode: NDNotationMode
    ) -> BottomSheetWorkspaceSnapshot {
        BottomSheetWorkspaceSnapshot.make(
            from: timers,
            formatRemaining: { seconds in
                let s = Int(seconds.rounded(.down))
                return String(format: "%02d:%02d", s / 60, s % 60)
            },
            formatShutter: formatShutter,
            ndNotationMode: mode,
            timeContext: { _ in nil },
            compactCompletedSupplementaryText: { _ in nil }
        )
    }

    func testSecondLineShowsSourceAndFinalValueWithoutFilmOrStops() {
        let item = timer(
            source: .filmCorrectedExposure,
            ndStops: 6,
            baseShutterSeconds: 1.0 / 30.0,
            adjustedShutterSeconds: 8,
            duration: 100.6
        )
        let row = makeSnapshot([item], mode: .stops).sections.first?.items.first

        XCTAssertEqual(row?.identitySubtitle, "Corrected Exposure 01:40")
        XCTAssertEqual(row?.identitySubtitle?.contains("Tri-X 400"), false)
        XCTAssertEqual(row?.identitySubtitle?.contains("stops"), false)
    }

    func testRightColumnShowsStateOnlyWithNoDurationPair() {
        let item = timer(
            source: .filmAdjustedShutter,
            ndStops: 9,
            baseShutterSeconds: 1.0 / 30.0,
            adjustedShutterSeconds: 100,
            duration: 100,
            status: .running
        )
        let row = makeSnapshot([item], mode: .stops).sections.first?.items.first

        // No second duration in the right column (no slash-pair).
        XCTAssertNil(row?.totalDurationText)
        XCTAssertEqual(row?.remainingText.hasSuffix(" left"), true)
    }

    func testBasisReRendersWhenNotationModeChanges() {
        let item = timer(
            source: .filmAdjustedShutter,
            ndStops: 9,
            baseShutterSeconds: 1.0 / 30.0,
            adjustedShutterSeconds: 100
        )

        let stops = makeSnapshot([item], mode: .stops).sections.first?.items.first
        let nd = makeSnapshot([item], mode: .filterFactor).sections.first?.items.first

        XCTAssertEqual(stops?.contextText, "Base 1/30s · 9 stops")
        XCTAssertEqual(nd?.contextText, "Base 1/30s · ND512")
        // Only the basis notation changed; duration is untouched.
        XCTAssertEqual(stops?.remainingText, nd?.remainingText)
    }

    // MARK: - Structured metadata persistence

    func testStructuredFieldsSurvivePersistenceRoundTrip() throws {
        let snapshot = PersistentTimerMetadataSnapshot(
            id: UUID(),
            order: 3,
            name: "Timer - 100s",
            basisSummary: "",
            exposureSourceRaw: ExposureTimerSource.filmCorrectedExposure.rawValue,
            ndStops: 9,
            baseShutterSeconds: 1.0 / 30.0,
            adjustedShutterSeconds: 8
        )

        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(PersistentTimerMetadataSnapshot.self, from: data)

        XCTAssertEqual(decoded.ndStops, 9)
        XCTAssertEqual(try XCTUnwrap(decoded.baseShutterSeconds), 1.0 / 30.0, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(decoded.adjustedShutterSeconds), 8, accuracy: 0.0001)
    }

    // MARK: - Workspace model carries structured ND onto the emitted item

    @MainActor
    func testWorkspaceModelStartCarriesStructuredND() throws {
        let model = TimerWorkspaceModel(
            timerManager: FakeTimerManaging(),
            metadataPersistenceStore: NoOpTimerMetadataPersistenceStore(),
            defaultName: { _ in "Timer" }
        )

        _ = model.startTimer(
            duration: 100,
            name: "Timer - 100s",
            basisSummary: "",
            exposureSource: .filmCorrectedExposure,
            ndStops: 9,
            baseShutterSeconds: 1.0 / 30.0,
            adjustedShutterSeconds: 8
        )

        let item = try XCTUnwrap(model.timers.first)
        XCTAssertEqual(item.ndStops, 9)
        XCTAssertEqual(try XCTUnwrap(item.baseShutterSeconds), 1.0 / 30.0, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(item.adjustedShutterSeconds), 8, accuracy: 0.0001)
    }

    // MARK: - Composer populates structured fields

    func testComposerCapturesStructuredNDAndOmitsAdjustedForDigital() {
        let composer = TimerStartComposer(formatShutter: formatShutter)
        let result = ExposureCalculationResult(
            baseShutterSeconds: 1.0 / 30.0,
            ndStep: NDStep(stops: 9),
            resultShutterSeconds: 17
        )
        let payload = composer.compose(
            TimerStartComposer.Input(
                targetDuration: 17,
                result: result,
                filmModeResult: nil,
                source: .digitalResult,
                selectedPresetFilm: nil,
                selectedProfileOverride: nil,
                activeCameraSlot: nil,
                targetShutterSeconds: nil
            )
        )

        XCTAssertEqual(payload.ndStops, 9)
        XCTAssertEqual(try XCTUnwrap(payload.baseShutterSeconds), 1.0 / 30.0, accuracy: 0.0001)
        // No film-mode result → no reciprocity-adjusted intermediate.
        XCTAssertNil(payload.adjustedShutterSeconds)
    }
}
