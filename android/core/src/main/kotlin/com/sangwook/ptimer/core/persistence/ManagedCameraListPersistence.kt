// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.core.persistence

import com.sangwook.ptimer.core.slots.SlotCalculatorSnapshot
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.intOrNull

// On-disk shape of the managed camera list: the global order, each camera's
// name, pager inclusion, and calculator state, the active camera (absent when
// no camera is displayed), and every identity ever issued so a deleted
// camera's identity is never reused. Stored under its own key, separate from
// the legacy slot-session payload, which stays untouched as the migration
// source (CAMERA-PERSIST-006). (iOS: PersistentManagedCameraListSnapshot.)

/** One persisted managed camera. */
@Serializable
data class PersistentManagedCamera(
    val id: String,
    val name: String,
    val isDisplayed: Boolean,
    /** Absent or undecodable restores as fresh calculator defaults (CAMERA-PERSIST-005). */
    val calculator: SlotCalculatorSnapshot? = null,
)

@Serializable
data class PersistentManagedCameraList(
    val schemaVersion: Int = CURRENT_SCHEMA_VERSION,
    /** Identities ever issued, deleted cameras included. */
    val issuedIds: List<String>,
    /** `null` is the explicit "no active camera" state. */
    val activeCameraId: String?,
    val cameras: List<PersistentManagedCamera>,
) {
    companion object {
        const val CURRENT_SCHEMA_VERSION: Int = 1
    }
}

/**
 * One keyed camera record as read from storage. Every field is optional: the
 * restore layer applies the CAMERA-PERSIST-004 defaults for what is missing
 * or has the wrong type.
 */
data class DecodedManagedCamera(
    val id: String?,
    val name: String?,
    val isDisplayed: Boolean?,
    val calculator: SlotCalculatorSnapshot?,
)

/**
 * A decoded managed payload. Cameras decode one by one: an entry that is not
 * a keyed camera record is skipped without preventing the others from
 * restoring (CAMERA-PERSIST-004). [skippedEntryCount] lets the restore layer
 * persist the normalized list as the current shape.
 */
data class DecodedManagedCameraList(
    val issuedIds: List<String>,
    val activeCameraId: String?,
    val cameras: List<DecodedManagedCamera>,
    val skippedEntryCount: Int,
)

/** Outcome of loading the managed camera list. */
sealed interface ManagedCameraListLoadResult {
    /** No managed payload exists; legacy migration may run. */
    data object Absent : ManagedCameraListLoadResult

    /** A valid managed payload. */
    data class Loaded(val list: DecodedManagedCameraList) : ManagedCameraListLoadResult

    /**
     * Content was read successfully but its version, camera collection, or
     * whole payload cannot be decoded. The restore layer atomically replaces
     * it with fresh camera state; legacy data is never used in its place
     * (CAMERA-PERSIST-004/006).
     */
    data object Undecodable : ManagedCameraListLoadResult

    /**
     * The read itself failed and supplied no content. Camera state is not
     * made authoritative, nothing is deleted or written, and initialization
     * retries on the next launch (CAMERA-PERSIST-004/006).
     */
    data object ReadFailed : ManagedCameraListLoadResult
}

/** Persistence boundary for the managed camera list. */
interface ManagedCameraListStoring {
    fun load(): ManagedCameraListLoadResult

    /** Writes the whole payload in one operation. Returns whether it was committed. */
    fun save(payload: PersistentManagedCameraList): Boolean
}

/** In-memory store: the default when none is injected, and the test double. */
class InMemoryManagedCameraListStore(
    var result: ManagedCameraListLoadResult = ManagedCameraListLoadResult.Absent,
) : ManagedCameraListStoring {
    var failsWrites = false
    var saveCount = 0
        private set
    var lastSaved: PersistentManagedCameraList? = null
        private set

    override fun load(): ManagedCameraListLoadResult = result

    override fun save(payload: PersistentManagedCameraList): Boolean {
        if (failsWrites) return false
        saveCount++
        lastSaved = payload
        result = ManagedCameraListCodec.decode(ManagedCameraListCodec.encode(payload))
        return true
    }
}

/**
 * Pure JSON codec for the managed list. Encoding is total. Decoding rejects a
 * payload that is not a JSON object, carries a version other than the current
 * one, or has no `cameras` array; within an accepted payload each camera, and
 * each camera's calculator state, decodes in isolation; a missing field in a keyed record is left
 * absent for the restore layer to default.
 */
object ManagedCameraListCodec {
    private val json = Json { ignoreUnknownKeys = true; encodeDefaults = true }

    fun encode(payload: PersistentManagedCameraList): String = json.encodeToString(payload)

    /** [ManagedCameraListLoadResult.Loaded] or [ManagedCameraListLoadResult.Undecodable]. */
    fun decode(text: String): ManagedCameraListLoadResult {
        val root = try {
            json.parseToJsonElement(text) as? JsonObject
        } catch (_: Exception) {
            null
        } ?: return ManagedCameraListLoadResult.Undecodable
        val version = (root["schemaVersion"] as? JsonPrimitive)?.intOrNull
        if (version != PersistentManagedCameraList.CURRENT_SCHEMA_VERSION) {
            return ManagedCameraListLoadResult.Undecodable
        }
        val elements = root["cameras"] as? JsonArray ?: return ManagedCameraListLoadResult.Undecodable
        val issued = (root["issuedIds"] as? JsonArray)
            ?.mapNotNull { (it as? JsonPrimitive)?.takeIf { p -> p.isString }?.contentOrNull }
            ?: emptyList()
        val active = (root["activeCameraId"] as? JsonPrimitive)?.takeIf { it.isString }?.contentOrNull
        val cameras = elements.mapNotNull { decodeCamera(it) }
        return ManagedCameraListLoadResult.Loaded(
            DecodedManagedCameraList(
                issuedIds = issued,
                activeCameraId = active,
                cameras = cameras,
                skippedEntryCount = elements.size - cameras.size,
            ),
        )
    }

    private fun decodeCamera(element: JsonElement): DecodedManagedCamera? {
        val obj = element as? JsonObject ?: return null
        val id = (obj["id"] as? JsonPrimitive)?.takeIf { it.isString }?.contentOrNull
        val name = (obj["name"] as? JsonPrimitive)?.takeIf { it.isString }?.contentOrNull
        val shown = (obj["isDisplayed"] as? JsonPrimitive)?.booleanOrNull
        val calculator = obj["calculator"]?.takeIf { it !is JsonNull }?.let {
            runCatching { json.decodeFromJsonElement(SlotCalculatorSnapshot.serializer(), it) }.getOrNull()
        }
        return DecodedManagedCamera(id, name, shown, calculator)
    }
}
