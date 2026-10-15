// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.core.persistence

import com.sangwook.ptimer.core.slots.CameraListEntry
import com.sangwook.ptimer.core.slots.CameraListSnapshot
import com.sangwook.ptimer.core.slots.CameraSlotId
import com.sangwook.ptimer.core.slots.SlotCalculatorSnapshot
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Managed-list restore, migration, save, and the automatic-name sequence at the
 * persistence boundary (CAMERA-003, CAMERA-PERSIST-001..007,
 * PERSIST-CAMERA-SEQUENCE-001..003).
 */
class CameraListPersistenceControllerTest {

    private val shot = SlotCalculatorSnapshot(shutterIndex = 9, ndIndex = 4, selectedFilmId = null, selectedProfileId = null)
    private val other = SlotCalculatorSnapshot(shutterIndex = 2, ndIndex = 1, selectedFilmId = null, selectedProfileId = null)

    private class Events {
        val items = mutableListOf<String>()
    }

    /** Wraps a store and records the order of durable writes. */
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

    /** A managed store whose writes are acknowledged but never reach disk (a kill before commit). */
    private class LossyManaged : ManagedCameraListStoring {
        override fun load() = ManagedCameraListLoadResult.Absent
        override fun save(payload: PersistentManagedCameraList) = true
    }

    /** A legacy store that counts every write, to prove the source is never modified. */
    private class CountingLegacy(var session: PersistentSlotSession?) : SlotSessionStoring {
        var writes = 0
        override fun loadSession() = session
        override fun saveSession(session: PersistentSlotSession) { writes++ }
        override fun clearSession() { writes++ }
    }

    private fun controller(
        managed: ManagedCameraListStoring = InMemoryManagedCameraListStore(),
        legacy: SlotSessionStoring = NoOpSlotSessionStore(),
        sequence: CameraNameSequenceStoring = InMemoryCameraNameSequenceStore(),
    ) = CameraListPersistenceController(managed, legacy, sequence)

    private fun legacySession(custom: Map<CameraSlotId, String> = emptyMap(), active: CameraSlotId = CameraSlotId.camera3) =
        PersistentSlotSession(
            activeSlotId = active,
            snapshots = mapOf(CameraSlotId.camera1 to shot, CameraSlotId.camera3 to other),
            customNames = custom,
        )

    private fun payload(vararg ids: String, active: String? = ids.firstOrNull()) = PersistentManagedCameraList(
        issuedIds = ids.toList(),
        activeCameraId = active,
        cameras = ids.map { PersistentManagedCamera(it, "Name $it", true, shot) },
    )

    // --- Fresh install, seeding ---

    @Test
    fun freshInstallSeedsTheFourCamerasInOrderShownWithCameraOneActive() {
        val restored = controller().restore()
        assertTrue(restored.needsInitialSave)
        assertEquals(CameraSlotId.legacyOrdered, restored.list.cameras.map { it.id })
        assertEquals(listOf("Camera 1", "Camera 2", "Camera 3", "Camera 4"), restored.list.cameras.map { it.name })
        assertTrue(restored.list.cameras.all { it.isDisplayed })
        assertEquals(CameraSlotId.camera1, restored.list.activeSlotId)
        assertEquals(CameraSlotId.legacyOrdered.toSet(), restored.list.issuedIds)
    }

    @Test
    fun seededNamesAreFrozenFromTheInjectedLocalizer() {
        val restored = CameraListPersistenceController(defaultName = { "카메라 $it" }).restore()
        assertEquals("카메라 1", restored.list.cameras.first().name)
    }

    @Test
    fun freshInstallWritesTheSequenceBeforeTheManagedList() {
        val events = Events()
        val sequence = RecordingSequence(events)
        val c = controller(RecordingManaged(events), sequence = sequence)
        c.restore()
        assertTrue(c.save(CameraListSnapshot.seeded { "Camera $it" }))
        assertEquals(listOf("sequence=5", "managed"), events.items)
        // Later saves never rewrite the sequence.
        c.save(CameraListSnapshot.seeded { "Camera $it" })
        assertEquals(listOf("sequence=5", "managed", "managed"), events.items)
    }

