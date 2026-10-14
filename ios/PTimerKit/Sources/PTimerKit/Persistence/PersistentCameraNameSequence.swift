// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Outcome of reading the sequence store.
public enum CameraNameSequenceLoadResult: Equatable {
    /// No sequence has been stored.
    case absent
    /// The next automatic number.
    case value(Int)
    /// A value exists but cannot be used. The allocator treats it like
    /// a missing value (CAMERA-PERSIST-007).
    case unusable
}

/// Storage for the automatic camera-name sequence: the number the next
/// automatic `Camera N` name will use. It is independent of the managed
/// camera list and is never reconstructed from cameras, names, order,
/// count, identities, or timer records (CAMERA-NAME-004).
public protocol CameraNameSequenceStoring {
    func load() -> CameraNameSequenceLoadResult
    /// Stores the next automatic number. Returns whether the write
    /// succeeded.
    @discardableResult
    func save(nextNumber: Int) -> Bool
}

/// In-memory sequence store: the default when no persistent store is
/// injected, and the test double (it can simulate corruption and write
/// failures).
public final class InMemoryCameraNameSequenceStore: CameraNameSequenceStoring {
    public var result: CameraNameSequenceLoadResult
    public var failsWrites = false
    public private(set) var saveCount = 0

    public init(_ result: CameraNameSequenceLoadResult = .absent) {
        self.result = result
    }

    public func load() -> CameraNameSequenceLoadResult { result }

    @discardableResult
    public func save(nextNumber: Int) -> Bool {
        guard !failsWrites else { return false }
        saveCount += 1
        result = .value(nextNumber)
        return true
    }
}
