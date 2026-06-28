// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import XCTest
import PTimerCore
@testable import PTimerKit

/// PTIMER-36: tests for the Clone surface (clone from any row)
/// extracted from BottomSheetWorkspaceSnapshotFactoryTests so the
/// factory test class stays within strict file/type-length budgets.
final class BottomSheetStartAgainTests: XCTestCase {
    @MainActor
    func testEachStatusSurfacesItsActionSetAndCanceledIsNotLabeledDone() throws {
        let snapshot = makeSnapshot(from: sampleTimers())
        let activeSection = try XCTUnwrap(
            snapshot.sections.first(where: { $0.title == "Active" })
        )
        let completedSection = try XCTUnwrap(
            snapshot.sections.first(where: { $0.title == "History" })
        )

        for activeItem in activeSection.items {
            switch activeItem.status {
            case .running:
                XCTAssertEqual(
                    activeItem.actions,
                    [.pause, .clone, .cancel],
                    "Running rows offer Pause, Clone, Cancel"
                )
            case .paused:
                XCTAssertEqual(
                    activeItem.actions,
                    [.resume, .clone, .cancel, .remove],
                    "Paused rows offer Resume, Clone, Cancel, Remove"
                )
            case .completed, .canceled:
                XCTFail("Terminal records do not belong in the Active section")
            }
        }

        // Both completed and canceled records land in the history
        // section and share the Clone + Remove action set.
        XCTAssertTrue(
            completedSection.items.contains { $0.status == .canceled },
            "Canceled records belong in the history section, not Active"
        )
        for terminalItem in completedSection.items {
            XCTAssertEqual(
                terminalItem.actions,
                [.clone, .remove],
                "Terminal rows present Clone before Remove"
            )
            switch terminalItem.status {
            case .completed:
                XCTAssertEqual(terminalItem.statusLabel, "Done")
            case .canceled:
                XCTAssertEqual(
                    terminalItem.statusLabel,
                    "Canceled",
                    "Canceled records must read Canceled, never Done"
                )
            case .running, .paused:
                XCTFail("Active timers do not belong in the history section")
            }
        }
    }

    @MainActor
    func testHistorySectionShowsCanceledRemainingAndStableSequenceNumber() throws {
        let now = Date(timeIntervalSince1970: 1_000)
        let canceled = RunningTimerItem(
            id: UUID(uuidString: "66666666-6666-6666-6666-666666666666")!,
            order: 7,
            name: "Tri-X 400 - 90s",
            basisSummary: "Base 1s · 6 stops",
            duration: 90,
            startDate: now.addingTimeInterval(-40),
            endDate: now.addingTimeInterval(-10),
            pausedRemainingTime: nil,
            pausedAt: nil,
            status: .canceled,
            referenceDate: now,
            canceledRemainingTime: 51
        )

        let snapshot = makeSnapshot(from: [canceled])
        let history = try XCTUnwrap(snapshot.sections.first { $0.title == "History" })
        let item = try XCTUnwrap(history.items.first { $0.id == canceled.id })

        // Remaining-at-cancel is combined into the large status text,
        // no new line.
        XCTAssertEqual(item.remainingText, "Canceled · 51s left")
        XCTAssertEqual(item.statusLabel, "Canceled")
        // Stable numeric id = the timer's creation order, bare number.
        XCTAssertEqual(item.sequenceNumberText, "7")
    }

    @MainActor
    func testSequenceNumberTracksTimerOrderNotVisibleListIndex() throws {
        // Two timers whose visible order (LIFO / completion-desc) differs
        // from their creation order; the sequence number must follow the
        // stable creation order, not the rendered position.
        let now = Date(timeIntervalSince1970: 1_000)
        let older = RunningTimerItem(
            id: UUID(uuidString: "AAAAAAAA-0000-0000-0000-000000000001")!,
            order: 2, name: "A", basisSummary: "m", duration: 60,
            startDate: now, endDate: now.addingTimeInterval(60),
            pausedRemainingTime: nil, pausedAt: nil, status: .running, referenceDate: now
        )
        let newer = RunningTimerItem(
            id: UUID(uuidString: "AAAAAAAA-0000-0000-0000-000000000002")!,
            order: 5, name: "B", basisSummary: "m", duration: 60,
            startDate: now, endDate: now.addingTimeInterval(60),
            pausedRemainingTime: nil, pausedAt: nil, status: .running, referenceDate: now
        )

        let snapshot = makeSnapshot(from: [older, newer])
        let active = try XCTUnwrap(snapshot.sections.first { $0.title == "Active" })

        XCTAssertEqual(active.items.first { $0.id == older.id }?.sequenceNumberText, "2")
        XCTAssertEqual(active.items.first { $0.id == newer.id }?.sequenceNumberText, "5")
    }

