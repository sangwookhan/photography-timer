// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.app.vm

import com.sangwook.ptimer.core.catalog.LaunchPresetFilmCatalogV2
import com.sangwook.ptimer.core.persistence.PersistentSlotSession
import com.sangwook.ptimer.core.slots.CameraSlotId
import com.sangwook.ptimer.core.slots.SlotCalculatorSnapshot
import com.sangwook.ptimer.core.slots.canonicalNdStackStops
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * PTIMER-199 M3: the ND wheel stack on the Android controller —
 * per-wheel selections applied as ONE SET at quiescence, the stable
 * sort with identity following the permutation, the C1 add rule,
 * fire-time cleanup judgment, overscroll removal by identity, and
 * stack persistence with the legacy-maximum scalar. Mirrors the iOS
 * NDWheelAutoRemovalTests / stack state tests at controller level.
 */
class NdWheelStackControllerTest {

    private val films = LaunchPresetFilmCatalogV2.films

    private fun controller(initial: PersistentSlotSession? = null) =
        CalculatorController(films = films, initialSession = initial)

    private fun wheelStops(c: CalculatorController): List<Double> =
        c.exportSession().snapshots.getValue(c.state.value.slots.first { it.isActive }.id)
            .canonicalNdStackStops()

    /** Ladder index of [stops] on wheel [wheel] of the CURRENT state. */
    private fun ladderIndex(c: CalculatorController, wheel: Int, label: String): Int =
        c.state.value.ndWheels[wheel].labels.indexOf(label).also {
            require(it >= 0) { "label $label not on wheel $wheel ladder" }
        }

    private fun commitStops(c: CalculatorController, wheel: Int, label: String) {
        val id = c.state.value.ndWheels[wheel].id
        c.setNdWheelActive(id, true)
        c.setNdWheelValue(id, ladderIndex(c, wheel, label))
        c.setNdWheelActive(id, false)
    }

    // MARK: defaults and identity

    @Test
    fun startsWithASingleZeroWheelAndNonIndexIdentity() {
        val s = controller().state.value
        assertEquals(1, s.ndWheels.size)
        assertTrue("IDs start at 101 (never index-like)", s.ndWheels[0].id >= 101)
        assertTrue(s.showsAddNdWheel)
        assertTrue(s.canAddNdWheel)
        assertFalse(s.canRemoveEmptyNdWheel)
        assertNull(s.ndTotalStopsText)
    }

    // MARK: set commit

    @Test
    fun commitSortsDescendingAndIdentityFollowsThePermutation() {
        val c = controller()
        c.addNdWheel()
        commitStops(c, 0, "6")
        val sixId = c.state.value.ndWheels[0].id
        // Commit a larger value on the SECOND wheel: it sorts to the
        // front and carries its identity there.
        commitStops(c, 1, "13")
        val state = c.state.value
        assertEquals(listOf(13.0, 6.0), wheelStops(c))
        assertEquals("13", state.ndWheels[0].labels[state.ndWheels[0].selectedIndex])
        assertEquals(sixId, state.ndWheels[1].id)
    }

    @Test
    fun setCommitDefersWhileAnotherWheelIsActive() {
        val c = controller()
        c.addNdWheel()
        val idA = c.state.value.ndWheels[0].id
        val idB = c.state.value.ndWheels[1].id
        c.setNdWheelActive(idA, true)
        c.setNdWheelActive(idB, true)

        c.setNdWheelValue(idA, ladderIndex(c, 0, "4"))
        c.setNdWheelActive(idA, false)
        // B is still moving: the committed stack must not change.
        assertEquals(listOf(0.0, 0.0), wheelStops(c))
        // The display already reflects A's selection.
        assertEquals("4", c.state.value.ndTotalStopsText)

        c.setNdWheelValue(idB, ladderIndex(c, 1, "3"))
        c.setNdWheelActive(idB, false)
        assertEquals(listOf(4.0, 3.0), wheelStops(c))
    }

