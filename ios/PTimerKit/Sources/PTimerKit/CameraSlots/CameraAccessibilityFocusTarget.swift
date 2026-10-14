// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Where assistive-technology focus should land after a camera-list
/// change (CAMERA-PAGER-006): the resulting active camera, or the
/// empty-state message when no camera is active.
public enum CameraAccessibilityFocusTarget: Equatable, Hashable {
    case camera(CameraSlotID)
    case emptyState
}

/// A focus move and announcement that wait until the list edit and any
/// dismissing confirmation have settled. `id` is unique per request so
/// a second edit restarts the wait instead of being merged into the first.
public struct CameraFocusRequest: Equatable {
    public let id: UUID
    public let target: CameraAccessibilityFocusTarget
    public let message: String

    public init(id: UUID = UUID(), target: CameraAccessibilityFocusTarget, message: String) {
        self.id = id
        self.target = target
        self.message = message
    }

    /// Focus may move only once no confirmation is presented or
    /// dismissing; moving earlier lets the system restore focus to the
    /// control that presented it (the disabled bulk Delete button).
    public func isReady(isConfirmationPresented: Bool) -> Bool {
        !isConfirmationPresented
    }
}

/// A one-shot UIKit focus request for an edit-mode list cell. The pending
/// request is consumed by the first cell that fires it, so a recreated or
/// recycled row can never fire the same request again, and consuming an
/// old request never clears a newer one.
public struct CameraFocusLatch: Equatable {
    public private(set) var pendingID: UUID?
    public private(set) var pendingTarget: CameraAccessibilityFocusTarget?

    public init() {}

    public mutating func arm(id: UUID, target: CameraAccessibilityFocusTarget) {
        pendingID = id
        pendingTarget = target
    }

    /// The request id the row for `target` should fire; `nil` for any
    /// other row or when nothing is pending.
    public func requestID(for target: CameraAccessibilityFocusTarget) -> UUID? {
        pendingTarget == target ? pendingID : nil
    }

    /// Returns `true` once, for the pending request with this id, and clears it.
    @discardableResult
    public mutating func consume(_ id: UUID) -> Bool {
        guard pendingID == id else { return false }
        pendingID = nil
        pendingTarget = nil
        return true
    }
}
