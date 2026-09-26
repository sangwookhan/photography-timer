// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.core.timer

import com.sangwook.ptimer.core.exposure.NDNotationMode
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/** The timer basis renders inputs only, in the active notation mode (PTIMER-187). */
class TimerBasisPresenterTest {
    private val fmt: (Double) -> String = { s -> if (s < 1.0) "1/30" else "${s.toInt()}s" }

    @Test fun digitalAdjustedHasNoAdjSegment() {
        assertEquals(
            "Base 1/30 · 9 stops",
            TimerBasisPresenter.basisText(9.0, 0.033, 8.0, includesAdjusted = false, NDNotationMode.STOPS, fmt),
        )
    }

    @Test fun correctedTargetIncludesAdjAndFollowsNotation() {
        assertEquals(
            "Base 1/30 · ND512 · Adj 8s",
            TimerBasisPresenter.basisText(9.0, 0.033, 8.0, includesAdjusted = true, NDNotationMode.FILTER_FACTOR, fmt),
        )
        assertEquals(
            "Base 1/30 · OD 2.7 · Adj 8s",
            TimerBasisPresenter.basisText(9.0, 0.033, 8.0, includesAdjusted = true, NDNotationMode.OPTICAL_DENSITY, fmt),
        )
    }

    /**
     * FILTER-A11Y-003: the STOPS unit is a word, so a caller with
     * resources renders the ND fragment itself. The default stays
     * locale-independent for callers that have none.
     */
    @Test fun theCallersNotationRendererIsTheOneUsed() {
        val korean: (Double, NDNotationMode) -> String = { stops, mode ->
            when (mode) {
                NDNotationMode.STOPS -> "${stops.toInt()} 스톱"
                NDNotationMode.OPTICAL_DENSITY -> "OD ${"%.1f".format(stops * 0.3)}"
                NDNotationMode.FILTER_FACTOR -> "ND512"
            }
        }
        assertEquals(
            "Base 1/30 · 9 스톱",
            TimerBasisPresenter.basisText(
                9.0, 0.033, 8.0, includesAdjusted = false, NDNotationMode.STOPS, fmt,
                formatNotation = korean,
            ),
        )
        // The non-word notations read the same either way.
        for (mode in listOf(NDNotationMode.OPTICAL_DENSITY, NDNotationMode.FILTER_FACTOR)) {
            assertEquals(
                "$mode reads the same in both languages.",
                TimerBasisPresenter.basisText(9.0, 0.033, 8.0, includesAdjusted = false, mode, fmt),
                TimerBasisPresenter.basisText(
                    9.0, 0.033, 8.0, includesAdjusted = false, mode, fmt,
                    formatNotation = korean,
                ),
            )
        }
        // English keeps the default, and singular/plural with it.
        assertEquals(
            "Base 1/30 · 1 stop",
            TimerBasisPresenter.basisText(1.0, 0.033, 8.0, includesAdjusted = false, NDNotationMode.STOPS, fmt),
        )
    }

    @Test fun absentStructuredFieldsReturnNull() {
        assertNull(TimerBasisPresenter.basisText(null, 0.033, 8.0, includesAdjusted = true, NDNotationMode.STOPS, fmt))
        assertNull(TimerBasisPresenter.basisText(9.0, null, 8.0, includesAdjusted = true, NDNotationMode.STOPS, fmt))
    }
}
