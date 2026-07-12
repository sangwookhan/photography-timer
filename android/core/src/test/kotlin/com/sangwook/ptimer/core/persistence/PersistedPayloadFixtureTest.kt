// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.core.persistence

import com.sangwook.ptimer.core.reciprocity.FilmIdentityKind
import com.sangwook.ptimer.core.reciprocity.ReciprocityAuthority
import com.sangwook.ptimer.core.reciprocity.ReciprocityRuleKind
import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * Regression gate for PTIMER-215. The `FROZEN_*` strings are byte-exact
 * captures of the CURRENT on-disk format for the three persisted schemas,
 * taken before any schema-evolution-hardening change. The hardened codecs
 * must decode them to identical domain values. Do not regenerate — a frozen
 * fixture that tracks the codec cannot gate the codec.
 */
class PersistedPayloadFixtureTest {
    @Test
    fun frozenCustomFilmPayloadDecodesToExpectedDomainValues() {
        val snapshot = requireNotNull(CustomFilmLibraryCodec.decode(FROZEN_CUSTOM_FILM))
        assertEquals(1, snapshot.schemaVersion)
        assertEquals(listOf("cf-1", "cf-2"), snapshot.films.map { it.id })
        assertEquals(listOf("Alpha", "Beta"), snapshot.films.map { it.canonicalStockName })
        assertEquals(listOf(100, 400), snapshot.films.map { it.iso })

        val alpha = snapshot.films.first()
        assertEquals(FilmIdentityKind.custom, alpha.kind)
        val profile = alpha.profiles.first()
        assertEquals(ReciprocityAuthority.userDefined, profile.source.authority)
        assertEquals(1, profile.rules.size)
        assertEquals(ReciprocityRuleKind.formula, profile.rules.first().kind)
    }

    @Test
    fun frozenTimerStatePayloadDecodesToExpectedDomainValues() {
        val snapshot = requireNotNull(TimerSnapshotCodec.decode(FROZEN_TIMER_STATE))
        assertEquals(1, snapshot.schemaVersion)
        assertEquals(1, snapshot.timers.size)
        val timer = snapshot.timers.first()
        assertEquals("11111111-1111-1111-1111-111111111111", timer.id.toString())
        assertEquals(SnapshotStatus.running, timer.status)
        assertEquals(120.0, timer.duration, 0.0)
    }

    @Test
    fun frozenWorkspacePayloadDecodesToExpectedDomainValues() {
        val snapshot = requireNotNull(WorkspaceSnapshotCodec.decode(FROZEN_WORKSPACE))
        assertEquals(1, snapshot.schemaVersion)
        assertEquals(1, snapshot.timers.size)
        val entry = snapshot.timers.first()
        assertEquals("Camera 1 · Alpha", entry.identity.title)
        assertEquals("Alpha", entry.identity.filmName)
        assertEquals(1, entry.order)
        assertEquals(SnapshotStatus.running, entry.snapshot.status)
    }

    private companion object {
        const val FROZEN_CUSTOM_FILM =
            """{"films":[{"id":"cf-1","kind":"custom","canonicalStockName":"Alpha","manufacturer":null,"brandLabel":null,"aliases":[],"iso":100,"productionStatus":"unknown","profiles":[{"id":"cf-1-profile","name":"Profile for Alpha","source":{"kind":"userDefined","authority":"userDefined","confidence":"unknown","publisher":"","title":null,"citation":null,"sourceVersion":null},"rules":[{"kind":"formula","threshold":null,"formula":{"formula":{"formulaFamily":"modifiedSchwarzschild","coefficientSeconds":1.0,"referenceMeteredTimeSeconds":1.0,"exponent":1.3,"offsetSeconds":0.0,"noCorrectionThroughSeconds":1.0,"sourceRangeThroughSeconds":null},"additionalAdjustments":[],"notes":[]},"limitedGuidance":null,"tableInterpolation":null}],"notes":[],"userMetadata":{"displayNameOverride":null,"tags":[],"notes":[],"customSourceType":null,"customManufacturer":null,"referenceURL":null,"referenceTableFilmID":null},"sourceEvidence":[],"modelBasis":null,"selectorLabel":null,"sourcePageUrl":null,"downloadUrl":null,"sourceNote":null}],"userMetadata":{"displayNameOverride":null,"tags":[],"notes":[],"customSourceType":null,"customManufacturer":null,"referenceURL":null,"referenceTableFilmID":null}},{"id":"cf-2","kind":"custom","canonicalStockName":"Beta","manufacturer":null,"brandLabel":null,"aliases":[],"iso":400,"productionStatus":"unknown","profiles":[{"id":"cf-2-profile","name":"Profile for Beta","source":{"kind":"userDefined","authority":"userDefined","confidence":"unknown","publisher":"","title":null,"citation":null,"sourceVersion":null},"rules":[{"kind":"formula","threshold":null,"formula":{"formula":{"formulaFamily":"modifiedSchwarzschild","coefficientSeconds":1.0,"referenceMeteredTimeSeconds":1.0,"exponent":1.3,"offsetSeconds":0.0,"noCorrectionThroughSeconds":1.0,"sourceRangeThroughSeconds":null},"additionalAdjustments":[],"notes":[]},"limitedGuidance":null,"tableInterpolation":null}],"notes":[],"userMetadata":{"displayNameOverride":null,"tags":[],"notes":[],"customSourceType":null,"customManufacturer":null,"referenceURL":null,"referenceTableFilmID":null},"sourceEvidence":[],"modelBasis":null,"selectorLabel":null,"sourcePageUrl":null,"downloadUrl":null,"sourceNote":null}],"userMetadata":{"displayNameOverride":null,"tags":[],"notes":[],"customSourceType":null,"customManufacturer":null,"referenceURL":null,"referenceTableFilmID":null}}],"schemaVersion":1}"""

        const val FROZEN_TIMER_STATE =
            """{"timers":[{"id":"11111111-1111-1111-1111-111111111111","status":"running","duration":120.0,"startDate":"2026-06-20T00:00:00Z","expectedCompletionAt":"2026-06-20T00:02:00Z","pausedRemainingDuration":null,"pausedAt":null,"completedAt":null}],"schemaVersion":1}"""

        const val FROZEN_WORKSPACE =
            """{"timers":[{"snapshot":{"id":"11111111-1111-1111-1111-111111111111","status":"running","duration":120.0,"startDate":"2026-06-20T00:00:00Z","expectedCompletionAt":"2026-06-20T00:02:00Z","pausedRemainingDuration":null,"pausedAt":null,"completedAt":null},"identity":{"title":"Camera 1 · Alpha","subtitle":"","baseLine":"","slotLabel":"C1","ndStops":null,"baseShutterSeconds":null,"adjustedShutterSeconds":null,"basisIncludesAdjusted":false,"filmName":"Alpha"},"order":1}],"schemaVersion":1}"""
    }
}
