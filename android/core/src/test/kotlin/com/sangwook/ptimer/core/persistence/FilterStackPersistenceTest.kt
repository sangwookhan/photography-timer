// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.core.persistence

import com.sangwook.ptimer.core.exposure.CplExposureLossChoices
import com.sangwook.ptimer.core.exposure.FilterInventory
import com.sangwook.ptimer.core.exposure.FilterItem
import com.sangwook.ptimer.core.exposure.FilterItemBehavior
import com.sangwook.ptimer.core.exposure.FilterItemId
import com.sangwook.ptimer.core.exposure.FilterRegisteredValue
import com.sangwook.ptimer.core.exposure.FilterRowChoice
import com.sangwook.ptimer.core.exposure.FilterRowSelection
import com.sangwook.ptimer.core.exposure.FilterSet
import com.sangwook.ptimer.core.exposure.FilterSetColor
import com.sangwook.ptimer.core.exposure.FilterSetId
import com.sangwook.ptimer.core.exposure.FilterSource
import com.sangwook.ptimer.core.exposure.FilterStack
import com.sangwook.ptimer.core.exposure.FilterValueUnit
import com.sangwook.ptimer.core.exposure.FilterWheel
import com.sangwook.ptimer.core.exposure.FilterWheelSelection
import com.sangwook.ptimer.core.exposure.GndCalculationMode
import com.sangwook.ptimer.core.slots.CameraSlotId
import com.sangwook.ptimer.core.slots.PersistentFilterWheel
import com.sangwook.ptimer.core.slots.SlotCalculatorSnapshot
import com.sangwook.ptimer.core.slots.restoredFilterWheels
import com.sangwook.ptimer.core.slots.restoredLastFilterSource
import com.sangwook.ptimer.core.slots.writingFilterStack
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/**
 * Mixed-stack persistence (FILTER-PERSIST-001/002, FILTER-PLUS-004):
 * relaunch round-trip of the wheels and the last Filter Source, the
 * Standard-only downgrade fields, legacy restore, and stale-reference
 * recovery — all at the snapshot layer the calculator will write.
 */
class FilterStackPersistenceTest {

    private val nd1000 = FilterItem(
        "Big Stopper",
        FilterItemBehavior.Fixed(FilterRegisteredValue(1000.0, FilterValueUnit.filterFactor)),
        FilterItemId("i-nd1000"),
    )
    private val gnd = FilterItem(
        "GND",
        FilterItemBehavior.Gnd(FilterRegisteredValue(0.9, FilterValueUnit.opticalDensity)),
        FilterItemId("i-gnd"),
    )
    private val cpl = FilterItem(
        "CPL",
        FilterItemBehavior.Cpl(CplExposureLossChoices(listOf(1.0, 2.0, null))),
        FilterItemId("i-cpl"),
    )
    private val set = FilterSet(
        "Lee",
        FilterSetColor.red,
        listOf(nd1000, gnd, cpl),
        FilterSetId("s-lee"),
    )
    private val inventory = FilterInventory(listOf(set))
    private val setSource = FilterSource.FilterSet(set.id)

    private val base = SlotCalculatorSnapshot(
        shutterIndex = 3,
        ndIndex = 0,
        selectedFilmId = null,
        selectedProfileId = null,
    )

    private fun itemWheel(item: FilterItem, choice: FilterRowChoice = FilterRowChoice.Fixed) =
        FilterWheel(setSource, FilterWheelSelection.Item(FilterRowSelection(item.id, choice)))

    private fun roundTrip(snapshot: SlotCalculatorSnapshot): SlotCalculatorSnapshot {
        val session = PersistentSlotSession(
            activeSlotId = CameraSlotId.camera1,
            snapshots = mapOf(CameraSlotId.camera1 to snapshot),
        )
        val decoded = SlotSessionCodec.decode(SlotSessionCodec.encode(session))!!
        return decoded.snapshots.getValue(CameraSlotId.camera1)
    }

    @Test fun mixedStackAndLastSourceSurviveRelaunch() {
        val stack = FilterStack.validated(
            listOf(
                itemWheel(nd1000),
                itemWheel(gnd, FilterRowChoice.Gnd(GndCalculationMode.recordOnly)),
                FilterWheel.standard(6.6),
            ),
            inventory,
        )!!
        val restored = roundTrip(base.writingFilterStack(stack, setSource))

        assertEquals(stack.wheels, restored.restoredFilterWheels(inventory))
        assertEquals(setSource, restored.restoredLastFilterSource(inventory))
        assertEquals(
            "ND1000 restores as exactly 10 stops.",
            16.6,
            FilterStack.validated(restored.restoredFilterWheels(inventory), inventory)!!.effectiveStops,
            1e-9,
        )
    }

    @Test fun downgradeFieldsCarryStandardWheelsOnly() {
        val stack = FilterStack.validated(
            listOf(FilterWheel.standard(6.6), itemWheel(nd1000), FilterWheel.standard(3.0)),
            inventory,
        )!!
        val written = roundTrip(base.writingFilterStack(stack, setSource))

        assertEquals(listOf(6.6, 3.0), written.ndStack)
        assertEquals(7, written.ndIndex)
        assertEquals(6.6, written.ndStops!!, 0.0)
        assertEquals(3, written.filterStack!!.size)
        assertEquals(PersistentFilterWheel.FILTER_SET_SOURCE_KIND, written.lastFilterSourceKind)
        assertEquals(set.id.rawValue, written.lastFilterSetId)
    }

