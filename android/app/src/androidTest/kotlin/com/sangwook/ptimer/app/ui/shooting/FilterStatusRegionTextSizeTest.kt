// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.app.ui.shooting

import android.content.res.Configuration
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.width
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.test.getUnclippedBoundsInRoot
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.onRoot
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.height
import androidx.test.platform.app.InstrumentationRegistry
import com.sangwook.ptimer.app.vm.FilterSourceSummaryItem
import com.sangwook.ptimer.app.vm.FilterStatusLeading
import com.sangwook.ptimer.app.vm.FilterStatusRegionContent
import com.sangwook.ptimer.core.exposure.FilterSetColor
import com.sangwook.ptimer.core.exposure.FilterSource
import com.sangwook.ptimer.core.exposure.NDNotationMode
import com.sangwook.ptimer.ui.theme.PTimerTheme
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.junit.runners.Parameterized
import java.util.Locale

/**
 * PTIMER-221 FILTER-STACK-008: the region "shall reserve only the height
 * required for one visual row plus its normal vertical padding" and the
 * total "shall remain visible and untruncated".
 *
 * Measured by laying the total out with a [TextMeasurer] in the same
 * composition — same style, same density — and holding the region's own
 * height against it. Neither the node bounds nor the semantics tree can
 * see a shortfall: the region gives its Row a fixed height, so the Text
 * is MEASURED at that height and simply draws its glyphs past it, and
 * the card's clip then cuts them. Checked at the shooting screen's fixed
 * 1.0x, in both languages.
 */
@RunWith(Parameterized::class)
class FilterStatusRegionTextSizeTest(private val case: Case) {
    @get:Rule
    val composeTestRule = createComposeRule()

    data class Case(val locale: Locale) {
        override fun toString() = locale.toLanguageTag()
    }

    companion object {
        @JvmStatic
        @Parameterized.Parameters(name = "{0}")
        fun cases(): List<Array<Any>> = listOf(Locale.US, Locale.KOREA).map { arrayOf<Any>(Case(it)) }
    }

    private val total = "합계 16.6 스톱"

    /** What one line of the total needs, in the composition under test. */
    private var rowNeeds = 0.dp

    @Test
    fun theRegionReservesTheRowItsOwnTextNeeds() {
        val base = InstrumentationRegistry.getInstrumentation().targetContext
        val configuration = Configuration(base.resources.configuration).apply {
            setLocale(case.locale)
            fontScale = 1f
        }
        val localized = base.createConfigurationContext(configuration)
        composeTestRule.setContent {
            val platformDensity = LocalDensity.current
            CompositionLocalProvider(
                LocalContext provides localized,
                LocalConfiguration provides configuration,
                LocalDensity provides Density(platformDensity.density, 1f),
            ) {
                PTimerTheme {
                    val measurer = rememberTextMeasurer()
                    val density = LocalDensity.current
                    rowNeeds = with(density) {
                        measurer.measure(
                            total,
                            MaterialTheme.typography.labelSmall,
                            maxLines = 1,
                            softWrap = false,
                        ).size.height.toDp()
                    }
                    Box(Modifier.width(220.dp)) {
                        FilterStatusRegion(
                            content = FilterStatusRegionContent(
                                leading = FilterStatusLeading.IdleSummary(
                                    listOf(
                                        FilterSourceSummaryItem(
                                            source = FilterSource.Standard,
                                            name = "Lee holder",
                                            count = 3,
                                            color = FilterSetColor.blue,
                                        ),
                                    ),
                                ),
                                total = total,
                                isHeld = true,
                                isSecondaryEmphasis = true,
                            ),
                            wheelCount = 4,
                            notationMode = NDNotationMode.STOPS,
                        )
                    }
                }
            }
        }
        composeTestRule.waitForIdle()

        // The harness Box wraps the region, so the root IS the region.
        val region = composeTestRule.onRoot().getUnclippedBoundsInRoot().height
        composeTestRule.onNodeWithText(total).assertExists()
        assertTrue(
            "$case: one line of `$total` needs $rowNeeds and the region reserved $region, so " +
                "${rowNeeds - region} of the line is drawn outside it and the card that wraps " +
                "the region cuts it off. FILTER-STACK-008 reserves the height one visual row " +
                "requires and keeps the total visible and untruncated.",
            rowNeeds <= region + 1.dp,
        )
    }
}
