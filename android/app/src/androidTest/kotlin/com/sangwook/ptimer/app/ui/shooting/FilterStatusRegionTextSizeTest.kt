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
import com.sangwook.ptimer.app.ui.MaxCappedFontScale
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
 * PTIMER-221 FILTER-STACK-008 at every supported text size.
 *
 * The region "shall reserve only the height required for one visual row
 * plus its normal vertical padding" and the total "shall remain visible
 * and untruncated". The height was a fixed 20dp, which is what that row
 * needs at the DEFAULT text size and no more: the card clips its
 * content, so at a raised size the total lost the bottom of its glyphs
 * rather than the region growing. Found in a rendered capture of the
 * shooting card at 360dp in Korean at 2.0x, where `합계 16.6 스톱` was
 * sliced horizontally through the middle of its syllables.
 *
 * Measured by laying the total out with a [TextMeasurer] in the same
 * composition — same style, same density, same font scale — and holding
 * the region's own height against it. Neither the node bounds nor the
 * semantics tree can see this: the region gives its Row a fixed height,
 * so the Text is MEASURED at that height and simply draws its glyphs
 * past it. The node is the reserved box, not the line inside it, and the
 * truncation only becomes visible once the card's clip is around it. The
 * region reserving less than its row needs is the defect, wherever the
 * clip lands.
 */
@RunWith(Parameterized::class)
class FilterStatusRegionTextSizeTest(private val case: Case) {
    @get:Rule
    val composeTestRule = createComposeRule()

    data class Case(val locale: Locale, val fontScale: Float) {
        override fun toString() = "${locale.toLanguageTag()} ${fontScale}x"
    }

    companion object {
        @JvmStatic
        @Parameterized.Parameters(name = "{0}")
        fun cases(): List<Array<Any>> = listOf(Locale.US, Locale.KOREA).flatMap { locale ->
            // Default, the app's own cap, and the largest system step.
            // The shipping app caps at 1.3x and Spec PR #68 permits
            // that, so 2.0x here is stress coverage: the region asked to
            // reserve its row at a scale the app does not render, which
            // is where the fixed height gave way.
            listOf(1.0f, MaxCappedFontScale, 2.0f).map { scale ->
                arrayOf<Any>(Case(locale, scale))
            }
        }
    }

    private val total = "합계 16.6 스톱"

    /** What one line of the total needs, in the composition under test. */
    private var rowNeeds = 0.dp

    @Test
    fun theRegionReservesTheRowItsOwnTextNeeds() {
        val base = InstrumentationRegistry.getInstrumentation().targetContext
        val configuration = Configuration(base.resources.configuration).apply {
            setLocale(case.locale)
            fontScale = case.fontScale
        }
        val localized = base.createConfigurationContext(configuration)
        composeTestRule.setContent {
            val platformDensity = LocalDensity.current
            CompositionLocalProvider(
                LocalContext provides localized,
                LocalConfiguration provides configuration,
                LocalDensity provides Density(platformDensity.density, case.fontScale),
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
