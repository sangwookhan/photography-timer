// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.core.persistence

import com.sangwook.ptimer.core.slots.CameraListEntry
import com.sangwook.ptimer.core.slots.CameraListSnapshot
import com.sangwook.ptimer.core.slots.CameraNaming
import com.sangwook.ptimer.core.slots.CameraSlotId
import com.sangwook.ptimer.core.slots.SlotCalculatorSnapshot

/**
 * Bridges the runtime managed camera list and its on-disk formats. Owns the
 * serialise/deserialise rules, the legacy migration, the corrupt-content
 * replacement, and the automatic-name sequence so the view-model layer stays a
 * thin facade. (iOS: CameraSlotSessionPersistenceController.)
 *
 * Sources, in precedence order (CAMERA-PERSIST-004/006):
 * 1. A valid managed payload always wins; missing fields take their defaults.
 * 2. Content that was read successfully but cannot be decoded is replaced, in
 *    one write, by four default cameras with new opaque identities. Legacy data
 *    is never used in its place and no absent-payload interval is exposed.
 * 3. With no managed payload, the legacy slot-session payload migrates into
 *    the managed list, or a fresh install seeds the four default cameras. The
 *    legacy store is never modified or removed, so a retry after an
 *    interruption repeats the same idempotent migration.
 * 4. A camera-list or legacy storage read that fails and supplies no content
 *    makes camera state non-authoritative for this launch ([isReadFailed]): nothing is deleted or
 *    written, there is no legacy fallback, and the next launch retries.
 *
 * Thread-safe: restore runs on the bootstrap read, saves and reservations on
 * the persistence writer, and [isReadFailed] is read from the main thread.
 */