    @MainActor
    func testCloningFromCompletedAddsCloneAndLeavesSourceUnchanged() throws {
        let harness = makeRuntimeHarness(now: 100)

        harness.viewModel.startTimer(from: 8)
        let sourceID = try XCTUnwrap(harness.viewModel.timers.first?.id)

        // Drive the source to completed.
        harness.currentDate = Date(timeIntervalSince1970: 200)
        harness.timerManager.tick(now: harness.currentDate)
        let completedSource = try XCTUnwrap(
            harness.viewModel.timers.first { $0.id == sourceID }
        )
        XCTAssertEqual(completedSource.status, .completed)

        // Advance the clock again so the cloned timer's start date is
        // distinct from the source's start date (the clone's running
        // payload must not share start/completion timestamps).
        harness.currentDate = Date(timeIntervalSince1970: 250)
        harness.viewModel.cloneTimer(from: completedSource)

        XCTAssertEqual(harness.viewModel.timers.count, 2)

        let sourceAfter = try XCTUnwrap(
            harness.viewModel.timers.first { $0.id == sourceID }
        )
        let cloned = try XCTUnwrap(
            harness.viewModel.timers.first { $0.id != sourceID }
        )

        XCTAssertEqual(sourceAfter.status, .completed)
        XCTAssertEqual(sourceAfter.duration, completedSource.duration, accuracy: 0.0001)
        XCTAssertEqual(sourceAfter.completedAt, completedSource.completedAt)

        XCTAssertEqual(cloned.status, .running)
        XCTAssertEqual(cloned.duration, completedSource.duration, accuracy: 0.0001)
        XCTAssertNotEqual(cloned.id, sourceID)
        XCTAssertEqual(cloned.startDate, harness.currentDate)
    }

    @MainActor
    func testCloningFromRunningRowPreservesSourceAndStartsOneFreshTimer() throws {
        let harness = makeRuntimeHarness(now: 100)

        harness.viewModel.startTimer(from: 60)
        let runningSource = try XCTUnwrap(harness.viewModel.timers.first)
        XCTAssertEqual(runningSource.status, .running)

        // Advance the clock so the fresh timer's start date is distinct
        // from the source's.
        harness.currentDate = Date(timeIntervalSince1970: 130)
        harness.viewModel.cloneTimer(from: runningSource)

        // Clone never cancels: the source keeps running and the clone joins
        // it from full duration — two running timers.
        XCTAssertEqual(harness.viewModel.timers.count, 2)
        XCTAssertEqual(
            harness.viewModel.timers.filter { $0.status == .running }.count,
            2
        )
        let sourceAfter = try XCTUnwrap(
            harness.viewModel.timers.first { $0.id == runningSource.id }
        )
        XCTAssertEqual(sourceAfter.status, .running)

        let fresh = try XCTUnwrap(
            harness.viewModel.timers.first { $0.id != runningSource.id }
        )
        XCTAssertEqual(fresh.status, .running)
        XCTAssertEqual(fresh.duration, runningSource.duration, accuracy: 0.0001)
        XCTAssertEqual(fresh.startDate, harness.currentDate)
    }

    @MainActor
    func testCloneReturnsFreshTimerIDForFocus() throws {
        let harness = makeRuntimeHarness(now: 100)

        harness.viewModel.startTimer(from: 60)
        let runningSource = try XCTUnwrap(harness.viewModel.timers.first)

        harness.currentDate = Date(timeIntervalSince1970: 130)
        let newID = harness.viewModel.cloneTimer(from: runningSource)

        // The returned id is the fresh clone's id — the value the shell
        // uses to move focus onto it — not the source.
        let fresh = try XCTUnwrap(
            harness.viewModel.timers.first { $0.id != runningSource.id }
        )
        XCTAssertEqual(newID, fresh.id)
        XCTAssertNotEqual(newID, runningSource.id)
    }

