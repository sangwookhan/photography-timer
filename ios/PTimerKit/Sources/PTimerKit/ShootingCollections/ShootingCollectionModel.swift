// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import Combine
import Foundation

public enum ShootingCollectionError: Error, Equatable {
    case unavailable, invalidSelection, alreadyCollected, saveFailed
}

@MainActor
public final class ShootingCollectionModel: ObservableObject {
    @Published public private(set) var collections: [PersistentShootingCollection] = []
    public private(set) var isAvailable = true
    private let store: ShootingCollectionStoring

    public init(store: ShootingCollectionStoring) {
        self.store = store
        do {
            collections = try store.load().sorted(by: Self.newestFirst)
        } catch {
            isAvailable = false
        }
    }

    public func collection(containing eventID: UUID) -> PersistentShootingCollection? {
        collections.first { $0.records.contains { $0.id == eventID } }
    }

    public func create(
        from timers: [RunningTimerItem], at now: Date, timeZone: TimeZone,
        id: UUID = UUID()
    ) -> Result<UUID, ShootingCollectionError> {
        guard isAvailable else { return .failure(.unavailable) }
        let records = timers.compactMap(PersistentShootingRecord.init(timer:))
        guard !records.isEmpty, records.count == timers.count,
              Set(records.map(\.id)).count == records.count,
              !collections.contains(where: { $0.id == id }) else { return .failure(.invalidSelection) }
        guard records.allSatisfy({ collection(containing: $0.id) == nil }) else {
            return .failure(.alreadyCollected)
        }
        let ordered = records.sorted {
            $0.startDate == $1.startDate ? $0.id.uuidString < $1.id.uuidString : $0.startDate < $1.startDate
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        let collection = PersistentShootingCollection(
            id: id, title: formatter.string(from: ordered[0].startDate), createdAt: now, records: ordered
        )
        let next = (collections + [collection]).sorted(by: Self.newestFirst)
        do {
            try store.save(next)
            collections = next
            return .success(id)
        } catch {
            return .failure(.saveFailed)
        }
    }

    private static func newestFirst(_ lhs: PersistentShootingCollection, _ rhs: PersistentShootingCollection) -> Bool {
        lhs.createdAt == rhs.createdAt ? lhs.id.uuidString < rhs.id.uuidString : lhs.createdAt > rhs.createdAt
    }
}
