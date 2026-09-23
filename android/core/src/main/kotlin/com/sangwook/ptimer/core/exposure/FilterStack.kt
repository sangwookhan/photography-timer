// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.core.exposure

import com.sangwook.ptimer.core.exposure.ExposureCalculator.Companion.STABILITY_EPSILON
import kotlin.math.abs

/**
 * Which source a filter wheel draws its rows from: the built-in
 * Standard ND ladder, or one user-owned Filter Set.
 * (iOS: `FilterSource`.)
 */
sealed class FilterSource {
    data object Standard : FilterSource()
    data class FilterSet(val id: FilterSetId) : FilterSource()

    val filterSetId: FilterSetId? get() = (this as? FilterSet)?.id
}

/** Which shooting row of a physical item is selected. (iOS: `FilterRowChoice`.) */
sealed class FilterRowChoice {
    /** The single row of a Fixed item. */
    data object Fixed : FilterRowChoice()

    /** One of a CPL item's configured exposure-loss choices, in stops. */
    data class CplLoss(val stops: Double) : FilterRowChoice()

    /** A GND item's per-shot calculation mode. */
    data class Gnd(val mode: GndCalculationMode) : FilterRowChoice()
}

/** A mounted physical item plus the row chosen for it. (iOS: `FilterRowSelection`.) */
data class FilterRowSelection(val itemId: FilterItemId, val choice: FilterRowChoice)

/**
 * The committed (or in-flight) value of one wheel. [Standard] is the
 * only selection a Standard wheel holds; a Filter Set wheel holds
 * [Empty] (no physical item) or [Item] (a mounted item and its row).
 * (iOS: `FilterWheelSelection`.)
 */
sealed class FilterWheelSelection {
    data class Standard(val stops: Double) : FilterWheelSelection()
    data object Empty : FilterWheelSelection()
    data class Item(val selection: FilterRowSelection) : FilterWheelSelection()

    val itemId: FilterItemId? get() = (this as? Item)?.selection?.itemId
}

/**
 * One wheel of the mixed Filter Stack: its source and its selection.
 * (iOS: `FilterWheel`.)
 */
data class FilterWheel(val source: FilterSource, val selection: FilterWheelSelection) {

    val isStandard: Boolean get() = source is FilterSource.Standard

    val standardStops: Double? get() = (selection as? FilterWheelSelection.Standard)?.stops

    /**
     * Standard 0 and Filter Set Empty are the cleanable states: no
     * physical item is mounted and nothing contributes. A mounted
     * Record-only item is NOT cleanable (FILTER-STACK-006).
     */
    val isCleanable: Boolean
        get() = when (val current = selection) {
            is FilterWheelSelection.Standard -> current.stops == 0.0
            is FilterWheelSelection.Empty -> true
            is FilterWheelSelection.Item -> false
        }

    val mountedItemId: FilterItemId? get() = selection.itemId

    /**
     * Source and selection agree: Standard wheels hold `Standard`,
     * Filter Set wheels hold `Empty` or `Item`.
     */
    internal val isConsistent: Boolean
        get() = when (selection) {
            is FilterWheelSelection.Standard -> source is FilterSource.Standard
            is FilterWheelSelection.Empty, is FilterWheelSelection.Item -> source is FilterSource.FilterSet
        }

    companion object {
        fun standard(stops: Double): FilterWheel =
            FilterWheel(FilterSource.Standard, FilterWheelSelection.Standard(stops))

        fun empty(inFilterSetId: FilterSetId): FilterWheel =
            FilterWheel(FilterSource.FilterSet(inFilterSetId), FilterWheelSelection.Empty)
    }
}

/**
 * A wheel selection resolved against the inventory: what it contributes
 * now, what it sorts by, and the item it names.
 * (iOS: `ResolvedFilterRow`.)
 */
data class ResolvedFilterRow(
    val selection: FilterWheelSelection,
    /** Active contribution in canonical stops (0 for Empty and Record-only). */
    val contributionStops: Double,
    /**
     * Sort key within one source: the Standard value, an item's
     * canonical registered value, or a CPL row's chosen loss. Empty
     * sorts last regardless.
     */
    val registeredStops: Double,
    /** The physical item for `Item` selections; `null` otherwise. */
    val item: FilterItem?,
)

