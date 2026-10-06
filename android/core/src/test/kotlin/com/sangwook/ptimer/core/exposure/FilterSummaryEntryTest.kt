// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.core.exposure

import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * FILTER-PERSIST-003: the summary captured when a timer starts records
 * each mounted row's source, item, registered value, calculation mode,
 * and contributed stops. Port of the iOS FilterStackTests summary case.
 */
class FilterSummaryEntryTest {

    @Test fun summaryCapturesSourceItemModeAndContribution() {
        val gnd = FilterItem(
            "Lee GND 0.9",
            FilterItemBehavior.Gnd(FilterRegisteredValue(0.9, FilterValueUnit.opticalDensity)),
        )
        val red = FilterItem("Red 25A", FilterItemBehavior.Color(FilterExposureLoss(3.0), FilterSetColor.red))
        val set = FilterSet("Lee holder", FilterSetColor.blue, listOf(gnd, red))
        val inventory = FilterInventory(listOf(set))
        val stack = FilterStack.validated(
            listOf(FilterWheel.standard(6.6), FilterWheel.empty(set.id)),
            listOf(
                MountedAuxiliaryFilter(set.id, gnd.id, AuxiliaryFilterChoice.Gnd(GndCalculationMode.recordOnly)),
                MountedAuxiliaryFilter(set.id, red.id, AuxiliaryFilterChoice.RegisteredLoss),
            ),
            inventory,
        )!!

        val summary = FilterSummaryEntry.summary(stack, inventory)
        assertEquals("Auxiliary filters first, Empty wheels omitted.", 3, summary.size)

        val color = summary[0]
        assertEquals(FilterItemKind.color, color.itemKind)
        assertEquals("Red 25A", color.itemName)
        assertEquals(FilterSummaryEntry.CalculationMode.fixed, color.calculationMode)
        assertEquals(3.0, color.contributedStops, 0.0)

        val entry = summary[1]
        assertEquals(FilterSummaryEntry.SourceKind.filterSet, entry.sourceKind)
        assertEquals(set.id.rawValue, entry.filterSetId)
        assertEquals("Lee holder", entry.filterSetName)
        assertEquals(gnd.id.rawValue, entry.itemId)
        assertEquals("Lee GND 0.9", entry.itemName)
        assertEquals(FilterItemKind.gnd, entry.itemKind)
        assertEquals(0.9, entry.originalValue!!, 0.0)
        assertEquals(FilterValueUnit.opticalDensity, entry.originalUnit)
        assertEquals(3.0, entry.canonicalStops!!, 1e-9)
        assertEquals(FilterSummaryEntry.CalculationMode.gndRecordOnly, entry.calculationMode)
        assertEquals(0.0, entry.contributedStops, 0.0)

        assertEquals(FilterSummaryEntry.SourceKind.standard, summary[2].sourceKind)
        assertEquals(6.6, summary[2].contributedStops, 0.0)
    }
}
