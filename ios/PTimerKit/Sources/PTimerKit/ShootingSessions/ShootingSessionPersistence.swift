// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import Foundation
import PTimerCore

public struct ShootingSessionMembership: Codable, Equatable {
    public let timerID: UUID
    public let sessionID: UUID
    public let firstStart: Date
    public let startedAt: Date

    public init(timerID: UUID, sessionID: UUID, firstStart: Date, startedAt: Date) {
        self.timerID = timerID
        self.sessionID = sessionID
        self.firstStart = firstStart
        self.startedAt = startedAt
    }
}

public struct PersistentShootingSessions: Codable, Equatable {
    public var memberships: [ShootingSessionMembership]
    /// Retained after deletion so removing the latest record cannot rewind activity.
    public var latest: ShootingSessionMembership?

    public init(memberships: [ShootingSessionMembership] = [], latest: ShootingSessionMembership? = nil) {
        self.memberships = memberships
        self.latest = latest
    }

    public static func decode(from data: Data) -> SnapshotDecodeResult<Self> {
        let result = VersionedCollectionDecoder.decodeRecords(
            ShootingSessionMembership.self, from: data, recordsKey: "memberships",
            expectedSchemaVersion: 1, idOf: { AnyHashable($0.timerID) }
        )
        let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        let latest = root?["latest"].flatMap { try? JSONSerialization.data(withJSONObject: $0) }
            .flatMap { try? JSONDecoder().decode(ShootingSessionMembership.self, from: $0) }
        return .init(
            snapshot: .init(memberships: result.records, latest: latest ?? result.records.last),
            outcome: result.outcome, droppedRecordCount: result.droppedRecordCount
        )
    }
}

public enum ShootingSessionLoadResult {
    case loaded(PersistentShootingSessions)
    case failed
}

public protocol ShootingSessionStoring {
    func loadSessions() -> ShootingSessionLoadResult
    func saveSessions(_ snapshot: PersistentShootingSessions) -> Bool
}

public struct NoOpShootingSessionStore: ShootingSessionStoring {
    public init() {}
    public func loadSessions() -> ShootingSessionLoadResult { .loaded(.init()) }
    public func saveSessions(_ snapshot: PersistentShootingSessions) -> Bool { true }
}
