// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.app.vm

import com.sangwook.ptimer.app.persistence.OrderedPersistenceWriter
import com.sangwook.ptimer.core.persistence.CameraListPersistenceController
import com.sangwook.ptimer.core.persistence.CameraNameSequenceLoadResult
import com.sangwook.ptimer.core.persistence.CameraNameSequenceStoring
import com.sangwook.ptimer.core.persistence.InMemoryCameraNameSequenceStore
import com.sangwook.ptimer.core.persistence.InMemoryManagedCameraListStore
import com.sangwook.ptimer.core.persistence.ManagedCameraListLoadResult
import com.sangwook.ptimer.core.persistence.ManagedCameraListStoring
import com.sangwook.ptimer.core.persistence.PersistentManagedCameraList
import com.sangwook.ptimer.core.persistence.PersistentSlotSession
import com.sangwook.ptimer.core.persistence.SlotSessionStoring
import com.sangwook.ptimer.core.slots.CameraSlotId
import com.sangwook.ptimer.core.slots.SlotCalculatorSnapshot
import com.sangwook.ptimer.core.timer.TimerIdentity
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The camera-list commands end to end at the state layer: calculator
 * controller + [CameraListManager] + persistence controller over in-memory
 * stores (CAMERA-001..007, CAMERA-003 sequence, CAMERA-PERSIST-001..007).
 * Writes run inline, so a relaunch reads exactly what was committed.
 */
class CameraListManagerTest {

    private class Events {
        val items = mutableListOf<String>()
    }

    private class RecordingManaged(
        private val events: Events,
        val delegate: InMemoryManagedCameraListStore = InMemoryManagedCameraListStore(),
    ) : ManagedCameraListStoring by delegate {
        override fun save(payload: PersistentManagedCameraList): Boolean {
            events.items += "managed"
            return delegate.save(payload)
        }
    }

    private class RecordingSequence(
        private val events: Events,
        val delegate: InMemoryCameraNameSequenceStore = InMemoryCameraNameSequenceStore(),
    ) : CameraNameSequenceStoring by delegate {
        override fun save(nextNumber: Int): Boolean {
            events.items += "sequence=$nextNumber"
            return delegate.save(nextNumber)
        }
    }

    /** Acknowledges writes but never commits them: a kill before the commit. */
    private class LossyManaged : ManagedCameraListStoring {
        override fun load() = ManagedCameraListLoadResult.Absent
        override fun save(payload: PersistentManagedCameraList) = true
    }

    private class LegacyStore(private val session: PersistentSlotSession?) : SlotSessionStoring {
        override fun loadSession() = session
        override fun saveSession(session: PersistentSlotSession) = Unit
        override fun clearSession() = Unit
    }

    private object ImmediateWriter : OrderedPersistenceWriter {
        override fun submit(write: () -> Unit) = write()
        override suspend fun <T> readOrdered(read: () -> T): T = read()
    }

    private class Stores(
        val managed: ManagedCameraListStoring = InMemoryManagedCameraListStore(),
        val sequence: CameraNameSequenceStoring = InMemoryCameraNameSequenceStore(),
        val legacy: SlotSessionStoring = LegacyStore(null),
    )

    private class Launch(stores: Stores) {
        val started = mutableListOf<TimerIdentity>()
        val persistence = CameraListPersistenceController(stores.managed, stores.legacy, stores.sequence, defaultName = { "Camera $it" })
        private val restored = persistence.restore()
        val calculator = CalculatorController(
            films = emptyList(),
            onStart = { _, identity -> started += identity },
            initialCameraList = restored.list,
        )
        val manager = CameraListManager(calculator, persistence, ImmediateWriter) { "Camera $it" }

        init {
            // What the owner does on first launch after a fresh install or migration.
            if (restored.needsInitialSave) manager.persistCalculatorContext()
        }

