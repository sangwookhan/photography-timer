package com.sangwook.ptimer.core.reciprocity

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class ReciprocitySourceReferencePresenterTest {

    // Trimming formatter so the expected labels read "4s", "1s" (not "4.0s").
    private val fmt: (Double) -> String = { seconds ->
        val whole = seconds.toLong()
        if (seconds == whole.toDouble()) "${whole}s" else "${seconds}s"
    }

    private fun exposureRow(metered: Double, stopDelta: Double, colorFilter: String) =
        ReciprocitySourceEvidenceRow(
            meteredExposure = MeteredExposureSelector(
                kind = MeteredExposureSelectorKind.exactSeconds,
                exactSeconds = metered,
            ),
            adjustments = listOf(
                ReciprocityAdjustment(
                    kind = ReciprocityAdjustmentKind.exposure,
                    exposure = ExposureAdjustment(
                        kind = ExposureAdjustmentKind.stopDelta,
                        stopDelta = StopDeltaAdjustment(stopDelta),
                    ),
                ),
                ReciprocityAdjustment(
                    kind = ReciprocityAdjustmentKind.colorFilter,
                    colorFilter = ColorFilterRecommendation(colorFilter),
                ),
            ),
        )

    private fun velviaLikeProfile() = ReciprocityProfile(
        id = "velvia",
        name = "Velvia 50",
        source = ReciprocitySourceProvenance(
            kind = ReciprocitySourceKind.manufacturerPublished,
            authority = ReciprocityAuthority.official,
            publisher = "Fujifilm",
        ),
        rules = listOf(
            ReciprocityRule(
                kind = ReciprocityRuleKind.formula,
                formula = FormulaReciprocityRule(
                    formula = ReciprocityFormula(
                        formulaFamily = FormulaFamily.modifiedSchwarzschild,
                        exponent = 1.1821,
                        noCorrectionThroughSeconds = 1.0,
                    ),
                ),
            ),
        ),
        sourceEvidence = listOf(
            exposureRow(4.0, 0.33, "5M"),
            exposureRow(8.0, 0.5, "7.5M"),
            exposureRow(16.0, 0.67, "10M"),
            exposureRow(32.0, 1.0, "12.5M"),
            ReciprocitySourceEvidenceRow(
                meteredExposure = MeteredExposureSelector(
                    kind = MeteredExposureSelectorKind.exactSeconds,
                    exactSeconds = 64.0,
                ),
                adjustments = listOf(
                    ReciprocityAdjustment(
                        kind = ReciprocityAdjustmentKind.warning,
                        warning = ReciprocityWarning(
                            ReciprocityWarningSeverity.notRecommended,
                            "64 sec is not recommended.",
                        ),
                    ),
                ),
            ),
        ),
    )

    @Test
    fun colorCorrectionValuesStayTiedToMeteredExposureAsSubLines() {
        val result = ReciprocitySourceReferencePresenter.rows(velviaLikeProfile(), fmt)

        assertEquals(
            listOf(
                ReciprocityReferenceRow("<= 1s", "No correction range", null),
                ReciprocityReferenceRow("4s", "+0.33 stops", "5M"),
                ReciprocityReferenceRow("8s", "+0.5 stops", "7.5M"),
                ReciprocityReferenceRow("16s", "+0.67 stops", "10M"),
                ReciprocityReferenceRow("32s", "+1 stop", "12.5M"),
            ),
            result.sourceReference,
        )
        assertEquals(
            listOf(ReciprocityReferenceRow("64s", "Not recommended", null)),
            result.guidanceBoundary,
        )
    }

    @Test
    fun stopDeltaPluralizationMatchesIos() {
        // 1 stop is singular; everything else is "stops".
        val rows = ReciprocitySourceReferencePresenter.rows(velviaLikeProfile(), fmt).sourceReference
        assertEquals("+1 stop", rows.first { it.meteredText == "32s" }.valueText)
        assertEquals("+0.5 stops", rows.first { it.meteredText == "8s" }.valueText)
    }

    @Test
    fun profileWithoutSourceEvidenceProducesNoTable() {
        val profile = velviaLikeProfile().copy(sourceEvidence = emptyList())
        val result = ReciprocitySourceReferencePresenter.rows(profile, fmt)
        assertTrue(result.sourceReference.isEmpty())
        assertTrue(result.guidanceBoundary.isEmpty())
    }
}
