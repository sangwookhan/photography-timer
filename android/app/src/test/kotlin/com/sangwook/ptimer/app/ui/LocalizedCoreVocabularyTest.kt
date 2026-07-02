// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.app.ui

import com.sangwook.ptimer.R
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/**
 * The display-boundary resolver maps canonical core English to resources and
 * passes everything else through (returns null), so localization can never
 * change semantic state — only what the user reads (PTIMER-183).
 */
class LocalizedCoreVocabularyTest {

    @Test
    fun mapsCanonicalReciprocityVocabulary() {
        assertEquals(R.string.recip_value_formula_derived, coreVocabularyRes("Formula-derived"))
        assertEquals(R.string.recip_value_no_quantified_prediction, coreVocabularyRes("No quantified prediction"))
        assertEquals(R.string.recip_value_manufacturer_formula, coreVocabularyRes("Manufacturer formula"))
        assertEquals(R.string.recip_value_guarded_formula, coreVocabularyRes("Guarded formula"))
        assertEquals(R.string.recip_value_manufacturer_limited_guidance, coreVocabularyRes("Manufacturer limited guidance"))
        assertEquals(R.string.recip_value_limited_guidance, coreVocabularyRes("Limited guidance"))
        assertEquals(R.string.recip_value_user_defined, coreVocabularyRes("User-defined"))
        assertEquals(R.string.recip_details_title, coreVocabularyRes("Reciprocity Details"))
        assertEquals(R.string.shooting_no_corrected_value, coreVocabularyRes("No corrected value"))
        assertEquals(
            R.string.recip_detail_no_official_beyond_range,
            coreVocabularyRes("No official quantified prediction is available beyond this range."),
        )
    }

    @Test
    fun mapsSourceTypeAndFitQualityLabels() {
        assertEquals(R.string.recip_value_personal_test, coreVocabularyRes("Personal test"))
        assertEquals(R.string.recip_value_community_reference, coreVocabularyRes("Community reference"))
        assertEquals(R.string.recip_value_unknown_source, coreVocabularyRes("Unknown source"))
        assertEquals(R.string.cf_fit_good, coreVocabularyRes("Good fit"))
        assertEquals(R.string.cf_fit_borderline, coreVocabularyRes("Borderline fit"))
        assertEquals(R.string.cf_fit_poor, coreVocabularyRes("Poor fit"))
    }

    @Test
    fun mapsGuidanceProse() {
        assertEquals(
            R.string.cf_fit_shorten_warning,
            coreVocabularyRes(
                "The fitted formula would shorten exposure with the current table boundaries. " +
                    "Raise no correction or add a lower-range anchor. The table remains your reliable calculation.",
            ),
        )
        assertEquals(
            R.string.recip_guidance_longer_exposures,
            coreVocabularyRes("Longer exposures: test under your conditions."),
        )
        assertEquals(
            R.string.recip_note_official_sheet_no_data,
            coreVocabularyRes("Official sheet found, but no reciprocity correction data was found."),
        )
    }

    @Test
    fun unknownVocabularyPassesThrough() {
        assertNull(coreVocabularyRes("Ektar 100"))
        assertNull(coreVocabularyRes("Current input is beyond the published source table."))
    }

    @Test
    fun timerSubtitleSourceExtractsCanonicalTokensOnly() {
        assertEquals("Adjusted Exposure", timerSubtitleSource("Adjusted Exposure 34.133s"))
        assertEquals("Corrected Exposure", timerSubtitleSource("Corrected Exposure 02:39:14.557"))
        assertEquals("Target Exposure", timerSubtitleSource("Target Exposure 1m"))
        assertEquals("Calculated", timerSubtitleSource("Calculated 30s"))
        assertNull(timerSubtitleSource("Adjusted Exposure"))
        assertNull(timerSubtitleSource("Legacy free-form subtitle"))
    }

    @Test
    fun timerSourceLabelsFollowIosParity() {
        // The corrected-exposure timer row reads "Reciprocity" (iOS PTIMER-183).
        assertEquals(R.string.shooting_reciprocity, timerSourceRes("Corrected Exposure"))
        assertEquals(R.string.timer_source_adjusted, timerSourceRes("Adjusted Exposure"))
        assertEquals(R.string.timer_source_target, timerSourceRes("Target Exposure"))
        assertEquals(R.string.timer_source_calculated, timerSourceRes("Calculated"))
        assertNull(timerSourceRes("Reciprocity"))
    }
}
