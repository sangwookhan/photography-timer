package com.sangwook.ptimer.calculator

import com.sangwook.ptimer.core.catalog.AlternateReciprocityModels
import com.sangwook.ptimer.core.catalog.FilmIdentity
import com.sangwook.ptimer.core.catalog.ReciprocityProfile
import com.sangwook.ptimer.core.exposure.CalculatorDefaults
import com.sangwook.ptimer.core.exposure.ExposureCalculator
import com.sangwook.ptimer.core.exposure.ExposureScale
import com.sangwook.ptimer.core.exposure.ExposureScaleMode
import com.sangwook.ptimer.core.exposure.NdStep
import com.sangwook.ptimer.core.reciprocity.ReciprocityCalculationPolicyEvaluator
import com.sangwook.ptimer.core.reciprocity.ReciprocityConfidencePresentationMapper
import com.sangwook.ptimer.core.reciprocity.ReciprocityResult
import com.sangwook.ptimer.target.TargetShutterPresenter
import java.util.Locale

data class ModelOptionUi(val profileId: String, val label: String, val isSelected: Boolean)

/** Immutable calculator/film result state. */
data class CalculatorUiState(
    val baseShutterLabel: String,
    val ndStops: Int,
    val filmName: String?,
    val authorityLabel: String?,
    val adjustedShutterLabel: String,
    val correctedExposureLabel: String?,
    val reciprocityBadge: String?,
    val canStartTimer: Boolean,
    val startDisabledHint: String?,
    val availableModels: List<ModelOptionUi>,
    val isCustomTable: Boolean = false,
    val fittedPreviewSummary: String? = null,
    val selectedCustomFilmId: String? = null,
    val targetSeconds: Double? = null,
    val targetStopDifference: Double? = null,
    val targetIsMatch: Boolean = false,
    val targetUnavailable: Boolean = false,
    val targetSummary: String? = null,
)

/** What a Start-Timer tap should create, or null when disabled. */
data class StartTimerRequest(val name: String, val durationSeconds: Double, val selectedModelLabel: String?)

/**
 * Android-free calculator + film-selection logic. Computes the digital
 * adjusted shutter and, for film, the reciprocity-corrected exposure via the
 * core policy evaluator; resolves preset alternate models; and derives
 * Start-Timer enablement (quantified positive-finite enables the corrected
 * timer; limited/unsupported disables it with a hint). JVM-testable.
 */
class CalculatorController(private val catalog: List<FilmIdentity>) {
    private val calculator = ExposureCalculator()
    private val policy = ReciprocityCalculationPolicyEvaluator()

    private var baseShutterSeconds: Double = CalculatorDefaults.BASE_SHUTTER_SECONDS
    private var ndStops: Int = CalculatorDefaults.ND_STOP
    private var selectedFilmId: String? = null
    private var selectedProfileId: String? = null // null = primary profile
    private var customFilms: List<FilmIdentity> = emptyList()
    private var targetSeconds: Double? = null

    /** Make custom-library films selectable alongside the preset catalog. */
    fun setCustomFilms(films: List<FilmIdentity>) { customFilms = films }

    fun setTarget(seconds: Double?) {
        targetSeconds = seconds?.takeIf { it.isFinite() && it > 0 }
    }
    fun clearTarget() { targetSeconds = null }

    fun setBaseShutterSeconds(seconds: Double) { baseShutterSeconds = seconds }
    fun setBaseShutterLadderIndex(index: Int) {
        val ladder = ExposureScale.oneThirdStop.shutterSteps
        if (index in ladder.indices) baseShutterSeconds = ladder[index].seconds
    }
    fun setNdStops(stops: Int) { ndStops = stops.coerceIn(0, ExposureScale.MAX_WHOLE_ND_STOPS) }
    fun selectFilm(id: String?) { selectedFilmId = id; selectedProfileId = null }
    fun clearFilm() { selectedFilmId = null; selectedProfileId = null }
    fun selectModel(profileId: String?) { selectedProfileId = profileId }

    fun currentBaseSeconds(): Double = baseShutterSeconds
    fun currentFilmId(): String? = selectedFilmId

    /** Capture the active calculator inputs for per-slot persistence. */
    fun capture(): SlotCalculatorSnapshot =
        SlotCalculatorSnapshot(baseShutterSeconds, ndStops, selectedFilmId, selectedProfileId, targetSeconds)

    /** Apply a per-slot snapshot (or reset to defaults when null). */
    fun apply(snapshot: SlotCalculatorSnapshot?) {
        if (snapshot == null) {
            baseShutterSeconds = CalculatorDefaults.BASE_SHUTTER_SECONDS
            ndStops = CalculatorDefaults.ND_STOP
            selectedFilmId = null
            selectedProfileId = null
            targetSeconds = null
            return
        }
        baseShutterSeconds = snapshot.baseShutterSeconds
        ndStops = snapshot.ndStops
        selectedFilmId = snapshot.selectedFilmId
        selectedProfileId = snapshot.selectedProfileId
        targetSeconds = snapshot.targetShutterSeconds
    }

    private fun film(): FilmIdentity? = selectedFilmId?.let { id ->
        catalog.firstOrNull { it.id == id } ?: customFilms.firstOrNull { it.id == id }
    }

    private fun activeProfile(film: FilmIdentity): ReciprocityProfile {
        val pid = selectedProfileId ?: return film.profiles.first()
        return AlternateReciprocityModels.profile(pid) ?: film.profiles.first()
    }

    private fun adjustedShutterSeconds(): Double =
        calculator.calculate(baseShutterSeconds, NdStep(ndStops.toDouble()), ExposureScaleMode.ONE_THIRD_STOP)

