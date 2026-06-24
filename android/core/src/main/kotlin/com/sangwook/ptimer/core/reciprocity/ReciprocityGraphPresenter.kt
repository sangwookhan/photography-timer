package com.sangwook.ptimer.core.reciprocity

import kotlin.math.log10
import kotlin.math.pow

/** A point in the graph's normalized [0,1]×[0,1] space (origin bottom-left). */
data class GraphPoint(val x: Double, val y: Double)

/** An axis tick: normalized position [0,1] along the axis + its compact label. */
data class GraphTick(val position: Double, val label: String)

/**
 * Normalized geometry for the reciprocity curve graph (log-log). The domain is
 * fixed to the profile's own range (no-correction knee … beyond the source
 * range) and does NOT depend on the current input, so the axes stay put as the
 * exposure changes. The current-result marker carries [currentOutOfRange] so the
 * view can draw a border triangle when it falls outside the fixed plot.
 * (iOS: FilmModeDetailsGraphPresenter, normalized subset.)
 */
data class ReciprocityGraph(
    val curve: List<GraphPoint>,
    val anchors: List<GraphPoint>,
    /** Published source-evidence reference points plotted on the curve (iOS green markers). */
    val referenceMarkers: List<GraphPoint> = emptyList(),
    /** Clamped to [0,1] for drawing; see [currentOutOfRange] for the triangle. */
    val current: GraphPoint?,
    val currentOutOfRange: Boolean,
    val noCorrectionFraction: Double?,
    val sourceRangeFraction: Double?,
    /** Normalized x of a not-recommended manufacturer boundary (iOS vertical marker). */
    val notRecommendedBoundaryFraction: Double? = null,
    val xTicks: List<GraphTick>,
    val yTicks: List<GraphTick>,
)

object ReciprocityGraphPresenter {
    private const val SAMPLES = 48

    fun make(profile: ReciprocityProfile, adjustedShutterSeconds: Double): ReciprocityGraph? {
        val formula = profile.rules.firstNotNullOfOrNull { it.formula }?.formula
        val table = profile.rules.firstNotNullOfOrNull { it.tableInterpolation }
        if (formula == null && table == null) return null

        val corrected: (Double) -> Double? = { tm -> correctedAt(formula, table, tm) }

        val anchorTms = table?.sortedAnchors?.map { it.meteredSeconds } ?: emptyList()
        val noCorrection = formula?.noCorrectionThroughSeconds ?: table!!.noCorrectionThroughSeconds
        val sourceRange = formula?.sourceRangeThroughSeconds ?: table?.sourceRangeThroughSeconds

        // Fixed domain from the profile alone (NOT the current input). Floor at
        // 0.1s; extend a decade past the source range / last anchor to leave room
        // for the beyond-range band. An unlimited formula has no published top,
        // so cap the preview window at ~1h instead of running to 100h (which made
        // a steep p blow the Y axis out to days).
        val rangeTop = sourceRange ?: anchorTms.maxOrNull()?.times(10) ?: 3600.0
        val domainMinSec = minOf(0.1, noCorrection.takeIf { it > 0 } ?: 0.1)
        val domainMaxSec = maxOf(rangeTop * if (sourceRange != null) 10.0 else 1.0, 3600.0)
        val xMin = log10(domainMinSec)
        val xMax = log10(domainMaxSec)
        if (!(xMax > xMin)) return null

        val samples = (0..SAMPLES).mapNotNull { i ->
            val x = xMin + (xMax - xMin) * i / SAMPLES
            val tm = 10.0.pow(x)
            corrected(tm)?.takeIf { it.isFinite() && it > 0 }?.let { tm to it }
        }
        if (samples.size < 2) return null

        val ys = samples.map { log10(it.second) }
        val yMin = ys.min()
        // Cap the Y axis at 1 day so an extreme p doesn't blow the scale out to
        // multi-day ticks (the steep tail just runs off the top, which reads as
        // "off the chart"). Real films stay well under this in their domain.
        val yMax = minOf(ys.max(), log10(86_400.0)).coerceAtLeast(yMin + 1e-9)
        val ySpan = (yMax - yMin).takeIf { it > 1e-9 } ?: 1.0
        val rawX: (Double) -> Double = { (log10(it) - xMin) / (xMax - xMin) }
        val rawY: (Double) -> Double = { (log10(it) - yMin) / ySpan }
        val cx: (Double) -> Double = { rawX(it).coerceIn(0.0, 1.0) }
        val cy: (Double) -> Double = { rawY(it).coerceIn(0.0, 1.0) }

        val currentTc = adjustedShutterSeconds.takeIf { it.isFinite() && it > 0 }?.let { corrected(it) }
        val current = if (adjustedShutterSeconds.isFinite() && adjustedShutterSeconds > 0 && currentTc != null && currentTc > 0) {
            GraphPoint(cx(adjustedShutterSeconds), cy(currentTc))
        } else {
            null
        }
        val outOfRange = current != null && run {
            val rx = rawX(adjustedShutterSeconds)
            val ry = rawY(currentTc!!)
            rx < 0.0 || rx > 1.0 || ry < 0.0 || ry > 1.0
        }

        // Source-evidence reference points plotted on the curve (iOS green
        // markers): each published reference row at corrected(metered). Formula
        // profiles (e.g. Velvia) carry these even with no table anchors, so the
        // "Source reference" chip + dots appear like iOS. The guidance-boundary
        // row (not-recommended) becomes a vertical marker instead.
        val referenceMarkers = profile.sourceEvidence
            .filterNot { ReciprocitySourceEvidenceClassifier.isGuidanceBoundary(it) }
            .mapNotNull { row ->
                val tm = ReciprocitySourceEvidenceClassifier.meteredSeconds(row.meteredExposure) ?: return@mapNotNull null
                val tc = corrected(tm)?.takeIf { it.isFinite() && it > 0 } ?: return@mapNotNull null
                GraphPoint(cx(tm), cy(tc))
            }
        val notRecommendedBoundaryFraction = profile.sourceEvidence
            .firstOrNull { ReciprocitySourceEvidenceClassifier.isGuidanceBoundary(it) }
            ?.let { ReciprocitySourceEvidenceClassifier.meteredSeconds(it.meteredExposure) }
            ?.let { cx(it) }

        return ReciprocityGraph(
            curve = samples.map { GraphPoint(cx(it.first), cy(it.second)) },
            anchors = table?.sortedAnchors?.map { GraphPoint(cx(it.meteredSeconds), cy(it.correctedSeconds)) } ?: emptyList(),
            referenceMarkers = referenceMarkers,
            current = current,
            currentOutOfRange = outOfRange,
            noCorrectionFraction = noCorrection.takeIf { it > 0 }?.let { cx(it) },
            sourceRangeFraction = sourceRange?.let { cx(it) },
            notRecommendedBoundaryFraction = notRecommendedBoundaryFraction,
            // Round-duration ticks (1/10s, 1s, 10s, 1m, 10m, 1h, 10h, 100h) with
            // iOS-style labels, filtered to the plotted domain — so labels read
            // "1m / 1h" instead of decade values like "2m / 17m / 3h".
            xTicks = niceTicks(domainMinSec, domainMaxSec, xMin, xMax - xMin),
            yTicks = niceTicks(10.0.pow(yMin), 10.0.pow(yMin + ySpan), yMin, ySpan),
        )
    }

