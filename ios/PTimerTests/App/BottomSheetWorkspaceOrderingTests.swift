import PTimerKit
import PTimerCore
import XCTest
@testable import PTimer

final class BottomSheetWorkspaceOrderingTests: XCTestCase {
    func testActiveTimersPreserveStableRelativeOrderAcrossStatusChanges() {
        let before = makeSnapshot(from: activeOrderingTimers(pausedFirstTimerStatus: .running))
        let after = makeSnapshot(from: activeOrderingTimers(pausedFirstTimerStatus: .paused))

        XCTAssertEqual(
            before.compactItems.map(\.id),
            [
                UUID(uuidString: "ccccccc3-3333-3333-3333-333333333333")!,
                UUID(uuidString: "bbbbbbb2-2222-2222-2222-222222222222")!,
                UUID(uuidString: "aaaaaaa1-1111-1111-1111-111111111111")!,
            ]
        )
        XCTAssertEqual(before.compactItems.map(\.id), after.compactItems.map(\.id))
        XCTAssertEqual(before.sections.first?.items.map(\.id), after.sections.first?.items.map(\.id))
    }

    func testCompletedTimersAreDeferredBehindActiveTimersInWorkspaceOrdering() {
        let ordered = TimerWorkspaceOrdering.sort(completedAheadOfActiveTimers())

        XCTAssertEqual(
            ordered.map(\.id),
            [
                UUID(uuidString: "eeeeeee5-5555-5555-5555-555555555555")!,
                UUID(uuidString: "ddddddd4-4444-4444-4444-444444444444")!,
                UUID(uuidString: "fffffff6-6666-6666-6666-666666666666")!,
                UUID(uuidString: "77777777-7777-7777-7777-777777777777")!,
            ]
        )
        XCTAssertEqual(ordered.prefix(2).map(\.status), [.paused, .running])
        XCTAssertEqual(ordered.suffix(2).map(\.status), [.completed, .completed])
    }

    func testNewTimerIsAlwaysInsertedAtTheTop() {
        let now = Date(timeIntervalSince1970: 5_000)
        let timerA = RunningTimerItem(
            id: UUID(), order: 1, name: "A", basisSummary: "", duration: 60,
            startDate: now, endDate: now.addingTimeInterval(60),
            pausedRemainingTime: nil, pausedAt: nil,
            status: .running, referenceDate: now
        )
        let timerB = RunningTimerItem(
            id: UUID(), order: 2, name: "B", basisSummary: "", duration: 120,
            startDate: now, endDate: now.addingTimeInterval(120),
            pausedRemainingTime: nil, pausedAt: nil,
            status: .running, referenceDate: now
        )

        let snapshot = makeSnapshot(from: [timerA, timerB])
        XCTAssertEqual(snapshot.compactItems.map(\.id), [timerB.id, timerA.id])
        XCTAssertEqual(snapshot.sections.first?.items.map(\.id), [timerB.id, timerA.id])

        // Add timer C (newest)
        let timerC = RunningTimerItem(
            id: UUID(), order: 3, name: "C", basisSummary: "", duration: 180,
            startDate: now, endDate: now.addingTimeInterval(180),
            pausedRemainingTime: nil, pausedAt: nil,
            status: .running, referenceDate: now
        )
        let snapshot2 = makeSnapshot(from: [timerA, timerB, timerC])
        XCTAssertEqual(snapshot2.compactItems.map(\.id), [timerC.id, timerB.id, timerA.id])
    }

    func testNewTimerInsertedAtTopEvenWhenCompletedTimersExist() {
        let now = Date(timeIntervalSince1970: 6_000)
        let activeA = RunningTimerItem(
            id: UUID(), order: 1, name: "A", basisSummary: "", duration: 60,
            startDate: now, endDate: now.addingTimeInterval(60),
            pausedRemainingTime: nil, pausedAt: nil,
            status: .running, referenceDate: now
        )
        let completedB = RunningTimerItem(
            id: UUID(), order: 2, name: "B", basisSummary: "", duration: 30,
            startDate: now.addingTimeInterval(-60), endDate: now.addingTimeInterval(-30),
            pausedRemainingTime: nil, pausedAt: nil,
            status: .completed, referenceDate: now
        )

        let snapshot = makeSnapshot(from: [activeA, completedB])
        XCTAssertEqual(snapshot.compactItems.map(\.id), [activeA.id, completedB.id])

        // New active C
        let activeC = RunningTimerItem(
            id: UUID(), order: 3, name: "C", basisSummary: "", duration: 120,
            startDate: now, endDate: now.addingTimeInterval(120),
            pausedRemainingTime: nil, pausedAt: nil,
            status: .running, referenceDate: now
        )
        let snapshot2 = makeSnapshot(from: [activeA, completedB, activeC])
        XCTAssertEqual(snapshot2.compactItems.map(\.id), [activeC.id, activeA.id, completedB.id])
    }