        val names get() = calculator.state.value.cameras.map { it.name }
        val shown get() = calculator.state.value.slots.map { it.id }
        val active get() = calculator.state.value.slots.firstOrNull { it.isActive }?.id
        fun nameOf(id: CameraSlotId?) = id?.let { calculator.cameraIdentity(it)?.displayName }
        fun add(): CameraSlotId? = runBlocking { manager.addCamera() }
    }

    private fun launch(stores: Stores = Stores()) = Launch(stores)

    private val shot = SlotCalculatorSnapshot(shutterIndex = 11, ndIndex = 0, selectedFilmId = null, selectedProfileId = null)

    private fun legacySession(custom: Map<CameraSlotId, String> = emptyMap()) = PersistentSlotSession(
        activeSlotId = CameraSlotId.camera2,
        snapshots = mapOf(CameraSlotId.camera1 to shot),
        customNames = custom,
    )

    // --- Commands ---

    @Test
    fun anAddedCameraBecomesActiveWithFreshCalculatorDefaults() {
        val l = launch()
        l.calculator.setShutterIndex(3)
        val added = l.add()!!
        assertEquals("Camera 5", l.nameOf(added))
        assertEquals(added, l.active)
        assertEquals(5, l.shown.size)
        assertEquals(l.calculator.state.value.shutterLabels.indexOf("1/30"), l.calculator.state.value.shutterIndex)
        l.calculator.selectSlot(CameraSlotId.camera1)
        assertEquals(3, l.calculator.state.value.shutterIndex)
    }

    @Test
    fun renameKeepsStateAndRejectsBlankAndUnknown() {
        val l = launch()
        l.calculator.setShutterIndex(4)
        assertTrue(l.manager.renameCamera(CameraSlotId.camera1, "  Leica  "))
        assertEquals("Leica", l.calculator.state.value.activeSlotName)
        assertEquals(4, l.calculator.state.value.shutterIndex)
        assertFalse(l.manager.renameCamera(CameraSlotId.camera1, "   "))
        assertFalse(l.manager.renameCamera(CameraSlotId("missing"), "X"))
        assertEquals("Leica", l.calculator.state.value.activeSlotName)
    }

    @Test
    fun hidingTheActiveCameraLoadsTheNextCamerasOwnState() {
        val l = launch()
        l.calculator.setShutterIndex(4)
        l.calculator.selectSlot(CameraSlotId.camera2)
        l.calculator.setShutterIndex(9)
        l.manager.setCameraDisplayed(CameraSlotId.camera2, false)
        assertEquals(CameraSlotId.camera3, l.active)
        assertEquals(l.calculator.state.value.shutterLabels.indexOf("1/30"), l.calculator.state.value.shutterIndex)
        // Hidden camera keeps its state while hidden and after showing.
        l.manager.setCameraDisplayed(CameraSlotId.camera2, true)
        assertEquals(CameraSlotId.camera3, l.active)
        l.calculator.selectSlot(CameraSlotId.camera2)
        assertEquals(9, l.calculator.state.value.shutterIndex)
    }

    @Test
    fun selectingAHiddenCameraIsIgnored() {
        val l = launch()
        l.manager.setCameraDisplayed(CameraSlotId.camera3, false)
        l.calculator.selectSlot(CameraSlotId.camera3)
        assertEquals(CameraSlotId.camera1, l.active)
    }

    @Test
    fun reorderChangesThePagerOrderAndKeepsEveryCamerasState() {
        val l = launch()
        l.calculator.setShutterIndex(4)
        l.manager.moveCamera(CameraSlotId.camera1, 2)
        assertEquals(listOf(CameraSlotId.camera2, CameraSlotId.camera3, CameraSlotId.camera1, CameraSlotId.camera4), l.shown)
        assertEquals(CameraSlotId.camera1, l.active)
        assertEquals(4, l.calculator.state.value.shutterIndex)
    }

