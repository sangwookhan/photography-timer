import Foundation
import PTimerCore
import PTimerKit

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
