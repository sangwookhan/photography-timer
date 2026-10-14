// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import XCTest
import PTimerKit

/// Pager utility page rules (CAMERA-PAGER-004, CAMERA-PAGER-007).
final class CameraPagerNavigationTests: XCTestCase {
    func testClosingManagementFromTheUtilityPageReturnsThereWhileACameraIsDisplayed() {
        XCTAssertEqual(CameraPagerNavigation.returnTarget(from: .utilityPage, displayedCameraCount: 1), .utilityPage)
        XCTAssertEqual(CameraPagerNavigation.returnTarget(from: .utilityPage, displayedCameraCount: 5), .utilityPage)
    }

    func testClosingManagementFromTheUtilityPageAfterEveryCameraWasHiddenShowsTheEmptyState() {
        XCTAssertEqual(CameraPagerNavigation.returnTarget(from: .utilityPage, displayedCameraCount: 0), .emptyState)
    }

    func testClosingManagementFromSettingsReturnsToTheActiveCameraOrTheEmptyState() {
        XCTAssertEqual(CameraPagerNavigation.returnTarget(from: .settings, displayedCameraCount: 3), .activeCamera)
        XCTAssertEqual(CameraPagerNavigation.returnTarget(from: .settings, displayedCameraCount: 0), .emptyState)
    }

    func testClosingManagementFromTheEmptyStateReturnsToTheActiveCameraOnceOneIsDisplayed() {
        XCTAssertEqual(CameraPagerNavigation.returnTarget(from: .emptyState, displayedCameraCount: 2), .activeCamera)
        XCTAssertEqual(CameraPagerNavigation.returnTarget(from: .emptyState, displayedCameraCount: 0), .emptyState)
    }

    func testTheIndicatorCountsTheUtilityPageButCameraPositionsExcludeIt() throws {
        let onCamera = try XCTUnwrap(CameraPagerNavigation.indicator(
            displayedCameraCount: 4, activeCameraIndex: 1, isUtilityPageShowing: false
        ))
        XCTAssertEqual(onCamera.dotCount, 5)
        XCTAssertEqual(onCamera.activeDot, 1)
        XCTAssertEqual(onCamera.positionText, "2 of 4", "Camera counts exclude the utility page.")
        XCTAssertEqual(onCamera.accessibilityValue, "2 of 4")

        let onUtility = try XCTUnwrap(CameraPagerNavigation.indicator(
            displayedCameraCount: 4, activeCameraIndex: 3, isUtilityPageShowing: true
        ))
        XCTAssertEqual(onUtility.dotCount, 5)
        XCTAssertEqual(onUtility.activeDot, 4, "The utility page is the last dot.")
        XCTAssertNil(onUtility.positionText)
        XCTAssertEqual(onUtility.accessibilityValue, "Camera management")
    }

    func testThereIsNoIndicatorWhenNoCameraIsDisplayed() {
        XCTAssertNil(CameraPagerNavigation.indicator(
            displayedCameraCount: 0, activeCameraIndex: 0, isUtilityPageShowing: false
        ))
    }

    func testThePageFollowsTheUtilityFlagWithoutChangingTheActiveCamera() {
        XCTAssertEqual(
            CameraPagerNavigation.page(activeCamera: .camera2, firstDisplayedCamera: .camera1, isUtilityPageShowing: false),
            .camera(.camera2)
        )
        XCTAssertEqual(
            CameraPagerNavigation.page(activeCamera: .camera2, firstDisplayedCamera: .camera1, isUtilityPageShowing: true),
            .utilityPage
        )
        XCTAssertEqual(
            CameraPagerNavigation.page(activeCamera: nil, firstDisplayedCamera: .camera3, isUtilityPageShowing: false),
            .camera(.camera3)
        )
    }

    func testNextCameraFromTheLastCameraRevealsTheUtilityPage() {
        XCTAssertTrue(CameraPagerNavigation.revealsUtilityPage(activeCameraIndex: 3, displayedCameraCount: 4))
        XCTAssertFalse(CameraPagerNavigation.revealsUtilityPage(activeCameraIndex: 2, displayedCameraCount: 4))
        XCTAssertFalse(CameraPagerNavigation.revealsUtilityPage(activeCameraIndex: 0, displayedCameraCount: 0))
    }
}
