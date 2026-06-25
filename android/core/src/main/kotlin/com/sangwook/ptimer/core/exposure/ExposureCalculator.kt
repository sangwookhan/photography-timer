package com.sangwook.ptimer.core.exposure

import java.util.Locale
import kotlin.math.abs
import kotlin.math.ceil
import kotlin.math.floor
import kotlin.math.log2
import kotlin.math.max
import kotlin.math.pow

/**
 * Result of an exposure calculation. `stop` is the whole-stop view of the ND
 * input. Port of iOS `ExposureCalculationResult` (PTimerCore).
 */
data class ExposureCalculationResult(
    val baseShutterSeconds: Double,
    val ndStep: NDStep,
    val resultShutterSeconds: Double,
) {
    constructor(baseShutterSeconds: Double, stop: Int, resultShutterSeconds: Double) :
        this(baseShutterSeconds, NDStep(stop.toDouble()), resultShutterSeconds)

    val stop: Int
        get() = ndStep.wholeStops ?: ndStep.stops.swiftRounded().toInt()
}

/** Two-line duration display: an extended clock string plus a raw-seconds string. */
data class TimeDisplay(val primary: String, val secondary: String)

/**
 * Calculation/parse errors. `key` is the stable identifier shared with the
 * cross-platform golden fixture (`exposure-golden.json`).
 */
enum class ExposureCalculatorError(val key: String, val message: String) {
    EMPTY_BASE_SHUTTER("emptyBaseShutter", "Base shutter is required."),
    INVALID_BASE_SHUTTER("invalidBaseShutter", "Enter shutter like 1/30, 0.5, or 2s."),
    NON_POSITIVE_BASE_SHUTTER("nonPositiveBaseShutter", "Base shutter must be greater than 0."),
    NON_POSITIVE_ND("nonPositiveND", "ND stop must be 0 or greater."),
    OVERFLOW("overflow", "Calculated shutter is too large to display."),
}

class ExposureCalculatorException(val error: ExposureCalculatorError) : Exception(error.message)

