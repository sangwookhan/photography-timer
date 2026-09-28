// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.app.vm

import com.sangwook.ptimer.core.exposure.CplExposureLossChoices
import com.sangwook.ptimer.core.exposure.FilterInventory
import com.sangwook.ptimer.core.exposure.FilterItem
import com.sangwook.ptimer.core.exposure.FilterItemBehavior
import com.sangwook.ptimer.core.exposure.FilterRegisteredValue
import com.sangwook.ptimer.core.exposure.FilterSet
import com.sangwook.ptimer.core.exposure.FilterSetColor
import com.sangwook.ptimer.core.exposure.FilterSource
import com.sangwook.ptimer.core.exposure.FilterStack
import com.sangwook.ptimer.core.exposure.FilterStackRejection
import com.sangwook.ptimer.core.exposure.FilterValueUnit
import com.sangwook.ptimer.core.exposure.FilterWheel
import com.sangwook.ptimer.core.exposure.FilterWheelRowOption
import com.sangwook.ptimer.core.exposure.GndCalculationMode
import com.sangwook.ptimer.core.exposure.NDNotationMode
import com.sangwook.ptimer.core.exposure.ResolvedFilterRow
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/**
 * FILTER-STACK-007: what one picker row shows. Fixed and GND follow the
 * app-global notation through the shared Standard formatter (numeric
 * component only), CPL stays exposure loss in stops in every notation,
 * and Empty renders canonical zero.
 */
class FilterWheelPresenterTest {

    private val bigStopper = FilterItem(
        "Big Stopper",
        FilterItemBehavior.Fixed(FilterRegisteredValue(1000.0, FilterValueUnit.filterFactor)),
    )
    private val gnd = FilterItem(
        "Lee GND 0.9",
        FilterItemBehavior.Gnd(FilterRegisteredValue(0.9, FilterValueUnit.opticalDensity)),
    )
    private val cpl = FilterItem(
        "Lee CPL",
        FilterItemBehavior.Cpl(CplExposureLossChoices(listOf(1.0, 1.5, null))),
    )

    private val filterSet = FilterSet("Lee holder", FilterSetColor.indigo, listOf(bigStopper, gnd, cpl))
    private val inventory = FilterInventory(listOf(filterSet))
    private val source = FilterSource.FilterSet(filterSet.id)

    /** Every row the one Filter Set wheel offers, in wheel order. */
    private fun rows(mode: NDNotationMode): List<FilterWheelRowUiState> {
        val stack = FilterStack.validated(listOf(FilterWheel.empty(filterSet.id)), inventory)!!
        return stack.rowOptions(0, inventory).map { FilterWheelPresenter.row(it, mode) }
    }

    private fun row(mode: NDNotationMode, name: String, gndMode: GndCalculationMode? = null) =
        rows(mode).first { it.itemName == name && it.gndMode == gndMode }

    @Test
    fun fixedValuesFollowTheGlobalNotationNumericComponentOnly() {
        // ND1000 is exactly 10 canonical stops, so it renders 10 / 3.0 / 1000.
        assertEquals("10", row(NDNotationMode.STOPS, "Big Stopper").compactValueText)
        assertEquals("3.0", row(NDNotationMode.OPTICAL_DENSITY, "Big Stopper").compactValueText)
        assertEquals("1000", row(NDNotationMode.FILTER_FACTOR, "Big Stopper").compactValueText)
        assertEquals(FilterRowTypeCategory.nd, row(NDNotationMode.STOPS, "Big Stopper").typeCategory)
        assertEquals(
            FilterRegisteredValue(1000.0, FilterValueUnit.filterFactor),
            row(NDNotationMode.STOPS, "Big Stopper").registeredValue,
        )
    }

