// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.app.vm

import com.sangwook.ptimer.app.persistence.OrderedPersistenceWriter
import com.sangwook.ptimer.core.persistence.CameraListPersistenceController
import com.sangwook.ptimer.core.slots.CameraNaming
import com.sangwook.ptimer.core.slots.CameraSlotId

/**
 * The camera-list command surface: applies each edit to the
 * [CalculatorController] and persists the whole resulting list in one write
 * (CAMERA-PERSIST-005). It is the only place that pairs the live state with
 * [CameraListPersistenceController]; the controller stays free of persistence.
 *
 * After a storage read that supplied no content ([CameraListPersistenceController.isReadFailed])
 * camera state is not authoritative: every camera-list edit is ignored for
 * the session, so no write can replace data that may be healthy and unread.
 * Writes run on the shared persistence writer in submission order.
 */
class CameraListManager(
    private val calculator: CalculatorController,
    private val persistence: CameraListPersistenceController,
    private val writer: OrderedPersistenceWriter,
    /** Localized `Camera N` name; the generated name is frozen as stored text. */
    private val defaultName: (Int) -> String,
) {
    /** Whether camera-list edits apply; `false` for the launch after a failed storage read. */
    val isEditable: Boolean get() = !persistence.isReadFailed

    /**
     * Adds a camera named from the durable automatic-name sequence (`Camera 5`
     * first, then increasing, never reused while the sequence stays readable):
     * it joins the pager at the end and becomes active. The number is reserved
     * durably before the camera record is committed; a failure after that
     * point leaves a gap, never a reuse. Returns `null` when camera state is
     * read-only or the number could not be reserved.
     */
    suspend fun addCamera(): CameraSlotId? {
        if (persistence.isReadFailed) return null
        val number = writer.readOrdered { runCatching { persistence.reserveNextCameraNumber() }.getOrNull() } ?: return null
        val added = calculator.addCamera(defaultName(number))
        saveNow()
        return added
    }

    /** Renames a camera; a blank or unknown target changes nothing and returns false. */
    fun renameCamera(id: CameraSlotId, name: String): Boolean {
        if (persistence.isReadFailed) return false
        if (CameraNaming.trimmedName(name) == null || calculator.cameraIdentity(id) == null) return false
        val applied = calculator.renameCamera(id, name)
        saveNow()
        return applied
    }

    fun setCameraDisplayed(id: CameraSlotId, isDisplayed: Boolean) =
        edit { calculator.setCameraDisplayed(id, isDisplayed) }

    /** Non-drag reorder: moves one camera [delta] positions in the global order. */
    fun moveCamera(id: CameraSlotId, delta: Int) = edit { calculator.moveCamera(id, delta) }

    fun hideCameras(ids: Set<CameraSlotId>) = edit { calculator.hideCameras(ids) }

    /** Deletes cameras and their calculator state; the caller confirms with the user first. */
    fun deleteCameras(ids: Set<CameraSlotId>) = edit { calculator.deleteCameras(ids) }

    /** Persists the current list after a calculator change (a no-op after a failed read). */
    fun persistCalculatorContext() = saveNow()

    private fun edit(change: () -> Unit) {
        if (persistence.isReadFailed) return
        change()
        saveNow()
    }

    private fun saveNow() {
        val list = calculator.exportCameraList()
        writer.submit { runCatching { persistence.save(list) } }
    }
}
