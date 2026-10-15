// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.core.slots

/** One managed camera in the global camera list. (iOS: CameraListEntry.) */
data class CameraListEntry(
    val id: CameraSlotId,
    /** Stored, trimmed, non-empty name. */
    val name: String,
    /** Whether the camera is included in the shooting pager. */
    val isDisplayed: Boolean = true,
)

/**
 * The whole managed camera list as one value: the restore input and the
 * export of [CameraSlotSession]. [snapshots] holds the calculator state of
 * every camera (the active one included); a camera without an entry has
 * fresh calculator defaults.
 */
data class CameraListSnapshot(
    val cameras: List<CameraListEntry>,
    /** `null` is the explicit "no active camera" state. */
    val activeSlotId: CameraSlotId?,
    /** Every identity ever issued, deleted cameras included. */
    val issuedIds: Set<CameraSlotId>,
    val snapshots: Map<CameraSlotId, SlotCalculatorSnapshot>,
) {
    companion object {
        /**
         * The fresh-install list: `camera1` ... `camera4`, in that order,
         * shown in the pager, with `Camera N` names frozen as stored text.
         */
        fun seeded(defaultName: (Int) -> String): CameraListSnapshot = CameraListSnapshot(
            cameras = CameraSlotId.legacyOrdered.mapIndexed { index, id ->
                CameraListEntry(id, defaultName(index + 1))
            },
            activeSlotId = CameraSlotId.camera1,
            issuedIds = CameraSlotId.legacyOrdered.toSet(),
            snapshots = emptyMap(),
        )

        /**
         * Atomic replacement of undecodable managed content (CAMERA-PERSIST-004):
         * four default names with new opaque identities, shown in order, the
         * first active. The old identities are not reissued.
         */
        fun replacement(defaultName: (Int) -> String, generateId: () -> CameraSlotId): CameraListSnapshot {
            val ids = LinkedHashSet<CameraSlotId>()
            while (ids.size < 4) ids.add(generateId())
            val ordered = ids.toList()
            return CameraListSnapshot(
                cameras = ordered.mapIndexed { index, id -> CameraListEntry(id, defaultName(index + 1)) },
                activeSlotId = ordered.first(),
                issuedIds = ids,
                snapshots = emptyMap(),
            )
        }
    }
}

/**
 * Owns the managed camera list: the global order, each camera's name and
 * pager inclusion, the active camera (or the explicit absence of one), the
 * identities ever issued, and a stable calculator snapshot for *every*
 * camera. Switching the active camera is a pure change of [activeSlotId]
 * with no cross-camera capture/restore side effect — the caller (the
 * calculator controller) reads and mutates the active camera's snapshot in
 * place through [activeSnapshot] / [updateActiveSnapshot]. With no active
 * camera [activeSnapshot] reads the defaults and updates are no-ops.
 * (iOS: CameraSlotSessionModel; there the active camera's live state sits on
 * other models, here the session is the single per-camera owner.)
 */