class CameraListPersistenceController(
    private val managedStore: ManagedCameraListStoring = InMemoryManagedCameraListStore(),
    private val legacyStore: SlotSessionStoring = NoOpSlotSessionStore(),
    private val sequenceStore: CameraNameSequenceStoring = InMemoryCameraNameSequenceStore(),
    /** Localized `Camera N` name; frozen as stored text when seeding, migrating, or replacing. */
    private val defaultName: (Int) -> String = { "Camera $it" },
    /** Localized `Camera`, for a stored record that lacks a usable name. */
    private val recordFallbackName: String = "Camera",
    private val generateId: () -> CameraSlotId = { CameraSlotId.generate() },
) {
    /** A restored list, and whether it still has to be written to the managed store. */
    class Restored(val list: CameraListSnapshot, val needsInitialSave: Boolean)

    // Set when a storage read supplied no content: no camera write may follow.
    @Volatile
    var isReadFailed = false
        private set

    // Fresh install, migration, or replacement: this sequence value is written
    // (advance-only) before the first managed payload is committed.
    private var pendingSequenceTarget: Int? = null

    /** Loads the managed payload, or replaces / migrates / seeds (CAMERA-PERSIST-001/002/004/006). */
    @Synchronized
    fun restore(): Restored = when (val loaded = managedStore.load()) {
        ManagedCameraListLoadResult.ReadFailed -> readFailed()
        ManagedCameraListLoadResult.Absent -> when (val legacy = legacyStore.load()) {
            SlotSessionLoadResult.ReadFailed -> readFailed()
            is SlotSessionLoadResult.Loaded -> initializing(migrated(legacy.session, defaultName))
            SlotSessionLoadResult.Absent, SlotSessionLoadResult.Unsupported ->
                initializing(CameraListSnapshot.seeded(defaultName))
        }
        ManagedCameraListLoadResult.Undecodable -> initializing(CameraListSnapshot.replacement(defaultName, generateId))
        is ManagedCameraListLoadResult.Loaded -> restoredList(loaded.list)
    }

    private fun readFailed(): Restored {
        isReadFailed = true
        return Restored(EMPTY, needsInitialSave = false)
    }

    /** A list that becomes authoritative only after the sequence is initialized. */
    private fun initializing(list: CameraListSnapshot): Restored {
        val target = when (val sequence = sequenceStore.load()) {
            is CameraNameSequenceLoadResult.Value ->
                if (CameraNameSequenceRange.isUsable(sequence.nextNumber)) sequence.nextNumber else INITIAL_SEQUENCE_VALUE
            CameraNameSequenceLoadResult.Absent, CameraNameSequenceLoadResult.Unusable,
            CameraNameSequenceLoadResult.ReadFailed -> INITIAL_SEQUENCE_VALUE
        }
        pendingSequenceTarget = target
        return Restored(list, needsInitialSave = true)
    }

    /** CAMERA-PERSIST-004 per-record defaults; reports whether the list needs rewriting. */
    private fun restoredList(decoded: DecodedManagedCameraList): Restored {
        var normalized = decoded.skippedEntryCount > 0
        val cameras = ArrayList<CameraListEntry>()
        val snapshots = HashMap<CameraSlotId, SlotCalculatorSnapshot>()
        val issued = decoded.issuedIds.mapNotNull { runCatching { CameraSlotId(it) }.getOrNull() }.toMutableSet()
        val seen = HashSet<CameraSlotId>()
        for (record in decoded.cameras) {
            val stored = record.id?.let { runCatching { CameraSlotId(it) }.getOrNull() }
            val id = if (stored != null && seen.add(stored)) {
                stored
            } else {
                normalized = true
                var fresh = generateId()
                while (fresh in seen || fresh in issued) fresh = generateId()
                seen.add(fresh)
                fresh
            }
            issued.add(id)
            val name = CameraNaming.trimmedName(record.name)
            if (name == null || record.isDisplayed == null || record.calculator == null) normalized = true
            cameras.add(CameraListEntry(id, name ?: recordFallbackName, record.isDisplayed ?: true))
            record.calculator?.let { snapshots[id] = it }
        }
        val active = decoded.activeCameraId?.let { runCatching { CameraSlotId(it) }.getOrNull() }
        return Restored(
            CameraListSnapshot(cameras = cameras, activeSlotId = active, issuedIds = issued, snapshots = snapshots),
            needsInitialSave = normalized,
        )
    }

    /**
     * Reserves the next automatic number durably before the camera is
     * committed (CAMERA-003, PERSIST-CAMERA-SEQUENCE-002/003). A failed or
     * interrupted creation may leave a gap; an issued number is never reused
     * while the sequence stays readable. A missing, unreadable, undecodable, or out-of-range
     * (below 5, or `Int.MAX_VALUE`) sequence starts normal allocation at 5, which stores 6 before `Camera 5` is
     * committed. A sequence read that fails is treated the same way (the
     * normal allocator fallback); it is not the blocked camera-list state.
     * Returns `null` when camera state is read-only or the reservation write
     * failed.
     */
    @Synchronized
    fun reserveNextCameraNumber(): Int? {
        if (isReadFailed) return null
        val number = when (val current = sequenceStore.load()) {
            is CameraNameSequenceLoadResult.Value ->
                if (CameraNameSequenceRange.isUsable(current.nextNumber)) current.nextNumber else INITIAL_SEQUENCE_VALUE
            CameraNameSequenceLoadResult.Absent, CameraNameSequenceLoadResult.Unusable,
            CameraNameSequenceLoadResult.ReadFailed -> INITIAL_SEQUENCE_VALUE
        }
        if (!sequenceStore.save(number + 1)) return null
        return number
    }

    /**
     * Writes the pending sequence value before the first managed payload
     * (fresh install, migration, replacement). Advance-only: a readable value
     * at or above the target is never lowered or replaced; an absent, unusable, or
     * unreadable sequence is written with the target. Returns whether the
     * managed payload may now be written.
     */
    private fun ensureSequenceInitialized(): Boolean {
        val target = pendingSequenceTarget ?: return true
        when (val current = sequenceStore.load()) {
            is CameraNameSequenceLoadResult.Value ->
                if ((!CameraNameSequenceRange.isUsable(current.nextNumber) || current.nextNumber < target) &&
                    !sequenceStore.save(target)
                ) {
                    return false
                }
            CameraNameSequenceLoadResult.Absent, CameraNameSequenceLoadResult.Unusable,
            CameraNameSequenceLoadResult.ReadFailed ->
                if (!sequenceStore.save(target)) return false
        }
        pendingSequenceTarget = null
        return true
    }

    /**
     * Persists the whole managed list in one write, so list entries, order,
     * pager inclusion, active camera, and calculator states land together
     * (CAMERA-PERSIST-005). Never writes after a failed read. Returns whether
     * the payload was committed.
     */
    @Synchronized
    fun save(list: CameraListSnapshot): Boolean {
        if (isReadFailed) return false
        // Sequence before payload (CAMERA-PERSIST-001/002): without it the
        // managed list is not committed, so a retry stays consistent.
        if (!ensureSequenceInitialized()) return false
        return managedStore.save(
            PersistentManagedCameraList(
                issuedIds = list.issuedIds.map { it.raw }.sorted(),
                activeCameraId = list.activeSlotId?.raw,
                cameras = list.cameras.map { camera ->
                    PersistentManagedCamera(
                        id = camera.id.raw,
                        name = camera.name,
                        isDisplayed = camera.isDisplayed,
                        calculator = list.snapshots[camera.id],
                    )
                },
            ),
        )
    }

    companion object {
        /** The first automatic number after the four legacy cameras. */
        const val INITIAL_SEQUENCE_VALUE: Int = 5

        private val EMPTY = CameraListSnapshot(emptyList(), null, emptySet(), emptyMap())

        /**
         * CAMERA-PERSIST-002/003: the four legacy cameras migrate in their
         * existing order with their identities, names, and calculator state,
         * all shown in the pager. An unnamed slot freezes its resolved
         * `Camera N` string.
         */
        fun migrated(session: PersistentSlotSession, defaultName: (Int) -> String): CameraListSnapshot {
            val legacy = CameraSlotId.legacyOrdered
            return CameraListSnapshot(
                cameras = legacy.mapIndexed { index, id ->
                    CameraListEntry(id, CameraNaming.trimmedName(session.customNames[id]) ?: defaultName(index + 1))
                },
                activeSlotId = session.activeSlotId.takeIf { it in legacy } ?: CameraSlotId.camera1,
                issuedIds = legacy.toSet(),
                snapshots = session.snapshots.filterKeys { it in legacy },
            )
        }
    }
}
