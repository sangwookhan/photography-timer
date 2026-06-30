// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import XCTest
import PTimerCore

/// PTIMER-73: duration-bucket policy for staged timer alerts.
///
/// - `<= 30s` → completion only.
/// - `> 30s and <= 60s` → pre1 at T−5s, then completion.
/// - `> 60s` → pre1 at T−10s, pre2 at T−5s, then completion.
final class TimerAlertScheduleTests: XCTestCase {
    private let endDate = Date(timeIntervalSince1970: 1_000)

    func testShortTimerSchedulesCompletionOnly() {
        for duration: TimeInterval in [1, 15, 30] {
            let alerts = TimerAlertSchedule.alerts(duration: duration, endDate: endDate)
            XCTAssertEqual(
                alerts,
                [TimerStagedAlert(stage: .completion, fireDate: endDate, secondsBeforeCompletion: 0)],
                "duration \(duration) should produce completion only"
            )
        }
    }

    func testMediumTimerSchedulesPre1AndCompletion() {
        for duration: TimeInterval in [31, 45, 60] {
            let alerts = TimerAlertSchedule.alerts(duration: duration, endDate: endDate)
            XCTAssertEqual(
                alerts,
                [
                    TimerStagedAlert(
                        stage: .pre1,
                        fireDate: endDate.addingTimeInterval(-5),
                        secondsBeforeCompletion: 5
                    ),
                    TimerStagedAlert(stage: .completion, fireDate: endDate, secondsBeforeCompletion: 0),
                ],
                "duration \(duration) should produce pre1 at T-5 and completion"
            )
        }
    }

    func testLongTimerSchedulesPre1Pre2AndCompletion() {
        for duration: TimeInterval in [61, 75, 600] {
            let alerts = TimerAlertSchedule.alerts(duration: duration, endDate: endDate)
            XCTAssertEqual(
                alerts,
                [
                    TimerStagedAlert(
                        stage: .pre1,
                        fireDate: endDate.addingTimeInterval(-10),
                        secondsBeforeCompletion: 10
                    ),
                    TimerStagedAlert(
                        stage: .pre2,
                        fireDate: endDate.addingTimeInterval(-5),
                        secondsBeforeCompletion: 5
                    ),
                    TimerStagedAlert(stage: .completion, fireDate: endDate, secondsBeforeCompletion: 0),
                ],
                "duration \(duration) should produce pre1 at T-10, pre2 at T-5, and completion"
            )
        }
    }

    func testAlertsAreReturnedInFireOrder() {
        let alerts = TimerAlertSchedule.alerts(duration: 120, endDate: endDate)
        let fireDates = alerts.map(\.fireDate)
        XCTAssertEqual(fireDates, fireDates.sorted())
    }

    func testCompletionAlertAlwaysPresent() {
        for duration: TimeInterval in [1, 30, 45, 90] {
            let alerts = TimerAlertSchedule.alerts(duration: duration, endDate: endDate)
            XCTAssertEqual(alerts.last?.stage, .completion)
            XCTAssertEqual(alerts.last?.fireDate, endDate)
        }
    }
}
