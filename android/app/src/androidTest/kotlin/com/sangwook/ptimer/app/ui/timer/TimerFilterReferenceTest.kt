// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.app.ui.timer

import android.content.res.Configuration
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.getUnclippedBoundsInRoot
import androidx.compose.ui.test.assertCountEquals
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.unit.height
import com.sangwook.ptimer.app.vm.ShootingUiState
import com.sangwook.ptimer.app.vm.TimerCardState
import com.sangwook.ptimer.core.exposure.FilterSummaryEntry
import com.sangwook.ptimer.core.exposure.NDNotationMode
import com.sangwook.ptimer.core.exposure.FilterValueUnit
import com.sangwook.ptimer.core.timer.TimerIdentity
import com.sangwook.ptimer.core.timer.TimerStatus
import com.sangwook.ptimer.ui.theme.PTimerTheme
import org.junit.Assert.assertTrue
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

    private fun show(
        identity: TimerIdentity,
        locale: Locale? = null,
        notation: NDNotationMode = NDNotationMode.DEFAULT,
    ) {
        composeTestRule.setContent {
            val list = @androidx.compose.runtime.Composable {
                PTimerTheme {
                    FullTimerList(
                        state = state(identity),
                        onEvent = {},
                        onCollapse = {},
                        focusId = null,
                        ndNotationMode = notation,
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

    /**
     * FILTER-PERSIST-003: a mixed Filter Stack's primary value is the
     * captured canonical total. It is a plain decimal in stops — the
     * ladder's reserved third-stop fractions do not describe it, and
     * neither does the global OD / ND notation. 29.6 stops is `29.6`,
     * not `29 2/3` and not `OD 8.9`.
     */
    @Test
    fun aMixedStackTotalIsPlainDecimalStopsInEveryNotation() {
        val mixed = TimerIdentity(
            title = "Camera 1",
            ndStops = 29.6,
            baseShutterSeconds = 0.033,
            basisIncludesAdjusted = false,
            filterSummary = listOf(capturedEntry),
            filterReferenceText = "NiSi kit: Big Stopper ND1000",
        )
        // One composition, notation switched underneath it: setContent can
        // only be called once per test, and switching is closer to what the
        // user does anyway.
        val notation = mutableStateOf(NDNotationMode.STOPS)
        composeTestRule.setContent {
            val base = InstrumentationRegistry.getInstrumentation().targetContext
            val config = Configuration(base.resources.configuration).apply { setLocale(Locale.KOREA) }
            CompositionLocalProvider(
                LocalContext provides base.createConfigurationContext(config),
                LocalConfiguration provides config,
            ) {
                PTimerTheme {
                    FullTimerList(
                        state = state(mixed),
                        onEvent = {},
                        onCollapse = {},
                        focusId = null,
                        ndNotationMode = notation.value,
                    )
                }
            }
        }
        for (mode in NDNotationMode.entries) {
            composeTestRule.runOnUiThread { notation.value = mode }
            composeTestRule.waitForIdle()
            composeTestRule.onAllNodesWithText("29.6 스톱", substring = true).assertCountEquals(1)
            composeTestRule.onAllNodesWithText("29 2/3", substring = true).assertCountEquals(0)
            composeTestRule.onAllNodesWithText("OD ", substring = true).assertCountEquals(0)
            composeTestRule.onAllNodesWithText("ND5", substring = true).assertCountEquals(0)
        }
    }

    /** A Standard-only timer keeps following the global notation. */
    @Test
    fun aStandardOnlyTotalStillFollowsTheNotation() {
        show(
            TimerIdentity(
                title = "Camera 1",
                ndStops = 9.0,
                baseShutterSeconds = 0.033,
                basisIncludesAdjusted = false,
            ),
            locale = Locale.KOREA,
            notation = NDNotationMode.OPTICAL_DENSITY,
        )
        composeTestRule.onAllNodesWithText("OD 2.7", substring = true).assertCountEquals(1)
    }

    /**
     * FILTER-PERSIST-003 asks the list to present the reference string.
     * A realistic one — two Filter Set items plus a Standard segment —
     * does not fit one line on a phone, and truncating it to a fragment
     * stops it naming the filters the timer used. It wraps to a second
     * line, as iOS does.
     *
     * Both cards are in one list so the two heights are measured under
     * identical width and typography.
     */
    @Test
    fun aLongReferenceLineWrapsInsteadOfBecomingAFragment() {
        val short = "NiSi kit: Big Stopper"
        val long = "Standard 16.6 스톱 · NiSi kit: Big Stopper ND1000 + NiSi GND OD 0.9 (전체 값 적용)"
        fun card(reference: String) = TimerCardState(
            id = UUID.randomUUID(),
            order = 1,
            identity = TimerIdentity(
                title = "Camera 1",
                filterSummary = listOf(capturedEntry),
                filterReferenceText = reference,
            ),
            status = TimerStatus.running,
            remainingSeconds = 120.0,
            endDate = Instant.EPOCH.plusSeconds(120),
            remainingAtCancelSeconds = null,
            durationSeconds = 120.0,
        )
        composeTestRule.setContent {
            PTimerTheme {
                FullTimerList(
                    state = ShootingUiState(
                        active = listOf(card(short), card(long)),
                        now = Instant.EPOCH,
                    ),
                    onEvent = {},
                    onCollapse = {},
                    focusId = null,
                )
            }
        }
        val oneLine = composeTestRule.onNodeWithText(short).getUnclippedBoundsInRoot().height
        val wrapped = composeTestRule.onNodeWithText(long).getUnclippedBoundsInRoot().height
        assertTrue(
            "The long reference must occupy two lines, not one: one line is " +
                "$oneLine, the long one is $wrapped",
            wrapped.value > oneLine.value * 1.5f,
        )
        // And it is still the complete string, not a fragment.
        composeTestRule.onNodeWithText(long).assertIsDisplayed()
    }
}
