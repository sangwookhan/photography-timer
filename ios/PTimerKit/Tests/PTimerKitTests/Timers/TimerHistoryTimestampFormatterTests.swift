// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import XCTest
@testable import PTimerKit
import PTimerCore

/// Absolute event timestamps in timer History (completed / canceled, and the
/// shared running "Ends" / paused rows) must render in the device's local
/// time zone (regression guard for PTIMER-146) using the active system
/// locale and the user's 12/24-hour time preference, never a fixed pattern
/// or hardcoded locale (regression guard for PTIMER-229 / L10N-014).
final class TimerHistoryTimestampFormatterTests: XCTestCase {
    /// `en_US` with an explicit hour-cycle override, standing in for the
    /// device's "24-Hour Time" preference toggle without touching global
    /// process/simulator state.
    private static func english(hourCycle: Locale.HourCycle) -> Locale {
        var components = Locale.Components(identifier: "en_US")
        components.hourCycle = hourCycle
        return Locale(components: components)
    }

    @MainActor
    func testAbsoluteTimestampUsesDeviceLocalTimeZone() {
        let viewModel = ExposureCalculatorViewModel(
            calculator: ExposureCalculator(),
            timerManager: FakeTimerManaging()
        )
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let locale = Self.english(hourCycle: .zeroToTwentyThree)

        let expected = date.formatted(
            Date.FormatStyle(date: .numeric, time: .standard, locale: locale, timeZone: .current)
        )

        XCTAssertEqual(viewModel.formatDateTime(date, locale: locale), expected)
    }

    @MainActor
    func testAbsoluteTimestampFollows24HourPreferenceWhenForced() {
        let viewModel = ExposureCalculatorViewModel(
            calculator: ExposureCalculator(),
            timerManager: FakeTimerManaging()
        )
        let date = Date(timeIntervalSince1970: 1_700_000_000)

        let text = viewModel.formatDateTime(date, locale: Self.english(hourCycle: .zeroToTwentyThree))

        XCTAssertFalse(text.contains("AM"))
        XCTAssertFalse(text.contains("PM"))
    }

    @MainActor
    func testAbsoluteTimestampFollows12HourPreferenceWhenForced() {
        let viewModel = ExposureCalculatorViewModel(
            calculator: ExposureCalculator(),
            timerManager: FakeTimerManaging()
        )
        let date = Date(timeIntervalSince1970: 1_700_000_000)

        let text = viewModel.formatDateTime(date, locale: Self.english(hourCycle: .oneToTwelve))

        XCTAssertTrue(text.contains("AM") || text.contains("PM"))
    }

    @MainActor
    func testAbsoluteTimestampUsesActiveLocaleForKorean() {
        let viewModel = ExposureCalculatorViewModel(
            calculator: ExposureCalculator(),
            timerManager: FakeTimerManaging()
        )
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let locale = Locale(identifier: "ko_KR")

        let expected = date.formatted(
            Date.FormatStyle(date: .numeric, time: .standard, locale: locale, timeZone: .current)
        )

        XCTAssertEqual(viewModel.formatDateTime(date, locale: locale), expected)
    }

    /// Locks the public, no-locale-argument entry point that every production
    /// call site actually uses. The other tests above exercise the internal
    /// `formatDateTime(_:locale:)` test seam directly and would keep passing
    /// even if the public overload alone regressed back to a hardcoded
    /// formatter; this test would catch that.
    @MainActor
    func testPublicFormatDateTimeUsesLiveSystemLocaleAndTimeZone() {
        let viewModel = ExposureCalculatorViewModel(
            calculator: ExposureCalculator(),
            timerManager: FakeTimerManaging()
        )
        let date = Date(timeIntervalSince1970: 1_700_000_000)

        let expected = date.formatted(
            Date.FormatStyle(date: .numeric, time: .standard, locale: .autoupdatingCurrent, timeZone: .autoupdatingCurrent)
        )

        XCTAssertEqual(viewModel.formatDateTime(date), expected)
    }

    @MainActor
    func testAbsoluteTimestampNoLongerForcesHardcodedPOSIXPattern() {
        let viewModel = ExposureCalculatorViewModel(
            calculator: ExposureCalculator(),
            timerManager: FakeTimerManaging()
        )
        let date = Date(timeIntervalSince1970: 1_700_000_000)

        let hardcodedPOSIXFormatter = DateFormatter()
        hardcodedPOSIXFormatter.calendar = Calendar(identifier: .gregorian)
        hardcodedPOSIXFormatter.locale = Locale(identifier: "en_US_POSIX")
        hardcodedPOSIXFormatter.timeZone = .current
        hardcodedPOSIXFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"

        let koreanText = viewModel.formatDateTime(date, locale: Locale(identifier: "ko_KR"))

        XCTAssertNotEqual(koreanText, hardcodedPOSIXFormatter.string(from: date))
    }
}
