// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import Foundation
import PTimerCore

public enum ShootingCollectionCodec {
    private struct Payload: Encodable {
        let schemaVersion = 1
        let collections: [PersistentShootingCollection]
    }

    private struct Header: Decodable {
        let id: UUID
        let title: String
        let createdAt: Date
    }

    public static func encode(_ collections: [PersistentShootingCollection]) throws -> Data {
        try JSONEncoder().encode(Payload(collections: collections))
    }

    /// Isolation applies both to Collections and to their individual records.
    /// Duplicate event membership resolves first-valid-wins across the archive.
    public static func decode(_ data: Data) -> SnapshotDecodeResult<[PersistentShootingCollection]> {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return result([], .malformed, 0)
        }
        if let version = root["schemaVersion"], (version as? Int) != 1 {
            return result([], .versionRejected, 0)
        }
        guard let rawCollections = root["collections"] as? [Any] else {
            return result([], .malformed, 0)
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
        return result(collections, dropped == 0 ? .loaded : .degraded, dropped)
    }

    private static func result(
        _ collections: [PersistentShootingCollection], _ outcome: PersistenceLoadOutcome, _ dropped: Int
    ) -> SnapshotDecodeResult<[PersistentShootingCollection]> {
        SnapshotDecodeResult(snapshot: collections, outcome: outcome, droppedRecordCount: dropped)
    }
}
