// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Outcome of decoding a versioned, record-collection persistence payload.
/// Distinguishes the states that a bare `nil` used to collapse together, so
/// the store can decide whether to quarantine the raw payload and what signal
/// to surface (PTIMER-215).
public enum PersistenceLoadOutcome: String, Equatable, Sendable {
    /// Root object parsed, version accepted, every record decoded.
    case loaded
    /// Root + version accepted, but one or more records were dropped (an
    /// undecodable record — e.g. an unknown enum value or rule kind — or a
    /// duplicate id). The surviving records are returned.
    case degraded
    /// A `schemaVersion` field was present and did not equal the expected
    /// version (a payload written by a newer or older incompatible format).
    /// No records are returned.
    case versionRejected
    /// The payload is not a JSON object, or its records field is present but
    /// not an array. No records are returned.
    case malformed

    /// Whether the raw payload should be quarantined and a signal surfaced.
    public var indicatesFailure: Bool { self != .loaded }
}

/// A decoded snapshot paired with the diagnostics a store needs to quarantine
/// and signal (PTIMER-215). `snapshot` is always usable — degraded or empty on
/// failure, never `nil` — so the runtime restores what survived.
public struct SnapshotDecodeResult<Snapshot> {
    public let snapshot: Snapshot
    public let outcome: PersistenceLoadOutcome
    public let droppedRecordCount: Int

    public init(snapshot: Snapshot, outcome: PersistenceLoadOutcome, droppedRecordCount: Int) {
        self.snapshot = snapshot
        self.outcome = outcome
        self.droppedRecordCount = droppedRecordCount
    }

    public var indicatesFailure: Bool { outcome.indicatesFailure }
}

/// Records decoded from a collection payload, with the diagnostics needed to
/// drive quarantine and signalling.
public struct PerRecordDecodeResult<Record> {
    public let records: [Record]
    public let droppedRecordCount: Int
    public let outcome: PersistenceLoadOutcome

    public init(records: [Record], droppedRecordCount: Int, outcome: PersistenceLoadOutcome) {
        self.records = records
        self.droppedRecordCount = droppedRecordCount
        self.outcome = outcome
    }
}

/// Per-record decoder for versioned collection payloads. Mirrors the isolation
/// the Android workspace codec already had: a payload written by a newer schema
/// degrades only the affected record instead of wiping the whole collection.
///
/// Contract:
/// - The root must be a JSON object; otherwise `.malformed` with no records.
/// - `versionKey`, when present, must equal `expectedSchemaVersion`; otherwise
///   `.versionRejected` with no records. A missing version is accepted as the
///   legacy `expectedSchemaVersion` (matching the Android workspace codec).
/// - Each element of the `recordsKey` array is decoded independently; an
///   element that fails to decode is dropped and counted. Duplicate ids are
///   de-duplicated first-valid-wins (matching the Android workspace codec).
/// - The `recordsKey` array must be present: the encoders always write it,
///   even for an empty collection, so an absent key means a truncated or
///   otherwise corrupt payload and is `.malformed` (a truly empty store is
///   the absence of the payload itself, handled before decode). A present
///   `recordsKey` that is not an array is likewise `.malformed`. Only an
///   explicit empty array is a legitimately empty collection (`.loaded`).
public enum VersionedCollectionDecoder {
    public static func decodeRecords<Record: Decodable>(
        _ type: Record.Type = Record.self,
        from data: Data,
        recordsKey: String,
        expectedSchemaVersion: Int,
        versionKey: String = "schemaVersion",
        decoder: JSONDecoder = JSONDecoder(),
        idOf: (Record) -> AnyHashable
    ) -> PerRecordDecodeResult<Record> {
        guard let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return PerRecordDecodeResult(records: [], droppedRecordCount: 0, outcome: .malformed)
        }

        if let rawVersion = root[versionKey] {
            guard let version = rawVersion as? Int, version == expectedSchemaVersion else {
                return PerRecordDecodeResult(records: [], droppedRecordCount: 0, outcome: .versionRejected)
            }
        }

        guard let rawRecords = root[recordsKey], let elements = rawRecords as? [Any] else {
            // The encoders always write the records array (empty when there
            // are no records), so an absent or non-array key is corruption,
            // not an empty collection.
            return PerRecordDecodeResult(records: [], droppedRecordCount: 0, outcome: .malformed)
        }

        var seen = Set<AnyHashable>()
        var records: [Record] = []
        var dropped = 0
        for element in elements {
            guard JSONSerialization.isValidJSONObject(element),
                  let elementData = try? JSONSerialization.data(withJSONObject: element),
                  let record = try? decoder.decode(Record.self, from: elementData) else {
                dropped += 1
                continue
            }
            if seen.insert(idOf(record)).inserted {
                records.append(record)
            } else {
                // Duplicate id — first valid wins.
                dropped += 1
            }
        }

        return PerRecordDecodeResult(
            records: records,
            droppedRecordCount: dropped,
            outcome: dropped > 0 ? .degraded : .loaded
        )
    }
}