    @Test
    fun deletingTheActiveCameraLoadsTheNextAndDropsItsState() {
        val l = launch()
        l.calculator.setShutterIndex(4)
        l.manager.deleteCameras(setOf(CameraSlotId.camera1))
        assertEquals(CameraSlotId.camera2, l.active)
        assertFalse(CameraSlotId.camera1 in l.shown)
        assertNull(l.calculator.exportCameraList().snapshots[CameraSlotId.camera1])
    }

    @Test
    fun bulkHideAndBulkDeleteApplyTogether() {
        val l = launch()
        l.manager.hideCameras(setOf(CameraSlotId.camera1, CameraSlotId.camera2))
        assertEquals(CameraSlotId.camera3, l.active)
        l.manager.deleteCameras(setOf(CameraSlotId.camera3, CameraSlotId.camera4))
        assertNull(l.active)
        assertEquals(2, l.names.size)
        assertTrue(l.shown.isEmpty())
    }

    @Test
    fun anEmptyPagerRefusesCalculatorBoundTimersThatAllowedOnesStillStart() {
        val l = launch()
        l.calculator.selectFilm(null)
        l.calculator.startFromAdjusted()
        assertEquals(1, l.started.size)
        l.manager.hideCameras(CameraSlotId.legacyOrdered.toSet())
        l.calculator.start()
        l.calculator.startFromAdjusted()
        l.calculator.startFromCorrected()
        l.calculator.setTargetShutter(30.0)
        l.calculator.startFromTarget()
        assertEquals(1, l.started.size)
    }

    @Test
    fun deletingEveryCameraYieldsAnEmptyListThatAddingRecovers() {
        val l = launch()
        l.manager.deleteCameras(CameraSlotId.legacyOrdered.toSet())
        assertTrue(l.names.isEmpty())
        val added = l.add()!!
        assertEquals(listOf(added), l.shown)
        assertEquals("Camera 5", l.nameOf(added))
    }

    @Test
    fun timersKeepTheCapturedCameraAfterEveryListEdit() {
        val l = launch()
        l.manager.renameCamera(CameraSlotId.camera1, "Nikon F3")
        l.calculator.startFromAdjusted()
        val captured = l.started.single()
        assertEquals("camera1", captured.cameraId)
        assertEquals("Nikon F3", captured.cameraName)
        assertEquals("C1", captured.slotLabel)
        l.manager.renameCamera(CameraSlotId.camera1, "Renamed")
        l.manager.moveCamera(CameraSlotId.camera1, 3)
        l.manager.setCameraDisplayed(CameraSlotId.camera1, false)
        l.manager.deleteCameras(setOf(CameraSlotId.camera1))
        assertEquals("Nikon F3", captured.cameraName)
        assertTrue(captured.title.startsWith("Nikon F3"))
        // A timer started after a rename captures the new name.
        l.manager.renameCamera(CameraSlotId.camera2, "Rolleiflex")
        l.calculator.selectSlot(CameraSlotId.camera2)
        l.calculator.startFromAdjusted()
        assertEquals("Rolleiflex", l.started.last().cameraName)
    }

    @Test
    fun aGeneratedCamerasTimerGetsABadgeFromTheCapturedName() {
        val l = launch()
        l.add()
        l.calculator.startFromAdjusted()
        assertEquals("C5", l.started.single().slotLabel)
        assertEquals("Camera 5", l.started.single().cameraName)
    }

    @Test
    fun theWholeListSurvivesRelaunchIncludingHiddenCamerasAndNoActiveCamera() {
        val stores = Stores()
        val first = launch(stores)
        first.calculator.setShutterIndex(6)
        first.manager.renameCamera(CameraSlotId.camera2, "Two")
        first.manager.setCameraDisplayed(CameraSlotId.camera3, false)
        first.manager.moveCamera(CameraSlotId.camera4, -3)
        first.manager.persistCalculatorContext()
        val again = launch(stores)
        assertEquals(first.names, again.names)
        assertEquals(first.shown, again.shown)
        assertEquals(first.active, again.active)
        assertEquals(6, again.calculator.state.value.shutterIndex)

        first.manager.hideCameras(first.shown.toSet())
        val empty = launch(stores)
        assertNull(empty.active)
        assertEquals(4, empty.names.size)
    }

