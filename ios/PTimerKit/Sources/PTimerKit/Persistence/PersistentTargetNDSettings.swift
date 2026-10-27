// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import Foundation
import PTimerCore

/// Dedicated global selection-policy settings. Existing calculator, camera,
/// timer and display-only snapshots keep their schemas and meanings.
public struct PersistentTargetNDSettings: Codable, Equatable {
    public let isEnabled: Bool?
    public let negativeRaw: String?
    public let positiveRaw: String?
    public let digitalRaw: String?

    public init(_ settings: TargetNDSettings) {
        isEnabled = settings.isEnabled
        negativeRaw = settings.negative.rawValue
        positiveRaw = settings.positive.rawValue
        digitalRaw = settings.digital.rawValue
    }

    public var restored: TargetNDSettings {
        var settings = TargetNDSettings()
        settings.isEnabled = isEnabled ?? true
        settings.negative = negativeRaw.flatMap(TargetNDAllowance.init(rawValue:)) ?? .standard
        settings.positive = positiveRaw.flatMap(TargetNDAllowance.init(rawValue:)) ?? .standard
        settings.digital = digitalRaw.flatMap(TargetNDAllowance.init(rawValue:)) ?? .standard
        return settings
    }
}

public protocol TargetNDSettingsStoring {
    func loadSettings() -> PersistentTargetNDSettings?
    func saveSettings(_ settings: PersistentTargetNDSettings)
}

public struct NoOpTargetNDSettingsStore: TargetNDSettingsStoring {
    public init() {}
    public func loadSettings() -> PersistentTargetNDSettings? { nil }
    public func saveSettings(_ settings: PersistentTargetNDSettings) {}
}
