// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import Foundation

public struct ShootingRecordDisplayState {
    public struct Field: Identifiable {
        public let label: String
        public let value: String
        public var id: String { label }
    }
    public let title: String
    public let subtitle: String
    public let fields: [Field]
}
