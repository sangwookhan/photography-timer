package com.sangwook.ptimer.core.exposure

import java.util.Locale
import kotlin.math.abs
import kotlin.math.ceil
import kotlin.math.floor
import kotlin.math.log2
import kotlin.math.pow
import kotlin.math.roundToInt
import kotlin.math.roundToLong

/** ND-adjusted shutter result. Mirrors iOS `ExposureCalculationResult`. */
data class ExposureCalculationResult(
    val baseShutterSeconds: Double,
    val ndStep: NdStep,
    val resultShutterSeconds: Double,
) {
    constructor(baseShutterSeconds: Double, stop: Int, resultShutterSeconds: Double) :
        this(baseShutterSeconds, NdStep(stop.toDouble()), resultShutterSeconds)

    /** Whole-stop view of the ND input (rounded for fractional). */
    val stop: Int get() = ndStep.wholeStops ?: ndStep.stops.roundToInt()
}

/** Primary/secondary duration display pair. Mirrors iOS `TimeDisplay`. */
data class TimeDisplay(val primary: String, val secondary: String)

/**
 * Pure ND exposure math, base-shutter parsing, snap-to-full-stop, and
 * locale-independent shutter/duration formatting. Protected behavior —
 * exact parity with iOS `ExposureCalculator`.
 */
class ExposureCalculator {

    companion object {
        const val STABILITY_EPSILON: Double = 0.000_001

        val FULL_STOP_SHUTTER_SPEEDS: List<Double> = listOf(
            1.0 / 8000, 1.0 / 4000, 1.0 / 2000, 1.0 / 1000,
            1.0 / 500, 1.0 / 250, 1.0 / 125, 1.0 / 60,
            1.0 / 30, 1.0 / 15, 1.0 / 8, 1.0 / 4,
            1.0 / 2, 1.0, 2.0, 4.0, 8.0, 15.0, 30.0,
        )

        private val TRAILING_ZEROS = Regex("(\\.\\d*?[1-9])0+$|\\.0+$")
    }

    fun parseBaseShutter(input: String): Double {
        val trimmed = normalize(input)
        if (trimmed.isEmpty()) throw ExposureCalcException(ExposureCalcError.EMPTY_BASE_SHUTTER)

        if (trimmed.contains("/")) {
            val parts = trimmed.split("/").filter { it.isNotEmpty() }
            if (parts.size != 2) throw ExposureCalcException(ExposureCalcError.INVALID_BASE_SHUTTER)
            val numerator = parts[0].toDoubleOrNull()
            val denominator = parts[1].toDoubleOrNull()
            if (numerator == null || denominator == null) {
                throw ExposureCalcException(ExposureCalcError.INVALID_BASE_SHUTTER)
            }
            if (numerator <= 0 || denominator <= 0) {
                throw ExposureCalcException(ExposureCalcError.NON_POSITIVE_BASE_SHUTTER)
            }
            return numerator / denominator
        }

        val seconds = trimmed.toDoubleOrNull()
            ?: throw ExposureCalcException(ExposureCalcError.INVALID_BASE_SHUTTER)
        if (seconds <= 0) throw ExposureCalcException(ExposureCalcError.NON_POSITIVE_BASE_SHUTTER)
        return seconds
    }

    fun calculate(baseShutterSeconds: Double, stop: Int): Double =
        calculate(baseShutterSeconds, NdStep(stop.toDouble()), ExposureScaleMode.FULL_STOP)

    fun calculate(baseShutterSeconds: Double, ndStep: NdStep): Double =
        calculate(baseShutterSeconds, ndStep, ExposureScaleMode.FULL_STOP)

