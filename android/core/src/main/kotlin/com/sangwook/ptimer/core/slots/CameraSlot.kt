package com.sangwook.ptimer.core.slots

import kotlinx.serialization.Serializable

/**
 * Stable identity for a shooting-session camera slot. The MVP ships
 * Camera 1 through Camera 4; identities stay stable across slot switches
 * and persist into timer metadata so a timer can be associated with the
 * camera that started it. (iOS: CameraSlotID.)
 */
@Serializable
enum class CameraSlotId {
    camera1,
    camera2,
    camera3,
    camera4;

    /** Canonical, locale-stable label tied to the slot id. */
    val defaultDisplayName: String
        get() = when (this) {
            camera1 -> "Camera 1"
            camera2 -> "Camera 2"
            camera3 -> "Camera 3"
            camera4 -> "Camera 4"
        }

    /** Compact label for timer metadata / pager chips ("C1".."C4"). */
    val shortLabel: String
        get() = "C${ordinal + 1}"

    companion object {
        /** Default order surfaced by the session model and slot pager. */
        val allOrdered: List<CameraSlotId> = entries.toList()
    }
}

/**
 * View-facing pair of stable id + display label. The display layer reads
 * [displayName], which prefers a non-blank [customDisplayName] and
 * otherwise falls back to the canonical `Camera N`. The rename / reset
 * surface writes only [customDisplayName]; clearing it restores the
 * default without touching slot identity. (iOS: CameraSlotIdentity.)
 */
data class CameraSlotIdentity(
    val id: CameraSlotId,
    val customDisplayName: String? = null,
) {
    val displayName: String
        get() = customDisplayName?.trim()?.takeIf { it.isNotEmpty() } ?: id.defaultDisplayName
}

/**
 * Per-slot snapshot of the calculator working state. Inactive slots keep
 * their snapshot in the session so a switch can restore the slot's
 * exposure inputs and film selection without resetting the active
 * calculator. Stored in controller-native terms (wheel indices + film /
 * profile ids) rather than re-deriving seconds. (iOS:
 * CameraSlotCalculatorSnapshot.)
 */
@Serializable
data class SlotCalculatorSnapshot(
    val shutterIndex: Int,
    val ndIndex: Int,
    val selectedFilmId: String?,
    val selectedProfileId: String?,
    /** Per-slot Target Shutter duration in seconds; `null` when unset. */
    val targetSeconds: Double? = null,
)

/**
 * Owns the camera-slot session state: which slot is active and the
 * calculator snapshot for every slot the user is not currently on.
 * Inactive snapshots stay untouched so a slot switch restores the slot's
 * inputs without invoking any reset on the active calculator. The active
 * slot's snapshot is intentionally absent — its live state lives on the
 * caller (the calculator controller). (iOS: CameraSlotSessionModel.)
 */
class CameraSlotSession(
    val availableSlots: List<CameraSlotId> = CameraSlotId.allOrdered,
    initialActiveSlotId: CameraSlotId = CameraSlotId.camera1,
    private val defaultSnapshot: SlotCalculatorSnapshot,
    initialSnapshots: Map<CameraSlotId, SlotCalculatorSnapshot> = emptyMap(),
    initialCustomNames: Map<CameraSlotId, String> = emptyMap(),
) {
    init {
        require(availableSlots.size >= 2) { "Camera slot session must expose at least two slots." }
        require(availableSlots.size <= CameraSlotId.entries.size) {
            "Camera slot session must expose at most ${CameraSlotId.entries.size} slots."
        }
        require(availableSlots.toSet().size == availableSlots.size) {
            "Camera slot session must expose unique slot ids."
        }
        require(initialActiveSlotId in availableSlots) {
            "Initial active slot must be one of the available slots."
        }
    }

    var activeSlotId: CameraSlotId = initialActiveSlotId
        private set

    private val inactiveSnapshots: MutableMap<CameraSlotId, SlotCalculatorSnapshot> =
        initialSnapshots.filterKeys { it != initialActiveSlotId }.toMutableMap()

    private val customNames: MutableMap<CameraSlotId, String> =
        sanitizeCustomNames(initialCustomNames).toMutableMap()

    /** Identity for an arbitrary slot, merging default + custom name. */
    fun identity(slotId: CameraSlotId): CameraSlotIdentity =
        CameraSlotIdentity(slotId, customNames[slotId])

    val activeIdentity: CameraSlotIdentity get() = identity(activeSlotId)

    /** Identities for every available slot, in pager order. */
    fun identities(): List<CameraSlotIdentity> = availableSlots.map { identity(it) }

    /**
     * Sets a slot's photographer-supplied name. Whitespace is trimmed; an
     * empty / blank / null value clears the custom entry.
     */
    fun setCustomName(name: String?, slotId: CameraSlotId) {
        if (slotId !in availableSlots) return
        val trimmed = name?.trim()
        if (!trimmed.isNullOrEmpty()) customNames[slotId] = trimmed else customNames.remove(slotId)
    }

    fun resetCustomName(slotId: CameraSlotId) {
        if (slotId !in availableSlots) return
        customNames.remove(slotId)
    }

    /** Snapshot for an inactive slot (the default when none stored); null for the active/unknown slot. */
    fun snapshot(forInactiveSlot: CameraSlotId): SlotCalculatorSnapshot? {
        if (forInactiveSlot == activeSlotId || forInactiveSlot !in availableSlots) return null
        return inactiveSnapshots[forInactiveSlot] ?: defaultSnapshot
    }

    /**
     * Atomic slot switch: stores [outgoingSnapshot] for the currently
     * active slot, makes [targetSlotId] active, and returns the snapshot
     * the caller should load into the live calculator for the incoming
     * slot. A no-op switch (target already active, or unknown) returns
     * null so the caller can skip redundant model writes.
     */
    fun switchActiveSlot(
        targetSlotId: CameraSlotId,
        outgoingSnapshot: SlotCalculatorSnapshot,
    ): SlotCalculatorSnapshot? {
        if (targetSlotId !in availableSlots || targetSlotId == activeSlotId) return null
        inactiveSnapshots[activeSlotId] = outgoingSnapshot
        val incoming = inactiveSnapshots.remove(targetSlotId) ?: defaultSnapshot
        activeSlotId = targetSlotId
        return incoming
    }

    /** Snapshot of every inactive slot (the active slot's live state lives on the caller). */
    fun currentInactiveSnapshots(): Map<CameraSlotId, SlotCalculatorSnapshot> = inactiveSnapshots.toMap()

    /** Current photographer-supplied display names, keyed by slot. */
    fun currentCustomNames(): Map<CameraSlotId, String> = customNames.toMap()

    private fun sanitizeCustomNames(names: Map<CameraSlotId, String>): Map<CameraSlotId, String> {
        val allowed = availableSlots.toSet()
        return names.mapNotNull { (slot, value) ->
            if (slot !in allowed) return@mapNotNull null
            val trimmed = value.trim()
            if (trimmed.isEmpty()) null else slot to trimmed
        }.toMap()
    }
}
