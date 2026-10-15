// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.core.slots

import com.sangwook.ptimer.core.exposure.ExposureScale
import com.sangwook.ptimer.core.exposure.NdFilterStack
import kotlinx.serialization.KSerializer
import kotlinx.serialization.Serializable
import kotlinx.serialization.SerializationException
import kotlinx.serialization.descriptors.PrimitiveKind
import kotlinx.serialization.descriptors.PrimitiveSerialDescriptor
import kotlinx.serialization.descriptors.SerialDescriptor
import kotlinx.serialization.encoding.Decoder
import kotlinx.serialization.encoding.Encoder
import java.util.UUID

/**
 * Stable identity for a managed camera. It never changes for the life of
 * a camera, is never reassigned to a different camera after deletion, and
 * persists into timer metadata so a timer can be associated with the camera
 * that started it. The four identities of the fixed-slot product
 * (`camera1` ... `camera4`) are kept verbatim as the migrated cameras'
 * identities; every other identity is generated and is not derived from a
 * list position or a display name. Serialized as a plain string, so legacy
 * payloads keyed by `camera1` ... `camera4` read unchanged.
 * (iOS: CameraSlotID.)
 */
@Serializable(with = CameraSlotIdSerializer::class)
data class CameraSlotId(val raw: String) {
    init {
        require(raw.isNotBlank()) { "Camera id must not be blank." }
    }

    /** `Camera N` number for a legacy identity; `null` for any other. */
    val legacyNumber: Int? get() = legacyOrdered.indexOf(this).takeIf { it >= 0 }?.plus(1)

    companion object {
        val camera1 = CameraSlotId("camera1")
        val camera2 = CameraSlotId("camera2")
        val camera3 = CameraSlotId("camera3")
        val camera4 = CameraSlotId("camera4")

        /** The identities of the fixed-slot product, in their original order. */
        val legacyOrdered: List<CameraSlotId> = listOf(camera1, camera2, camera3, camera4)

        /**
         * A new, collision-free identity. UUID-based so it is never derived
         * from a position or a name and cannot collide with a legacy
         * `cameraN` raw value.
         */
        fun generate(): CameraSlotId = CameraSlotId("camera-${UUID.randomUUID().toString().lowercase()}")
    }
}

object CameraSlotIdSerializer : KSerializer<CameraSlotId> {
    override val descriptor: SerialDescriptor = PrimitiveSerialDescriptor("CameraSlotId", PrimitiveKind.STRING)

    override fun serialize(encoder: Encoder, value: CameraSlotId) = encoder.encodeString(value.raw)

    override fun deserialize(decoder: Decoder): CameraSlotId {
        val raw = decoder.decodeString()
        return try {
            CameraSlotId(raw)
        } catch (_: IllegalArgumentException) {
            throw SerializationException("Empty camera id")
        }
    }
}

/**
 * View-facing pair of stable id + display name. Timer metadata captures it
 * at timer start, so a later rename, hide, reorder, or delete of the camera
 * never changes what an existing timer shows. (iOS: CameraSlotIdentity.)
 */
data class CameraSlotIdentity(
    val id: CameraSlotId,
    /** The camera's stored name (trimmed, non-empty). */
    val displayName: String,
) {
    /** Identity named by the legacy `Camera N` label (or the raw identity
     *  for any other camera), for callers that hold only an id. */
    constructor(id: CameraSlotId) : this(id, id.legacyNumber?.let { "Camera $it" } ?: id.raw)
}

/** Camera naming rules shared by seeding, migration, rename, and add. */
object CameraNaming {
    /** Trimmed name, or `null` for a blank / whitespace-only value. */
    fun trimmedName(name: String?): String? = name?.trim()?.takeIf { it.isNotEmpty() }

    /**
     * Compact camera badge for timer cards, derived only from what the
     * timer captured so it never depends on the current camera list.
     * Legacy identities keep `C1`...`C4`; any other camera uses the first
     * letter plus the last two digits of a trailing number (`Leica M6` ->
     * `L6`, `Camera 123` -> `C23`), the last two digits of a name made only
     * of digits (`35` -> `35`), otherwise the first two letters. (iOS:
     * TimerCardIdentityPresenter.compactCameraLabel.)
     */
    fun compactLabel(id: CameraSlotId, name: String): String {
        id.legacyNumber?.let { return "C$it" }
        val trailingDigits = name.takeLastWhile { it.isDigit() }
        if (trailingDigits.isNotEmpty()) {
            val shown = trailingDigits.takeLast(2)
            if (trailingDigits.length == name.length) return shown
            return (name.first().toString() + shown).uppercase()
        }
        return name.take(2).uppercase()
    }
}