    /**
     * ND-adjusted shutter for a fractional-aware ND input in [scaleMode].
     * Snap-to-full-stop applies only in [ExposureScaleMode.FULL_STOP] with
     * a whole-stop ND; in one-third-stop mode the raw value is returned.
     */
    fun calculate(baseShutterSeconds: Double, ndStep: NdStep, scaleMode: ExposureScaleMode): Double {
        if (baseShutterSeconds <= 0) {
            throw ExposureCalcException(ExposureCalcError.NON_POSITIVE_BASE_SHUTTER)
        }
        if (ndStep.stops < -STABILITY_EPSILON) {
            throw ExposureCalcException(ExposureCalcError.NON_POSITIVE_ND)
        }
        val result = baseShutterSeconds * 2.0.pow(ndStep.stops)
        if (!result.isFinite()) throw ExposureCalcException(ExposureCalcError.OVERFLOW)

        val snapAllowed = scaleMode == ExposureScaleMode.FULL_STOP && ndStep.isWholeStop
        return if (snapAllowed) snapToFullStop(result) else result
    }

    fun formatShutter(seconds: Double): String {
        if (!seconds.isFinite() || seconds <= 0) return "-"
        return formatRawSeconds(seconds)
    }

    fun formatTimeDisplay(seconds: Double): TimeDisplay {
        val safe = normalizeDuration(seconds)
        return TimeDisplay(formatExtendedClock(safe), formatRawDurationSeconds(safe))
    }

    fun formatExtendedClock(seconds: Double): String {
        val safe = normalizeDuration(seconds)

        if (safe < 1) return "${trimmedMilliseconds(safe)}s"
        if (safe < 60) return shortSecondsText(safe)

        val secondsPerMinute = 60
        val secondsPerHour = 60 * secondsPerMinute
        val secondsPerDay = 24 * secondsPerHour
        val secondsPerMonth = 30 * secondsPerDay
        val secondsPerYear = 365 * secondsPerDay

        val years = (safe / secondsPerYear).toInt()
        var remainder = safe - years.toDouble() * secondsPerYear
        val months = (remainder / secondsPerMonth).toInt()
        remainder -= months.toDouble() * secondsPerMonth
        val days = (remainder / secondsPerDay).toInt()
        remainder -= days.toDouble() * secondsPerDay
        val hours = (remainder / secondsPerHour).toInt()
        remainder -= hours.toDouble() * secondsPerHour
        val minutes = (remainder / secondsPerMinute).toInt()
        remainder -= minutes.toDouble() * secondsPerMinute
        val secondText = formattedClockSeconds(remainder)

        if (years > 0) {
            return formatDatePrefix(years, months, days,
                String.format(Locale.ROOT, "%02d:%02d:%s", hours, minutes, secondText))
        }
        if (months > 0) {
            return formatDatePrefix(0, months, days,
                String.format(Locale.ROOT, "%02d:%02d:%s", hours, minutes, secondText))
        }
        if (days > 0) {
            return formatDatePrefix(0, 0, days,
                String.format(Locale.ROOT, "%02d:%02d:%s", hours, minutes, secondText))
        }
        if (safe >= secondsPerHour.toDouble()) {
            val totalHours = (safe / secondsPerHour).toInt()
            return String.format(Locale.ROOT, "%02d:%02d:%s", totalHours, minutes, secondText)
        }
        if (safe >= secondsPerMinute.toDouble()) {
            return String.format(Locale.ROOT, "%02d:%s", minutes, secondText)
        }
        return "00:$secondText"
    }

    /** Inverse search: lowest stop whose snapped result is closest. */
    fun reconstructedStop(baseShutterSeconds: Double, resultShutterSeconds: Double, maxStop: Int = 64): Int? {
        if (!baseShutterSeconds.isFinite() || !resultShutterSeconds.isFinite() ||
            baseShutterSeconds <= 0 || resultShutterSeconds <= 0 || maxStop < 0
        ) return null

        var bestStop: Int? = null
        var bestDistance = Double.POSITIVE_INFINITY
        for (stop in 0..maxStop) {
            val candidate = try {
                calculate(baseShutterSeconds, stop)
            } catch (_: ExposureCalcException) {
                continue
            }
            val distance = abs(candidate - resultShutterSeconds)
            if (distance < bestDistance - STABILITY_EPSILON) {
                bestDistance = distance
                bestStop = stop
            } else if (abs(distance - bestDistance) <= STABILITY_EPSILON) {
                val currentBest = bestStop
                if (currentBest != null && stop < currentBest) bestStop = stop
            }
        }
        return bestStop
    }

