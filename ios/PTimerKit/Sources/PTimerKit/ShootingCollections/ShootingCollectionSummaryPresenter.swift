// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import Foundation

public enum ShootingCollectionSummaryPresenter {
    public static func display(_ collection: PersistentShootingCollection) -> ShootingCollectionSummaryDisplayState {
        let records = collection.records
        var groups: [String: [PersistentShootingRecord]] = [:]
        for record in records {
            let metadata = record.metadata
            let key = metadata.cameraSlotIDRaw.map { "id:\($0)" }
                ?? cameraName(record).map { "name:\($0)" }
            if let key { groups[key, default: []].append(record) }
        }
        let cameras = groups.values.map { $0.sorted(by: earlierRecord) }.sorted { lhs, rhs in
            if lhs.count != rhs.count { return lhs.count > rhs.count }
            return earlierRecord(lhs[0], rhs[0])
        }
        return ShootingCollectionSummaryDisplayState(
            recordCount: records.count,
            startDate: records.map(\.startDate).min(),
            endDate: records.compactMap(\.terminalDate).max(),
            missingEndCount: records.filter { $0.terminalDate == nil }.count,
            representativeCameraName: cameras.first?.compactMap(cameraName).first,
            additionalCameraCount: max(0, cameras.count - 1),
            missingCameraCount: records.filter { cameraName($0) == nil }.count
        )
    }

    private static func cameraName(_ record: PersistentShootingRecord) -> String? {
        guard let name = record.metadata.cameraSlotDisplayName?.trimmingCharacters(in: .whitespacesAndNewlines),
              !name.isEmpty else { return nil }
        return name
    }

    private static func earlierRecord(_ lhs: PersistentShootingRecord, _ rhs: PersistentShootingRecord) -> Bool {
        lhs.startDate == rhs.startDate ? lhs.id.uuidString < rhs.id.uuidString : lhs.startDate < rhs.startDate
    }
}