/**
 * Why a selection or mode change was refused. Changes are rejected,
 * never clamped; the previous valid state stays intact
 * (FILTER-STACK-004). (iOS: `FilterStackRejection`.)
 */
enum class FilterStackRejection {
    /** The active contributions would exceed 30 stops. */
    exceedsTotalLimit,

    /** The same physical item is already mounted on another wheel of this camera. */
    itemAlreadyMounted,

    /** The selection does not resolve against the inventory or does not
     *  belong to the wheel's source. */
    unresolvedSelection,
}

/**
 * Why the selected source cannot currently add a usable wheel
 * (FILTER-PLUS-005). (iOS: `FilterAddUnavailability`.)
 */
enum class FilterAddUnavailability {
    stackFull,

    /** Standard: the budget-truncated ladder holds no value above 0. */
    noSelectableValue,
    unknownFilterSet,
    filterSetHasNoItems,
    allItemsMounted,

    /** Every unmounted item's rows would exceed the 30-stop cap. */
    exceedsTotalLimit,
}

/** One selectable row of a wheel's picker. (iOS: `FilterWheelRowOption`.) */
data class FilterWheelRowOption(
    val row: ResolvedFilterRow,
    /** `null` when the row can be selected on this wheel right now. */
    val unavailability: FilterStackRejection?,
) {
    val selection: FilterWheelSelection get() = row.selection
    val isAvailable: Boolean get() = unavailability == null
}

/**
 * Outcome of writing one wheel's selection: the new stack, or the
 * reason the write was refused. (iOS: `Result<FilterStack, FilterStackRejection>`.)
 */
sealed class FilterStackChange {
    data class Accepted(val stack: FilterStack) : FilterStackChange()
    data class Rejected(val reason: FilterStackRejection) : FilterStackChange()
}

/**
 * The active camera's mixed Filter Stack: one to four wheels drawn from
 * Standard and Filter Set sources, resolved against the inventory
 * (FILTER-STACK-001). The 30-stop cap on active contributions and the
 * one-item-per-camera rule are invariants of this type: construction
 * goes through [validated], which reports a violation as `null`, and
 * every mutation returns either a valid stack or a rejection.
 * (iOS: `FilterStack`.)
 *
 * Two stacks are equal when their wheels are equal; [rows] is a pure
 * resolution of those wheels against an inventory.
 */