    @Test
    fun overBudgetSelectionIsRejectedInSettleOrder() {
        val c = controller()
        c.addNdWheel()
        val idA = c.state.value.ndWheels[0].id
        val idB = c.state.value.ndWheels[1].id
        c.setNdWheelActive(idA, true)
        c.setNdWheelActive(idB, true)
        c.setNdWheelValue(idA, ladderIndex(c, 0, "20"))
        c.setNdWheelValue(idB, ladderIndex(c, 1, "20"))
        c.setNdWheelActive(idA, false)
        c.setNdWheelActive(idB, false)

        assertEquals(
            "First-settled wins; the second selection would exceed 30 and reverts.",
            listOf(20.0, 0.0),
            wheelStops(c),
        )
    }

    @Test
    fun overBudgetRejectionFollowsSettleOrderNotChangeOrder() {
        // B's value changes LAST but A settles FIRST: the barrier must
        // apply A first (settle order), so A's 20 wins and B reverts —
        // last-change order would wrongly keep B.
        val c = controller()
        c.addNdWheel()
        val idA = c.state.value.ndWheels[0].id
        val idB = c.state.value.ndWheels[1].id
        c.setNdWheelActive(idA, true)
        c.setNdWheelActive(idB, true)
        c.setNdWheelValue(idB, ladderIndex(c, 1, "20"))
        c.setNdWheelValue(idA, ladderIndex(c, 0, "20"))

        c.setNdWheelActive(idA, false)
        c.setNdWheelActive(idB, false)

        assertEquals(listOf(20.0, 0.0), wheelStops(c))
        assertEquals("The surviving 20 must be A's wheel.", idA, c.state.value.ndWheels[0].id)

        // Same shape, other side: A's value changes last, B settles
        // first — B wins.
        val c2 = controller()
        c2.addNdWheel()
        val id2A = c2.state.value.ndWheels[0].id
        val id2B = c2.state.value.ndWheels[1].id
        c2.setNdWheelActive(id2A, true)
        c2.setNdWheelActive(id2B, true)
        c2.setNdWheelValue(id2B, ladderIndex(c2, 1, "20"))
        c2.setNdWheelValue(id2A, ladderIndex(c2, 0, "20"))

        c2.setNdWheelActive(id2B, false)
        c2.setNdWheelActive(id2A, false)

        assertEquals(listOf(20.0, 0.0), wheelStops(c2))
        assertEquals("The surviving 20 must be B's wheel.", id2B, c2.state.value.ndWheels[0].id)
    }

    @Test
    fun cleanupActionAvailabilityRequiresAQuietMachine() {
        val c = controller()
        c.addNdWheel()
        commitStops(c, 0, "10")
        // [10, 0]: structurally removable AND quiet — both flags on.
        assertTrue(c.state.value.canRemoveEmptyNdWheel)
        assertTrue(c.state.value.canCleanupEmptyNdWheels)

        // A moving wheel keeps the timer flag (fire-time judgment) but
        // must withdraw the TalkBack action's availability.
        val zeroId = c.state.value.ndWheels[1].id
        c.setNdWheelActive(zeroId, true)
        assertTrue(c.state.value.canRemoveEmptyNdWheel)
        assertFalse(c.state.value.canCleanupEmptyNdWheels)

        c.setNdWheelActive(zeroId, false)
        assertTrue(c.state.value.canCleanupEmptyNdWheels)
    }

    @Test
    fun maximumMarkerFollowsTheLiveTotal() {
        val c = controller()
        c.addNdWheel()
        commitStops(c, 0, "29")
        // Pending 1 on the second wheel: the live total hits 30, so the
        // text and the Maximum marker must flip together, pre-commit.
        val id = c.state.value.ndWheels[1].id
        c.setNdWheelActive(id, true)
        c.setNdWheelValue(id, ladderIndex(c, 1, "1"))
        assertEquals("30", c.state.value.ndTotalStopsText)
        assertTrue(c.state.value.ndTotalIsMaximum)

        c.setNdWheelActive(id, false)
        assertTrue(c.state.value.ndTotalIsMaximum)
    }