class CameraSlotSession(
    initial: CameraListSnapshot,
    private val defaultSnapshot: SlotCalculatorSnapshot,
    private val generateId: () -> CameraSlotId = { CameraSlotId.generate() },
) {
    private val entries: MutableList<CameraListEntry>
    private val snapshots: MutableMap<CameraSlotId, SlotCalculatorSnapshot>
    private val issued: MutableSet<CameraSlotId>

    var activeSlotId: CameraSlotId? = null
        private set

    init {
        val seen = HashSet<CameraSlotId>()
        entries = initial.cameras.filter { seen.add(it.id) }.toMutableList()
        issued = (initial.issuedIds + entries.map { it.id }).toMutableSet()
        snapshots = entries.associate { it.id to (initial.snapshots[it.id] ?: defaultSnapshot) }.toMutableMap()
        val displayed = entries.filter { it.isDisplayed }.map { it.id }
        activeSlotId = initial.activeSlotId?.takeIf { it in displayed } ?: displayed.firstOrNull()
    }

    // --- Reads ---

    /** The managed list in global user-defined order. */
    val cameras: List<CameraListEntry> get() = entries.toList()

    /** Every camera id in global order, hidden cameras included. */
    val cameraIds: List<CameraSlotId> get() = entries.map { it.id }

    /** Cameras included in the shooting pager, in global order. */
    val displayedCameras: List<CameraListEntry> get() = entries.filter { it.isDisplayed }

    val displayedIds: List<CameraSlotId> get() = displayedCameras.map { it.id }

    val issuedIds: Set<CameraSlotId> get() = issued.toSet()

    fun entry(id: CameraSlotId): CameraListEntry? = entries.firstOrNull { it.id == id }

    /** Identity for a camera in the list, or `null` for an unknown id. */
    fun identity(id: CameraSlotId): CameraSlotIdentity? = entry(id)?.let { CameraSlotIdentity(it.id, it.name) }

    /** Identity of the active camera, or `null` when none is active. */
    val activeIdentity: CameraSlotIdentity? get() = activeSlotId?.let { identity(it) }

    // --- List edits ---

    /**
     * Adds a camera named [name] at the end of the list, shown in the pager
     * and active, with fresh calculator defaults (CAMERA-STATE-003). The
     * name comes from the automatic-name sequence, which the caller has
     * already advanced durably; the session never derives it from the
     * current cameras.
     */
    fun addCamera(name: String): CameraSlotId {
        var id = generateId()
        while (id in issued) id = generateId()
        issued.add(id)
        entries.add(CameraListEntry(id, name))
        snapshots[id] = defaultSnapshot
        activeSlotId = id
        return id
    }

    /**
     * Renames a camera. The name is trimmed; a blank name is rejected and
     * leaves the stored name unchanged. Returns whether it applied.
     */
    fun renameCamera(id: CameraSlotId, name: String): Boolean {
        val trimmed = CameraNaming.trimmedName(name) ?: return false
        val index = entries.indexOfFirst { it.id == id }
        if (index < 0) return false
        entries[index] = entries[index].copy(name = trimmed)
        return true
    }

    /** Shows or hides one camera. Hiding preserves name, state, and position. */
    fun setDisplayed(id: CameraSlotId, isDisplayed: Boolean) {
        if (!isDisplayed) {
            hideCameras(setOf(id))
            return
        }
        val index = entries.indexOfFirst { it.id == id }
        if (index < 0 || entries[index].isDisplayed) return
        entries[index] = entries[index].copy(isDisplayed = true)
        if (activeSlotId == null) activeSlotId = id
    }

    /** Hides several cameras in one change; ids no longer present are ignored. */
    fun hideCameras(ids: Set<CameraSlotId>) {
        val before = entries.toList()
        for (index in entries.indices) {
            if (entries[index].id in ids) entries[index] = entries[index].copy(isDisplayed = false)
        }
        resolveActiveAfterRemoval(before)
    }

    /**
     * Deletes several cameras and their calculator state in one change; ids
     * no longer present are ignored. Identities stay in the issued set so
     * they are never reused.
     */
    fun deleteCameras(ids: Set<CameraSlotId>) {
        val before = entries.toList()
        entries.removeAll { it.id in ids }
        ids.forEach { snapshots.remove(it) }
        resolveActiveAfterRemoval(before)
    }

    /** Moves one camera by [delta] positions in the global order (non-drag reorder). */
    fun moveCamera(id: CameraSlotId, delta: Int) {
        val index = entries.indexOfFirst { it.id == id }
        if (index < 0) return
        val target = (index + delta).coerceIn(0, entries.lastIndex)
        if (target == index) return
        entries.add(target, entries.removeAt(index))
    }

    /**
     * CAMERA-PAGER-003: when the active camera was hidden or removed, the
     * next displayed camera in the resulting global order becomes active;
     * with none after it, the first displayed camera; with no displayed
     * camera, none.
     */
    private fun resolveActiveAfterRemoval(previous: List<CameraListEntry>) {
        val active = activeSlotId ?: return
        if (entry(active)?.isDisplayed == true) return
        val activeIndex = previous.indexOfFirst { it.id == active }
        val survivorsAfter = previous
            .drop(activeIndex + 1)
            .mapNotNull { old -> entry(old.id) }
            .filter { it.isDisplayed }
        activeSlotId = survivorsAfter.firstOrNull()?.id ?: displayedCameras.firstOrNull()?.id
    }

    // --- Snapshots ---

    /** Snapshot for any camera in the list (active or not); null for an unknown id. */
    fun snapshot(id: CameraSlotId): SlotCalculatorSnapshot? = snapshots[id]

    /** The active camera's stable snapshot; the defaults when none is active. */
    val activeSnapshot: SlotCalculatorSnapshot
        get() = activeSlotId?.let { snapshots[it] } ?: defaultSnapshot

    /** Replaces the active camera's snapshot in place; a no-op with no active camera. */
    fun updateActiveSnapshot(transform: (SlotCalculatorSnapshot) -> SlotCalculatorSnapshot) {
        val active = activeSlotId ?: return
        snapshots[active] = transform(snapshots.getValue(active))
    }

    /**
     * Replaces any camera's snapshot in place (active included); an unknown
     * id is a no-op. Used when a change outside the calculator — an
     * inventory edit — has to be applied to every camera, not just the
     * active one. (iOS: `updateInactiveSnapshots`.)
     */
    fun updateSnapshot(id: CameraSlotId, transform: (SlotCalculatorSnapshot) -> SlotCalculatorSnapshot) {
        val current = snapshots[id] ?: return
        snapshots[id] = transform(current)
    }

    /**
     * Makes [target] the active camera. Each camera keeps its own snapshot,
     * so no capture/restore crosses cameras. Returns false for a no-op
     * (unknown or hidden target, or the camera is already active) so the
     * caller can skip a redundant republish.
     */
    fun switchActiveSlot(target: CameraSlotId): Boolean {
        if (entry(target)?.isDisplayed != true || target == activeSlotId) return false
        activeSlotId = target
        return true
    }

    /** The whole list as a value, for persistence. */
    fun export(): CameraListSnapshot = CameraListSnapshot(
        cameras = cameras,
        activeSlotId = activeSlotId,
        issuedIds = issuedIds,
        snapshots = snapshots.toMap(),
    )
}
