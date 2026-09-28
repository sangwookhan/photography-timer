// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.app.vm

import com.sangwook.ptimer.core.exposure.FilterItem
import com.sangwook.ptimer.core.exposure.FilterItemBehavior
import com.sangwook.ptimer.core.exposure.FilterItemKind
import com.sangwook.ptimer.core.exposure.FilterValueUnit

/**
 * What one open Filter Set editing session remembers between consecutive
 * new items (FILTER-ITEM-007): the registered-value notation of the last
 * saved new Fixed or GND item, so the next new item starts in Stops, OD,
 * or ND accordingly. The kind is independent and always starts as Fixed.
 * The value lives with the open editor and is never persisted — closing
 * the editor or relaunching starts a fresh session in Stops.
 * (iOS: `FilterItemEditorSessionMemory`.)
 */
class FilterItemEditorSessionMemory {

    /** Notation the next new item starts with. */
    var initialUnit: FilterValueUnit = FilterValueUnit.stops
        private set

    /** Every new item starts as Fixed regardless of what was saved. */
    val initialKind: FilterItemKind get() = FilterItemKind.fixed

    /**
     * A new item was saved in this session. Fixed and GND carry a
     * registered notation and update the memory; a CPL has none and
     * leaves it unchanged. Editing an existing item never calls this.
     */
    fun didSaveNewItem(item: FilterItem) {
        when (val behavior = item.behavior) {
            is FilterItemBehavior.Fixed -> initialUnit = behavior.value.unit
            is FilterItemBehavior.Gnd -> initialUnit = behavior.value.unit
            is FilterItemBehavior.Cpl -> Unit
        }
    }
}
