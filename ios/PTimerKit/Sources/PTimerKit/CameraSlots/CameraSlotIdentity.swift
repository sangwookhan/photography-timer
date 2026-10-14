// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import Foundation
import PTimerCore

/// Stable identity for a managed camera. The identity never changes
/// for the life of a camera, is never reassigned to a different camera
/// after deletion, and persists into timer metadata so a timer can be
/// associated with the camera that started it.
///
/// The four identities that shipped with the fixed-slot product
/// (`camera1` ... `camera4`) are kept verbatim as the migrated
/// cameras' identities. Every other identity is generated and is not
/// derived from a list position or a display name.
public struct CameraSlotID: RawRepresentable, Codable, Equatable, Hashable, Identifiable {
    public let rawValue: String

    /// `nil` for an empty / whitespace-only raw value, which can never
    /// be a camera identity.
    public init?(rawValue: String) {
        guard !rawValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        self.rawValue = rawValue
    }

    private init(verbatim rawValue: String) {
        self.rawValue = rawValue
    }

    public var id: CameraSlotID { self }

    public static let camera1 = CameraSlotID(verbatim: "camera1")
    public static let camera2 = CameraSlotID(verbatim: "camera2")
    public static let camera3 = CameraSlotID(verbatim: "camera3")
    public static let camera4 = CameraSlotID(verbatim: "camera4")

    /// The identities of the pre-managed-list product, in their
    /// original order. Migration and fresh-install seeding use them.
    public static let legacyOrdered: [CameraSlotID] = [.camera1, .camera2, .camera3, .camera4]

    /// Localized `Camera N` label for a legacy identity (`nil` for any
    /// other identity). Used to freeze migrated names and to render
    /// pre-managed-list timer records that never captured a name.
    public var legacyDefaultName: String? {
        guard let index = Self.legacyOrdered.firstIndex(of: self) else { return nil }
        return CameraNaming.defaultName(number: index + 1)
    }

    /// A new, collision-free identity. UUID-based so it is never
    /// derived from a position or a name and cannot collide with a
    /// legacy `cameraN` raw value.
    public static func generate() -> CameraSlotID {
        CameraSlotID(verbatim: "camera-\(UUID().uuidString.lowercased())")
    }

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        guard let id = CameraSlotID(rawValue: raw) else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "Empty camera id")
            )
        }
        self = id
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// View-facing pair of stable id + display name. Timer metadata
/// captures it at timer start, so a later rename, hide, reorder, or
/// delete of the camera never changes what an existing timer shows.
public struct CameraSlotIdentity: Equatable, Hashable, Codable {
    public let id: CameraSlotID
    /// The camera's stored name (trimmed, non-empty).
    public let displayName: String

    public init(id: CameraSlotID, displayName: String) {
        self.id = id
        self.displayName = displayName
    }

    /// Identity named by the legacy `Camera N` label (or the raw
    /// identity for any other camera).
    public init(id: CameraSlotID) {
        self.init(id: id, displayName: id.legacyDefaultName ?? id.rawValue)
    }

    /// Restores a captured identity from persisted timer metadata,
    /// where the stored name may be absent (older snapshots). A
    /// missing name falls back to the legacy `Camera N` label, or to
    /// the raw identity, so the entry stays renderable without
    /// consulting the camera list.
    public init(id: CameraSlotID, displayName: String?) {
        let trimmed = displayName?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.id = id
        self.displayName = (trimmed?.isEmpty == false ? trimmed : nil)
            ?? id.legacyDefaultName
            ?? id.rawValue
    }
}

/// Default camera naming (`Camera N`) shared by seeding, migration, and
/// the add action (whose number comes from the automatic-name sequence).
public enum CameraNaming {
    public static func defaultName(number: Int) -> String {
        String(localized: "Camera \(number)")
    }

    /// Trimmed name, or `nil` for a blank / whitespace-only value.
    public static func trimmedName(_ name: String?) -> String? {
        guard let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}
