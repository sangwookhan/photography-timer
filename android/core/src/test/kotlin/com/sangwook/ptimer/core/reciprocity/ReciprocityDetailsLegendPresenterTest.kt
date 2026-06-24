package com.sangwook.ptimer.core.reciprocity

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ReciprocityDetailsLegendPresenterTest {

    private fun profileWith(adjustments: List<ReciprocityAdjustment>) = ReciprocityProfile(
        id = "p",
        name = "P",
        source = ReciprocitySourceProvenance(
            kind = ReciprocitySourceKind.manufacturerPublished,
            authority = ReciprocityAuthority.official,
            publisher = "Test",
        ),
        rules = listOf(
            ReciprocityRule(
                kind = ReciprocityRuleKind.threshold,
                threshold = ThresholdReciprocityRule(
                    noCorrectionRange = ReciprocityTimeRange(minimumSeconds = 0.0, maximumSeconds = 1.0),
                    adjustments = adjustments,
                ),
            ),
        ),
    )

    private fun colorFilter(name: String) = ReciprocityAdjustment(
        kind = ReciprocityAdjustmentKind.colorFilter,
        colorFilter = ColorFilterRecommendation(filterName = name),
    )

    private fun development(instruction: String) = ReciprocityAdjustment(
        kind = ReciprocityAdjustmentKind.development,
        development = DevelopmentAdjustment(instruction = instruction),
    )

    private fun warning(severity: ReciprocityWarningSeverity) = ReciprocityAdjustment(
        kind = ReciprocityAdjustmentKind.warning,
        warning = ReciprocityWarning(severity = severity, message = "msg"),
    )

    @Test
    fun ccFilterProducesKodakColorCorrectionLine() {
        val lines = ReciprocityDetailsLegendPresenter.legendLines(profileWith(listOf(colorFilter("CC30M"))))
        assertTrue(lines.contains("Color correction: CC30M = color-compensating magenta filtration."))
    }

    @Test
    fun developmentProducesDevelopmentLine() {
        val lines = ReciprocityDetailsLegendPresenter.legendLines(profileWith(listOf(development("Dev -10%"))))
        assertTrue(lines.contains("Development adjustment: Dev -10% means adjust development time by -10%."))
    }

    @Test
    fun notRecommendedWarningProducesStopLine() {
        val lines = ReciprocityDetailsLegendPresenter.legendLines(
            profileWith(listOf(warning(ReciprocityWarningSeverity.notRecommended))),
        )
        assertTrue(lines.contains("Warning: Not recommended marks a manufacturer stop-signal."))
    }

    @Test
    fun cautionWarningDoesNotProduceStopLine() {
        val lines = ReciprocityDetailsLegendPresenter.legendLines(
            profileWith(listOf(warning(ReciprocityWarningSeverity.caution))),
        )
        assertFalse(lines.any { it.startsWith("Warning:") })
    }

    @Test
    fun nonKodakSingleChannelFilterUsesBareLetterLine() {
        val lines = ReciprocityDetailsLegendPresenter.legendLines(profileWith(listOf(colorFilter("30Y"))))
        assertTrue(lines.contains("Color correction: Y = yellow filtration."))
    }

    @Test
    fun noAdjustmentsYieldEmpty() {
        assertEquals(emptyList<String>(), ReciprocityDetailsLegendPresenter.legendLines(profileWith(emptyList())))
    }
}
