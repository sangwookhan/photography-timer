// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import Foundation
import PTimerCore

/// App-global, display-only preferences that are not tied to a camera
/// slot or a calculator context. Persisted under its own key so it
/// stays independent of the per-context calculator snapshot.
///
/// Holds ND notation and the read-only required-ND preference. The raw value is stored
/// as an optional string with a `.stops` fallback so an absent field
/// or an unknown future case decodes to the shipping default rather
/// than failing.
public struct PersistentDisplaySettings: Codable, Equatable {
    public let ndNotationModeRaw: String?
    public let showRequiredND: Bool?

    public init(ndNotationMode: NDNotationMode, showRequiredND: Bool = true) {
        self.ndNotationModeRaw = ndNotationMode.rawValue
        self.showRequiredND = showRequiredND
    }

    public var restoredShowRequiredND: Bool { showRequiredND ?? true }

    public var restoredNDNotationMode: NDNotationMode {
        guard let raw = ndNotationModeRaw,
              let mode = NDNotationMode(rawValue: raw) else {
            return .stops
        }
        return mode
    }
}

public protocol DisplaySettingStoring {
    func loadSettings() -> PersistentDisplaySettings?
    func saveSettings(_ settings: PersistentDisplaySettings)
    func clearSettings()
}

public struct NoOpDisplaySettingStore: DisplaySettingStoring {
    public init() {}
    public func loadSettings() -> PersistentDisplaySettings? { nil }
    public func saveSettings(_ settings: PersistentDisplaySettings) {}
    public func clearSettings() {}
}
