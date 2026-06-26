package com.sangwook.ptimer.app.vm

import com.sangwook.ptimer.app.calc.ShootingCalculator
import com.sangwook.ptimer.app.calc.ShootingResult
import com.sangwook.ptimer.core.customfilm.CustomFormulaFilmInput
import com.sangwook.ptimer.core.customfilm.CustomTableFilmInput
import com.sangwook.ptimer.core.exposure.ExposureCalculator
import com.sangwook.ptimer.core.exposure.ExposureScale
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
 * result for the active slot. A slot switch captures the active slot's live
 * inputs into the [CameraSlotSession] and restores the incoming slot's
 * snapshot, so each camera keeps its own exposure context (iOS
 * capture-on-switch). Start delegates the computed duration + captured
 * identity to the timer workspace via [onStart]. Pure of Android;
 * deterministic and unit-testable.
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
    private val ndLabels = (0..ExposureScale.MAXIMUM_WHOLE_ND_STOPS).map { it.toString() }
    private val defaultShutterIndex = shutterLabels.indexOf("1/30").coerceAtLeast(0)

    // Live state for the active slot.
    private var shutterIndex = defaultShutterIndex
    private var ndIndex = 0
    private var selectedFilmId: String? = null
    private var selectedProfileId: String? = null
    private var targetSeconds: Double? = null

    private val session = CameraSlotSession(
        initialActiveSlotId = initialSession?.activeSlotId ?: CameraSlotId.camera1,
        defaultSnapshot = SlotCalculatorSnapshot(defaultShutterIndex, 0, null, null),
        initialSnapshots = initialSession?.snapshots ?: emptyMap(),
        initialCustomNames = initialSession?.customNames ?: emptyMap(),
    )

    init {
        // Restore the active slot's live state from the persisted session.
        initialSession?.snapshots?.get(session.activeSlotId)?.let { loadSnapshot(it) }
    }

    private val _state = MutableStateFlow(compute())
    val state: StateFlow<CalculatorUiState> = _state.asStateFlow()

    /** Serializable snapshot of the whole slot session (active slot's live state included). */
    fun exportSession(): PersistentSlotSession = PersistentSlotSession(
        activeSlotId = session.activeSlotId,
        snapshots = session.currentInactiveSnapshots() + (session.activeSlotId to captureSnapshot()),
        customNames = session.currentCustomNames(),
    )

    fun setShutterIndex(index: Int) { shutterIndex = index.coerceIn(shutterLabels.indices); publish() }
    fun setNdIndex(index: Int) { ndIndex = index.coerceIn(ndLabels.indices); publish() }

    fun selectFilm(id: String?) {
        selectedFilmId = id
        // Reset the model selection to the film's primary profile.
        selectedProfileId = id?.let { films.firstOrNull { f -> f.id == it }?.profiles?.firstOrNull()?.id }
        publish()
    }

    fun selectProfile(id: String) { selectedProfileId = id; publish() }

    /** Replaces the available film list (preset + custom library) and republishes. */
    fun setFilms(list: List<FilmIdentity>) { films = list; publish() }

    /** Sets the active slot's Target Shutter duration; a non-finite/≤0 value clears it. */
    fun setTargetShutter(seconds: Double?) {
        targetSeconds = seconds?.takeIf { it.isFinite() && it > 0 }
        publish()
    }

    /** Starts a timer from the active slot's target duration (no-op when unset). */
    fun startFromTarget() {
        val target = targetSeconds ?: return
        onStart(target, targetIdentity())
    }

    /** Starts a timer from the ND-adjusted shutter (the digital / pre-reciprocity value). */
    fun startFromAdjusted() {
        val result = calculator.result(shutterIndex, ndIndex, resolvedProfile())
        val d = result.adjustedShutterSeconds
        if (d.isFinite() && d > 0) onStart(d, identity(result, "Adjusted shutter"))
    }

    /** Starts a timer from the reciprocity-corrected exposure, including an
     * out-of-range ("outside guidance") computed value; no-op when truly none. */
    fun startFromCorrected() {
        val result = calculator.result(shutterIndex, ndIndex, resolvedProfile())
        val d = (result.correctedSeconds ?: result.reciprocity?.calculatedCorrectedSeconds) ?: return
        if (d.isFinite() && d > 0) onStart(d, identity(result, "Corrected exposure"))
    }

    /** Resets the active slot to defaults: no film, base 1/30, ND 0, no target, default name. */
    fun resetActiveSlot() {
        shutterIndex = defaultShutterIndex
        ndIndex = 0
        selectedFilmId = null
        selectedProfileId = null
        targetSeconds = null
        session.resetCustomName(session.activeSlotId)
        publish()
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

    /** Switches the active camera slot, capturing the current slot's inputs and restoring the target's. */
    fun selectSlot(id: CameraSlotId) {
        val incoming = session.switchActiveSlot(id, captureSnapshot()) ?: return
        loadSnapshot(incoming)
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
        onStart(duration, identity(result))
    }

    private fun captureSnapshot() =
        SlotCalculatorSnapshot(shutterIndex, ndIndex, selectedFilmId, selectedProfileId, targetSeconds)

    private fun loadSnapshot(snapshot: SlotCalculatorSnapshot) {
        shutterIndex = snapshot.shutterIndex.coerceIn(shutterLabels.indices)
        ndIndex = snapshot.ndIndex.coerceIn(ndLabels.indices)
        // Normalize a stale film/profile selection so a deleted custom film (or
        // a profile id no longer valid for the film) is not re-persisted as a
        // broken selection. An unknown film clears both; an invalid profile for
        // a known film clears the profile (it falls back to the film's primary).
        val film = snapshot.selectedFilmId?.let { id -> films.firstOrNull { it.id == id } }
        selectedFilmId = film?.id
        selectedProfileId = film?.let { f ->
            snapshot.selectedProfileId?.takeIf { pid -> modelProfiles(f).any { it.id == pid } }
        }
        targetSeconds = snapshot.targetSeconds?.takeIf { it.isFinite() && it > 0 }
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

    private fun identity(result: ShootingResult, source: String = "Calculated"): TimerIdentity {
        val film = selectedFilm()
        val filmName = film?.canonicalStockName ?: "No film"
        val slot = session.activeIdentity
        val stops = ndIndex
        return TimerIdentity(
            title = "${slot.displayName} · $filmName",
            subtitle = result.confidenceLabel?.let { "$source · $it" } ?: "$source · $stops stops",
            baseLine = "Base ${shutterLabels[shutterIndex]} · $stops stops",
            slotLabel = slot.id.shortLabel,
        )
    }

    private fun targetIdentity(): TimerIdentity {
        val film = selectedFilm()
        val filmName = film?.canonicalStockName ?: "No film"
        val slot = session.activeIdentity
        return TimerIdentity(
            title = "${slot.displayName} · $filmName",
            subtitle = "Target shutter",
            baseLine = "Target ${exposure.formatExtendedClock(targetSeconds ?: 0.0)}",
            slotLabel = slot.id.shortLabel,
        )
    }

    /** Whole-seconds secondary for clock-band values (1 min .. 1 day); null otherwise. */
    private fun secondsComparison(seconds: Double): String? {
        if (!seconds.isFinite() || seconds < 60 || seconds >= 86_400) return null
        return "${Math.round(seconds)}s"
    }

    private fun comparisonSource(result: ShootingResult): TargetShutterPresenter.ComparisonSource {
        // Compare the target against the corrected exposure when a usable number
        // exists (including an out-of-range "outside guidance" value); otherwise
        // fall back to the adjusted shutter so the ↑/↓ stop guidance is always
        // shown while a target is set — even when there is no corrected value.
        val corrected = result.correctedSeconds ?: result.reciprocity?.calculatedCorrectedSeconds
        return if (corrected != null && corrected.isFinite() && corrected > 0) {
            TargetShutterPresenter.ComparisonSource.CorrectedExposure(corrected)
        } else {
            TargetShutterPresenter.ComparisonSource.AdjustedShutter(result.adjustedShutterSeconds)
        }
    }

    /**
     * Top-level state: the active slot's state, carrying every slot's read-only
     * state in [CalculatorUiState.slotStates] so the camera pager renders each
     * page from its own slot (no clone-until-settle during a swipe). The active
     * slot reads the live fields; inactive slots read their session snapshots.
     */
    private fun compute(): CalculatorUiState {
        val activeSnapshot = captureSnapshot()
        val perSlot = session.availableSlots.map { slotId ->
            val snapshot = if (slotId == session.activeSlotId) {
                activeSnapshot
            } else {
                session.snapshot(slotId) ?: activeSnapshot
            }
            computeSlot(snapshot, slotId)
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

        return CalculatorUiState(
            slots = session.availableSlots.map {
                SlotTab(it, session.identity(it).displayName, it == session.activeSlotId)
            },
            activeSlotName = session.identity(slotId).displayName,
            shutterLabels = shutterLabels,
            shutterIndex = snapshot.shutterIndex,
            ndLabels = ndLabels,
            ndIndex = snapshot.ndIndex,
            filmOptions = listOf(FilmOption(null, "No film")) +
                films.map { f ->
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
                },
            selectedFilmId = snapshot.selectedFilmId,
            selectedFilmName = film?.canonicalStockName ?: "No film",
            modelOptions = modelOptions,
            selectedProfileId = snapshot.selectedProfileId,
            hasFilm = film != null,
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
}
