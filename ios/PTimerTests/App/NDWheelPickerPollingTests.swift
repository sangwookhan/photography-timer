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