    @Test
    fun theSeededPayloadIsNotCommittedWhenTheSequenceWriteFails() {
        val managed = InMemoryManagedCameraListStore()
        val sequence = InMemoryCameraNameSequenceStore().also { it.failsWrites = true }
        val c = controller(managed, sequence = sequence)
        c.restore()
        assertFalse(c.save(CameraListSnapshot.seeded { "Camera $it" }))
        assertEquals(0, managed.saveCount)
        sequence.failsWrites = false
        assertTrue(c.save(CameraListSnapshot.seeded { "Camera $it" }))
        assertEquals(1, managed.saveCount)
        assertEquals(CameraNameSequenceLoadResult.Value(5), sequence.result)
    }

    @Test
    fun aFreshInstallOverAnExistingValidSequenceStoreKeepsItsValue() {
        val sequence = InMemoryCameraNameSequenceStore(CameraNameSequenceLoadResult.Value(12))
        val c = controller(sequence = sequence)
        c.restore()
        c.save(CameraListSnapshot.seeded { "Camera $it" })
        assertEquals(CameraNameSequenceLoadResult.Value(12), sequence.result)
        assertEquals(0, sequence.saveCount)
        assertEquals(12, c.reserveNextCameraNumber())
    }

    // --- Round trip ---

    @Test
    fun listOrderInclusionActiveCameraNamesIdentitiesAndStateSurviveRelaunch() {
        val managed = InMemoryManagedCameraListStore()
        val sequence = InMemoryCameraNameSequenceStore()
        val first = controller(managed, sequence = sequence)
        first.restore()
        val generated = CameraSlotId("camera-xyz")
        val list = CameraListSnapshot(
            cameras = listOf(
                CameraListEntry(generated, "Leica M6", isDisplayed = false),
                CameraListEntry(CameraSlotId.camera3, "Three"),
                CameraListEntry(CameraSlotId.camera1, "One"),
            ),
            activeSlotId = CameraSlotId.camera1,
            issuedIds = CameraSlotId.legacyOrdered.toSet() + generated,
            snapshots = mapOf(generated to shot, CameraSlotId.camera1 to other, CameraSlotId.camera3 to shot),
        )
        assertTrue(first.save(list))

        val restored = controller(managed, sequence = sequence).restore()
        assertFalse(restored.needsInitialSave)
        assertEquals(list.cameras, restored.list.cameras)
        assertEquals(CameraSlotId.camera1, restored.list.activeSlotId)
        assertEquals(list.issuedIds, restored.list.issuedIds)
        assertEquals(shot, restored.list.snapshots[generated])
        assertEquals(other, restored.list.snapshots[CameraSlotId.camera1])
        assertEquals(shot, restored.list.snapshots[CameraSlotId.camera3])
    }

    @Test
    fun noActiveCameraAndAnEmptyListSurviveRelaunchWithoutReseeding() {
        val managed = InMemoryManagedCameraListStore()
        val sequence = InMemoryCameraNameSequenceStore(CameraNameSequenceLoadResult.Value(9))
        val first = controller(managed, sequence = sequence)
        first.restore()
        first.save(CameraListSnapshot(emptyList(), null, setOf(CameraSlotId.camera1), emptyMap()))

        val restored = controller(managed, sequence = sequence).restore()
        assertFalse(restored.needsInitialSave)
        assertTrue(restored.list.cameras.isEmpty())
        assertNull(restored.list.activeSlotId)
        assertEquals(CameraNameSequenceLoadResult.Value(9), sequence.result)
    }

    @Test
    fun aSavePersistsTheWholeListAsOneWrite() {
        val managed = InMemoryManagedCameraListStore()
        val c = controller(managed)
        c.restore()
        c.save(CameraListSnapshot.seeded { "Camera $it" })
        val before = managed.saveCount
        c.save(
            CameraListSnapshot(
                cameras = listOf(CameraListEntry(CameraSlotId.camera2, "Two", false)),
                activeSlotId = null,
                issuedIds = CameraSlotId.legacyOrdered.toSet(),
                snapshots = mapOf(CameraSlotId.camera2 to shot),
            ),
        )
        assertEquals(before + 1, managed.saveCount)
        val saved = managed.lastSaved!!
        assertEquals(listOf("camera2"), saved.cameras.map { it.id })
        assertNull(saved.activeCameraId)
        assertEquals(shot, saved.cameras.single().calculator)
    }

    // --- Migration ---