    @Test
    fun saturatedSetShedsLeftoverZerosInTheSameCommit() {
        val c = controller()
        c.addNdWheel()
        c.addNdWheel()
        commitStops(c, 0, "29")
        assertEquals(3, c.state.value.ndWheels.size)

        commitStops(c, 1, "1")

        assertEquals(listOf(29.0, 1.0), wheelStops(c))
        assertTrue(c.state.value.ndTotalIsMaximum)
    }

    // MARK: add rule (C1) and structural gate

    @Test
    fun addRefusedWhenNewWheelCouldHoldNoValue() {
        // 16.6 + 13 = 29.6 leaves 0.4 stop — below every ladder value
        // above 0, so C1 hides and refuses the add even though budget
        // remains.
        val c = controller()
        c.addNdWheel()
        commitStops(c, 0, "16.6")
        commitStops(c, 1, "13")
        assertFalse(c.state.value.showsAddNdWheel)
        c.addNdWheel()
        assertEquals(2, c.state.value.ndWheels.size)
    }

    @Test
    fun addRefusedAtSaturationAndWhileAWheelMoves() {
        val c = controller()
        c.addNdWheel()
        commitStops(c, 0, "29")
        commitStops(c, 1, "1")
        // Saturated at 30: C1 hides and refuses the add.
        assertFalse(c.state.value.showsAddNdWheel)
        c.addNdWheel()
        assertEquals(2, c.state.value.ndWheels.size)

        // While a wheel moves, availability drops but presence stays.
        val c2 = controller()
        c2.addNdWheel()
        val id = c2.state.value.ndWheels[1].id
        c2.setNdWheelActive(id, true)
        assertTrue(c2.state.value.showsAddNdWheel)
        c2.setNdWheelValue(id, ladderIndex(c2, 1, "3"))
        assertFalse(c2.state.value.canAddNdWheel)
        c2.addNdWheel()
        assertEquals(2, c2.state.value.ndWheels.size)
    }

    @Test
    fun wiggleAndReturnReleaseRestoresAddAvailability() {
        // Field capture 2026-07-17 ([8, 5, 4], + dimmed): touching a
        // wheel and returning to its committed value leaves nothing to
        // commit, so the release publishes no commit — availability
        // must still flip back instead of showing a stale busy state.
        val c = controller()
        c.addNdWheel()
        c.addNdWheel()
        commitStops(c, 0, "8")
        commitStops(c, 1, "5")
        commitStops(c, 2, "4")
        assertEquals(listOf(8.0, 5.0, 4.0), wheelStops(c))
        assertTrue(c.state.value.canAddNdWheel)

        val id = c.state.value.ndWheels[0].id
        c.setNdWheelActive(id, true)
        c.setNdWheelValue(id, ladderIndex(c, 0, "9"))
        assertFalse(c.state.value.canAddNdWheel)
        // Wiggle back to the committed 8: the pending entry clears.
        c.setNdWheelValue(id, ladderIndex(c, 0, "8"))
        assertFalse("Still under the finger.", c.state.value.canAddNdWheel)

        c.setNdWheelActive(id, false)
        assertTrue("Release must re-enable Add.", c.state.value.canAddNdWheel)
        assertEquals(listOf(8.0, 5.0, 4.0), wheelStops(c))
    }

