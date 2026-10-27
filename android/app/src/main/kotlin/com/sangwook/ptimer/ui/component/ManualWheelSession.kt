// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.ui.component

sealed interface ManualWheelEvent {
    data object Started : ManualWheelEvent
    data class Preview(val index: Int) : ManualWheelEvent
    data class Committed(val index: Int) : ManualWheelEvent
    data object Cancelled : ManualWheelEvent
}

/** A single ordered event stream: preview precedes commit even when two
 * snapshotFlow collectors would otherwise observe their states in any order.
 * Programmatic parking and initial composition never start a manual session. */
internal class ManualWheelSession {
    var isOpen = false; private set
    private var expectedAccessibleIndex: Int? = null
    private var lastIndex: Int? = null
    fun begin(accessibleIndex: Int? = null): ManualWheelEvent {
        isOpen = true
        expectedAccessibleIndex = accessibleIndex
        lastIndex = null
        return ManualWheelEvent.Started
    }
    fun sample(index: Int, active: Boolean, centered: Boolean): List<ManualWheelEvent> {
        if (!isOpen || (expectedAccessibleIndex != null && expectedAccessibleIndex != index)) return emptyList()
        val events = mutableListOf<ManualWheelEvent>()
        if (lastIndex != index) { lastIndex = index; events += ManualWheelEvent.Preview(index) }
        if (!active && centered && (expectedAccessibleIndex == null || expectedAccessibleIndex == index)) {
            isOpen = false
            events += ManualWheelEvent.Committed(index)
        }
        return events
    }
    fun cancel(): ManualWheelEvent { isOpen = false; return ManualWheelEvent.Cancelled }
}
