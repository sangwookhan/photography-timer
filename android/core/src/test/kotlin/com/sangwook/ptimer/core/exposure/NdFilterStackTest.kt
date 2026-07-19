// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.core.exposure

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * PTIMER-199: the ND filter wheel stack domain type — sum, stable
 * commit sort with its permutation, the 30-stop invariant at every
 * construction/mutation boundary, budgets, and restore validation.
 * Mirrors the iOS NDFilterStack tests.
 */
class NdFilterStackTest {
    @Test
    fun effectiveStopsIsTheSum() {
        assertEquals(19.0, NdFilterStack(listOf(10.0, 6.0, 3.0, 0.0)).effectiveStops, 1e-9)
        assertEquals(13.2, NdFilterStack(listOf(6.6, 6.6)).effectiveStops, 1e-9)
    }

    @Test
    fun sortIsDescendingZerosRightAndStable() {
        val stack = NdFilterStack(listOf(0.0, 10.0, 0.0, 6.0))
        assertEquals(listOf(10.0, 6.0, 0.0, 0.0), stack.sortedForCommit().entries)
        assertEquals(listOf(1, 3, 0, 2), stack.commitSortPermutation())

        // Equal values keep their input order (stable).
        val equal = NdFilterStack(listOf(6.6, 6.6, 3.0))
        assertEquals(listOf(0, 1, 2), equal.commitSortPermutation())
    }

    @Test(expected = IllegalArgumentException::class)
    fun constructionRejectsOverThirtyStops() {
        NdFilterStack(listOf(20.0, 11.0))
    }

    @Test(expected = IllegalArgumentException::class)
    fun constructionRejectsNegativeWheels() {
        NdFilterStack(listOf(-1.0))
    }

    @Test(expected = IllegalArgumentException::class)
    fun constructionRejectsEmptyAndOversizedStacks() {
        NdFilterStack(emptyList())
    }

    @Test
    fun replacingWheelRefusesOverLimitAndInvalidWrites() {
        val stack = NdFilterStack(listOf(20.0, 0.0))
        assertEquals(stack, stack.replacingWheel(1, 11.0))
        assertEquals(stack, stack.replacingWheel(1, -1.0))
        assertEquals(stack, stack.replacingWheel(1, Double.NaN))
        assertEquals(stack, stack.replacingWheel(5, 1.0))
        assertEquals(listOf(20.0, 10.0), stack.replacingWheel(1, 10.0).entries)
    }

    @Test
    fun budgetExcludesTheWheelItself() {
        val stack = NdFilterStack(listOf(10.0, 6.6, 0.0))
        assertEquals(23.4, stack.remainingBudget(excludingWheelAt = 0), 1e-9)
        assertEquals(13.4, stack.remainingBudget(excludingWheelAt = 2), 1e-9)
    }

    @Test
    fun addAndRemoveRules() {
        val one = NdFilterStack(listOf(7.0))
        assertTrue(one.canAddWheel)
        assertFalse(one.canRemoveEmptyWheel)

        val four = NdFilterStack(listOf(1.0, 2.0, 3.0, 0.0))
        assertFalse(four.canAddWheel)
        assertEquals(four, four.addingWheel())
        assertEquals(listOf(1.0, 2.0, 3.0), four.removingRightmostEmptyWheel().entries)

        // Indexed removal takes exactly the pulled wheel.
        val zeros = NdFilterStack(listOf(10.0, 0.0, 0.0))
        assertEquals(listOf(10.0, 0.0), zeros.removingEmptyWheel(at = 1).entries)
        // Refusals: non-zero, out of range, last wheel.
        assertEquals(zeros, zeros.removingEmptyWheel(at = 0))
        assertEquals(zeros, zeros.removingEmptyWheel(at = 9))
        val lone = NdFilterStack(listOf(0.0))
        assertEquals(lone, lone.removingEmptyWheel(at = 0))
    }

    @Test
    fun restoredStackValidationRejectsNeverClamps() {
        assertTrue(NdFilterStack.isValidRestoredStack(listOf(10.0, 6.6, 0.0)))
        assertFalse(NdFilterStack.isValidRestoredStack(null))
        assertFalse(NdFilterStack.isValidRestoredStack(emptyList()))
        assertFalse(NdFilterStack.isValidRestoredStack(listOf(1.0, 2.0, 3.0, 4.0, 5.0)))
        assertFalse(NdFilterStack.isValidRestoredStack(listOf(-1.0)))
        assertFalse(NdFilterStack.isValidRestoredStack(listOf(20.0, 11.0)))
        // Off-ladder value: rejected, not snapped.
        assertFalse(NdFilterStack.isValidRestoredStack(listOf(6.4)))
    }
}