    /** Build the reciprocity-details transparency for the active film, or null if digital. */
    fun details(lookup: (String) -> FilmIdentity?): com.sangwook.ptimer.details.DetailsUi? {
        val film = film() ?: return null
        val profile = activeProfile(film)
        val adjusted = adjustedShutterSeconds()
        val result = policy.evaluate(profile, adjusted)
        return com.sangwook.ptimer.details.DetailsPresenter.build(film, profile, result, adjusted, lookup)
    }

    /** The request a Start-Timer tap should create, or null when disabled. */
    fun startRequest(): StartTimerRequest? {
        val adjusted = adjustedShutterSeconds()
        val film = film() ?: return StartTimerRequest("Digital ${calculator.formatShutter(adjusted)}", adjusted, null)
        val profile = activeProfile(film)
        val result = policy.evaluate(profile, adjusted)
        val corrected = (result as? ReciprocityResult.Quantified)?.corrected ?: return null
        if (!corrected.isFinite() || corrected <= 0) return null
        val modelLabel = profile.selectorLabel ?: profile.name
        return StartTimerRequest("${film.canonicalStockName} corrected", corrected, modelLabel)
    }

    fun uiState(): CalculatorUiState {
        val adjusted = adjustedShutterSeconds()
        val adjustedLabel = calculator.formatShutter(adjusted)
        val baseLabel = ExposureScale.oneThirdStopShutterCameraLabel(baseShutterSeconds)
            ?: calculator.formatShutter(baseShutterSeconds)
        val film = film()
            ?: run {
                val tf = targetFields(adjusted)
                return CalculatorUiState(
                    baseShutterLabel = baseLabel, ndStops = ndStops, filmName = null, authorityLabel = null,
                    adjustedShutterLabel = adjustedLabel, correctedExposureLabel = null, reciprocityBadge = null,
                    canStartTimer = adjusted.isFinite() && adjusted > 0, startDisabledHint = null, availableModels = emptyList(),
                    targetSeconds = tf.seconds, targetStopDifference = tf.stop, targetIsMatch = tf.match,
                    targetUnavailable = tf.unavailable, targetSummary = tf.summary,
                )
            }

        val profile = activeProfile(film)
        val result = policy.evaluate(profile, adjusted)
        val presentation = ReciprocityConfidencePresentationMapper.map(result)
        val quantified = result as? ReciprocityResult.Quantified
        val correctedLabel = quantified?.let { calculator.formatExtendedClock(it.corrected) }
        val canStart = quantified != null
        val hint = if (canStart) null else "No quantified correction for this exposure — corrected timer unavailable."

        val alternates = AlternateReciprocityModels.alternates(film.id)
        val models = if (alternates.isEmpty()) emptyList() else buildList {
            add(ModelOptionUi(film.profiles.first().id, film.profiles.first().selectorLabel ?: film.profiles.first().name, selectedProfileId == null))
            alternates.forEach { add(ModelOptionUi(it.id, it.selectorLabel ?: it.name, selectedProfileId == it.id)) }
        }

        val tableRule = (profile.typedRules.firstOrNull() as? com.sangwook.ptimer.core.catalog.ReciprocityRule.Table)?.rule
        val isCustomTable = film.kind == "custom" && tableRule != null
        val fittedSummary = if (isCustomTable && tableRule != null) {
            when (val preview = com.sangwook.ptimer.customfilm.FittedFormulaPreviewPresenter.preview(tableRule)) {
                is com.sangwook.ptimer.customfilm.FittedPreview.Available ->
                    "Fitted (inspection-only): ${preview.parameterText} · ${preview.quality}"
                is com.sangwook.ptimer.customfilm.FittedPreview.Unavailable -> preview.reason
            }
        } else {
            null
        }

        val tf = targetFields(quantified?.corrected)

        return CalculatorUiState(
            baseShutterLabel = baseLabel, ndStops = ndStops, filmName = film.canonicalStockName,
            authorityLabel = authorityLabel(profile), adjustedShutterLabel = adjustedLabel,
            correctedExposureLabel = correctedLabel, reciprocityBadge = presentation.shortLabel,
            canStartTimer = canStart, startDisabledHint = hint, availableModels = models,
            isCustomTable = isCustomTable, fittedPreviewSummary = fittedSummary,
            selectedCustomFilmId = if (film.kind == "custom") film.id else null,
            targetSeconds = tf.seconds, targetStopDifference = tf.stop, targetIsMatch = tf.match,
            targetUnavailable = tf.unavailable, targetSummary = tf.summary,
        )
    }

    private data class TargetFields(
        val seconds: Double?, val stop: Double?, val match: Boolean, val unavailable: Boolean, val summary: String?,
    )

    private fun targetFields(comparisonValue: Double?): TargetFields {
        val t = targetSeconds ?: return TargetFields(null, null, false, false, null)
        val cmp = TargetShutterPresenter.compare(t, comparisonValue)
        val label = calculator.formatShutter(t)
        val summary = when {
            cmp.isUnavailable -> "Target $label · comparison unavailable"
            cmp.isMatch -> "Target $label · matches"
            else -> "Target $label · ${String.format(Locale.ROOT, "%+.1f", cmp.stopDifference)} stops"
        }
        return TargetFields(t, cmp.stopDifference, cmp.isMatch, cmp.isUnavailable, summary)
    }

    private fun authorityLabel(profile: ReciprocityProfile): String = when (profile.source.authority) {
        "official" -> "Official guidance"
        "unofficial" -> "Unofficial practical"
        "userDefined" -> "Custom"
        else -> "Reciprocity"
    }
}
