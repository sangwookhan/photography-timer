// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// A page of the shooting pager: a camera, or the utility page that
/// follows the last camera (CAMERA-PAGER-007).
public enum CameraPagerPage: Hashable {
    case camera(CameraSlotID)
    case utilityPage
}

/// Where camera management was opened from; decides where closing it
/// returns to (CAMERA-PAGER-007).
public enum CameraManagementOrigin: Equatable {
    case utilityPage
    case settings
    case emptyState
}

public enum CameraPagerReturnTarget: Equatable {
    case utilityPage
    case activeCamera
    case emptyState
}

/// Pure pager rules, kept out of the views so they can be tested.
public enum CameraPagerNavigation {
    /// Closing camera management: from the utility page it returns there
    /// while at least one camera remains displayed (the empty state
    /// replaces it otherwise); from Settings it returns to the active
    /// camera, or to the empty state when no camera is displayed.
    public static func returnTarget(
        from origin: CameraManagementOrigin,
        displayedCameraCount: Int
    ) -> CameraPagerReturnTarget {
        guard displayedCameraCount > 0 else { return .emptyState }
        switch origin {
        case .utilityPage: return .utilityPage
        case .settings, .emptyState: return .activeCamera
        }
    }

    /// The standard page indicator includes the utility page; camera
    /// position labels and camera counts exclude it.
    public struct Indicator: Equatable {
        public let dotCount: Int
        public let activeDot: Int
        /// `n of M` over cameras only; `nil` on the utility page.
        public let positionText: String?
        /// The indicator's accessibility value.
        public let accessibilityValue: String
    }

    /// `nil` when no camera is displayed (the empty state has no pager).
    public static func indicator(
        displayedCameraCount: Int,
        activeCameraIndex: Int,
        isUtilityPageShowing: Bool
    ) -> Indicator? {
        guard displayedCameraCount > 0 else { return nil }
        if isUtilityPageShowing {
            return Indicator(
                dotCount: displayedCameraCount + 1,
                activeDot: displayedCameraCount,
                positionText: nil,
                accessibilityValue: String(localized: "Camera management")
            )
        }
        let text = "\(activeCameraIndex + 1) of \(displayedCameraCount)"
        return Indicator(
            dotCount: displayedCameraCount + 1,
            activeDot: activeCameraIndex,
            positionText: text,
            accessibilityValue: text
        )
    }

    /// The page the pager shows for the current state.
    public static func page(
        activeCamera: CameraSlotID?,
        firstDisplayedCamera: CameraSlotID?,
        isUtilityPageShowing: Bool
    ) -> CameraPagerPage {
        if isUtilityPageShowing { return .utilityPage }
        return .camera(activeCamera ?? firstDisplayedCamera ?? .camera1)
    }

    /// The accessibility "Next camera" action: from the last camera it
    /// reveals the utility page.
    public static func revealsUtilityPage(
        activeCameraIndex: Int,
        displayedCameraCount: Int
    ) -> Bool {
        displayedCameraCount > 0 && activeCameraIndex == displayedCameraCount - 1
    }
}
