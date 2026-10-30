// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0
package com.sangwook.ptimer.app.ui.shooting

import androidx.compose.foundation.layout.width
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.swipe
import androidx.compose.ui.test.performTouchInput
import androidx.compose.ui.text.TextLayoutResult
import androidx.compose.ui.unit.dp
import com.sangwook.ptimer.app.vm.CalculatorController
import com.sangwook.ptimer.app.vm.RequiredNDGuidanceState
import com.sangwook.ptimer.ui.component.LocalWheelRenderProbe
import com.sangwook.ptimer.ui.component.SnapWheel
import com.sangwook.ptimer.ui.component.WheelRenderProbe
import com.sangwook.ptimer.ui.theme.PTimerTheme
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import kotlin.math.abs

class BaseWheelSettlementTest {
    @get:Rule val compose = createComposeRule()

    @Test fun finalCommitNeverPrecedesTheLastRenderedWheelMovement() {
        val controller = CalculatorController(emptyList())
        controller.setShutterIndex(28)
        controller.setTargetShutter(1024.0)
        val positions = mutableMapOf<Int, Float>()
        var touched = false
        var settlements = 0
        var movedAfterSettlement = false
        var changedRowAfterSettlement = false
        var finalRow = -1
        var movementCount = 0
        val probe = object : WheelRenderProbe {
            override fun onRow(wheel: String, index: Int, isCenter: Boolean, hasRail: Boolean, layout: TextLayoutResult) {}
            override fun onLabel(wheel: String, hasSourceCue: Boolean, layout: TextLayoutResult) {}
            override fun onRowPosition(wheel: String, index: Int, centerY: Float) {
                val previous = positions.put(index, centerY)
                if (touched && previous != null && abs(previous - centerY) > 0.5f) {
                    movementCount++
                    if (settlements > 0) movedAfterSettlement = true
                }
            }
        }
        compose.setContent {
            val state by controller.state.collectAsState()
            PTimerTheme {
                CompositionLocalProvider(LocalWheelRenderProbe provides probe) {
                    SnapWheel(state.shutterLabels, state.shutterIndex,
                        onSelectedIndexChange = { row ->
                            if (touched && settlements > 0 && row != finalRow) changedRowAfterSettlement = true
                            controller.setShutterIndex(row)
                        },
                        modifier = Modifier.width(180.dp).testTag("base"),
                        visibleCount = 3, itemHeight = 34.dp,
                        accessibilityLabel = "Base Shutter", onActiveChange = {},
                        onTouchBegan = {
                            touched = true; settlements = 0
                            movedAfterSettlement = false; changedRowAfterSettlement = false
                            controller.beginBaseInteraction()
                        },
                        onSettledSelection = { row ->
                            if (touched) {
                                settlements++; finalRow = row
                                controller.finishBaseInteraction(row)
                            }
                        },
                    )
                }
            }
        }
        compose.mainClock.autoAdvance = false
        compose.onNodeWithTag("base").performTouchInput {
            swipe(Offset(center.x, height - 8f), Offset(center.x, -height * 2f), durationMillis = 160)
        }
        repeat(180) { compose.mainClock.advanceTimeByFrame() }
        compose.runOnIdle {
            assertTrue("The test must actually move the rendered wheel", movementCount > 3)
            assertEquals("One final commit for the gesture", 1, settlements)
            assertFalse("Rendered rows moved after final commit", movedAfterSettlement)
            assertFalse("A later centered value arrived after final commit", changedRowAfterSettlement)
            assertEquals(finalRow, controller.state.value.shutterIndex)
            assertEquals(RequiredNDGuidanceState.Phase.Crossfading, controller.state.value.requiredND.phase)
        }
    }
}
