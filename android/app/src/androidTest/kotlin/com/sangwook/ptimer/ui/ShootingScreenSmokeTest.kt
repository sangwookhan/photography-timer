package com.sangwook.ptimer.ui

import android.Manifest
import android.os.Build
import androidx.compose.ui.test.ExperimentalTestApi
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onFirst
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollToNode
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.rule.GrantPermissionRule
import com.sangwook.ptimer.MainActivity
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Compose UI smoke test: the app launches and the minimum shooting flow runs
 * without crashing. This is NOT a pixel / visual-parity test — it asserts that
 * key nodes exist and that starting a timer produces an active row with source
 * identity and the expected actions. Robust to pre-existing persisted state
 * (it counts row deltas and raises ND so the started timer stays running).
 */
@OptIn(ExperimentalTestApi::class)
@RunWith(AndroidJUnit4::class)
class ShootingScreenSmokeTest {

    @get:Rule
    val composeRule = createAndroidComposeRule<MainActivity>()

    // Avoid the API 33+ POST_NOTIFICATIONS dialog interfering with the flow.
    @get:Rule
    val permissionRule: GrantPermissionRule =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            GrantPermissionRule.grant(Manifest.permission.POST_NOTIFICATIONS)
        } else {
            GrantPermissionRule.grant()
        }

    private fun activeRowCount(): Int =
        composeRule.onAllNodesWithTag(TestTags.ACTIVE_TIMER_ROW).fetchSemanticsNodes().size

    private fun textCount(text: String): Int =
        composeRule.onAllNodesWithText(text, substring = true).fetchSemanticsNodes().size

    /** Wait until restore settles (the Restoring… overlay is gone) and content is up. */
    private fun awaitReady() {
        composeRule.waitUntil(timeoutMillis = 10_000) {
            composeRule.onAllNodesWithTag(TestTags.RESTORING_OVERLAY).fetchSemanticsNodes().isEmpty() &&
                composeRule.onAllNodesWithTag(TestTags.START_ADJUSTED_BUTTON).fetchSemanticsNodes().isNotEmpty()
        }
    }

    /** Raise ND so the adjusted result is multi-second and a started timer stays running. */
    private fun raiseNd(times: Int = 8) {
        composeRule.onNodeWithTag(TestTags.SHOOTING_SCREEN)
            .performScrollToNode(hasTestTag(TestTags.ND_PLUS_BUTTON))
        repeat(times) { composeRule.onNodeWithTag(TestTags.ND_PLUS_BUTTON).performClick() }
    }

    private fun startAdjustedTimer(): Int {
        raiseNd()
        val before = activeRowCount()
        composeRule.onNodeWithTag(TestTags.SHOOTING_SCREEN)
            .performScrollToNode(hasTestTag(TestTags.START_ADJUSTED_BUTTON))
        composeRule.onNodeWithTag(TestTags.START_ADJUSTED_BUTTON).performClick()
        composeRule.waitUntil(timeoutMillis = 5_000) { activeRowCount() == before + 1 }
        return before + 1
    }

    @Test
    fun launch_showsReadyShootingScreen() {
        awaitReady()
        composeRule.onNodeWithTag(TestTags.SHOOTING_SCREEN).assertExists()
        composeRule.onNodeWithTag(TestTags.START_ADJUSTED_BUTTON).assertExists()
    }

    @Test
    fun startAdjustedTimer_createsActiveTimerRowWithSourceIdentity() {
        awaitReady()
        startAdjustedTimer()
        // An active row exists, and its source identity is shown.
        composeRule.onNodeWithTag(TestTags.SHOOTING_SCREEN)
            .performScrollToNode(hasTestTag(TestTags.ACTIVE_TIMER_ROW))
        composeRule.onAllNodesWithTag(TestTags.ACTIVE_TIMER_ROW).onFirst().assertIsDisplayed()
        assertTrue("camera/title identity should be visible", textCount("Camera") > 0)
        assertTrue("source line should be visible", textCount("Adjusted Shutter") > 0)
    }

    @Test
    fun activeTimer_exposesPauseResumeAndRemoveActions() {
        awaitReady()
        startAdjustedTimer()
        composeRule.onNodeWithTag(TestTags.SHOOTING_SCREEN)
            .performScrollToNode(hasTestTag(TestTags.ACTIVE_TIMER_ROW))
        assertTrue("running row exposes Pause", textCount("Pause") > 0)
        assertTrue("running row exposes Remove", textCount("Remove") > 0)
        composeRule.onAllNodesWithText("Pause").onFirst().performClick()
        composeRule.waitUntil(timeoutMillis = 5_000) { textCount("Resume") > 0 } // pause → resume
    }
}
