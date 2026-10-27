// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.core.exposure

import com.sangwook.ptimer.core.reciprocity.ReciprocityProfile
import com.sangwook.ptimer.core.reciprocity.ReciprocityCalculationPolicyEvaluator
import com.sangwook.ptimer.core.reciprocity.ReciprocityCalculationRangeStatus
import com.sangwook.ptimer.core.reciprocity.ReciprocityInverse
import com.sangwook.ptimer.core.reciprocity.ReciprocityInverseFailure
import com.sangwook.ptimer.core.reciprocity.ReciprocityInverseResult
import com.sangwook.ptimer.core.reciprocity.calculatedCorrectedSeconds
import kotlin.math.abs
import kotlin.math.log2
import kotlin.math.max
import kotlin.math.pow

enum class TargetNDMedium { negative, positive, digital }
enum class TargetNDAllowance {
    standard, extended;
    fun interval(medium: TargetNDMedium): ClosedFloatingPointRange<Double> = when (medium) {
        TargetNDMedium.negative -> if (this == standard) -0.5..1.0 else -0.5..2.0
        TargetNDMedium.positive -> if (this == standard) (-1.0 / 3)..(1.0 / 3) else -0.5..0.5
        TargetNDMedium.digital -> if (this == standard) -1.0..0.0 else -2.0..0.0
    }
}

data class TargetNDCandidate(val stack: FilterStack, val remainingError: Double, val requiresSourceWarning: Boolean, val isCurrent: Boolean)
sealed interface TargetNDSelectionFailure {
    data object InvalidInput : TargetNDSelectionFailure
    data class Inverse(val reason: ReciprocityInverseFailure) : TargetNDSelectionFailure
    data object NegativeRequiredTotal : TargetNDSelectionFailure
    data object NoCombination : TargetNDSelectionFailure
}
sealed interface TargetNDSelectionResult {
    data class Available(val requiredStops: Double, val candidate: TargetNDCandidate) : TargetNDSelectionResult
    data class Unavailable(val reason: TargetNDSelectionFailure) : TargetNDSelectionResult
}
data class TargetNDSelectionContext(val selectedSets: List<FilterSetId>, val current: FilterStack, val allowance: ClosedFloatingPointRange<Double>)

