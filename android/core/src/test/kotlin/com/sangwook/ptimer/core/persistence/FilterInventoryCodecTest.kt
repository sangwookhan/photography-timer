// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.core.persistence

import com.sangwook.ptimer.core.exposure.CplExposureLossChoices
import com.sangwook.ptimer.core.exposure.FilterInventory
import com.sangwook.ptimer.core.exposure.FilterItem
import com.sangwook.ptimer.core.exposure.FilterItemBehavior
import com.sangwook.ptimer.core.exposure.FilterItemId
import com.sangwook.ptimer.core.exposure.FilterRegisteredValue
import com.sangwook.ptimer.core.exposure.FilterSet
import com.sangwook.ptimer.core.exposure.FilterSetColor
import com.sangwook.ptimer.core.exposure.FilterSetId
import com.sangwook.ptimer.core.exposure.FilterValueUnit
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * FILTER-PERSIST-001/002: inventory records round-trip and decode
 * independently — one damaged Filter Set is dropped while the rest
 * survive, one damaged item is dropped while its set survives, and an
 * unknown color degrades to the default instead of losing the set.
 */
class FilterInventoryCodecTest {

    private val nd8 = FilterItem(
        "ND8",
        FilterItemBehavior.Fixed(FilterRegisteredValue(3.0, FilterValueUnit.stops)),
        FilterItemId("i-nd8"),
    )
    private val cpl = FilterItem(
        "CPL",
        FilterItemBehavior.Cpl(CplExposureLossChoices(listOf(1.0, null, 2.0))),
        FilterItemId("i-cpl"),
    )
    private val gnd = FilterItem(
        "GND 0.9",
        FilterItemBehavior.Gnd(FilterRegisteredValue(0.9, FilterValueUnit.opticalDensity)),
        FilterItemId("i-gnd"),
    )
    private val inventory = FilterInventory(
        listOf(
            FilterSet("Lee", FilterSetColor.green, listOf(nd8, cpl, gnd), FilterSetId("s-lee")),
            FilterSet("NiSi", FilterSetColor.red, emptyList(), FilterSetId("s-nisi")),
        ),
    )

    @Test fun inventoryRoundTripsThroughTheCodec() {
        val snapshot = PersistentFilterInventorySnapshot.from(inventory)
        val decoded = FilterInventoryCodec.decode(FilterInventoryCodec.encode(snapshot))
        assertEquals(snapshot, decoded)
        assertEquals(inventory, decoded!!.restoredInventory)
    }

    @Test fun aMalformedItemIsSkippedWhileItsFilterSetSurvives() {
        val json = """
            {"schemaVersion":1,"filterSets":[{"id":"s-lee","name":"Lee","color":"green","items":[
              {"id":"i-nd8","name":"ND8","kind":"fixed","value":3.0,"unit":"stops"},
              {"id":"i-bad","name":"Broken","kind":"fixed","value":"three","unit":"stops"},
              {"id":"i-unknown","name":"Unknown kind","kind":"laser"}
            ]}]}
        """.trimIndent()
        val result = FilterInventoryCodec.decodeWithDiagnostics(json)
        val restored = result.snapshot.restoredInventory
        assertEquals(1, restored.filterSets.size)
        assertEquals(
            "The undecodable and the unknown-kind items are dropped.",
            listOf(nd8),
            restored.filterSets.first().items,
        )
        // The set survived, so the collection decoder refused nothing...
        assertEquals(0, result.droppedRecordCount)
        // ...but two of the user's filters are gone, and the store
        // quarantines on the OUTCOME. This read `loaded` until PTIMER-221,
        // which left those losses with no copy of the original payload.
        assertEquals(
            "One item failed to parse and one had an unknown kind.",
            2,
            result.droppedOnRestoreCount,
        )
        assertEquals(PersistenceLoadOutcome.degraded, result.outcome)
        assertTrue(result.indicatesFailure)
    }

    @Test fun aFilterSetThatParsesButCannotBeRestoredDegradesTheOutcome() {
        // A record with a blank id parses — `id` is a string — and then
        // restores to nothing, so it never reaches the inventory.
        val json = """
            {"schemaVersion":1,"filterSets":[
              {"id":"s-lee","name":"Lee","color":"green","items":[]},
              {"id":"   ","name":"Blank id","color":"red","items":[]}
            ]}
        """.trimIndent()
        val result = FilterInventoryCodec.decodeWithDiagnostics(json)
        assertEquals(0, result.droppedRecordCount)
        assertEquals(1, result.droppedOnRestoreCount)
        assertEquals(PersistenceLoadOutcome.degraded, result.outcome)
        assertEquals(listOf("Lee"), result.snapshot.restoredInventory.filterSets.map { it.name })
    }

    @Test fun duplicateItemIdsDegradeTheOutcome() {
        val json = """
            {"schemaVersion":1,"filterSets":[{"id":"s","name":"Lee","color":"green","items":[
              {"id":"i","name":"First","kind":"fixed","value":3.0,"unit":"stops"},
              {"id":"i","name":"Second","kind":"fixed","value":6.0,"unit":"stops"}
            ]}]}
        """.trimIndent()
        val result = FilterInventoryCodec.decodeWithDiagnostics(json)
        assertEquals(1, result.droppedOnRestoreCount)
        assertEquals(PersistenceLoadOutcome.degraded, result.outcome)
        assertEquals(
            listOf("First"),
            result.snapshot.restoredInventory.filterSets.single().items.map { it.name },
        )
    }