    @Test
    fun quickSpinPlusOverscrollRemovalLeavesAQuietMachine() {
        // Field repro 2026-07-17: from [20, 5, 4, 0], fling the big
        // wheel down to 7 and pull the zero wheel out while the fling
        // is still settling. Whatever the interleaving, the end state
        // must be [7, 5, 4] with the machine quiet and Add available.
        val c = controller()
        c.addNdWheel()
        c.addNdWheel()
        c.addNdWheel()
        commitStops(c, 0, "20")
        commitStops(c, 1, "5")
        commitStops(c, 2, "4")
        val bigId = c.state.value.ndWheels[0].id
        val zeroId = c.state.value.ndWheels[3].id

        // Fling starts; the zero wheel is grabbed before it settles.
        c.setNdWheelActive(bigId, true)
        c.setNdWheelValue(bigId, ladderIndex(c, 0, "7"))
        c.setNdWheelActive(zeroId, true)
        // Pull released while the big wheel still moves: refused.
        c.removeNdWheelFromOverscroll(zeroId)
        assertEquals(4, c.state.value.ndWheels.size)

        // Big wheel settles (commit still deferred: zero wheel active).
        c.setNdWheelActive(bigId, false)
        assertEquals(listOf(20.0, 5.0, 4.0, 0.0), wheelStops(c))
        // Pull released while the big wheel's selection is still
        // pending: refused — a removal must never flush another
        // wheel's pending commit.
        c.removeNdWheelFromOverscroll(zeroId)
        assertEquals(4, c.state.value.ndWheels.size)
        // The zero wheel goes quiet, the set commits normally.
        c.setNdWheelActive(zeroId, false)
        assertEquals(listOf(7.0, 5.0, 4.0, 0.0), wheelStops(c))
        // A second pull on the now-quiet machine succeeds.
        c.removeNdWheelFromOverscroll(zeroId)

        assertEquals(listOf(7.0, 5.0, 4.0), wheelStops(c))
        assertTrue("Machine must be quiet after the dust settles.", c.state.value.canAddNdWheel)
        assertFalse(c.runNdCleanupIfQuiet())

        // Same story, reversed tail: the zero wheel releases first and
        // the removal happens via the delayed cleanup instead.
        val c2 = controller()
        c2.addNdWheel()
        c2.addNdWheel()
        c2.addNdWheel()
        commitStops(c2, 0, "20")
        commitStops(c2, 1, "5")
        commitStops(c2, 2, "4")
        val big2 = c2.state.value.ndWheels[0].id
        val zero2 = c2.state.value.ndWheels[3].id
        c2.setNdWheelActive(big2, true)
        c2.setNdWheelValue(big2, ladderIndex(c2, 0, "7"))
        c2.setNdWheelActive(zero2, true)
        c2.removeNdWheelFromOverscroll(zero2)
        c2.setNdWheelActive(zero2, false)
        c2.setNdWheelActive(big2, false)

        assertEquals(listOf(7.0, 5.0, 4.0, 0.0), wheelStops(c2))
        // Four wheels still present: Add is correctly absent (full
        // stack), but the machine itself must be quiet — the pending
        // flush must not be stuck behind the refused removal.
        assertFalse(c2.state.value.showsAddNdWheel)
        assertTrue(c2.runNdCleanupIfQuiet())
        assertEquals(listOf(7.0, 5.0, 4.0), wheelStops(c2))
        assertTrue(c2.state.value.canAddNdWheel)
    }

    // MARK: ViewModel-scope-owned cleanup timer (PTIMER-223 handoff)

    @Test
    fun ownedTimerCleansAnUntouchedZeroAfterTheGracePeriod() = runTest {
        val c = CalculatorController(films = films, ndCleanupScope = backgroundScope)
        c.addNdWheel()
        commitStops(c, 0, "10")
        // [10, 0]: the commit write armed the timer.
        advanceTimeBy(4_001)
        runCurrent()
        assertEquals(listOf(10.0), wheelStops(c))
    }

    @Test
    fun ownedTimerDefersUnderAFingerThenCleansOnTheNextFire() = runTest {
        val c = CalculatorController(films = films, ndCleanupScope = backgroundScope)
        c.addNdWheel()
        commitStops(c, 0, "10")
        val zeroId = c.state.value.ndWheels[1].id
        c.setNdWheelActive(zeroId, true)
        advanceTimeBy(4_001)
        runCurrent()
        assertEquals("Fire is refused under the finger.", 2, c.state.value.ndWheels.size)

        c.setNdWheelActive(zeroId, false)
        advanceTimeBy(4_001)
        runCurrent()
        assertEquals(listOf(10.0), wheelStops(c))
    }