    @Test
    fun legacySessionMigratesNamesStatesOrderAndVisibility() {
        val legacy = CountingLegacy(legacySession(custom = mapOf(CameraSlotId.camera2 to "  Hasselblad ")))
        val restored = controller(legacy = legacy).restore()
        assertTrue(restored.needsInitialSave)
        assertEquals(CameraSlotId.legacyOrdered, restored.list.cameras.map { it.id })
        // The custom name is kept (trimmed); unnamed slots freeze their resolved Camera N text.
        assertEquals(listOf("Camera 1", "Hasselblad", "Camera 3", "Camera 4"), restored.list.cameras.map { it.name })
        assertTrue(restored.list.cameras.all { it.isDisplayed })
        assertEquals(CameraSlotId.camera3, restored.list.activeSlotId)
        assertEquals(shot, restored.list.snapshots[CameraSlotId.camera1])
        assertEquals(other, restored.list.snapshots[CameraSlotId.camera3])
        assertEquals(CameraSlotId.legacyOrdered.toSet(), restored.list.issuedIds)
        assertEquals(0, legacy.writes)
    }

    @Test
    fun migrationIsIdempotentAndTheLegacySourceIsNeverModified() {
        val managed = LossyManaged()
        val legacy = CountingLegacy(legacySession())
        val sequence = InMemoryCameraNameSequenceStore()
        val first = controller(managed, legacy, sequence)
        val a = first.restore()
        first.save(a.list)
        // The managed write was lost (an interrupted first save): the retry migrates again.
        val b = controller(managed, legacy, sequence).restore()
        assertEquals(a.list, b.list)
        assertEquals(4, b.list.cameras.size)
        assertEquals(0, legacy.writes)
    }

    @Test
    fun aValidManagedPayloadWinsOverARemainingLegacyPayload() {
        val managed = InMemoryManagedCameraListStore(
            ManagedCameraListCodec.decode(ManagedCameraListCodec.encode(payload("camera-only"))),
        )
        val legacy = CountingLegacy(legacySession(custom = mapOf(CameraSlotId.camera1 to "Legacy")))
        val restored = controller(managed, legacy, InMemoryCameraNameSequenceStore(CameraNameSequenceLoadResult.Value(5))).restore()
        assertEquals(listOf("Name camera-only"), restored.list.cameras.map { it.name })
        assertFalse(restored.needsInitialSave)
    }

    @Test
    fun migrationWritesSequenceFiveFirstAndIgnoresCurrentNames() {
        val events = Events()
        val sequence = RecordingSequence(events)
        val c = controller(
            RecordingManaged(events),
            CountingLegacy(legacySession(custom = mapOf(CameraSlotId.camera1 to "Camera 9"))),
            sequence,
        )
        val restored = c.restore()
        assertEquals("Camera 9", restored.list.cameras.first().name)
        c.save(restored.list)
        assertEquals(listOf("sequence=5", "managed"), events.items)
        assertEquals(5, c.reserveNextCameraNumber())
    }

    @Test
    fun aRetriedMigrationNeverLowersAnExistingSequenceValue() {
        val sequence = InMemoryCameraNameSequenceStore(CameraNameSequenceLoadResult.Value(8))
        val c = controller(legacy = CountingLegacy(legacySession()), sequence = sequence)
        c.save(c.restore().list)
        assertEquals(CameraNameSequenceLoadResult.Value(8), sequence.result)
        assertEquals(0, sequence.saveCount)
        assertEquals(8, c.reserveNextCameraNumber())
    }

    // --- Successfully read content that cannot be decoded (CAMERA-PERSIST-004/006) ---

    private var nextGenerated = 0
    private val generate = { CameraSlotId("camera-new-${nextGenerated++}") }

    private fun recovering(
        managed: ManagedCameraListStoring,
        legacy: SlotSessionStoring = NoOpSlotSessionStore(),
        sequence: CameraNameSequenceStoring = InMemoryCameraNameSequenceStore(),
    ) = CameraListPersistenceController(managed, legacy, sequence, generateId = generate)

    @Test
    fun undecodableContentIsReplacedByFourDefaultCamerasWithNewOpaqueIdentities() {
        val c = recovering(InMemoryManagedCameraListStore(ManagedCameraListLoadResult.Undecodable))
        val restored = c.restore()
        assertTrue(restored.needsInitialSave)
        assertEquals(listOf("Camera 1", "Camera 2", "Camera 3", "Camera 4"), restored.list.cameras.map { it.name })
        assertTrue(restored.list.cameras.all { it.isDisplayed })
        assertEquals(4, restored.list.cameras.map { it.id }.toSet().size)
        assertTrue(restored.list.cameras.none { it.id in CameraSlotId.legacyOrdered })
        assertEquals(restored.list.cameras.first().id, restored.list.activeSlotId)
        assertEquals(restored.list.cameras.map { it.id }.toSet(), restored.list.issuedIds)
        assertTrue(restored.list.snapshots.isEmpty())
    }