    // --- Sequence ---

    @Test
    fun theFirstAddedCameraIsCameraFiveAndNumbersOnlyIncrease() {
        val l = launch()
        assertEquals("Camera 5", l.nameOf(l.add()))
        assertEquals("Camera 6", l.nameOf(l.add()))
    }

    @Test
    fun renameHideDeleteAndHandTypedNamesNeverMoveTheSequence() {
        val l = launch()
        val first = l.add()!!
        l.manager.renameCamera(first, "Leica")
        l.manager.setCameraDisplayed(first, false)
        l.manager.deleteCameras(setOf(first, CameraSlotId.camera1))
        l.manager.renameCamera(CameraSlotId.camera2, "Camera 9")
        assertEquals("Camera 6", l.nameOf(l.add()))
        l.manager.renameCamera(CameraSlotId.camera3, "Camera 7")
        assertEquals("Camera 7", l.nameOf(l.add()))
    }

    @Test
    fun theSequenceIsNeverReconstructedFromNamesOrCountAcrossRelaunch() {
        val stores = Stores()
        val l = launch(stores)
        repeat(3) { l.add() }
        l.manager.deleteCameras(l.calculator.state.value.cameras.map { it.id }.toSet())
        val again = launch(stores)
        assertTrue(again.names.isEmpty())
        assertEquals("Camera 8", again.nameOf(again.add()))
    }

    @Test
    fun freshInstallWritesTheSequenceBeforeTheManagedList() {
        val events = Events()
        launch(Stores(RecordingManaged(events), RecordingSequence(events)))
        assertEquals(listOf("sequence=5", "managed"), events.items)
    }

    @Test
    fun reservationIsDurableBeforeTheCameraIsCommitted() {
        val events = Events()
        val l = launch(Stores(RecordingManaged(events), RecordingSequence(events)))
        events.items.clear()
        l.add()
        assertEquals(listOf("sequence=6", "managed"), events.items)
    }

    @Test
    fun aCreationThatNeverCommitsLeavesAGapNotAReuse() {
        val sequence = InMemoryCameraNameSequenceStore()
        val lossy = LossyManaged()
        val first = launch(Stores(lossy, sequence))
        val lost = first.add()!!
        assertEquals("Camera 5", first.nameOf(lost))
        assertEquals(CameraNameSequenceLoadResult.Value(6), sequence.result)
        val relaunched = launch(Stores(lossy, sequence))
        assertNull(relaunched.nameOf(lost))
        assertEquals("Camera 6", relaunched.nameOf(relaunched.add()))
    }

    @Test
    fun aFailedReservationCreatesNoCameraAndLaterAddsContinue() {
        val sequence = InMemoryCameraNameSequenceStore()
        val l = launch(Stores(sequence = sequence))
        l.add()
        sequence.failsWrites = true
        val before = l.names.size
        assertNull(l.add())
        assertEquals(before, l.names.size)
        sequence.failsWrites = false
        assertNotNull(l.add())
    }

    // --- Migration and interrupted installation ---

    @Test
    fun migrationKeepsNamesStatesOrderAndWritesSequenceFiveFirstIgnoringCurrentNames() {
        val events = Events()
        val stores = Stores(
            RecordingManaged(events),
            RecordingSequence(events),
            LegacyStore(legacySession(custom = mapOf(CameraSlotId.camera1 to "Camera 9"))),
        )
        val l = launch(stores)
        assertEquals(listOf("Camera 9", "Camera 2", "Camera 3", "Camera 4"), l.names)
        assertEquals(CameraSlotId.camera2, l.active)
        assertEquals(listOf("sequence=5", "managed"), events.items)
        l.calculator.selectSlot(CameraSlotId.camera1)
        assertEquals(11, l.calculator.state.value.shutterIndex)
        assertEquals("Camera 5", l.nameOf(l.add()))
    }