/** Replace all ND as a value; keep exact auxiliaries and validate with the shared stack contract. */
class TargetNDSelection {
    fun evaluate(baseSeconds: Double, targetSeconds: Double, profile: ReciprocityProfile?, inventory: FilterInventory, context: TargetNDSelectionContext): TargetNDSelectionResult {
        if (!baseSeconds.isFinite() || baseSeconds <= 0 || !targetSeconds.isFinite() || targetSeconds <= 0) return TargetNDSelectionResult.Unavailable(TargetNDSelectionFailure.InvalidInput)
        var inverseWarning = false
        val metered = if (profile == null) targetSeconds else {
            when (val result = ReciprocityInverse().evaluate(profile, targetSeconds)) {
                is ReciprocityInverseResult.Available -> {
                    inverseWarning = result.evaluation.metadata.rangeStatus != ReciprocityCalculationRangeStatus.withinStatedRange
                    result.meteredSeconds
                }
                is ReciprocityInverseResult.Unavailable -> return TargetNDSelectionResult.Unavailable(TargetNDSelectionFailure.Inverse(result.reason))
            }
        }
        val required = log2(metered) - log2(baseSeconds)
        if (!required.isFinite()) return TargetNDSelectionResult.Unavailable(TargetNDSelectionFailure.InvalidInput)
        if (required < 0) return TargetNDSelectionResult.Unavailable(TargetNDSelectionFailure.NegativeRequiredTotal)
        val items = inventory.filterSets.filter { it.id in context.selectedSets }.flatMap { set -> set.ndItems.map { set.id to it } }
            .sortedWith(compareBy({ it.first.rawValue }, { it.second.id.rawValue }))
        val candidates = mutableListOf<Ranked>()
        fun consider(wheels: List<FilterWheel>) {
            val represented = wheels.ifEmpty { listOf(items.firstOrNull()?.let { FilterWheel.empty(it.first) } ?: FilterWheel.standard(0.0)) }
            val stack = FilterStack.validated(represented, context.current.auxiliaryFilters, inventory) ?: return
            val error = required - stack.effectiveStops
            val roundoff = 4 * max(Math.ulp(required), Math.ulp(stack.effectiveStops))
            if (error < context.allowance.start - roundoff || error > context.allowance.endInclusive + roundoff) return
            var warning = inverseWarning
            if (profile != null) {
                val result = ReciprocityCalculationPolicyEvaluator().evaluate(profile, baseSeconds * 2.0.pow(stack.effectiveStops))
                val corrected = result.calculatedCorrectedSeconds ?: return
                if (!corrected.isFinite() || corrected <= 0) return
                warning = warning || result.metadata.rangeStatus != ReciprocityCalculationRangeStatus.withinStatedRange
            }
            val identity = keys(stack)
            val old = keys(context.current)
            val counts = identity.groupingBy { it }.eachCount()
            val oldCounts = old.groupingBy { it }.eachCount()
            val changes = (counts.keys + oldCounts.keys).sumOf { abs((counts[it] ?: 0) - (oldCounts[it] ?: 0)) }
            candidates += Ranked(TargetNDCandidate(stack.sortedForCommit(inventory), error, warning, identity == old), identity, changes)
        }
        if (items.isEmpty()) {
            for (stop in 0..30) consider(listOf(FilterWheel.standard(stop.toDouble())))
        } else {
            val limit = FilterStack.wheelLimit(context.current.auxiliaryFilters.isNotEmpty())
            fun search(start: Int, wheels: List<FilterWheel>, used: Set<FilterItemId>) {
                consider(wheels)
                if (wheels.size >= limit) return
                for (index in start until items.size) {
                    val (source, item) = items[index]
                    if (item.id in used) continue
                    val wheel = FilterWheel(FilterSource.FilterSet(source), FilterWheelSelection.Item(FilterRowSelection(item.id, FilterRowChoice.Fixed)))
                    search(index + 1, wheels + wheel, used + item.id)
                }
            }
            search(0, emptyList(), emptySet())
        }
        val best = candidates.minOfOrNull { abs(it.candidate.remainingError) } ?: return TargetNDSelectionResult.Unavailable(TargetNDSelectionFailure.NoCombination)
        val chosen = candidates.filter { abs(it.candidate.remainingError) <= best + 0.1 + 8 * max(Math.ulp(required), Math.ulp(it.candidate.stack.effectiveStops)) }
            .minWith(compareBy<Ranked>({ it.keys.size }, { it.changes }).thenComparator { a, b -> compareKeys(a.keys, b.keys) })
        return TargetNDSelectionResult.Available(required, chosen.candidate)
    }

    private sealed class Identity : Comparable<Identity> {
        data class Standard(val stops: Double) : Identity()
        data class Physical(val source: String, val item: String) : Identity()
        override fun compareTo(other: Identity): Int = when (this) {
            is Standard -> if (other is Standard) stops.compareTo(other.stops) else -1
            is Physical -> if (other is Physical) compareValuesBy(this, other, { it.source }, { it.item }) else 1
        }
    }
    private data class Ranked(val candidate: TargetNDCandidate, val keys: List<Identity>, val changes: Int)
    private fun keys(stack: FilterStack): List<Identity> = stack.wheels.mapNotNull { wheel ->
        when (val selection = wheel.selection) {
            FilterWheelSelection.Empty -> null
            is FilterWheelSelection.Standard -> if (selection.stops == 0.0) null else Identity.Standard(selection.stops)
            is FilterWheelSelection.Item -> wheel.source.filterSetId?.let { Identity.Physical(it.rawValue, selection.selection.itemId.rawValue) }
        }
    }.sorted()
    private fun compareKeys(first: List<Identity>, second: List<Identity>): Int {
        for (index in 0 until minOf(first.size, second.size)) {
            val comparison = first[index].compareTo(second[index])
            if (comparison != 0) return comparison
        }
        return first.size.compareTo(second.size)
    }
}
