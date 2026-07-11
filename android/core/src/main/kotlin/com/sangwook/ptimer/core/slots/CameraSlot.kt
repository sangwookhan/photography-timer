// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

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
 * Per-slot snapshot of the calculator working state. Every slot keeps its
 * own snapshot in the session so a switch preserves the slot's exposure
 * inputs and film selection without resetting the active calculator. Stored
 * in controller-native terms (wheel indices + film / profile ids) rather than
 * re-deriving seconds. (iOS: CameraSlotCalculatorSnapshot.)
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
 * Owns the camera-slot session state: which slot is active and a stable
 * calculator snapshot for *every* slot. Each slot's snapshot lives here for
 * the life of the session, so switching the active slot is a pure change of
 * [activeSlotId] with no cross-slot capture/restore side effect — the caller
 * (the calculator controller) reads and mutates the active slot's snapshot in
 * place through [activeSnapshot] / [updateActiveSnapshot]. (iOS keeps the
 * active slot's live state on its calc/film models; the Android controller has
 * no such split, so the session is the single per-slot owner here.)
 */
class CameraSlotSession(
    val availableSlots: List<CameraSlotId> = CameraSlotId.allOrdered,
    initialActiveSlotId: CameraSlotId = CameraSlotId.camera1,
    defaultSnapshot: SlotCalculatorSnapshot,
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

    // One stable snapshot per available slot (active included). Missing entries
    // seed from the default so every slot has an owner from construction.
    private val snapshots: MutableMap<CameraSlotId, SlotCalculatorSnapshot> =
        availableSlots.associateWith { initialSnapshots[it] ?: defaultSnapshot }.toMutableMap()

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

    /** Snapshot for any available slot (active or not); null for an unknown slot. */
    fun snapshot(slotId: CameraSlotId): SlotCalculatorSnapshot? =
        if (slotId in availableSlots) snapshots.getValue(slotId) else null

    /** The active slot's stable snapshot. */
    val activeSnapshot: SlotCalculatorSnapshot get() = snapshots.getValue(activeSlotId)

    /** Replaces the active slot's snapshot in place; other slots are untouched. */
    fun updateActiveSnapshot(transform: (SlotCalculatorSnapshot) -> SlotCalculatorSnapshot) {
        snapshots[activeSlotId] = transform(snapshots.getValue(activeSlotId))
    }

    /**
     * Makes [targetSlotId] the active slot. Each slot keeps its own snapshot
     * entry, so no capture/restore crosses slots. Returns false for a no-op
     * (unknown target, or the slot is already active) so the caller can skip
     * a redundant republish.
     */
    fun switchActiveSlot(targetSlotId: CameraSlotId): Boolean {
        if (targetSlotId !in availableSlots || targetSlotId == activeSlotId) return false
        activeSlotId = targetSlotId
        return true
    }

    /** Snapshot of every available slot (active included). */
    fun currentSnapshots(): Map<CameraSlotId, SlotCalculatorSnapshot> = snapshots.toMap()

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