    @Test
    fun aRetriedMigrationNeverLowersAnExistingSequenceValue() {
        val sequence = InMemoryCameraNameSequenceStore(CameraNameSequenceLoadResult.Value(8))
        val l = launch(Stores(sequence = sequence, legacy = LegacyStore(legacySession())))
        assertEquals(CameraNameSequenceLoadResult.Value(8), sequence.result)
        assertEquals("Camera 8", l.nameOf(l.add()))
    }

    @Test
    fun aKillBetweenTheFreshInstallSequenceAndListWritesLeavesNoFailureState() {
        val sequence = InMemoryCameraNameSequenceStore()
        val lossy = LossyManaged()
        launch(Stores(lossy, sequence))
        assertEquals(CameraNameSequenceLoadResult.Value(5), sequence.result)
        val relaunched = launch(Stores(lossy, sequence))
        assertEquals(listOf("Camera 1", "Camera 2", "Camera 3", "Camera 4"), relaunched.names)
        assertEquals("Camera 5", relaunched.nameOf(relaunched.add()))
        assertEquals(CameraNameSequenceLoadResult.Value(6), sequence.result)
    }

    @Test
    fun retryingAPartialMigrationKeepsAHigherExistingSequenceValue() {
        val sequence = InMemoryCameraNameSequenceStore()
        val lossy = LossyManaged()
        val legacy = LegacyStore(legacySession(custom = mapOf(CameraSlotId.camera1 to "Field")))
        val first = launch(Stores(lossy, sequence, legacy))
        assertNotNull(first.add())
        assertEquals(CameraNameSequenceLoadResult.Value(6), sequence.result)
        val retried = launch(Stores(lossy, sequence, legacy))
        assertEquals(CameraNameSequenceLoadResult.Value(6), sequence.result)
        assertEquals("Field", retried.names.first())
        assertEquals("Camera 6", retried.nameOf(retried.add()))
    }

    @Test
    fun aFreshInstallOverAnExistingValidSequenceStoreKeepsItsValue() {
        val sequence = InMemoryCameraNameSequenceStore(CameraNameSequenceLoadResult.Value(12))
        val l = launch(Stores(sequence = sequence))
        assertEquals(0, sequence.saveCount)
        assertEquals("Camera 12", l.nameOf(l.add()))
    }

    // --- Integrity failure ---

    private fun seededManaged(): InMemoryManagedCameraListStore {
        val managed = InMemoryManagedCameraListStore()
        launch(Stores(managed, InMemoryCameraNameSequenceStore())).manager.renameCamera(CameraSlotId.camera1, "Nikon Z7")
        return managed
    }

    @Test
    fun aMissingSequenceStartsTheAllocatorAtFiveAndStoresSixBeforeCameraFive() {
        val events = Events()
        val sequence = RecordingSequence(events, InMemoryCameraNameSequenceStore(CameraNameSequenceLoadResult.Absent))
        val l = launch(Stores(RecordingManaged(events, seededManaged()), sequence))
        assertEquals("Nikon Z7", l.names.first())
        events.items.clear()
        val first = l.add()
        assertEquals("Camera 5", l.nameOf(first))
        assertEquals(listOf("sequence=6", "managed"), events.items)
        assertEquals("Camera 6", l.nameOf(l.add()))
    }

    @Test
    fun anUndecodableSequenceBehavesLikeAMissingOneAndExistingNamesAreNotConsulted() {
        val managed = seededManaged()
        val first = launch(Stores(managed, InMemoryCameraNameSequenceStore(CameraNameSequenceLoadResult.Unusable)))
        assertTrue(first.manager.renameCamera(CameraSlotId.camera2, "Camera 5"))
        val added = first.add()
        // A display name may repeat after this fallback; the identity never does.
        assertEquals("Camera 5", first.nameOf(added))
        assertTrue(added!! !in CameraSlotId.legacyOrdered)
        assertEquals(2, first.names.count { it == "Camera 5" })
        assertEquals("Camera 6", first.nameOf(first.add()))
    }

