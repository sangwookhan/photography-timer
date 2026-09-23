// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.app.vm

/**
 * Decides what a Filter Set name field does with its draft when the user
 * submits, the field loses focus, or the detail screen is left
 * (FILTER-SET-001). The decision is a pure value so the editor's three
 * exit paths cannot disagree: a deleted set is a no-op, an empty draft
 * restores the current name, an unchanged draft does nothing, and
 * anything else renames to the trimmed draft.
 * (iOS: `FilterSetRenameCommit`.)
 */
sealed class FilterSetRenameCommit {
    /** Rename the set to this trimmed, non-empty name. */
    data class Rename(val name: String) : FilterSetRenameCommit()

    /** The draft was blank; put the current name back in the field. */
    data class Restore(val name: String) : FilterSetRenameCommit()

    /** Nothing to do: the set no longer exists or the name is unchanged. */
    data object None : FilterSetRenameCommit()

    companion object {
        fun decide(draft: String, currentName: String?): FilterSetRenameCommit {
            currentName ?: return None
            val trimmed = draft.trim()
            if (trimmed.isEmpty()) return Restore(currentName)
            return if (trimmed == currentName) None else Rename(trimmed)
        }
    }
}
