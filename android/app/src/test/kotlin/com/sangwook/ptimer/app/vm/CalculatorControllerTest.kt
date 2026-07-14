// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.app.vm

import com.sangwook.ptimer.core.catalog.LaunchPresetFilmCatalogV2
import com.sangwook.ptimer.core.exposure.ExposureScale
import com.sangwook.ptimer.core.persistence.PersistentSlotSession
import com.sangwook.ptimer.core.slots.CameraSlotId
import com.sangwook.ptimer.core.slots.SlotCalculatorSnapshot
import com.sangwook.ptimer.core.timer.TimerIdentity
import kotlin.math.abs
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
    fun communityPracticalModelsAreHiddenFromPicker() {
        // PTIMER-158: unofficial community/practical models are hidden from the
        // model picker for this release; official app-derived models stay.
        val c = controller()
        c.selectFilm("foma-fomapan-100")
        val fomaOptions = c.state.value.modelOptions
        assertFalse(fomaOptions.any { it.id == "foma-fomapan-100-ohzart-community-table" })
        assertTrue(fomaOptions.any { it.id == "foma-fomapan-100-app-formula" })

        c.selectFilm("kodak-portra-400")
        assertFalse(c.state.value.modelOptions.any { it.id == "kodak-portra-400-unofficial-practical" })
    }

    @Test
    fun selectingHiddenCommunityModelNormalizesToOfficialPrimary() {
        // Activating a now-hidden community model falls back to the film's
        // official primary profile instead of switching to the community model.
        val c = controller()
        c.selectFilm("kodak-portra-400")
        c.selectProfile("kodak-portra-400-unofficial-practical")
        // The hidden id is dropped (null override → the film's primary official
        // profile is active), never retained as the selected practical model.
        assertNull(c.state.value.selectedProfileId)
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

    // --- PTIMER-209 commercial fractional presets ---

    private fun ladderIndexOf(stops: Double): Int =
        ExposureScale.shippingNDLadder.indexOfFirst { abs(it.stops - stops) < 1e-9 }

    @Test
    fun commercialPresetSelectionRoundTripsThroughPersistence() {
        val nd100kIndex = ladderIndexOf(16.6)
        val c = controller()
        c.setNdIndex(nd100kIndex)

        // The wheel keeps the preset selected (position round-trips).
        assertEquals(nd100kIndex, c.state.value.ndIndex)

        // Exported snapshot: exact value in ndStops, nearest whole in ndIndex.
        val exported = c.exportSession().snapshots.getValue(CameraSlotId.camera1)
        assertEquals(16.6, exported.ndStops!!, 1e-9)
        assertEquals(17, exported.ndIndex)

        // Relaunch: a fresh controller restores the preset exactly.
        val relaunched = CalculatorController(films = films, initialSession = c.exportSession())
        assertEquals(nd100kIndex, relaunched.state.value.ndIndex)
    }

    @Test
    fun wholeStopSelectionLeavesExactFieldNull() {
        val c = controller()
        c.setNdIndex(ladderIndexOf(7.0))
        val exported = c.exportSession().snapshots.getValue(CameraSlotId.camera1)
        assertNull(exported.ndStops)
        assertEquals(7, exported.ndIndex)
    }

    @Test
    fun unsupportedExactValueIgnoredOnRestore() {
        // An off-grid ndStops (cannot arise from the picker) is ignored on
        // restore; the whole-stop ndIndex is used instead.
        val session = PersistentSlotSession(
            activeSlotId = CameraSlotId.camera1,
            snapshots = mapOf(
                CameraSlotId.camera1 to SlotCalculatorSnapshot(
                    shutterIndex = 0,
                    ndIndex = 5,
                    selectedFilmId = null,
                    selectedProfileId = null,
                    ndStops = 12.4,
                ),
            ),
        )
        val c = CalculatorController(films = films, initialSession = session)
        assertEquals(ladderIndexOf(5.0), c.state.value.ndIndex)
    }

    @Test
    fun twoSlotsKeepIndependentCalculatorAndFilmStateAcrossSwitches() {
        // PTIMER-192: per-slot state is owned independently, so switching between
        // two slots with different calculator + Film mode state never bleeds one
        // slot's inputs into the other.
        val c = controller()

        // Camera 1: Pan F Plus, base index 4, ND 6, film primary profile.
        c.selectFilm("ilford-pan-f-plus-50")
        c.setShutterIndex(4)
        c.setNdIndex(6)

        // Camera 2: a different film with alternate models, its own base + ND + profile.
        c.selectSlot(CameraSlotId.camera2)
        c.selectFilm("foma-fomapan-100")
        // A non-primary alternate model (the picker exposes more than one).
        val fomaModel = c.state.value.modelOptions[1]
        c.selectProfile(fomaModel.id)
        c.setShutterIndex(9)
        c.setNdIndex(3)

        // Back to Camera 1: its film, base, and ND are intact.
        c.selectSlot(CameraSlotId.camera1)
        val camera1 = c.state.value
        assertEquals("ilford-pan-f-plus-50", camera1.selectedFilmId)
        assertEquals(4, camera1.shutterIndex)
        assertEquals(6, camera1.ndIndex)

        // Camera 2 still holds its own distinct film, base, ND, and profile.
        c.selectSlot(CameraSlotId.camera2)
        val camera2 = c.state.value
        assertEquals("foma-fomapan-100", camera2.selectedFilmId)
        assertEquals(9, camera2.shutterIndex)
        assertEquals(3, camera2.ndIndex)
        assertEquals(fomaModel.id, camera2.selectedProfileId)
    }

    @Test
    fun customCameraNamesArePreservedPerSlotAcrossSwitches() {
        // PTIMER-192: each slot owns its custom name; switching does not carry a
        // name from one slot onto another or lose it on return.
        val c = controller()
        c.renameActiveSlot("Leica M6")

        c.selectSlot(CameraSlotId.camera2)
        assertEquals("Camera 2", c.state.value.activeSlotName)
        c.renameActiveSlot("Hasselblad 500")

        c.selectSlot(CameraSlotId.camera1)
        assertEquals("Leica M6", c.state.value.activeSlotName)
        c.selectSlot(CameraSlotId.camera2)
        assertEquals("Hasselblad 500", c.state.value.activeSlotName)
    }

    @Test
    fun startedTimerKeepsCameraIdentityWhenSlotStateChangesLater() {
        // PTIMER-192: the identity handed to the timer is a snapshot taken at start,
        // so renaming the slot or switching cameras afterwards does not mutate it.
        var identity: TimerIdentity? = null
        val c = controller { _, id -> identity = id }
        c.renameActiveSlot("Nikon F3")
        c.selectFilm("ilford-pan-f-plus-50")
        c.start()
        val captured = identity!!

        // Later slot activity must not retroactively change the started timer.
        c.renameActiveSlot("Renamed After Start")
        c.selectSlot(CameraSlotId.camera2)
        c.selectFilm("kodak-portra-400")

        assertTrue(captured.title.startsWith("Nikon F3"))
        assertTrue(captured.title.contains("Pan F Plus"))
        assertEquals("C1", captured.slotLabel)
        // The captured value is unchanged by the later edits.
        assertEquals(captured, identity)
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
    fun digitalWorkflowTargetComparesAgainstAdjustedShutter() {
        // ND mode must keep comparing against the Adjusted Shutter — this is
        // the regression guard for PTIMER-191's Android fix.
        val c = controller()
        c.setNdIndex(6)
        c.setTargetShutter(999.0)

        val display = c.state.value.targetDisplay
            as com.sangwook.ptimer.core.target.TargetShutterDisplayState.Available
        val comparison = display.state.comparison
        assertNotNull(comparison)
        assertEquals("Adjusted Shutter", comparison!!.label)
        assertNotNull(display.state.stopDifference)
    }

    @Test
    fun filmWorkflowQuantifiedTargetComparesAgainstCorrectedExposure() {
        val c = controller()
        c.selectFilm("ilford-pan-f-plus-50")
        c.setNdIndex(6)
        assertNotNull(c.state.value.correctedText)

        c.setTargetShutter(999.0)

        val display = c.state.value.targetDisplay
            as com.sangwook.ptimer.core.target.TargetShutterDisplayState.Available
        val comparison = display.state.comparison
        assertNotNull(comparison)
        assertEquals("Corrected Exposure", comparison!!.label)
        assertNotNull(display.state.stopDifference)
    }

    @Test
    fun filmWorkflowLimitedGuidanceTargetComparisonIsUnavailable() {
        // With the current launch catalog, Portra 400 at a 15s metered
        // exposure resolves without a quantified corrected exposure.
        // Target Shutter comparison must not silently fall back to the
        // intermediate Adjusted Shutter value (PTIMER-191).
        val c = controller()
        c.selectFilm("kodak-portra-400")
        c.setShutterIndex(c.state.value.shutterLabels.indexOf("15s"))
        assertNull(c.state.value.correctedText)

        c.setTargetShutter(60.0)

        val display = c.state.value.targetDisplay
            as com.sangwook.ptimer.core.target.TargetShutterDisplayState.Available
        assertEquals(60.0, display.state.targetSeconds, 0.0)
        assertNull(display.state.comparison)
        assertNull(display.state.stopDifference)
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
    fun switchingToASlotWithStaleStoredStateNormalizesUiAndPersistence() {
        // PTIMER-192 regression: an inactive slot restored with a stale film /
        // profile reference, an out-of-range shutter index, and an invalid
        // target must be normalized the moment it becomes active — both the
        // rendered state and what exportSession persists — not carried forward
        // as a broken reference. (ND stays a valid value: an out-of-range ND
        // is not reachable through normal persistence, since the pager compute
        // would reject it at construction.)
        val staleCamera2 = SlotCalculatorSnapshot(
            shutterIndex = 9_999,
            ndIndex = 2,
            selectedFilmId = "deleted-custom-film",
            selectedProfileId = "gone-profile",
            targetSeconds = -5.0,
        )
        val session = PersistentSlotSession(
            activeSlotId = CameraSlotId.camera1,
            snapshots = mapOf(CameraSlotId.camera2 to staleCamera2),
        )
        val c = CalculatorController(films = films, initialSession = session)

        c.selectSlot(CameraSlotId.camera2)
        val ui = c.state.value
        assertEquals("Camera 2", ui.activeSlotName)
        assertEquals("No film", ui.selectedFilmName)
        assertNull(ui.selectedProfileId)
        assertTrue("shutter index coerced into range", ui.shutterIndex in ui.shutterLabels.indices)
        assertEquals(2, ui.ndIndex)
        assertTrue(ui.targetDisplay is com.sangwook.ptimer.core.target.TargetShutterDisplayState.Unavailable)

        val persisted = c.exportSession().snapshots.getValue(CameraSlotId.camera2)
        assertNull(persisted.selectedFilmId)
        assertNull(persisted.selectedProfileId)
        assertTrue(persisted.shutterIndex in ui.shutterLabels.indices)
        assertEquals(2, persisted.ndIndex)
        assertNull(persisted.targetSeconds)
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
