// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0
package com.sangwook.ptimer.app.ui.shooting

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.width
import androidx.compose.runtime.getValue
import androidx.compose.runtime.setValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.toPixelMap
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.captureToImage
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.getUnclippedBoundsInRoot
import androidx.compose.ui.unit.dp
import com.sangwook.ptimer.app.vm.FilterStatusLeading
import com.sangwook.ptimer.app.vm.FilterStatusRegionContent
import com.sangwook.ptimer.app.vm.RequiredNDGuidanceState
import com.sangwook.ptimer.core.exposure.NDNotationMode
import com.sangwook.ptimer.core.exposure.RequiredNDResult
import com.sangwook.ptimer.ui.theme.PTimerTheme
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test

class RequiredNDCrossfadeTest {
    private val motionScale = object : androidx.compose.ui.MotionDurationScale {
        override var scaleFactor by androidx.compose.runtime.mutableFloatStateOf(1f)
    }
    @get:Rule val compose = createComposeRule(effectContext = motionScale)

    @Test fun bothLayersHaveIntermediateBrightnessAndRetouchRestoresGuidance() {
        val initial = RequiredNDGuidanceState(RequiredNDResult.Value(10.0, false), RequiredNDGuidanceState.Phase.Tracking, 1)
        val state = mutableStateOf(initial)
        compose.setContent {
            PTimerTheme(darkTheme = false, dynamicColor = false) {
                Box(Modifier.width(360.dp).background(Color.White)) {
                    FilterStatusRegion(
                        content = FilterStatusRegionContent(FilterStatusLeading.None, "Total 2 stops", isHeld = true),
                        wheelCount = 2, notationMode = NDNotationMode.STOPS,
                        totalValueText = "2", modifier = Modifier.testTag("status"),
                        requiredND = state.value, actualTotal = "Total 2 stops",
                        onRequiredNDComplete = { token ->
                            if (state.value.generation == token) state.value = state.value.copy(
                                result = null, phase = RequiredNDGuidanceState.Phase.Ordinary)
                        },
                    )
                }
            }
        }
        compose.mainClock.autoAdvance = false
        val node = compose.onNodeWithTag("status", useUnmergedTree = true)
        val bounds = node.getUnclippedBoundsInRoot()
        val start = node.captureToImage()
        compose.runOnIdle { state.value = initial.copy(phase = RequiredNDGuidanceState.Phase.Crossfading) }
        compose.mainClock.advanceTimeByFrame()
        compose.mainClock.advanceTimeBy(250)
        val middle = node.captureToImage()
        compose.mainClock.advanceTimeBy(350)
        val end = node.captureToImage()
        assertEquals(bounds, node.getUnclippedBoundsInRoot())
        val a = start.toPixelMap(); val m = middle.toPixelMap(); val b = end.toPixelMap()
        var outgoing = 0; var incoming = 0
        for (y in 0 until a.height) for (x in 0 until a.width) {
            val sa = a[x, y]; val sm = m[x, y]; val sb = b[x, y]
            if (sa.blue - sa.red > 0.25f && sb.red > 0.95f &&
                sm.blue - sm.red > 0.03f && sm.blue - sm.red < sa.blue - sa.red - 0.03f) outgoing++
            if (sa.red > 0.95f && sa.green > 0.95f && sa.blue > 0.95f && sb.red < 0.6f &&
                sm.red > sb.red + 0.03f && sm.red < 0.95f) incoming++
        }
        assertTrue("Outgoing blue has intermediate brightness: $outgoing pixels", outgoing > 5)
        assertTrue("Incoming Total has intermediate brightness simultaneously: $incoming pixels", incoming > 5)
        for (offset in listOf(100L, 350L)) {
            compose.runOnIdle { state.value = initial.copy(generation = state.value.generation + 1) }
            compose.mainClock.advanceTimeByFrame()
            compose.runOnIdle { state.value = state.value.copy(phase = RequiredNDGuidanceState.Phase.Crossfading) }
            compose.mainClock.advanceTimeByFrame()
            compose.mainClock.advanceTimeBy(offset)
            compose.runOnIdle { state.value = initial.copy(generation = state.value.generation + 1) }
            compose.mainClock.advanceTimeByFrame()
            assertImagesEqual(start, node.captureToImage())
            compose.mainClock.advanceTimeBy(600)
            assertEquals(RequiredNDGuidanceState.Phase.Tracking, state.value.phase)
        }
        compose.runOnIdle { state.value = RequiredNDGuidanceState(generation = state.value.generation + 1) }
        compose.mainClock.advanceTimeByFrame()
        assertImagesEqual(end, node.captureToImage())
    }

