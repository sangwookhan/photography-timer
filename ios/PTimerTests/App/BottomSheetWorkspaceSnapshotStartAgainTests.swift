import XCTest
import PTimerCore
@testable import PTimer

/// PTIMER-36: tests for the Start Again surface (completed-row clone)
/// extracted from BottomSheetWorkspaceSnapshotFactoryTests so the
/// factory test class stays within strict file/type-length budgets.
final class BottomSheetStartAgainTests: XCTestCase {
    @MainActor
    func testCompletedRowSurfacesStartAgainActionAndOtherStatusesDoNot() throws {
        let snapshot = makeSnapshot(from: sampleTimers())
        let activeSection = try XCTUnwrap(
            snapshot.sections.first(where: { $0.title == "Active" })
        )
        let completedSection = try XCTUnwrap(
            snapshot.sections.first(where: { $0.title == "Recently Completed" })
        )

        for activeItem in activeSection.items {
            XCTAssertFalse(
                activeItem.actions.contains(.startAgain),
                "\(activeItem.status) timers must not surface the Start Again action"
            )
        }

        for completedItem in completedSection.items {
            XCTAssertTrue(
                completedItem.actions.contains(.startAgain),
                "Completed timers must surface the Start Again action"
            )
            XCTAssertEqual(
                completedItem.actions,
                [.startAgain, .remove],
                "Start Again is presented before Remove on completed rows"
            )
        }
    }

    @MainActor
    func testStartingNewTimerFromCompletedAddsCloneAndLeavesSourceUnchanged() throws {
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
        harness.viewModel.startNewTimer(fromCompleted: completedSource)

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
    func testStartingNewTimerFromNonCompletedRowIsRejected() throws {
        let harness = makeRuntimeHarness(now: 100)

        harness.viewModel.startTimer(from: 60)
        let runningSource = try XCTUnwrap(harness.viewModel.timers.first)
        XCTAssertEqual(runningSource.status, .running)

        harness.viewModel.startNewTimer(fromCompleted: runningSource)

        XCTAssertEqual(harness.viewModel.timers.count, 1)
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

        XCTAssertEqual(timer.name, "6 stops - 4s")
        XCTAssertEqual(timer.basisSummary, "Base 1/15s · 6 stops")
        XCTAssertEqual(timer.duration, 4, accuracy: 0.0001)
        XCTAssertEqual(compactItem.id, timer.id)
        XCTAssertEqual(largeItem.id, timer.id)
        XCTAssertEqual(largeItem.contextText, timer.basisSummary)
        XCTAssertEqual(largeItem.remainingText, harness.viewModel.formatTimerClock(4))
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

    @MainActor
    private func makeRuntimeHarness(now: TimeInterval) -> RuntimeHarness {
        var currentDate = Date(timeIntervalSince1970: now)
        let timerManager = TimerManager(
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
            timeContext: viewModel.timerTimeContext,
            compactCompletedSupplementaryText: viewModel.compactCompletedSupplementaryText
        )
        let snapshotStore = BottomSheetWorkspaceSnapshotStore(
            initialTimers: viewModel.timers,
            timersPublisher: viewModel.$timers.eraseToAnyPublisher(),
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
        let timerManager: TimerManager
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
            timerManager: TimerManager,
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
