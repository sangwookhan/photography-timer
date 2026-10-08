// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.app.ui

import org.junit.Assert.assertEquals
import org.junit.Test

/** The approved label size rule: 14 x system scale, held between 13 and 14.5 sp. */
class MainLabelSizeTest {
    @Test fun smallSystemTextShrinksButStopsAtTheFloor() {
        assertEquals(13f, mainLabelSizeSp(0.85f), 0.001f)
        assertEquals(13.3f, mainLabelSizeSp(0.95f), 0.001f)
    }

    @Test fun defaultScaleIsFourteen() {
        assertEquals(14f, mainLabelSizeSp(1.0f), 0.001f)
    }

    @Test fun largerSystemTextGrowsOnlyToTheCap() {
        assertEquals(14.5f, mainLabelSizeSp(1.05f), 0.001f)
        assertEquals(14.5f, mainLabelSizeSp(1.08f), 0.001f)
        assertEquals(14.5f, mainLabelSizeSp(1.3f), 0.001f)
        assertEquals(14.5f, mainLabelSizeSp(2.0f), 0.001f)
    }
}
