// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.core.exposure

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.math.log2

/**
 * Filter Set contract — inventory value rules: registered-value
 * conversion (FILTER-ITEM-004), CPL choice validation and decimal input
 * normalization (FILTER-CPL-001/002/003), and the creation color
 * suggestion (FILTER-SET-003). Port of iOS FilterInventoryTests.
 */
class FilterInventoryTest {

    private fun registered(value: Double, unit: FilterValueUnit) = FilterRegisteredValue(value, unit)

    // --- FILTER-ITEM-004 — conversion to canonical stops ---

    @Test fun stopsValueIsUnchanged() {
        assertEquals(3.3, registered(3.3, FilterValueUnit.stops).canonicalStops!!, 0.0)
    }

    @Test fun opticalDensityDividesByPointThree() {
        assertEquals(3.0, registered(0.9, FilterValueUnit.opticalDensity).canonicalStops!!, 1e-9)
        // OD 2.0 is NOT snapped to the Standard 6.6 preset.
        assertEquals(
            2.0 / 0.3,
            registered(2.0, FilterValueUnit.opticalDensity).canonicalStops!!,
            1e-9,
        )
    }

    @Test fun filterFactorMatchingACommercialLabelTakesTheLadderValue() {
        assertEquals(3.0, registered(8.0, FilterValueUnit.filterFactor).canonicalStops!!, 1e-12)
        // ND1000 is the Standard label of 10 stops: exactly 10, not log2(1000).
        assertEquals(10.0, registered(1000.0, FilterValueUnit.filterFactor).canonicalStops!!, 0.0)
        assertEquals(11.0, registered(2000.0, FilterValueUnit.filterFactor).canonicalStops!!, 0.0)
        assertEquals(13.0, registered(8000.0, FilterValueUnit.filterFactor).canonicalStops!!, 0.0)
        assertEquals(6.6, registered(100.0, FilterValueUnit.filterFactor).canonicalStops!!, 0.0)
        assertEquals(16.6, registered(100_000.0, FilterValueUnit.filterFactor).canonicalStops!!, 0.0)
        assertEquals(14.0, registered(16384.0, FilterValueUnit.filterFactor).canonicalStops!!, 0.0)
    }

    @Test fun filterFactorWithoutACommercialLabelUsesLog2() {
        assertEquals(
            log2(500.0),
            registered(500.0, FilterValueUnit.filterFactor).canonicalStops!!,
            1e-12,
        )
        assertEquals(
            log2(64_000.0),
            registered(64_000.0, FilterValueUnit.filterFactor).canonicalStops!!,
            1e-12,
        )
    }

    @Test fun invalidRegisteredValuesAreRejected() {
        assertNull(registered(0.0, FilterValueUnit.stops).canonicalStops)
        assertNull(registered(-1.0, FilterValueUnit.stops).canonicalStops)
        assertNull(registered(30.5, FilterValueUnit.stops).canonicalStops)
        assertNull(registered(Double.NaN, FilterValueUnit.stops).canonicalStops)
        assertNull(registered(Double.POSITIVE_INFINITY, FilterValueUnit.opticalDensity).canonicalStops)
        assertNull("ND1 is 0 stops.", registered(1.0, FilterValueUnit.filterFactor).canonicalStops)
        assertNull(registered(0.0, FilterValueUnit.filterFactor).canonicalStops)
        assertEquals(30.0, registered(30.0, FilterValueUnit.stops).canonicalStops!!, 0.0)
    }

    // --- FILTER-CPL-001/002 — choices ---

    @Test fun defaultChoicesAreOneOnePointFiveTwo() {
        assertEquals(listOf(1.0, 1.5, 2.0), CplExposureLossChoices.defaults.shootingChoices)
        assertTrue(CplExposureLossChoices.defaults.isValid)
    }

    @Test fun choiceRangeAndPrecision() {
        assertFalse(CplExposureLossChoices.isValidChoice(0.0))
        assertFalse(CplExposureLossChoices.isValidChoice(10.0))
        assertFalse(CplExposureLossChoices.isValidChoice(1.25))
        assertTrue(CplExposureLossChoices.isValidChoice(0.1))
        assertTrue(CplExposureLossChoices.isValidChoice(9.9))
        assertTrue(CplExposureLossChoices.isValidChoice(1.5))
    }

    @Test fun emptyFieldsOmitChoicesAndDuplicatesCollapse() {
        val choices = CplExposureLossChoices(listOf(2.0, null, 2.0))
        assertTrue(choices.isValid)
        assertEquals(listOf(2.0), choices.shootingChoices)
        assertEquals(3, choices.fields.size)
    }

    @Test fun atLeastOneValidChoiceIsRequired() {
        assertFalse(CplExposureLossChoices(listOf(null, null, null)).isValid)
        assertFalse(CplExposureLossChoices(listOf(1.0, 1.25, null)).isValid)
    }

    // --- FILTER-CPL-003 — decimal input normalization ---

    @Test fun cplFieldParsingNormalizesSeparatorsAndRejectsOutOfRule() {
        assertEquals(FilterDecimalInput.CplFieldParse.Value(1.5), FilterDecimalInput.parseCplField("1,5"))
        assertEquals(FilterDecimalInput.CplFieldParse.Value(2.0), FilterDecimalInput.parseCplField(" 2 "))
        assertEquals(FilterDecimalInput.CplFieldParse.Empty, FilterDecimalInput.parseCplField(""))
        assertEquals(FilterDecimalInput.CplFieldParse.Invalid, FilterDecimalInput.parseCplField("0"))
        assertEquals(FilterDecimalInput.CplFieldParse.Invalid, FilterDecimalInput.parseCplField("10"))
        assertEquals(FilterDecimalInput.CplFieldParse.Invalid, FilterDecimalInput.parseCplField("1.25"))
        assertEquals(FilterDecimalInput.CplFieldParse.Invalid, FilterDecimalInput.parseCplField("abc"))
    }

    @Test fun generalDecimalParsing() {
        assertEquals(0.9, FilterDecimalInput.parseDecimal("0,9")!!, 0.0)
        assertEquals(1000.0, FilterDecimalInput.parseDecimal("1000")!!, 0.0)
        assertNull(FilterDecimalInput.parseDecimal(""))
        assertNull(FilterDecimalInput.parseDecimal("1e3"))
    }

    // --- FILTER-SET-003 — color suggestion ---

    @Test fun colorSuggestionDiffersFromPreviousSuggestion() {
        var previous: FilterSetColor? = null
        repeat(200) {
            val next = FilterSetColor.suggestion(excluding = previous)
            assertNotEquals(previous, next)
            previous = next
        }
    }

    // --- FILTER-ITEM-002 — duplicates are distinct items ---

    @Test fun equalItemsRemainDistinctById() {
        val value = registered(3.0, FilterValueUnit.stops)
        val first = FilterItem("ND8", FilterItemBehavior.Fixed(value))
        val second = FilterItem("ND8", FilterItemBehavior.Fixed(value))
        assertNotEquals(first.id, second.id)
        val inventory = FilterInventory(listOf(FilterSet("Holder", FilterSetColor.red, listOf(first, second))))
        assertEquals(second, inventory.item(second.id)?.second)
        assertNotNull(inventory.item(first.id))
    }
}