class FilterStack private constructor(
    val wheels: List<FilterWheel>,
    val rows: List<ResolvedFilterRow>,
) {

    // MARK: Derived values

    val contributions: List<Double> get() = rows.map { it.contributionStops }

    /**
     * The one effective value the calculation consumes: the sum of
     * active contributions in canonical stops.
     */
    val effectiveStops: Double get() = contributions.sum()

    /**
     * Remaining budget for the wheel at [excludingWheelAt]: the cap
     * minus every OTHER wheel's active contribution.
     */
    fun remainingBudget(excludingWheelAt: Int): Double {
        require(excludingWheelAt in wheels.indices) { "Wheel index out of range." }
        val others = rows.filterIndexed { index, _ -> index != excludingWheelAt }
            .sumOf { it.contributionStops }
        return TOTAL_LIMIT - others
    }

    fun mountedItemIds(excludingWheelAt: Int?): Set<FilterItemId> =
        wheels.withIndex()
            .filter { (index, _) -> index != excludingWheelAt }
            .mapNotNull { (_, wheel) -> wheel.mountedItemId }
            .toSet()

    // MARK: Row options

    /**
     * Picker rows for the wheel at [wheelIndex]. Standard wheels get the
     * shipping ladder truncated from the top to the remaining budget
     * (every row selectable); Filter Set wheels get Empty plus every row
     * of the set's items, each marked unavailable when its item is
     * mounted elsewhere on this camera or its contribution would exceed
     * the cap. The wheel's own current row is always available
     * (FILTER-CPL-005).
     */
    fun rowOptions(
        wheelIndex: Int,
        inventory: FilterInventory,
        ladderStops: List<Double> = shippingLadderStops,
    ): List<FilterWheelRowOption> {
        if (wheelIndex !in wheels.indices) return emptyList()
        val wheel = wheels[wheelIndex]
        val budget = remainingBudget(excludingWheelAt = wheelIndex)
        return when (val source = wheel.source) {
            is FilterSource.Standard ->
                ladderStops.filter { it <= budget + STABILITY_EPSILON }.map { stops ->
                    FilterWheelRowOption(standardRow(stops), unavailability = null)
                }

            is FilterSource.FilterSet -> {
                val filterSet = inventory.filterSet(source.id) ?: return emptyList()
                val mountedElsewhere = mountedItemIds(excludingWheelAt = wheelIndex)
                val current = wheel.selection
                val options = ArrayList<FilterWheelRowOption>()
                options.add(FilterWheelRowOption(emptyRow, unavailability = null))
                for (item in filterSet.items) {
                    for (row in rows(forItem = item)) {
                        val unavailability = when {
                            row.selection == current -> null
                            mountedElsewhere.contains(item.id) -> FilterStackRejection.itemAlreadyMounted
                            row.contributionStops > budget + STABILITY_EPSILON ->
                                FilterStackRejection.exceedsTotalLimit

                            else -> null
                        }
                        options.add(FilterWheelRowOption(row, unavailability))
                    }
                }
                options
            }
        }
    }

    // MARK: Adding wheels

    val canAddWheel: Boolean get() = wheels.size < MAX_WHEEL_COUNT

    /**
     * Why [source] cannot add a usable wheel right now, or `null` when
     * it can. A Record-only row keeps a Filter Set addable at a 30-stop
     * total as long as a slot and an unmounted item remain
     * (FILTER-PLUS-005).
     */
    fun addUnavailability(
        source: FilterSource,
        inventory: FilterInventory,
        ladderStops: List<Double> = shippingLadderStops,
    ): FilterAddUnavailability? {
        if (!canAddWheel) return FilterAddUnavailability.stackFull
        val budget = TOTAL_LIMIT - effectiveStops
        return when (source) {
            is FilterSource.Standard -> {
                val hasValue = ladderStops.any { it > 0 && it <= budget + STABILITY_EPSILON }
                if (hasValue) null else FilterAddUnavailability.noSelectableValue
            }

            is FilterSource.FilterSet -> {
                val filterSet = inventory.filterSet(source.id)
                    ?: return FilterAddUnavailability.unknownFilterSet
                if (filterSet.items.isEmpty()) return FilterAddUnavailability.filterSetHasNoItems
                val mounted = mountedItemIds(excludingWheelAt = null)
                val unmounted = filterSet.items.filter { it.id !in mounted }
                if (unmounted.isEmpty()) return FilterAddUnavailability.allItemsMounted
                val fits = unmounted.any { item ->
                    rows(forItem = item).any { it.contributionStops <= budget + STABILITY_EPSILON }
                }
                if (fits) null else FilterAddUnavailability.exceedsTotalLimit
            }
        }
    }

    /**
     * Appends a Standard 0-stop wheel or a Filter Set Empty wheel for
     * [source]. Never changes the effective value. No-op at the maximum
     * or for an unknown Filter Set (FILTER-PLUS-003).
     */
    fun addingWheel(source: FilterSource, inventory: FilterInventory): FilterStack {
        if (!canAddWheel || !inventory.contains(source)) return this
        val wheel = when (source) {
            is FilterSource.Standard -> FilterWheel.standard(0.0)
            is FilterSource.FilterSet -> FilterWheel.empty(source.id)
        }
        val row = when (source) {
            is FilterSource.Standard -> standardRow(0.0)
            is FilterSource.FilterSet -> emptyRow
        }
        return FilterStack(wheels + wheel, rows + row)
    }

    // MARK: Removing cleanable wheels

    /**
     * More than one wheel AND at least one cleanable wheel (Standard 0
     * or Empty). Mounted items are never removed.
     */
    val canRemoveEmptyWheel: Boolean
        get() = wheels.size > 1 && wheels.any { it.isCleanable }

    fun removingEmptyWheel(at: Int): FilterStack {
        if (wheels.size <= 1 || at !in wheels.indices || !wheels[at].isCleanable) return this
        return FilterStack(
            wheels.filterIndexed { index, _ -> index != at },
            rows.filterIndexed { index, _ -> index != at },
        )
    }

    fun removingRightmostEmptyWheel(): FilterStack {
        val index = wheels.indexOfLast { it.isCleanable }
        if (index < 0) return this
        return removingEmptyWheel(at = index)
    }

    // MARK: Replacing a wheel's selection

    /**
     * Writes one wheel's selection. Rejected — leaving the stack
     * unchanged — when the selection does not resolve for the wheel's
     * source, the item is already mounted on another wheel, or the
     * active contributions would exceed 30 stops.
     */
    fun replacingWheel(
        at: Int,
        selection: FilterWheelSelection,
        inventory: FilterInventory,
    ): FilterStackChange {
        if (at !in wheels.indices) {
            return FilterStackChange.Rejected(FilterStackRejection.unresolvedSelection)
        }
        val wheel = FilterWheel(wheels[at].source, selection)
        val row = resolvedRow(wheel, inventory)
            ?: return FilterStackChange.Rejected(FilterStackRejection.unresolvedSelection)
        val itemId = row.selection.itemId
        if (itemId != null && mountedItemIds(excludingWheelAt = at).contains(itemId)) {
            return FilterStackChange.Rejected(FilterStackRejection.itemAlreadyMounted)
        }
        if (row.contributionStops > remainingBudget(excludingWheelAt = at) + STABILITY_EPSILON) {
            return FilterStackChange.Rejected(FilterStackRejection.exceedsTotalLimit)
        }
        val newWheels = wheels.toMutableList().also { it[at] = FilterWheel(wheel.source, row.selection) }
        val newRows = rows.toMutableList().also { it[at] = row }
        return FilterStackChange.Accepted(FilterStack(newWheels, newRows))
    }

    // MARK: Post-commit ordering

    /**
     * A row's sort value (FILTER-STACK-005): a Standard row's selected
     * stops, a Fixed row's registered canonical stops, a CPL row's
     * selected exposure-loss choice, a GND row's registered full density
     * in BOTH modes (so a mode change never moves it), and zero for
     * Empty and Standard 0.
     */
    fun sortValue(wheelIndex: Int): Double =
        if (wheels[wheelIndex].isCleanable) 0.0 else rows[wheelIndex].registeredStops

    /**
     * Registered subtotal of one source group: the sum of the sort
     * values of every wheel from [source]. Zero for a source with no
     * wheel in the stack.
     */
    fun registeredSubtotal(source: FilterSource): Double =
        wheels.indices.sumOf { if (wheels[it].source == source) sortValue(it) else 0.0 }

    /**
     * Permutation of the current indices in commit order
     * (FILTER-STACK-005): wheels from one source stay contiguous and
     * source groups sort by registered subtotal descending; equal
     * subtotals put Standard first and then follow the user-defined
     * Filter Set order. Within one group, non-empty rows sort by the
     * same row value descending with stable ties; Empty (and Standard 0)
     * last.
     */
    fun commitSortPermutation(inventory: FilterInventory): List<Int> {
        val subtotals = wheels.map { it.source }.distinct().associateWith { registeredSubtotal(it) }
        return wheels.indices.sortedWith { lhs, rhs ->
            val lhsSource = wheels[lhs].source
            val rhsSource = wheels[rhs].source
            if (lhsSource != rhsSource) {
                val lhsSubtotal = subtotals[lhsSource] ?: 0.0
                val rhsSubtotal = subtotals[rhsSource] ?: 0.0
                if (abs(lhsSubtotal - rhsSubtotal) > STABILITY_EPSILON) {
                    return@sortedWith if (lhsSubtotal > rhsSubtotal) -1 else 1
                }
                return@sortedWith inventory.sourceOrderIndex(lhsSource)
                    .compareTo(inventory.sourceOrderIndex(rhsSource))
            }
            val lhsEmpty = wheels[lhs].isCleanable
            val rhsEmpty = wheels[rhs].isCleanable
            if (lhsEmpty != rhsEmpty) return@sortedWith if (lhsEmpty) 1 else -1
            val lhsKey = sortValue(lhs)
            val rhsKey = sortValue(rhs)
            if (abs(lhsKey - rhsKey) > STABILITY_EPSILON) {
                return@sortedWith if (lhsKey > rhsKey) -1 else 1
            }
            lhs.compareTo(rhs)
        }
    }

    fun sortedForCommit(inventory: FilterInventory): FilterStack {
        val permutation = commitSortPermutation(inventory)
        return FilterStack(permutation.map { wheels[it] }, permutation.map { rows[it] })
    }

    override fun equals(other: Any?): Boolean =
        this === other || (other is FilterStack && other.wheels == wheels)

    override fun hashCode(): Int = wheels.hashCode()

    override fun toString(): String = "FilterStack(wheels=$wheels)"

    companion object {
        val MAX_WHEEL_COUNT: Int = NdFilterStack.MAX_WHEEL_COUNT
        const val TOTAL_LIMIT: Double = 30.0

        /** The shipping ND ladder as plain stop values (the default Standard rows). */
        val shippingLadderStops: List<Double> = ExposureScale.shippingNDLadder.map { it.stops }

        private val emptyRow = ResolvedFilterRow(
            selection = FilterWheelSelection.Empty,
            contributionStops = 0.0,
            registeredStops = 0.0,
            item = null,
        )

        private fun standardRow(stops: Double) = ResolvedFilterRow(
            selection = FilterWheelSelection.Standard(stops),
            contributionStops = stops,
            registeredStops = stops,
            item = null,
        )

        /** A single Standard wheel — the default and legacy shape. */
        fun single(stops: Double): FilterStack =
            FilterStack(listOf(FilterWheel.standard(stops)), listOf(standardRow(stops)))

        /** Standard-only stack from raw wheel values (legacy callers). */
        fun standardSteps(stops: List<Double>): FilterStack =
            requireNotNull(validated(stops.map { FilterWheel.standard(it) }, FilterInventory.empty)) {
                "A Filter Stack holds 1..$MAX_WHEEL_COUNT resolvable wheels within $TOTAL_LIMIT stops."
            }

        /**
         * Validating construction: `null` when any wheel fails to
         * resolve, the count is outside 1–4, or the contributions exceed
         * the cap.
         */
        fun validated(wheels: List<FilterWheel>, inventory: FilterInventory): FilterStack? {
            if (wheels.size !in 1..MAX_WHEEL_COUNT) return null
            val rows = ArrayList<ResolvedFilterRow>(wheels.size)
            val mounted = HashSet<FilterItemId>()
            for (wheel in wheels) {
                val row = resolvedRow(wheel, inventory) ?: return null
                val itemId = row.selection.itemId
                if (itemId != null && !mounted.add(itemId)) return null
                rows.add(row)
            }
            if (!isWithinTotalLimit(rows.map { it.contributionStops })) return null
            return FilterStack(wheels, rows)
        }

        fun isWithinTotalLimit(contributions: List<Double>): Boolean =
            contributions.sum() <= TOTAL_LIMIT + STABILITY_EPSILON

        /**
         * Resolves one wheel against the inventory. `null` when the wheel
         * is inconsistent, names an unknown Filter Set or item, or names
         * a row the item no longer offers.
         */
        fun resolvedRow(wheel: FilterWheel, inventory: FilterInventory): ResolvedFilterRow? {
            if (!wheel.isConsistent) return null
            return when (val selection = wheel.selection) {
                is FilterWheelSelection.Standard -> {
                    if (!selection.stops.isFinite() || selection.stops < 0) return null
                    standardRow(selection.stops)
                }

                is FilterWheelSelection.Empty ->
                    if (inventory.contains(wheel.source)) emptyRow else null

                is FilterWheelSelection.Item -> {
                    val filterSetId = wheel.source.filterSetId ?: return null
                    val filterSet = inventory.filterSet(filterSetId) ?: return null
                    val item = filterSet.item(selection.selection.itemId) ?: return null
                    resolvedRow(item, selection.selection.choice)
                }
            }
        }

        internal fun resolvedRow(item: FilterItem, choice: FilterRowChoice): ResolvedFilterRow? {
            val behavior = item.behavior
            return when {
                behavior is FilterItemBehavior.Fixed && choice is FilterRowChoice.Fixed -> {
                    val stops = behavior.value.canonicalStops ?: return null
                    ResolvedFilterRow(itemSelection(item, choice), stops, stops, item)
                }

                behavior is FilterItemBehavior.Cpl && choice is FilterRowChoice.CplLoss -> {
                    val matched = behavior.choices.shootingChoices.firstOrNull {
                        abs(it - choice.stops) <= STABILITY_EPSILON
                    } ?: return null
                    val normalized = itemSelection(item, FilterRowChoice.CplLoss(matched))
                    ResolvedFilterRow(normalized, matched, matched, item)
                }

                behavior is FilterItemBehavior.Gnd && choice is FilterRowChoice.Gnd -> {
                    val stops = behavior.value.canonicalStops ?: return null
                    val contribution =
                        if (choice.mode == GndCalculationMode.applyFullValue) stops else 0.0
                    ResolvedFilterRow(itemSelection(item, choice), contribution, stops, item)
                }

                else -> null
            }
        }

        private fun itemSelection(item: FilterItem, choice: FilterRowChoice): FilterWheelSelection =
            FilterWheelSelection.Item(FilterRowSelection(item.id, choice))

        /**
         * Every shooting row an item offers, in wheel order: Fixed → one
         * row; CPL → one row per distinct configured choice; GND → Record
         * only, then Apply full value.
         */
        fun rows(forItem: FilterItem): List<ResolvedFilterRow> =
            when (val behavior = forItem.behavior) {
                is FilterItemBehavior.Fixed ->
                    listOfNotNull(resolvedRow(forItem, FilterRowChoice.Fixed))

                is FilterItemBehavior.Cpl -> behavior.choices.shootingChoices.mapNotNull {
                    resolvedRow(forItem, FilterRowChoice.CplLoss(it))
                }

                is FilterItemBehavior.Gnd -> GndCalculationMode.entries.mapNotNull {
                    resolvedRow(forItem, FilterRowChoice.Gnd(it))
                }
            }

        /**
         * Safe re-resolution of persisted or previously valid wheels
         * against the current inventory: a wheel whose Filter Set no
         * longer exists is dropped, and a wheel whose item or selected
         * row no longer exists becomes Empty — a CPL selection whose
         * configured exposure-loss choice is gone is never replaced by
         * another choice (FILTER-PERSIST-002). An inconsistent wheel is
         * dropped. A result with no wheel becomes one Standard 0 wheel.
         * Returns `null` only when more than four wheels were supplied —
         * that is corruption, not recoverable state.
         */
        fun normalizedWheels(
            wheels: List<FilterWheel>,
            inventory: FilterInventory,
        ): List<FilterWheel>? {
            if (wheels.size > MAX_WHEEL_COUNT) return null
            val normalized = ArrayList<FilterWheel>(wheels.size)
            val mounted = HashSet<FilterItemId>()
            for (wheel in wheels) {
                var resolved = normalizedWheel(wheel, inventory) ?: continue
                // A physical item may be mounted once per camera: a later
                // duplicate reference becomes Empty.
                val itemId = resolved.mountedItemId
                if (itemId != null && !mounted.add(itemId)) {
                    resolved = FilterWheel(resolved.source, FilterWheelSelection.Empty)
                }
                normalized.add(resolved)
            }
            return normalized.ifEmpty { listOf(FilterWheel.standard(0.0)) }
        }

        /**
         * Single-wheel step of [normalizedWheels]: the wheel as it should
         * now read, or `null` when it must be dropped (inconsistent,
         * invalid Standard value, or unknown Filter Set). Exposed so a
         * caller keeping per-wheel identity can follow each wheel through
         * re-resolution.
         */
        fun normalizedWheel(wheel: FilterWheel, inventory: FilterInventory): FilterWheel? {
            if (!wheel.isConsistent) return null
            return when (val selection = wheel.selection) {
                is FilterWheelSelection.Standard ->
                    if (selection.stops.isFinite() && selection.stops >= 0) wheel else null

                is FilterWheelSelection.Empty -> if (inventory.contains(wheel.source)) wheel else null

                is FilterWheelSelection.Item -> {
                    val filterSetId = wheel.source.filterSetId ?: return null
                    val filterSet = inventory.filterSet(filterSetId) ?: return null
                    val item = filterSet.item(selection.selection.itemId)
                    if (item == null || resolvedRow(item, selection.selection.choice) == null) {
                        FilterWheel.empty(filterSetId)
                    } else {
                        wheel
                    }
                }
            }
        }
    }
}