    @Test
    fun theReplacementIsOneManagedWriteAfterTheSequenceAndNeverUsesLegacyData() {
        val events = Events()
        val managed = RecordingManaged(events, InMemoryManagedCameraListStore(ManagedCameraListLoadResult.Undecodable))
        val legacy = CountingLegacy(legacySession(custom = mapOf(CameraSlotId.camera1 to "Stale legacy")))
        val c = recovering(managed, legacy, RecordingSequence(events))
        val restored = c.restore()
        assertTrue(restored.list.cameras.none { it.name == "Stale legacy" })
        assertTrue(c.save(restored.list))
        // One managed commit overwrites the unreadable payload: no delete, no absent interval.
        assertEquals(listOf("sequence=5", "managed"), events.items)
        assertEquals(0, legacy.writes)
        assertTrue(managed.delegate.result is ManagedCameraListLoadResult.Loaded)
    }

    @Test
    fun theReplacementKeepsAReadableHigherSequenceAndNeverLowersIt() {
        val sequence = InMemoryCameraNameSequenceStore(CameraNameSequenceLoadResult.Value(12))
        val c = recovering(InMemoryManagedCameraListStore(ManagedCameraListLoadResult.Undecodable), sequence = sequence)
        c.save(c.restore().list)
        assertEquals(CameraNameSequenceLoadResult.Value(12), sequence.result)
        assertEquals(0, sequence.saveCount)
        assertEquals(12, c.reserveNextCameraNumber())
    }

    @Test
    fun theReplacementRaisesALowerReadableSequenceToFive() {
        val sequence = InMemoryCameraNameSequenceStore(CameraNameSequenceLoadResult.Value(3))
        val c = recovering(InMemoryManagedCameraListStore(ManagedCameraListLoadResult.Undecodable), sequence = sequence)
        c.save(c.restore().list)
        assertEquals(CameraNameSequenceLoadResult.Value(5), sequence.result)
    }

    @Test
    fun theReplacementUsesFiveWhenNoSequenceCanBeRead() {
        listOf(
            CameraNameSequenceLoadResult.Absent,
            CameraNameSequenceLoadResult.Unusable,
            CameraNameSequenceLoadResult.ReadFailed,
        ).forEach { stored ->
            val sequence = InMemoryCameraNameSequenceStore(stored)
            val c = recovering(InMemoryManagedCameraListStore(ManagedCameraListLoadResult.Undecodable), sequence = sequence)
            c.save(c.restore().list)
            assertEquals(CameraNameSequenceLoadResult.Value(5), sequence.result)
        }
    }

    @Test
    fun anInterruptedReplacementRetriesWithoutLegacyMigrationOrAnAbsentPayload() {
        val managed = InMemoryManagedCameraListStore(ManagedCameraListLoadResult.Undecodable)
        val legacy = CountingLegacy(legacySession(custom = mapOf(CameraSlotId.camera1 to "Stale legacy")))
        val sequence = InMemoryCameraNameSequenceStore()
        val first = recovering(managed, legacy, sequence)
        first.restore()
        // Killed before the managed write: the unreadable payload is still there, never absent.
        val retried = recovering(managed, legacy, sequence).restore()
        assertEquals(listOf("Camera 1", "Camera 2", "Camera 3", "Camera 4"), retried.list.cameras.map { it.name })
        assertEquals(0, legacy.writes)
        assertEquals(ManagedCameraListLoadResult.Undecodable, managed.result)
    }

    // --- Failed storage read: no content (CAMERA-PERSIST-004/006) ---

    @Test
    fun aFailedManagedReadMakesCameraStateReadOnlyWithNoWritesAndNoLegacyFallback() {
        val managed = InMemoryManagedCameraListStore(ManagedCameraListLoadResult.ReadFailed)
        val legacy = CountingLegacy(legacySession(custom = mapOf(CameraSlotId.camera1 to "Stale legacy")))
        val sequence = InMemoryCameraNameSequenceStore(CameraNameSequenceLoadResult.Value(7))
        val c = recovering(managed, legacy, sequence)
        val restored = c.restore()
        assertTrue(c.isReadFailed)
        assertTrue(restored.list.cameras.isEmpty())
        assertNull(restored.list.activeSlotId)
        assertFalse(restored.needsInitialSave)
        assertFalse(c.save(CameraListSnapshot.seeded { "Camera $it" }))
        assertNull(c.reserveNextCameraNumber())
        assertEquals(0, managed.saveCount)
        assertEquals(0, sequence.saveCount)
        assertEquals(0, legacy.writes)
    }

