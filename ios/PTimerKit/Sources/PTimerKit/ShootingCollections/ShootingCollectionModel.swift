// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import Combine
import Foundation

public enum ShootingCollectionError: Error, Equatable {
    case unavailable, invalidSelection, alreadyCollected, saveFailed
}

@MainActor
public final class ShootingCollectionModel: ObservableObject {
    @Published private var archive = PersistentShootingArchive()
    public private(set) var isAvailable = true
    private let store: ShootingCollectionStoring

    public var collections: [PersistentShootingCollection] { archive.collections }
    public var uncollectedRecords: [PersistentShootingRecord] { archive.uncollectedRecords }

    public init(store: ShootingCollectionStoring) {
        self.store = store
        do {
            archive = Self.ordered(try store.load())
        } catch {
            isAvailable = false
        }
    }

    public func collection(containing eventID: UUID) -> PersistentShootingCollection? {
        collections.first { $0.records.contains { $0.id == eventID } }
    }

    public func records(in collectionID: UUID?) -> [PersistentShootingRecord] {
        guard let collectionID else { return uncollectedRecords }
        return collections.first { $0.id == collectionID }?.records ?? []
    }

    public func record(id: UUID) -> PersistentShootingRecord? {
        collection(containing: id)?.records.first { $0.id == id }
            ?? uncollectedRecords.first { $0.id == id }
    }

    public var collectedEventIDs: Set<UUID> {
        Set(collections.flatMap { $0.records.map(\.id) })
    }

    public func create(
        from timers: [RunningTimerItem], at now: Date, timeZone: TimeZone,
        id: UUID = UUID()
    ) -> Result<UUID, ShootingCollectionError> {
        guard isAvailable else { return .failure(.unavailable) }
        let captured = timers.compactMap(PersistentShootingRecord.init(timer:))
        guard !captured.isEmpty, captured.count == timers.count,
              Set(captured.map(\.id)).count == captured.count,
              !collections.contains(where: { $0.id == id }) else { return .failure(.invalidSelection) }
        guard captured.allSatisfy({ collection(containing: $0.id) == nil }) else {
            return .failure(.alreadyCollected)
        }
        // Recollect the original capture, even if History's current display differs.
        let records = captured.map { timerRecord in
            uncollectedRecords.first { $0.id == timerRecord.id } ?? timerRecord
        }.sorted(by: Self.earliestFirst)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        let collection = PersistentShootingCollection(
            id: id, title: formatter.string(from: records[0].startDate), createdAt: now, records: records
        )
        let ids = Set(records.map(\.id))
        return commit(PersistentShootingArchive(
            collections: collections + [collection],
            uncollectedRecords: uncollectedRecords.filter { !ids.contains($0.id) }
        )).map { id }
    }

    public func remove(
        recordIDs: Set<UUID>, from collectionID: UUID
    ) -> Result<Void, ShootingCollectionError> {
        guard isAvailable else { return .failure(.unavailable) }
        let source = records(in: collectionID)
        guard !recordIDs.isEmpty, recordIDs.isSubset(of: Set(source.map(\.id))) else {
            return .failure(.invalidSelection)
        }
        let next = collections.map { collection in
            collection.id == collectionID
                ? Self.replacingRecords(of: collection, with: source.filter { !recordIDs.contains($0.id) })
                : collection
        }
        return commit(PersistentShootingArchive(
            collections: next,
            uncollectedRecords: uncollectedRecords + source.filter { recordIDs.contains($0.id) }
        ))
    }

    public func move(
        recordIDs: Set<UUID>, from sourceID: UUID?, to destinationID: UUID
    ) -> Result<Void, ShootingCollectionError> {
        guard isAvailable else { return .failure(.unavailable) }
        let source = records(in: sourceID)
        guard !recordIDs.isEmpty, sourceID != destinationID,
              collections.contains(where: { $0.id == destinationID }),
              recordIDs.isSubset(of: Set(source.map(\.id))) else { return .failure(.invalidSelection) }
        let moving = source.filter { recordIDs.contains($0.id) }
        let next = collections.map { collection in
            if collection.id == sourceID {
                return Self.replacingRecords(of: collection, with: source.filter { !recordIDs.contains($0.id) })
            }
            if collection.id == destinationID {
                return Self.replacingRecords(of: collection, with: collection.records + moving)
            }
            return collection
        }
        return commit(PersistentShootingArchive(
            collections: next,
            uncollectedRecords: sourceID == nil
                ? uncollectedRecords.filter { !recordIDs.contains($0.id) } : uncollectedRecords
        ))
    }

    private func commit(_ next: PersistentShootingArchive) -> Result<Void, ShootingCollectionError> {
        do {
            let ordered = Self.ordered(next)
            try store.save(ordered)
            archive = ordered
            return .success(())
        } catch {
            return .failure(.saveFailed)
        }
    }

    private static func replacingRecords(
        of collection: PersistentShootingCollection, with records: [PersistentShootingRecord]
    ) -> PersistentShootingCollection {
        PersistentShootingCollection(
            id: collection.id, title: collection.title, createdAt: collection.createdAt,
            records: records.sorted(by: earliestFirst)
        )
    }

    private static func ordered(_ archive: PersistentShootingArchive) -> PersistentShootingArchive {
        PersistentShootingArchive(
            collections: archive.collections.map { replacingRecords(of: $0, with: $0.records) }.sorted {
                $0.createdAt == $1.createdAt ? $0.id.uuidString < $1.id.uuidString : $0.createdAt > $1.createdAt
            },
            uncollectedRecords: archive.uncollectedRecords.sorted(by: earliestFirst)
        )
    }

    private static func earliestFirst(_ lhs: PersistentShootingRecord, _ rhs: PersistentShootingRecord) -> Bool {
        lhs.startDate == rhs.startDate ? lhs.id.uuidString < rhs.id.uuidString : lhs.startDate < rhs.startDate
    }
}
