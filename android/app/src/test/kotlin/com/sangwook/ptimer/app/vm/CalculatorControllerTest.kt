// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.app.vm

import com.sangwook.ptimer.core.catalog.LaunchPresetFilmCatalogV2
import com.sangwook.ptimer.core.slots.CameraSlotId
import com.sangwook.ptimer.core.timer.TimerIdentity
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class CalculatorControllerTest {

    private val films = LaunchPresetFilmCatalogV2.films

    private fun controller(onStart: (Double, TimerIdentity) -> Unit = { _, _ -> }) =
        CalculatorController(films = films, onStart = onStart)

    @Test
    fun defaultsToDigitalWithStartableAdjustedShutter() {
        val s = controller().state.value
        assertEquals("No film", s.selectedFilmName)
        assertTrue(s.startEnabled)
        assertNull(s.correctedText)
        assertTrue(s.adjustedText.isNotEmpty())
        assertTrue(s.modelOptions.isEmpty())
    }

    @Test
    fun presetFilmOptionsAreGroupedAndSortedLikeIos() {
        val presetOptions = controller().state.value.filmOptions
            .filter { it.id != null && !it.isCustom }

        val manufacturerOrder = presetOptions
            .map { it.manufacturer.orEmpty() }
            .distinct()
        assertEquals(manufacturerOrder.sortedWith(java.lang.String.CASE_INSENSITIVE_ORDER), manufacturerOrder)

        manufacturerOrder.forEach { manufacturer ->
            val names = presetOptions
                .filter { it.manufacturer.orEmpty() == manufacturer }
                .map { it.name }
            assertEquals(names.sortedWith(java.lang.String.CASE_INSENSITIVE_ORDER), names)
        }
    }

    @Test
    fun startDelegatesDurationAndIdentity() {
        var duration: Double? = null
        var identity: TimerIdentity? = null
        val c = controller { d, id -> duration = d; identity = id }
        c.start()
        assertNotNull(duration)
        assertTrue(duration!! > 0)
        assertNotNull(identity)
        assertTrue(identity!!.title.contains("No film"))
    }

    @Test
    fun selectingFormulaFilmProducesCorrectedExposure() {
        val c = controller()
        c.selectFilm("ilford-pan-f-plus-50")
        c.setNdIndex(6) // 1/30 + 6 stops on the 1/3 ladder → long metered
        val s = c.state.value
        assertEquals("Pan F Plus", s.selectedFilmName)
        assertNotNull(s.correctedText)
        assertTrue(s.startEnabled)
    }

    @Test
    fun filmWithAlternatesExposesModelOptions() {
        val c = controller()
        c.selectFilm("foma-fomapan-100")
        val s = c.state.value
        assertTrue(s.modelOptions.size > 1)
    }

    @Test
    fun ndIndexChangesAdjustedShutter() {
        val c = controller()
        val before = c.state.value.adjustedText
        c.setNdIndex(10)
        assertTrue(c.state.value.adjustedText != before)
    }

    @Test
    fun switchingSlotCapturesAndRestoresPerSlotInputs() {
        val c = controller()
        c.selectFilm("ilford-pan-f-plus-50")
        c.setNdIndex(6)
        val camera1State = c.state.value

        // Camera 2 starts fresh: no film, default ND.
        c.selectSlot(CameraSlotId.camera2)
        val camera2State = c.state.value
        assertEquals("Camera 2", camera2State.activeSlotName)
        assertEquals("No film", camera2State.selectedFilmName)
        assertEquals(0, camera2State.ndIndex)

        // Returning to Camera 1 restores its film + ND.
        c.selectSlot(CameraSlotId.camera1)
        val restored = c.state.value
        assertEquals(camera1State.selectedFilmName, restored.selectedFilmName)
        assertEquals(camera1State.ndIndex, restored.ndIndex)
    }

    @Test
    fun slotStatesCarryEachSlotsOwnContentForThePager() {
        val c = controller()
        c.selectFilm("ilford-pan-f-plus-50")
        c.setNdIndex(6)

        val states = c.state.value.slotStates
        // One read-only state per camera slot, in slot order.
        assertEquals(c.state.value.slots.size, states.size)

        // The active (Camera 1) page reflects the live film + ND, while the
        // other pages show their own untouched defaults — not a clone of the
        // active page (the swipe-clone bug).
        val camera1 = states[0]
        assertEquals("Pan F Plus", camera1.selectedFilmName)
        assertEquals(6, camera1.ndIndex)
        assertEquals("Camera 1", camera1.activeSlotName)

        val camera2 = states[1]
        assertEquals("Camera 2", camera2.activeSlotName)
        assertEquals("No film", camera2.selectedFilmName)
        assertEquals(0, camera2.ndIndex)
    }

    @Test
    fun startFromAdjustedAndCorrectedUseTheirOwnDurations() {
        val starts = mutableListOf<Pair<Double, TimerIdentity>>()
        val c = controller { d, id -> starts += d to id }
        c.selectFilm("ilford-pan-f-plus-50")
        c.setNdIndex(6)
        assertNotNull(c.state.value.correctedText)

        c.startFromAdjusted()
        c.startFromCorrected()
        assertEquals(2, starts.size)
        // Second line is "<source> <final value>" (PTIMER-187).
        assertTrue(starts[0].second.subtitle.startsWith("Adjusted Exposure "))
        assertTrue(starts[1].second.subtitle.startsWith("Corrected Exposure "))
        // The two timers have different durations (correction lengthened it).
        assertTrue(starts[0].first < starts[1].first)
    }

    @Test
    fun outsideGuidanceShowsTheComputedCorrectedValue() {
        // T-MAX table beyond its 100s source range still computes a corrected
        // value (flagged "outside guidance"); the main must show it, not hide it.
        val c = controller()
        c.selectFilm("kodak-tmax-100")
        // Find the table model and a long base shutter that lands out of range.
        c.state.value.modelOptions.firstOrNull { it.label.contains("table", true) }?.let { c.selectProfile(it.id) }
        c.setShutterIndex(c.state.value.shutterLabels.lastIndex) // longest base shutter
        c.setNdIndex(10) // push well beyond the 100s source range
        val s = c.state.value
        // Either quantified or outside-guidance, but a value must be shown.
        assertTrue(s.correctedText != null && s.correctedText != "No corrected value")
    }

    @Test
    fun startFromCorrectedIsNoOpWithoutQuantifiedCorrection() {
        var count = 0
        val c = controller { _, _ -> count++ }
        // Digital workflow (no film) has no corrected value.
        c.startFromCorrected()
        assertEquals(0, count)
    }

    @Test
    fun resetActiveSlotSettingsAndNameClearsFilmInputsAndName() {
        val c = controller()
        c.selectFilm("ilford-pan-f-plus-50")
        c.setNdIndex(6)
        c.renameActiveSlot("Leica")
        c.resetActiveSlotSettingsAndName()
        val s = c.state.value
        assertEquals("No film", s.selectedFilmName)
        assertEquals(0, s.ndIndex)
        assertEquals("Camera 1", s.activeSlotName)
        assertFalse(s.hasFilm)
    }

    @Test
    fun canResetIsFalseAtDefaultsAndTrueAfterChanges() {
        val c = controller()
        assertFalse(c.state.value.canReset)
        c.setNdIndex(6)
        assertTrue(c.state.value.canReset)
    }

    @Test
    fun canResetIsTrueWhenOnlyCustomNameSet() {
        val c = controller()
        c.renameActiveSlot("Leica")
        // Settings are still at defaults, but the custom name is
        // resettable via "Reset settings and name".
        assertTrue(c.state.value.canReset)
    }

    @Test
    fun resetActiveSlotSettingsKeepsCustomName() {
        val c = controller()
        c.selectFilm("ilford-pan-f-plus-50")
        c.setNdIndex(6)
        c.renameActiveSlot("Leica")
        c.resetActiveSlotSettings()
        val s = c.state.value
        // Settings cleared...
        assertEquals("No film", s.selectedFilmName)
        assertEquals(0, s.ndIndex)
        assertFalse(s.hasFilm)
        // ...but the custom camera name survives.
        assertEquals("Leica", s.activeSlotName)
    }

    @Test
    fun targetShutterIsPerSlotAndStartsFromTargetDuration() {
        var duration: Double? = null
        var identity: TimerIdentity? = null
        val c = controller { d, id -> duration = d; identity = id }

        c.setTargetShutter(30.0)
        assertTrue(c.state.value.targetDisplay is com.sangwook.ptimer.core.target.TargetShutterDisplayState.Available)

        // Camera 2 has no target.
        c.selectSlot(CameraSlotId.camera2)
        assertTrue(c.state.value.targetDisplay is com.sangwook.ptimer.core.target.TargetShutterDisplayState.Unavailable)

        // Camera 1 restores its target and starts a timer from it.
        c.selectSlot(CameraSlotId.camera1)
        c.startFromTarget()
        assertEquals(30.0, duration!!, 0.0)
        assertTrue(identity!!.subtitle.startsWith("Target Exposure "))
    }

    @Test
    fun renameActiveSlotFlowsIntoStateAndTimerIdentity() {
        var identity: TimerIdentity? = null
        val c = controller { _, id -> identity = id }
        c.renameActiveSlot("Hasselblad")
        assertEquals("Hasselblad", c.state.value.activeSlotName)
        c.start()
        assertTrue(identity!!.title.startsWith("Hasselblad"))
        assertEquals("C1", identity!!.slotLabel)
    }

    @Test
    fun setFilmsExposesACustomFilmThatComputesCorrectedExposure() {
        val custom = com.sangwook.ptimer.core.customfilm.CustomFilmBuilder.buildFormulaFilm(
            input = com.sangwook.ptimer.core.customfilm.CustomFormulaFilmInput(
                filmLabel = "My Film",
                profileName = "My Film",
                iso = 100,
                coefficientSeconds = 2.0,
                referenceMeteredTimeSeconds = 1.0,
                exponent = 1.3,
                noCorrectionThroughSeconds = 1.0,
            ),
            filmId = "custom-1",
            profileId = "custom-profile-1",
        )!!
        val c = controller()
        c.setFilms(films + custom)
        c.selectFilm("custom-1")
        c.setNdIndex(6)
        val s = c.state.value
        assertEquals("My Film", s.selectedFilmName)
        assertNotNull(s.correctedText)
    }

    @Test
    fun exportedSessionRestoresPerSlotStateAndNames() {
        val origin = controller()
        origin.renameActiveSlot("Rollei")
        origin.selectFilm("ilford-pan-f-plus-50")
        origin.setNdIndex(6)
        origin.setTargetShutter(45.0)
        origin.selectSlot(CameraSlotId.camera2)
        origin.setNdIndex(2)
        val exported = origin.exportSession()

        // Rebuild from the exported session: active slot + per-slot state survive.
        val restored = CalculatorController(films = films, initialSession = exported)
        val camera2 = restored.state.value
        assertEquals("Camera 2", camera2.activeSlotName)
        assertEquals(2, camera2.ndIndex)

        restored.selectSlot(CameraSlotId.camera1)
        val camera1 = restored.state.value
        assertEquals("Rollei", camera1.activeSlotName)
        assertEquals("Pan F Plus", camera1.selectedFilmName)
        assertEquals(6, camera1.ndIndex)
        assertTrue(camera1.targetDisplay is com.sangwook.ptimer.core.target.TargetShutterDisplayState.Available)
    }

    @Test
    fun restoreNormalizesStaleFilmSelectionWhenFilmNoLongerExists() {
        val origin = controller()
        origin.selectFilm("ilford-pan-f-plus-50")
        val exported = origin.exportSession()

        // Rebuild with the selected film removed from the catalog (e.g. a
        // deleted custom film). The stale selection is normalized to a safe
        // state, not re-persisted as a broken reference.
        val reduced = films.filterNot { it.id == "ilford-pan-f-plus-50" }
        val restored = CalculatorController(films = reduced, initialSession = exported)

        assertEquals("No film", restored.state.value.selectedFilmName)
        val activeSnapshot = restored.exportSession().snapshots[CameraSlotId.camera1]
        assertNull(activeSnapshot?.selectedFilmId)
        assertNull(activeSnapshot?.selectedProfileId)
    }

    @Test
    fun customFilmDraftRoundTripsFormulaFieldsForEditing() {
        val custom = com.sangwook.ptimer.core.customfilm.CustomFilmBuilder.buildFormulaFilm(
            input = com.sangwook.ptimer.core.customfilm.CustomFormulaFilmInput(
                filmLabel = "HP5-x",
                profileName = "HP5-x",
                iso = 800,
                coefficientSeconds = 2.0,
                referenceMeteredTimeSeconds = 1.0,
                exponent = 1.32,
                offsetSeconds = 0.0,
                noCorrectionThroughSeconds = 1.0,
                sourceRangeThroughSeconds = 30.0,
                manufacturer = "Ilford",
            ),
            filmId = "custom-1",
            profileId = "custom-profile-1",
        )!!
        val c = controller()
        c.setFilms(films + custom)

        val draft = c.customFilmDraft("custom-1")!!
        assertFalse(draft.isTable)
        assertEquals("HP5-x", draft.label)      // manufacturer stripped from the canonical name
        assertEquals("Ilford", draft.manufacturer)
        assertEquals("800", draft.iso)
        assertEquals("2", draft.tc0)
        assertEquals("1.32", draft.exponent)
        assertEquals("30", draft.sourceThrough)
        assertEquals("custom-profile-1", c.customFilmProfileId("custom-1"))
    }

    @Test
    fun customFilmDraftRoundTripsDetailsMetadataForEditing() {
        val custom = com.sangwook.ptimer.core.customfilm.CustomFilmBuilder.buildFormulaFilm(
            input = com.sangwook.ptimer.core.customfilm.CustomFormulaFilmInput(
                filmLabel = "Noted", profileName = "Noted", iso = 100,
                coefficientSeconds = 1.0, referenceMeteredTimeSeconds = 1.0,
                exponent = 1.3, noCorrectionThroughSeconds = 1.0,
                notes = "Pushed one stop",
                sourceType = com.sangwook.ptimer.core.reciprocity.CustomProfileSourceType.personalTest,
                referenceUrl = "https://example.com/recip",
            ),
            filmId = "custom-d", profileId = "custom-profile-d",
        )!!
        val c = controller()
        c.setFilms(films + custom)

        val draft = c.customFilmDraft("custom-d")!!
        assertEquals("Pushed one stop", draft.notes)
        assertEquals(com.sangwook.ptimer.core.reciprocity.CustomProfileSourceType.personalTest, draft.sourceType)
        assertEquals("https://example.com/recip", draft.referenceUrl)
    }

    @Test
    fun previewTableFitAndFormulaFromTableInputDeriveFromTheForm() {
        val c = controller()
        val input = com.sangwook.ptimer.core.customfilm.CustomTableFilmInput(
            filmLabel = "My Table", profileName = "My Table", iso = 100,
            anchors = listOf(1.0 to 1.3, 10.0 to 15.0, 100.0 to 200.0),
            noCorrectionThroughSeconds = 0.5,
        )
        // The inline preview fits a usable formula from the in-progress anchors.
        val outcome = c.previewTableFit(input)
        assertTrue(outcome is com.sangwook.ptimer.core.customfilm.CustomTableFittedFormula.Outcome.Available)

        // Create-from-table yields a separate formula film labelled "(formula)".
        val film = c.buildFormulaFilmFromTableInput(input, "f", "p")!!
        assertTrue(film.canonicalStockName.contains("(formula)"))
        assertNotNull(film.profiles.first().rules.firstNotNullOfOrNull { it.formula })

        // The fitted coefficient/exponent carry full double precision; the editor
        // draft must round them so chips + calculation basis don't overflow.
        c.setFilms(films + film)
        val draft = c.customFilmDraft(film.id)!!
        assertTrue("tc0 should be rounded, was ${draft.tc0}", draft.tc0.length <= 6)
        assertTrue("exponent should be rounded, was ${draft.exponent}", draft.exponent.length <= 6)
    }

    @Test
    fun formulaFromTableLinksBackAndReferencePointsTrackTableEdits() {
        val c = controller()
        val tableInput = com.sangwook.ptimer.core.customfilm.CustomTableFilmInput(
            filmLabel = "Linked", profileName = "Linked", iso = 100,
            anchors = listOf(1.0 to 1.3, 10.0 to 15.0), noCorrectionThroughSeconds = 0.5,
        )
        val table = com.sangwook.ptimer.core.customfilm.CustomFilmBuilder.buildTableFilm(tableInput, "table-1", "tp")!!
        val formula = c.buildFormulaFilmFromTableInput(tableInput, "formula-1", "fp", referenceTableFilmId = "table-1")!!
        c.setFilms(films + table + formula)

        // The formula's editor draft resolves the source table's current anchors.
        val draft = c.customFilmDraft("formula-1")!!
        assertEquals("table-1", draft.referenceTableFilmId)
        assertEquals(2, draft.linkedTableAnchors.size)

        // Reference points compare the formula against those anchors.
        val input = com.sangwook.ptimer.core.customfilm.CustomFormulaFilmInput(
            filmLabel = draft.label, profileName = draft.label, iso = draft.iso.toInt(),
            coefficientSeconds = draft.tc0.toDouble(), referenceMeteredTimeSeconds = draft.tm0.toDouble(),
            exponent = draft.exponent.toDouble(), offsetSeconds = draft.offset.toDouble(),
            noCorrectionThroughSeconds = draft.noCorrection.toDouble(),
        )
        val rows = c.referencePoints(input, draft.linkedTableAnchors)
        assertEquals(2, rows.size)
        assertEquals(1.0, rows.first().meteredSeconds, 0.0)
        assertEquals(1.3, rows.first().referenceCorrectedSeconds, 0.0)
    }

    @Test
    fun customFilmDraftRoundTripsTableAnchorsForEditing() {
        val custom = com.sangwook.ptimer.core.customfilm.CustomFilmBuilder.buildTableFilm(
            input = com.sangwook.ptimer.core.customfilm.CustomTableFilmInput(
                filmLabel = "My Table",
                profileName = "My Table",
                iso = 100,
                anchors = listOf(1.0 to 1.3, 10.0 to 15.0),
                noCorrectionThroughSeconds = 0.5,
            ),
            filmId = "custom-t",
            profileId = "custom-profile-t",
        )!!
        val c = controller()
        c.setFilms(films + custom)

        val draft = c.customFilmDraft("custom-t")!!
        assertTrue(draft.isTable)
        assertEquals("My Table", draft.label)
        assertEquals(listOf("1" to "1.3", "10" to "15"), draft.anchors)
    }
}
