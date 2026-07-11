// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import Foundation
import PTimerCore

/// On-disk schema for the custom film library. The
/// snapshot is intentionally a thin wrapper around `[FilmIdentity]`
/// (the same in-memory shape the library publishes) because every
/// custom entry is by construction `kind == .custom` with a single
/// `.userDefined`-authority profile — the same domain types preset
/// films use, so there's no translation step on either side.
///
/// `schemaVersion` lets a future structural change roll the persisted
/// payload forward without breaking older app builds, mirroring the
/// `PersistentCameraSlotSessionSnapshot` convention. Increment 1 ships
/// `currentSchemaVersion = 1`; any future format change bumps the
/// constant and adds a migration branch in the store's loader.
public struct PersistentCustomFilmLibrarySnapshot: Codable, Equatable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let films: [FilmIdentity]

    public init(
        schemaVersion: Int = currentSchemaVersion,
        films: [FilmIdentity]
    ) {
        self.schemaVersion = schemaVersion
        self.films = films
    }

    /// Decodes a persisted payload with per-record isolation (PTIMER-215).
    /// One film carrying an unknown enum value or rule kind is dropped; the
    /// rest of the library survives. A `schemaVersion` mismatch rejects the
    /// whole payload; a missing version is accepted as the legacy v1.
    /// Duplicate ids collapse first-valid-wins. The store uses the returned
    /// `outcome` to decide whether to quarantine the raw payload.
    public static func decode(from data: Data) -> SnapshotDecodeResult<PersistentCustomFilmLibrarySnapshot> {
        let result = VersionedCollectionDecoder.decodeRecords(
            FilmIdentity.self,
            from: data,
            recordsKey: "films",
            expectedSchemaVersion: currentSchemaVersion,
            idOf: { AnyHashable($0.id) }
        )
        return SnapshotDecodeResult(
            snapshot: PersistentCustomFilmLibrarySnapshot(films: result.records),
            outcome: result.outcome,
            droppedRecordCount: result.droppedRecordCount
        )
    }
}

/// Persistence-facing API the runtime `CustomFilmLibrary` consumes.
/// Real / no-op implementations follow the `*Storing` / `NoOp*` pair
/// convention documented in CLAUDE.md.
public protocol CustomFilmLibraryStoring {
    /// Loads the snapshot, or `nil` when none has been persisted
    /// yet (fresh install, or after an explicit `clearSnapshot`).
    /// Malformed payloads return `nil` rather than throwing so the
    /// library can fall back to an empty in-memory state on
    /// corruption without crashing the launch path.
    func loadSnapshot() -> PersistentCustomFilmLibrarySnapshot?
    func saveSnapshot(_ snapshot: PersistentCustomFilmLibrarySnapshot)
    func clearSnapshot()
}

/// Test double — same surface, no I/O. Tests that exercise the
/// library's in-memory invariants without persistence behavior
/// inject this directly.
public struct NoOpCustomFilmLibraryStore: CustomFilmLibraryStoring {
    public init() {}
    public func loadSnapshot() -> PersistentCustomFilmLibrarySnapshot? { nil }
    public func saveSnapshot(_ snapshot: PersistentCustomFilmLibrarySnapshot) {}
    public func clearSnapshot() {}
}
