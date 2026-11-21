// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Save commits the entire archive atomically or throws without changing it.
/// A read failure must not be mistaken for a fresh installation.
public protocol ShootingCollectionStoring {
    func load() throws -> PersistentShootingArchive
    func save(_ archive: PersistentShootingArchive) throws
}

public struct NoOpShootingCollectionStore: ShootingCollectionStoring {
    public init() {}
    public func load() throws -> PersistentShootingArchive { PersistentShootingArchive() }
    public func save(_ archive: PersistentShootingArchive) throws {}
}