    @Test fun aStackWithoutStandardWheelsStillDegradesToOneStandardZeroWheel() {
        val stack = FilterStack.validated(listOf(itemWheel(nd1000)), inventory)!!
        val written = base.writingFilterStack(stack, setSource)

        assertEquals(listOf(0.0), written.ndStack)
        assertEquals(0, written.ndIndex)
        assertNull(written.ndStops)
    }

    @Test fun anUnresolvedFilterSetIsDroppedAndAMissingItemBecomesEmpty() {
        val unknownSet = FilterSetId.generate()
        val snapshot = base.copy(
            ndIndex = 2,
            ndStack = listOf(2.0),
            filterStack = listOf(
                PersistentFilterWheel(PersistentFilterWheel.STANDARD_SOURCE_KIND, stops = 2.0),
                PersistentFilterWheel(
                    PersistentFilterWheel.FILTER_SET_SOURCE_KIND,
                    filterSetId = unknownSet.rawValue,
                ),
                PersistentFilterWheel(
                    PersistentFilterWheel.FILTER_SET_SOURCE_KIND,
                    filterSetId = set.id.rawValue,
                    itemId = "gone",
                    rowKind = "fixed",
                ),
            ),
            lastFilterSourceKind = PersistentFilterWheel.FILTER_SET_SOURCE_KIND,
            lastFilterSetId = unknownSet.rawValue,
        )
        val restored = roundTrip(snapshot)

        assertEquals(
            listOf(FilterWheel.standard(2.0), FilterWheel.empty(set.id)),
            restored.restoredFilterWheels(inventory),
        )
        assertEquals(
            "A vanished last source falls back to Standard.",
            FilterSource.Standard,
            restored.restoredLastFilterSource(inventory),
        )
    }

    @Test fun aRemovedCplChoiceRestoresAsEmptyNeverAnotherChoice() {
        val stack = FilterStack.validated(
            listOf(itemWheel(cpl, FilterRowChoice.CplLoss(2.0))),
            inventory,
        )!!
        val restored = roundTrip(base.writingFilterStack(stack, setSource))

        val editedCpl = FilterItem(
            "CPL",
            FilterItemBehavior.Cpl(CplExposureLossChoices(listOf(1.0, null, null))),
            cpl.id,
        )
        val edited = FilterInventory(
            listOf(FilterSet("Lee", FilterSetColor.red, listOf(editedCpl), set.id)),
        )
        assertEquals(
            listOf(FilterWheel.empty(set.id)),
            restored.restoredFilterWheels(edited),
        )
    }

    @Test fun aCorruptedMixedStackFallsBackToTheLegacyStandardPath() {
        // More than four wheels is corruption, not recoverable state.
        val tooMany = base.copy(
            ndIndex = 4,
            ndStack = listOf(4.0),
            filterStack = List(5) {
                PersistentFilterWheel(PersistentFilterWheel.STANDARD_SOURCE_KIND, stops = 0.0)
            },
        )
        assertEquals(
            listOf(FilterWheel.standard(4.0)),
            roundTrip(tooMany).restoredFilterWheels(inventory),
        )

        // An off-ladder Standard wheel is structurally corrupted too.
        val offLadder = base.copy(
            ndIndex = 4,
            ndStack = listOf(4.0),
            filterStack = listOf(
                PersistentFilterWheel(PersistentFilterWheel.STANDARD_SOURCE_KIND, stops = 4.4),
            ),
        )
        assertEquals(
            listOf(FilterWheel.standard(4.0)),
            roundTrip(offLadder).restoredFilterWheels(inventory),
        )
    }

    @Test fun aLegacyPayloadWithoutTheFilterKeysRestoresTheStandardStack() {
        val json = """
            {"activeSlotId":"camera1","snapshots":{"camera1":{"shutterIndex":3,
            "ndIndex":10,"selectedFilmId":null,"selectedProfileId":null,
            "ndStack":[10.0,6.6]}},"customNames":{},"schemaVersion":1}
        """.trimIndent().replace("\n", "")
        val snapshot = SlotSessionCodec.decode(json)!!.snapshots.getValue(CameraSlotId.camera1)

        assertNull(snapshot.filterStack)
        assertEquals(
            listOf(FilterWheel.standard(10.0), FilterWheel.standard(6.6)),
            snapshot.restoredFilterWheels(inventory),
        )
        assertEquals(FilterSource.Standard, snapshot.restoredLastFilterSource(inventory))
    }

    @Test fun aLegacyScalarOnlyPayloadRestoresOneStandardWheel() {
        val snapshot = base.copy(ndIndex = 5)
        assertEquals(
            listOf(FilterWheel.standard(5.0)),
            snapshot.restoredFilterWheels(FilterInventory.empty),
        )
    }
}
