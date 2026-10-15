// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// On-disk shape of the managed camera list: the global order, each
/// camera's name, pager inclusion, and calculator state, the active
/// camera (absent when no camera is displayed), and every identity
/// ever issued so a deleted camera's identity is never reused.
///
/// Stored under its own key, separate from the pre-managed-list
/// camera-slot session snapshot, which stays untouched as the legacy
/// migration source (CAMERA-PERSIST-006).
public struct PersistentManagedCameraListSnapshot: Codable, Equatable {
    public let schemaVersion: Int
    /// Raw identities ever issued, deleted cameras included.
    public let issuedIDRaws: [String]
    /// Raw identity of the active camera; `nil` is the explicit
    /// "no active camera" state.
    public let activeCameraIDRaw: String?
    public let cameras: [PersistentManagedCamera]

    public static let currentSchemaVersion: Int = 1

    public init(
        schemaVersion: Int = PersistentManagedCameraListSnapshot.currentSchemaVersion,
        issuedIDRaws: [String],
        activeCameraIDRaw: String?,
        cameras: [PersistentManagedCamera]
    ) {
        self.schemaVersion = schemaVersion
        self.issuedIDRaws = issuedIDRaws
        self.activeCameraIDRaw = activeCameraIDRaw
        self.cameras = cameras
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, issuedIDRaws, activeCameraIDRaw, cameras
    }

    /// The version and the camera collection must decode, otherwise the
    /// whole payload is undecodable (CAMERA-PERSIST-004). Cameras then
    /// decode one by one: a value that is not a keyed camera record is
    /// skipped, and a record with missing fields takes the documented
    /// defaults. `isNormalized` is set when any default, skip, or
    /// replacement happened, so the load layer knows to persist the
    /// normalized list.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        let issued = try? container.decode([String].self, forKey: .issuedIDRaws)
        issuedIDRaws = issued ?? []
        let active = try? container.decodeIfPresent(String.self, forKey: .activeCameraIDRaw)
        activeCameraIDRaw = active
        let elements = try container.decode([LossyElement<PersistentManagedCamera>].self, forKey: .cameras)
        cameras = elements.compactMap(\.value)
        isNormalized = issued == nil
            || cameras.count != elements.count
            || cameras.contains { $0.isNormalized }
    }

    /// Whether decoding applied any default or skipped any value.
    public private(set) var isNormalized: Bool = false

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(issuedIDRaws, forKey: .issuedIDRaws)
        try container.encode(activeCameraIDRaw, forKey: .activeCameraIDRaw)
        try container.encode(cameras, forKey: .cameras)
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.schemaVersion == rhs.schemaVersion
            && lhs.issuedIDRaws == rhs.issuedIDRaws
            && lhs.activeCameraIDRaw == rhs.activeCameraIDRaw
            && lhs.cameras == rhs.cameras
    }
}

/// One persisted managed camera.
public struct PersistentManagedCamera: Codable, Equatable {
    public let idRaw: String
    public let name: String
    public let isDisplayed: Bool
    /// Calculator state. Absent or undecodable restores as fresh
    /// calculator defaults (CAMERA-PERSIST-005).
    public let calculator: PersistentCameraSlotCalculatorSnapshot?
    /// Whether decoding replaced a missing or unreadable field with
    /// its default. Not part of the stored shape or of equality.
    public let isNormalized: Bool

    public init(
        idRaw: String,
        name: String,
        isDisplayed: Bool,
        calculator: PersistentCameraSlotCalculatorSnapshot?
    ) {
        self.idRaw = idRaw
        self.name = name
        self.isDisplayed = isDisplayed
        self.calculator = calculator
        self.isNormalized = false
    }

    private enum CodingKeys: String, CodingKey {
        case idRaw, name, isDisplayed, calculator
    }

    /// A keyed record with missing or unreadable fields takes the
    /// documented defaults (CAMERA-PERSIST-004): a new opaque identity,
    /// the localized `Camera` name, shown, and fresh calculator state.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let storedID = try? container.decodeIfPresent(String.self, forKey: .idRaw)
        let storedName = try? container.decodeIfPresent(String.self, forKey: .name)
        let storedDisplayed = try? container.decodeIfPresent(Bool.self, forKey: .isDisplayed)
        let storedCalculator = try? container.decodeIfPresent(
            PersistentCameraSlotCalculatorSnapshot.self,
            forKey: .calculator
        )
        idRaw = storedID ?? CameraSlotID.generate().rawValue
        name = storedName ?? String(localized: "Camera")
        isDisplayed = storedDisplayed ?? true
        calculator = storedCalculator
        isNormalized = storedID == nil || storedName == nil || storedDisplayed == nil
            || (storedCalculator == nil && container.contains(.calculator))
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.idRaw == rhs.idRaw
            && lhs.name == rhs.name
            && lhs.isDisplayed == rhs.isDisplayed
            && lhs.calculator == rhs.calculator
    }
}

/// Decodes to `nil` instead of throwing, so one bad array element does
/// not fail the whole array.
private struct LossyElement<Value: Decodable>: Decodable {
    let value: Value?

    init(from decoder: Decoder) throws {
        value = try? Value(from: decoder)
    }
}

/// Outcome of loading the managed camera list.
public enum ManagedCameraListLoadResult: Equatable {
    /// No managed payload exists; legacy migration may run.
    case absent
    /// A readable managed payload.
    case loaded(PersistentManagedCameraListSnapshot)
    /// Content was read successfully but its version, camera collection,
    /// or whole payload cannot be decoded. It is atomically replaced
    /// with fresh camera state; legacy data is never used in its place.
    case undecodable
    /// The storage read itself failed and supplied no content. Nothing
    /// is deleted or written, and initialization retries on the next
    /// launch.
    case readFailed
}
