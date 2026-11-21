// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import Foundation
import PTimerCore

public enum ShootingCollectionCodec {
    private struct Payload: Encodable {
        let schemaVersion = 2
        let collections: [PersistentShootingCollection]
        let uncollectedRecords: [PersistentShootingRecord]
    }

    private struct Header: Decodable {
        let id: UUID
        let title: String
        let createdAt: Date
    }

    public static func encode(_ archive: PersistentShootingArchive) throws -> Data {
        try JSONEncoder().encode(Payload(
            collections: archive.collections, uncollectedRecords: archive.uncollectedRecords
        ))
    }

    /// Isolation applies both to Collections and to their individual records.
    /// Duplicate event membership resolves first-valid-wins across the archive.
    public static func decode(_ data: Data) -> SnapshotDecodeResult<PersistentShootingArchive> {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return result(PersistentShootingArchive(), .malformed, 0)
        }
        let version = root["schemaVersion"] as? Int ?? 1
        if root["schemaVersion"] != nil && root["schemaVersion"] as? Int == nil || ![1, 2].contains(version) {
            return result(PersistentShootingArchive(), .versionRejected, 0)
        }
        // v1 (including the original unversioned shape) predates uncollected records.
        if version == 2 && !(root["uncollectedRecords"] is [Any]) {
            return result(PersistentShootingArchive(), .malformed, 0)
        }
        guard let rawCollections = root["collections"] as? [Any] else {
            return result(PersistentShootingArchive(), .malformed, 0)
        }
        var collections: [PersistentShootingCollection] = []
        var collectionIDs = Set<UUID>()
        var eventIDs = Set<UUID>()
        var dropped = 0
        for raw in rawCollections {
            guard JSONSerialization.isValidJSONObject(raw),
                  let bytes = try? JSONSerialization.data(withJSONObject: raw),
                  let header = try? JSONDecoder().decode(Header.self, from: bytes),
                  !collectionIDs.contains(header.id) else {
                dropped += 1
                continue
            }
            let decoded = VersionedCollectionDecoder.decodeRecords(
                PersistentShootingRecord.self, from: bytes, recordsKey: "records",
                expectedSchemaVersion: 1, idOf: { $0.id }
            )
            guard decoded.outcome == .loaded || decoded.outcome == .degraded else {
                dropped += 1
                continue
            }
            dropped += decoded.droppedRecordCount
            let records = decoded.records.filter { record in
                guard record.duration.isFinite, record.duration > 0,
                      eventIDs.insert(record.id).inserted else {
                    dropped += 1
                    return false
                }
                return true
            }
            collectionIDs.insert(header.id)
            collections.append(PersistentShootingCollection(
                id: header.id, title: header.title, createdAt: header.createdAt, records: records
            ))
        }
        var uncollected: [PersistentShootingRecord] = []
        if version == 2 {
            let decoded = VersionedCollectionDecoder.decodeRecords(
                PersistentShootingRecord.self, from: data, recordsKey: "uncollectedRecords",
                expectedSchemaVersion: 2, idOf: { $0.id }
            )
            dropped += decoded.droppedRecordCount
            uncollected = decoded.records.filter { record in
                guard record.duration.isFinite, record.duration > 0,
                      eventIDs.insert(record.id).inserted else {
                    dropped += 1
                    return false
                }
                return true
            }
        }
        return result(
            PersistentShootingArchive(collections: collections, uncollectedRecords: uncollected),
            dropped == 0 ? .loaded : .degraded, dropped
        )
    }

    private static func result(
        _ archive: PersistentShootingArchive, _ outcome: PersistenceLoadOutcome, _ dropped: Int
    ) -> SnapshotDecodeResult<PersistentShootingArchive> {
        SnapshotDecodeResult(snapshot: archive, outcome: outcome, droppedRecordCount: dropped)
    }
}
