// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// User-facing source classification for a custom reciprocity profile
/// that the photographer authored in-app. Distinct from
/// `ReciprocitySourceKind` / `ReciprocityAuthority`, both of which
/// always remain `.userDefined` for a custom-authored profile — the
/// source kind drives the calculation policy's authority impact,
/// while this enum is purely descriptive metadata so the user (and
/// later, the timer identity snapshot) can recall *why* this profile
/// exists: a self-measured test, a community-shared formula, etc.
///
/// The four cases are intentionally chosen so a custom profile can
/// never be mistaken for official manufacturer data: every case
/// renders with a "Custom" badge on the selector row and a
/// source-type subtitle in the Details surface.
public enum CustomProfileSourceType: String, Codable, Equatable, CaseIterable, Hashable {
    /// Catch-all for a custom profile whose origin the user did not
    /// classify further. Default for new entries.
    case userDefined

    /// Photographer's own measurements (e.g., long-exposure step
    /// wedge tests). The user vouches for the formula themselves.
    case personalTest

    /// Formula taken from a community source (forum post,
    /// shared spreadsheet, third-party guidance) that does not have
    /// manufacturer publication backing.
    case communityReference

    /// Origin not known or not recorded.
    case unknown

    /// Short user-facing label rendered in the selector subtitle
    /// and in the Details source-type row.
    public var displayLabel: String {
        switch self {
        case .userDefined: return "User-defined"
        case .personalTest: return "Personal test"
        case .communityReference: return "Community reference"
        case .unknown: return "Unknown source"
        }
    }
}
