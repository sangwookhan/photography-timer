// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.app.vm

import com.sangwook.ptimer.core.exposure.FilterItemBehavior
import com.sangwook.ptimer.core.exposure.FilterItemKind
import com.sangwook.ptimer.core.exposure.FilterRegisteredValue
import com.sangwook.ptimer.core.exposure.FilterValueUnit
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * PTIMER-221 phase 3b: the pure validation behind the physical-filter
 * editor (FILTER-ITEM-004, FILTER-CPL-001/002/003) — what converts,
 * what is refused, and when Save may fire.
 */
class FilterItemEditorDraftTest {

    private fun fixed(valueText: String, unit: FilterValueUnit) =
        FilterItemEditorDraft(name = "Big Stopper", valueText = valueText, unit = unit)

    private fun cpl(vararg texts: String) =
        FilterItemEditorDraft(name = "NiSi CPL", kind = FilterItemKind.cpl, cplTexts = texts.toList())

    // MARK: Fixed / GND conversion

    @Test
    fun opticalDensityDividesByPointThree() {
        val draft = fixed("0.9", FilterValueUnit.opticalDensity)
        assertEquals(3.0, draft.canonicalStops!!, 1e-9)
        assertTrue(draft.canSave)
        assertFalse(draft.hasValueError)
    }

    @Test
    fun commercialNdFactorUsesTheLadderValue() {
        // ND1000 is exactly 10 stops, not log2(1000).
        assertEquals(10.0, fixed("1000", FilterValueUnit.filterFactor).canonicalStops!!, 1e-9)
    }

    @Test
    fun zeroAndOverThirtyStopsAreRefused() {
        val zero = fixed("0", FilterValueUnit.stops)
        assertNull(zero.canonicalStops)
        assertTrue(zero.hasValueError)
        assertFalse(zero.canSave)

        val tooLarge = fixed("31", FilterValueUnit.stops)
        assertNull(tooLarge.canonicalStops)
        assertTrue(tooLarge.hasValueError)
        assertFalse(tooLarge.canSave)
    }

    @Test
    fun anUntouchedValueFieldIsNotYetAnError() {
        val empty = fixed("", FilterValueUnit.stops)
        assertFalse("Nothing typed yet — no red text.", empty.hasValueError)
        assertFalse(empty.canSave)
    }

    @Test
    fun aCommaDecimalSeparatorParses() {
        assertEquals(3.0, fixed("0,9", FilterValueUnit.opticalDensity).canonicalStops!!, 1e-9)
    }

    @Test
    fun aBlankNameBlocksSaveEvenWithAValidValue() {
        assertFalse(fixed("3", FilterValueUnit.stops).copy(name = "   ").canSave)
    }

    @Test
    fun theKindDecidesWhetherTheValueBecomesFixedOrGnd() {
        val draft = fixed("0.9", FilterValueUnit.opticalDensity)
        assertTrue(draft.behavior() is FilterItemBehavior.Fixed)
        assertTrue(draft.copy(kind = FilterItemKind.gnd).behavior() is FilterItemBehavior.Gnd)
    }

    // MARK: CPL exposure-loss choices

    @Test
    fun newCplChoicesStartAtOneOnePointFiveAndTwo() {
        assertEquals(listOf("1", "1.5", "2"), FilterItemEditorDraft.DEFAULT_CPL_TEXTS)
        val draft = FilterItemEditorDraft(name = "NiSi CPL", kind = FilterItemKind.cpl)
        val behavior = draft.behavior() as FilterItemBehavior.Cpl
        assertEquals(listOf(1.0, 1.5, 2.0), behavior.choices.shootingChoices)
    }

    @Test
    fun aTwoDecimalChoiceIsRefusedOnItsOwnField() {
        val draft = cpl("1.25", "1.5", "")
        assertEquals(listOf(true, false, false), draft.cplFieldErrors)
        assertFalse(draft.canSave)
    }

    @Test
    fun aChoiceOutsideTheRangeIsRefused() {
        assertEquals(listOf(true, false, false), cpl("10", "1.5", "").cplFieldErrors)
        assertEquals(listOf(true, false, false), cpl("0", "1.5", "").cplFieldErrors)
    }

    @Test
    fun allEmptyFieldsAreRefused() {
        val draft = cpl("", "", "")
        assertTrue(draft.cplIsEmpty)
        assertFalse(draft.canSave)
    }

    @Test
    fun oneValidChoiceIsEnoughAndEmptyFieldsAreSkipped() {
        val draft = cpl("", "1,5", "")
        assertFalse(draft.cplIsEmpty)
        assertTrue(draft.canSave)
        val behavior = draft.behavior() as FilterItemBehavior.Cpl
        assertEquals(listOf(1.5), behavior.choices.shootingChoices)
    }

    @Test
    fun theValueErrorNeverFiresWhileTheKindIsCpl() {
        assertFalse(cpl("1", "1.5", "2").copy(valueText = "nonsense").hasValueError)
    }

    // MARK: Editing an existing item

    @Test
    fun editingSeedsTheRegisteredValueAndUnit() {
        val item = FilterItemEditorDraft.editing(
            "Lee GND",
            FilterItemBehavior.Gnd(FilterRegisteredValue(0.9, FilterValueUnit.opticalDensity)),
        )
        assertEquals("Lee GND", item.name)
        assertEquals(FilterItemKind.gnd, item.kind)
        assertEquals("0.9", item.valueText)
        assertEquals(FilterValueUnit.opticalDensity, item.unit)
        // Switching kind mid-edit starts CPL from the shipping defaults.
        assertEquals(FilterItemEditorDraft.DEFAULT_CPL_TEXTS, item.cplTexts)
    }
}
