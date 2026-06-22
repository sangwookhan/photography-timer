package com.sangwook.ptimer.ui

import androidx.compose.material3.MaterialTheme
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollToNode
import com.sangwook.ptimer.calculator.CalculatorUiState
import com.sangwook.ptimer.calculator.StartActionState
import com.sangwook.ptimer.core.timer.ExposureTimerSource
import com.sangwook.ptimer.core.timer.TimerStatus
import com.sangwook.ptimer.timer.TimerItemUi
import com.sangwook.ptimer.timer.TimerWorkspaceUiState
import com.sangwook.ptimer.vm.FilmRowUi
import com.sangwook.ptimer.vm.ShootingIntent
import com.sangwook.ptimer.vm.SlotChipUi
import com.sangwook.ptimer.vm.SlotsUiState
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

/**
 * Host-side (Robolectric) Compose smoke: renders the STATELESS [ShootingScreen]
 * with fake state — no MainActivity, ViewModel, DataStore, alarms, or
 * permissions — and asserts the stable smoke selectors and source identity are
 * present. It runs under `./gradlew testDebugUnitTest` (no emulator).
 *
 * Scope: this proves the screen composes and the selectors/text render. It does
 * NOT exercise real interaction/behavior (the fake `onEvent` is a no-op) and is
 * NOT a substitute for the instrumented `connectedDebugAndroidTest` smoke, which
 * still needs a stable-API emulator. SDK is pinned to 33 because that is the
 * highest `android-all` runtime cached locally (the SDK repo is unreachable).
 */
@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [33])
class ShootingScreenHostSmokeTest {

    @get:Rule
    val composeRule = createComposeRule()

    private fun adjustedAction() = StartActionState(
        enabled = true,
        durationSeconds = 34.1,
        disabledReason = null,
        source = ExposureTimerSource.DIGITAL_RESULT,
        filmContext = "Digital",
        subtitle = "Adjusted Shutter · 34.1s",
        selectedModelLabel = null,
    )

    private fun calcState() = CalculatorUiState(
        baseShutterLabel = "1/30",
        ndStops = 10,
        filmName = null,
        authorityLabel = null,
        adjustedShutterLabel = "34.1s",
        correctedExposureLabel = null,
        reciprocityBadge = null,
        adjustedAction = adjustedAction(),
        correctedAction = null,
        targetAction = null,
        availableModels = emptyList(),
    )

    private fun slotsState() = SlotsUiState(
        slots = listOf(
            SlotChipUi("camera1", "Camera 1", isActive = true),
            SlotChipUi("camera2", "Camera 2", isActive = false),
        ),
        activeLabel = "Camera 1",
    )

    private fun timersWithActive() = TimerWorkspaceUiState(
        active = listOf(
            TimerItemUi(
                id = "timer-0",
                title = "Camera 1 · Fomapan 100 Classic",
                subtitle = "Adjusted Shutter · 34.1s",
                metadata = "Base 1/30 · ND 10 · Adjusted 34.1s",
                source = ExposureTimerSource.FILM_ADJUSTED_SHUTTER,
                status = TimerStatus.RUNNING,
                statusLabel = "Running",
                remainingSeconds = 34.0,
                remainingLabel = "00:34",
                endsAtLabel = "Ends 12:00:34",
            ),
        ),
        completed = emptyList(),
    )

    private fun renderReady(timers: TimerWorkspaceUiState = TimerWorkspaceUiState()) {
        composeRule.setContent {
            MaterialTheme {
                ShootingScreen(
                    slots = slotsState(),
                    calc = calcState(),
                    films = emptyList<FilmRowUi>(),
                    timers = timers,
                    details = null,
                    onEvent = { _: ShootingIntent -> },
                    ready = true,
                )
            }
        }
    }

    @Test
    fun hostSmoke_rendersReadyShootingScreen() {
        renderReady()
        composeRule.onNodeWithTag(TestTags.SHOOTING_SCREEN).assertExists()
    }

    @Test
    fun hostSmoke_rendersAdjustedStartAction() {
        renderReady()
        // The Result row is below the fold on Robolectric's small default screen;
        // LazyColumn only composes visible items, so scroll it into view first.
        composeRule.onNodeWithTag(TestTags.SHOOTING_SCREEN)
            .performScrollToNode(hasTestTag(TestTags.START_ADJUSTED_BUTTON))
        composeRule.onNodeWithTag(TestTags.START_ADJUSTED_BUTTON).assertExists()
    }

    @Test
    fun hostSmoke_opensTimersWorkspaceShowingActiveRowWithSourceIdentity() {
        // The main scroll now shows only a timer summary; the full active row
        // lives in the Timers workspace, opened via the summary's Open button.
        renderReady(timersWithActive())
        composeRule.onNodeWithTag(TestTags.SHOOTING_SCREEN)
            .performScrollToNode(hasTestTag(TestTags.OPEN_TIMERS_BUTTON))
        composeRule.onNodeWithTag(TestTags.OPEN_TIMERS_BUTTON).performClick()
        composeRule.onNodeWithTag(TestTags.TIMERS_WORKSPACE).assertExists()
        composeRule.onNodeWithTag(TestTags.ACTIVE_TIMER_ROW).assertExists()
        composeRule.onNodeWithText("Camera 1 · Fomapan 100 Classic").assertExists() // title identity
        composeRule.onNodeWithText("Adjusted Shutter · 34.1s").assertExists()        // source line
    }
}
