// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

public struct TimerStartWarningView: View {
    @ObservedObject private var model: TimerCancellationNoticeModel

    public init(model: TimerCancellationNoticeModel) {
        self.model = model
    }

    public var body: some View {
        if model.hasPausedTimers {
            Text("Starting a new timer cancels paused timers.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("timer-start-paused-warning")
        }
    }
}
