// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.app.vm

import com.sangwook.ptimer.app.calc.ShootingCalculator
import com.sangwook.ptimer.app.calc.ShootingResult
import com.sangwook.ptimer.core.customfilm.CustomFormulaFilmInput
import com.sangwook.ptimer.core.customfilm.CustomTableFilmInput
import com.sangwook.ptimer.core.exposure.ExposureCalculator
import com.sangwook.ptimer.core.exposure.ExposureScale
import com.sangwook.ptimer.core.exposure.NDNotationFormatter
import com.sangwook.ptimer.core.exposure.NDNotationMode
import com.sangwook.ptimer.core.reciprocity.AlternateReciprocityModels
import com.sangwook.ptimer.core.reciprocity.ReciprocityAuthority
import com.sangwook.ptimer.core.reciprocity.calculatedCorrectedSeconds
import com.sangwook.ptimer.core.reciprocity.FilmIdentity
import com.sangwook.ptimer.core.reciprocity.FilmIdentityKind
import com.sangwook.ptimer.core.reciprocity.ReciprocityDetailsDisplayState
import com.sangwook.ptimer.core.reciprocity.ReciprocityDetailsPresenter
import com.sangwook.ptimer.core.persistence.PersistentSlotSession
import com.sangwook.ptimer.core.reciprocity.ReciprocityProfile
import com.sangwook.ptimer.core.slots.CameraSlotId
import com.sangwook.ptimer.core.slots.CameraSlotSession
import com.sangwook.ptimer.core.slots.SlotCalculatorSnapshot
import com.sangwook.ptimer.core.target.TargetShutterDisplayState
import com.sangwook.ptimer.core.target.TargetShutterPresenter
import com.sangwook.ptimer.core.timer.TimerIdentity
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

data class FilmOption(
    val id: String?,
    val name: String,
    val manufacturer: String? = null,
    val iso: Int? = null,
    val isUnofficial: Boolean = false,
    val hasReciprocityCurve: Boolean = false,
    val isCustom: Boolean = false,
)

data class ModelOption(val id: String, val label: String)
data class SlotTab(val id: CameraSlotId, val displayName: String, val isActive: Boolean)

/** Immutable state the shooting calculator surface renders. */
data class CalculatorUiState(
    val slots: List<SlotTab>,
    val activeSlotName: String,
    val shutterLabels: List<String>,
    val shutterIndex: Int,
    val ndLabels: List<String>,
    val ndIndex: Int,
    val filmOptions: List<FilmOption>,
    val selectedFilmId: String?,
    val selectedFilmName: String,
    val modelOptions: List<ModelOption>,
    val selectedProfileId: String?,
    val hasFilm: Boolean,
    /**
     * True when the slot has anything a reset would clear: non-default
     * settings (film, ND, shutter, target) or a custom camera name.
     * Gates the Reset affordance so it shows only when actionable
     * (matches iOS).
     */
    val canReset: Boolean,
    /** Current ND notation display mode; drives the wheel labels + the toggle (PTIMER-187). */
    val ndNotationMode: NDNotationMode = NDNotationMode.DEFAULT,
    val adjustedText: String,
    /** Whole-seconds comparison (e.g. "34953s") for clock-band values; null otherwise. */
    val adjustedSecondsText: String?,
    val adjustedStartEnabled: Boolean,
    val correctedText: String?,
    val correctedSecondsText: String?,
    val correctedStartEnabled: Boolean,
    val confidenceLabel: String?,
    val startEnabled: Boolean,
    val hint: String?,
    val targetDisplay: TargetShutterDisplayState,
    /**
     * Per-slot read-only states in [slots] order, so the camera pager can render
     * each page from its own slot instead of cloning the active page during a
     * swipe. Populated only on the top-level (active) state; each entry here has
     * an empty list.
     */
    val slotStates: List<CalculatorUiState> = emptyList(),
)

