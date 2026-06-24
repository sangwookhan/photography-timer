package com.sangwook.ptimer.app.vm

import com.sangwook.ptimer.app.calc.ShootingCalculator
import com.sangwook.ptimer.app.calc.ShootingResult
import com.sangwook.ptimer.core.customfilm.CustomFormulaFilmInput
import com.sangwook.ptimer.core.customfilm.CustomTableFilmInput
import com.sangwook.ptimer.core.exposure.ExposureCalculator
import com.sangwook.ptimer.core.exposure.ExposureScale
import com.sangwook.ptimer.core.reciprocity.AlternateReciprocityModels
import com.sangwook.ptimer.core.reciprocity.FilmIdentity
import com.sangwook.ptimer.core.reciprocity.FilmIdentityKind
import com.sangwook.ptimer.core.reciprocity.ReciprocityAuthority
import com.sangwook.ptimer.core.reciprocity.ReciprocityDetailsDisplayState
import com.sangwook.ptimer.core.reciprocity.ReciprocityDetailsPresenter
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
    val adjustedText: String,
    val correctedText: String?,
    val confidenceLabel: String?,
    val startEnabled: Boolean,
    val hint: String?,
    val targetDisplay: TargetShutterDisplayState,
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
    private var films: List<FilmIdentity>,
    private val calculator: ShootingCalculator = ShootingCalculator(),
    private val exposure: ExposureCalculator = ExposureCalculator(),
    private val onStart: (duration: Double, identity: TimerIdentity) -> Unit = { _, _ -> },
) {
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
        defaultSnapshot = SlotCalculatorSnapshot(defaultShutterIndex, 0, null, null),
    )

    private val _state = MutableStateFlow(compute())
    val state: StateFlow<CalculatorUiState> = _state.asStateFlow()

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

    private fun captureSnapshot() =
        SlotCalculatorSnapshot(shutterIndex, ndIndex, selectedFilmId, selectedProfileId, targetSeconds)

    private fun loadSnapshot(snapshot: SlotCalculatorSnapshot) {
        shutterIndex = snapshot.shutterIndex.coerceIn(shutterLabels.indices)
        ndIndex = snapshot.ndIndex.coerceIn(ndLabels.indices)
        selectedFilmId = snapshot.selectedFilmId
        selectedProfileId = snapshot.selectedProfileId
        targetSeconds = snapshot.targetSeconds?.takeIf { it.isFinite() && it > 0 }
    }

    private fun publish() { _state.value = compute() }

    private fun selectedFilm(): FilmIdentity? = selectedFilmId?.let { id -> films.firstOrNull { it.id == id } }

    private fun modelProfiles(film: FilmIdentity): List<ReciprocityProfile> {
        val primary = film.profiles.first()
        return AlternateReciprocityModels.modelPickerOrder(primary, film.id)
    }

    private fun resolvedProfile(): ReciprocityProfile? {
        val film = selectedFilm() ?: return null
        val options = modelProfiles(film)
        return options.firstOrNull { it.id == selectedProfileId } ?: film.profiles.first()
    }

    private fun identity(result: ShootingResult): TimerIdentity {
        val film = selectedFilm()
        val filmName = film?.canonicalStockName ?: "No film"
        val slot = session.activeIdentity
        val stops = ndIndex
        return TimerIdentity(
            title = "${slot.displayName} · $filmName",
            subtitle = result.confidenceLabel?.let { "Calculated · $it" } ?: "Calculated · $stops stops",
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

    private fun comparisonSource(result: ShootingResult): TargetShutterPresenter.ComparisonSource {
        val corrected = result.correctedSeconds
        return if (corrected != null && corrected.isFinite() && corrected > 0) {
            TargetShutterPresenter.ComparisonSource.CorrectedExposure(corrected)
        } else {
            TargetShutterPresenter.ComparisonSource.AdjustedShutter(result.adjustedShutterSeconds)
        }
    }

    private fun compute(): CalculatorUiState {
        val film = selectedFilm()
        val profile = resolvedProfile()
        val result = calculator.result(shutterIndex, ndIndex, profile)
        val modelOptions = film?.let { f ->
            val options = modelProfiles(f)
            if (options.size > 1) options.map { ModelOption(it.id, it.selectorLabel ?: it.name) } else emptyList()
        } ?: emptyList()

        return CalculatorUiState(
            slots = session.availableSlots.map {
                SlotTab(it, session.identity(it).displayName, it == session.activeSlotId)
            },
            activeSlotName = session.activeIdentity.displayName,
            shutterLabels = shutterLabels,
            shutterIndex = shutterIndex,
            ndLabels = ndLabels,
            ndIndex = ndIndex,
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
            selectedFilmId = selectedFilmId,
            selectedFilmName = film?.canonicalStockName ?: "No film",
            modelOptions = modelOptions,
            selectedProfileId = selectedProfileId,
            adjustedText = exposure.formatExtendedClock(result.adjustedShutterSeconds),
            correctedText = result.correctedSeconds?.let { exposure.formatExtendedClock(it) },
            confidenceLabel = result.confidenceLabel,
            startEnabled = result.startEnabled,
            hint = result.hint,
            targetDisplay = TargetShutterPresenter.makeDisplayState(targetSeconds, comparisonSource(result)),
        )
    }
}
