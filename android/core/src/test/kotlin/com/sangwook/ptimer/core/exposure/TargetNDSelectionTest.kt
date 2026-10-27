// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.core.exposure

import java.io.File
import kotlin.math.pow
import kotlinx.serialization.json.*
import org.junit.Assert.*
import org.junit.Test

class TargetNDSelectionTest {
    private val selector = TargetNDSelection()

    @Test fun sharedSelectionFixturesMatchIOS() {
        var directory: File? = File(System.getProperty("user.dir")).absoluteFile
        var fixture: File? = null
        while (directory != null && fixture == null) {
            File(directory, "shared/test-fixtures/target-nd-selection.json").takeIf { it.exists() }?.let { fixture = it }
            directory = directory.parentFile
        }
        val rows = Json.parseToJsonElement(requireNotNull(fixture).readText()).jsonObject["cases"]!!.jsonArray
        val setId = FilterSetId("set")
        for (element in rows) {
            val row = element.jsonObject
            val name = row["name"]!!.jsonPrimitive.content
            val items = row["items"]!!.jsonArray.mapIndexed { index, value ->
                FilterItem("ND $index", FilterItemBehavior.Fixed(FilterRegisteredValue(value.jsonPrimitive.double, FilterValueUnit.stops)), FilterItemId("item-$index"))
            }
            val inventory = FilterInventory(listOf(FilterSet("ND", FilterSetColor.blue, items, setId)))
            val context = TargetNDSelectionContext(if (row["selectSet"]!!.jsonPrimitive.boolean) listOf(setId) else emptyList(), FilterStack.single(0.0), row["minimumError"]!!.jsonPrimitive.double..row["maximumError"]!!.jsonPrimitive.double)
            val result = selector.evaluate(1.0, 2.0.pow(row["requiredStops"]!!.jsonPrimitive.double), null, inventory, context)
            if (row["expectedStops"] == JsonNull) {
                assertEquals(name, TargetNDSelectionResult.Unavailable(TargetNDSelectionFailure.NoCombination), result)
            } else {
                assertTrue("$name: $result", result is TargetNDSelectionResult.Available)
                val candidate = (result as TargetNDSelectionResult.Available).candidate
                assertEquals(name, row["expectedStops"]!!.jsonPrimitive.double, candidate.stack.effectiveStops, 1e-10)
                assertEquals(name, row["expectedCount"]!!.jsonPrimitive.int, candidate.stack.wheels.count { !it.isCleanable })
            }
        }
    }

    @Test fun replacementStandardIgnoresRemovedNDAndLegacyFraction() {
        val current = requireNotNull(FilterStack.validated(listOf(FilterWheel.standard(10.0), FilterWheel.standard(10.0)), FilterInventory.empty))
        val result = selector.evaluate(1.0, 2.0.pow(25), null, FilterInventory.empty, TargetNDSelectionContext(emptyList(), current, -1.0..0.0)) as TargetNDSelectionResult.Available
        assertEquals(listOf(FilterWheel.standard(25.0)), result.candidate.stack.wheels)
        val fraction = selector.evaluate(1.0, 2.0.pow(6.6), null, FilterInventory.empty, TargetNDSelectionContext(emptyList(), FilterStack.single(6.6), -0.5..1.0)) as TargetNDSelectionResult.Available
        assertEquals(listOf(FilterWheel.standard(7.0)), fraction.candidate.stack.wheels)
    }
    @Test fun structuredIdentitiesDoNotAliasAcrossSources() {
        val first = FilterSet("First", FilterSetColor.blue, listOf(FilterItem("ND6", FilterItemBehavior.Fixed(FilterRegisteredValue(6.0, FilterValueUnit.stops)), FilterItemId("b:c"))), FilterSetId("a"))
        val second = FilterSet("Second", FilterSetColor.red, listOf(FilterItem("ND7", FilterItemBehavior.Fixed(FilterRegisteredValue(7.0, FilterValueUnit.stops)), FilterItemId("c"))), FilterSetId("a:b"))
        val inventory = FilterInventory(listOf(first, second))
        val current = requireNotNull(FilterStack.validated(listOf(FilterWheel(FilterSource.FilterSet(first.id), FilterWheelSelection.Item(FilterRowSelection(first.items[0].id, FilterRowChoice.Fixed)))), inventory))
        val result = selector.evaluate(1.0, 128.0, null, inventory, TargetNDSelectionContext(listOf(first.id, second.id), current, -0.5..1.0)) as TargetNDSelectionResult.Available
        assertEquals(7.0, result.candidate.stack.effectiveStops, 0.0)
        assertFalse(result.candidate.isCurrent)
    }

}
