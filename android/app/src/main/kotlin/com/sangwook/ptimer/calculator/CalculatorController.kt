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
import com.sangwook.ptimer.core.timer.ExposureTimerSource
import com.sangwook.ptimer.target.TargetShutterPresenter
import java.util.Locale

data class ModelOptionUi(val profileId: String, val label: String, val isSelected: Boolean)

/**
 * A single, source-specific start action. Each result row owns one, so the UI
 * can never present an ambiguous generic "Start timer". `filmContext` becomes
 * the timer title's film/digital/target part; `subtitle` is the source line.
 */
data class StartActionState(
    val enabled: Boolean,
    val durationSeconds: Double?,
    val disabledReason: String?,
    val source: ExposureTimerSource,
    val filmContext: String,
    val subtitle: String,
    val selectedModelLabel: String?,
)

/** Immutable calculator/film result state. */
data class CalculatorUiState(
    val baseShutterLabel: String,
    val ndStops: Int,
    val filmName: String?,
    val authorityLabel: String?,
    val adjustedShutterLabel: String,
    val correctedExposureLabel: String?,
    val reciprocityBadge: String?,
    val adjustedAction: StartActionState,
    val correctedAction: StartActionState?,
    val targetAction: StartActionState?,
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
        // A corrupt/non-finite persisted base falls back to the default shutter.
        baseShutterSeconds = snapshot.baseShutterSeconds.takeIf { it.isFinite() && it > 0 }
            ?: CalculatorDefaults.BASE_SHUTTER_SECONDS
        ndStops = snapshot.ndStops.coerceIn(0, ExposureScale.MAX_WHOLE_ND_STOPS)
        selectedFilmId = snapshot.selectedFilmId
        selectedProfileId = snapshot.selectedProfileId
        sanitizeFilmSelection()
        // Sanitize a persisted/corrupt target the same way setTarget does.
        targetSeconds = snapshot.targetShutterSeconds?.takeIf { it.isFinite() && it > 0 }
    }

    /**
     * Drop a restored film/profile selection that no longer resolves, so a
     * stale id can never leak into the UI or be recaptured into a later
     * snapshot. An unknown film id clears both; a profile id that is the
     * primary profile (or does not resolve to a known alternate of the
     * selected film) is normalized to the primary-profile convention (null).
     */
    private fun sanitizeFilmSelection() {
        val film = film()
        if (film == null) {
            selectedFilmId = null
            selectedProfileId = null
            return
        }
        val pid = selectedProfileId ?: return
        // Primary profile is represented by null; never keep its explicit id.
        if (pid == film.profiles.first().id) {
            selectedProfileId = null
            return
        }
        // Keep only a profile id that is a known alternate of THIS film.
        if (AlternateReciprocityModels.alternates(film.id).none { it.id == pid }) {
            selectedProfileId = null
        }
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

    /** Start action for the adjusted shutter (always present; enabled when finite>0). */
    fun adjustedAction(): StartActionState {
        val adjusted = adjustedShutterSeconds()
        val film = film()
        val enabled = adjusted.isFinite() && adjusted > 0
        val source = if (film != null) ExposureTimerSource.FILM_ADJUSTED_SHUTTER else ExposureTimerSource.DIGITAL_RESULT
        val limited = film != null &&
            policy.evaluate(activeProfile(film), adjusted) !is ReciprocityResult.Quantified
        val subtitle = buildString {
            append("Adjusted Shutter")
            if (limited) append(" · Limited guidance")
            append(" · ${calculator.formatShutter(adjusted)}")
        }
        return StartActionState(
            enabled = enabled,
            durationSeconds = if (enabled) adjusted else null,
            disabledReason = if (enabled) null else "Adjusted shutter is not a valid duration.",
            source = source,
            filmContext = film?.canonicalStockName ?: "Digital",
            subtitle = subtitle,
            selectedModelLabel = null,
        )
    }

    /** Start action for the corrected exposure; null when no film, disabled when non-quantified. */
    fun correctedAction(): StartActionState? {
        val film = film() ?: return null
        val profile = activeProfile(film)
        val adjusted = adjustedShutterSeconds()
        val quantified = policy.evaluate(profile, adjusted) as? ReciprocityResult.Quantified
        val corrected = quantified?.corrected
        val enabled = corrected != null && corrected.isFinite() && corrected > 0
        val modelLabel = profile.selectorLabel ?: profile.name
        val subtitle = if (enabled) {
            "Corrected Exposure · $modelLabel · ${calculator.formatExtendedClock(corrected!!)}"
        } else {
            "Corrected Exposure · unavailable"
        }
        return StartActionState(
            enabled = enabled,
            durationSeconds = corrected,
            disabledReason = if (enabled) null else "No quantified correction for this exposure.",
            source = ExposureTimerSource.FILM_CORRECTED_EXPOSURE,
            filmContext = film.canonicalStockName,
            subtitle = subtitle,
            selectedModelLabel = modelLabel,
        )
    }

    /** Start action for the target shutter; null unless a valid target is set. */
    fun targetAction(): StartActionState? {
        val t = targetSeconds ?: return null
        val film = film()
        val comparison = if (film != null) {
            (policy.evaluate(activeProfile(film), adjustedShutterSeconds()) as? ReciprocityResult.Quantified)?.corrected
        } else {
            adjustedShutterSeconds()
        }
        val cmp = TargetShutterPresenter.compare(t, comparison)
        val stopPart = when {
            cmp.isUnavailable -> ""
            cmp.isMatch -> " · matches"
            else -> " · ${String.format(Locale.ROOT, "%+.1f", cmp.stopDifference)} stops"
        }
        return StartActionState(
            enabled = true,
            durationSeconds = t,
            disabledReason = null,
            source = ExposureTimerSource.TARGET_SHUTTER,
            filmContext = "Target Shutter",
            subtitle = "Target · ${calculator.formatExtendedClock(t)}$stopPart",
            selectedModelLabel = null,
        )
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
                    adjustedAction = adjustedAction(), correctedAction = null, targetAction = targetAction(),
                    availableModels = emptyList(),
                    targetSeconds = tf.seconds, targetStopDifference = tf.stop, targetIsMatch = tf.match,
                    targetUnavailable = tf.unavailable, targetSummary = tf.summary,
                )
            }

        val profile = activeProfile(film)
        val result = policy.evaluate(profile, adjusted)
        val presentation = ReciprocityConfidencePresentationMapper.map(result)
        val quantified = result as? ReciprocityResult.Quantified
        val correctedLabel = quantified?.let { calculator.formatExtendedClock(it.corrected) }

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
            adjustedAction = adjustedAction(), correctedAction = correctedAction(), targetAction = targetAction(),
            availableModels = models,
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
