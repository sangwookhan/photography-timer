// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.app.vm

import com.sangwook.ptimer.core.exposure.CplExposureLossChoices
import com.sangwook.ptimer.core.exposure.FilterItem
import com.sangwook.ptimer.core.exposure.FilterItemBehavior
import com.sangwook.ptimer.core.exposure.FilterItemKind
import com.sangwook.ptimer.core.exposure.FilterRegisteredValue
import com.sangwook.ptimer.core.exposure.FilterValueUnit
import org.junit.Assert.assertEquals
import org.junit.Test

/** FILTER-ITEM-007: the open editor session's remembered notation. */
class FilterItemEditorSessionMemoryTest {

    private fun fixed(unit: FilterValueUnit) = FilterItem(
        "Fixed",
        FilterItemBehavior.Fixed(FilterRegisteredValue(3.0, unit)),
    )

    private fun gnd(unit: FilterValueUnit) = FilterItem(
        "GND",
        FilterItemBehavior.Gnd(FilterRegisteredValue(0.9, unit)),
    )

    @Test
    fun startsInStopsAndAlwaysStartsAsFixed() {
        val sut = FilterItemEditorSessionMemory()
        assertEquals(FilterValueUnit.stops, sut.initialUnit)
        assertEquals(FilterItemKind.fixed, sut.initialKind)
    }

    @Test
    fun savingANewFixedOrGndItemRemembersItsNotation() {
        val sut = FilterItemEditorSessionMemory()
        sut.didSaveNewItem(fixed(FilterValueUnit.filterFactor))
        assertEquals(FilterValueUnit.filterFactor, sut.initialUnit)

        sut.didSaveNewItem(gnd(FilterValueUnit.opticalDensity))
        assertEquals(FilterValueUnit.opticalDensity, sut.initialUnit)
        assertEquals(
            "A GND save must not make the next new item a GND.",
            FilterItemKind.fixed,
            sut.initialKind,
        )
    }

    @Test
    fun savingANewCplItemLeavesTheNotationUnchanged() {
        val sut = FilterItemEditorSessionMemory()
        sut.didSaveNewItem(fixed(FilterValueUnit.opticalDensity))
        sut.didSaveNewItem(FilterItem("CPL", FilterItemBehavior.Cpl(CplExposureLossChoices.defaults)))
        assertEquals(FilterValueUnit.opticalDensity, sut.initialUnit)
    }
}
