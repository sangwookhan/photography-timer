package com.sangwook.ptimer.core.reciprocity

/**
 * Parses the duration-style strings the custom-profile editor accepts in
 * its range fields. Mirrors iOS `CustomFilmDurationParser`.
 *
 * - empty → [ParsedDuration.Empty]
 * - "unlimited" (case-insensitive) → [ParsedDuration.Unlimited]
 * - plain decimal "100" → 100s; "100s"/"5m"/"1h" → seconds
 * - anything else → null
 */
object CustomFilmDurationParser {
    sealed interface ParsedDuration {
        data class Seconds(val value: Double) : ParsedDuration
        data object Unlimited : ParsedDuration
        data object Empty : ParsedDuration
    }

    fun parse(text: String): ParsedDuration? {
        val trimmed = text.trim()
        if (trimmed.isEmpty()) return ParsedDuration.Empty
        if (trimmed.equals("unlimited", ignoreCase = true)) return ParsedDuration.Unlimited

        val lowered = trimmed.lowercase()
        val plain = lowered.toDoubleOrNull()
        if (plain != null && plain.isFinite()) return ParsedDuration.Seconds(plain)

        if (lowered.isNotEmpty()) {
            val unit = lowered.last()
            val body = lowered.dropLast(1)
            val value = body.toDoubleOrNull()
            if (value == null || !value.isFinite()) return null
            return when (unit) {
                's' -> ParsedDuration.Seconds(value)
                'm' -> ParsedDuration.Seconds(value * 60)
                'h' -> ParsedDuration.Seconds(value * 3600)
                else -> null
            }
        }
        return null
    }
}
