// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import Combine
import Foundation

@MainActor
public final class TargetNDSettingsModel: ObservableObject {
    @Published public var settings: TargetNDSettings {
        didSet {
            guard settings != oldValue else { return }
            store.saveSettings(PersistentTargetNDSettings(settings))
        }
    }
    private let store: TargetNDSettingsStoring

    public init(store: TargetNDSettingsStoring = NoOpTargetNDSettingsStore()) {
        self.store = store
        settings = store.loadSettings()?.restored ?? TargetNDSettings()
    }
}
