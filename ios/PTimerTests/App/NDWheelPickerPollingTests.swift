// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import UIKit
import XCTest
@testable import PTimer

/// The owned picker's visual-center poll is bounded: paused at rest,
/// running from a touch through deceleration, paused again once UIKit
/// reports the settled row or the wheel has sat on its selected row.
@MainActor
final class NDWheelPickerPollingTests: XCTestCase {
    private typealias Picker = NDWheelPickerView<Int, Text>

    private func makeCoordinator() -> (Picker.Coordinator, UIPickerView) {
        let view = Picker(
            steps: [0, 1, 2],
            selectedStep: 0,
            isCleanableRow: { $0 == 0 },
            isResolved: true,
            isInputEnabled: true,
            generation: 1,
            rowConfiguration: AnyHashable(0),
            rowHeight: 32,
            rowContent: { Text(String($0)) },
            onRowObserved: { _, _ in },
            onSelected: { _, _ in },
            onTouchBegan: { _ in },
            onTouchEnded: {},
            onOverscrollReleased: { _ in }
        )
        let coordinator = view.makeCoordinator()
        let picker = UIPickerView(frame: CGRect(x: 0, y: 0, width: 80, height: 160))
        picker.dataSource = coordinator
        picker.delegate = coordinator
        coordinator.attach(to: picker)
        return (coordinator, picker)
    }

    func testPollIsPausedAtRestAndRunsFromTouchUntilTheSettledRow() {
        let (coordinator, picker) = makeCoordinator()
        XCTAssertFalse(coordinator.isPolling, "Idle wheels do not poll.")

        coordinator.setTouchActiveForTesting(true)
        XCTAssertTrue(coordinator.isPolling)

        coordinator.setTouchActiveForTesting(false)
        XCTAssertTrue(coordinator.isPolling, "Deceleration after release is still observed.")

        coordinator.pickerView(picker, didSelectRow: 1, inComponent: 0)
        XCTAssertFalse(coordinator.isPolling, "UIKit's settled row ends the poll.")
    }

    func testSettledRowDuringATouchKeepsPollingUntilRelease() {
        let (coordinator, picker) = makeCoordinator()
        coordinator.setTouchActiveForTesting(true)
        coordinator.pickerView(picker, didSelectRow: 1, inComponent: 0)
        XCTAssertTrue(coordinator.isPolling, "A finger still down can move rows again.")
    }

    func testWheelRestingOnItsSelectedRowAfterReleasePausesWithoutADidSelect() {
        let (coordinator, picker) = makeCoordinator()
        // The coordinator only holds the picker weakly; keep it alive
        // for the ticks, as the hosting view does in the app.
        withExtendedLifetime(picker) {
            coordinator.setTouchActiveForTesting(true)
            coordinator.setTouchActiveForTesting(false)
            for _ in 0..<14 {
                coordinator.handleTick()
            }
            XCTAssertTrue(coordinator.isPolling, "Fourteen quiet ticks are not yet a settle.")
            coordinator.handleTick()
            XCTAssertFalse(coordinator.isPolling, "Half a second at rest on the selected row ends the poll.")
        }
    }
}

/// The Base barrier must not confuse touch release, delegate delivery or an
/// unchanged selectedRow with completed momentum/final snap.
@MainActor
final class BaseWheelSettlementTests: XCTestCase {
    func testMomentumAndSubRowSnapDelayCommitIncludingSameValueGesture() {
        var events: [String] = []
        let view = BaseWheelPickerView(steps: [1, 2, 4], selected: 1, rowHeight: 32, renderingKey: AnyHashable(0),
                                       rowContent: { Text(String($0)) }, onBegin: { events.append("begin") },
                                       onPreview: { events.append("live \($0)") }, onCommit: { events.append("commit \($0)") })
        let coordinator = view.makeCoordinator()
        coordinator.begin()
        for index in 0..<30 {
            coordinator.sample(row: 0, selectedRow: 0, geometry: [CGFloat(index)], scrolling: true)
        }
        for index in 0..<30 {
            coordinator.sample(row: 0, selectedRow: 0, geometry: [CGFloat(index)], scrolling: false)
        }
        XCTAssertFalse(events.contains { $0.hasPrefix("commit") }, "Moving within the same row is not a snap.")
        for _ in 0..<16 { coordinator.sample(row: 0, selectedRow: 0, geometry: [0], scrolling: false) }
        XCTAssertEqual(events, ["begin", "live 1.0", "commit 1.0"])
        coordinator.sample(row: 0, selectedRow: 0, geometry: [0], scrolling: false)
        XCTAssertEqual(events.count, 3, "One final commit per interaction.")
    }

