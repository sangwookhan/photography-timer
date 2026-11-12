// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import PTimerKit
import SwiftUI

struct ShootingRecordSummaryView: View {
    let record: PersistentShootingRecord

    var body: some View {
        let display = ShootingRecordPresenter.display(record)
        VStack(alignment: .leading, spacing: 4) {
            Text(display.title).font(.headline)
            Text(display.subtitle).font(.subheadline).foregroundStyle(.secondary)
            Text(record.startDate, format: .dateTime.month().day().hour().minute().second())
                .font(.caption).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}