    @Test
    fun aFailedManagedReadRetriesOnTheNextLaunch() {
        val managed = InMemoryManagedCameraListStore(ManagedCameraListLoadResult.ReadFailed)
        recovering(managed).restore()
        managed.result = ManagedCameraListCodec.decode(ManagedCameraListCodec.encode(payload("camera1", "camera2")))
        val relaunched = recovering(managed, sequence = InMemoryCameraNameSequenceStore(CameraNameSequenceLoadResult.Value(5)))
        assertEquals(2, relaunched.restore().list.cameras.size)
        assertFalse(relaunched.isReadFailed)
    }

    @Test
    fun aFailedLegacyReadDoesNotSeedOverMigrationData() {
        val managed = InMemoryManagedCameraListStore()
        val legacy = object : SlotSessionStoring {
            override fun loadSession(): PersistentSlotSession? = null
            override fun load(): SlotSessionLoadResult = SlotSessionLoadResult.ReadFailed
            override fun saveSession(session: PersistentSlotSession) {}
            override fun clearSession() {}
        }
        val c = recovering(managed, legacy)
        val restored = c.restore()
        assertTrue(c.isReadFailed)
        assertTrue(restored.list.cameras.isEmpty())
        assertFalse(c.save(CameraListSnapshot.seeded { "Camera $it" }))
        assertEquals(0, managed.saveCount)
    }

    @Test
    fun aFailedSequenceReadOnFirstLaunchSeedsFourCamerasAndStoresFiveBeforeThePayload() {
        val events = Events()
        val managed = RecordingManaged(events)
        val sequence = RecordingSequence(events, InMemoryCameraNameSequenceStore(CameraNameSequenceLoadResult.ReadFailed))
        val c = recovering(managed, sequence = sequence)
        val restored = c.restore()
        assertFalse(c.isReadFailed)
        assertEquals(4, restored.list.cameras.size)
        assertTrue(c.save(restored.list))
        assertEquals(listOf("sequence=5", "managed"), events.items)
    }

    // --- Per-record defaults (CAMERA-PERSIST-004) ---

    private fun loaded(vararg cameras: DecodedManagedCamera, active: String? = null, skipped: Int = 0, issued: List<String> = emptyList()) =
        InMemoryManagedCameraListStore(
            ManagedCameraListLoadResult.Loaded(DecodedManagedCameraList(issued, active, cameras.toList(), skipped)),
        )

    private val sequenceFive get() = InMemoryCameraNameSequenceStore(CameraNameSequenceLoadResult.Value(5))

    @Test
    fun aRecordWithMissingFieldsTakesTheDefaultsAndIsPersistedNormalized() {
        val c = CameraListPersistenceController(
            loaded(DecodedManagedCamera(null, null, null, null), DecodedManagedCamera("kept", "  Leica  ", false, shot)),
            sequenceStore = sequenceFive,
            recordFallbackName = "Camera",
            generateId = generate,
        )
        val restored = c.restore()
        assertTrue(restored.needsInitialSave)
        val first = restored.list.cameras[0]
        assertEquals("Camera", first.name)
        assertTrue(first.isDisplayed)
        assertTrue(first.id.raw.startsWith("camera-new-"))
        assertNull(restored.list.snapshots[first.id])
        assertEquals(CameraListEntry(CameraSlotId("kept"), "Leica", false), restored.list.cameras[1])
        assertEquals(shot, restored.list.snapshots[CameraSlotId("kept")])
    }

    @Test
    fun aMissingOrUnusableActiveCameraSelectsTheFirstShownCameraOrNone() {
        val hiddenActive = loaded(
            DecodedManagedCamera("a", "A", false, null),
            DecodedManagedCamera("b", "B", true, null),
            active = "a",
        )
        val session = com.sangwook.ptimer.core.slots.CameraSlotSession(
            CameraListPersistenceController(hiddenActive, sequenceStore = sequenceFive).restore().list,
            shot,
        )
        assertEquals(CameraSlotId("b"), session.activeSlotId)
        val noneShown = loaded(DecodedManagedCamera("a", "A", false, null))
        val none = com.sangwook.ptimer.core.slots.CameraSlotSession(
            CameraListPersistenceController(noneShown, sequenceStore = sequenceFive).restore().list,
            shot,
        )
        assertNull(none.activeSlotId)
    }