    func testAccessibleDelegateStartsBarrierButProgrammaticRestoreDoesNot() {
        var committed: [Double] = []
        var starts = 0
        let view = BaseWheelPickerView(steps: [1, 2], selected: 1, rowHeight: 32, renderingKey: AnyHashable(0),
                                       rowContent: { Text(String($0)) }, onBegin: { starts += 1 },
                                       onPreview: { _ in }, onCommit: { committed.append($0) })
        let coordinator = view.makeCoordinator()
        let picker = UIPickerView(frame: CGRect(x: 0, y: 0, width: 100, height: 160))
        picker.dataSource = coordinator
        picker.delegate = coordinator
        coordinator.attach(picker)
        XCTAssertEqual(starts, 0)
        coordinator.pickerView(picker, didSelectRow: 1, inComponent: 0)
        XCTAssertEqual(starts, 1)
        XCTAssertTrue(committed.isEmpty)
        for _ in 0..<16 { coordinator.sample(row: 1, selectedRow: 1, geometry: [80], scrolling: false) }
        XCTAssertEqual(committed, [2])
        coordinator.detach()
    }
}

@MainActor
extension BaseWheelSettlementTests {
    func testRealRenderedPickerCentersReachTheFinalCommitBarrier() {
        var committed: [Double] = []
        let view = BaseWheelPickerView(steps: [1, 2, 4], selected: 2, rowHeight: 34, renderingKey: AnyHashable(0),
                                       rowContent: { Text(String($0)) }, onBegin: {}, onPreview: { _ in }, onCommit: { committed.append($0) })
        let coordinator = view.makeCoordinator()
        let picker = UIPickerView(frame: CGRect(x: 0, y: 0, width: 120, height: 160))
        picker.dataSource = coordinator
        picker.delegate = coordinator
        let host = UIViewController()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 240, height: 240))
        window.rootViewController = host
        host.view.addSubview(picker)
        window.isHidden = false
        coordinator.attach(picker)
        picker.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        coordinator.begin()
        for _ in 0..<16 { coordinator.tick() }
        XCTAssertEqual(committed, [2], "Use real hosted row centers, not a simulated selectedRow alone.")
        coordinator.detach()
        window.isHidden = true
    }
}

@MainActor
extension BaseWheelSettlementTests {
    func testOwnedPickerExposesFormattedValueToAccessibility() {
        let view = BaseWheelPickerView(steps: [0.5, 1], selected: 1, rowHeight: 34, renderingKey: AnyHashable(0),
                                       rowContent: { Text(String($0)) }, onBegin: {}, onPreview: { _ in }, onCommit: { _ in },
                                       accessibilityValue: { $0 == 1 ? "1s" : "1/2s" })
        let coordinator = view.makeCoordinator()
        let picker = UIPickerView()
        picker.dataSource = coordinator; picker.delegate = coordinator
        coordinator.attach(picker)
        XCTAssertEqual(picker.accessibilityValue, "1s")
        XCTAssertEqual(coordinator.pickerView(picker, viewForRow: 0, forComponent: 0, reusing: nil).accessibilityLabel, "1/2s")
        coordinator.detach()
    }
}
