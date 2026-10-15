// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.app.vm

/** Renames the camera that is active now (the header rename of the main screen). */
internal fun CalculatorController.renameActiveSlot(name: String) {
    renameCamera(state.value.slots.first { it.isActive }.id, name)
}
