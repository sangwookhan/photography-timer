// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import Foundation
import PTimerKit

/// A separate archive; removing a Timer workspace payload never touches it.
struct FileShootingCollectionStore: ShootingCollectionStoring {
    let url: URL

    init(url: URL = URL.applicationSupportDirectory
        .appending(path: "ShootingCollections/archive.json")) {
        self.url = url
    }

    func load() throws -> [PersistentShootingCollection] {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return []
        }
        let decoded = ShootingCollectionCodec.decode(data)
        if decoded.indicatesFailure {
            // Preserve the original before a later successful save can replace it.
            try data.write(to: url.appendingPathExtension("quarantine"), options: .atomic)
        }
        guard decoded.outcome == .loaded || decoded.outcome == .degraded else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return decoded.snapshot
    }

    func save(_ collections: [PersistentShootingCollection]) throws {
        let data = try ShootingCollectionCodec.encode(collections)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try data.write(to: url, options: .atomic)
    }
}