    @Test
    fun gndShowsItsRegisteredDensityInBothModesWithTheGndCategory() {
        for (mode in listOf(GndCalculationMode.recordOnly, GndCalculationMode.applyFullValue)) {
            val stops = row(NDNotationMode.STOPS, "Lee GND 0.9", mode)
            val od = row(NDNotationMode.OPTICAL_DENSITY, "Lee GND 0.9", mode)
            assertEquals("3", stops.compactValueText)
            assertEquals("0.9", od.compactValueText)
            assertEquals(FilterRowTypeCategory.gnd, stops.typeCategory)
            assertEquals(mode, stops.gndMode)
            assertEquals(3.0, stops.registeredStops, 1e-9)
        }
        // Only the contribution differs between the two modes.
        assertEquals(0.0, row(NDNotationMode.STOPS, "Lee GND 0.9", GndCalculationMode.recordOnly).contributionStops, 1e-9)
        assertEquals(
            3.0,
            row(NDNotationMode.STOPS, "Lee GND 0.9", GndCalculationMode.applyFullValue).contributionStops,
            1e-9,
        )
    }

    @Test
    fun cplChoicesStayExposureLossInStopsInEveryNotation() {
        for (mode in NDNotationMode.entries) {
            val cplRows = rows(mode).filter { it.itemName == "Lee CPL" }
            assertEquals(listOf("1", "1.5"), cplRows.map { it.compactValueText })
            assertEquals(listOf(1.0, 1.5), cplRows.map { it.cplLossStops })
            assertEquals(listOf(FilterRowTypeCategory.cpl, FilterRowTypeCategory.cpl), cplRows.map { it.typeCategory })
            assertNull("A CPL row carries choices, not a registered value.", cplRows[0].registeredValue)
        }
    }

    @Test
    fun emptyRendersCanonicalZeroThroughTheSharedStandardFormatter() {
        assertEquals("0", rows(NDNotationMode.STOPS).first().compactValueText)
        assertEquals("0.0", rows(NDNotationMode.OPTICAL_DENSITY).first().compactValueText)
        assertEquals("1", rows(NDNotationMode.FILTER_FACTOR).first().compactValueText)
        assertEquals(FilterRowTypeCategory.empty, rows(NDNotationMode.STOPS).first().typeCategory)
        assertNull(rows(NDNotationMode.STOPS).first().itemName)
    }

    @Test
    fun standardRowsUseTheLadderValueAndTheNdCategory() {
        val stack = FilterStack.single(0.0)
        val options = stack.rowOptions(0, inventory)
        val ten = options.map { FilterWheelPresenter.row(it, NDNotationMode.FILTER_FACTOR) }
            .first { it.registeredStops == 10.0 }
        assertEquals("1000", ten.compactValueText)
        assertEquals(FilterRowTypeCategory.nd, ten.typeCategory)
    }

    @Test
    fun unavailableRowsCarryTheirReason() {
        val option = FilterWheelRowOption(
            row = ResolvedFilterRow(FilterWheel.empty(filterSet.id).selection, 0.0, 0.0, null),
            unavailability = FilterStackRejection.itemAlreadyMounted,
        )
        val state = FilterWheelPresenter.row(option, NDNotationMode.STOPS)
        assertEquals(FilterStackRejection.itemAlreadyMounted, state.unavailability)
        assertEquals(false, state.isAvailable)
    }

    @Test
    fun sourceNameUsesCanonicalEnglish() {
        assertEquals("Standard", FilterWheelPresenter.sourceName(FilterSource.Standard, inventory))
        assertEquals("Lee holder", FilterWheelPresenter.sourceName(source, inventory))
    }

    @Test
    fun decimalRenderingTrimsTrailingZeros() {
        assertEquals("1", FilterWheelPresenter.decimalStopsValue(1.0))
        assertEquals("1.5", FilterWheelPresenter.decimalStopsValue(1.5))
        assertEquals("6.6", FilterWheelPresenter.decimalStopsValue(6.6))
        assertEquals("0.9", FilterWheelPresenter.trimmedNumber(0.9))
        assertEquals("1000", FilterWheelPresenter.trimmedNumber(1000.0))
    }
}
