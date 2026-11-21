// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import PTimerKit
import SwiftUI

struct ShootingCollectionDestinationRow: View {
    let collection: PersistentShootingCollection
    let isSelected: Bool

    var body: some View {
        let summary = ShootingCollectionSummaryPresenter.display(collection)
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text(collection.title).font(.headline).foregroundStyle(Color.primary)
                Label {
                    let camera = summary.representativeCameraName ?? String(localized: "Camera not recorded")
                    if summary.additionalCameraCount > 0 {
                        Text("\(camera) + \(summary.additionalCameraCount) more")
                    } else {
                        Text(camera)
                    }
                } icon: {
                    Image(systemName: "camera").accessibilityHidden(true)
                }
                Label("Location not recorded", systemImage: "mappin.and.ellipse")
                if summary.missingCameraCount > 0 && summary.missingCameraCount < summary.recordCount {
                    Text("Camera missing in \(summary.missingCameraCount) records")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .trailing, spacing: 5) {
                if let start = summary.startDate {
                    Text("Started \(start.formatted(.dateTime.month(.twoDigits).day(.twoDigits).hour().minute().second()))")
                } else {
                    Text("Start not recorded")
                }
                if let end = summary.endDate {
                    Text("Ended \(end.formatted(.dateTime.month(.twoDigits).day(.twoDigits).hour().minute().second()))")
                    if summary.missingEndCount > 0 {
                        Text("End missing in \(summary.missingEndCount) records")
                    }
                } else {
                    Text("End not recorded")
                }
                Text("\(summary.recordCount) records")
            }
            .layoutPriority(1)
            .multilineTextAlignment(.trailing)
            Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
                .opacity(isSelected ? 1 : 0)
                .accessibilityHidden(true)
        }
        .font(.caption)
        .foregroundStyle(Color.secondary)
        .accessibilityElement(children: .combine)
    }
}