    @MainActor
    func testCloneFromTerminalReturnsClonedTimerIDForFocus() throws {
        let harness = makeRuntimeHarness(now: 100)

        harness.viewModel.startTimer(from: 8)
        let sourceID = try XCTUnwrap(harness.viewModel.timers.first?.id)
        harness.currentDate = Date(timeIntervalSince1970: 200)
        harness.timerManager.tick(now: harness.currentDate)
        let completedSource = try XCTUnwrap(
            harness.viewModel.timers.first { $0.id == sourceID }
        )

        harness.currentDate = Date(timeIntervalSince1970: 250)
        let newID = harness.viewModel.cloneTimer(from: completedSource)

        let cloned = try XCTUnwrap(
            harness.viewModel.timers.first { $0.id != sourceID }
        )
        XCTAssertEqual(newID, cloned.id)
        XCTAssertNotEqual(newID, sourceID)
    }

    @MainActor
    func testCloningFromPausedRowPreservesSourceAndStartsFromBeginning() throws {
        let harness = makeRuntimeHarness(now: 100)

        harness.viewModel.startTimer(from: 60)
        let runningSource = try XCTUnwrap(harness.viewModel.timers.first)

        // Pause partway through, then Clone.
        harness.currentDate = Date(timeIntervalSince1970: 130)
        harness.viewModel.pauseTimer(id: runningSource.id)
        let pausedSource = try XCTUnwrap(harness.viewModel.timers.first)
        XCTAssertEqual(pausedSource.status, .paused)

        harness.currentDate = Date(timeIntervalSince1970: 150)
        harness.viewModel.cloneTimer(from: pausedSource)

        XCTAssertEqual(harness.viewModel.timers.count, 2)
        // Source stays paused; clone never cancels.
        XCTAssertEqual(
            harness.viewModel.timers.first { $0.id == pausedSource.id }?.status,
            .paused
        )

        let fresh = try XCTUnwrap(
            harness.viewModel.timers.first { $0.id != pausedSource.id }
        )
        XCTAssertEqual(fresh.status, .running)
        XCTAssertNil(fresh.pausedAt)
        XCTAssertEqual(fresh.duration, pausedSource.duration, accuracy: 0.0001)
        XCTAssertEqual(fresh.remainingTime, pausedSource.duration, accuracy: 0.0001)
        XCTAssertEqual(fresh.startDate, harness.currentDate)
    }

    @MainActor
    func testCancelOnPausedProducesCanceledRecordThatCanClone() throws {
        let harness = makeRuntimeHarness(now: 100)

        harness.viewModel.startTimer(from: 60)
        let runningSource = try XCTUnwrap(harness.viewModel.timers.first)

        harness.currentDate = Date(timeIntervalSince1970: 130)
        harness.viewModel.pauseTimer(id: runningSource.id)
        harness.viewModel.cancelTimer(id: runningSource.id)

        let canceled = try XCTUnwrap(harness.viewModel.timers.first)
        XCTAssertEqual(canceled.status, .canceled)
        XCTAssertEqual(harness.viewModel.timers.count, 1)

        // Clone on the canceled record starts a fresh running timer and
        // leaves the canceled record intact.
        harness.currentDate = Date(timeIntervalSince1970: 160)
        harness.viewModel.cloneTimer(from: canceled)

        XCTAssertEqual(harness.viewModel.timers.count, 2)
        XCTAssertEqual(
            harness.viewModel.timers.first { $0.id == canceled.id }?.status,
            .canceled
        )
        let fresh = try XCTUnwrap(
            harness.viewModel.timers.first { $0.id != canceled.id }
        )
        XCTAssertEqual(fresh.status, .running)
        XCTAssertEqual(fresh.startDate, harness.currentDate)
    }

