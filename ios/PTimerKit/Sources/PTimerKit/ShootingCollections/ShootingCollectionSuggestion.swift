// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// The exact candidates inspected in one preview; never an archive snapshot.
public struct ShootingCollectionSuggestion: Identifiable {
    public var id: UUID { anchor.id }
    public let anchor: RunningTimerItem
    public let candidates: [RunningTimerItem]
}
