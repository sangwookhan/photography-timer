// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import XCTest
@testable import PTimer

@MainActor
final class FakeMuteProbe: MuteLikelihoodProbing {
    var result: Bool
    private(set) var probeCount = 0
    private let deferCompletion: Bool
    private var pendingCompletion: (@MainActor (Bool) -> Void)?

    init(result: Bool, deferCompletion: Bool = false) {
        self.result = result
        self.deferCompletion = deferCompletion
    }

    func probe(completion: @escaping @MainActor (Bool) -> Void) {
        probeCount += 1
        if deferCompletion {
            pendingCompletion = completion
        } else {
            completion(result)
        }
    }

    func finishDeferredProbe() {
        pendingCompletion?(result)
        pendingCompletion = nil
    }
}

final class SilentModeAdvisoryTests: XCTestCase {
    @MainActor
    func testAllowedActiveEntryShowsAdvisoryWhenMutedLikely() {
        let controller = SilentModeAdvisoryController(probe: FakeMuteProbe(result: true))

        controller.handleAppBecameActive(isAlarmSounding: false)

        XCTAssertTrue(controller.isAdvisoryVisible)
    }

    @MainActor
    func testNotMutedLikelyDoesNotShowAdvisory() {
        let controller = SilentModeAdvisoryController(probe: FakeMuteProbe(result: false))

        controller.handleAppBecameActive(isAlarmSounding: false)

        XCTAssertFalse(controller.isAdvisoryVisible)
    }

    @MainActor
    func testAlarmSoundingSuppressesProbe() {
        let probe = FakeMuteProbe(result: true)
        let controller = SilentModeAdvisoryController(probe: probe)

        controller.handleAppBecameActive(isAlarmSounding: true)

        XCTAssertEqual(probe.probeCount, 0)
        XCTAssertFalse(controller.isAdvisoryVisible)
    }

    @MainActor
    func testNotificationEntrySuppressesAdvisoryWithoutBurningSession() {
        let probe = FakeMuteProbe(result: true)
        let controller = SilentModeAdvisoryController(probe: probe)

        controller.noteOpenedFromNotification()
        controller.handleAppBecameActive(isAlarmSounding: false)
        XCTAssertEqual(probe.probeCount, 0)
        XCTAssertFalse(controller.isAdvisoryVisible)

        // The suppressed notification entry must not burn the one-per-session
        // probe: a later quiet entry can still surface the advisory.
        controller.handleAppBecameActive(isAlarmSounding: false)
        XCTAssertEqual(probe.probeCount, 1)
        XCTAssertTrue(controller.isAdvisoryVisible)
    }

    @MainActor
    func testProbesAtMostOncePerSession() {
        let probe = FakeMuteProbe(result: false)
        let controller = SilentModeAdvisoryController(probe: probe)

        controller.handleAppBecameActive(isAlarmSounding: false)
        controller.handleAppBecameActive(isAlarmSounding: false)

        XCTAssertEqual(probe.probeCount, 1)
    }

    @MainActor
    func testNotificationTapDuringAsyncProbeStillSuppresses() {
        let probe = FakeMuteProbe(result: true, deferCompletion: true)
        let controller = SilentModeAdvisoryController(probe: probe)

        controller.handleAppBecameActive(isAlarmSounding: false)
        // A notification tap lands while the probe is still in flight
        // (cold-launch race): the post-probe re-check must still suppress.
        controller.noteOpenedFromNotification()
        probe.finishDeferredProbe()

        XCTAssertFalse(controller.isAdvisoryVisible)
    }
}
