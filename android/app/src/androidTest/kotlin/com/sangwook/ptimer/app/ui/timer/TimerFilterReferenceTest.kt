// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.app.ui.timer

import android.content.res.Configuration
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertCountEquals
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithText
import com.sangwook.ptimer.app.vm.ShootingUiState
import com.sangwook.ptimer.app.vm.TimerCardState
import com.sangwook.ptimer.core.exposure.FilterSummaryEntry
import com.sangwook.ptimer.core.exposure.FilterValueUnit
import com.sangwook.ptimer.core.timer.TimerIdentity
import com.sangwook.ptimer.core.timer.TimerStatus
import com.sangwook.ptimer.ui.theme.PTimerTheme
import org.junit.Rule
import org.junit.Test
import androidx.test.platform.app.InstrumentationRegistry
import java.time.Instant
import java.util.Locale
import java.util.UUID

/**
 * FILTER-PERSIST-003 on the rendered Timer list: the reference line is
 * the string the timer captured when it started. Nothing the list can
 * see — the live inventory, the current app language — may recompose
 * over it.
 */
class TimerFilterReferenceTest {
    @get:Rule
    val composeTestRule = createComposeRule()

    private val capturedEntry = FilterSummaryEntry(
        sourceKind = FilterSummaryEntry.SourceKind.filterSet,
        filterSetId = "set",
        filterSetName = "Lee holder",
        itemId = "item",
        itemName = "Big Stopper",
        originalValue = 1000.0,
        originalUnit = FilterValueUnit.filterFactor,
        canonicalStops = 10.0,
        calculationMode = FilterSummaryEntry.CalculationMode.fixed,
        contributedStops = 10.0,
    )

    private fun state(identity: TimerIdentity) = ShootingUiState(
        active = listOf(
            TimerCardState(
                id = UUID.randomUUID(),
                order = 1,
                identity = identity,
                status = TimerStatus.running,
                remainingSeconds = 120.0,
                endDate = Instant.EPOCH.plusSeconds(120),
                remainingAtCancelSeconds = null,
                durationSeconds = 120.0,
            ),
        ),
        now = Instant.EPOCH,
    )

    private fun show(identity: TimerIdentity, locale: Locale? = null) {
        composeTestRule.setContent {
            val list = @androidx.compose.runtime.Composable {
                PTimerTheme {
                    FullTimerList(
                        state = state(identity),
                        onEvent = {},
                        onCollapse = {},
                        focusId = null,
                    )
                }
            }
            if (locale == null) {
                list()
            } else {
                val base = InstrumentationRegistry.getInstrumentation().targetContext
                val config = Configuration(base.resources.configuration).apply { setLocale(locale) }
                CompositionLocalProvider(
                    LocalContext provides base.createConfigurationContext(config),
                    LocalConfiguration provides config,
                ) { list() }
            }
        }
    }

    @Test
    fun theCapturedStringIsRenderedVerbatim() {
        // A string that the summary beside it could never produce: if the
        // list recomposed the line, this text would not appear.
        show(
            TimerIdentity(
                title = "Camera 1",
                filterSummary = listOf(capturedEntry),
                filterReferenceText = "Lee holder: Big Stopper ND1000",
            ),
        )
        composeTestRule.onNodeWithText("Lee holder: Big Stopper ND1000").assertIsDisplayed()
    }

    @Test
    fun aRenamedSetDoesNotReachTheCapturedLine() {
        // The captured summary and the captured string disagree, exactly as
        // they would after the set was renamed post-start. The string wins.
        show(
            TimerIdentity(
                title = "Camera 1",
                filterSummary = listOf(capturedEntry.copy(filterSetName = "Renamed kit")),
                filterReferenceText = "Lee holder: Big Stopper ND1000",
            ),
        )
        composeTestRule.onNodeWithText("Lee holder: Big Stopper ND1000").assertIsDisplayed()
        composeTestRule.onNodeWithText("Renamed kit: Big Stopper ND1000").assertDoesNotExist()
    }

    @Test
    fun aLegacyPayloadWithoutTheStringStillGetsALine() {
        show(
            TimerIdentity(
                title = "Camera 1",
                filterSummary = listOf(capturedEntry),
                filterReferenceText = null,
            ),
        )
        composeTestRule.onNodeWithText("Lee holder: Big Stopper ND1000").assertIsDisplayed()
    }

    /**
     * FILTER-A11Y-003 on the rendered card: the basis line's unit noun is
     * a word, so it must be the user's. It used to come from a
     * locale-independent core formatter and read `10 stops` inside an
     * otherwise Korean card.
     */
    @Test
    fun theKoreanBasisLineUsesTheKoreanStopsNoun() {
        show(
            TimerIdentity(
                title = "Camera 1",
                ndStops = 10.0,
                baseShutterSeconds = 5.0,
                basisIncludesAdjusted = false,
            ),
            locale = Locale.KOREA,
        )
        composeTestRule.onAllNodesWithText("스톱", substring = true).assertCountEquals(1)
        composeTestRule.onAllNodesWithText("stops", substring = true).assertCountEquals(0)
        composeTestRule.onAllNodesWithText("stop", substring = true).assertCountEquals(0)
    }
}
