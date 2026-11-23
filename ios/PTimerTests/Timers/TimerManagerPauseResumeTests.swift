// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import Combine
import SwiftUI
import UIKit
import Vision
import XCTest
import PTimerKit
import PTimerCore
@testable import PTimer

final class TimerManagerPauseResumeTests: XCTestCase {
    @MainActor
    func testRepeatShotTransitionReview() throws {
        let now = Date(timeIntervalSince1970: 1_000)
        let manager = TimerManager(tickInterval: 60, dateProvider: { now })
        let model = TimerWorkspaceModel(
            timerManager: manager, metadataPersistenceStore: NoOpTimerMetadataPersistenceStore(),
            defaultName: { _ in "Exposure" }
        )
        let sourceID = try XCTUnwrap(model.startTimer(
            duration: 90, name: "Tri-X exposure", basisSummary: "Base 1s",
            cameraSlot: CameraSlotIdentity(id: .camera1), filmDisplayName: "Tri-X 400",
            exposureSource: .filmCorrectedExposure
        ))
        model.pauseTimer(id: sourceID)
        let source = try XCTUnwrap(model.timers.first)
        let adapter = BottomSheetWorkspacePresentationAdapter(
            formatRemaining: { BottomSheetWorkspaceSnapshot.compactDurationText($0) },
            formatShutter: { String($0) },
            timeContext: { $0.status == .canceled ? "Canceled just now" : "Started just now" },
            compactCompletedSupplementaryText: { _ in nil }
        )
        let snapshots = BottomSheetWorkspaceSnapshotStore(
            initialTimers: model.timers, timersPublisher: model.$timers.eraseToAnyPublisher(),
            ndNotationModePublisher: Just(NDNotationMode.stops).eraseToAnyPublisher(), adapter: adapter
        )
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previousKeyWindow = scene.windows.first { $0.isKeyWindow }
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
        defer {
            window.isHidden = true
            window.rootViewController = nil
            previousKeyWindow?.makeKeyAndVisible()
        }
        let host = UIHostingController(rootView: RepeatShotReviewHost(snapshots: snapshots)
            .overlay(alignment: .bottom) { TimerCancellationNoticeView(model: model.cancellationNotice) }
            .environment(\.scenePhase, .active))
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(1))
        attachRepeatFrame("Repeat-before", view: host.view)
        var newID: UUID?
        withAnimation(TimerWorkspaceAnimation.movement(reduceMotion: false)) {
            newID = model.startTimer(cloning: source)
        }
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        attachRepeatFrame("Repeat-moving", view: host.view)
        RunLoop.main.run(until: Date().addingTimeInterval(0.6))
        attachRepeatFrame("Repeat-after", view: host.view)
        XCTAssertNotNil(newID)
        XCTAssertEqual(model.timers.first?.id, newID)
        XCTAssertEqual(model.timers.last?.id, sourceID)
        XCTAssertEqual(model.timers.last?.status, .canceled)
        RunLoop.main.run(until: Date().addingTimeInterval(1))
    }

    @MainActor
    private func attachRepeatFrame(_ name: String, view: UIView) {
        let image = UIGraphicsImageRenderer(size: view.bounds.size).image { _ in
            view.drawHierarchy(in: view.bounds, afterScreenUpdates: true)
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    func testTimerCellHeightStaysConstantAcrossStatesCountdownAndAlarm() throws {
        for width in [320.0, 393.0, 430.0] {
            for textSize in [DynamicTypeSize.large, .xxxLarge, .accessibility1] {
                for localeID in ["en", "ko"] {
                    let runningHeight = try timerRowHeight(
                        status: .running, width: width, textSize: textSize, localeID: localeID
                    )
                    for status in [TimerStatus.paused, .completed, .canceled] {
                        for elapsed in [0.0, 60.0, 119.0] {
                            let height = try timerRowHeight(
                                status: status, elapsed: elapsed, width: width,
                                textSize: textSize, localeID: localeID
                            )
                            XCTAssertEqual(height, runningHeight, accuracy: 0.5,
                                           "\(status), \(elapsed)s, \(width)pt, \(textSize), \(localeID)")
                        }
                    }
                    let alarmHeight = try timerRowHeight(
                        status: .completed, width: width, textSize: textSize,
                        localeID: localeID, isAlarmSounding: true
                    )
                    XCTAssertEqual(alarmHeight, runningHeight, accuracy: 0.5,
                                   "Alarm must stay within the existing cell")
                }
            }
        }
    }

    @MainActor
    func testSessionEntryDoesNotIncreaseExistingTimerCellHeight() throws {
        for width in [320.0, 393.0] {
            for textSize in [DynamicTypeSize.large, .accessibility1] {
                for status in [TimerStatus.running, .paused, .completed, .canceled] {
                    let baseline = try timerRowHeight(status: status, width: width, textSize: textSize, localeID: "en")
                    let session = try timerRowHeight(status: status, width: width, textSize: textSize,
                                                    localeID: "en", sessionTitle: "Session 12")
                    XCTAssertEqual(session, baseline, accuracy: 0.5, "Session entry changes \(status) cell at \(width)pt")
                }
            }
        }
    }

    @MainActor
    func testStartSaveFailureShowsExplanationWithoutStartingCountdown() throws {
        struct RejectedMetadata: TimerMetadataPersistenceStoring {
            func loadSnapshot() -> PersistentTimerMetadataCollection? { nil }
            func saveSnapshot(_ snapshot: PersistentTimerMetadataCollection) {}
            func clearSnapshot() {}
            func savePreparingSnapshot(_ snapshot: PersistentTimerMetadataCollection) -> TimerSnapshotSaveResult { .failed }
        }
        let manager = TimerManager(tickInterval: 60)
        let model = TimerWorkspaceModel(timerManager: manager, metadataPersistenceStore: RejectedMetadata(), defaultName: { _ in "Timer" })
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first { $0.isKeyWindow }
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
        let host = UIHostingController(rootView: Text("Start test").modifier(TimerStartFailureModifier(workspace: model)))
        defer {
            window.isHidden = true
            window.rootViewController = nil
            previous?.makeKeyAndVisible()
        }
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        XCTAssertNil(model.startTimer(duration: 60, name: "Failed start", basisSummary: ""))
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        XCTAssertTrue(manager.timers.isEmpty)
        XCTAssertNotNil(model.startError)
        XCTAssertNotNil(host.presentedViewController, "The failed start explanation must be presented")
    }

    @MainActor
    func testShootingSessionWorkspaceRenderForReview() throws {
        var now = Date(timeIntervalSince1970: 1_800_000_000)
        let epoch = now
        let manager = TimerManager(tickInterval: 60, dateProvider: { now })
        let model = TimerWorkspaceModel(timerManager: manager, metadataPersistenceStore: NoOpTimerMetadataPersistenceStore(), defaultName: { _ in "Exposure" })
        _ = model.startTimer(duration: 10800, name: "Camera A", basisSummary: "Base 1s · 10 stops")
        now = epoch + 7200
        _ = model.startTimer(duration: 2, name: "Camera B", basisSummary: "Base 1s · 1 stop")
        now = epoch + 8400
        let secondSessionTimer = try XCTUnwrap(model.startTimer(duration: 4200, name: "Camera B", basisSummary: "Base 1s · 12 stops"))
        now = epoch + 12601
        manager.reconcile(now: now)
        _ = model.startTimer(duration: 300, name: "Camera A", basisSummary: "Base 1s · 8 stops")
        let snapshot = BottomSheetWorkspaceSnapshot.make(
            from: model.timers, formatRemaining: { BottomSheetWorkspaceSnapshot.compactDurationText($0) },
            formatShutter: { String($0) }, ndNotationMode: .stops,
            timeContext: { timer in timer.terminalAt?.formatted(date: .abbreviated, time: .shortened) },
            compactCompletedSupplementaryText: { _ in nil }
        )
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previousKeyWindow = scene.windows.first { $0.isKeyWindow }
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
        defer {
            window.isHidden = true
            window.rootViewController = nil
            previousKeyWindow?.makeKeyAndVisible()
        }
        let workspace = FullScreenTimersWindow(
            snapshot: snapshot, openFocus: .none, onPauseTimer: model.pauseTimer,
            onResumeTimer: model.resumeTimer, onCancelTimer: model.cancelTimer,
            onRemoveTimer: model.removeTimer, onCloneTimer: { _ in },
            onClearCompletedTimers: model.clearCompletedTimers, onClose: {}, sessionWorkspace: model
        )
        let host = UIHostingController(rootView: workspace)
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        attachRepeatFrame("Session-History", view: host.view)
        let membership = try XCTUnwrap(model.sessions.membership(for: secondSessionTimer))
        let detail = ShootingSessionDetailView(title: model.sessions.title(for: membership.sessionID),
                                             sections: model.sessions.sections(for: membership.sessionID, from: snapshot))
        let detailHost = UIHostingController(rootView: NavigationStack { detail })
        window.rootViewController = detailHost
        detailHost.view.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        attachRepeatFrame("Session-Detail", view: detailHost.view)
        XCTAssertEqual(model.sessions.sections(for: membership.sessionID, from: snapshot).flatMap(\.items).count, 2)
    }

    @MainActor
    private func timerRowHeight(
        status: TimerStatus, elapsed: TimeInterval = 0, width: CGFloat,
        textSize: DynamicTypeSize, localeID: String, isAlarmSounding: Bool = false,
        sessionTitle: String? = nil
    ) throws -> CGFloat {
        let start = Date(timeIntervalSince1970: 1_000)
        let timer = RunningTimerItem(
            id: UUID(), order: 1, name: "Tri-X exposure", basisSummary: "Base 1s",
            duration: 90, startDate: start, endDate: start.addingTimeInterval(90),
            pausedRemainingTime: status == .paused ? 60 : nil,
            pausedAt: status == .paused ? start : nil, status: status,
            referenceDate: start.addingTimeInterval(elapsed),
            cameraSlot: CameraSlotIdentity(id: .camera1), filmDisplayName: "Tri-X 400",
            exposureSource: .filmCorrectedExposure,
            canceledRemainingTime: status == .canceled ? 60 : nil,
            cancellationReason: status == .canceled ? .pauseExpired : nil
        )
        let snapshot = BottomSheetWorkspaceSnapshot.make(
            from: [timer], formatRemaining: { BottomSheetWorkspaceSnapshot.compactDurationText($0) },
            formatShutter: { String($0) }, ndNotationMode: .stops,
            timeContext: { _ in "\(status.rawValue) 2026-11-22 11:03:00 · just now" },
            compactCompletedSupplementaryText: { _ in nil }
        )
        let item = try XCTUnwrap(snapshot.sections.first?.items.first)
        let row = LargeWorkspaceTimerRowView(
            item: item, isFocused: false, onAction: { _ in }, isAlarmSounding: isAlarmSounding,
            sessionTitle: sessionTitle, onOpenSession: sessionTitle == nil ? nil : {}
        )
        let configuredRow = row
            .environment(\.dynamicTypeSize, textSize)
            .environment(\.locale, Locale(identifier: localeID))
        let host = UIHostingController(rootView: configuredRow)
        let height = host.sizeThatFits(in: CGSize(width: width, height: 2_000)).height
        if status == .canceled, width == 320, textSize == .accessibility1,
           localeID == "en", elapsed == 0, !isAlarmSounding {
            let renderer = ImageRenderer(content: configuredRow.frame(width: width))
            renderer.scale = 3
            let image = try XCTUnwrap(renderer.cgImage)
            let request = VNRecognizeTextRequest()
            try VNImageRequestHandler(cgImage: image).perform([request])
            let text = request.results?.compactMap { $0.topCandidates(1).first?.string }
                .joined(separator: " ") ?? ""
            XCTAssertTrue(text.contains("01:00 left"), "Rendered cancellation duration missing: \(text)")
        }
        return height
    }

    @MainActor
    func testPausedAndCanceledWorkspaceRenderForReview() throws {
        var now = Date(timeIntervalSince1970: 1_000)
        let manager = TimerManager(tickInterval: 60, dateProvider: { now })
        let model = TimerWorkspaceModel(
            timerManager: manager,
            metadataPersistenceStore: NoOpTimerMetadataPersistenceStore(),
            defaultName: { _ in "Exposure" }
        )
        let id = try XCTUnwrap(model.startTimer(
            duration: 90, name: "Tri-X exposure", basisSummary: "Base 1s",
            cameraSlot: CameraSlotIdentity(id: .camera1),
            filmDisplayName: "Tri-X 400", exposureSource: .filmCorrectedExposure
        ))
        now += 30
        model.pauseTimer(id: id)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previousKeyWindow = scene.windows.first { $0.isKeyWindow }
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 393, height: 852)
        defer {
            window.isHidden = true
            window.rootViewController = nil
            previousKeyWindow?.makeKeyAndVisible()
        }
        for isExpired in [false, true] {
            if isExpired {
                now += 120
                manager.reconcile()
            }
            let snapshot = BottomSheetWorkspaceSnapshot.make(
                from: model.timers,
                formatRemaining: { BottomSheetWorkspaceSnapshot.compactDurationText($0) },
                formatShutter: { String($0) }, ndNotationMode: .stops,
                timeContext: { _ in isExpired ? "Canceled just now" : "Paused just now" },
                compactCompletedSupplementaryText: { _ in nil }
            )
            let screen = FullScreenTimersWindow(
                snapshot: snapshot, openFocus: .activeSection(highlightedTimerID: nil),
                onPauseTimer: { _ in }, onResumeTimer: { _ in }, onCancelTimer: { _ in },
                onRemoveTimer: { _ in }, onCloneTimer: { _ in },
                onClearCompletedTimers: {}, onClose: {}
            )
            let host = UIHostingController(rootView: screen.overlay(alignment: .bottom) {
                TimerCancellationNoticeView(model: model.cancellationNotice)
            }.environment(\.scenePhase, .active))
            window.rootViewController = host
            window.makeKeyAndVisible()
            host.view.layoutIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.3))
            if isExpired {
                XCTAssertNotNil(model.cancellationNotice.text)
                XCTAssertTrue(model.cancellationNotice.pendingTimerIDs.isEmpty)
            }
            let image = UIGraphicsImageRenderer(size: host.view.bounds.size).image { _ in
                host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
            }
            let attachment = XCTAttachment(image: image)
            attachment.name = isExpired ? "Pause-expired-History" : "Pause-resume-countdown"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    @MainActor
    func testPausedOnlyTimerExpiresFromRunLoopWithoutManualTick() async throws {
        var now = Date(timeIntervalSince1970: 100)
        let alerts = CompletionAlertSpy()
        let manager = TimerManager(
            tickInterval: 0.01, dateProvider: { now }, completionAlertService: alerts
        )
        let id = try XCTUnwrap(manager.start(duration: 90))
        now += 30
        manager.pause(id: id)
        let expired = expectation(description: "Paused-only timer expires on its own")
        let subscription = manager.$timers
            .first { $0.first?.status == .canceled }
            .sink { _ in expired.fulfill() }
        now += 120
        await fulfillment(of: [expired], timeout: 2)
        subscription.cancel()
        XCTAssertEqual(manager.timers.first?.remainingAtCancel, 60)
        XCTAssertEqual(manager.timers.first?.endDate, Date(timeIntervalSince1970: 250))
        XCTAssertTrue(alerts.events.isEmpty)
    }

    @MainActor
    func testPauseFreezesRemainingTimeInResumablePausedState() throws {
        let startDate = Date(timeIntervalSince1970: 100)
        var currentDate = startDate
        let manager = TimerManager(
            tickInterval: 60,
            dateProvider: { currentDate }
        )

        let firstID = try XCTUnwrap(manager.start(duration: 5))
        let secondID = try XCTUnwrap(manager.start(duration: 9))

        currentDate = startDate.addingTimeInterval(2)
        manager.pause(id: firstID)

        let firstTimer = tryUnwrapTimer(withID: firstID, from: manager.timers)
        let secondTimer = tryUnwrapTimer(withID: secondID, from: manager.timers)

        XCTAssertEqual(firstTimer.status(at: currentDate), TimerStatus.paused)
        XCTAssertEqual(firstTimer.remainingTime(at: currentDate), 3, accuracy: 0.0001)

        let laterDate = startDate.addingTimeInterval(4)
        XCTAssertEqual(firstTimer.status(at: laterDate), TimerStatus.paused)
        XCTAssertEqual(firstTimer.remainingTime(at: laterDate), 3, accuracy: 0.0001)
        let pausedRemainingTime = try XCTUnwrap(firstTimer.pausedRemainingTime)
        XCTAssertEqual(pausedRemainingTime, 3, accuracy: 0.0001)
        XCTAssertEqual(secondTimer.status(at: currentDate), TimerStatus.running)
        XCTAssertEqual(secondTimer.remainingTime(at: currentDate), 7, accuracy: 0.0001)
    }

    @MainActor
    func testTickDoesNotAdvanceFrozenPausedTimerRemainingTime() throws {
        let startDate = Date(timeIntervalSince1970: 100)
        var currentDate = startDate
        let manager = TimerManager(
            tickInterval: 60,
            dateProvider: { currentDate }
        )

        let id = try XCTUnwrap(manager.start(duration: 12))

        currentDate = startDate.addingTimeInterval(5)
        manager.pause(id: id)

        let pausedTimer = tryUnwrapTimer(withID: id, from: manager.timers)
        XCTAssertEqual(pausedTimer.remainingTime(at: currentDate), 7, accuracy: 0.0001)

        let muchLaterDate = startDate.addingTimeInterval(30)
        manager.tick(now: muchLaterDate)

        let timerAfterTick = tryUnwrapTimer(withID: id, from: manager.timers)
        XCTAssertEqual(timerAfterTick.status(at: muchLaterDate), TimerStatus.paused)
        XCTAssertEqual(timerAfterTick.remainingTime(at: muchLaterDate), 7, accuracy: 0.0001)
    }

    @MainActor
    func testResumeContinuesFromFrozenPausedRemainingTime() throws {
        let startDate = Date(timeIntervalSince1970: 100)
        var currentDate = startDate
        let manager = TimerManager(
            tickInterval: 60,
            dateProvider: { currentDate }
        )

        let id = try XCTUnwrap(manager.start(duration: 10))

        currentDate = startDate.addingTimeInterval(4)
        manager.pause(id: id)

        let pausedTimer = tryUnwrapTimer(withID: id, from: manager.timers)
        XCTAssertEqual(pausedTimer.status(at: currentDate), .paused)
        XCTAssertEqual(pausedTimer.remainingTime(at: currentDate), 6, accuracy: 0.0001)

        currentDate = startDate.addingTimeInterval(7)
        manager.resume(id: id)

        let resumedTimer = tryUnwrapTimer(withID: id, from: manager.timers)
        XCTAssertEqual(resumedTimer.status(at: currentDate), .running)
        XCTAssertEqual(resumedTimer.remainingTime(at: currentDate), 6, accuracy: 0.0001)

        let laterDate = currentDate.addingTimeInterval(2)
        XCTAssertEqual(resumedTimer.remainingTime(at: laterDate), 4, accuracy: 0.0001)
    }

    @MainActor
    func testResumeRecalculatesEndDateFromFrozenPausedRemainingTime() throws {
        let startDate = Date(timeIntervalSince1970: 100)
        var currentDate = startDate
        let manager = TimerManager(
            tickInterval: 60,
            dateProvider: { currentDate }
        )

        let id = try XCTUnwrap(manager.start(duration: 12))

        currentDate = startDate.addingTimeInterval(5)
        manager.pause(id: id)

        let pausedTimer = tryUnwrapTimer(withID: id, from: manager.timers)
        let pausedRemaining = try XCTUnwrap(pausedTimer.pausedRemainingTime)
        XCTAssertEqual(pausedRemaining, 7, accuracy: 0.0001)

        currentDate = startDate.addingTimeInterval(9)
        manager.resume(id: id)

        let resumedTimer = tryUnwrapTimer(withID: id, from: manager.timers)
        XCTAssertEqual(resumedTimer.status(at: currentDate), .running)
        XCTAssertEqual(resumedTimer.remainingTime(at: currentDate), 7, accuracy: 0.0001)
        XCTAssertEqual(
            resumedTimer.endDate,
            currentDate.addingTimeInterval(pausedRemaining)
        )
    }

    @MainActor
    func testPausedTimerPreservesFrozenStatePauseMetadata() throws {
        let startDate = Date(timeIntervalSince1970: 100)
        var currentDate = startDate
        let manager = TimerManager(
            tickInterval: 60,
            dateProvider: { currentDate }
        )

        let id = try XCTUnwrap(manager.start(duration: 10))

        currentDate = startDate.addingTimeInterval(4)
        manager.pause(id: id)

        let timer = tryUnwrapTimer(withID: id, from: manager.timers)
        XCTAssertEqual(timer.status(at: currentDate), .paused)
        XCTAssertEqual(timer.startDate, startDate)
        XCTAssertEqual(timer.pausedAt, currentDate)
        XCTAssertEqual(try XCTUnwrap(timer.pausedRemainingTime), 6, accuracy: 0.0001)
    }

    @MainActor
    func testCompletedTimerPreservesOriginalDurationMetadata() throws {
        let startDate = Date(timeIntervalSince1970: 100)
        let manager = TimerManager(
            tickInterval: 60,
            dateProvider: { startDate }
        )

        let id = try XCTUnwrap(manager.start(duration: 3))
        let completionDate = startDate.addingTimeInterval(5)
        manager.tick(now: completionDate)

        let timer = tryUnwrapTimer(withID: id, from: manager.timers)
        XCTAssertEqual(timer.status(at: completionDate), .completed)
        XCTAssertEqual(timer.remainingTime(at: completionDate), 0, accuracy: 0.0001)
        XCTAssertEqual(timer.duration, 3, accuracy: 0.0001)
        XCTAssertEqual(timer.startDate, startDate)
        XCTAssertEqual(timer.endDate, startDate.addingTimeInterval(3))
    }

    @MainActor
    func testRemoveCompletedTimersKeepsPausedTimersResumable() throws {
        let startDate = Date(timeIntervalSince1970: 100)
        var currentDate = startDate
        let manager = TimerManager(
            tickInterval: 60,
            dateProvider: { currentDate }
        )

        let pausedID = try XCTUnwrap(manager.start(duration: 10))
        let completedID = try XCTUnwrap(manager.start(duration: 1))

        currentDate = startDate.addingTimeInterval(4)
        manager.pause(id: pausedID)
        manager.tick(now: currentDate)
        manager.removeCompletedTimers()

        XCTAssertNil(manager.timers.first { $0.id == completedID })

        let pausedTimer = tryUnwrapTimer(withID: pausedID, from: manager.timers)
        XCTAssertEqual(pausedTimer.status(at: currentDate), .paused)
        XCTAssertEqual(pausedTimer.remainingTime(at: currentDate), 6, accuracy: 0.0001)

        currentDate = startDate.addingTimeInterval(8)
        manager.resume(id: pausedID)

        let resumedTimer = tryUnwrapTimer(withID: pausedID, from: manager.timers)
        XCTAssertEqual(resumedTimer.status(at: currentDate), .running)
        XCTAssertEqual(resumedTimer.remainingTime(at: currentDate), 6, accuracy: 0.0001)
    }

    @MainActor
    func testResumeMultipleTimesMaintainsCorrectRemainingTime() throws {
        let startDate = Date(timeIntervalSince1970: 100)
        var currentDate = startDate
        let manager = TimerManager(
            tickInterval: 60,
            dateProvider: { currentDate }
        )

        let id = try XCTUnwrap(manager.start(duration: 20))

        currentDate = startDate.addingTimeInterval(5)
        manager.pause(id: id)
        XCTAssertEqual(tryUnwrapTimer(withID: id, from: manager.timers).remainingTime(at: currentDate), 15, accuracy: 0.0001)

        currentDate = startDate.addingTimeInterval(9)
        manager.resume(id: id)
        XCTAssertEqual(tryUnwrapTimer(withID: id, from: manager.timers).remainingTime(at: currentDate), 15, accuracy: 0.0001)

        currentDate = startDate.addingTimeInterval(12)
        manager.pause(id: id)
        XCTAssertEqual(tryUnwrapTimer(withID: id, from: manager.timers).remainingTime(at: currentDate), 12, accuracy: 0.0001)

        currentDate = startDate.addingTimeInterval(30)
        manager.resume(id: id)
        let resumedTimer = tryUnwrapTimer(withID: id, from: manager.timers)
        XCTAssertEqual(resumedTimer.status(at: currentDate), .running)
        XCTAssertEqual(resumedTimer.remainingTime(at: currentDate), 12, accuracy: 0.0001)
        XCTAssertEqual(resumedTimer.endDate, currentDate.addingTimeInterval(12))
    }

    @MainActor
    func testResumeAfterExpiredPauseKeepsCanceledRecord() throws {
        let startDate = Date(timeIntervalSince1970: 100)
        var currentDate = startDate
        let manager = TimerManager(
            tickInterval: 60,
            dateProvider: { currentDate }
        )

        let id = try XCTUnwrap(manager.start(duration: 10))

        currentDate = startDate.addingTimeInterval(4)
        manager.pause(id: id)

        currentDate = startDate.addingTimeInterval(10_000)
        manager.resume(id: id)

        let timer = tryUnwrapTimer(withID: id, from: manager.timers)
        XCTAssertEqual(timer.status(at: currentDate), .canceled)
        XCTAssertEqual(timer.remainingAtCancel, 6)
        XCTAssertEqual(timer.endDate, startDate.addingTimeInterval(124))
    }

    @MainActor
    func testPausedTimerEndDateIsDerivedFromFreezeMetadata() throws {
        // PausedTimer.endDate is now computed (`pausedAt +
        // pausedRemainingTime`) rather than stored. Verify the derived
        // value equals the original endDate at the pause boundary, and
        // — unlike the legacy stored field — also equals
        // `pausedAt + pausedRemainingTime` for synthetic paused state
        // constructed via the back-compat init.
        let startDate = Date(timeIntervalSince1970: 100)
        var currentDate = startDate
        let manager = TimerManager(
            tickInterval: 60,
            dateProvider: { currentDate }
        )

        let id = try XCTUnwrap(manager.start(duration: 10))
        currentDate = startDate.addingTimeInterval(3)
        manager.pause(id: id)

        let paused = tryUnwrapTimer(withID: id, from: manager.timers)
        let pausedAt = try XCTUnwrap(paused.pausedAt)
        let remaining = try XCTUnwrap(paused.pausedRemainingTime)
        XCTAssertEqual(paused.endDate, pausedAt.addingTimeInterval(remaining))
        XCTAssertEqual(paused.endDate, startDate.addingTimeInterval(10))
    }

    @MainActor
    func testResumeAfterLogicalCompletionKeepsTimerRunningFromRemainingTime() throws {
        let startDate = Date(timeIntervalSince1970: 100)
        var currentDate = startDate
        let manager = TimerManager(
            tickInterval: 60,
            dateProvider: { currentDate }
        )

        let id = try XCTUnwrap(manager.start(duration: 5))

        currentDate = startDate.addingTimeInterval(4)
        manager.pause(id: id)

        currentDate = startDate.addingTimeInterval(10)
        manager.resume(id: id)

        XCTAssertEqual(manager.timers.count, 1)

        let timer = tryUnwrapTimer(withID: id, from: manager.timers)
        XCTAssertEqual(timer.status(at: currentDate), .running)
        XCTAssertEqual(timer.remainingTime(at: currentDate), 1, accuracy: 0.0001)
        XCTAssertNil(timer.pausedAt)
        XCTAssertNil(timer.pausedRemainingTime)
        XCTAssertEqual(timer.endDate, currentDate.addingTimeInterval(1))
    }

    @MainActor
    func testCompletionDateMatchesRegardlessOfCompletionPath() throws {
        let startDate = Date(timeIntervalSince1970: 100)

        let tickManager = TimerManager(
            tickInterval: 60,
            dateProvider: { startDate }
        )
        let tickID = try XCTUnwrap(tickManager.start(duration: 10))
        tickManager.tick(now: startDate.addingTimeInterval(12))
        let tickCompleted = tryUnwrapTimer(withID: tickID, from: tickManager.timers)

        var currentDate = startDate
        let resumeManager = TimerManager(
            tickInterval: 60,
            dateProvider: { currentDate }
        )
        let resumeID = try XCTUnwrap(resumeManager.start(duration: 10))
        currentDate = startDate.addingTimeInterval(4)
        resumeManager.pause(id: resumeID)
        currentDate = startDate.addingTimeInterval(11)
        resumeManager.resume(id: resumeID)
        resumeManager.tick(now: currentDate.addingTimeInterval(6))
        let resumeCompleted = tryUnwrapTimer(withID: resumeID, from: resumeManager.timers)

        XCTAssertEqual(tickCompleted.status(at: startDate.addingTimeInterval(12)), .completed)
        XCTAssertEqual(resumeCompleted.status(at: currentDate.addingTimeInterval(6)), .completed)
        XCTAssertEqual(tickCompleted.endDate, startDate.addingTimeInterval(10))
        XCTAssertEqual(resumeCompleted.endDate, currentDate.addingTimeInterval(6))
    }

    @MainActor
    func testLongPausedResumeStaysRunningWithoutAlertAndAlertsOnlyAfterRunningCompletion() throws {
        let startDate = Date(timeIntervalSince1970: 100)
        var currentDate = startDate
        let alertSpy = CompletionAlertSpy()
        let manager = TimerManager(
            tickInterval: 60,
            dateProvider: { currentDate },
            completionAlertService: alertSpy
        )

        let id = try XCTUnwrap(manager.start(duration: 5))

        currentDate = startDate.addingTimeInterval(4)
        manager.pause(id: id)

        currentDate = startDate.addingTimeInterval(100)
        manager.resume(id: id)

        let resumed = tryUnwrapTimer(withID: id, from: manager.timers)
        XCTAssertEqual(resumed.status(at: currentDate), .running)
        XCTAssertEqual(resumed.remainingTime(at: currentDate), 1, accuracy: 0.0001)
        XCTAssertTrue(alertSpy.events.isEmpty)

        currentDate = currentDate.addingTimeInterval(1)
        manager.tick(now: currentDate)

        let completed = tryUnwrapTimer(withID: id, from: manager.timers)
        XCTAssertEqual(completed.status(at: currentDate), .completed)
        XCTAssertEqual(alertSpy.events, [
            TimerCompletionEvent(
                timerID: id,
                completionDate: currentDate
            ),
        ])
    }
}

private struct RepeatShotReviewHost: View {
    @ObservedObject var snapshots: BottomSheetWorkspaceSnapshotStore

    var body: some View {
        FullScreenTimersWindow(
            snapshot: snapshots.snapshot, openFocus: .activeSection(highlightedTimerID: nil),
            onPauseTimer: { _ in }, onResumeTimer: { _ in }, onCancelTimer: { _ in },
            onRemoveTimer: { _ in }, onCloneTimer: { _ in },
            onClearCompletedTimers: {}, onClose: {}
        )
    }
}