    private fun correctedAt(
        formula: ReciprocityFormula?,
        table: TableInterpolationReciprocityRule?,
        tm: Double,
    ): Double? {
        if (formula != null) {
            return when (val r = formula.evaluate(tm)) {
                is FormulaEvaluationResult.WithinSourceRange -> r.correctedExposureSeconds
                is FormulaEvaluationResult.BeyondSourceRange -> r.correctedExposureSeconds
                FormulaEvaluationResult.NoCorrection -> tm
                else -> null
            }
        }
        if (table != null) {
            return when (val r = table.evaluate(tm)) {
                is TableEvaluationResult.WithinSourceRange -> r.correctedExposureSeconds
                is TableEvaluationResult.BeyondSourceRange -> r.correctedExposureSeconds
                TableEvaluationResult.NoCorrection -> tm
                else -> null
            }
        }
        return null
    }

    /**
     * Round-duration axis ticks with iOS-style labels (mirrors the durations iOS
     * uses across its graph scale tiers). Only the values that fall within the
     * plotted [minSec, maxSec] domain are kept; positions are normalized in log
     * space. This keeps labels clean ("1m", "1h") rather than the decade values
     * (100s -> "2m", 1000s -> "17m") the old log-decade ticks produced.
     */
    private val NICE_TICKS: List<Pair<Double, String>> = listOf(
        0.1 to "1/10s",
        1.0 to "1s",
        10.0 to "10s",
        60.0 to "1m",
        600.0 to "10m",
        3600.0 to "1h",
        36_000.0 to "10h",
        360_000.0 to "100h",
    )

    private fun niceTicks(minSec: Double, maxSec: Double, logMin: Double, logSpan: Double): List<GraphTick> {
        if (logSpan <= 0.0) return emptyList()
        return NICE_TICKS
            .filter { it.first >= minSec * (1 - 1e-6) && it.first <= maxSec * (1 + 1e-6) }
            .map { GraphTick((log10(it.first) - logMin) / logSpan, it.second) }
    }
}
