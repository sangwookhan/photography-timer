// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.core.timer

import com.sangwook.ptimer.core.exposure.FilterItemKind
import com.sangwook.ptimer.core.exposure.FilterSummaryEntry
import com.sangwook.ptimer.core.exposure.FilterValueUnit
import com.sangwook.ptimer.core.persistence.PersistentWorkspaceSnapshot
import com.sangwook.ptimer.core.persistence.WorkspaceSnapshotCodec
import kotlinx.serialization.json.Json
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.Instant
import java.util.UUID

/**
 * FILTER-PERSIST-003: a timer's captured filter summary is stored with
 * the on-disk enum tokens, round-trips through the workspace codec, and
 * decodes entry by entry so one damaged entry never erases the rest — or
 * the timer.
 */
class TimerIdentityFilterSummaryTest {

    private val t0: Instant = Instant.parse("2026-06-20T00:00:00Z")

    private val entry = FilterSummaryEntry(
        sourceKind = FilterSummaryEntry.SourceKind.filterSet,
        filterSetId = "s",
        filterSetName = "Lee",
        itemId = "i",
        itemName = "GND",
        itemKind = FilterItemKind.gnd,
        originalValue = 0.9,
        originalUnit = FilterValueUnit.opticalDensity,
        canonicalStops = 3.0,
        calculationMode = FilterSummaryEntry.CalculationMode.gndRecordOnly,
        contributedStops = 0.0,
    )

    private fun workspace(identity: TimerIdentity) = PersistentWorkspaceSnapshot.from(
        listOf(
            WorkspaceTimer(
                state = TimerState.Running(
                    UUID.fromString("00000000-0000-0000-0000-000000000001"),
                    100.0,
                    t0,
                    t0.plusSecondsDouble(100.0),
                ),
                identity = identity,
            ),
        ),
    )

    @Test fun summaryStoresRawTokensAndRoundTrips() {
        val snapshot = workspace(
            TimerIdentity(
                title = "Camera 1 · HP5 Plus",
                filterSummary = listOf(entry),
            ),
        )
        val json = WorkspaceSnapshotCodec.encode(snapshot)
        assertTrue(json, json.contains(""""sourceKind":"filterSet""""))
        assertTrue(json, json.contains(""""calculationMode":"gndRecordOnly""""))

        val decoded = WorkspaceSnapshotCodec.decode(json)
        assertEquals(snapshot, decoded)
        val identity = decoded!!.timers.single().identity
        assertEquals(listOf(entry), identity.filterSummary)
    }

    @Test fun oneMalformedEntryIsDroppedAndTheTimerSurvives() {
        val valid = WorkspaceSnapshotCodec.encode(
            workspace(TimerIdentity(title = "Good", filterSummary = listOf(entry))),
        )
        val withBad = valid.replaceFirst(
            """"filterSummary":[""",
            """"filterSummary":[""" +
                """{"sourceKind":"standard","canonicalStops":"broken","contributedStops":1.0},""" +
                """{"sourceKind":"unknownKind","contributedStops":1.0},""",
        )
        val decoded = WorkspaceSnapshotCodec.decode(withBad)!!
        val identity = decoded.timers.single().identity
        assertEquals("Good", identity.title)
        assertEquals(
            "The undecodable and the unknown-source entries are dropped.",
            listOf(entry),
            identity.filterSummary,
        )
    }

    /** An unknown OPTIONAL token degrades that field to null instead of
     *  discarding the entry (iOS parity). */
    @Test fun anUnknownOptionalTokenDegradesToNull() {
        val valid = WorkspaceSnapshotCodec.encode(
            workspace(TimerIdentity(title = "Good", filterSummary = listOf(entry))),
        )
        val withUnknownTokens = valid.replaceFirst(
            """"filterSummary":[""",
            """"filterSummary":[""" +
                """{"sourceKind":"filterSet","itemKind":"laser","originalUnit":"parsec",""" +
                """"contributedStops":4.0},""",
        )
        val summary = WorkspaceSnapshotCodec.decode(withUnknownTokens)!!
            .timers.single().identity.filterSummary!!
        assertEquals(2, summary.size)
        assertEquals(FilterSummaryEntry.SourceKind.filterSet, summary[0].sourceKind)
        assertNull(summary[0].itemKind)
        assertNull(summary[0].originalUnit)
        assertEquals(4.0, summary[0].contributedStops, 0.0)
    }

    @Test fun aLegacyIdentityWithoutTheFilterKeysDecodes() {
        val identity = Json { ignoreUnknownKeys = true }
            .decodeFromString<TimerIdentity>("""{"title":"t","slotLabel":"C1"}""")
        assertEquals("t", identity.title)
        assertNull(identity.filterSummary)
    }

    /** A stored value that is not an array degrades to an empty summary
     *  rather than dropping the timer. */
    @Test fun aNonArraySummaryDecodesAsEmpty() {
        val identity = Json { ignoreUnknownKeys = true }
            .decodeFromString<TimerIdentity>("""{"title":"t","filterSummary":{"bad":true}}""")
        assertEquals(emptyList<FilterSummaryEntry>(), identity.filterSummary)
    }
}
