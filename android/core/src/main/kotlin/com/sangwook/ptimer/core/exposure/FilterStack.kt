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

/**
 * Which shooting row of a physical item is selected on an ND wheel. Only
 * [Fixed] resolves on a wheel today (FILTER-STACK-003); the CPL and GND
 * cases survive as legacy wheel selections so a persisted mixed stack can
 * be migrated into auxiliary filters ([FilterStack.migratingLegacyWheels]).
 * (iOS: `FilterRowChoice`.)
 */
sealed class FilterRowChoice {
    /** The single row of a Fixed (ND) item. */
    data object Fixed : FilterRowChoice()

    /** Legacy: one of a CPL item's exposure-loss choices, in stops. */
    data class CplLoss(val stops: Double) : FilterRowChoice()

    /** Legacy: a GND item's per-shot calculation mode. */
    data class Gnd(val mode: GndCalculationMode) : FilterRowChoice()
}

/** A mounted physical item plus the row chosen for it. (iOS: `FilterRowSelection`.) */
data class FilterRowSelection(val itemId: FilterItemId, val choice: FilterRowChoice)

/**
 * Per-shot choice for a mounted auxiliary filter (FILTER-AUX-003): a
 * CPL's selected exposure-loss choice, a GND's calculation mode, or — for
 * Color and Effect items — their registered loss.
 * (iOS: `AuxiliaryFilterChoice`.)
 */
sealed class AuxiliaryFilterChoice {
    data class CplLoss(val stops: Double) : AuxiliaryFilterChoice()
    data class Gnd(val mode: GndCalculationMode) : AuxiliaryFilterChoice()
    data object RegisteredLoss : AuxiliaryFilterChoice()
}

/**
 * One physical auxiliary filter mounted on the active camera, with the
 * choice made for the current shot. Auxiliary filters share one summary
 * space on Main; they are not wheels. (iOS: `MountedAuxiliaryFilter`.)
 */
data class MountedAuxiliaryFilter(
    val filterSetId: FilterSetId,
    val itemId: FilterItemId,
    val choice: AuxiliaryFilterChoice,
) {
    companion object {
        /**
         * The default choice when an item is first mounted: a CPL's first
         * configured choice, Record only for a GND (FILTER-GND-002), and
         * the registered loss otherwise. `null` for an ND item, which is
         * never an auxiliary filter.
         */
        fun initialChoice(item: FilterItem): AuxiliaryFilterChoice? = when (val behavior = item.behavior) {
            is FilterItemBehavior.Fixed -> null
            is FilterItemBehavior.Cpl ->
                behavior.choices.shootingChoices.firstOrNull()?.let { AuxiliaryFilterChoice.CplLoss(it) }
            is FilterItemBehavior.Gnd -> AuxiliaryFilterChoice.Gnd(GndCalculationMode.recordOnly)
            is FilterItemBehavior.Color, is FilterItemBehavior.Effect -> AuxiliaryFilterChoice.RegisteredLoss
        }
    }
}

/**
 * A mounted auxiliary filter resolved against the inventory: the item it
 * names, its owning set's presentation metadata, what it contributes now,
 * and its registered value (a GND's full density, a CPL's selected
 * choice, a Color / Effect item's loss). (iOS: `ResolvedAuxiliaryFilter`.)
 */
data class ResolvedAuxiliaryFilter(
    val mount: MountedAuxiliaryFilter,
    val item: FilterItem,
    val filterSetName: String,
    val filterSetColor: FilterSetColor,
    /** Active contribution in canonical stops (0 for Record only). */
    val contributionStops: Double,
    /** Registered value in canonical stops. */
    val registeredStops: Double,
)

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

    /**
     * Standard 0 and Filter Set Empty are the cleanable states: no
     * physical item is mounted and nothing contributes. A mounted
     * Record-only item is NOT cleanable (FILTER-STACK-006). Lives on
     * the selection so the wheel, the picker row, and the display layer
     * all read the same rule.
     */
    val isCleanable: Boolean
        get() = when (this) {
            is Standard -> stops == 0.0
            is Empty -> true
            is Item -> false
        }
}