    func testLargeSectionsGroupTimersByPresentationStatus() {
        let snapshot = makeSnapshot(from: sampleTimers())

        XCTAssertEqual(snapshot.sections.map(\.title), ["Active", "Recently Completed"])
        XCTAssertEqual(snapshot.sections[0].items.count, 2)
        XCTAssertEqual(snapshot.sections[1].items.count, 2)
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

    private func activeOrderingTimers(pausedFirstTimerStatus: TimerStatus) -> [RunningTimerItem] {
        let now = Date(timeIntervalSince1970: 2_000)

        return [
            RunningTimerItem(
                id: UUID(uuidString: "aaaaaaa1-1111-1111-1111-111111111111")!,
                order: 1,
                name: "First Active",
                basisSummary: "Base 1/30s · 6 stops",
                duration: 90,
                startDate: now.addingTimeInterval(-10),
                endDate: pausedFirstTimerStatus == .running ? now.addingTimeInterval(50) : now.addingTimeInterval(80),
                pausedRemainingTime: pausedFirstTimerStatus == .paused ? 50 : nil,
                pausedAt: pausedFirstTimerStatus == .paused ? now.addingTimeInterval(-5) : nil,
                status: pausedFirstTimerStatus,
                referenceDate: now
            ),
            RunningTimerItem(
                id: UUID(uuidString: "bbbbbbb2-2222-2222-2222-222222222222")!,
                order: 2,
                name: "Second Active",
                basisSummary: "Base 1/60s · 10 stops",
                duration: 200,
                startDate: now,
                endDate: now.addingTimeInterval(20),
                pausedRemainingTime: nil,
                pausedAt: nil,
                status: .running,
                referenceDate: now
            ),
            RunningTimerItem(
                id: UUID(uuidString: "ccccccc3-3333-3333-3333-333333333333")!,
                order: 3,
                name: "Third Active",
                basisSummary: "Base 1/15s · 8 stops",
                duration: 140,
                startDate: now.addingTimeInterval(-15),
                endDate: now.addingTimeInterval(110),
                pausedRemainingTime: 70,
                pausedAt: now.addingTimeInterval(-12),
                status: .paused,
                referenceDate: now
            ),
        ]
    }

    private func completedAheadOfActiveTimers() -> [RunningTimerItem] {
        let now = Date(timeIntervalSince1970: 3_000)

        return [
            RunningTimerItem(
                id: UUID(uuidString: "fffffff6-6666-6666-6666-666666666666")!,
                order: 3,
                name: "Completed Latest",
                basisSummary: "Base 1/8s · 5 stops",
                duration: 30,
                startDate: now.addingTimeInterval(-30),
                endDate: now.addingTimeInterval(-5),
                pausedRemainingTime: nil,
                pausedAt: nil,
                status: .completed,
                referenceDate: now
            ),
            RunningTimerItem(
                id: UUID(uuidString: "77777777-7777-7777-7777-777777777777")!,
                order: 4,
                name: "Completed Earlier",
                basisSummary: "Base 1/4s · 4 stops",
                duration: 20,
                startDate: now.addingTimeInterval(-50),
                endDate: now.addingTimeInterval(-20),
                pausedRemainingTime: nil,
                pausedAt: nil,
                status: .completed,
                referenceDate: now
            ),
            RunningTimerItem(
                id: UUID(uuidString: "ddddddd4-4444-4444-4444-444444444444")!,
                order: 1,
                name: "Active First",
                basisSummary: "Base 1/2s · 2 stops",
                duration: 180,
                startDate: now,
                endDate: now.addingTimeInterval(90),
                pausedRemainingTime: nil,
                pausedAt: nil,
                status: .running,
                referenceDate: now
            ),
            RunningTimerItem(
                id: UUID(uuidString: "eeeeeee5-5555-5555-5555-555555555555")!,
                order: 2,
                name: "Active Second",
                basisSummary: "Base 1/1s · 1 stop",
                duration: 240,
                startDate: now.addingTimeInterval(-20),
                endDate: now.addingTimeInterval(160),
                pausedRemainingTime: 55,
                pausedAt: now.addingTimeInterval(-10),
                status: .paused,
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

}
