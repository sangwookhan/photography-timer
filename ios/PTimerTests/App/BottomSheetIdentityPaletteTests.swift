import SwiftUI
import PTimerKit
import PTimerCore
import UIKit
import XCTest
@testable import PTimer

final class BottomSheetIdentityPaletteTests: XCTestCase {
    func testIdentityCueStaysConsistentAcrossCompactAndLargePresentations() {
        let snapshot = makeSnapshot(from: sampleTimers())
        let compactByID = Dictionary(uniqueKeysWithValues: snapshot.compactItems.map { ($0.id, $0.identityCue) })
        let largeByID = Dictionary(
            uniqueKeysWithValues: snapshot.sections.flatMap(\.items).map { ($0.id, $0.identityCue) }
        )

        XCTAssertEqual(compactByID[UUID(uuidString: "33333333-3333-3333-3333-333333333333")!], largeByID[UUID(uuidString: "33333333-3333-3333-3333-333333333333")!])
        XCTAssertEqual(compactByID[UUID(uuidString: "22222222-2222-2222-2222-222222222222")!], largeByID[UUID(uuidString: "22222222-2222-2222-2222-222222222222")!])
        XCTAssertEqual(compactByID[UUID(uuidString: "11111111-1111-1111-1111-111111111111")!], largeByID[UUID(uuidString: "11111111-1111-1111-1111-111111111111")!])
    }

    func testIdentityCueRemainsStableWhenTimerMovesToCompletedSection() {
        let now = Date(timeIntervalSince1970: 9_000)
        let timerID = UUID(uuidString: "abababab-abab-abab-abab-abababababab")!
        let runningTimer = RunningTimerItem(
            id: timerID,
            order: 9,
            name: "Completion Shift",
            basisSummary: "Base 1/30s · 6 stops",
            duration: 90,
            startDate: now.addingTimeInterval(-15),
            endDate: now.addingTimeInterval(75),
            pausedRemainingTime: nil,
            pausedAt: nil,
            status: .running,
            referenceDate: now
        )
        let completedTimer = RunningTimerItem(
            id: timerID,
            order: 9,
            name: "Completion Shift",
            basisSummary: "Base 1/30s · 6 stops",
            duration: 90,
            startDate: now.addingTimeInterval(-90),
            endDate: now.addingTimeInterval(-1),
            pausedRemainingTime: nil,
            pausedAt: nil,
            status: .completed,
            referenceDate: now
        )

        let runningSnapshot = makeSnapshot(from: [runningTimer])
        let completedSnapshot = makeSnapshot(from: [completedTimer])

        XCTAssertEqual(runningSnapshot.compactItems.first?.identityCue, completedSnapshot.compactItems.first?.identityCue)
        XCTAssertEqual(runningSnapshot.sections.first?.items.first?.identityCue, completedSnapshot.sections.first?.items.first?.identityCue)
    }

    func testMultipleTimersGetDistinguishableIdentityCues() {
        let snapshot = makeSnapshot(from: sampleTimers())
        let visibleCompactCues = snapshot.compactItems.map(\.identityCue)

        XCTAssertEqual(Set(visibleCompactCues.map(\.markerText)).count, 3)
        XCTAssertGreaterThanOrEqual(Set(visibleCompactCues.map(\.tintSlot)).count, 2)
    }

    @MainActor
    func testCompactIdentityCueRemainsSeparateFromPrimaryAndSecondaryTimeText() throws {
        let snapshot = makeSnapshot(from: sampleTimers())
        let item = try XCTUnwrap(snapshot.compactItems.first)

        XCTAssertEqual(item.identityCue.markerText, "T2")
        XCTAssertFalse(item.primaryRemainingText.contains(item.identityCue.markerText))
        XCTAssertFalse((item.secondaryTotalText ?? "").contains(item.identityCue.markerText))
        XCTAssertEqual(item.primaryRemainingText, "55s")
        XCTAssertEqual(item.secondaryTotalText, "03:00")
    }

    @MainActor
    func testLargeIdentityCueRemainsSeparateFromTitleTimeAndStatusValues() throws {
        let snapshot = makeSnapshot(from: sampleTimers())
        let row = try XCTUnwrap(snapshot.sections.first?.items.first)

        XCTAssertEqual(row.identityCue.markerText, "T2")
        XCTAssertFalse((row.title ?? "").contains(row.identityCue.markerText))
        XCTAssertFalse(row.statusLabel.contains(row.identityCue.markerText))
        XCTAssertFalse(row.remainingText.contains(row.identityCue.markerText))
        XCTAssertFalse((row.totalDurationText ?? "").contains(row.identityCue.markerText))
        XCTAssertFalse((row.timingText ?? "").contains(row.identityCue.markerText))
        XCTAssertFalse((row.contextText ?? "").contains(row.identityCue.markerText))
    }

