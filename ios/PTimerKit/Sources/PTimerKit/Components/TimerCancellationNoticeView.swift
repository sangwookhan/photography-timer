// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import SwiftUI

public struct TimerCancellationNoticeView: View {
    @ObservedObject private var model: TimerCancellationNoticeModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var isVisible = false

    public init(model: TimerCancellationNoticeModel) {
        self.model = model
    }

    public var body: some View {
        VStack(spacing: 0) {
            if let text = model.text {
                Button(action: model.dismiss) {
                    Label(text, systemImage: "xmark.circle")
                        .font(.subheadline)
                        .padding(12)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .accessibilityHint(Text("Dismiss"))
                .accessibilityIdentifier("timer-cancellation-notice")
                .padding(.horizontal)
                .padding(.bottom, 12)
            }
        }
        .onAppear {
            isVisible = true
            if scenePhase == .active { model.presentPendingNotice() }
        }
        .onDisappear { isVisible = false }
        .onChange(of: model.pendingTimerIDs, initial: true) { _, _ in
            if isVisible && scenePhase == .active { model.presentPendingNotice() }
        }
        .onChange(of: scenePhase) { _, phase in
            if isVisible && phase == .active { model.presentPendingNotice() }
        }
    }
}
