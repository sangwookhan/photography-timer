// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import PTimerKit
import SwiftUI

struct ShootingRecordDetailView: View {
    let record: PersistentShootingRecord

    var body: some View {
        let display = ShootingRecordPresenter.display(record)
        List {
            Section {
                Text(display.title).font(.headline)
                Text(display.subtitle).foregroundStyle(.secondary)
            }
            Section("Captured record") {
                ForEach(display.fields) { field in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(field.label).font(.caption).foregroundStyle(.secondary)
                        Text(field.value).textSelection(.enabled)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .navigationTitle("Record")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("shooting-record-detail")
    }
}
