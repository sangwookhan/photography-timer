// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

public enum TimerWorkspaceAnimation {
    public static func movementDuration(reduceMotion: Bool) -> TimeInterval {
        reduceMotion ? 0.15 : 0.55
    }

    public static func movement(reduceMotion: Bool) -> Animation {
        .easeInOut(duration: movementDuration(reduceMotion: reduceMotion))
    }
}
