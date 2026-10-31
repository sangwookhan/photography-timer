// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0
package com.sangwook.ptimer.app.ui.shooting

import androidx.compose.ui.unit.dp
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class PhoneShootingPresentationTest {
    @Test fun pixelBusyPageHasRoomForThePhonePresentation() {
        assertTrue(usesPhoneShootingPresentation(411.dp, 694.dp, 411, false))
    }

    @Test fun wideShortAndFoldArrangementsKeepTheirPresentation() {
        assertFalse(usesPhoneShootingPresentation(704.dp, 780.dp, 704, false))
        assertFalse(usesPhoneShootingPresentation(411.dp, 694.dp, 411, true))
        assertFalse(usesPhoneShootingPresentation(411.dp, 600.dp, 411, false))
        assertFalse(usesPhoneShootingPresentation(411.dp, 800.dp, 800, false))
        assertFalse(usesPhoneShootingPresentation(320.dp, 800.dp, 320, false))
    }
}