    @Test
    fun theFirstDuplicateIdentityIsKeptAndLaterOnesGetNewIdentities() {
        val c = CameraListPersistenceController(
            loaded(
                DecodedManagedCamera("a", "First", true, shot),
                DecodedManagedCamera("a", "Second", true, other),
                DecodedManagedCamera("b", "Third", true, null),
                active = "a",
            ),
            sequenceStore = sequenceFive,
            generateId = generate,
        )
        val restored = c.restore()
        assertTrue(restored.needsInitialSave)
        assertEquals(listOf("First", "Second", "Third"), restored.list.cameras.map { it.name })
        assertEquals(CameraSlotId("a"), restored.list.cameras[0].id)
        assertTrue(restored.list.cameras[1].id.raw.startsWith("camera-new-"))
        assertEquals(CameraSlotId("b"), restored.list.cameras[2].id)
        assertEquals(shot, restored.list.snapshots[CameraSlotId("a")])
        assertEquals(other, restored.list.snapshots[restored.list.cameras[1].id])
        assertEquals(3, restored.list.issuedIds.size)
    }

    @Test
    fun entriesThatAreNotKeyedRecordsAreSkippedAndTheNormalizedListIsPersisted() {
        val c = CameraListPersistenceController(
            loaded(DecodedManagedCamera("a", "A", true, shot), skipped = 2),
            sequenceStore = sequenceFive,
        )
        val restored = c.restore()
        assertTrue(restored.needsInitialSave)
        assertEquals(listOf("A"), restored.list.cameras.map { it.name })
    }

    @Test
    fun aCompleteValidListNeedsNoRewrite() {
        val c = CameraListPersistenceController(
            loaded(DecodedManagedCamera("a", "A", true, shot), active = "a"),
            sequenceStore = sequenceFive,
        )
        assertFalse(c.restore().needsInitialSave)
    }

    @Test
    fun anExplicitEmptyListStaysEmptyAndIsNeverReseeded() {
        val managed = loaded()
        val c = CameraListPersistenceController(managed, sequenceStore = sequenceFive)
        val restored = c.restore()
        assertTrue(restored.list.cameras.isEmpty())
        assertFalse(restored.needsInitialSave)
        assertTrue(c.save(CameraListSnapshot(emptyList(), null, emptySet(), emptyMap())))
    }

    // --- Automatic-name sequence ---

    @Test
    fun theFirstReservationIsFiveAndNumbersOnlyIncrease() {
        val sequence = InMemoryCameraNameSequenceStore()
        val c = controller(sequence = sequence)
        c.save(c.restore().list)
        assertEquals(5, c.reserveNextCameraNumber())
        assertEquals(6, c.reserveNextCameraNumber())
        assertEquals(CameraNameSequenceLoadResult.Value(7), sequence.result)
    }

    @Test
    fun theSequenceSurvivesRelaunchWhateverTheListHolds() {
        val managed = InMemoryManagedCameraListStore()
        val sequence = InMemoryCameraNameSequenceStore()
        val first = controller(managed, sequence = sequence)
        first.save(first.restore().list)
        first.reserveNextCameraNumber()
        first.reserveNextCameraNumber()
        first.reserveNextCameraNumber()
        first.save(CameraListSnapshot(emptyList(), null, emptySet(), emptyMap()))

        val relaunched = controller(managed, sequence = sequence)
        assertTrue(relaunched.restore().list.cameras.isEmpty())
        assertEquals(8, relaunched.reserveNextCameraNumber())
    }

    @Test
    fun reservationIsDurableBeforeTheCameraRecordIsCommitted() {
        val events = Events()
        val c = controller(RecordingManaged(events), sequence = RecordingSequence(events))
        c.save(c.restore().list)
        events.items.clear()
        assertEquals(5, c.reserveNextCameraNumber())
        // The caller creates the camera and saves afterwards.
        c.save(CameraListSnapshot.seeded { "Camera $it" })
        assertEquals(listOf("sequence=6", "managed"), events.items)
    }

