package com.sangwook.ptimer.app.vm

import com.sangwook.ptimer.app.calc.ShootingCalculator
import com.sangwook.ptimer.core.exposure.ExposureCalculator
import com.sangwook.ptimer.core.exposure.ExposureScale
import com.sangwook.ptimer.core.reciprocity.AlternateReciprocityModels
import com.sangwook.ptimer.core.reciprocity.FilmIdentity
import com.sangwook.ptimer.core.reciprocity.ReciprocityProfile
import com.sangwook.ptimer.core.timer.TimerIdentity
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

data class FilmOption(val id: String?, val name: String)
data class ModelOption(val id: String, val label: String)

/** Immutable state the shooting calculator surface renders. */
data class CalculatorUiState(
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
)

/**
 * Owns the shooting calculator surface: base-shutter / ND wheel indices, film
 * + alternate-model selection, and the derived result. Start delegates the
 * computed duration + captured identity to the timer workspace via [onStart].
 * Pure of Android; deterministic and unit-testable.
 */
class CalculatorController(
    private val films: List<FilmIdentity>,
    private val calculator: ShootingCalculator = ShootingCalculator(),
    private val exposure: ExposureCalculator = ExposureCalculator(),
    private val onStart: (duration: Double, identity: TimerIdentity) -> Unit = { _, _ -> },
) {
    private val shutterLabels = ExposureScale.oneThirdStopShutterCameraLabels
    private val shutterSteps = ExposureScale.oneThirdStop.shutterSteps
    private val ndLabels = (0..ExposureScale.MAXIMUM_WHOLE_ND_STOPS).map { it.toString() }

    private var shutterIndex = shutterLabels.indexOf("1/30").coerceAtLeast(0)
    private var ndIndex = 0
    private var selectedFilmId: String? = null
    private var selectedProfileId: String? = null

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

    fun start() {
        val result = calculator.result(shutterIndex, ndIndex, resolvedProfile())
        val duration = result.startDurationSeconds ?: return
        onStart(duration, identity(result))
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

    private fun identity(result: com.sangwook.ptimer.app.calc.ShootingResult): TimerIdentity {
        val film = selectedFilm()
        val filmName = film?.canonicalStockName ?: "No film"
        val stops = ndIndex
        return TimerIdentity(
            title = "Camera 1 · $filmName",
            subtitle = result.confidenceLabel?.let { "Calculated · $it" } ?: "Calculated · $stops stops",
            baseLine = "Base ${shutterLabels[shutterIndex]} · $stops stops",
            slotLabel = "C1",
        )
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
            shutterLabels = shutterLabels,
            shutterIndex = shutterIndex,
            ndLabels = ndLabels,
            ndIndex = ndIndex,
            filmOptions = listOf(FilmOption(null, "No film")) +
                films.map { FilmOption(it.id, it.canonicalStockName) },
            selectedFilmId = selectedFilmId,
            selectedFilmName = film?.canonicalStockName ?: "No film",
            modelOptions = modelOptions,
            selectedProfileId = selectedProfileId,
            adjustedText = exposure.formatExtendedClock(result.adjustedShutterSeconds),
            correctedText = result.correctedSeconds?.let { exposure.formatExtendedClock(it) },
            confidenceLabel = result.confidenceLabel,
            startEnabled = result.startEnabled,
            hint = result.hint,
        )
    }
}
