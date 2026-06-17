package com.sangwook.ptimer.customfilm

/**
 * Generates collision-free custom-film ids of the form
 * `custom-<prefix>-<n>`. The next sequence value is derived from the
 * highest numeric suffix already present across ALL custom ids (formula and
 * table share one monotonic sequence), never from the library size — so a
 * delete followed by relaunch can never re-mint an id that still exists and
 * overwrite a persisted profile. Pure / Android-free / JVM-testable.
 */
object CustomFilmIdSequencer {
    private val PATTERN = Regex("""^custom-(?:formula|table)-(\d+)$""")

    /** One past the largest existing numeric suffix (0 when none match). */
    fun nextSequence(existingIds: Collection<String>): Int {
        var max = -1
        for (id in existingIds) {
            val n = PATTERN.matchEntire(id)?.groupValues?.get(1)?.toIntOrNull() ?: continue
            if (n > max) max = n
        }
        return max + 1
    }

    fun id(prefix: String, sequence: Int): String = "custom-$prefix-$sequence"
}