    @Test
    fun aCreationThatNeverCommitsLeavesAGapNotAReuse() {
        val sequence = InMemoryCameraNameSequenceStore()
        val lossy = LossyManaged()
        val first = controller(lossy, sequence = sequence)
        first.save(first.restore().list)
        assertEquals(5, first.reserveNextCameraNumber())
        // The camera record never reached disk; the number was reserved first.
        assertEquals(CameraNameSequenceLoadResult.Value(6), sequence.result)

        val relaunched = controller(lossy, sequence = sequence)
        relaunched.restore()
        assertEquals(6, relaunched.reserveNextCameraNumber())
    }

    @Test
    fun aFailedReservationWriteReturnsNullAndLaterReservationsContinue() {
        val sequence = InMemoryCameraNameSequenceStore()
        val c = controller(sequence = sequence)
        c.save(c.restore().list)
        c.reserveNextCameraNumber()
        sequence.failsWrites = true
        assertNull(c.reserveNextCameraNumber())
        sequence.failsWrites = false
        assertEquals(6, c.reserveNextCameraNumber())
    }

    // --- Interrupted installation and migration (CAMERA-PERSIST-001/002) ---

    @Test
    fun aKillBetweenTheFreshInstallSequenceAndListWritesLeavesNoFailureState() {
        val sequence = InMemoryCameraNameSequenceStore()
        val lossy = LossyManaged()
        val first = controller(lossy, sequence = sequence)
        first.save(first.restore().list)
        assertEquals(CameraNameSequenceLoadResult.Value(5), sequence.result)

        val relaunched = controller(lossy, sequence = sequence)
        val restored = relaunched.restore()
        assertEquals(listOf("Camera 1", "Camera 2", "Camera 3", "Camera 4"), restored.list.cameras.map { it.name })
        assertEquals(5, relaunched.reserveNextCameraNumber())
        assertEquals(CameraNameSequenceLoadResult.Value(6), sequence.result)
    }

    @Test
    fun retryingAPartialMigrationKeepsAHigherExistingSequenceValue() {
        val sequence = InMemoryCameraNameSequenceStore()
        val lossy = LossyManaged()
        val legacy = CountingLegacy(legacySession(custom = mapOf(CameraSlotId.camera1 to "Field")))
        val first = controller(lossy, legacy, sequence)
        first.save(first.restore().list)
        assertEquals(5, first.reserveNextCameraNumber())
        assertEquals(CameraNameSequenceLoadResult.Value(6), sequence.result)

        val retried = controller(lossy, legacy, sequence)
        val restored = retried.restore()
        retried.save(restored.list)
        assertEquals(CameraNameSequenceLoadResult.Value(6), sequence.result)
        assertEquals("Field", restored.list.cameras.first().name)
        assertEquals(6, retried.reserveNextCameraNumber())
    }

    @Test
    fun aMissingUnreadableOrUndecodableSequenceStartsTheAllocatorAtFiveAndStoresSixBeforeCameraFive() {
        listOf(
            CameraNameSequenceLoadResult.Absent,
            CameraNameSequenceLoadResult.Unusable,
            CameraNameSequenceLoadResult.ReadFailed,
        ).forEach { stored ->
            val events = Events()
            val managed = RecordingManaged(
                events,
                InMemoryManagedCameraListStore(
                    ManagedCameraListCodec.decode(ManagedCameraListCodec.encode(payload("camera1", "camera2"))),
                ),
            )
            val sequence = RecordingSequence(events, InMemoryCameraNameSequenceStore(stored))
            val c = CameraListPersistenceController(managed, sequenceStore = sequence)
            val restored = c.restore()
            assertFalse(c.isReadFailed)
            assertEquals(2, restored.list.cameras.size)
            // Same-name cameras may exist already; the allocator does not look at them.
            assertEquals(5, c.reserveNextCameraNumber())
            c.save(restored.list)
            assertEquals(listOf("sequence=6", "managed"), events.items)
            assertEquals(6, c.reserveNextCameraNumber())
            assertEquals(CameraNameSequenceLoadResult.Value(7), sequence.delegate.result)
        }
    }

