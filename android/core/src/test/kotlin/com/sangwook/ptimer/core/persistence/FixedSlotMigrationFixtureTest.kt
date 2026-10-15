// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.core.persistence

import com.sangwook.ptimer.core.slots.CameraSlotId
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/**
 * Fixed-slot to managed-list migration over the two supported fixed-slot
 * storage shapes (CAMERA-PERSIST-002/003/006, PERSIST-005,
 * PERSIST-CAMERA-SEQUENCE-003), driven by the fixtures under
 * `shared/test-fixtures/camera-migration/`.
 *
 * Fixture provenance is recorded next to the files in
 * `android-provenance.txt`. `0.8.0-35f5fce6` comes from the exact Android
 * 0.8.0 (versionCode 5) release source `35f5fce6`. `0.9.1-dev-9213f12a` is a
 * DEVELOPMENT verification fixture generated from the latest `main` PR merge
 * commit `9213f12a` (#74, Android versionName 0.9.1) under the Strategy.md
 * latest-main rule; it is not an official release fixture and is replaced by
 * the one regenerated from `release/android/0.9.1` once that tag exists. Each
 * file is the output of that build's own `CalculatorController.exportSession()`
 * encoded by `SlotSessionCodec`, after applying the Strategy.md configuration;
 * neither was hand-written. The 0.8.0 payload predates the Filter Stack fields,
 * so it also proves migration of the older shape.
 */
class FixedSlotMigrationFixtureTest {

    private fun fixtureText(name: String): String {
        var dir: File? = File(System.getProperty("user.dir")).absoluteFile
        while (dir != null) {
            val candidate = File(dir, "shared/test-fixtures/camera-migration/$name")
            if (candidate.exists()) return candidate.readText()
            dir = dir.parentFile
        }
        error("Fixture $name not found above ${System.getProperty("user.dir")}")
    }

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

    private class FixtureLegacy(private val session: PersistentSlotSession) : SlotSessionStoring {
        var writes = 0
        override fun loadSession() = session
        override fun saveSession(session: PersistentSlotSession) { writes++ }
        override fun clearSession() { writes++ }
    }

    private class Migrated(fixture: String) {
        val source = requireNotNull(SlotSessionCodec.decode(fixture))
        val legacy = FixtureLegacy(source)
        val events = Events()
        val managed = RecordingManaged(events)
        val sequence = RecordingSequence(events)
        val controller = CameraListPersistenceController(managed, legacy, sequence)
        val restored = controller.restore()
    }

    private fun assertCommonShape(m: Migrated) {
        val list = m.restored.list
        assertTrue(m.restored.needsInitialSave)
        // The four identities verbatim, in order, all shown, camera1 active.
        assertEquals(CameraSlotId.legacyOrdered, list.cameras.map { it.id })
        assertEquals(listOf("Nikon Z7", "Hasselblad 503CX", "Nikon F2", "Camera 4"), list.cameras.map { it.name })
        assertTrue(list.cameras.all { it.isDisplayed })
        assertEquals(CameraSlotId.camera1, list.activeSlotId)
        assertEquals(CameraSlotId.legacyOrdered.toSet(), list.issuedIds)
        assertEquals(m.source.snapshots, list.snapshots)
        // Film, profile, and Target Shutter as configured.
        assertNull(list.snapshots.getValue(CameraSlotId.camera1).selectedFilmId)
        assertEquals(120.0, list.snapshots.getValue(CameraSlotId.camera1).targetSeconds)
        assertEquals("kodak-tmax-100", list.snapshots.getValue(CameraSlotId.camera2).selectedFilmId)
        assertEquals(1800.0, list.snapshots.getValue(CameraSlotId.camera2).targetSeconds)
        assertEquals("ilford-kentmere-pan-100", list.snapshots.getValue(CameraSlotId.camera3).selectedFilmId)
        assertNull(list.snapshots.getValue(CameraSlotId.camera3).targetSeconds)
        assertNull(list.snapshots.getValue(CameraSlotId.camera4).selectedFilmId)
    }

    private fun assertDurableAndRepeatable(m: Migrated) {
        // Sequence 5 first, then one managed payload; the legacy source is never modified.
        assertTrue(m.controller.save(m.restored.list))
        assertEquals(listOf("sequence=5", "managed"), m.events.items)
        assertEquals(0, m.legacy.writes)
        // Relaunch: the managed payload now wins and round-trips the same state.
        val relaunch = CameraListPersistenceController(m.managed.delegate, m.legacy, m.sequence.delegate).restore()
        assertEquals(m.restored.list, relaunch.list)
        assertEquals(false, relaunch.needsInitialSave)
        // The first added camera is Camera 5, then 6.
        val next = CameraListPersistenceController(m.managed.delegate, m.legacy, m.sequence.delegate)
        next.restore()
        assertEquals(5, next.reserveNextCameraNumber())
        assertEquals(6, next.reserveNextCameraNumber())
    }

    @Test
    fun the080FixedSlotShapeMigratesWithoutAnyFilterSetSelection() {
        val m = Migrated(fixtureText("android-slot-session-0.8.0-35f5fce6.json"))
        assertCommonShape(m)
        assertTrue(m.restored.list.snapshots.values.all { it.candidateFilterSetIds == null && it.filterStack == null })
        assertDurableAndRepeatable(m)
    }

    @Test
    fun the091DevelopmentFixedSlotShapeMigratesAndKeepsEachCamerasFilterSetSelection() {
        val m = Migrated(fixtureText("android-slot-session-0.9.1-dev-9213f12a.json"))
        assertCommonShape(m)
        val snapshots = m.restored.list.snapshots
        val z7 = snapshots.getValue(CameraSlotId.camera1).candidateFilterSetIds
        val hasselblad = snapshots.getValue(CameraSlotId.camera2).candidateFilterSetIds
        val f2 = snapshots.getValue(CameraSlotId.camera3).candidateFilterSetIds
        // Z7 selects one Set; the two film cameras share the other two; Camera 4 selects none.
        assertEquals(1, z7?.size)
        assertEquals(2, hasselblad?.size)
        assertEquals(hasselblad, f2)
        assertTrue(z7!!.intersect(hasselblad!!.toSet()).isEmpty())
        assertNull(snapshots.getValue(CameraSlotId.camera4).candidateFilterSetIds)
        assertNotNull(snapshots.getValue(CameraSlotId.camera2).filterStack)
        assertDurableAndRepeatable(m)
    }

    @Test
    fun anInterruptedMigrationRetriesIdempotentlyForBothShapes() {
        listOf("android-slot-session-0.8.0-35f5fce6.json", "android-slot-session-0.9.1-dev-9213f12a.json").forEach { name ->
            val session = requireNotNull(SlotSessionCodec.decode(fixtureText(name)))
            val legacy = FixtureLegacy(session)
            val sequence = InMemoryCameraNameSequenceStore()
            // The managed write never lands (a kill after the sequence write).
            val lossy = object : ManagedCameraListStoring {
                override fun load() = ManagedCameraListLoadResult.Absent
                override fun save(payload: PersistentManagedCameraList) = true
            }
            val first = CameraListPersistenceController(lossy, legacy, sequence)
            val a = first.restore()
            first.save(a.list)
            val b = CameraListPersistenceController(lossy, legacy, sequence).restore()
            assertEquals(a.list, b.list)
            assertEquals(4, b.list.cameras.size)
            assertEquals(CameraNameSequenceLoadResult.Value(5), sequence.result)
        }
    }
}
