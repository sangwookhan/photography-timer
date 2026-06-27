// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.app.ui.timer

import org.junit.Assert.assertEquals
import org.junit.Test
import java.time.Instant

/**
 * The History relative-time labels are a pure function of the presentation
 * `now`. These lock that contract so the UI-local presentation clock can
 * advance the visible copy ("just now" -> "1 min ago" -> "1 hr ago") simply by
 * feeding a later `now`, without the timer coordinator running.
 */
class RelativeTimeFormatterTest {
    private val end = Instant.ofEpochSecond(1_000)

    @Test
    fun longLabelAdvancesAsNowMovesForward() {
        assertEquals("just now", relativeTimeLong(end, end.plusSeconds(15)))
        assertEquals("just now", relativeTimeLong(end, end.plusSeconds(59)))
        assertEquals("1 min ago", relativeTimeLong(end, end.plusSeconds(60)))
        assertEquals("2 min ago", relativeTimeLong(end, end.plusSeconds(150)))
        assertEquals("1 hr ago", relativeTimeLong(end, end.plusSeconds(3_600)))
        assertEquals("1 day ago", relativeTimeLong(end, end.plusSeconds(86_400)))
        assertEquals("2 days ago", relativeTimeLong(end, end.plusSeconds(172_800)))
    }

    @Test
    fun compactLabelAdvancesAsNowMovesForward() {
        assertEquals("just now", relativeTime(end, end.plusSeconds(3)))
        assertEquals("30s ago", relativeTime(end, end.plusSeconds(30)))
        assertEquals("2m ago", relativeTime(end, end.plusSeconds(150)))
        assertEquals("1h ago", relativeTime(end, end.plusSeconds(3_600)))
        assertEquals("1d ago", relativeTime(end, end.plusSeconds(86_400)))
    }
}