    @Test
    fun aFailedSequenceReadReservesFiveAndStoresSixThenContinuesMonotonically() {
        val managed = InMemoryManagedCameraListStore(
            ManagedCameraListCodec.decode(ManagedCameraListCodec.encode(payload("camera1"))),
        )
        val sequence = InMemoryCameraNameSequenceStore(CameraNameSequenceLoadResult.ReadFailed)
        val c = CameraListPersistenceController(managed, sequenceStore = sequence)
        c.restore()
        assertFalse(c.isReadFailed)
        assertEquals(5, c.reserveNextCameraNumber())
        assertEquals(CameraNameSequenceLoadResult.Value(6), sequence.result)
        assertEquals(6, c.reserveNextCameraNumber())
        assertEquals(7, (sequence.result as CameraNameSequenceLoadResult.Value).nextNumber)
    }

    @Test
    fun aCorruptSequenceOnAFirstLaunchStillMigratesAndInitializesFive() {
        val managed = InMemoryManagedCameraListStore()
        val sequence = InMemoryCameraNameSequenceStore(CameraNameSequenceLoadResult.Unusable)
        val c = controller(managed, CountingLegacy(legacySession(custom = mapOf(CameraSlotId.camera1 to "Field"))), sequence)
        val restored = c.restore()
        assertEquals("Field", restored.list.cameras.first().name)
        assertTrue(c.save(restored.list))
        assertEquals(1, managed.saveCount)
        assertEquals(CameraNameSequenceLoadResult.Value(5), sequence.result)
        assertEquals(5, c.reserveNextCameraNumber())
    }

    private val outOfRangeSequenceValues = listOf(Int.MIN_VALUE, -1, 0, 1, 2, 3, 4, Int.MAX_VALUE)

    @Test
    fun anOutOfRangeSequenceValueStoresSixBeforeCameraFiveIsCommitted() {
        outOfRangeSequenceValues.forEach { stored ->
            val events = Events()
            val managed = RecordingManaged(
                events,
                InMemoryManagedCameraListStore(
                    ManagedCameraListCodec.decode(ManagedCameraListCodec.encode(payload("camera1", "camera2"))),
                ),
            )
            val sequence = RecordingSequence(events, InMemoryCameraNameSequenceStore(CameraNameSequenceLoadResult.Value(stored)))
            val c = CameraListPersistenceController(managed, sequenceStore = sequence)
            val restored = c.restore()
            assertFalse(c.isReadFailed)
            assertEquals("stored $stored", 5, c.reserveNextCameraNumber())
            c.save(restored.list)
            assertEquals("stored $stored", listOf("sequence=6", "managed"), events.items)
            assertEquals(6, c.reserveNextCameraNumber())
            assertEquals(CameraNameSequenceLoadResult.Value(7), sequence.delegate.result)
        }
    }

    @Test
    fun theUpperBoundOfTheRangeIsStillAllocatable() {
        val sequence = InMemoryCameraNameSequenceStore(CameraNameSequenceLoadResult.Value(Int.MAX_VALUE - 1))
        val c = CameraListPersistenceController(
            InMemoryManagedCameraListStore(ManagedCameraListCodec.decode(ManagedCameraListCodec.encode(payload("camera1")))),
            sequenceStore = sequence,
        )
        c.restore()
        assertEquals(Int.MAX_VALUE - 1, c.reserveNextCameraNumber())
    }

    @Test
    fun aFailedFallbackWriteForAnOutOfRangeValueReservesNothing() {
        outOfRangeSequenceValues.forEach { stored ->
            val sequence = InMemoryCameraNameSequenceStore(CameraNameSequenceLoadResult.Value(stored))
            val c = CameraListPersistenceController(
                InMemoryManagedCameraListStore(ManagedCameraListCodec.decode(ManagedCameraListCodec.encode(payload("camera1")))),
                sequenceStore = sequence,
            )
            c.restore()
            sequence.failsWrites = true
            assertNull("stored $stored", c.reserveNextCameraNumber())
            assertEquals(CameraNameSequenceLoadResult.Value(stored), sequence.result)
        }
    }

    @Test
    fun anOutOfRangeSequenceOnFirstLaunchIsReplacedByFiveBeforeThePayload() {
        outOfRangeSequenceValues.forEach { stored ->
            val events = Events()
            val sequence = RecordingSequence(events, InMemoryCameraNameSequenceStore(CameraNameSequenceLoadResult.Value(stored)))
            val c = CameraListPersistenceController(RecordingManaged(events), sequenceStore = sequence)
            val restored = c.restore()
            assertTrue(c.save(restored.list))
            assertEquals("stored $stored", listOf("sequence=5", "managed"), events.items)
            assertEquals(CameraNameSequenceLoadResult.Value(5), sequence.delegate.result)
        }
    }
}
