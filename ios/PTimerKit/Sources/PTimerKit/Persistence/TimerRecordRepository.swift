// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import Foundation
import PTimerCore

/// One atomic archive for runtime state and its start metadata. Memberships
/// remain independently decodable: an assignment failure never removes a Timer.
/// File I/O is supplied by the app; tests inject retained/failed/uncertain writes.
public final class TimerRecordRepository {
    private struct Archive: Codable, Equatable {
        var schemaVersion = 1
        var timers: Data?
        var metadata: Data?
        var sessions: Data?

        init(timers: Data?, metadata: Data?, sessions: Data? = nil) {
            self.timers = timers
            self.metadata = metadata
            self.sessions = sessions
        }

        private enum CodingKeys: String, CodingKey { case schemaVersion, timers, metadata, sessions }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
            timers = Self.component(.timers, from: container)
            metadata = Self.component(.metadata, from: container)
            sessions = Self.component(.sessions, from: container)
        }

        private static func component(_ key: CodingKeys, from container: KeyedDecodingContainer<CodingKeys>) -> Data? {
            do { return try container.decodeIfPresent(Data.self, forKey: key) }
            catch { return Data([0xFF]) } // Preserve a failed component, never confuse it with absence.
        }
    }

    private let read: () throws -> Data?
    private let write: (Data) -> TimerSnapshotSaveResult
    private let quarantine: (Data) -> Void
    private var archive: Archive
    private var hasPersistedArchive = false
    private var quarantinedOnLoad = false
    private var available = true
    private var writeUncertain = false

    public init(
        read: @escaping () throws -> Data?,
        write: @escaping (Data) -> TimerSnapshotSaveResult,
        quarantine: @escaping (Data) -> Void = { _ in },
        legacyTimers: PersistentTimerCollectionSnapshot? = nil,
        legacyMetadata: PersistentTimerMetadataCollection? = nil
    ) {
        self.read = read
        self.write = write
        self.quarantine = quarantine
        archive = Archive(
            timers: legacyTimers.flatMap { $0.timers.isEmpty ? nil : try? Self.encode($0) },
            metadata: legacyMetadata.flatMap { $0.timers.isEmpty ? nil : try? Self.encode($0) }
        )
        do {
            if let data = try read() {
                guard let decoded = try? JSONDecoder().decode(Archive.self, from: data), decoded.schemaVersion == 1 else {
                    quarantine(data)
                    available = false
                    return
                }
                archive = decoded
                hasPersistedArchive = true
                let timerFailure = decoded.timers.map { PersistentTimerCollectionSnapshot.decode(from: $0).indicatesFailure } ?? false
                let metadataFailure = decoded.metadata.map { PersistentTimerMetadataCollection.decode(from: $0).indicatesFailure } ?? false
                let sessionFailure = decoded.sessions.map { PersistentShootingSessions.decode(from: $0).indicatesFailure } ?? false
                if timerFailure || metadataFailure || sessionFailure {
                    quarantine(data)
                    quarantinedOnLoad = true
                }
            }
        } catch {
            available = false
        }
    }

    private static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(value)
    }

    private func refreshAfterUncertainty() -> Bool {
        guard writeUncertain else { return available }
        do {
            guard let data = try read() else {
                writeUncertain = false
                hasPersistedArchive = false
                return true
            }
            guard let retained = try? JSONDecoder().decode(Archive.self, from: data),
                  retained.schemaVersion == 1 else { return false }
            archive = retained
            hasPersistedArchive = true
            writeUncertain = false
            return true
        } catch { return false }
    }

    private func save(_ update: (inout Archive) throws -> Void) -> TimerSnapshotSaveResult {
        guard available, refreshAfterUncertainty() else { return .uncertain }
        var candidate = archive
        do {
            try update(&candidate)
            if candidate == archive && hasPersistedArchive { return .saved }
            let encoded = try Self.encode(candidate)
            let outcome = write(encoded)
            if outcome == .saved {
                archive = candidate
                hasPersistedArchive = true
            } else if outcome == .uncertain {
                writeUncertain = true
                if refreshAfterUncertainty(), archive == candidate { return .saved }
                if !writeUncertain { return .failed }
            }
            return outcome
        } catch { return .failed }
    }

    public func loadTimers() -> PersistentTimerCollectionSnapshot? {
        guard available else { return nil }
        return archive.timers.map { PersistentTimerCollectionSnapshot.decode(from: $0).snapshot }
    }

    public func saveTimers(_ snapshot: PersistentTimerCollectionSnapshot) -> TimerSnapshotSaveResult {
        save { archive in
            archive.timers = snapshot.timers.isEmpty ? nil : try Self.encode(snapshot)
            if let data = archive.metadata {
                let metadata = PersistentTimerMetadataCollection.decode(from: data).snapshot
                let starts = Dictionary(snapshot.timers.map { ($0.id, $0.startDate) }, uniquingKeysWith: { first, _ in first })
                let entries = metadata.timers.map { stored in
                    var entry = stored
                    if let activity = entry.sessionActivity, let start = starts[entry.id] {
                        entry.sessionActivity = .init(startedAt: start, policy: activity.policy)
                    }
                    return entry
                }
                archive.metadata = entries.isEmpty ? nil : try Self.encode(
                    PersistentTimerMetadataCollection(nextTimerOrder: metadata.nextTimerOrder, timers: entries)
                )
            }
        }
    }

    public func verifyStart(id: UUID) -> TimerSnapshotSaveResult {
        guard available, refreshAfterUncertainty() else { return .uncertain }
        return loadTimers()?.timers.contains(where: { $0.id == id }) == true ? .saved : .failed
    }

    public func loadMetadata() -> PersistentTimerMetadataCollection? {
        guard available else { return nil }
        return archive.metadata.map { PersistentTimerMetadataCollection.decode(from: $0).snapshot }
    }

    public func saveMetadata(_ snapshot: PersistentTimerMetadataCollection) -> TimerSnapshotSaveResult {
        save { $0.metadata = snapshot.timers.isEmpty ? nil : try Self.encode(snapshot) }
    }

    public func loadSessions() -> ShootingSessionLoadResult {
        guard available, refreshAfterUncertainty() else { return .failed }
        guard let data = archive.sessions else { return .loaded(.init()) }
        let result = PersistentShootingSessions.decode(from: data)
        if result.indicatesFailure, !quarantinedOnLoad, let raw = try? Self.encode(archive) {
            quarantine(raw)
            quarantinedOnLoad = true
        }
        guard result.outcome == .loaded || result.outcome == .degraded else { return .failed }
        return .loaded(result.snapshot)
    }

    public func saveSessions(_ snapshot: PersistentShootingSessions) -> Bool {
        save { $0.sessions = try Self.encode(snapshot) } == .saved
    }
}

