package com.sangwook.ptimer.slots

import com.sangwook.ptimer.calculator.SlotCalculatorSnapshot

/**
 * Per-camera-slot session: each of the (up to 4) slots keeps its own
 * calculator/film/model snapshot and an optional custom display name.
 * Switching captures the outgoing slot and restores the incoming one;
 * renaming is isolated from calculator state and from already-started
 * timers. Android-free / JVM-testable. Mirrors iOS `CameraSlotSessionModel`.
 */
class CameraSlotSession(
    val slotIds: List<String> = listOf("camera1", "camera2", "camera3", "camera4"),
) {
    var activeSlotId: String = slotIds.first()
        private set

    private val snapshots = HashMap<String, SlotCalculatorSnapshot>()
    private val customNames = HashMap<String, String>()

    fun snapshot(id: String): SlotCalculatorSnapshot? = snapshots[id]

    /** Store the captured snapshot for a slot (typically the outgoing active slot). */
    fun store(id: String, snapshot: SlotCalculatorSnapshot) { snapshots[id] = snapshot }

    fun activate(id: String) {
        require(id in slotIds) { "Unknown slot $id" }
        activeSlotId = id
    }

    /** Set a custom display name; blank/whitespace clears it back to the canonical label. */
    fun setCustomName(id: String, name: String) {
        if (id !in slotIds) return // ignore unknown slot ids
        val trimmed = name.trim()
        if (trimmed.isEmpty()) customNames.remove(id) else customNames[id] = trimmed
    }

    fun resetName(id: String) { customNames.remove(id) }

    fun label(id: String): String = customNames[id] ?: canonicalLabel(id)

    fun customNames(): Map<String, String> = HashMap(customNames)

    fun activeLabel(): String = label(activeSlotId)

    private fun canonicalLabel(id: String): String {
        val index = slotIds.indexOf(id)
        return if (index >= 0) "Camera ${index + 1}" else id
    }

    /**
     * Replace runtime state from persistence. Only known slot ids survive;
     * names are run through the same trim/drop-blank rules as
     * [setCustomName] so a corrupt snapshot cannot smuggle in
     * blank/whitespace names or entries for unknown slots, and no stale
     * prior entry is retained.
     */
    fun restore(activeSlotId: String, snapshots: Map<String, SlotCalculatorSnapshot>, names: Map<String, String>) {
        this.snapshots.clear()
        for ((id, snapshot) in snapshots) if (id in slotIds) this.snapshots[id] = snapshot
        this.customNames.clear()
        for ((id, name) in names) {
            if (id !in slotIds) continue
            val trimmed = name.trim()
            if (trimmed.isNotEmpty()) this.customNames[id] = trimmed
        }
        this.activeSlotId = if (activeSlotId in slotIds) activeSlotId else slotIds.first()
    }

    fun allSnapshots(): Map<String, SlotCalculatorSnapshot> = HashMap(snapshots)
}
