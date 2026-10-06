// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.app.vm

import com.sangwook.ptimer.core.exposure.FilterItemKind

/**
 * Which editing path opened the filter editor: the Filter Set's
 * Auxiliary tab (CPL, GND, Color, Effect) or its ND tab (ND items only)
 * (FILTER-SET-001). An existing item's own kind decides it.
 * (iOS: `FilterItemEditorContext.Category`.)
 */
enum class FilterItemCategory {
    auxiliary,
    nd;

    /** The kinds a new item on this path may take; the first is the
     *  kind a new item starts at. */
    val kinds: List<FilterItemKind>
        get() = when (this) {
            auxiliary -> FilterItemKind.entries.filter { it.isAuxiliary }
            nd -> listOf(FilterItemKind.fixed)
        }

    companion object {
        fun of(kind: FilterItemKind): FilterItemCategory = if (kind.isAuxiliary) auxiliary else nd

        /**
         * Kinds the editor offers: a new item stays within its tab's
         * kinds; an existing item may be corrected to any kind (for
         * example an ND item entered by mistake becomes a Color filter).
         */
        fun selectableKinds(category: FilterItemCategory, isNewItem: Boolean): List<FilterItemKind> =
            if (isNewItem) category.kinds else FilterItemKind.entries
    }
}