/**
 * Per-slot snapshot of the calculator working state. Every slot keeps its
 * own snapshot in the session so a switch preserves the slot's exposure
 * inputs and film selection without resetting the active calculator. Stored
 * in controller-native terms rather than re-deriving seconds: [shutterIndex]
 * is a wheel position, while ND is kept as the canonical stop value —
 * [ndIndex] carries the whole-stop value (the legacy field / fallback) and
 * [ndStops] the exact value for a commercial preset (PTIMER-209). Film /
 * profile are ids. (iOS: CameraSlotCalculatorSnapshot.)
 */
@Serializable
data class SlotCalculatorSnapshot(
    val shutterIndex: Int,
    /**
     * Whole-stop ND value (0…30). Kept as the legacy field and the fallback
     * when [ndStops] is absent, so pre-PTIMER-209 payloads decode unchanged.
     * For a commercial preset this holds the nearest whole stop; the exact
     * value lives in [ndStops].
     */
    val ndIndex: Int,
    val selectedFilmId: String?,
    val selectedProfileId: String?,
    /** Per-slot Target Shutter duration in seconds; `null` when unset. */
    val targetSeconds: Double? = null,
    /**
     * Exact ND strength in stops for a supported commercial preset (PTIMER-209:
     * 6.6, 7.6, 16.6). Additive optional: whole-stop selections leave it null,
     * so pre-PTIMER-209 payloads stay backward-compatible. Preferred over
     * [ndIndex] by [canonicalNDStops] when it matches a preset, so a value like
     * 6.6 is not truncated to a whole stop on restore.
     */
    val ndStops: Double? = null,
    /**
     * ND filter wheel stack (PTIMER-199): committed wheel values in
     * display order, canonical stops, 1..4 entries. Additive optional
     * so pre-stack payloads decode unchanged. When present AND valid
     * it is the source of truth; [ndIndex]/[ndStops] then carry the
     * MAXIMUM wheel so an older build downgrades to the strongest
     * single filter (iOS parity). Invalid stacks are rejected at read
     * time (never clamped) and fall back to the legacy scalar.
     */
    val ndStack: List<Double>? = null,
    /**
     * Mixed Filter Stack (Filter Set contract, FILTER-PERSIST-001): every
     * wheel in display order, Standard and Filter Set sources alike.
     * Additive optional so pre-Filter-Set payloads decode unchanged. When
     * present and structurally sound it is authoritative, and [ndStack] /
     * [ndIndex] / [ndStops] carry the Standard-only projection an older
     * build restores.
     */
    val filterStack: List<PersistentFilterWheel>? = null,
    /**
     * The slot's last settled Filter Source (FILTER-PLUS-004):
     * `"standard"` or `"filterSet"` (with [lastFilterSetId]). Additive
     * optional; absent or unresolvable restores as Standard.
     */
    val lastFilterSourceKind: String? = null,
    val lastFilterSetId: String? = null,
    /**
     * Mounted auxiliary filters (FILTER-AUX-001), one entry per mounted
     * item in display order. Additive optional: a snapshot written before
     * auxiliary filters existed omits it, and any CPL / GND rows still in
     * [filterStack] migrate into auxiliary filters on restore
     * (FILTER-PERSIST-002).
     */
    val auxiliaryFilters: List<PersistentAuxiliaryFilter>? = null,
    /**
     * The slot's candidate Filter Sets (FILTER-CAMERA-001) by stable id.
     * Additive optional: absent means no explicit assignment; the sets
     * referenced by the restored wheels and auxiliary filters are always
     * included on restore.
     */
    val candidateFilterSetIds: List<String>? = null,
)

/**
 * Canonical ND strength in stops for this snapshot: the exact preset value
 * when [SlotCalculatorSnapshot.ndStops] matches a supported commercial preset,
 * otherwise the legacy whole-stop [SlotCalculatorSnapshot.ndIndex]. An
 * unsupported [ndStops] is ignored so the fixed product set stays a domain
 * invariant. Mirrors iOS `restoredNDStep` precedence.
 */
fun SlotCalculatorSnapshot.canonicalNDStops(): Double =
    ndStops?.let { ExposureScale.commercialNDPresetStop(it) } ?: ndIndex.toDouble()

/**
 * Canonical ND wheel stack for this snapshot (PTIMER-199): the
 * validated [SlotCalculatorSnapshot.ndStack] when present, otherwise a
 * single wheel holding the legacy scalar. Restore rejects — it never
 * clamps: an invalid persisted stack (bad count, off-ladder value,
 * over-30 sum) is treated as absent. Mirrors the iOS restore
 * precedence.
 */
fun SlotCalculatorSnapshot.canonicalNdStackStops(): List<Double> =
    if (NdFilterStack.isValidRestoredStack(ndStack)) {
        ndStack!!
    } else {
        listOf(canonicalNDStops())
    }
