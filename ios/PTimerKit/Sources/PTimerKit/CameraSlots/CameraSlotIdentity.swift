import Foundation
import PTimerCore

/// Stable identity for a shooting-session camera slot. The first
/// implementation supports `Camera 1` through `Camera 4`; identities
/// stay stable across slot switches and persist into timer metadata so
/// a timer can be associated with the camera that started it.
public enum CameraSlotID: String, CaseIterable, Codable, Equatable, Hashable, Identifiable {
    case camera1
    case camera2
    case camera3
    case camera4

    /// `Identifiable` conformance for SwiftUI surfaces (e.g.
    /// `.sheet(item:)` on the rename sheet). Each slot is its own
    /// stable identity, which is exactly what `Identifiable` asks
    /// for — no wrapper struct is required.
    public var id: CameraSlotID { self }

    /// Default order used by the session model and the slot pager
    /// UI. The shipping experience exposes all four slots — the
    /// session model preconditions that at least two are available,
    /// not that only two are surfaced.
    public static let allOrdered: [CameraSlotID] = CameraSlotID.allCases

    /// Human-facing label used by the slot switcher and timer
    /// metadata. Names stay simple by design — slot identity is not a
    /// camera inventory.
    public var defaultDisplayName: String {
        switch self {
        case .camera1: return "Camera 1"
        case .camera2: return "Camera 2"
        case .camera3: return "Camera 3"
        case .camera4: return "Camera 4"
        }
    }
}

/// View-facing pair of stable id + display label. Stored in timer
/// metadata as a separate axis from the exposure-source tag (adjusted /
/// corrected / future target shutter) so the two never collide.
///
/// The display layer reads `displayName`, which prefers
/// `customDisplayName` (when present and non-empty) and otherwise
/// falls back to `defaultDisplayName`. The rename / reset surface
/// writes only `customDisplayName`; clearing it restores the
/// canonical `Camera N` label without touching slot identity.
public struct CameraSlotIdentity: Equatable, Hashable, Codable {
    public let id: CameraSlotID
    /// Canonical, locale-stable label tied to the slot id (e.g.
    /// `"Camera 1"`). Always present so the display layer has a
    /// guaranteed fallback when no custom name exists.
    public let defaultDisplayName: String
    /// Optional photographer-supplied label. `nil` means "use default".
    /// The rename / reset surface writes only this value; clearing it
    /// restores the canonical `Camera N` label without changing slot
    /// identity.
    public var customDisplayName: String?

    /// Active label for any UI surface. Non-empty `customDisplayName`
    /// wins; otherwise falls back to `defaultDisplayName`. Trimming
    /// whitespace prevents an accidentally-blank custom name from
    /// hiding the default.
    public var displayName: String {
        if let trimmed = customDisplayName?.trimmedNonEmpty {
            return trimmed
        }
        return defaultDisplayName
    }

    /// Designated init. Lets callers (tests, future custom-name
    /// editing) supply both fields explicitly. Production code paths
    /// usually use the `displayName` convenience init below.
    public init(
        id: CameraSlotID,
        defaultDisplayName: String? = nil,
        customDisplayName: String? = nil
    ) {
        self.id = id
        self.defaultDisplayName = defaultDisplayName ?? id.defaultDisplayName
        self.customDisplayName = customDisplayName
    }

    /// Convenience init that maps a single `displayName` argument
    /// onto either the default name (when equal to the canonical
    /// `id.defaultDisplayName`) or the custom slot. Used by call
    /// sites that already had a pre-split display name — e.g., timer
    /// metadata persistence captures one stored display name and
    /// this init converts it back to the split representation.
    public init(id: CameraSlotID, displayName: String?) {
        let defaultName = id.defaultDisplayName
        self.id = id
        self.defaultDisplayName = defaultName
        if let trimmed = displayName?.trimmedNonEmpty,
           trimmed != defaultName {
            self.customDisplayName = trimmed
        } else {
            self.customDisplayName = nil
        }
    }
}

private extension String {
    /// `nil` for an all-whitespace string; otherwise a
    /// whitespace-stripped copy. Keeps display-name decisions free
    /// of "" / "  " edge cases.
    var trimmedNonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