    @Test
    fun structuralChangeRestartsTheGracePeriodForNewZeros() = runTest {
        val c = CalculatorController(films = films, ndCleanupScope = backgroundScope)
        c.addNdWheel()
        commitStops(c, 0, "10")
        advanceTimeBy(3_900)
        runCurrent()
        // A wheel added just before the old fire time must get the
        // FULL grace period — the add re-arms the timer.
        c.addNdWheel()
        advanceTimeBy(200)
        runCurrent()
        assertEquals(3, c.state.value.ndWheels.size)

        advanceTimeBy(3_900)
        runCurrent()
        assertEquals(listOf(10.0), wheelStops(c))
    }

    // MARK: cleanup (fire-time judgment)

    @Test
    fun fireTimeCleanupRunsOnlyWhenQuiet() {
        val c = controller()
        c.addNdWheel()
        commitStops(c, 0, "10")
        // [10, 0]: cleanable — but a moving wheel defers the fire.
        val zeroId = c.state.value.ndWheels[1].id
        c.setNdWheelActive(zeroId, true)
        assertFalse(c.runNdCleanupIfQuiet())
        assertEquals(2, c.state.value.ndWheels.size)

        c.setNdWheelActive(zeroId, false)
        assertTrue(c.runNdCleanupIfQuiet())
        assertEquals(listOf(10.0), wheelStops(c))
    }

    @Test
    fun cleanupRemovesAllZerosButKeepsOneWheelWhenAllZero() {
        val c = controller()
        c.addNdWheel()
        c.addNdWheel()
        commitStops(c, 0, "7")
        c.cleanupEmptyNdWheels()
        assertEquals(listOf(7.0), wheelStops(c))

        val allZero = controller()
        allZero.addNdWheel()
        allZero.addNdWheel()
        allZero.cleanupEmptyNdWheels()
        assertEquals(listOf(0.0), wheelStops(allZero))
    }

    // MARK: overscroll removal

    @Test
    fun overscrollRemovesExactlyThePulledWheel() {
        val c = controller()
        c.addNdWheel()
        c.addNdWheel()
        commitStops(c, 0, "10")
        // [10, 0, 0]
        val pulledId = c.state.value.ndWheels[1].id
        val survivorId = c.state.value.ndWheels[2].id
        c.removeNdWheelFromOverscroll(pulledId)

        val state = c.state.value
        assertEquals(listOf(10.0, 0.0), wheelStops(c))
        assertEquals(survivorId, state.ndWheels[1].id)
    }

    @Test
    fun overscrollRefusalsMatchTheRules() {
        val c = controller()
        c.addNdWheel()
        commitStops(c, 0, "10")
        val tenId = c.state.value.ndWheels[0].id
        val zeroId = c.state.value.ndWheels[1].id

        // Refused while another wheel is in motion.
        c.setNdWheelActive(tenId, true)
        c.removeNdWheelFromOverscroll(zeroId)
        assertEquals(2, c.state.value.ndWheels.size)
        c.setNdWheelActive(tenId, false)

        // Non-zero wheel: refused. Last wheel: refused even at 0.
        c.removeNdWheelFromOverscroll(tenId)
        assertEquals(2, c.state.value.ndWheels.size)
        c.removeNdWheelFromOverscroll(zeroId)
        assertEquals(listOf(10.0), wheelStops(c))
        c.setNdIndex(0)
        c.removeNdWheelFromOverscroll(c.state.value.ndWheels[0].id)
        assertEquals(listOf(0.0), wheelStops(c))
    }

    @Test
    fun refusedOverscrollPullMutatesNothing() {
        // A pull refused because another wheel's selection is pending
        // must leave every transient untouched: the pending survives
        // and commits normally afterwards.
        val c = controller()
        c.addNdWheel()
        commitStops(c, 0, "10")
        val tenId = c.state.value.ndWheels[0].id
        val zeroId = c.state.value.ndWheels[1].id

        c.setNdWheelActive(tenId, true)
        c.setNdWheelValue(tenId, ladderIndex(c, 0, "12"))
        c.removeNdWheelFromOverscroll(zeroId)
        assertEquals("Refused: pending selection open.", 2, c.state.value.ndWheels.size)

        c.setNdWheelActive(tenId, false)
        assertEquals(
            "The pending selection was untouched by the refused pull.",
            listOf(12.0, 0.0),
            wheelStops(c),
        )
    }

