import Foundation
import PTimerCore
import PTimerKit

public struct UserDefaultsCalculatorContextStore: ExposureCalculatorContextStoring {
    private let userDefaults: UserDefaults
    private let snapshotKey: String
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(
        userDefaults: UserDefaults = .standard,
        snapshotKey: String = "ptimer.exposure-calculator.context.snapshot"
    ) {
        self.userDefaults = userDefaults
        self.snapshotKey = snapshotKey
    }

    public func loadSnapshot() -> PersistentCalculatorContextSnapshot? {
        guard let data = userDefaults.data(forKey: snapshotKey) else {
            return nil
        }

        return try? decoder.decode(PersistentCalculatorContextSnapshot.self, from: data)
    }

    public func saveSnapshot(_ snapshot: PersistentCalculatorContextSnapshot) {
        guard let data = try? encoder.encode(snapshot) else {
            return
        }

        userDefaults.set(data, forKey: snapshotKey)
    }

    public func clearSnapshot() {
        userDefaults.removeObject(forKey: snapshotKey)
    }
}