    // MARK: - private

    private fun formatRawSeconds(seconds: Double): String {
        if (!seconds.isFinite() || seconds <= 0) return "-"
        if (seconds >= 1) {
            if (abs(seconds.roundToLong().toDouble() - seconds) < 0.0001) {
                return "${seconds.roundToLong()}s"
            }
            return String.format(Locale.ROOT, "%.1fs", seconds)
        }
        val reciprocal = 1 / seconds
        if (abs(reciprocal.roundToLong().toDouble() - reciprocal) < 0.05) {
            return "1/${reciprocal.roundToLong()}s"
        }
        return String.format(Locale.ROOT, "%.3fs", seconds)
    }

    private fun formatRawDurationSeconds(seconds: Double): String {
        val normalized = normalizeDuration(seconds)
        return if (isEffectivelyInteger(normalized)) {
            "${normalized.roundToLong()}s"
        } else {
            "${trimmedMilliseconds(normalized)}s"
        }
    }

    private fun normalizeDuration(seconds: Double): Double {
        if (!seconds.isFinite()) return 0.0
        val clamped = maxOf(0.0, seconds)
        return if (clamped < STABILITY_EPSILON) 0.0 else clamped
    }

    private fun formattedClockSeconds(seconds: Double): String {
        if (abs(seconds.roundToLong().toDouble() - seconds) < 0.0001) {
            return String.format(Locale.ROOT, "%02d", seconds.roundToLong())
        }
        val whole = seconds.toLong()
        val milliseconds = ((seconds - whole.toDouble()) * 1_000).roundToInt()
        if (milliseconds == 1_000) {
            return String.format(Locale.ROOT, "%02d", whole + 1)
        }
        return String.format(Locale.ROOT, "%02d.%03d", whole, milliseconds)
    }

    private fun trimmedMilliseconds(seconds: Double): String {
        val raw = String.format(Locale.ROOT, "%.3f", (seconds * 1_000).roundToLong() / 1_000.0)
        return TRAILING_ZEROS.replace(raw) { it.groupValues[1] }
    }

    private fun shortSecondsText(seconds: Double): String {
        return if (isEffectivelyInteger(seconds)) {
            "${seconds.roundToLong()}s"
        } else {
            "${trimmedMilliseconds(seconds)}s"
        }
    }

    private fun formatDatePrefix(years: Int, months: Int, days: Int, timeText: String): String {
        val parts = ArrayList<String>()
        if (years > 0) parts.add("${years}y")
        if (months > 0) parts.add("${months}mo")
        if (days > 0) parts.add("${days}d")
        val prefix = parts.joinToString(" ")
        return if (prefix.isEmpty()) timeText else "$prefix $timeText"
    }

    private fun normalize(input: String): String =
        input.trim().lowercase()
            .replace("seconds", "")
            .replace("second", "")
            .replace("sec", "")
            .replace("s", "")
            .replace(" ", "")

    private fun snapToFullStop(value: Double): Double {
        val normalized = normalizeDuration(value)
        if (normalized <= 0) return normalized

        if (normalized <= 30 + STABILITY_EPSILON) {
            return FULL_STOP_SHUTTER_SPEEDS.minByOrNull { abs(it - normalized) } ?: normalized
        }
        if (normalized < 64 - STABILITY_EPSILON) {
            return if (abs(normalized - 30) <= abs(64 - normalized)) 30.0 else 64.0
        }
        val lower = 2.0.pow(floor(log2(normalized)))
        val upper = 2.0.pow(ceil(log2(normalized)))
        return if (abs(normalized - lower) <= abs(upper - normalized)) lower else upper
    }

    private fun isEffectivelyInteger(value: Double): Boolean =
        abs(value.roundToLong().toDouble() - value) < STABILITY_EPSILON
}
