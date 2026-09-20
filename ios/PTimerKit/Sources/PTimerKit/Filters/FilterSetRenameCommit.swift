// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Decides what a Filter Set name field does with its draft when the
/// user submits, the field loses focus, or the detail screen is left
/// (FILTER-SET-001). The decision is a pure value so the editor's
/// three exit paths cannot disagree: a deleted set is a no-op, an
/// empty draft restores the current name, an unchanged draft does
/// nothing, and anything else renames to the trimmed draft.
public enum FilterSetRenameCommit: Equatable, Sendable {
    /// Rename the set to this trimmed, non-empty name.
    case rename(String)
    /// The draft was blank; put the current name back in the field.
    case restore(String)
    /// Nothing to do: the set no longer exists or the name is unchanged.
    case none

    public static func decide(draft: String, currentName: String?) -> FilterSetRenameCommit {
        guard let currentName else {
            return .none
        }
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return .restore(currentName)
        }
        return trimmed == currentName ? .none : .rename(trimmed)
    }
}