    @MainActor
    func testSnapshotStoreReflectsPreviewStateTimerStartWithoutChangingWorkspaceFlow() throws {
        let harness = makeRuntimeHarness(now: 100)

        harness.viewModel.baseShutter = 1.0 / 30.0
        harness.viewModel.ndStop = 6
        harness.viewModel.updateLiveBaseShutter(1.0 / 15.0)
        harness.viewModel.startTimer()

        let timer = try XCTUnwrap(harness.viewModel.timers.first)
        let compactItem = try XCTUnwrap(harness.snapshotStore.snapshot.compactItems.first)
        let largeItem = try XCTUnwrap(harness.snapshotStore.snapshot.sections.first?.items.first)

        XCTAssertEqual(timer.name, "Timer - 4s")
        XCTAssertEqual(timer.basisSummary, "Base 1/15s · 6 stops")
        XCTAssertEqual(timer.duration, 4, accuracy: 0.0001)
        XCTAssertEqual(compactItem.id, timer.id)
        XCTAssertEqual(largeItem.id, timer.id)
        XCTAssertEqual(largeItem.contextText, timer.basisSummary)
        XCTAssertEqual(largeItem.remainingText, harness.viewModel.formatTimerClock(4) + " left")
        XCTAssertFalse(harness.stateStore.isExpanded)
        XCTAssertEqual(harness.stateStore.detent, .compact)
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
            RunningTimerItem(
                id: UUID(uuidString: "55555555-5555-5555-5555-555555555555")!,
                order: 5,
                name: "Canceled Shot",
                basisSummary: "Base 1/8s · 5 stops",
                duration: 200,
                startDate: now.addingTimeInterval(-40),
                endDate: now.addingTimeInterval(-10),
                pausedRemainingTime: nil,
                pausedAt: nil,
                status: .canceled,
                referenceDate: now
            ),
        ]
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
            formatShutter: { "\(Int($0))s" },
            ndNotationMode: .stops,
            timeContext: { timer in
                switch timer.status {
                case .running:
                    return "Ends soon"
                case .paused:
                    return "Paused recently"
                case .completed:
                    return "Completed recently"
                case .canceled:
                    return "Canceled recently"
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
                case .running, .paused, .canceled:
                    return nil
                }
            }
        )
    }

    @MainActor
    private func makeRuntimeHarness(now: TimeInterval) -> RuntimeHarness {
        var currentDate = Date(timeIntervalSince1970: now)
        let timerManager = RuntimeBackedTimerManaging(
            tickInterval: 60,
            dateProvider: { currentDate }
        )
        let viewModel = ExposureCalculatorViewModel(
            calculator: ExposureCalculator(),
            timerManager: timerManager
        )
        viewModel.scaleMode = .fullStop
        let adapter = BottomSheetWorkspacePresentationAdapter(
            formatRemaining: viewModel.formatTimerClock,
            formatShutter: viewModel.formatShutter,
            timeContext: viewModel.timerTimeContext,
            compactCompletedSupplementaryText: viewModel.compactCompletedSupplementaryText
        )
        let snapshotStore = BottomSheetWorkspaceSnapshotStore(
            initialTimers: viewModel.timers,
            timersPublisher: viewModel.$timers.eraseToAnyPublisher(),
            ndNotationModePublisher: viewModel.$ndNotationMode.eraseToAnyPublisher(),
            adapter: adapter
        )
        let stateStore = BottomSheetWorkspaceStateStore()

        return RuntimeHarness(
            timerManager: timerManager,
            viewModel: viewModel,
            snapshotStore: snapshotStore,
            stateStore: stateStore,
            currentDate: { currentDate },
            setCurrentDate: { currentDate = $0 }
        )
    }

    @MainActor
    private struct RuntimeHarness {
        let timerManager: RuntimeBackedTimerManaging
        let viewModel: ExposureCalculatorViewModel
        let snapshotStore: BottomSheetWorkspaceSnapshotStore
        let stateStore: BottomSheetWorkspaceStateStore
        let currentDateProvider: () -> Date
        let setCurrentDate: (Date) -> Void

        var currentDate: Date {
            get { currentDateProvider() }
            nonmutating set { setCurrentDate(newValue) }
        }

        init(
            timerManager: RuntimeBackedTimerManaging,
            viewModel: ExposureCalculatorViewModel,
            snapshotStore: BottomSheetWorkspaceSnapshotStore,
            stateStore: BottomSheetWorkspaceStateStore,
            currentDate: @escaping () -> Date,
            setCurrentDate: @escaping (Date) -> Void
        ) {
            self.timerManager = timerManager
            self.viewModel = viewModel
            self.snapshotStore = snapshotStore
            self.stateStore = stateStore
            self.currentDateProvider = currentDate
            self.setCurrentDate = setCurrentDate
        }
    }
}