public struct TimerRecordRuntimeStore: TimerPersistenceStoring {
    private let repository: TimerRecordRepository
    public init(repository: TimerRecordRepository) { self.repository = repository }
    public func loadSnapshot() -> PersistentTimerCollectionSnapshot? { repository.loadTimers() }
    public func saveSnapshot(_ snapshot: PersistentTimerCollectionSnapshot) { _ = repository.saveTimers(snapshot) }
    public func clearSnapshot() { _ = repository.saveTimers(.init(snapshots: [])) }
    public func saveStartingSnapshot(_ snapshot: PersistentTimerCollectionSnapshot) -> TimerSnapshotSaveResult {
        repository.saveTimers(snapshot)
    }
    public func verifyRetainedStart(id: UUID) -> TimerSnapshotSaveResult { repository.verifyStart(id: id) }
}

public struct TimerRecordMetadataStore: TimerMetadataPersistenceStoring {
    private let repository: TimerRecordRepository
    public init(repository: TimerRecordRepository) { self.repository = repository }
    public func loadSnapshot() -> PersistentTimerMetadataCollection? { repository.loadMetadata() }
    public func saveSnapshot(_ snapshot: PersistentTimerMetadataCollection) { _ = repository.saveMetadata(snapshot) }
    public func clearSnapshot() { _ = repository.saveMetadata(.init(nextTimerOrder: 1, timers: [])) }
    public func savePreparingSnapshot(_ snapshot: PersistentTimerMetadataCollection) -> TimerSnapshotSaveResult {
        repository.saveMetadata(snapshot)
    }
}

extension TimerRecordRepository: ShootingSessionStoring {}
