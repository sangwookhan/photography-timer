// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.core.exposure

import com.sangwook.ptimer.core.exposure.ExposureCalculator.Companion.STABILITY_EPSILON

/**
 * A stack of one to four standard ND filter wheel values (PTIMER-199).
 * Every entry is one wheel's committed value in display order, in
 * canonical stops; the whole stack collapses to a single effective
 * (summed) value that feeds the existing exposure calculation
 * unchanged. (iOS: NDFilterStack.)
 *
 * The 30-stop total limit is a DOMAIN INVARIANT of this type: every
 * construction and mutation boundary guarantees `sum <= 30`. The UI
 * additionally makes over-limit selections unrepresentable (wheels
 * select from ladders truncated to the remaining budget), but non-UI
 * callers are held to the same rule: construction rejects a violating
 * stack, and [replacingWheel] ignores a write that would push the sum
 * over the cap. Raw persisted values must be validated BEFORE
 * constructing a stack (the restore path rejects, it never clamps).
 */
data class NdFilterStack(val entries: List<Double>) {
    init {
        require(entries.size in 1..MAX_WHEEL_COUNT) {
            "An ND filter stack holds 1..$MAX_WHEEL_COUNT wheels."
        }
        require(entries.all { it >= 0.0 && it.isFinite() }) {
            "ND filter wheels never hold negative or non-finite stops."
        }
        require(isWithinTotalLimit(entries)) {
            "An ND filter stack never exceeds $MAX_TOTAL_STOPS stops in total."
        }
    }

    /** The one effective filter value the calculation consumes. */
    val effectiveStops: Double get() = entries.sum()

    /**
     * Remaining stop budget available to the wheel at [index] under the
     * 30-stop total limit: the cap minus every OTHER wheel's committed
     * value. Feeds the per-wheel ladder truncation.
     */
    fun remainingBudget(excludingWheelAt: Int): Double {
        require(excludingWheelAt in entries.indices) { "Wheel index out of range." }
        val others = entries.filterIndexed { i, _ -> i != excludingWheelAt }.sum()
        return MAX_TOTAL_STOPS - others
    }

    val canAddWheel: Boolean get() = entries.size < MAX_WHEEL_COUNT

    /**
     * Whether a wheel can be removed: more than one wheel AND at least
     * one 0-stop wheel (wheels holding a value are never removed).
     */
    val canRemoveEmptyWheel: Boolean
        get() = entries.size > 1 && entries.any { it == 0.0 }

    /** Appends one 0-stop wheel at the right; no-op at the maximum. */
    fun addingWheel(): NdFilterStack =
        if (canAddWheel) NdFilterStack(entries + 0.0) else this

    /** Removes the rightmost 0-stop wheel; no-op when unavailable. */
    fun removingRightmostEmptyWheel(): NdFilterStack {
        if (!canRemoveEmptyWheel) return this
        val index = entries.indexOfLast { it == 0.0 }
        if (index < 0) return this
        return NdFilterStack(entries.filterIndexed { i, _ -> i != index })
    }

    /**
     * Removes the 0-stop wheel at [index] — the overscroll gesture's
     * target (§4.2.3: exactly the wheel the photographer pulled).
     * No-op for out-of-range indices, non-zero wheels, and
     * single-wheel stacks.
     */
    fun removingEmptyWheel(at: Int): NdFilterStack {
        if (at !in entries.indices || entries[at] != 0.0 || entries.size <= 1) return this
        return NdFilterStack(entries.filterIndexed { i, _ -> i != at })
    }

    /**
     * Replaces one wheel's value. Out-of-range indices, negative or
     * non-finite values, and writes that would push the total over the
     * 30-stop limit are all ignored (reject, never clamp).
     */
    fun replacingWheel(at: Int, stops: Double): NdFilterStack {
        if (at !in entries.indices || stops < 0.0 || !stops.isFinite()) return this
        val replaced = entries.toMutableList().also { it[at] = stops }
        return if (isWithinTotalLimit(replaced)) NdFilterStack(replaced) else this
    }

    /**
     * The index permutation [sortedForCommit] applies: `result[i]` is
     * the CURRENT index of the wheel that lands at position `i`.
     * Exposed so a caller tracking per-wheel identity (the reorder
     * animation) can move companion state through the same stable
     * sort. Descending by stops, zeros rightmost, equal values keep
     * their existing relative order.
     */
    fun commitSortPermutation(): List<Int> =
        entries.withIndex()
            .sortedWith(compareByDescending<IndexedValue<Double>> { it.value }.thenBy { it.index })
            .map { it.index }

    /** The agreed post-commit ordering; reorders VALUES only. */
    fun sortedForCommit(): NdFilterStack =
        NdFilterStack(commitSortPermutation().map { entries[it] })

    companion object {
        const val MAX_WHEEL_COUNT: Int = 4
        const val MAX_TOTAL_STOPS: Double = 30.0

        /**
         * Whether [entries] respect the 30-stop total limit (within
         * the engine's stability epsilon). Exposed so validation
         * layers (persistence restore) can check RAW values before
         * attempting construction.
         */
        fun isWithinTotalLimit(entries: List<Double>): Boolean =
            entries.sum() <= MAX_TOTAL_STOPS + STABILITY_EPSILON

        /**
         * Restore validation (reject, never clamp): a persisted stack
         * is accepted only when the count, every value (finite,
         * non-negative, ON the shipping ladder), and the total pass —
         * otherwise the caller falls back to the legacy scalar.
         */
        fun isValidRestoredStack(entries: List<Double>?): Boolean {
            if (entries == null) return false
            if (entries.size !in 1..MAX_WHEEL_COUNT) return false
            if (!entries.all { it.isFinite() && it >= 0.0 }) return false
            if (!isWithinTotalLimit(entries)) return false
            return entries.all { value ->
                ExposureScale.shippingNDLadder.any { rung ->
                    kotlin.math.abs(rung.stops - value) <= STABILITY_EPSILON
                }
            }
        }
    }
}