    @Test fun returningTotalGetsItsOrdinaryLifetimeAfterLongGuidance() {
        val state = mutableStateOf(RequiredNDGuidanceState(RequiredNDResult.Value(10.0, false),
            RequiredNDGuidanceState.Phase.Tracking, 1))
        compose.setContent {
            PTimerTheme(darkTheme = false, dynamicColor = false) {
                FilterStatusRegion(
                    content = FilterStatusRegionContent(FilterStatusLeading.None, "Total 2 stops", isHeld = false),
                    wheelCount = 2, notationMode = NDNotationMode.STOPS, requiredND = state.value,
                    onRequiredNDComplete = { state.value = state.value.copy(result = null,
                        phase = RequiredNDGuidanceState.Phase.Ordinary) },
                )
            }
        }
        // The ordinary controller's 1.5-second lifetime may expire while
        // guidance is held. Restoration must start a fresh ordinary lifetime.
        compose.mainClock.advanceTimeBy(1700)
        compose.waitForIdle()
        compose.runOnIdle { state.value = state.value.copy(phase = RequiredNDGuidanceState.Phase.Crossfading) }
        compose.waitForIdle()
        compose.onNodeWithText("Total 2 stops").assertIsDisplayed()
        compose.mainClock.advanceTimeBy(1700)
        compose.waitForIdle()
        compose.waitForIdle()
        compose.onNodeWithText("Total 2 stops").assertDoesNotExist()
    }

    @Test fun zeroMotionScaleRestoresOrdinaryOnTheNextFrames() {
        val state = mutableStateOf(RequiredNDGuidanceState())
        compose.setContent {
            PTimerTheme(darkTheme = false, dynamicColor = false) {
                Box(Modifier.width(360.dp).background(Color.White)) {
                    FilterStatusRegion(
                        content = FilterStatusRegionContent(FilterStatusLeading.None, "Total 2 stops", isHeld = true),
                        wheelCount = 2, notationMode = NDNotationMode.STOPS,
                        modifier = Modifier.testTag("status"), requiredND = state.value,
                        onRequiredNDComplete = { state.value = state.value.copy(result = null,
                            phase = RequiredNDGuidanceState.Phase.Ordinary) },
                    )
                }
            }
        }
        val node = compose.onNodeWithTag("status", useUnmergedTree = true)
        val ordinary = node.captureToImage()
        compose.mainClock.autoAdvance = false
        compose.runOnIdle { state.value = RequiredNDGuidanceState(RequiredNDResult.Value(10.0, false), RequiredNDGuidanceState.Phase.Tracking, 1) }
        compose.mainClock.advanceTimeByFrame()
        compose.runOnIdle {
            motionScale.scaleFactor = 0f
            state.value = state.value.copy(phase = RequiredNDGuidanceState.Phase.Crossfading)
        }
        repeat(3) { compose.mainClock.advanceTimeByFrame() }
        compose.runOnIdle { assertEquals(RequiredNDGuidanceState.Phase.Ordinary, state.value.phase) }
        compose.onNodeWithText("Total 2 stops").assertIsDisplayed()
        assertImagesEqual(ordinary, node.captureToImage())
    }

    private fun assertImagesEqual(expected: ImageBitmap, actual: ImageBitmap) {
        val a = expected.toPixelMap(); val b = actual.toPixelMap()
        assertEquals(a.width, b.width); assertEquals(a.height, b.height)
        for (y in 0 until a.height) for (x in 0 until a.width) assertEquals(a[x, y], b[x, y])
    }
}
