import Foundation

struct PersistentExposureCalculatorContextSnapshot: Codable, Equatable {
    let selectedPresetFilmID: String?
    let baseShutterSeconds: Double?
    let ndStop: Int?
}

protocol ExposureCalculatorContextPersistenceStoring {
    func loadSnapshot() -> PersistentExposureCalculatorContextSnapshot?
    func saveSnapshot(_ snapshot: PersistentExposureCalculatorContextSnapshot)
    func clearSnapshot()
}

struct NoOpExposureCalculatorContextPersistenceStore: ExposureCalculatorContextPersistenceStoring {
    func loadSnapshot() -> PersistentExposureCalculatorContextSnapshot? { nil }
    func saveSnapshot(_ snapshot: PersistentExposureCalculatorContextSnapshot) {}
    func clearSnapshot() {}
}

struct UserDefaultsExposureCalculatorContextPersistenceStore: ExposureCalculatorContextPersistenceStoring {
    private let userDefaults: UserDefaults
    private let snapshotKey: String
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(
        userDefaults: UserDefaults = .standard,
        snapshotKey: String = "ptimer.exposure-calculator.context.snapshot"
    ) {
        self.userDefaults = userDefaults
        self.snapshotKey = snapshotKey
    }

    func loadSnapshot() -> PersistentExposureCalculatorContextSnapshot? {
        guard let data = userDefaults.data(forKey: snapshotKey) else {
            return nil
        }

        return try? decoder.decode(PersistentExposureCalculatorContextSnapshot.self, from: data)
    }

    func saveSnapshot(_ snapshot: PersistentExposureCalculatorContextSnapshot) {
        guard let data = try? encoder.encode(snapshot) else {
            return
        }

        userDefaults.set(data, forKey: snapshotKey)
    }

    func clearSnapshot() {
        userDefaults.removeObject(forKey: snapshotKey)
    }
}