    @Test fun anIntactInventoryStaysLoaded() {
        val result = FilterInventoryCodec.decodeWithDiagnostics(
            FilterInventoryCodec.encode(PersistentFilterInventorySnapshot.from(inventory)),
        )
        assertEquals(PersistenceLoadOutcome.loaded, result.outcome)
        assertEquals(0, result.droppedRecordCount)
        assertEquals(0, result.droppedOnRestoreCount)
    }

    @Test fun aNonArrayItemsFieldDropsTheSetAndDegrades() {
        // `as? JsonArray ?: empty` used to read this exactly like a set
        // with no filters: nothing dropped, outcome `loaded`, no
        // quarantine, and the next save overwrote the payload.
        val json = """
            {"schemaVersion":1,"filterSets":[
              {"id":"s-lee","name":"Lee","color":"green","items":[]},
              {"id":"s-torn","name":"Torn","color":"red","items":{"0":"was an array"}}
            ]}
        """.trimIndent()
        val result = FilterInventoryCodec.decodeWithDiagnostics(json)
        assertEquals(PersistenceLoadOutcome.degraded, result.outcome)
        assertEquals(1, result.droppedRecordCount)
        assertEquals(listOf("s-lee"), result.snapshot.filterSets.map { it.id })
    }

    @Test fun aStringItemsFieldDropsTheSetAndDegrades() {
        val json = """
            {"schemaVersion":1,"filterSets":[
              {"id":"s-torn","name":"Torn","color":"red","items":"damaged"}
            ]}
        """.trimIndent()
        val result = FilterInventoryCodec.decodeWithDiagnostics(json)
        assertEquals(PersistenceLoadOutcome.degraded, result.outcome)
        assertEquals(1, result.droppedRecordCount)
        assertTrue(result.snapshot.filterSets.isEmpty())
    }

    @Test fun anAbsentItemsFieldIsAnEmptySetNotDamage() {
        // The legacy default, and the encoder's own output for a set with
        // nothing registered. Nothing is lost, so nothing degrades.
        val json = """
            {"schemaVersion":1,"filterSets":[{"id":"s","name":"Lee","color":"green"}]}
        """.trimIndent()
        val result = FilterInventoryCodec.decodeWithDiagnostics(json)
        assertEquals(PersistenceLoadOutcome.loaded, result.outcome)
        assertEquals(0, result.droppedRecordCount)
        assertEquals(0, result.droppedOnRestoreCount)
        assertTrue(result.snapshot.restoredInventory.filterSets.single().items.isEmpty())
    }

    @Test fun anUnknownColorRestoresAsTheDefault() {
        val json = """
            {"schemaVersion":1,"filterSets":[
              {"id":"s","name":"Lee","color":"chartreuse","items":[]}
            ]}
        """.trimIndent()
        val restored = FilterInventoryCodec.decode(json)!!.restoredInventory
        assertEquals(FilterSetColor.blue, restored.filterSets.single().color)
    }

    @Test fun aMalformedFilterSetIsDroppedAndTheOutcomeDegrades() {
        val json = """
            {"schemaVersion":1,"filterSets":[
              {"id":"s-lee","name":"Lee","color":"green","items":[]},
              {"id":"s-broken","color":"red","items":[]}
            ]}
        """.trimIndent()
        val result = FilterInventoryCodec.decodeWithDiagnostics(json)
        assertEquals(PersistenceLoadOutcome.degraded, result.outcome)
        assertEquals(1, result.droppedRecordCount)
        assertEquals(listOf("s-lee"), result.snapshot.filterSets.map { it.id })
    }

    @Test fun duplicateFilterSetIdsCollapseFirstWins() {
        val json = """
            {"schemaVersion":1,"filterSets":[
              {"id":"s","name":"First","color":"green","items":[]},
              {"id":"s","name":"Second","color":"red","items":[]}
            ]}
        """.trimIndent()
        val result = FilterInventoryCodec.decodeWithDiagnostics(json)
        assertEquals(PersistenceLoadOutcome.degraded, result.outcome)
        assertEquals(1, result.droppedRecordCount)
        assertEquals("First", result.snapshot.filterSets.single().name)
    }

    /** Duplicate ITEM ids inside one set collapse first-wins as well. */
    @Test fun duplicateItemIdsCollapseFirstWins() {
        val json = """
            {"schemaVersion":1,"filterSets":[{"id":"s","name":"Lee","color":"green","items":[
              {"id":"i","name":"First","kind":"fixed","value":3.0,"unit":"stops"},
              {"id":"i","name":"Second","kind":"fixed","value":4.0,"unit":"stops"}
            ]}]}
        """.trimIndent()
        val restored = FilterInventoryCodec.decode(json)!!.restoredInventory
        assertEquals("First", restored.filterSets.single().items.single().name)
    }

    @Test fun unknownSchemaVersionAndMalformedRootAreRejected() {
        assertNull(FilterInventoryCodec.decode("{not json"))
        assertNull(FilterInventoryCodec.decode("""{"schemaVersion":999,"filterSets":[]}"""))
        assertEquals(
            PersistenceLoadOutcome.versionRejected,
            FilterInventoryCodec.decodeWithDiagnostics(
                """{"schemaVersion":999,"filterSets":[]}""",
            ).outcome,
        )
    }

    /** An empty id or name cannot identify a Filter Set, so it is skipped. */
    @Test fun blankIdsAndNamesAreSkippedOnRestore() {
        val snapshot = PersistentFilterInventorySnapshot(
            listOf(
                PersistentFilterSetRecord(" ", "Lee", "green"),
                PersistentFilterSetRecord("s", "  ", "green"),
                PersistentFilterSetRecord("s2", "Kept", "green"),
            ),
        )
        assertEquals(listOf("Kept"), snapshot.restoredInventory.filterSets.map { it.name })
    }
}