/**
 * Owns the shooting calculator surface across camera slots: base-shutter /
 * ND wheel indices, film + alternate-model selection, and the derived
 * result for the active slot. Per-slot state lives in the [CameraSlotSession],
 * which owns a stable snapshot for every slot; the controller reads and mutates
 * the active slot's snapshot in place, so a slot switch just re-points the
 * active slot without capturing or restoring live state. Start delegates the
 * computed duration + captured identity to the timer workspace via [onStart].
 * Pure of Android; deterministic and unit-testable.
 */
class CalculatorController(
    films: List<FilmIdentity>,
    private val calculator: ShootingCalculator = ShootingCalculator(),
    private val exposure: ExposureCalculator = ExposureCalculator(),
    private val onStart: (duration: Double, identity: TimerIdentity) -> Unit = { _, _ -> },
    initialSession: PersistentSlotSession? = null,
) {
    // Catalog + custom films; replaced via [setFilms] when the custom library changes.
    private var films: List<FilmIdentity> = films

    private val shutterLabels = ExposureScale.oneThirdStopShutterCameraLabels
    private val ndStopRange = 0..ExposureScale.MAXIMUM_WHOLE_ND_STOPS
    private val defaultShutterIndex = shutterLabels.indexOf("1/30").coerceAtLeast(0)

    // App-global ND notation display mode (PTIMER-187); display-only, never feeds calc.
    private var ndNotationMode: NDNotationMode = NDNotationMode.DEFAULT

    /** ND wheel labels for the current notation mode (same length/order as the stop ladder). */
    private fun ndLabels(): List<String> =
        ndStopRange.map { NDNotationFormatter.display(it.toDouble(), ndNotationMode).value }

    private val defaultSnapshot = SlotCalculatorSnapshot(defaultShutterIndex, 0, null, null)

    // The session is the single owner of every slot's calculator state; the
    // active slot's inputs are read/written through [session] in place, not
    // mirrored into controller-level fields.
    private val session = CameraSlotSession(
        initialActiveSlotId = initialSession?.activeSlotId ?: CameraSlotId.camera1,
        defaultSnapshot = defaultSnapshot,
        initialSnapshots = initialSession?.snapshots ?: emptyMap(),
        initialCustomNames = initialSession?.customNames ?: emptyMap(),
    )

    // Read-only views of the active slot's owned state.
    private val shutterIndex: Int get() = session.activeSnapshot.shutterIndex
    private val ndIndex: Int get() = session.activeSnapshot.ndIndex
    private val selectedFilmId: String? get() = session.activeSnapshot.selectedFilmId
    private val selectedProfileId: String? get() = session.activeSnapshot.selectedProfileId
    private val targetSeconds: Double? get() = session.activeSnapshot.targetSeconds

    init {
        // Normalize the restored active slot (coerce indices, drop a stale film /
        // profile reference) so a deleted custom film is not re-persisted as a
        // broken selection. Inactive slots normalize when they become active.
        session.updateActiveSnapshot { normalizeSnapshot(it) }
    }

    private val _state = MutableStateFlow(compute())
    val state: StateFlow<CalculatorUiState> = _state.asStateFlow()

    /** Serializable snapshot of the whole slot session (every slot's owned state). */
    fun exportSession(): PersistentSlotSession = PersistentSlotSession(
        activeSlotId = session.activeSlotId,
        snapshots = session.currentSnapshots(),
        customNames = session.currentCustomNames(),
    )

    fun setShutterIndex(index: Int) {
        session.updateActiveSnapshot { it.copy(shutterIndex = index.coerceIn(shutterLabels.indices)) }
        publish()
    }

    fun setNdIndex(index: Int) {
        session.updateActiveSnapshot { it.copy(ndIndex = index.coerceIn(ndStopRange.first, ndStopRange.last)) }
        publish()
    }

    /** Sets the ND notation display mode; re-publishes so wheel labels update. */
    fun setNotationMode(mode: NDNotationMode) {
        if (mode == ndNotationMode) return
        ndNotationMode = mode
        publish()
    }

    fun selectFilm(id: String?) {
        // Reset the model selection to the film's primary profile.
        val profileId = id?.let { films.firstOrNull { f -> f.id == it }?.profiles?.firstOrNull()?.id }
        session.updateActiveSnapshot { it.copy(selectedFilmId = id, selectedProfileId = profileId) }
        publish()
    }

    fun selectProfile(id: String) {
        // PTIMER-158: only models present in the (community-filtered) picker can
        // be activated; a hidden community/practical or otherwise unknown id
        // normalizes to the film's primary official profile.
        val film = selectedFilm()
        val resolved = id.takeIf { pid -> film != null && modelProfiles(film).any { it.id == pid } }
        session.updateActiveSnapshot { it.copy(selectedProfileId = resolved) }
        publish()
    }

    /** Replaces the available film list (preset + custom library) and republishes. */
    fun setFilms(list: List<FilmIdentity>) { films = list; publish() }

    /** Sets the active slot's Target Shutter duration; a non-finite/≤0 value clears it. */
    fun setTargetShutter(seconds: Double?) {
        val target = seconds?.takeIf { it.isFinite() && it > 0 }
        session.updateActiveSnapshot { it.copy(targetSeconds = target) }
        publish()
    }

    /** Starts a timer from the active slot's target duration (no-op when unset). */
    fun startFromTarget() {
        val target = targetSeconds ?: return
        val result = calculator.result(shutterIndex, ndIndex, resolvedProfile())
        onStart(target, identity(result, "Target Exposure", target, includesAdjusted = true))
    }

    /** Starts a timer from the ND-adjusted shutter (the digital / pre-reciprocity value). */
    fun startFromAdjusted() {
        val result = calculator.result(shutterIndex, ndIndex, resolvedProfile())
        val d = result.adjustedShutterSeconds
        if (d.isFinite() && d > 0) onStart(d, identity(result, "Adjusted Exposure", d, includesAdjusted = false))
    }

    /** Starts a timer from the reciprocity-corrected exposure, including an
     * out-of-range ("outside guidance") computed value; no-op when truly none. */
    fun startFromCorrected() {
        val result = calculator.result(shutterIndex, ndIndex, resolvedProfile())
        val d = (result.correctedSeconds ?: result.reciprocity?.calculatedCorrectedSeconds) ?: return
        if (d.isFinite() && d > 0) onStart(d, identity(result, "Corrected Exposure", d, includesAdjusted = true))
    }

    /**
     * Resets the active slot's shooting settings to defaults: no film,
     * base 1/30, ND 0, no target. Keeps the custom camera name (the
     * "Reset settings" choice).
     */
    fun resetActiveSlotSettings() {
        resetActiveSlotSettingsFields()
        publish()
    }

    /**
     * Resets the active slot's settings *and* clears its custom camera
     * name, returning the slot to a fully blank state (the "Reset
     * settings and name" choice).
     */
    fun resetActiveSlotSettingsAndName() {
        resetActiveSlotSettingsFields()
        session.resetCustomName(session.activeSlotId)
        publish()
    }

    private fun resetActiveSlotSettingsFields() {
        session.updateActiveSnapshot { defaultSnapshot }
    }

    // --- Custom-film editing (delegated to CustomFilmEditingPresenter) ---

    fun previewTableFit(input: CustomTableFilmInput) =
        CustomFilmEditingPresenter.previewTableFit(input)

    fun buildFormulaFilmFromTableInput(
        input: CustomTableFilmInput,
        filmId: String,
        profileId: String,
        referenceTableFilmId: String? = null,
    ) = CustomFilmEditingPresenter.buildFormulaFilmFromTableInput(input, filmId, profileId, referenceTableFilmId)

    fun referencePoints(input: CustomFormulaFilmInput, anchors: List<Pair<Double, Double>>) =
        CustomFilmEditingPresenter.referencePoints(input, anchors)

    fun tableAnchorsOf(filmId: String?) = CustomFilmEditingPresenter.tableAnchorsOf(films, filmId)

    fun previewFormulaGraph(input: CustomFormulaFilmInput) =
        CustomFilmEditingPresenter.previewFormulaGraph(input, currentAdjustedSeconds())

    fun previewTableGraph(input: CustomTableFilmInput) =
        CustomFilmEditingPresenter.previewTableGraph(input, currentAdjustedSeconds())

    fun previewFormulaCheckpoints(input: CustomFormulaFilmInput) =
        CustomFilmEditingPresenter.previewFormulaCheckpoints(input)

    fun previewTableCheckpoints(input: CustomTableFilmInput) =
        CustomFilmEditingPresenter.previewTableCheckpoints(input)

    fun calculationBasis(input: CustomFormulaFilmInput) =
        CustomFilmEditingPresenter.calculationBasis(input)

    private fun currentAdjustedSeconds(): Double =
        calculator.result(shutterIndex, ndIndex, null).adjustedShutterSeconds

    fun customFilmDraft(filmId: String) = CustomFilmEditingPresenter.customFilmDraft(films, filmId)

    fun customFilmProfileId(filmId: String) = CustomFilmEditingPresenter.customFilmProfileId(films, filmId)

    /** Reciprocity details for the active film/profile; null in the digital (no-film) workflow. */
    fun detailsState(): ReciprocityDetailsDisplayState? {
        val film = selectedFilm() ?: return null
        val profile = resolvedProfile() ?: return null
        val result = calculator.result(shutterIndex, ndIndex, profile)
        val recip = result.reciprocity ?: return null
        return ReciprocityDetailsPresenter.make(
            film = film,
            profile = profile,
            result = recip,
            adjustedShutterSeconds = result.adjustedShutterSeconds,
            formatDuration = exposure::formatCoarse,
        )
    }

    /** Switches the active camera slot. Each slot owns its own snapshot, so this
     * only re-points the active slot — no capture/restore of live state. The
     * newly-active slot is normalized in place so visiting a slot heals a stale
     * film/profile or an out-of-range index in its stored snapshot (matching the
     * pre-refactor load-on-switch behavior) without re-persisting a broken ref. */
    fun selectSlot(id: CameraSlotId) {
        if (!session.switchActiveSlot(id)) return
        session.updateActiveSnapshot { normalizeSnapshot(it) }
        publish()
    }

    /** Renames the active slot; a blank name clears the custom name back to `Camera N`. */
    fun renameActiveSlot(name: String?) {
        session.setCustomName(name, session.activeSlotId)
        publish()
    }

    fun start() {
        val result = calculator.result(shutterIndex, ndIndex, resolvedProfile())
        val duration = result.startDurationSeconds ?: return
        // Digital/no-film start uses the same shape as Adjusted (the digital
        // result is the ND-adjusted shutter); film starts go through the
        // dedicated adjusted/corrected entry points above.
        val source = if (selectedFilm() == null) "Calculated" else "Corrected Exposure"
        val includesAdjusted = selectedFilm() != null
        onStart(duration, identity(result, source, duration, includesAdjusted))
    }

    /**
     * Coerces a restored snapshot into a safe state: wheel indices back into
     * range, and a stale film/profile selection dropped so a deleted custom
     * film (or a profile id no longer valid for the film) is not re-persisted
     * as a broken reference. An unknown film clears both; an invalid profile
     * for a known film clears the profile (it falls back to the film's primary).
     */
    private fun normalizeSnapshot(snapshot: SlotCalculatorSnapshot): SlotCalculatorSnapshot {
        val film = snapshot.selectedFilmId?.let { id -> films.firstOrNull { it.id == id } }
        return SlotCalculatorSnapshot(
            shutterIndex = snapshot.shutterIndex.coerceIn(shutterLabels.indices),
            ndIndex = snapshot.ndIndex.coerceIn(ndStopRange.first, ndStopRange.last),
            selectedFilmId = film?.id,
            selectedProfileId = film?.let { f ->
                snapshot.selectedProfileId?.takeIf { pid -> modelProfiles(f).any { it.id == pid } }
            },
            targetSeconds = snapshot.targetSeconds?.takeIf { it.isFinite() && it > 0 },
        )
    }

    private fun publish() { _state.value = compute() }

    private fun selectedFilm(): FilmIdentity? = selectedFilmId?.let { id -> films.firstOrNull { it.id == id } }

    private fun modelProfiles(film: FilmIdentity): List<ReciprocityProfile> {
        val primary = film.profiles.first()
        return AlternateReciprocityModels.modelPickerOrder(primary, film.id)
    }

    private fun resolvedProfile(): ReciprocityProfile? = resolvedProfileFor(selectedFilm(), selectedProfileId)

    private fun resolvedProfileFor(film: FilmIdentity?, profileId: String?): ReciprocityProfile? {
        film ?: return null
        val options = modelProfiles(film)
        return options.firstOrNull { it.id == profileId } ?: film.profiles.first()
    }

    /**
     * Captured timer identity (PTIMER-187): the title carries the camera + film
     * identity, the second line carries the exposure source + final value, and
     * the structured ND/base/adjusted fields let the timer card render its basis
     * in the current notation mode. No ND token / duration in the title, and no
     * film name / duration repeated on the second line.
     *
     * [includesAdjusted] is true for corrected/target timers, where the adjusted
     * shutter is an intermediate distinct from the final duration.
     */
    private fun identity(
        result: ShootingResult,
        source: String,
        finalSeconds: Double,
        includesAdjusted: Boolean,
    ): TimerIdentity {
        val film = selectedFilm()
        val filmName = film?.canonicalStockName ?: "No film"
        val slot = session.activeIdentity
        val ladder = ExposureScale.oneThirdStop.shutterSteps
        val base = ladder[shutterIndex.coerceIn(ladder.indices)].seconds
        return TimerIdentity(
            title = "${slot.displayName} · $filmName",
            subtitle = "$source ${exposure.formatExtendedClock(finalSeconds)}",
            slotLabel = slot.id.shortLabel,
            ndStops = ndIndex.toDouble(),
            baseShutterSeconds = base,
            adjustedShutterSeconds = result.adjustedShutterSeconds,
            basisIncludesAdjusted = includesAdjusted,
            filmName = filmName,
        )
    }

    /** Whole-seconds secondary for clock-band values (1 min .. 1 day); null otherwise. */
    private fun secondsComparison(seconds: Double): String? {
        if (!seconds.isFinite() || seconds < 60 || seconds >= 86_400) return null
        return "${Math.round(seconds)}s"
    }

    private fun comparisonSource(result: ShootingResult): TargetShutterPresenter.ComparisonSource {
        // Compare the target against the corrected exposure when a usable number
        // exists (including an out-of-range "outside guidance" value). Digital
        // workflow falls back to the adjusted shutter so the ↑/↓ stop guidance
        // is always shown while a target is set. Film workflow without a
        // quantified corrected exposure (limited-guidance / unsupported) must
        // not silently fall back to the intermediate adjusted shutter — the
        // comparison is unavailable instead (PTIMER-191).
        val corrected = result.correctedSeconds ?: result.reciprocity?.calculatedCorrectedSeconds
        if (corrected != null && corrected.isFinite() && corrected > 0) {
            return TargetShutterPresenter.ComparisonSource.CorrectedExposure(corrected)
        }
        return if (result.isDigital) {
            TargetShutterPresenter.ComparisonSource.AdjustedShutter(result.adjustedShutterSeconds)
        } else {
            TargetShutterPresenter.ComparisonSource.Unavailable
        }
    }

    /**
     * Top-level state: the active slot's state, carrying every slot's read-only
     * state in [CalculatorUiState.slotStates] so the camera pager renders each
     * page from its own slot (no clone-until-settle during a swipe). Every slot
     * reads its own session-owned snapshot.
     */
    private fun compute(): CalculatorUiState {
        val perSlot = session.availableSlots.map { slotId ->
            computeSlot(session.snapshot(slotId) ?: defaultSnapshot, slotId)
        }
        val activeIndex = session.availableSlots.indexOf(session.activeSlotId).coerceAtLeast(0)
        return perSlot[activeIndex].copy(slotStates = perSlot)
    }

    /** Builds a slot's read-only calculator state from its snapshot inputs. */
    private fun computeSlot(snapshot: SlotCalculatorSnapshot, slotId: CameraSlotId): CalculatorUiState {
        val film = snapshot.selectedFilmId?.let { id -> films.firstOrNull { it.id == id } }
        val profile = resolvedProfileFor(film, snapshot.selectedProfileId)
        val result = calculator.result(snapshot.shutterIndex, snapshot.ndIndex, profile)
        val modelOptions = film?.let { f ->
            val options = modelProfiles(f)
            if (options.size > 1) options.map { ModelOption(it.id, it.selectorLabel ?: it.name) } else emptyList()
        } ?: emptyList()

        val canReset = snapshot.shutterIndex != defaultShutterIndex ||
            snapshot.ndIndex != 0 ||
            film != null ||
            snapshot.targetSeconds != null ||
            slotId in session.currentCustomNames()

        return CalculatorUiState(
            slots = session.availableSlots.map {
                SlotTab(it, session.identity(it).displayName, it == session.activeSlotId)
            },
            activeSlotName = session.identity(slotId).displayName,
            shutterLabels = shutterLabels,
            shutterIndex = snapshot.shutterIndex,
            ndLabels = ndLabels(),
            ndIndex = snapshot.ndIndex,
            filmOptions = filmOptions(),
            selectedFilmId = snapshot.selectedFilmId,
            selectedFilmName = film?.canonicalStockName ?: "No film",
            modelOptions = modelOptions,
            selectedProfileId = snapshot.selectedProfileId,
            hasFilm = film != null,
            canReset = canReset,
            ndNotationMode = ndNotationMode,
            adjustedText = exposure.formatCoarse(result.adjustedShutterSeconds),
            adjustedSecondsText = secondsComparison(result.adjustedShutterSeconds),
            adjustedStartEnabled = result.adjustedShutterSeconds.isFinite() && result.adjustedShutterSeconds > 0,
            // Show the computed corrected value even when out of range ("outside
            // guidance") so the main matches the Details sheet; only truly-no-value
            // (limited guidance) reads "No corrected value".
            correctedText = (result.correctedSeconds ?: result.reciprocity?.calculatedCorrectedSeconds)
                ?.takeIf { it.isFinite() && it > 0 }?.let { exposure.formatCoarse(it) },
            correctedSecondsText = (result.correctedSeconds ?: result.reciprocity?.calculatedCorrectedSeconds)
                ?.let { secondsComparison(it) },
            correctedStartEnabled = (result.correctedSeconds ?: result.reciprocity?.calculatedCorrectedSeconds ?: 0.0)
                .let { it.isFinite() && it > 0 },
            confidenceLabel = result.confidenceLabel,
            startEnabled = result.startEnabled,
            hint = result.hint,
            targetDisplay = TargetShutterPresenter.makeDisplayState(snapshot.targetSeconds, comparisonSource(result)),
        )
    }

    private fun filmOptions(): List<FilmOption> {
        val options = films.map { f ->
            val primary = f.profiles.firstOrNull()
            FilmOption(
                id = f.id,
                name = f.canonicalStockName,
                manufacturer = f.manufacturer,
                iso = f.iso,
                isUnofficial = primary?.source?.authority == ReciprocityAuthority.unofficial,
                hasReciprocityCurve = primary?.rules?.any {
                    it.formula != null || it.tableInterpolation != null
                } == true,
                isCustom = f.kind == FilmIdentityKind.custom,
            )
        }
        val presetComparator = compareBy<FilmOption, String>(java.lang.String.CASE_INSENSITIVE_ORDER) {
            it.manufacturer.orEmpty()
        }.thenBy(java.lang.String.CASE_INSENSITIVE_ORDER) { it.name }

        return listOf(FilmOption(null, "No film")) +
            options.filter { it.isCustom } +
            options.filterNot { it.isCustom }.sortedWith(presetComparator)
    }
}
