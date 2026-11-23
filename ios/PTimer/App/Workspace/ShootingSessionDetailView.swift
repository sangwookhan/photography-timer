// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import PTimerKit
import SwiftUI

struct ShootingSessionDetailView: View {
    let title: String
    let sections: [TimerWorkspaceSection]

    var body: some View {
        List {
            ForEach(sections) { section in
                Section(section.title) {
                    ForEach(section.items) { item in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(item.title ?? String(localized: "Timer"))
                                .font(.headline)
                            if let subtitle = item.identitySubtitle {
                                Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
                            }
                            Text(item.remainingText).monospacedDigit()
                            if let total = item.totalDurationText {
                                Text(total).font(.footnote).foregroundStyle(.secondary)
                            }
                            if let timing = item.timingText {
                                Text(timing).font(.footnote).foregroundStyle(.secondary)
                            }
                            if let context = item.contextText {
                                Text(context).font(.footnote).foregroundStyle(.secondary)
                            }
                            if let filters = item.filterReferenceText {
                                Text(filters).font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("session-timer-\(item.id.uuidString)")
                    }
                }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("shooting-session-detail")
    }
}
