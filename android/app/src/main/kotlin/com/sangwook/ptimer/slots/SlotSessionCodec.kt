package com.sangwook.ptimer.slots

import com.sangwook.ptimer.calculator.SlotCalculatorSnapshot
import kotlinx.serialization.Serializable
import kotlinx.serialization.decodeFromString
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json

/**
 * Serializes the camera-slot session (active slot, per-slot calculator
 * snapshots, custom names) for DataStore persistence. Greenfield: calculator
 * context lives inside the slot-session snapshot (no separate legacy
 * single-context store). Corrupt/unknown-version payloads decode to empty.
 */
object SlotSessionCodec {
    private const val SCHEMA_VERSION = 1
    private val json = Json { ignoreUnknownKeys = true; encodeDefaults = true }

    @Serializable
    private data class SlotDto(
        val slotId: String,
        val customName: String? = null,
        val snapshot: SlotCalculatorSnapshot? = null,
    )

    @Serializable
    private data class SessionDto(
        val schemaVersion: Int = SCHEMA_VERSION,
        val activeSlotId: String,
        val slots: List<SlotDto> = emptyList(),
    )

    data class Restored(
        val activeSlotId: String,
        val snapshots: Map<String, SlotCalculatorSnapshot>,
        val names: Map<String, String>,
    )

    fun encode(session: CameraSlotSession): String {
        val snaps = session.allSnapshots()
        val names = session.customNames()
        val slotIds = (snaps.keys + names.keys).toSortedSet()
        val slots = slotIds.map { SlotDto(it, names[it], snaps[it]) }
        return json.encodeToString(SessionDto(SCHEMA_VERSION, session.activeSlotId, slots))
    }

    fun decode(text: String): Restored? {
        val session = try {
            json.decodeFromString<SessionDto>(text)
        } catch (_: Exception) {
            return null
        }
        if (session.schemaVersion != SCHEMA_VERSION) return null
        val snapshots = LinkedHashMap<String, SlotCalculatorSnapshot>()
        val names = LinkedHashMap<String, String>()
        for (slot in session.slots) {
            slot.snapshot?.let { snapshots[slot.slotId] = it }
            slot.customName?.let { names[slot.slotId] = it }
        }
        return Restored(session.activeSlotId, snapshots, names)
    }
}
