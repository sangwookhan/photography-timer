package com.sangwook.ptimer.core.reciprocity

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class ReciprocitySecondaryGuidanceFormatterTest {

    private fun colorFilter(name: String, note: String? = null) = ReciprocityAdjustment(
        kind = ReciprocityAdjustmentKind.colorFilter,
        colorFilter = ColorFilterRecommendation(filterName = name, note = note),
    )

    private fun development(instruction: String, note: String? = null) = ReciprocityAdjustment(
        kind = ReciprocityAdjustmentKind.development,
        development = DevelopmentAdjustment(instruction = instruction, note = note),
    )

    private fun warning(severity: ReciprocityWarningSeverity, message: String) = ReciprocityAdjustment(
        kind = ReciprocityAdjustmentKind.warning,
        warning = ReciprocityWarning(severity = severity, message = message),
    )

    private fun note(text: String) = ReciprocityAdjustment(
        kind = ReciprocityAdjustmentKind.note,
        note = ReciprocityNote(text = text),
    )

    private fun exposureStop(stop: Double) = ReciprocityAdjustment(
        kind = ReciprocityAdjustmentKind.exposure,
        exposure = ExposureAdjustment(
            kind = ExposureAdjustmentKind.stopDelta,
            stopDelta = StopDeltaAdjustment(stopDelta = stop),
        ),
    )

    @Test
    fun colorFilterMapsToColorCorrectionNeutral() {
        val out = ReciprocitySecondaryGuidanceFormatter.format(listOf(colorFilter("CC30M", "Magenta")))
        assertEquals(1, out.size)
        val g = out.first()
        assertEquals(SecondaryGuidanceKind.colorCorrection, g.kind)
        assertEquals("Color correction", g.title)
        assertEquals("CC30M", g.valueText)
        assertEquals("Magenta", g.detailText)
        assertEquals(SecondaryGuidanceSeverity.neutral, g.severity)
    }

    @Test
    fun colorFilterWithoutNoteHasEmptyDetail() {
        val out = ReciprocitySecondaryGuidanceFormatter.format(listOf(colorFilter("CC30M")))
        assertEquals("", out.first().detailText)
    }

    @Test
    fun developmentMapsToDevelopmentAdjustmentNeutral() {
        val out = ReciprocitySecondaryGuidanceFormatter.format(listOf(development("Dev -10%", "Reduce agitation")))
        val g = out.first()
        assertEquals(SecondaryGuidanceKind.developmentAdjustment, g.kind)
        assertEquals("Development adjustment", g.title)
        assertEquals("Dev -10%", g.valueText)
        assertEquals("Reduce agitation", g.detailText)
        assertEquals(SecondaryGuidanceSeverity.neutral, g.severity)
    }

    @Test
    fun warningCautionMapsToCaution() {
        val out = ReciprocitySecondaryGuidanceFormatter.format(
            listOf(warning(ReciprocityWarningSeverity.caution, "Watch highlights")),
        )
        val g = out.first()
        assertEquals(SecondaryGuidanceKind.warning, g.kind)
        assertNull(g.valueText)
        assertEquals("Watch highlights", g.detailText)
        assertEquals(SecondaryGuidanceSeverity.caution, g.severity)
    }

    @Test
    fun warningNotRecommendedMapsToStop() {
        val out = ReciprocitySecondaryGuidanceFormatter.format(
            listOf(warning(ReciprocityWarningSeverity.notRecommended, "Beyond data")),
        )
        assertEquals(SecondaryGuidanceSeverity.stop, out.first().severity)
    }

    @Test
    fun blankNoteIsOmittedButRealNoteKept() {
        val out = ReciprocitySecondaryGuidanceFormatter.format(listOf(note("   "), note("Real note")))
        assertEquals(1, out.size)
        assertEquals(SecondaryGuidanceKind.note, out.first().kind)
        assertEquals("Real note", out.first().detailText)
        assertEquals(SecondaryGuidanceSeverity.caution, out.first().severity)
    }

    @Test
    fun exposureAdjustmentIsOmitted() {
        val out = ReciprocitySecondaryGuidanceFormatter.format(listOf(exposureStop(1.0)))
        assertTrue(out.isEmpty())
    }
}