    @MainActor
    func testOverflowCardKeepsViewAllRoleWithoutTimerIdentityMarker() {
        let snapshot = makeSnapshot(from: sampleTimers())

        XCTAssertEqual(snapshot.compactOverflowText, "+1")
        XCTAssertEqual(snapshot.hiddenCompactItemCount, 1)
        XCTAssertEqual(snapshot.compactItems.map(\.identityCue.markerText), ["T2", "T1", "T3"])
        XCTAssertFalse(snapshot.compactItems.map(\.identityCue.markerText).contains("T4"))
    }

    // MARK: - Camera-slot + film identity surfacing

    @MainActor
    func testCompactCueShowsCameraShortLabelAndFilmDescriptorWhenSnapshotPresent() throws {
        let timer = makeIdentityTimer(
            cameraSlot: CameraSlotIdentity(id: .camera2),
            filmDisplayName: "CHS 100 II",
            exposureSource: .filmAdjustedShutter
        )

        let snapshot = makeSnapshot(from: [timer])
        let item = try XCTUnwrap(snapshot.compactItems.first)

        XCTAssertEqual(item.identityCue.markerText, "C2")
        XCTAssertEqual(item.identityCue.fullCameraLabel, "Camera 2")
        XCTAssertEqual(item.identityCue.filmDescriptor, "CHS 100 II")
        XCTAssertEqual(item.identityCue.sourceLabel, "Adjusted Shutter")
        XCTAssertEqual(item.identityFilmText, "CHS 100 II")
    }

    @MainActor
    func testCompactCueRendersNoFilmForDigitalTimer() throws {
        let timer = makeIdentityTimer(
            cameraSlot: CameraSlotIdentity(id: .camera1),
            filmDisplayName: nil,
            exposureSource: .digitalResult
        )

        let snapshot = makeSnapshot(from: [timer])
        let item = try XCTUnwrap(snapshot.compactItems.first)

        XCTAssertEqual(item.identityCue.markerText, "C1")
        XCTAssertEqual(item.identityCue.filmDescriptor, "No film")
        XCTAssertEqual(item.identityFilmText, "No film")
    }

    @MainActor
    func testLargeTitleIsCameraDotFilmAndSubtitleCarriesExposureSource() throws {
        let timer = makeIdentityTimer(
            cameraSlot: CameraSlotIdentity(id: .camera2),
            filmDisplayName: "CHS 100 II",
            exposureSource: .filmAdjustedShutter,
            order: 7,
            name: "16 stops - 832255.3s"
        )

        let snapshot = makeSnapshot(from: [timer])
        let row = try XCTUnwrap(snapshot.sections.first?.items.first)

        XCTAssertEqual(row.title, "Camera 2 · CHS 100 II")
        XCTAssertEqual(row.identitySubtitle, "Adjusted Shutter · 16 stops - 832255.3s")
    }

    @MainActor
    func testLargeTitleShowsNoFilmForDigitalTimerWithSlot() throws {
        let timer = makeIdentityTimer(
            cameraSlot: CameraSlotIdentity(id: .camera4),
            filmDisplayName: nil,
            exposureSource: .digitalResult
        )

        let snapshot = makeSnapshot(from: [timer])
        let row = try XCTUnwrap(snapshot.sections.first?.items.first)

        XCTAssertEqual(row.title, "Camera 4 · No film")
    }

    @MainActor
    func testLargeVoiceOverLabelIncludesCameraFilmSourceAndStatus() throws {
        let timer = makeIdentityTimer(
            cameraSlot: CameraSlotIdentity(id: .camera2),
            filmDisplayName: "CHS 100 II",
            exposureSource: .filmAdjustedShutter,
            status: .running
        )

        let snapshot = makeSnapshot(from: [timer])
        let row = try XCTUnwrap(snapshot.sections.first?.items.first)

        XCTAssertEqual(
            row.voiceOverLabel,
            "Camera 2, CHS 100 II, Adjusted Shutter timer, running"
        )
    }

