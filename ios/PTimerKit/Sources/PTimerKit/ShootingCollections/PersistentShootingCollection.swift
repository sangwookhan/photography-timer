// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import Foundation

public struct PersistentShootingCollection: Codable, Equatable, Identifiable {
    public let id: UUID
    public let title: String
    public let createdAt: Date
    public let records: [PersistentShootingRecord]

    public init(id: UUID, title: String, createdAt: Date, records: [PersistentShootingRecord]) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.records = records
    }
}
