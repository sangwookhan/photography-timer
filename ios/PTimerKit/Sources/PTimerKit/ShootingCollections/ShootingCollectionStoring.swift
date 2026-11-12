// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Save commits the entire archive atomically or throws without changing it.
/// A read failure must not be mistaken for a fresh installation.
public protocol ShootingCollectionStoring {
    func load() throws -> [PersistentShootingCollection]
    func save(_ collections: [PersistentShootingCollection]) throws
}

public struct NoOpShootingCollectionStore: ShootingCollectionStoring {
    public init() {}
    public func load() throws -> [PersistentShootingCollection] { [] }
    public func save(_ collections: [PersistentShootingCollection]) throws {}
}