    @MainActor
    func testTwoCameraSlotsGetDistinctTints() {
        let camera1Timer = makeIdentityTimer(
            id: UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!,
            cameraSlot: CameraSlotIdentity(id: .camera1),
            filmDisplayName: nil,
            exposureSource: .digitalResult
        )
        let camera2Timer = makeIdentityTimer(
            id: UUID(uuidString: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb")!,
            cameraSlot: CameraSlotIdentity(id: .camera2),
            filmDisplayName: nil,
            exposureSource: .digitalResult
        )

        let snapshot = makeSnapshot(from: [camera1Timer, camera2Timer])
        let cuesByMarker = Dictionary(
            uniqueKeysWithValues: snapshot.compactItems.map { ($0.identityCue.markerText, $0.identityCue) }
        )
        let camera1Cue = try? XCTUnwrap(cuesByMarker["C1"])
        let camera2Cue = try? XCTUnwrap(cuesByMarker["C2"])

        XCTAssertNotNil(camera1Cue)
        XCTAssertNotNil(camera2Cue)
        XCTAssertNotEqual(camera1Cue?.tintSlot, camera2Cue?.tintSlot)
    }

    @MainActor
    func testFallbackToOrderMarkerWhenSnapshotAbsent() throws {
        let timer = RunningTimerItem(
            id: UUID(uuidString: "cccccccc-cccc-cccc-cccc-cccccccccccc")!,
            order: 5,
            name: "Legacy",
            basisSummary: "manual",
            duration: 30,
            startDate: Date(timeIntervalSince1970: 1),
            endDate: Date(timeIntervalSince1970: 31),
            pausedRemainingTime: nil,
            pausedAt: nil,
            status: .running,
            referenceDate: Date(timeIntervalSince1970: 1)
        )

        let snapshot = makeSnapshot(from: [timer])
        let item = try XCTUnwrap(snapshot.compactItems.first)

        XCTAssertEqual(item.identityCue.markerText, "T5")
        XCTAssertNil(item.identityCue.fullCameraLabel)
        XCTAssertNil(item.identityCue.filmDescriptor)
        XCTAssertNil(item.identityFilmText)
    }

    private func sampleTimers() -> [RunningTimerItem] {
        let now = Date(timeIntervalSince1970: 1_000)

        return [
            RunningTimerItem(
                id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
                order: 3,
                name: "Completed Latest",
                basisSummary: "Base 1/15s · 8 stops",
                duration: 45,
                startDate: now.addingTimeInterval(-45),
                endDate: now.addingTimeInterval(-5),
                pausedRemainingTime: nil,
                pausedAt: nil,
                status: .completed,
                referenceDate: now
            ),
            RunningTimerItem(
                id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
                order: 1,
                name: "Running Soon",
                basisSummary: "Base 1/30s · 6 stops",
                duration: 120,
                startDate: now,
                endDate: now.addingTimeInterval(25),
                pausedRemainingTime: nil,
                pausedAt: nil,
                status: .running,
                referenceDate: now
            ),
            RunningTimerItem(
                id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
                order: 2,
                name: "Paused Hold",
                basisSummary: "Base 1/60s · 10 stops",
                duration: 180,
                startDate: now.addingTimeInterval(-20),
                endDate: now.addingTimeInterval(160),
                pausedRemainingTime: 55,
                pausedAt: now.addingTimeInterval(-15),
                status: .paused,
                referenceDate: now
            ),
            RunningTimerItem(
                id: UUID(uuidString: "44444444-4444-4444-4444-444444444444")!,
                order: 4,
                name: "Completed Earlier",
                basisSummary: "Base 1/4s · 4 stops",
                duration: 30,
                startDate: now.addingTimeInterval(-60),
                endDate: now.addingTimeInterval(-20),
                pausedRemainingTime: nil,
                pausedAt: nil,
                status: .completed,
                referenceDate: now
            ),
        ]
    }

    /// Builds a single-running timer with a captured identity snapshot.
    /// Used by the identity-surfacing tests so each test stays
    /// readable about which slot/film/source it cares about.
    private func makeIdentityTimer(
        id: UUID = UUID(uuidString: "12345678-1234-1234-1234-123456789abc")!,
        cameraSlot: CameraSlotIdentity?,
        filmDisplayName: String?,
        filmProfileQualifier: String? = nil,
        exposureSource: ExposureTimerSource,
        order: Int = 1,
        name: String = "Test - 60s",
        status: TimerStatus = .running
    ) -> RunningTimerItem {
        let now = Date(timeIntervalSince1970: 1_000)
        return RunningTimerItem(
            id: id,
            order: order,
            name: name,
            basisSummary: "Base 1/30s · 6 stops",
            duration: 60,
            startDate: now,
            endDate: status == .running ? now.addingTimeInterval(45) : nil,
            pausedRemainingTime: nil,
            pausedAt: nil,
            status: status,
            referenceDate: now,
            cameraSlot: cameraSlot,
            filmDisplayName: filmDisplayName,
            filmProfileQualifier: filmProfileQualifier,
            exposureSource: exposureSource
        )
    }

    private func makeSnapshot(from timers: [RunningTimerItem]) -> BottomSheetWorkspaceSnapshot {
        let completedRelativeTimeFormatter = CompletedRelativeTimeFormatter()

        return BottomSheetWorkspaceSnapshot.make(
            from: timers,
            formatRemaining: { seconds in
                let remaining = Int(seconds.rounded(.down))
                if remaining >= 3_600 {
                    let hours = remaining / 3_600
                    let minutes = (remaining % 3_600) / 60
                    let secs = remaining % 60
                    return String(format: "%02d:%02d:%02d", hours, minutes, secs)
                }
                let minutes = remaining / 60
                let secs = remaining % 60
                return String(format: "%02d:%02d", minutes, secs)
            },
            timeContext: { timer in
                switch timer.status {
                case .running:
                    return "Ends soon"
                case .paused:
                    return "Paused recently"
                case .completed:
                    return "Completed recently"
                }
            },
            compactCompletedSupplementaryText: { timer in
                switch timer.status {
                case .completed:
                    guard let completionDate = timer.completedAt else {
                        return "--"
                    }

                    return completedRelativeTimeFormatter.compactString(
                        from: completionDate,
                        relativeTo: timer.referenceDate
                    )
                case .running, .paused:
                    return nil
                }
            }
        )
    }
}
