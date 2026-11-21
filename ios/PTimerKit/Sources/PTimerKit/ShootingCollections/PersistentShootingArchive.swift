// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// One atomic snapshot owns both collected and independently preserved records.
public struct PersistentShootingArchive: Equatable {
    public let collections: [PersistentShootingCollection]
    public let uncollectedRecords: [PersistentShootingRecord]

    public init(
        collections: [PersistentShootingCollection] = [],
        uncollectedRecords: [PersistentShootingRecord] = []
    ) {
        self.collections = collections
        self.uncollectedRecords = uncollectedRecords
    }
}
