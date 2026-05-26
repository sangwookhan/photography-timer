import Foundation

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
struct PersistentCustomFilmLibrarySnapshot: Codable, Equatable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let films: [FilmIdentity]

    init(
        schemaVersion: Int = currentSchemaVersion,
        films: [FilmIdentity]
    ) {
        self.schemaVersion = schemaVersion
        self.films = films
    }
}

/// Persistence-facing API the runtime `CustomFilmLibrary` consumes.
/// Real / no-op implementations follow the `*Storing` / `NoOp*` pair
/// convention documented in CLAUDE.md.
protocol CustomFilmLibraryStoring {
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
struct NoOpCustomFilmLibraryStore: CustomFilmLibraryStoring {
    func loadSnapshot() -> PersistentCustomFilmLibrarySnapshot? { nil }
    func saveSnapshot(_ snapshot: PersistentCustomFilmLibrarySnapshot) {}
    func clearSnapshot() {}
}

/// Production store. Encodes the snapshot to JSON and writes it
/// under a dedicated UserDefaults key, kept separate from the
/// preset catalog and camera-slot session keys so the custom
/// library can be cleared (or migrated) independently.
struct UserDefaultsCustomFilmLibraryStore: CustomFilmLibraryStoring {
    private let userDefaults: UserDefaults
    private let snapshotKey: String
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(
        userDefaults: UserDefaults = .standard,
        snapshotKey: String = "ptimer.exposure-calculator.custom-films.snapshot"
    ) {
        self.userDefaults = userDefaults
        self.snapshotKey = snapshotKey
    }

    func loadSnapshot() -> PersistentCustomFilmLibrarySnapshot? {
        guard let data = userDefaults.data(forKey: snapshotKey) else {
            return nil
        }
        // `try?` swallows decode errors so a malformed payload
        // (manual UserDefaults edit, an in-development schema that
        // never shipped, etc.) does not crash launch — the library
        // restores to an empty list and any subsequent save
        // overwrites the bad blob.
        return try? decoder.decode(PersistentCustomFilmLibrarySnapshot.self, from: data)
    }

    func saveSnapshot(_ snapshot: PersistentCustomFilmLibrarySnapshot) {
        guard let data = try? encoder.encode(snapshot) else {
            return
        }
        userDefaults.set(data, forKey: snapshotKey)
    }

    func clearSnapshot() {
        userDefaults.removeObject(forKey: snapshotKey)
    }
}