/**
 * Exposure / ND-shutter calculator. Faithful port of iOS PTimerCore
 * `ExposureCalculator` (PROTECTED AREA — exact parity with `calculate`,
 * snap-to-full-stop, `stabilityEpsilon`, and the formatters; validated
 * against `shared/test-fixtures/exposure-golden.json`).
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
    }

    fun parseBaseShutter(input: String): Double {
        val trimmed = normalize(input)
        if (trimmed.isEmpty()) throw ExposureCalculatorException(ExposureCalculatorError.EMPTY_BASE_SHUTTER)

        if (trimmed.contains("/")) {
            val parts = trimmed.split("/").filter { it.isNotEmpty() }
            val numerator = parts.getOrNull(0)?.toDoubleOrNull()
            val denominator = parts.getOrNull(1)?.toDoubleOrNull()
            if (parts.size != 2 || numerator == null || denominator == null) {
                throw ExposureCalculatorException(ExposureCalculatorError.INVALID_BASE_SHUTTER)
            }
            if (numerator <= 0 || denominator <= 0) {
                throw ExposureCalculatorException(ExposureCalculatorError.NON_POSITIVE_BASE_SHUTTER)
            }
            return numerator / denominator
        }

        val seconds = trimmed.toDoubleOrNull()
            ?: throw ExposureCalculatorException(ExposureCalculatorError.INVALID_BASE_SHUTTER)
        if (seconds <= 0) {
            throw ExposureCalculatorException(ExposureCalculatorError.NON_POSITIVE_BASE_SHUTTER)
        }
        return seconds
    }

    /** Whole-stop convenience overload (legacy snap-to-full-stop behavior). */
    fun calculate(baseShutterSeconds: Double, stop: Int): Double =
        calculate(baseShutterSeconds, NDStep(stop.toDouble()), ExposureScaleMode.FULL_STOP)

    /**
     * Computes the ND-adjusted shutter. Snap-to-full-stop applies only in
     * [ExposureScaleMode.FULL_STOP] with a whole-stop ND; otherwise the result
     * is returned untouched so a 1/3-stop value survives.
     */
    fun calculate(
        baseShutterSeconds: Double,
        ndStep: NDStep,
        scaleMode: ExposureScaleMode = ExposureScaleMode.FULL_STOP,
    ): Double {
        if (baseShutterSeconds <= 0) {
            throw ExposureCalculatorException(ExposureCalculatorError.NON_POSITIVE_BASE_SHUTTER)
        }
        if (ndStep.stops < -STABILITY_EPSILON) {
            throw ExposureCalculatorException(ExposureCalculatorError.NON_POSITIVE_ND)
        }

        val result = baseShutterSeconds * 2.0.pow(ndStep.stops)
        if (!result.isFinite()) {
            throw ExposureCalculatorException(ExposureCalculatorError.OVERFLOW)
        }

        val snapAllowed = scaleMode == ExposureScaleMode.FULL_STOP && ndStep.isWholeStop
        return if (snapAllowed) snapToFullStop(result) else result
    }

    fun formatShutter(seconds: Double): String {
        if (!seconds.isFinite() || seconds <= 0) return "-"
        return formatRawSeconds(seconds)
    }

    fun formatTimeDisplay(seconds: Double): TimeDisplay {
        val safeSeconds = normalizeDuration(seconds)
        return TimeDisplay(
            primary = formatExtendedClock(safeSeconds),
            secondary = formatRawDurationSeconds(safeSeconds),
        )
    }

    fun formatExtendedClock(seconds: Double): String {
        val safeSeconds = normalizeDuration(seconds)

        if (safeSeconds < 1) return "${trimmedMilliseconds(safeSeconds)}s"
        if (safeSeconds < 60) return shortSecondsText(safeSeconds)

        val secondsPerMinute = 60L
        val secondsPerHour = 60 * secondsPerMinute
        val secondsPerDay = 24 * secondsPerHour
        val secondsPerMonth = 30 * secondsPerDay
        val secondsPerYear = 365 * secondsPerDay

        val years = (safeSeconds / secondsPerYear).toLong()
        var remainder = safeSeconds - years * secondsPerYear
        val months = (remainder / secondsPerMonth).toLong()
        remainder -= months * secondsPerMonth
        val days = (remainder / secondsPerDay).toLong()
        remainder -= days * secondsPerDay
        val hours = (remainder / secondsPerHour).toLong()
        remainder -= hours * secondsPerHour
        val minutes = (remainder / secondsPerMinute).toLong()
        remainder -= minutes * secondsPerMinute
        val secondText = formattedClockSeconds(remainder)

        if (years > 0) {
            return formatDatePrefix(years, months, days, String.format(Locale.ROOT, "%02d:%02d:%s", hours, minutes, secondText))
        }
        if (months > 0) {
            return formatDatePrefix(0, months, days, String.format(Locale.ROOT, "%02d:%02d:%s", hours, minutes, secondText))
        }
        if (days > 0) {
            return formatDatePrefix(0, 0, days, String.format(Locale.ROOT, "%02d:%02d:%s", hours, minutes, secondText))
        }
        if (safeSeconds >= secondsPerHour) {
            val totalHours = (safeSeconds / secondsPerHour).toLong()
            return String.format(Locale.ROOT, "%02d:%02d:%s", totalHours, minutes, secondText)
        }
        if (safeSeconds >= secondsPerMinute) {
            return String.format(Locale.ROOT, "%02d:%s", minutes, secondText)
        }
        return "00:$secondText"
    }

    /**
     * Compact, single-glance duration for result cards (iOS coarse style):
     * the largest one or two units — "10d", "9h 42m", "3m 20s" — so long
     * exposures stay on one line. Sub-minute values reuse [formatExtendedClock].
     */
    fun formatCoarse(seconds: Double): String {
        val safeSeconds = normalizeDuration(seconds)
        if (safeSeconds < 60) return formatExtendedClock(safeSeconds)
        val secondsPerMinute = 60L
        val secondsPerHour = 60 * secondsPerMinute
        val secondsPerDay = 24 * secondsPerHour
        return when {
            safeSeconds >= secondsPerDay -> "${(safeSeconds / secondsPerDay).toLong()}d"
            safeSeconds >= secondsPerHour -> {
                val h = (safeSeconds / secondsPerHour).toLong()
                val m = ((safeSeconds % secondsPerHour) / secondsPerMinute).toLong()
                "${h}h ${m}m"
            }
            else -> {
                val m = (safeSeconds / secondsPerMinute).toLong()
                val s = (safeSeconds % secondsPerMinute).toLong()
                "${m}m ${s}s"
            }
        }
    }

    /**
     * Reconstructs the whole ND stop that maps [baseShutterSeconds] to
     * [resultShutterSeconds] under the snap model, preferring the smallest
     * stop on ties. Null when inputs are invalid.
     */
    fun reconstructedStop(
        baseShutterSeconds: Double,
        resultShutterSeconds: Double,
        maxStop: Int = 64,
    ): Int? {
        if (!baseShutterSeconds.isFinite() || !resultShutterSeconds.isFinite() ||
            baseShutterSeconds <= 0 || resultShutterSeconds <= 0 || maxStop < 0
        ) {
            return null
        }

        var bestStop: Int? = null
        var bestDistance = Double.POSITIVE_INFINITY

        for (stop in 0..maxStop) {
            val candidate = try {
                calculate(baseShutterSeconds, stop)
            } catch (_: ExposureCalculatorException) {
                continue
            }

            val distance = abs(candidate - resultShutterSeconds)
            if (distance < bestDistance - STABILITY_EPSILON) {
                bestDistance = distance
                bestStop = stop
            } else if (abs(distance - bestDistance) <= STABILITY_EPSILON &&
                bestStop != null && stop < bestStop!!
            ) {
                bestStop = stop
            }
        }

        return bestStop
    }

    // MARK: - Private formatting helpers (ported verbatim)

    private fun formatRawSeconds(seconds: Double): String {
        if (!seconds.isFinite() || seconds <= 0) return "-"

        if (seconds >= 1) {
            if (abs(seconds.swiftRounded() - seconds) < 0.0001) {
                return "${seconds.swiftRounded().toLong()}s"
            }
            return String.format(Locale.ROOT, "%.1fs", seconds)
        }

        val reciprocal = 1 / seconds
        if (abs(reciprocal.swiftRounded() - reciprocal) < 0.05) {
            return "1/${reciprocal.swiftRounded().toLong()}s"
        }
        return String.format(Locale.ROOT, "%.3fs", seconds)
    }

    private fun formatRawDurationSeconds(seconds: Double): String {
        val normalized = normalizeDuration(seconds)
        if (isEffectivelyInteger(normalized)) {
            return "${normalized.swiftRounded().toLong()}s"
        }
        return "${trimmedMilliseconds(normalized)}s"
    }

    private fun normalizeDuration(seconds: Double): Double {
        if (!seconds.isFinite()) return 0.0
        val clamped = max(0.0, seconds)
        return if (clamped < STABILITY_EPSILON) 0.0 else clamped
    }

    private fun formattedClockSeconds(seconds: Double): String {
        if (abs(seconds.swiftRounded() - seconds) < 0.0001) {
            return String.format(Locale.ROOT, "%02d", seconds.swiftRounded().toLong())
        }

        val wholeSeconds = seconds.toLong()
        val milliseconds = ((seconds - wholeSeconds) * 1_000).swiftRounded().toLong()

        if (milliseconds == 1_000L) {
            return String.format(Locale.ROOT, "%02d", wholeSeconds + 1)
        }
        return String.format(Locale.ROOT, "%02d.%03d", wholeSeconds, milliseconds)
    }

    private fun trimmedMilliseconds(seconds: Double): String {
        val raw = String.format(Locale.ROOT, "%.3f", (seconds * 1_000).swiftRounded() / 1_000)
        return raw.replace(Regex("(\\.\\d*?[1-9])0+$|\\.0+$"), "$1")
    }

    private fun shortSecondsText(seconds: Double): String {
        if (isEffectivelyInteger(seconds)) {
            return "${seconds.swiftRounded().toLong()}s"
        }
        return "${trimmedMilliseconds(seconds)}s"
    }

    private fun formatDatePrefix(years: Long, months: Long, days: Long, timeText: String): String {
        val prefixParts = ArrayList<String>()
        if (years > 0) prefixParts.add("${years}y")
        if (months > 0) prefixParts.add("${months}mo")
        if (days > 0) prefixParts.add("${days}d")
        val prefix = prefixParts.joinToString(" ")
        return if (prefix.isEmpty()) timeText else "$prefix $timeText"
    }

    private fun normalize(input: String): String =
        input
            .trim()
            .lowercase()
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

        val lowerExponent = floor(log2(normalized))
        val upperExponent = ceil(log2(normalized))
        val lower = 2.0.pow(lowerExponent)
        val upper = 2.0.pow(upperExponent)

        return if (abs(normalized - lower) <= abs(upper - normalized)) lower else upper
    }

    private fun isEffectivelyInteger(value: Double): Boolean =
        abs(value.swiftRounded() - value) < STABILITY_EPSILON
}
