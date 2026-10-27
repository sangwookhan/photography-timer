// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.ui.component

import org.junit.Assert.*
import org.junit.Test

class ManualWheelSessionTest {
    @Test fun touchReleaseAndStableRowDoNotCommitBeforeFlingAndSnapFinish() {
        val session = ManualWheelSession()
        assertTrue(session.sample(2, false, true).isEmpty())
        assertEquals(ManualWheelEvent.Started, session.begin())
        assertEquals(listOf(ManualWheelEvent.Preview(2)), session.sample(2, true, true))
        assertTrue(session.sample(2, false, false).isEmpty())
        assertEquals(listOf(ManualWheelEvent.Preview(3)), session.sample(3, true, false))
        assertEquals(listOf(ManualWheelEvent.Preview(2), ManualWheelEvent.Committed(2)), session.sample(2, false, true))
        assertTrue(session.sample(2, false, true).isEmpty())
    }
    @Test fun accessibleAdjustmentWaitsForRequestedCenteredValueAndDisposalCancels() {
        val session = ManualWheelSession()
        session.begin(accessibleIndex = 4)
        assertTrue(session.sample(3, false, true).isEmpty())
        assertEquals(listOf(ManualWheelEvent.Preview(4), ManualWheelEvent.Committed(4)), session.sample(4, false, true))
        session.begin(); session.cancel()
        assertTrue(session.sample(4, false, true).isEmpty())
    }
}