    @Test
    fun aFailedSequenceReadUsesTheNormalAllocatorFallback() {
        val sequence = InMemoryCameraNameSequenceStore(CameraNameSequenceLoadResult.ReadFailed)
        val l = launch(Stores(seededManaged(), sequence))
        assertEquals("Camera 5", l.nameOf(l.add()))
        assertEquals(CameraNameSequenceLoadResult.Value(6), sequence.result)
        assertEquals("Camera 6", l.nameOf(l.add()))
        assertEquals(CameraNameSequenceLoadResult.Value(7), sequence.result)
    }

    @Test
    fun anOutOfRangeSequenceValueAddsCameraFiveAfterStoringSix() {
        listOf(1, 2, 3, 4, Int.MAX_VALUE, 0, -1).forEach { stored ->
            val events = Events()
            val sequence = RecordingSequence(events, InMemoryCameraNameSequenceStore(CameraNameSequenceLoadResult.Value(stored)))
            val l = launch(Stores(RecordingManaged(events, seededManaged()), sequence))
            events.items.clear()
            assertEquals("stored $stored", "Camera 5", l.nameOf(l.add()))
            assertEquals("stored $stored", listOf("sequence=6", "managed"), events.items)
            assertEquals(CameraNameSequenceLoadResult.Value(6), sequence.delegate.result)
            assertEquals("Camera 6", l.nameOf(l.add()))
        }
    }

    @Test
    fun aFailedFallbackWriteForAnOutOfRangeSequenceCreatesNoCamera() {
        listOf(1, 4, Int.MAX_VALUE).forEach { stored ->
            val sequence = InMemoryCameraNameSequenceStore(CameraNameSequenceLoadResult.Value(stored))
            val managed = seededManaged()
            val l = launch(Stores(managed, sequence))
            val before = l.names
            val savesBefore = managed.saveCount
            sequence.failsWrites = true
            assertNull("stored $stored", l.add())
            assertEquals(before, l.names)
            assertEquals(savesBefore, managed.saveCount)
            assertEquals(CameraNameSequenceLoadResult.Value(stored), sequence.result)
        }
    }

    @Test
    fun aFailedManagedReadMakesEveryCameraEditAWriteFreeNoOp() {
        val managed = InMemoryManagedCameraListStore(ManagedCameraListLoadResult.ReadFailed)
        val sequence = InMemoryCameraNameSequenceStore(CameraNameSequenceLoadResult.Value(7))
        val l = launch(Stores(managed, sequence))
        assertTrue(l.names.isEmpty())
        assertNull(l.add())
        assertFalse(l.manager.renameCamera(CameraSlotId.camera1, "X"))
        l.manager.persistCalculatorContext()
        assertEquals(0, managed.saveCount)
        assertEquals(0, sequence.saveCount)
        assertTrue(l.names.isEmpty())
    }

    @Test
    fun undecodableManagedContentIsReplacedByFourFreshCamerasInOneWrite() {
        val managed = InMemoryManagedCameraListStore(ManagedCameraListLoadResult.Undecodable)
        val l = launch(Stores(managed, InMemoryCameraNameSequenceStore(CameraNameSequenceLoadResult.Value(9)), LegacyStore(legacySession(mapOf(CameraSlotId.camera1 to "Stale")))))
        assertEquals(listOf("Camera 1", "Camera 2", "Camera 3", "Camera 4"), l.names)
        assertTrue(l.shown.none { it in CameraSlotId.legacyOrdered })
        assertEquals(l.shown.first(), l.active)
        assertEquals(1, managed.saveCount)
        assertEquals("Camera 9", l.nameOf(l.add()))
    }
}