    // MARK: slot switching under late signals

    @Test
    fun lateWheelCallbacksAfterSlotSwitchAreInert() {
        // The pager switches slots while camera1's wheel is mid-fling:
        // late callbacks carrying the OLD slot's wheel identities must
        // neither touch camera2's stack nor disturb the active slot,
        // and camera1's in-flight selection is discarded.
        val c = controller()
        c.addNdWheel()
        val idA = c.state.value.ndWheels[0].id
        c.setNdWheelActive(idA, true)
        c.setNdWheelValue(idA, ladderIndex(c, 0, "7"))

        c.selectSlot(CameraSlotId.camera2)

        c.setNdWheelValue(idA, 3)
        c.setNdWheelActive(idA, false)

        assertEquals(
            "Late stale-identity callbacks must not move the active slot.",
            CameraSlotId.camera2,
            c.state.value.slots.first { it.isActive }.id,
        )
        assertEquals("camera2's stack is untouched.", listOf(0.0), wheelStops(c))
        assertTrue("The machine is quiet on camera2.", c.state.value.canAddNdWheel)

        c.selectSlot(CameraSlotId.camera1)
        assertEquals(
            "camera1's in-flight selection was discarded with the switch.",
            listOf(0.0, 0.0),
            wheelStops(c),
        )
    }

    // MARK: persistence and restore

    @Test
    fun stackPersistsAndLegacyScalarCarriesTheMaximumWheel() {
        val c = controller()
        c.addNdWheel()
        commitStops(c, 0, "10")
        commitStops(c, 1, "6")

        val exported = c.exportSession()
        val snapshot = exported.snapshots.getValue(CameraSlotId.camera1)
        assertEquals(listOf(10.0, 6.0), snapshot.ndStack)
        assertEquals(10, snapshot.ndIndex)

        // Relaunch: the stack restores wholesale.
        val restored = controller(initial = exported)
        assertEquals(listOf(10.0, 6.0), wheelStops(restored))
        assertEquals(2, restored.state.value.ndWheels.size)
    }

    @Test
    fun invalidPersistedStackFallsBackToTheLegacyScalar() {
        val bad = PersistentSlotSession(
            activeSlotId = CameraSlotId.camera1,
            snapshots = mapOf(
                CameraSlotId.camera1 to SlotCalculatorSnapshot(
                    shutterIndex = 10,
                    ndIndex = 7,
                    selectedFilmId = null,
                    selectedProfileId = null,
                    ndStack = listOf(20.0, 11.0),  // over 30: rejected
                ),
            ),
            customNames = emptyMap(),
        )
        val c = controller(initial = bad)
        assertEquals(listOf(7.0), wheelStops(c))
    }

    @Test
    fun slotSwitchDiscardsInFlightSelections() {
        val c = controller()
        c.addNdWheel()
        val id = c.state.value.ndWheels[1].id
        c.setNdWheelActive(id, true)
        c.setNdWheelValue(id, ladderIndex(c, 1, "5"))

        c.selectSlot(CameraSlotId.camera2)
        c.selectSlot(CameraSlotId.camera1)

        assertEquals(
            "The uncommitted 5 was discarded with the outgoing slot state.",
            listOf(0.0, 0.0),
            wheelStops(c),
        )
    }

    @Test
    fun legacySetNdIndexCollapsesTheStack() {
        val c = controller()
        c.addNdWheel()
        commitStops(c, 0, "10")
        c.setNdIndex(5)
        assertEquals(listOf(5.0), wheelStops(c))
        assertEquals(1, c.state.value.ndWheels.size)
    }
}
