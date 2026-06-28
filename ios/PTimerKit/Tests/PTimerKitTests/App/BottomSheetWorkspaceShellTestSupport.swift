// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import XCTest
import PTimerKit

extension XCTestCase {
    func bottomSheetSampleTimers() -> [RunningTimerItem] {
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

    func bottomSheetLongDurationTimer() -> RunningTimerItem {
        let now = Date(timeIntervalSince1970: 1_000)

        return RunningTimerItem(
            id: UUID(uuidString: "55555555-5555-5555-5555-555555555555")!,
            order: 5,
            name: "Very Long Timer Name That Exceeds Compact Width",
            basisSummary: "Base 1/2s · 18 stops",
            duration: 367_200,
            startDate: now,
            endDate: now.addingTimeInterval(367_200),
            pausedRemainingTime: nil,
            pausedAt: nil,
            status: .running,
            referenceDate: now
        )
    }

    func bottomSheetSecondsScaleTimer() -> RunningTimerItem {
        let now = Date(timeIntervalSince1970: 4_000)

        return RunningTimerItem(
            id: UUID(uuidString: "12121212-1212-1212-1212-121212121212")!,
            order: 7,
            name: "Seconds Scale",
            basisSummary: "Base 1/15s · 3 stops",
            duration: 30,
            startDate: now.addingTimeInterval(-5),
            endDate: now.addingTimeInterval(25),
            pausedRemainingTime: nil,
            pausedAt: nil,
            status: .running,
            referenceDate: now
        )
    }

    func bottomSheetMinuteScaleTimer() -> RunningTimerItem {
        let now = Date(timeIntervalSince1970: 5_000)

        return RunningTimerItem(
            id: UUID(uuidString: "23232323-2323-2323-2323-232323232323")!,
            order: 8,
            name: "Minute Scale",
            basisSummary: "Base 1/30s · 5 stops",
            duration: 64,
            startDate: now.addingTimeInterval(-10),
            endDate: now.addingTimeInterval(54),
            pausedRemainingTime: nil,
            pausedAt: nil,
            status: .running,
            referenceDate: now
        )
    }

    func bottomSheetEightMinuteScaleTimer() -> RunningTimerItem {
        let now = Date(timeIntervalSince1970: 5_500)

        return RunningTimerItem(
            id: UUID(uuidString: "28282828-2828-2828-2828-282828282828")!,
            order: 12,
            name: "Eight Minute Scale",
            basisSummary: "Base 1/30s · 6 stops",
            duration: 480,
            startDate: now.addingTimeInterval(-2),
            endDate: now.addingTimeInterval(478),
            pausedRemainingTime: nil,
            pausedAt: nil,
            status: .running,
            referenceDate: now
        )
    }

    func bottomSheetThirtyFourMinuteScaleTimer() -> RunningTimerItem {
        let now = Date(timeIntervalSince1970: 5_800)

        return RunningTimerItem(
            id: UUID(uuidString: "38383838-3838-3838-3838-383838383838")!,
            order: 13,
            name: "Thirty Four Minute Scale",
            basisSummary: "Base 1/60s · 7 stops",
            duration: 2_048,
            startDate: now,
            endDate: now.addingTimeInterval(2_048),
            pausedRemainingTime: nil,
            pausedAt: nil,
            status: .running,
            referenceDate: now
        )
    }

    func bottomSheetHourScaleTimer() -> RunningTimerItem {
        let now = Date(timeIntervalSince1970: 6_000)

        return RunningTimerItem(
            id: UUID(uuidString: "34343434-3434-3434-3434-343434343434")!,
            order: 9,
            name: "Hour Scale",
            basisSummary: "Base 1/60s · 7 stops",
            duration: 7_200,
            startDate: now,
            endDate: now.addingTimeInterval(7_200),
            pausedRemainingTime: nil,
            pausedAt: nil,
            status: .running,
            referenceDate: now
        )
    }

    func bottomSheetPausedProgressTimer() -> RunningTimerItem {
        let now = Date(timeIntervalSince1970: 7_000)

        return RunningTimerItem(
            id: UUID(uuidString: "45454545-4545-4545-4545-454545454545")!,
            order: 10,
            name: "Paused Progress",
            basisSummary: "Base 1/8s · 4 stops",
            duration: 120,
            startDate: now.addingTimeInterval(-80),
            endDate: now.addingTimeInterval(60),
            pausedRemainingTime: 45,
            pausedAt: now.addingTimeInterval(-10),
            status: .paused,
            referenceDate: now
        )
    }

    func bottomSheetCompletedProgressTimer() -> RunningTimerItem {
        let now = Date(timeIntervalSince1970: 8_000)

        return RunningTimerItem(
            id: UUID(uuidString: "56565656-5656-5656-5656-565656565656")!,
            order: 11,
            name: "Completed Progress",
            basisSummary: "Base 1/4s · 2 stops",
            duration: 75,
            startDate: now.addingTimeInterval(-90),
            endDate: now.addingTimeInterval(-15),
            pausedRemainingTime: nil,
            pausedAt: nil,
            status: .completed,
            referenceDate: now
        )
    }

    func bottomSheetRedundantLargePresentationTimer() -> RunningTimerItem {
        let now = Date(timeIntervalSince1970: 1_500)

        return RunningTimerItem(
            id: UUID(uuidString: "99999999-9999-9999-9999-999999999999")!,
            order: 6,
            name: "Timer - 02:00",
            basisSummary: "Base 1/30s · 6 stops",
            duration: 120,
            startDate: now,
            endDate: now.addingTimeInterval(25),
            pausedRemainingTime: nil,
            pausedAt: nil,
            status: .running,
            referenceDate: now
        )
    }

    func makeBottomSheetSnapshot(from timers: [RunningTimerItem]) -> BottomSheetWorkspaceSnapshot {
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

    func bottomSheetTryUnwrapCompactItem(from snapshot: BottomSheetWorkspaceSnapshot) -> BottomSheetCompactItem {
        guard let item = snapshot.compactItems.first else {
            XCTFail("Expected a compact item in snapshot")
            fatalError("Missing compact item")
        }

        return item
    }
}