/**
 * One wheel of the mixed Filter Stack: its source and its selection.
 * (iOS: `FilterWheel`.)
 */
data class FilterWheel(val source: FilterSource, val selection: FilterWheelSelection) {

    val isStandard: Boolean get() = source is FilterSource.Standard

    val standardStops: Double? get() = (selection as? FilterWheelSelection.Standard)?.stops

    /** Whether an overscroll pull may remove this wheel; see
     *  [FilterWheelSelection.isCleanable]. */
    val isCleanable: Boolean get() = selection.isCleanable

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

    /** Mounting an auxiliary filter while four ND wheels exist: the
     *  wheels are never removed or merged automatically
     *  (FILTER-STACK-001, FILTER-AUX-003). */
    tooManyNDWheels,
}

/**
 * Why the selected source cannot currently add a usable wheel
 * (FILTER-PLUS-005). (iOS: `FilterAddUnavailability`.)
 */
enum class FilterAddUnavailability {
    /** The applicable ND-wheel limit is reached: four without auxiliary
     *  filters, three with them (FILTER-STACK-001). */
    stackFull,

    /** Standard: the budget-truncated ladder holds no value above 0. */
    noSelectableValue,
    unknownFilterSet,

    /** The Filter Set has no ND item; auxiliary items never make a wheel
     *  (FILTER-STACK-003). */
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
 * The active camera's Filter Stack: its ND wheels — drawn from Standard
 * and Filter Set sources — together with its mounted auxiliary filters,
 * all resolved against the inventory (FILTER-STACK-001). One to four
 * wheels are allowed without auxiliary filters, one to three with them.
 * The 30-stop cap on the combined active contributions and the
 * one-item-per-camera rule across wheels and auxiliary filters are
 * invariants of this type: construction goes through [validated], which
 * reports a violation as `null`, and every mutation returns either a
 * valid stack or a rejection. (iOS: `FilterStack`.)
 *
 * Two stacks are equal when their wheels and auxiliary filters are equal;
 * [rows] and [auxiliaryRows] are pure resolutions against an inventory.
 */
class FilterStack private constructor(
    val wheels: List<FilterWheel>,
    val rows: List<ResolvedFilterRow>,
    /** Mounted auxiliary filters in display order (Color, Effect, CPL,
     *  GND; then set order, then item order), never mount order; empty
     *  when the summary is hidden. */
    val auxiliaryFilters: List<MountedAuxiliaryFilter> = emptyList(),
    /** Resolved auxiliary filters parallel to [auxiliaryFilters]. */
    val auxiliaryRows: List<ResolvedAuxiliaryFilter> = emptyList(),
) {

    // MARK: Derived values

    /** Per-wheel active contributions in wheel order. */
    val contributions: List<Double> get() = rows.map { it.contributionStops }

    /** Per-item active contributions of the mounted auxiliary filters. */
    val auxiliaryContributions: List<Double> get() = auxiliaryRows.map { it.contributionStops }

    val hasAuxiliaryFilters: Boolean get() = auxiliaryFilters.isNotEmpty()

    /** The ND-wheel limit currently in force (FILTER-STACK-001). */
    val wheelLimit: Int get() = wheelLimit(hasAuxiliaryFilters)

    /**
     * The one effective value the calculation consumes: the sum of every
     * wheel's and every auxiliary filter's active contribution in
     * canonical stops (FILTER-STACK-004).
     */
    val effectiveStops: Double get() = contributions.sum() + auxiliaryContributions.sum()

    /**
     * Remaining budget for the wheel at [excludingWheelAt]: the cap minus
     * every OTHER wheel's and every auxiliary filter's active
     * contribution.
     */
    fun remainingBudget(excludingWheelAt: Int): Double {
        require(excludingWheelAt in wheels.indices) { "Wheel index out of range." }
        val others = rows.filterIndexed { index, _ -> index != excludingWheelAt }
            .sumOf { it.contributionStops }
        return TOTAL_LIMIT - others - auxiliaryContributions.sum()
    }

    /** Every physical item mounted on this camera — on a wheel other than
     *  [excludingWheelAt], or as an auxiliary filter (FILTER-AUX-004). */
    fun mountedItemIds(excludingWheelAt: Int?): Set<FilterItemId> =
        wheels.withIndex()
            .filter { (index, _) -> index != excludingWheelAt }
            .mapNotNull { (_, wheel) -> wheel.mountedItemId }
            .toSet() + auxiliaryFilters.map { it.itemId }

    // MARK: Row options

    /**
     * Picker rows for the wheel at [wheelIndex]. Standard wheels get the
     * shipping ladder truncated from the top to the remaining budget
     * (every row selectable); Filter Set wheels get Empty plus the set's
     * ND items (FILTER-STACK-003), each marked unavailable when its item
     * is mounted elsewhere on this camera — on another wheel or as an
     * auxiliary filter — or its contribution would exceed the cap. The wheel's own current row is always available
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
                for (item in filterSet.ndItems) {
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

    /** Whether another ND wheel fits under the applicable limit
     *  (FILTER-STACK-001). */
    val canAddWheel: Boolean get() = wheels.size < wheelLimit

    /**
     * Why [source] cannot add a usable wheel right now, or `null` when it
     * can: the applicable wheel limit, or no unmounted ND item of the set
     * whose value fits the remaining budget (FILTER-PLUS-005).
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
                val ndItems = filterSet.ndItems
                if (ndItems.isEmpty()) return FilterAddUnavailability.filterSetHasNoItems
                val mounted = mountedItemIds(excludingWheelAt = null)
                val unmounted = ndItems.filter { it.id !in mounted }
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
        return FilterStack(wheels + wheel, rows + row, auxiliaryFilters, auxiliaryRows)
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
            auxiliaryFilters,
            auxiliaryRows,
        )
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
        return FilterStackChange.Accepted(FilterStack(newWheels, newRows, auxiliaryFilters, auxiliaryRows))
    }

    // MARK: Replacing the mounted auxiliary filters

    /**
     * Writes the complete mounted auxiliary selection at once
     * (FILTER-AUX-003 Apply). Rejected — leaving the stack unchanged —
     * when a mount does not resolve, a physical item would be mounted
     * twice (across auxiliary filters and wheels), the current ND wheels
     * exceed the limit that applies with auxiliary filters, or the
     * combined contributions would exceed 30 stops. Any number of
     * auxiliary filters may be mounted; they are kept in display order.
     * Existing ND wheels are never removed or merged to make room.
     */
    fun replacingAuxiliaryFilters(
        mounts: List<MountedAuxiliaryFilter>,
        inventory: FilterInventory,
    ): FilterStackChange {
        val resolved = ArrayList<ResolvedAuxiliaryFilter>(mounts.size)
        val mounted = wheels.mapNotNull { it.mountedItemId }.toMutableSet()
        for (mount in mounts) {
            val row = resolvedAuxiliaryFilter(mount, inventory)
                ?: return FilterStackChange.Rejected(FilterStackRejection.unresolvedSelection)
            if (!mounted.add(mount.itemId)) {
                return FilterStackChange.Rejected(FilterStackRejection.itemAlreadyMounted)
            }
            resolved.add(row)
        }
        if (wheels.size > wheelLimit(mounts.isNotEmpty())) {
            return FilterStackChange.Rejected(FilterStackRejection.tooManyNDWheels)
        }
        if (!isWithinTotalLimit(contributions + resolved.map { it.contributionStops })) {
            return FilterStackChange.Rejected(FilterStackRejection.exceedsTotalLimit)
        }
        val ordered = displayOrdered(resolved, inventory)
        return FilterStackChange.Accepted(FilterStack(wheels, rows, ordered.map { it.mount }, ordered))
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

    /** Wheels in commit order; the auxiliary filters stay as they are
     *  (FILTER-STACK-005: they never take part in ND ordering). */
    fun sortedForCommit(inventory: FilterInventory): FilterStack {
        val permutation = commitSortPermutation(inventory)
        return FilterStack(
            permutation.map { wheels[it] },
            permutation.map { rows[it] },
            auxiliaryFilters,
            auxiliaryRows,
        )
    }

    override fun equals(other: Any?): Boolean =
        this === other ||
            (other is FilterStack && other.wheels == wheels && other.auxiliaryFilters == auxiliaryFilters)

    override fun hashCode(): Int = 31 * wheels.hashCode() + auxiliaryFilters.hashCode()

    override fun toString(): String = "FilterStack(wheels=$wheels, auxiliaryFilters=$auxiliaryFilters)"

    companion object {
        /** Absolute ND-wheel maximum, reached only without auxiliary filters. */
        val MAX_WHEEL_COUNT: Int = NdFilterStack.MAX_WHEEL_COUNT

        /** ND-wheel maximum while any auxiliary filter is mounted: the
         *  summary occupies one of the four spaces. */
        const val MAX_WHEEL_COUNT_WITH_AUXILIARY_FILTERS: Int = 3
        const val TOTAL_LIMIT: Double = 30.0

        /** The ND-wheel limit that applies with or without auxiliary
         *  filters (FILTER-STACK-001). */
        fun wheelLimit(hasAuxiliaryFilters: Boolean): Int =
            if (hasAuxiliaryFilters) MAX_WHEEL_COUNT_WITH_AUXILIARY_FILTERS else MAX_WHEEL_COUNT

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

        /** Validating construction without auxiliary filters. */
        fun validated(wheels: List<FilterWheel>, inventory: FilterInventory): FilterStack? =
            validated(wheels, emptyList(), inventory)

        /**
         * Validating construction: `null` when any wheel or auxiliary
         * filter fails to resolve, the wheel count is outside the
         * applicable limit, a physical item appears twice, or the
         * combined contributions exceed the cap. Any number of auxiliary
         * filters may be mounted; they are kept in display order.
         */
        fun validated(
            wheels: List<FilterWheel>,
            auxiliaryFilters: List<MountedAuxiliaryFilter>,
            inventory: FilterInventory,
        ): FilterStack? {
            if (wheels.size !in 1..wheelLimit(auxiliaryFilters.isNotEmpty())) return null
            val rows = ArrayList<ResolvedFilterRow>(wheels.size)
            val mounted = HashSet<FilterItemId>()
            for (wheel in wheels) {
                val row = resolvedRow(wheel, inventory) ?: return null
                val itemId = row.selection.itemId
                if (itemId != null && !mounted.add(itemId)) return null
                rows.add(row)
            }
            val auxiliaryRows = ArrayList<ResolvedAuxiliaryFilter>(auxiliaryFilters.size)
            for (mount in auxiliaryFilters) {
                val resolved = resolvedAuxiliaryFilter(mount, inventory) ?: return null
                if (!mounted.add(mount.itemId)) return null
                auxiliaryRows.add(resolved)
            }
            val contributions = rows.map { it.contributionStops } + auxiliaryRows.map { it.contributionStops }
            if (!isWithinTotalLimit(contributions)) return null
            val ordered = displayOrdered(auxiliaryRows, inventory)
            return FilterStack(wheels, rows, ordered.map { it.mount }, ordered)
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

        /** An ND wheel resolves ND items only (FILTER-STACK-003): a CPL,
         *  GND, Color, or Effect selection on a wheel is unresolvable. */
        internal fun resolvedRow(item: FilterItem, choice: FilterRowChoice): ResolvedFilterRow? {
            val behavior = item.behavior as? FilterItemBehavior.Fixed ?: return null
            if (choice !is FilterRowChoice.Fixed) return null
            val stops = behavior.value.canonicalStops ?: return null
            val selection = FilterWheelSelection.Item(FilterRowSelection(item.id, FilterRowChoice.Fixed))
            return ResolvedFilterRow(selection, stops, stops, item)
        }

        /** The single wheel row an ND item offers; auxiliary items never
         *  appear on a wheel (FILTER-ITEM-003, FILTER-STACK-003). */
        fun rows(forItem: FilterItem): List<ResolvedFilterRow> =
            listOfNotNull(resolvedRow(forItem, FilterRowChoice.Fixed))

        /**
         * Resolves one mounted auxiliary filter against the inventory:
         * `null` when its set or item no longer exists, the item is not an
         * auxiliary kind, or the choice does not fit the item — a CPL
         * choice that is no longer configured is never replaced by another
         * (FILTER-PERSIST-002). A CPL choice resolves to the configured
         * value it matches.
         */
        fun resolvedAuxiliaryFilter(
            mount: MountedAuxiliaryFilter,
            inventory: FilterInventory,
        ): ResolvedAuxiliaryFilter? {
            val filterSet = inventory.filterSet(mount.filterSetId) ?: return null
            val item = filterSet.item(mount.itemId) ?: return null
            val behavior = item.behavior
            val choice = mount.choice
            val resolved: Triple<AuxiliaryFilterChoice, Double, Double> = when {
                behavior is FilterItemBehavior.Cpl && choice is AuxiliaryFilterChoice.CplLoss -> {
                    val matched = behavior.choices.shootingChoices.firstOrNull {
                        abs(it - choice.stops) <= STABILITY_EPSILON
                    } ?: return null
                    Triple(AuxiliaryFilterChoice.CplLoss(matched), matched, matched)
                }

                behavior is FilterItemBehavior.Gnd && choice is AuxiliaryFilterChoice.Gnd -> {
                    val stops = behavior.value.canonicalStops ?: return null
                    val contribution = if (choice.mode == GndCalculationMode.applyFullValue) stops else 0.0
                    Triple(choice, contribution, stops)
                }

                choice is AuxiliaryFilterChoice.RegisteredLoss &&
                    (behavior is FilterItemBehavior.Color || behavior is FilterItemBehavior.Effect) -> {
                    val loss = behavior.exposureLoss ?: return null
                    if (!loss.isValid) return null
                    Triple(choice, loss.stops, loss.stops)
                }

                else -> return null
            }
            return ResolvedAuxiliaryFilter(
                mount = MountedAuxiliaryFilter(mount.filterSetId, mount.itemId, resolved.first),
                item = item,
                filterSetName = filterSet.name,
                filterSetColor = filterSet.color,
                contributionStops = resolved.second,
                registeredStops = resolved.third,
            )
        }

        /**
         * Safe re-resolution of persisted or previously valid auxiliary
         * filters (FILTER-PERSIST-002): an unresolvable mount — unknown
         * set or item, a CPL choice that no longer exists, a kind change —
         * is unmounted rather than substituted, a later duplicate of a
         * physical item is dropped, and the rest are put in display order.
         */
        fun normalizedAuxiliaryFilters(
            mounts: List<MountedAuxiliaryFilter>,
            inventory: FilterInventory,
        ): List<MountedAuxiliaryFilter> {
            val seen = HashSet<FilterItemId>()
            val normalized = mounts.mapNotNull { mount ->
                resolvedAuxiliaryFilter(mount, inventory)?.takeIf { seen.add(mount.itemId) }
            }
            return displayOrdered(normalized, inventory).map { it.mount }
        }

        /**
         * The stable display order of mounted auxiliary filters
         * (FILTER-AUX-002): Color, Effect, CPL, GND; within one kind the
         * Filter Set order (the camera's candidate sets follow it), then
         * the item order inside the set. Mount order never matters.
         */
        fun displayOrdered(
            rows: List<ResolvedAuxiliaryFilter>,
            inventory: FilterInventory,
        ): List<ResolvedAuxiliaryFilter> {
            fun kindRank(kind: FilterItemKind): Int = when (kind) {
                FilterItemKind.color -> 0
                FilterItemKind.effect -> 1
                FilterItemKind.cpl -> 2
                FilterItemKind.gnd -> 3
                FilterItemKind.fixed -> 4
            }
            fun setIndex(row: ResolvedAuxiliaryFilter): Int =
                inventory.filterSets.indexOfFirst { it.id == row.mount.filterSetId }.takeIf { it >= 0 } ?: Int.MAX_VALUE
            fun itemIndex(row: ResolvedAuxiliaryFilter): Int =
                inventory.filterSet(row.mount.filterSetId)?.items
                    ?.indexOfFirst { it.id == row.mount.itemId }?.takeIf { it >= 0 } ?: Int.MAX_VALUE
            return rows.sortedWith(
                compareBy<ResolvedAuxiliaryFilter> { kindRank(it.item.behavior.kind) }
                    .thenBy { setIndex(it) }
                    .thenBy { itemIndex(it) },
            )
        }

        /**
         * Splits a legacy mixed stack into its two halves
         * (FILTER-PERSIST-002): a wheel mounting a CPL or GND row becomes
         * an auxiliary filter with the same item, choice, and mode, and
         * that wheel is dropped; every other wheel stays. A stack that
         * held only auxiliary rows receives one Standard 0 wheel. The
         * result is not yet validated against the inventory.
         */
        fun migratingLegacyWheels(wheels: List<FilterWheel>): Pair<List<FilterWheel>, List<MountedAuxiliaryFilter>> {
            val remaining = ArrayList<FilterWheel>()
            val auxiliary = ArrayList<MountedAuxiliaryFilter>()
            for (wheel in wheels) {
                val selection = (wheel.selection as? FilterWheelSelection.Item)?.selection
                val filterSetId = wheel.source.filterSetId
                if (selection != null && filterSetId != null) {
                    when (val choice = selection.choice) {
                        is FilterRowChoice.CplLoss -> {
                            auxiliary.add(
                                MountedAuxiliaryFilter(filterSetId, selection.itemId, AuxiliaryFilterChoice.CplLoss(choice.stops)),
                            )
                            continue
                        }

                        is FilterRowChoice.Gnd -> {
                            auxiliary.add(
                                MountedAuxiliaryFilter(filterSetId, selection.itemId, AuxiliaryFilterChoice.Gnd(choice.mode)),
                            )
                            continue
                        }

                        is FilterRowChoice.Fixed -> Unit
                    }
                }
                remaining.add(wheel)
            }
            if (remaining.isEmpty()) remaining.add(FilterWheel.standard(0.0))
            return remaining to auxiliary
        }

        /**
         * Role correction after an item's kind changes (FILTER-ITEM-003,
         * FILTER-ITEM-005): a selection follows its physical item into the
         * item's new role instead of being dropped. A wheel mounting an
         * item that is now auxiliary leaves the ND row and the item is
         * mounted as an auxiliary filter with its default choice (a legacy
         * CPL / GND wheel row keeps its choice); an auxiliary mount whose
         * item is now ND becomes a Filter Set ND wheel at the end of the
         * row; an auxiliary mount whose item changed to another auxiliary
         * kind takes that kind's default choice. Mounts of unknown sets or
         * items are left for normal re-resolution. A result with no wheel
         * gets one Standard 0 wheel. Limits are not checked here; callers
         * validate.
         */
        fun reassigningRoles(
            wheels: List<FilterWheel>,
            auxiliaryFilters: List<MountedAuxiliaryFilter>,
            inventory: FilterInventory,
        ): RoleReassignment {
            fun item(itemId: FilterItemId, filterSetId: FilterSetId): FilterItem? =
                inventory.filterSet(filterSetId)?.item(itemId)
            val keptWheels = ArrayList<FilterWheel>()
            val origins = ArrayList<Int?>()
            val mounts = auxiliaryFilters.toMutableList()
            wheels.forEachIndexed { index, wheel ->
                val selection = (wheel.selection as? FilterWheelSelection.Item)?.selection
                val filterSetId = wheel.source.filterSetId
                val mountedItem = if (selection != null && filterSetId != null) item(selection.itemId, filterSetId) else null
                if (selection != null && filterSetId != null && mountedItem != null && mountedItem.behavior.kind.isAuxiliary) {
                    if (mounts.none { it.itemId == selection.itemId }) {
                        val choice = carriedChoice(selection.choice, mountedItem)
                            ?: MountedAuxiliaryFilter.initialChoice(mountedItem)
                        if (choice != null) mounts.add(MountedAuxiliaryFilter(filterSetId, selection.itemId, choice))
                    }
                    return@forEachIndexed
                }
                keptWheels.add(wheel)
                origins.add(index)
            }
            val keptMounts = ArrayList<MountedAuxiliaryFilter>()
            for (mount in mounts) {
                val mountedItem = item(mount.itemId, mount.filterSetId)
                if (mountedItem == null) {
                    keptMounts.add(mount)
                    continue
                }
                if (!mountedItem.behavior.kind.isAuxiliary) {
                    keptWheels.add(
                        FilterWheel(
                            FilterSource.FilterSet(mount.filterSetId),
                            FilterWheelSelection.Item(FilterRowSelection(mount.itemId, FilterRowChoice.Fixed)),
                        ),
                    )
                    origins.add(null)
                } else if (!choiceFitsKind(mount.choice, mountedItem)) {
                    MountedAuxiliaryFilter.initialChoice(mountedItem)?.let {
                        keptMounts.add(MountedAuxiliaryFilter(mount.filterSetId, mount.itemId, it))
                    }
                } else {
                    keptMounts.add(mount)
                }
            }
            if (keptWheels.isEmpty()) {
                keptWheels.add(FilterWheel.standard(0.0))
                origins.clear()
                origins.add(null)
            }
            return RoleReassignment(keptWheels, keptMounts, origins)
        }

        /** A legacy wheel row's CPL or GND choice, when it matches the
         *  item's current kind. */
        private fun carriedChoice(choice: FilterRowChoice, item: FilterItem): AuxiliaryFilterChoice? = when {
            choice is FilterRowChoice.CplLoss && item.behavior is FilterItemBehavior.Cpl ->
                AuxiliaryFilterChoice.CplLoss(choice.stops)
            choice is FilterRowChoice.Gnd && item.behavior is FilterItemBehavior.Gnd ->
                AuxiliaryFilterChoice.Gnd(choice.mode)
            else -> null
        }

        /** Whether an auxiliary choice belongs to the item's kind; a CPL
         *  value that is no longer configured still counts as the CPL
         *  kind, so it is reported by re-resolution instead of being
         *  replaced. */
        private fun choiceFitsKind(choice: AuxiliaryFilterChoice, item: FilterItem): Boolean =
            when (choice) {
                is AuxiliaryFilterChoice.CplLoss -> item.behavior is FilterItemBehavior.Cpl
                is AuxiliaryFilterChoice.Gnd -> item.behavior is FilterItemBehavior.Gnd
                is AuxiliaryFilterChoice.RegisteredLoss ->
                    item.behavior is FilterItemBehavior.Color || item.behavior is FilterItemBehavior.Effect
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

/**
 * The stack after [FilterStack.reassigningRoles]: wheels and mounted
 * auxiliary filters with every selection in its item's current role,
 * plus, per returned wheel, the index of the input wheel it came from
 * (`null` for a wheel created from an auxiliary mount).
 * (iOS: `RoleReassignment`.)
 */
data class RoleReassignment(
    val wheels: List<FilterWheel>,
    val auxiliaryFilters: List<MountedAuxiliaryFilter>,
    val wheelOrigins: List<Int?>,
)
