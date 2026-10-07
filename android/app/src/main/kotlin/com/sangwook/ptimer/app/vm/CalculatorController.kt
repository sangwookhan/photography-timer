// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.app.vm

import androidx.annotation.VisibleForTesting
import com.sangwook.ptimer.app.calc.ShootingCalculator
import com.sangwook.ptimer.app.calc.ShootingResult
import com.sangwook.ptimer.core.customfilm.CustomFormulaFilmInput
import com.sangwook.ptimer.core.customfilm.CustomTableFilmInput
import com.sangwook.ptimer.core.exposure.ExposureCalculator
import com.sangwook.ptimer.core.exposure.ExposureScale
import com.sangwook.ptimer.core.exposure.FilterAddUnavailability
import com.sangwook.ptimer.core.exposure.FilterInventory
import com.sangwook.ptimer.core.exposure.FilterItem
import com.sangwook.ptimer.core.exposure.FilterItemId
import com.sangwook.ptimer.core.exposure.FilterSet
import com.sangwook.ptimer.core.exposure.FilterSetColor
import com.sangwook.ptimer.core.exposure.FilterSetId
import com.sangwook.ptimer.core.exposure.FilterSource
import com.sangwook.ptimer.core.exposure.FilterStack
import com.sangwook.ptimer.core.exposure.FilterStackChange
import com.sangwook.ptimer.core.exposure.FilterStackRejection
import com.sangwook.ptimer.core.exposure.FilterSummaryEntry
import com.sangwook.ptimer.core.exposure.FilterWheel
import com.sangwook.ptimer.core.exposure.FilterWheelSelection
import com.sangwook.ptimer.core.exposure.MountedAuxiliaryFilter
import com.sangwook.ptimer.core.exposure.NDNotationFormatter
import com.sangwook.ptimer.core.exposure.NDNotationMode
import com.sangwook.ptimer.core.exposure.NdFilterStack
import com.sangwook.ptimer.core.reciprocity.AlternateReciprocityModels
import com.sangwook.ptimer.core.reciprocity.ReciprocityAuthority
import com.sangwook.ptimer.core.reciprocity.calculatedCorrectedSeconds
import com.sangwook.ptimer.core.reciprocity.FilmIdentity
import com.sangwook.ptimer.core.reciprocity.FilmIdentityKind
import com.sangwook.ptimer.core.reciprocity.ReciprocityDetailsDisplayState
import com.sangwook.ptimer.core.reciprocity.ReciprocityDetailsPresenter
import com.sangwook.ptimer.core.persistence.PersistentSlotSession
import com.sangwook.ptimer.core.reciprocity.ReciprocityProfile
import com.sangwook.ptimer.core.slots.CameraSlotId
import com.sangwook.ptimer.core.slots.CameraSlotIdentity
import com.sangwook.ptimer.core.slots.CameraSlotSession
import com.sangwook.ptimer.core.slots.SlotCalculatorSnapshot
import com.sangwook.ptimer.core.slots.offeredFilterSources
import com.sangwook.ptimer.core.slots.restoredCandidateFilterSetIds
import com.sangwook.ptimer.core.slots.restoredFilterStack
import com.sangwook.ptimer.core.slots.restoredLastFilterSource
import com.sangwook.ptimer.core.slots.storedCandidateFilterSetIds
import com.sangwook.ptimer.core.slots.storedFilterReferences
import com.sangwook.ptimer.core.slots.writingFilterStack
import kotlin.math.abs
import com.sangwook.ptimer.core.target.TargetShutterDisplayState
import com.sangwook.ptimer.core.target.TargetShutterPresenter
import com.sangwook.ptimer.core.timer.TimerIdentity
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

data class FilmOption(
    val id: String?,
    val name: String,
    val manufacturer: String? = null,
    val iso: Int? = null,
    val isUnofficial: Boolean = false,
    val hasReciprocityCurve: Boolean = false,
    val isCustom: Boolean = false,
)

data class ModelOption(val id: String, val label: String)

data class SlotTab(val id: CameraSlotId, val displayName: String, val isActive: Boolean)

/** Immutable state the shooting calculator surface renders. */
data class CalculatorUiState(
    val slots: List<SlotTab>,
    val activeSlotName: String,
    val shutterLabels: List<String>,
    val shutterIndex: Int,
    val ndLabels: List<String>,
    val ndIndex: Int,
    /** Mixed Filter Stack (PTIMER-221): 1..4 wheels in display order. */
    val filterWheels: List<FilterWheelUiState> = emptyList(),
    /** Plus wheel: source browsing, remembered source, add availability. */
    val plus: FilterPlusUiState = FilterPlusUiState(false, emptyList(), 0, isQuiet = false),
    /** One-row status region: idle summary, moving row, rejection, total. */
    val filterStatus: FilterStatusUiState = FilterStatusUiState(null, null, null, "0", false),
    /** Main summary of the mounted auxiliary filters; `null` hides the
     *  space (FILTER-AUX-001). */
    val auxiliarySummary: AuxiliaryFilterSummaryDisplayState? = null,
    /** The mounted auxiliary filters in display order — what a Shooting
     *  Filters session starts from (FILTER-AUX-003). */
    val mountedAuxiliaryFilters: List<MountedAuxiliaryFilter> = emptyList(),
    /** The camera's candidate Filter Sets in their selection order
     *  (FILTER-CAMERA-001, FILTER-SET-004). */
    val candidateFilterSetIds: List<FilterSetId> = emptyList(),
    /** Stack total in stops ("18", "13.2"); null below two wheels. */
    val ndTotalStopsText: String? = null,
    /** True when the LIVE total (pending selections included, the
     *  same basis as [ndTotalStopsText]) sits at the 30-stop cap. */
    val ndTotalIsMaximum: Boolean = false,
    val filmOptions: List<FilmOption>,
    val selectedFilmId: String?,
    val selectedFilmName: String,
    val modelOptions: List<ModelOption>,
    val selectedProfileId: String?,
    val hasFilm: Boolean,
    /**
     * True when the slot has anything a reset would clear: non-default
     * settings (film, ND, shutter, target) or a custom camera name.
     * Gates the Reset affordance so it shows only when actionable
     * (matches iOS).
     */
    val canReset: Boolean,
    /** Current ND notation display mode; drives the wheel labels + the toggle (PTIMER-187). */
    val ndNotationMode: NDNotationMode = NDNotationMode.DEFAULT,
    val adjustedText: String,
    /** Whole-seconds comparison (e.g. "34953s") for clock-band values; null otherwise. */
    val adjustedSecondsText: String?,
    val adjustedStartEnabled: Boolean,
    val correctedText: String?,
    val correctedSecondsText: String?,
    val correctedStartEnabled: Boolean,
    val confidenceLabel: String?,
    val startEnabled: Boolean,
    val hint: String?,
    val targetDisplay: TargetShutterDisplayState,
    /**
     * Per-slot read-only states in [slots] order, so the camera pager can render
     * each page from its own slot instead of cloning the active page during a
     * swipe. Populated only on the top-level (active) state; each entry here has
     * an empty list.
     */
    val slotStates: List<CalculatorUiState> = emptyList(),
) {
    /** The wheel under a finger, found by its stable id so a settled
     *  reorder can never point it at a different wheel; `null` at rest. */
    val movingFilterWheel: FilterWheelUiState?
        get() = filterStatus.movingWheelId?.let { id -> filterWheels.firstOrNull { it.id == id } }

    /** Filter spaces the row lays out: the ND wheels plus the auxiliary
     *  summary, which occupies one space whatever its item count
     *  (FILTER-STACK-001/007). */
    val occupiedFilterSpaces: Int
        get() = filterWheels.size + if (auxiliarySummary != null) 1 else 0
}

/**
 * Owns the shooting calculator surface across camera slots: base-shutter /
 * filter wheel state, film + alternate-model selection, and the derived
 * result for the active slot. Per-slot state lives in the [CameraSlotSession],
 * which owns a stable snapshot for every slot; the controller reads and mutates
 * the active slot's snapshot in place, so a slot switch just re-points the
 * active slot without capturing or restoring live state.
 *
 * It is also the single facade for the mixed Filter Stack (PTIMER-221): it
 * forwards every Filter Set / Filter Item command to [inventoryModel] and then
 * re-resolves the active stack AND every inactive slot snapshot against the new
 * inventory, because it is the one place that reads both. Start delegates the
 * computed duration + captured identity to the timer workspace via [onStart].
 * Pure of Android; deterministic and unit-testable.
 */
class CalculatorController(
    films: List<FilmIdentity>,
    private val calculator: ShootingCalculator = ShootingCalculator(),
    private val exposure: ExposureCalculator = ExposureCalculator(),
    private val onStart: (duration: Double, identity: TimerIdentity) -> Unit = { _, _ -> },
    initialSession: PersistentSlotSession? = null,
    /** The user's Filter Sets and physical items (FILTER-SET / FILTER-ITEM). */
    private val inventoryModel: FilterInventoryModel = FilterInventoryModel(),
    /** Scope that owns the filter cleanup timer (PTIMER-199 §4.2.2 /
     *  PTIMER-223): the ViewModel scope in production, so it survives
     *  configuration changes with the state it judges. Null keeps the timer disarmed and pure
     *  state tests drive [runNdCleanupIfQuiet] directly. */
    private val ndCleanupScope: CoroutineScope? = null,
    private val ndCleanupDelayMillis: Long = 4_000,
    /** Words for the start-time reference string (FILTER-PERSIST-003),
     *  read once per timer start so it captures the language then in
     *  use. Production supplies the user's; the canonical-English
     *  default keeps this type free of Android resources. */
    private val referenceVocabulary: () -> FilterReferenceVocabulary = {
        FilterReferenceVocabulary.canonicalEnglish
    },
) {
    // Catalog + custom films; replaced via [setFilms] when the custom library changes.
    private var films: List<FilmIdentity> = films

    private val shutterLabels = ExposureScale.oneThirdStopShutterCameraLabels

    /**
     * Ordered ND stop values shown on the legacy single wheel: whole stops
     * 0…30. The wheel index is a position into this list, decoupled from
     * the stop value it carries.
     */
    private val ndStopValues: List<Double> = ExposureScale.shippingNDLadder.map { it.stops }
    private val defaultShutterIndex = shutterLabels.indexOf("1/30").coerceAtLeast(0)

    // App-global ND notation display mode (PTIMER-187); display-only, never feeds calc.
    private var ndNotationMode: NDNotationMode = NDNotationMode.DEFAULT

    /** ND wheel labels for the current notation mode (same length/order as the stop ladder). */
    private fun ndLabels(): List<String> =
        ndStopValues.map { NDNotationFormatter.display(it, ndNotationMode).value }

    /** Wheel position for a canonical stop value: the nearest ladder entry. */
    private fun ndWheelIndex(stops: Double): Int =
        ndStopValues.indices.minByOrNull { abs(ndStopValues[it] - stops) } ?: 0

    // --- Filter Stack interaction state (PTIMER-199 v2 / PTIMER-221) ---

    /** The user's Filter Sets and physical items. */
    private val inventory: FilterInventory get() = inventoryModel.inventory.value

    /** Stable identity per active-slot wheel (101+, never index-like). */
    private var ndWheelIds: List<Int> = emptyList()
    private var nextNdWheelId = 101

    /** Wheels currently in motion or under a finger (first-class
     *  Compose signals reported by the UI). Structural mutation and
     *  the set commit require this to be empty. */
    private val activeNdWheelIds = mutableSetOf<Int>()

    /** One wheel's selection waiting for the set commit. */
    private data class PendingNdCommit(
        val selection: FilterWheelSelection,
        /** From an assistive adjustment. No gesture traversed anything,
         *  so it gets NO sighted fallback — FILTER-A11Y-004 stays
         *  untouched by FILTER-STACK-004. */
        val isAssistive: Boolean = false,
    )

    /** Selections recorded while wheels move, applied as ONE SET when
     *  the last wheel goes quiet. Insertion order = settle order. */
    private val pendingNdCommits = LinkedHashMap<Int, PendingNdCommit>()

    /** FILTER-A11Y-006 on top of FILTER-STACK-005's settle order. */
    private enum class FilterStackOrdering {
        /** Settles sort the stack as usual. */
        live,

        /** A screen reader's touch exploration is on: the complete
         *  order is frozen. */
        frozen,

        /** Touch exploration went off: one reorder runs as soon as no
         *  wheel is moving and nothing waits to commit. */
        reorderPending,
    }

    private var filterStackOrdering = FilterStackOrdering.live

    /**
     * The FILTER-STACK-005 settle order with FILTER-A11Y-006 layered on
     * top, in one place: returns [stack] rearranged into committed
     * source-group order together with [ids] carried through the same
     * permutation, so every wheel keeps its stable identity. A frozen —
     * or about-to-reconcile — stack is returned untouched, and so is one
     * whose identity list has drifted out of step with its wheels.
     */
    private fun applyingSettledOrder(
        stack: FilterStack,
        ids: List<Int>,
        inventory: FilterInventory,
    ): Pair<FilterStack, List<Int>> {
        if (filterStackOrdering != FilterStackOrdering.live) return stack to ids
        if (ids.size != stack.wheels.size) return stack to ids
        val permutation = stack.commitSortPermutation(inventory)
        return stack.sortedForCommit(inventory) to permutation.map { ids[it] }
    }

    private var filterRejectionNotice: FilterRejectionNotice? = null
    /** Increases with every refusal, so a new one never reuses the
     *  number of one the view has already timed out. */
    private var filterRejectionSequence = 0
    private val _emptyWheelRemovals = MutableSharedFlow<Int>(extraBufferCapacity = 8)

    /**
     * One event per cleanup that ACTUALLY removed wheels, carrying how
     * many (FILTER-STACK-006). A cleanup that was scheduled, deferred or
     * found nothing emits nothing. The app host announces each event
     * once while a screen reader is active.
     */
    val emptyWheelRemovals: SharedFlow<Int> = _emptyWheelRemovals.asSharedFlow()

    private fun makeNdWheelId(): Int = nextNdWheelId++

    /** The active slot's committed mixed Filter Stack. */
    private fun activeFilterStack(): FilterStack = filterStackOf(session.activeSnapshot)

    /**
     * Any slot's committed stack — ND wheels and mounted auxiliary
     * filters — re-resolved against the live inventory. Restore falls
     * back to a valid Standard-only stack, so this never fails.
     */
    private fun filterStackOf(snapshot: SlotCalculatorSnapshot): FilterStack =
        snapshot.restoredFilterStack(inventory)

    /** The active camera's candidate Filter Sets (FILTER-CAMERA-001). */
    private val candidateFilterSetIds: List<FilterSetId>
        get() = session.activeSnapshot.restoredCandidateFilterSetIds(inventory)

    /** Standard, then the active camera's candidate sets that hold ND
     *  items (FILTER-PLUS-001). */
    private val filterSources: List<FilterSource>
        get() = inventory.offeredFilterSources(candidateFilterSetIds)

    /** The active camera's remembered Filter Source (FILTER-PLUS-004). */
    private val lastFilterSource: FilterSource
        get() = session.activeSnapshot.restoredLastFilterSource(inventory)

    /** Regenerates wheel identities for the active slot's stack. */
    private fun syncNdWheelIds() {
        val count = activeFilterStack().wheels.size
        if (ndWheelIds.size != count) {
            ndWheelIds = List(count) { makeNdWheelId() }
        }
        rearmNdCleanupTimer()
    }

    /** Controller-owned self-cleaning timer for committed cleanable
     *  wheels. Every (re)arm cancels the previous job and grants a
     *  FULL grace period; it happens on committed stack writes and
     *  wheel-identity re-syncs — never on live-preview values or
     *  touch/scroll signals. Interaction defers cleanup through the
     *  fire-time judgment in [runNdCleanupIfQuiet] (busy at fire →
     *  wait again), not by rescheduling. */
    private var ndCleanupJob: Job? = null

    private fun rearmNdCleanupTimer() {
        ndCleanupJob?.cancel()
        ndCleanupJob = null
        val scope = ndCleanupScope ?: return
        if (!activeFilterStack().canRemoveEmptyWheel) return
        ndCleanupJob = scope.launch {
            while (true) {
                delay(ndCleanupDelayMillis)
                // Fires blind; the judgment decides. A refusal (a
                // wheel was moving) re-arms; a stack that stopped
                // being cleanable ends the loop.
                if (runNdCleanupIfQuiet()) break
                if (!activeFilterStack().canRemoveEmptyWheel) break
            }
        }
    }

    /** Slot switches, resets, and inventory edits discard in-flight selections. */
    private fun clearNdInteraction() {
        activeNdWheelIds.clear()
        pendingNdCommits.clear()
    }

    private fun isSaturated(stack: FilterStack): Boolean =
        stack.effectiveStops >= FilterStack.TOTAL_LIMIT - ExposureCalculator.STABILITY_EPSILON

    /**
     * Whether a cleanable wheel could still accept a USABLE row: a
     * Standard 0 wheel needs a ladder value above 0 inside its remaining
     * budget; an Empty Filter Set wheel needs any selectable item row — a
     * Record-only row counts, so it stays usable even at the 30-stop
     * total (FILTER-PLUS-005 / FILTER-STACK-006).
     */
    private fun cleanableWheelIsUsable(stack: FilterStack, index: Int): Boolean {
        val wheel = stack.wheels.getOrNull(index) ?: return false
        if (!wheel.isCleanable) return false
        return stack.rowOptions(index, inventory).any { option ->
            option.isAvailable && when (val selection = option.selection) {
                is FilterWheelSelection.Standard -> selection.stops > 0
                is FilterWheelSelection.Empty -> false
                is FilterWheelSelection.Item -> true
            }
        }
    }

    /**
     * Writes the committed stack and the camera's remembered source. The
     * pre-Filter-Set fields keep describing only the Standard wheels, so
     * an older build restores a valid Standard-only projection
     * (FILTER-PERSIST-001).
     */
    private fun writeFilterStack(stack: FilterStack, lastSource: FilterSource = lastFilterSource) {
        val current = inventory
        session.updateActiveSnapshot { it.writingFilterStack(stack, lastSource, candidatesFor(it, stack, current)) }
        publish()
        rearmNdCleanupTimer()
    }

    /** UI signal: the wheel at [wheelId] is in motion / under a
     *  finger (true) or has gone quiet (false). Quiescence triggers
     *  the set commit. */
    fun setNdWheelActive(wheelId: Int, isActive: Boolean) {
        if (isActive) {
            if (wheelId in ndWheelIds) activeNdWheelIds.add(wheelId)
        } else {
            activeNdWheelIds.remove(wheelId)
            // The barrier applies pendings in SETTLE order — the order
            // wheels went quiet — not last-value-change order. Going
            // quiet moves this wheel's entry to the map's tail, so once
            // every wheel has settled the LinkedHashMap order IS the
            // settle order (a wheel that pended without ever being
            // active keeps its value-change position, which is when it
            // settled).
            pendingNdCommits.remove(wheelId)?.let { pendingNdCommits[wheelId] = it }
            commitNdSetIfQuiet()
        }
        // Activity flips the quiet-gated availability flag (plus.canAdd)
        // even when no value has changed yet; equal states dedup downstream.
        publish()
    }

    /** SnapWheel emission for one wheel: records the selection (live
     *  display + pending set commit) by ROW INDEX into that wheel's
     *  current options. A selection equal to the wheel's committed row
     *  clears the record — programmatic re-centers and return-to-committed
     *  scrolls leave nothing pending. */
    fun setNdWheelValue(wheelId: Int, rowIndex: Int) {
        val wheelIndex = ndWheelIds.indexOf(wheelId)
        if (wheelIndex < 0) return
        val stack = activeFilterStack()
        if (wheelIndex !in stack.wheels.indices) return
        val selection = stack.rowOptions(wheelIndex, inventory).getOrNull(rowIndex)?.selection ?: return
        pendingNdCommits.remove(wheelId)
        if (!isSameSelection(selection, stack.wheels[wheelIndex].selection)) {
            // Provisional position: last-change order stands in until
            // the wheel settles, when setNdWheelActive(_, false) moves
            // the entry to the tail so the barrier applies in true
            // settle order.
            // A sighted emission replaces any assistive entry on this wheel.
            pendingNdCommits[wheelId] = PendingNdCommit(selection)
        }
        publish()
        commitNdSetIfQuiet()
    }

    /**
     * The set commit (barrier): applies pendings in settle order (the
     * domain refuses over-30 and already-mounted applications; a sighted
     * settle then falls back to the nearest selectable row it traversed),
     * sorts once with identity following the permutation unless ordering
     * is frozen, sheds UNUSABLE cleanable wheels when the set saturates
     * the cap, and writes once.
     */
    private fun commitNdSetIfQuiet() {
        if (activeNdWheelIds.isNotEmpty()) return
        if (pendingNdCommits.isEmpty()) return
        val pendings = LinkedHashMap(pendingNdCommits)
        pendingNdCommits.clear()

        val current = inventory
        var applied = activeFilterStack()
        var ids = ndWheelIds
        var rejection: FilterStackRejection? = null
        for ((wheelId, pending) in pendings) {
            val selection = pending.selection
            val index = ids.indexOf(wheelId)
            if (index < 0 || index !in applied.wheels.indices) continue
            when (val change = applied.replacingWheel(index, selection, current)) {
                is FilterStackChange.Accepted -> applied = change.stack
                is FilterStackChange.Rejected -> {
                    val fallback = sightedFallbackSelection(
                        stack = applied,
                        index = index,
                        attempted = selection,
                        isAssistive = pending.isAssistive,
                    )
                    val retried = fallback?.let { applied.replacingWheel(index, it, current) }
                    if (retried is FilterStackChange.Accepted) {
                        applied = retried.stack
                    } else {
                        rejection = change.reason
                    }
                }
            }
        }

        // FILTER-A11Y-006: a frozen (or about-to-reconcile) stack keeps
        // its complete spatial order through the commit.
        applyingSettledOrder(applied, ids, current).let { (sorted, sortedIds) ->
            applied = sorted
            ids = sortedIds
        }

        // A0: a set that saturates the 30-stop budget sheds its leftover
        // UNUSABLE cleanable wheels immediately. An Empty Filter Set wheel
        // that can still mount a Record-only item is NOT unusable
        // (FILTER-PLUS-005) and keeps the normal idle interval.
        var removed = 0
        if (isSaturated(applied)) {
            val shed = shedUnusableCleanableWheels(applied, ids)
            removed = ids.size - shed.second.size
            applied = shed.first
            ids = shed.second
        }

        ndWheelIds = ids
        writeFilterStack(applied)
        if (removed > 0) noteEmptyFilterWheelRemoval(removed)
        if (rejection != null) showFilterRejectionNotice(rejection)
    }

    /**
     * The row a refused sighted settle falls back to (FILTER-STACK-004):
     * walking the wheel's rows from the attempted final row back toward
     * the previously committed row, the first selectable row strictly
     * inside that interval. Never beyond the attempted row, never
     * wrapping, never the committed row itself (which "keeps the previous
     * selection" with the reason instead). Only for a Filter Set wheel
     * whose commit followed motion; an assistive commit had no traversal
     * and keeps the plain refusal.
     */
    private fun sightedFallbackSelection(
        stack: FilterStack,
        index: Int,
        attempted: FilterWheelSelection,
        isAssistive: Boolean,
    ): FilterWheelSelection? {
        if (isAssistive) return null
        val wheel = stack.wheels[index]
        if (wheel.source !is FilterSource.FilterSet) return null
        val options = stack.rowOptions(index, inventory)
        val attemptedIndex = options.indexOfFirst { it.selection == attempted }
        val committedIndex = options.indexOfFirst { it.selection == wheel.selection }
        if (attemptedIndex < 0 || committedIndex < 0 || attemptedIndex == committedIndex) return null
        val towardCommitted = if (attemptedIndex > committedIndex) -1 else 1
        var candidate = attemptedIndex + towardCommitted
        while (candidate != committedIndex) {
            if (options[candidate].isAvailable) return options[candidate].selection
            candidate += towardCommitted
        }
        return null
    }

    /** Removes every cleanable wheel that can hold no usable row, keeping
     *  at least one wheel; identities follow their wheels. */
    private fun shedUnusableCleanableWheels(
        stack: FilterStack,
        ids: List<Int>,
    ): Pair<FilterStack, List<Int>> {
        var current = stack
        var currentIds = ids
        while (current.wheels.size > 1 && currentIds.size == current.wheels.size) {
            val index = current.wheels.indices.lastOrNull {
                current.wheels[it].isCleanable && !cleanableWheelIsUsable(current, it)
            } ?: break
            current = current.removingEmptyWheel(at = index)
            currentIds = currentIds.filterIndexed { i, _ -> i != index }
        }
        return current to currentIds
    }

    /**
     * Adds one wheel for [source] (FILTER-PLUS-003/004/005): Standard 0 or
     * Filter Set Empty. Refused — creating no wheel and leaving the stack,
     * the total, and the remembered source untouched — while the machine
     * is busy, or when the source can hold no usable row, in which case
     * the reason surfaces in the status region. Only a successful addition
     * moves the camera's remembered source.
     *
     * The new wheel enters the settled FILTER-STACK-005 order at once:
     * its own sort value is zero, so it sorts last inside its group, but
     * its GROUP takes its subtotal position immediately rather than
     * waiting for some other wheel to move. FILTER-A11Y-006 still wins —
     * while the order is frozen (or a reconciliation is queued) the
     * addition changes membership only and triggers no subtotal-based
     * reorder.
     */
    fun addFilterWheel(source: FilterSource = lastFilterSource) {
        if (activeNdWheelIds.isNotEmpty() || pendingNdCommits.isNotEmpty()) return
        val current = inventory
        // Only a source this camera offers: Standard or an ND-holding
        // candidate set (FILTER-PLUS-001).
        if (source !in filterSources) return
        val stack = activeFilterStack()
        val unavailability = stack.addUnavailability(source, current)
        if (unavailability != null) {
            showFilterAddUnavailabilityNotice(unavailability)
            return
        }
        val (applied, ids) = applyingSettledOrder(
            stack.addingWheel(source, current),
            ndWheelIds + makeNdWheelId(),
            current,
        )
        ndWheelIds = ids
        writeFilterStack(applied, lastSource = source)
    }

    /** Overscroll-past-zero removal, validate-first: the pull is
     *  accepted only when no OTHER wheel is in motion, NO selections
     *  are pending (a removal must never flush another wheel's
     *  pending commit), the pulled wheel exists, its COMMITTED row is
     *  cleanable (Standard 0 or Empty — never a mounted item), and it
     *  is not the last wheel. A refused pull mutates no state at all —
     *  transient or committed — so the set commit machinery proceeds
     *  exactly as if the pull never happened. */
    fun removeNdWheelFromOverscroll(wheelId: Int) {
        if ((activeNdWheelIds - wheelId).isNotEmpty()) return
        if (pendingNdCommits.isNotEmpty()) return
        val index = ndWheelIds.indexOf(wheelId)
        val stack = activeFilterStack()
        if (index < 0 || index !in stack.wheels.indices) return
        if (!stack.wheels[index].isCleanable || stack.wheels.size <= 1) return
        // Validated: remove exactly the pulled wheel. Its own active
        // entry goes with it (the wheel is leaving the screen); with
        // no pendings there is nothing to flush.
        activeNdWheelIds.remove(wheelId)
        ndWheelIds = ndWheelIds.filterIndexed { i, _ -> i != index }
        writeFilterStack(stack.removingEmptyWheel(at = index))
    }

    /** A2 cleanup in one action (the fire-time timer's execution
     *  path): removes ALL cleanable wheels when a
     *  non-cleanable wheel exists; keeps exactly one otherwise. */
    fun cleanupEmptyNdWheels() {
        if (activeNdWheelIds.isNotEmpty() || pendingNdCommits.isNotEmpty()) return
        var stack = activeFilterStack()
        if (!stack.canRemoveEmptyWheel) return
        var ids = ndWheelIds
        var removed = 0
        while (stack.canRemoveEmptyWheel && ids.size == stack.wheels.size) {
            val index = stack.wheels.indexOfLast { it.isCleanable }
            stack = stack.removingEmptyWheel(at = index)
            ids = ids.filterIndexed { i, _ -> i != index }
            removed++
        }
        ndWheelIds = ids
        writeFilterStack(stack)
        if (removed > 0) noteEmptyFilterWheelRemoval(removed)
    }

    /** Fire-time judgment for the controller-owned 4-second timer:
     *  executes only when the machine is quiet and the stack is
     *  still cleanable; the caller re-arms otherwise. Returns
     *  whether a cleanup ran. */
    fun runNdCleanupIfQuiet(): Boolean {
        if (activeNdWheelIds.isNotEmpty() || pendingNdCommits.isNotEmpty()) return false
        if (!activeFilterStack().canRemoveEmptyWheel) return false
        cleanupEmptyNdWheels()
        return true
    }

    // --- Screen-reader ordering (FILTER-A11Y-006) ---

    /**
     * Updates the platform-neutral screen-reader ordering policy.
     * Enabling freezes the complete order now and cancels a queued
     * reconciliation; disabling queues exactly one reconciliation, which
     * runs only once the wheel state machine is fully quiescent.
     */
    fun setFilterStackOrderingSuspended(isSuspended: Boolean) {
        if ((filterStackOrdering == FilterStackOrdering.frozen) == isSuspended) return
        filterStackOrdering = if (isSuspended) FilterStackOrdering.frozen else FilterStackOrdering.reorderPending
        publish()
    }

    /**
     * Runs the one reorder queued by [setFilterStackOrderingSuspended]
     * once the wheels are quiet. Called from [publish], which every
     * change goes through, so no mutation path has to remember it.
     */
    private fun reorderIfPending() {
        if (filterStackOrdering != FilterStackOrdering.reorderPending) return
        if (activeNdWheelIds.isNotEmpty() || pendingNdCommits.isNotEmpty()) return
        filterStackOrdering = FilterStackOrdering.live
        val (sorted, ids) = applyingSettledOrder(activeFilterStack(), ndWheelIds, inventory)
        if (ids == ndWheelIds) return
        ndWheelIds = ids
        writeFilterStack(sorted)
    }

    // --- Assistive adjustment (FILTER-A11Y-004/005) ---

    /**
     * Scans the wheel's existing row order in [direction], skipping rows
     * that are unavailable, and commits the first available one through
     * the barrier path — marked assistive, so no sighted fallback applies.
     * The caller announces the outcome.
     */
    fun adjustFilterWheel(
        wheelId: Int,
        direction: FilterWheelAdjustmentDirection,
    ): FilterWheelAdjustmentOutcome {
        val index = ndWheelIds.indexOf(wheelId)
        val stack = activeFilterStack()
        if (index < 0 || index !in stack.wheels.indices) {
            return FilterWheelAdjustmentOutcome.Unavailable(FilterStackRejection.unresolvedSelection)
        }
        val options = stack.rowOptions(index, inventory)
        val outcome = FilterWheelAccessibilityAdjustment.outcome(
            current = stack.wheels[index].selection,
            direction = direction,
            options = options,
        )
        if (outcome is FilterWheelAdjustmentOutcome.Selection) {
            pendingNdCommits.remove(wheelId)
            pendingNdCommits[wheelId] = PendingNdCommit(outcome.selection, isAssistive = true)
            publish()
            commitNdSetIfQuiet()
        }
        return outcome
    }

    // --- Transient notices (FILTER-STACK-004/006) ---

    private fun showFilterRejectionNotice(rejection: FilterStackRejection) {
        presentFilterRejectionNotice(
            FilterRejectionNotice(
                sequence = ++filterRejectionSequence,
                rejection = rejection,
            ),
        )
    }

    private fun showFilterAddUnavailabilityNotice(unavailability: FilterAddUnavailability) {
        presentFilterRejectionNotice(
            FilterRejectionNotice(
                sequence = ++filterRejectionSequence,
                addUnavailability = unavailability,
            ),
        )
    }

    /** Publishes the current refusal. How long it is shown is the
     *  view's decision; the controller only drops it when the context
     *  that produced it goes away. */
    private fun presentFilterRejectionNotice(notice: FilterRejectionNotice) {
        filterRejectionNotice = notice
        publish()
    }

    /** Drops the transient reason immediately. A refusal belongs to the
     *  context that produced it: a slot switch, a reset, or an inventory
     *  edit must not leave it lingering. */
    private fun clearFilterRejectionNotice() {
        if (filterRejectionNotice != null) {
            filterRejectionNotice = null
            publish()
        }
    }

    private fun noteEmptyFilterWheelRemoval(removed: Int) {
        if (removed > 0) _emptyWheelRemovals.tryEmit(removed)
    }

    // --- Filter Set / Filter Item facade (FILTER-SET / FILTER-ITEM) ---

    fun suggestFilterSetCreationColor(): FilterSetColor = inventoryModel.suggestCreationColor()

    fun createFilterSet(name: String, color: FilterSetColor): FilterSet? {
        val created = inventoryModel.createFilterSet(name, color) ?: return null
        applyFilterInventoryChange()
        return created
    }

    /** Saves a new filter into a proposed New Filter Set: the Set and the
     *  filter are created together, or nothing is (FILTER-ITEM-009). A new
     *  filter in a new Set is on no camera, so no stack can block it. */
    fun createFilterSet(name: String, color: FilterSetColor, holding: FilterItem): FilterSet? {
        val created = inventoryModel.createFilterSet(name, color, holding) ?: return null
        applyFilterInventoryChange()
        return created
    }

    /** Appends fresh example Filter Set copies (FILTER-SET-008). No
     *  camera selects them, so every camera keeps its state. */
    fun addExampleFilterSets(): List<FilterSet> {
        val added = inventoryModel.addExampleFilterSets()
        applyFilterInventoryChange()
        return added
    }

    fun renameFilterSet(id: FilterSetId, name: String) {
        inventoryModel.renameFilterSet(id, name)
        applyFilterInventoryChange()
    }

    fun recolorFilterSet(id: FilterSetId, color: FilterSetColor) {
        inventoryModel.recolorFilterSet(id, color)
        applyFilterInventoryChange()
    }

    /** Deletes a Filter Set. Its wheels disappear from every camera; a
     *  camera left with no wheel receives one Standard 0 wheel and a
     *  deleted last-used source falls back to Standard (FILTER-ITEM-006). */
    fun deleteFilterSet(id: FilterSetId) {
        inventoryModel.deleteFilterSet(id)
        applyFilterInventoryChange()
    }

    /** Deletes a physical item. Every wheel that referenced it becomes
     *  Empty on every camera (FILTER-ITEM-006). */
    fun deleteFilterItem(id: FilterItemId) {
        inventoryModel.deleteItem(id)
        applyFilterInventoryChange()
    }

    /**
     * Saves a new or edited item into [setId] (FILTER-ITEM-005). Blocked
     * — and nothing changes — when any camera stack would exceed 30 stops,
     * would lose a row it currently mounts, or would need more ND wheels
     * than its limit after a kind change. A selected CPL choice is never
     * silently replaced with another configured value; a kind change
     * within the limits moves the selection into the item's new role. An
     * existing item saved into another set moves there with its id at once,
     * and each camera judges the move against its own selected Filter Sets:
     * where that set is selected, an ND wheel keeps the item and an
     * auxiliary filter stays mounted; elsewhere the ND wheel becomes Empty
     * under its original source and the auxiliary filter is unmounted. No
     * camera selects the set (FILTER-ITEM-005/009).
     */
    fun saveFilterItem(item: FilterItem, setId: FilterSetId): FilterItemSaveOutcome {
        val conflicts = filterItemSaveConflicts(item, setId)
        if (conflicts.isNotEmpty()) {
            // One reason is shown: a removed selection first, then a full
            // role, then the cap.
            val priority = listOf(
                FilterItemSaveBlockReason.removesSelectedChoice,
                FilterItemSaveBlockReason.tooManyNDWheels,
                FilterItemSaveBlockReason.exceedsTotalLimit,
            )
            val reason = priority.first { candidate -> conflicts.any { it.second == candidate } }
            return FilterItemSaveOutcome.Blocked(conflicts.map { it.first }, reason)
        }
        val owner = inventory.item(item.id)?.first
        if (owner != null) {
            if (owner.id == setId) inventoryModel.updateItem(item) else inventoryModel.relocateItem(item, setId)
        } else {
            inventoryModel.addItem(item, setId)
        }
        applyFilterInventoryChange()
        return FilterItemSaveOutcome.Saved
    }

    /** Cameras whose stack currently mounts [itemId] — on a wheel or as
     *  an auxiliary filter — shown before a delete is confirmed
     *  (FILTER-ITEM-006). */
    fun camerasAffectedByDeletingItem(itemId: FilterItemId): List<CameraSlotIdentity> =
        cameraIdentities { stack ->
            stack.wheels.any { it.mountedItemId == itemId } || stack.auxiliaryFilters.any { it.itemId == itemId }
        }

    /** Cameras whose stack holds a wheel or a mounted auxiliary filter of
     *  the Filter Set. */
    fun camerasAffectedByDeletingFilterSet(setId: FilterSetId): List<CameraSlotIdentity> =
        cameraIdentities { stack ->
            stack.wheels.any { it.source == FilterSource.FilterSet(setId) } ||
                stack.auxiliaryFilters.any { it.filterSetId == setId }
        }

    /** Every camera's stack: the live stack for the active slot, each
     *  inactive slot's stored stack re-resolved against the inventory. */
    private fun stackForSlot(slotId: CameraSlotId): FilterStack? =
        if (slotId == session.activeSlotId) {
            activeFilterStack()
        } else {
            session.snapshot(slotId)?.let { filterStackOf(it) }
        }

    /** Identities, not resolved names: only the display boundary knows
     *  the user's language, and a default slot label has to be spoken in
     *  it (FILTER-A11Y-003). A photographer-supplied name passes through
     *  untouched. */
    private fun cameraIdentities(predicate: (FilterStack) -> Boolean): List<CameraSlotIdentity> =
        session.availableSlots
            .filter { slotId -> stackForSlot(slotId)?.let(predicate) == true }
            .map { session.identity(it) }

    /**
     * Cameras whose stack would become invalid if [item] were saved as
     * given, each with its reason.
     */
    private fun filterItemSaveConflicts(
        item: FilterItem,
        setId: FilterSetId,
    ): List<Pair<CameraSlotIdentity, FilterItemSaveBlockReason>> {
        if (!item.isWellFormed) return emptyList()
        val current = inventory
        val setIndex = current.filterSets.indexOfFirst { it.id == setId }
        if (setIndex < 0) return emptyList()
        val filterSet = current.filterSets[setIndex]
        val itemIndex = filterSet.items.indexOfFirst { it.id == item.id }
        val candidate = if (itemIndex >= 0) {
            val items = filterSet.items.toMutableList().also { it[itemIndex] = item }
            FilterInventory(current.filterSets.toMutableList().also { it[setIndex] = filterSet.copy(items = items) })
        } else {
            // A new item, or an existing one moving here from another set
            // (FILTER-ITEM-009).
            FilterInventory(
                current.filterSets.map { set ->
                    val stripped = set.items.filterNot { it.id == item.id }
                    set.copy(items = if (set.id == setId) stripped + item else stripped)
                },
            )
        }
        return session.availableSlots.mapNotNull { slotId ->
            val stack = stackForSlot(slotId) ?: return@mapNotNull null
            val selected = (if (slotId == session.activeSlotId) session.activeSnapshot else session.snapshot(slotId))
                ?.storedCandidateFilterSetIds ?: emptyList()
            val reason = stackConflict(stack, selected, item.id, candidate) ?: return@mapNotNull null
            session.identity(slotId) to reason
        }
    }

    /**
     * A camera's stack conflicts with the candidate inventory when a kind
     * change would move the mounted item into a role that is already
     * full, when a wheel or auxiliary filter mounting [itemId] no longer
     * resolves (its selected CPL choice is gone), or when the re-resolved
     * stack would exceed the cap. A kind change within the limits moves
     * the selection into the new role and does not conflict
     * (FILTER-ITEM-005).
     */
    private fun stackConflict(
        stack: FilterStack,
        selectedFilterSetIds: List<FilterSetId>,
        itemId: FilterItemId,
        candidate: FilterInventory,
    ): FilterItemSaveBlockReason? {
        val reassigned = FilterStack.reassigningRoles(stack.wheels, stack.auxiliaryFilters, selectedFilterSetIds, candidate)
        val wheels = reassigned.wheels
        val auxiliaryFilters = reassigned.auxiliaryFilters
        if (wheels.size > FilterStack.wheelLimit(auxiliaryFilters.isNotEmpty())) {
            return FilterItemSaveBlockReason.tooManyNDWheels
        }
        val selectedRowVanishes = wheels.any { wheel ->
            wheel.mountedItemId == itemId && FilterStack.resolvedRow(wheel, candidate) == null
        } || auxiliaryFilters.any { mount ->
            mount.itemId == itemId && FilterStack.resolvedAuxiliaryFilter(mount, candidate) == null
        }
        if (selectedRowVanishes) return FilterItemSaveBlockReason.removesSelectedChoice
        val normalized = FilterStack.normalizedWheels(wheels, candidate)
            ?: return FilterItemSaveBlockReason.exceedsTotalLimit
        val auxiliary = FilterStack.normalizedAuxiliaryFilters(auxiliaryFilters, candidate)
        if (FilterStack.validated(normalized, auxiliary, candidate) == null) {
            return FilterItemSaveBlockReason.exceedsTotalLimit
        }
        return null
    }

    /**
     * Applies an inventory mutation to every camera stack
     * (FILTER-ITEM-005/006, FILTER-PERSIST-002): in-flight wheel
     * interaction is discarded first — the edit came from the management
     * surface, never mid-gesture — a kind change moves each selection into
     * its item's new role, the active stack re-resolves wheel by wheel (so
     * surviving wheels keep their identity), an auxiliary filter that no
     * longer resolves is unmounted, every inactive slot snapshot
     * re-resolves in place, candidates follow the inventory, a vanished
     * last source falls back to Standard, the stale rejection reason is
     * dropped, and the cleanup timer re-arms against the new shape.
     */
    private fun applyFilterInventoryChange() {
        val current = inventory
        clearNdInteraction()
        clearFilterRejectionNotice()

        val (stack, ids) = reresolvedActiveStack(current)
        ndWheelIds = ids
        val source = session.activeSnapshot.restoredLastFilterSource(current)
        session.updateActiveSnapshot { it.writingFilterStack(stack, source, candidatesFor(it, stack, current)) }

        for (slotId in session.availableSlots) {
            if (slotId == session.activeSlotId) continue
            session.updateSnapshot(slotId) { snapshot ->
                val resolved = reresolvedStack(storedReferences(snapshot), snapshot.storedCandidateFilterSetIds, current)
                snapshot.writingFilterStack(
                    resolved,
                    snapshot.restoredLastFilterSource(current),
                    candidatesFor(snapshot, resolved, current),
                )
            }
        }
        publish()
        rearmNdCleanupTimer()
    }

    /** The active stack after an inventory edit, with each surviving
     *  wheel's stable identity carried through the role move. */
    private fun reresolvedActiveStack(current: FilterInventory): Pair<FilterStack, List<Int>> {
        val (storedWheels, storedMounts) = storedReferences(session.activeSnapshot)
        val reassigned = FilterStack.reassigningRoles(
            storedWheels,
            storedMounts,
            session.activeSnapshot.storedCandidateFilterSetIds,
            current,
        )
        val wheels = ArrayList<FilterWheel>()
        val ids = ArrayList<Int>()
        reassigned.wheels.zip(reassigned.wheelOrigins).forEach { (wheel, origin) ->
            val normalized = FilterStack.normalizedWheel(wheel, current) ?: return@forEach
            wheels.add(normalized)
            ids.add(origin?.let { ndWheelIds.getOrNull(it) } ?: makeNdWheelId())
        }
        if (wheels.isEmpty()) {
            wheels.add(FilterWheel.standard(0.0))
            ids.add(makeNdWheelId())
        }
        // A physical item may be mounted once per camera.
        val mounted = HashSet<FilterItemId>()
        for (index in wheels.indices) {
            val itemId = wheels[index].mountedItemId ?: continue
            if (!mounted.add(itemId)) {
                wheels[index] = FilterWheel(wheels[index].source, FilterWheelSelection.Empty)
            }
        }
        val auxiliary = FilterStack.normalizedAuxiliaryFilters(reassigned.auxiliaryFilters, current)
            .filter { it.itemId !in mounted }
        FilterStack.validated(wheels, auxiliary, current)?.let { return it to ids }
        // The save path blocks edits that would break the cap or the
        // limits; this is the defensive floor — empty every mounted wheel
        // item and, failing that, unmount the auxiliary filters, rather
        // than clamp any value.
        val emptied = wheels.map { if (it.isStandard) it else FilterWheel(it.source, FilterWheelSelection.Empty) }
        val stack = FilterStack.validated(emptied, auxiliary, current)
            ?: FilterStack.validated(emptied, current)
            ?: FilterStack.single(0.0)
        val stackIds = if (stack.wheels.size == ids.size) ids else List(stack.wheels.size) { makeNdWheelId() }
        return stack to stackIds
    }

    /** An inactive slot's stack after an inventory edit; same rules as
     *  [reresolvedActiveStack] without wheel identities. */
    private fun reresolvedStack(
        references: Pair<List<FilterWheel>, List<MountedAuxiliaryFilter>>,
        selectedFilterSetIds: List<FilterSetId>,
        current: FilterInventory,
    ): FilterStack {
        val reassigned = FilterStack.reassigningRoles(references.first, references.second, selectedFilterSetIds, current)
        val wheels = FilterStack.normalizedWheels(reassigned.wheels, current) ?: listOf(FilterWheel.standard(0.0))
        val onWheels = wheels.mapNotNull { it.mountedItemId }.toSet()
        val auxiliary = FilterStack.normalizedAuxiliaryFilters(reassigned.auxiliaryFilters, current)
            .filter { it.itemId !in onWheels }
        val emptied = wheels.map { if (it.isStandard) it else FilterWheel(it.source, FilterWheelSelection.Empty) }
        return FilterStack.validated(wheels, auxiliary, current)
            ?: FilterStack.validated(emptied, auxiliary, current)
            ?: FilterStack.validated(emptied, current)
            ?: FilterStack.single(0.0)
    }

    /** A slot's stored wheel and auxiliary references, unresolved, so a
     *  kind change can still be followed; the legacy Standard-only shape
     *  when the mixed-stack field is absent. */
    private fun storedReferences(snapshot: SlotCalculatorSnapshot): Pair<List<FilterWheel>, List<MountedAuxiliaryFilter>> =
        snapshot.storedFilterReferences()
            ?: filterStackOf(snapshot).let { it.wheels to it.auxiliaryFilters }

    /** A snapshot's candidates made consistent with [stack]: every set it
     *  references stays a candidate (FILTER-CAMERA-001). */
    private fun candidatesFor(
        snapshot: SlotCalculatorSnapshot,
        stack: FilterStack,
        current: FilterInventory,
    ): List<FilterSetId> =
        current.normalizedCandidateFilterSetIds(snapshot.storedCandidateFilterSetIds, stack.wheels, stack.auxiliaryFilters)

    // --- Mounted auxiliary filters (FILTER-AUX) ---

    /**
     * The Shooting Filters exposure reduction in stops: only the working
     * selection's auxiliary contributions, never the ND wheels, which
     * Shooting Filters does not show (FILTER-AUX-003). The 30-stop guard
     * still uses the complete stack ([shootingFiltersRejection]).
     */
    fun auxiliaryFiltersSubtotal(mounts: List<MountedAuxiliaryFilter>): Double {
        val current = inventory
        return mounts.sumOf { FilterStack.resolvedAuxiliaryFilter(it, current)?.contributionStops ?: 0.0 }
    }

    // --- Camera candidate Filter Sets (FILTER-CAMERA) ---

    /** Sets the active camera's stack still references — through an ND
     *  wheel (Empty included) or a mounted auxiliary filter. Shooting
     *  Filters marks them in use; leaving one out on Apply takes its
     *  filters and ND wheels off this camera (FILTER-CAMERA-003). */
    private val filterSetIdsReferencedByActiveCamera: Set<FilterSetId>
        get() {
            val stack = activeFilterStack()
            return stack.wheels.mapNotNull { it.source.filterSetId }.toSet() +
                stack.auxiliaryFilters.map { it.filterSetId }
        }

    /**
     * Arranges the active camera's candidate Filter Sets without a
     * Shooting Filters commit: no wheel is removed and Plus does not move.
     * Sets the stack references stay candidates, and a remembered source
     * that is no longer offered falls back to Standard. No production
     * caller: unit tests arrange a camera with it, while the app assigns
     * candidates only through [applyShootingFilters] and restore.
     */
    @VisibleForTesting
    internal fun arrangeCandidateFilterSets(ids: List<FilterSetId>) {
        val stack = activeFilterStack()
        val candidates = inventory.normalizedCandidateFilterSetIds(ids, stack.wheels, stack.auxiliaryFilters)
        session.updateActiveSnapshot { it.writingFilterStack(stack, lastFilterSource, candidates) }
        // Re-read against the new candidates: a remembered source that is
        // no longer offered is stored as Standard.
        val source = lastFilterSource
        session.updateActiveSnapshot { it.writingFilterStack(stack, source, candidates) }
        publish()
    }

    /** The working Selected Sets that still exist, in their selection
     *  order (FILTER-SET-001/004). */
    fun selectedFilterSets(selected: List<FilterSetId>): List<FilterSet> {
        val current = inventory
        return selected.mapNotNull { current.filterSet(it) }
    }

    /** Every other Filter Set, sorted by name (FILTER-SET-004). */
    fun availableFilterSets(selected: List<FilterSetId>): List<FilterSet> =
        FilterSetItemOrder.sortedByName(inventory.filterSets.filter { it.id !in selected })

    /** The Selected filters panel of a Shooting Filters session
     *  (FILTER-FLOW-003): every selected filter in Main's order. */
    fun selectedFilterRows(mounts: List<MountedAuxiliaryFilter>): List<SelectedFilterRowDisplayState> {
        val current = inventory
        val rows = mounts.mapNotNull { FilterStack.resolvedAuxiliaryFilter(it, current) }
        return AuxiliaryFilterSummaryPresenter.selectedFilterRows(FilterStack.displayOrdered(rows, current))
    }

    /** The working Selected Sets as Shooting Filters shows them
     *  (FILTER-SET-004): grouped ND-only, ND and auxiliary,
     *  auxiliary-only, empty, by their current items, each group in
     *  selection order. */
    fun displayedSelectedFilterSets(selected: List<FilterSetId>): List<FilterSet> =
        SelectedFilterSetGroup.ordered(selectedFilterSets(selected))

    /**
     * One mount change in a Shooting Filters session (FILTER-AUX-007):
     * mounting an item or changing its CPL choice or GND mode is refused at
     * once when the working state would be invalid — over 30 stops, or an
     * auxiliary filter beside four ND wheels that the working Set selection
     * keeps — and the session stays as it was. Unmounting is always
     * accepted. No ND wheel is ever removed to make room.
     */
    fun shootingFiltersSessionSettingMount(
        session: ShootingFiltersSession,
        itemId: FilterItemId,
        mount: MountedAuxiliaryFilter?,
    ): ShootingFiltersMountChange {
        val next = session.withMount(itemId, mount)
        if (mount == null) return ShootingFiltersMountChange.Accepted(next)
        val refused = shootingFiltersRejection(next.selectedFilterSetIds, next.mounts)
        return if (refused == null) ShootingFiltersMountChange.Accepted(next) else ShootingFiltersMountChange.Refused(refused)
    }

    /** Whether the active camera mounts a filter or an ND wheel from
     *  [id] — the "In use" state (FILTER-SET-001). */
    fun isFilterSetInUseOnActiveCamera(id: FilterSetId): Boolean = id in filterSetIdsReferencedByActiveCamera

    /**
     * The stack a Shooting Filters session would commit (FILTER-CAMERA-003):
     * the ND wheels of sets left unchecked are dropped, the remaining
     * wheels keep their identities, one Standard 0-stop wheel stands in
     * when none is left, and [mounts] replace the auxiliary filters. It
     * only reads: a wheel without an identity yet is `null`, and only a
     * successful Apply allocates one.
     */
    private fun shootingFiltersChange(
        selected: Set<FilterSetId>,
        mounts: List<MountedAuxiliaryFilter>,
    ): Pair<FilterStackChange, List<Int?>> {
        val stack = activeFilterStack()
        val keep = stack.wheels.indices.filter { index ->
            stack.wheels[index].source.filterSetId?.let { it in selected } ?: true
        }
        var wheels = keep.map { stack.wheels[it] }
        var ids: List<Int?> = keep.map { ndWheelIds.getOrNull(it) }
        if (wheels.isEmpty()) {
            wheels = listOf(FilterWheel.standard(0.0))
            ids = listOf(null)
        }
        val current = inventory
        val base = FilterStack.validated(wheels, current)
            ?: return FilterStackChange.Rejected(FilterStackRejection.exceedsTotalLimit) to ids
        return base.replacingAuxiliaryFilters(mounts.filter { it.filterSetId in selected }, current) to ids
    }

    /**
     * What Apply in Shooting Filters would report for a working session:
     * `null` when it would succeed. Nothing is committed.
     */
    fun shootingFiltersRejection(selected: List<FilterSetId>, mounts: List<MountedAuxiliaryFilter>): FilterStackRejection? =
        (shootingFiltersChange(selected.toSet(), mounts).first as? FilterStackChange.Rejected)?.reason

    /**
     * Commits a Shooting Filters session at once (FILTER-CAMERA-003,
     * FILTER-FLOW-003): the selected Filter Sets, in their selection
     * order (FILTER-SET-004), and the mounted auxiliary filters. Sets
     * left out lose their mounted filters and ND wheels on this camera
     * only; the sets stay in the inventory. Returns the rejection, leaving
     * everything unchanged, when the domain refuses the result.
     */
    fun applyShootingFilters(selected: List<FilterSetId>, mounts: List<MountedAuxiliaryFilter>): FilterStackRejection? {
        val (change, keptIds) = shootingFiltersChange(selected.toSet(), mounts)
        val replaced = when (change) {
            is FilterStackChange.Accepted -> change.stack
            is FilterStackChange.Rejected -> return change.reason
        }
        clearNdInteraction()
        clearFilterRejectionNotice()
        val current = inventory
        // An Apply that adds Filter Sets while Plus is on Standard moves Plus
        // to the preferred ND Set and turns every Standard 0-stop wheel, the
        // fallback included, into an Empty wheel of that Set with the same
        // identity and no contribution (FILTER-PLUS-006).
        val addsFilterSets = selected.any { it !in candidateFilterSetIds }
        val preferred = if (lastFilterSource == FilterSource.Standard && addsFilterSets) {
            PreferredNdSource.winner(selected.mapNotNull { current.filterSet(it) })
        } else {
            null
        }
        val converted = preferred?.let { replaced.convertingZeroStandardWheels(it, current) } ?: replaced
        // The same ordering rule as a wheel commit (FILTER-STACK-005,
        // FILTER-A11Y-006): positions stay while the screen reader orders
        // the wheels.
        val (committed, ids) = applyingSettledOrder(converted, keptIds.map { it ?: makeNdWheelId() }, current)
        val candidates = current.normalizedCandidateFilterSetIds(selected, committed.wheels, committed.auxiliaryFilters)
        val preferredSource = preferred?.let { FilterSource.FilterSet(it) } ?: lastFilterSource
        session.updateActiveSnapshot { it.writingFilterStack(committed, preferredSource, candidates) }
        ndWheelIds = ids
        // Re-read against the new candidates: a remembered source that is
        // no longer offered is stored as Standard.
        val source = lastFilterSource
        session.updateActiveSnapshot { it.writingFilterStack(committed, source, candidates) }
        publish()
        rearmNdCleanupTimer()
        return null
    }

    private val defaultSnapshot = SlotCalculatorSnapshot(defaultShutterIndex, 0, null, null)

    // The session is the single owner of every slot's calculator state; the
    // active slot's inputs are read/written through [session] in place, not
    // mirrored into controller-level fields.
    private val session = CameraSlotSession(
        initialActiveSlotId = initialSession?.activeSlotId ?: CameraSlotId.camera1,
        defaultSnapshot = defaultSnapshot,
        initialSnapshots = initialSession?.snapshots ?: emptyMap(),
        initialCustomNames = initialSession?.customNames ?: emptyMap(),
    )

    // Read-only views of the active slot's owned state.
    private val shutterIndex: Int get() = session.activeSnapshot.shutterIndex
    private val currentNdStops: Double get() = activeFilterStack().effectiveStops
    private val selectedFilmId: String? get() = session.activeSnapshot.selectedFilmId
    private val selectedProfileId: String? get() = session.activeSnapshot.selectedProfileId
    private val targetSeconds: Double? get() = session.activeSnapshot.targetSeconds

    init {
        // Normalize the restored active slot (coerce indices, drop a stale film /
        // profile reference) so a deleted custom film is not re-persisted as a
        // broken selection. Inactive slots normalize when they become active.
        // The persisted wheel order is restored as written — a launch with
        // screen-reader ordering suspended must not reorder (FILTER-A11Y-006).
        session.updateActiveSnapshot { normalizeSnapshot(it) }
        syncNdWheelIds()
    }

    private val _state = MutableStateFlow(compute())
    val state: StateFlow<CalculatorUiState> = _state.asStateFlow()

    /** Serializable snapshot of the whole slot session (every slot's owned state). */
    fun exportSession(): PersistentSlotSession = PersistentSlotSession(
        activeSlotId = session.activeSlotId,
        snapshots = session.currentSnapshots(),
        customNames = session.currentCustomNames(),
    )

    fun setShutterIndex(index: Int) {
        session.updateActiveSnapshot { it.copy(shutterIndex = index.coerceIn(shutterLabels.indices)) }
        publish()
    }

    fun setNdIndex(index: Int) {
        // Legacy single-filter assignment surface: replaces the whole
        // stack with one Standard wheel holding the value (iOS `ndStep`
        // setter parity). The stack path goes through `setNdWheelValue`.
        val stops = ndStopValues[index.coerceIn(ndStopValues.indices)]
        clearNdInteraction()
        ndWheelIds = listOf(makeNdWheelId())
        // Only a successful Plus addition moves the remembered source
        // (FILTER-PLUS-004), so this legacy write leaves it as it was.
        writeFilterStack(FilterStack.single(stops))
    }

    /** Sets the ND notation display mode; re-publishes so wheel labels update. */
    fun setNotationMode(mode: NDNotationMode) {
        if (mode == ndNotationMode) return
        ndNotationMode = mode
        publish()
    }

    fun selectFilm(id: String?) {
        // Reset the model selection to the film's primary profile.
        val profileId = id?.let { films.firstOrNull { f -> f.id == it }?.profiles?.firstOrNull()?.id }
        session.updateActiveSnapshot { it.copy(selectedFilmId = id, selectedProfileId = profileId) }
        publish()
    }

    fun selectProfile(id: String) {
        // PTIMER-158: only models present in the (community-filtered) picker can
        // be activated; a hidden community/practical or otherwise unknown id
        // normalizes to the film's primary official profile.
        val film = selectedFilm()
        val resolved = id.takeIf { pid -> film != null && modelProfiles(film).any { it.id == pid } }
        session.updateActiveSnapshot { it.copy(selectedProfileId = resolved) }
        publish()
    }

    /** Replaces the available film list (preset + custom library) and republishes. */
    fun setFilms(list: List<FilmIdentity>) { films = list; publish() }

    /** Sets the active slot's Target Shutter duration; a non-finite/≤0 value clears it. */
    fun setTargetShutter(seconds: Double?) {
        val target = seconds?.takeIf { it.isFinite() && it > 0 }
        session.updateActiveSnapshot { it.copy(targetSeconds = target) }
        publish()
    }

    /** Starts a timer from the active slot's target duration (no-op when unset). */
    fun startFromTarget() {
        val target = targetSeconds ?: return
        val result = calculator.result(shutterIndex, currentNdStops, resolvedProfile())
        onStart(target, identity(result, "Target Exposure", target, includesAdjusted = true))
    }

    /** Starts a timer from the ND-adjusted shutter (the digital / pre-reciprocity value). */
    fun startFromAdjusted() {
        val result = calculator.result(shutterIndex, currentNdStops, resolvedProfile())
        val d = result.adjustedShutterSeconds
        if (d.isFinite() && d > 0) onStart(d, identity(result, "Adjusted Exposure", d, includesAdjusted = false))
    }

    /** Starts a timer from the reciprocity-corrected exposure, including an
     * out-of-range ("outside guidance") computed value; no-op when truly none. */
    fun startFromCorrected() {
        val result = calculator.result(shutterIndex, currentNdStops, resolvedProfile())
        val d = (result.correctedSeconds ?: result.reciprocity?.calculatedCorrectedSeconds) ?: return
        if (d.isFinite() && d > 0) onStart(d, identity(result, "Corrected Exposure", d, includesAdjusted = true))
    }

    /**
     * Resets the active slot's shooting settings to defaults: no film,
     * base 1/30, ND 0, no target. Keeps the custom camera name (the
     * "Reset settings" choice).
     */
    fun resetActiveSlotSettings() {
        resetActiveSlotSettingsFields()
        publish()
    }

    /**
     * Resets the active slot's settings *and* clears its custom camera
     * name, returning the slot to a fully blank state (the "Reset
     * settings and name" choice).
     */
    fun resetActiveSlotSettingsAndName() {
        resetActiveSlotSettingsFields()
        session.resetCustomName(session.activeSlotId)
        publish()
    }

    private fun resetActiveSlotSettingsFields() {
        // The camera's candidate Filter Sets are an assignment, not a
        // shooting setting: a reset unmounts every auxiliary filter and
        // returns the ND wheels to one Standard 0 (RESET-011) but keeps
        // them, and keeps the remembered Plus source, which only a
        // successful addition changes (FILTER-PLUS-004).
        session.updateActiveSnapshot {
            defaultSnapshot.copy(
                candidateFilterSetIds = it.candidateFilterSetIds,
                lastFilterSourceKind = it.lastFilterSourceKind,
                lastFilterSetId = it.lastFilterSetId,
            )
        }
        clearNdInteraction()
        clearFilterRejectionNotice()
        ndWheelIds = emptyList()
        syncNdWheelIds()
    }

    // --- Custom-film editing (delegated to CustomFilmEditingPresenter) ---

    fun previewTableFit(input: CustomTableFilmInput) =
        CustomFilmEditingPresenter.previewTableFit(input)

    fun buildFormulaFilmFromTableInput(
        input: CustomTableFilmInput,
        filmId: String,
        profileId: String,
        referenceTableFilmId: String? = null,
    ) = CustomFilmEditingPresenter.buildFormulaFilmFromTableInput(input, filmId, profileId, referenceTableFilmId)

    fun referencePoints(input: CustomFormulaFilmInput, anchors: List<Pair<Double, Double>>) =
        CustomFilmEditingPresenter.referencePoints(input, anchors)

    fun tableAnchorsOf(filmId: String?) = CustomFilmEditingPresenter.tableAnchorsOf(films, filmId)

    fun previewFormulaGraph(input: CustomFormulaFilmInput) =
        CustomFilmEditingPresenter.previewFormulaGraph(input, currentAdjustedSeconds())

    fun previewTableGraph(input: CustomTableFilmInput) =
        CustomFilmEditingPresenter.previewTableGraph(input, currentAdjustedSeconds())

    fun previewFormulaCheckpoints(input: CustomFormulaFilmInput) =
        CustomFilmEditingPresenter.previewFormulaCheckpoints(input)

    fun previewTableCheckpoints(input: CustomTableFilmInput) =
        CustomFilmEditingPresenter.previewTableCheckpoints(input)

    fun calculationBasis(input: CustomFormulaFilmInput) =
        CustomFilmEditingPresenter.calculationBasis(input)

    private fun currentAdjustedSeconds(): Double =
        calculator.result(shutterIndex, currentNdStops, null).adjustedShutterSeconds

    fun customFilmDraft(filmId: String) = CustomFilmEditingPresenter.customFilmDraft(films, filmId)

    fun customFilmProfileId(filmId: String) = CustomFilmEditingPresenter.customFilmProfileId(films, filmId)

    /** Reciprocity details for the active film/profile; null in the digital (no-film) workflow. */
    fun detailsState(): ReciprocityDetailsDisplayState? {
        val film = selectedFilm() ?: return null
        val profile = resolvedProfile() ?: return null
        val result = calculator.result(shutterIndex, currentNdStops, profile)
        val recip = result.reciprocity ?: return null
        return ReciprocityDetailsPresenter.make(
            film = film,
            profile = profile,
            result = recip,
            adjustedShutterSeconds = result.adjustedShutterSeconds,
            formatDuration = exposure::formatCoarse,
        )
    }

    /** Switches the active camera slot. Each slot owns its own snapshot, so this
     * only re-points the active slot — no capture/restore of live state. The
     * newly-active slot is normalized in place so visiting a slot heals a stale
     * film/profile or an out-of-range index in its stored snapshot (matching the
     * pre-refactor load-on-switch behavior) without re-persisting a broken ref. */
    fun selectSlot(id: CameraSlotId) {
        if (!session.switchActiveSlot(id)) return
        session.updateActiveSnapshot { normalizeSnapshot(it) }
        // In-flight selections belong to the outgoing slot; the
        // arriving slot gets fresh wheel identities. A refusal belongs to
        // the camera that produced it and must not linger over another.
        clearNdInteraction()
        clearFilterRejectionNotice()
        ndWheelIds = emptyList()
        syncNdWheelIds()
        publish()
    }

    /** Renames the active slot; a blank name clears the custom name back to `Camera N`. */
    fun renameActiveSlot(name: String?) {
        session.setCustomName(name, session.activeSlotId)
        publish()
    }

    fun start() {
        val result = calculator.result(shutterIndex, currentNdStops, resolvedProfile())
        val duration = result.startDurationSeconds ?: return
        // Digital/no-film start uses the same shape as Adjusted (the digital
        // result is the ND-adjusted shutter); film starts go through the
        // dedicated adjusted/corrected entry points above.
        val source = if (selectedFilm() == null) "Calculated" else "Corrected Exposure"
        val includesAdjusted = selectedFilm() != null
        onStart(duration, identity(result, source, duration, includesAdjusted))
    }

    /**
     * Coerces a restored snapshot into a safe state: wheel indices back into
     * range, and a stale film/profile selection dropped so a deleted custom
     * film (or a profile id no longer valid for the film) is not re-persisted
     * as a broken reference. An unknown film clears both; an invalid profile
     * for a known film clears the profile (it falls back to the film's primary).
     * The additive mixed-stack fields pass through untouched — their own
     * restore rules resolve them against the live inventory.
     */
    private fun normalizeSnapshot(snapshot: SlotCalculatorSnapshot): SlotCalculatorSnapshot {
        val film = snapshot.selectedFilmId?.let { id -> films.firstOrNull { it.id == id } }
        return snapshot.copy(
            shutterIndex = snapshot.shutterIndex.coerceIn(shutterLabels.indices),
            ndIndex = snapshot.ndIndex.coerceIn(0, ExposureScale.MAXIMUM_WHOLE_ND_STOPS),
            selectedFilmId = film?.id,
            selectedProfileId = film?.let { f ->
                snapshot.selectedProfileId?.takeIf { pid -> modelProfiles(f).any { it.id == pid } }
            },
            targetSeconds = snapshot.targetSeconds?.takeIf { it.isFinite() && it > 0 },
            // Keep the exact ND value only when it is a supported commercial
            // preset; an unsupported off-grid value is dropped so restore falls
            // back to the legacy whole-stop field.
            ndStops = snapshot.ndStops?.let { ExposureScale.commercialNDPresetStop(it) },
            // Reject-never-clamp: an invalid persisted stack restores
            // through the legacy scalar instead of being repaired.
            ndStack = snapshot.ndStack?.takeIf { NdFilterStack.isValidRestoredStack(it) },
        )
    }

    private fun publish() {
        reorderIfPending()
        _state.value = compute()
    }

    private fun selectedFilm(): FilmIdentity? = selectedFilmId?.let { id -> films.firstOrNull { it.id == id } }

    private fun modelProfiles(film: FilmIdentity): List<ReciprocityProfile> {
        val primary = film.profiles.first()
        return AlternateReciprocityModels.modelPickerOrder(primary, film.id)
    }

    private fun resolvedProfile(): ReciprocityProfile? = resolvedProfileFor(selectedFilm(), selectedProfileId)

    private fun resolvedProfileFor(film: FilmIdentity?, profileId: String?): ReciprocityProfile? {
        film ?: return null
        val options = modelProfiles(film)
        return options.firstOrNull { it.id == profileId } ?: film.profiles.first()
    }

    /**
     * Captured timer identity (PTIMER-187): the title carries the camera + film
     * identity, the second line carries the exposure source + final value, and
     * the structured ND/base/adjusted fields let the timer card render its basis
     * in the current notation mode. No ND token / duration in the title, and no
     * film name / duration repeated on the second line.
     *
     * The immutable filter record (FILTER-PERSIST-003) is captured here too:
     * every mounted row's source, item, registered value, mode, and contributed
     * stops, plus the reference string generated at start time. A later rename,
     * reorder, edit, or deletion never rewrites it.
     *
     * [includesAdjusted] is true for corrected/target timers, where the adjusted
     * shutter is an intermediate distinct from the final duration.
     */
    private fun identity(
        result: ShootingResult,
        source: String,
        finalSeconds: Double,
        includesAdjusted: Boolean,
    ): TimerIdentity {
        val film = selectedFilm()
        val filmName = film?.canonicalStockName ?: "No film"
        val slot = session.activeIdentity
        val ladder = ExposureScale.oneThirdStop.shutterSteps
        val base = ladder[shutterIndex.coerceIn(ladder.indices)].seconds
        val stack = activeFilterStack()
        val summary = FilterSummaryEntry.summary(stack, inventory)
        return TimerIdentity(
            title = "${slot.displayName} · $filmName",
            subtitle = "$source ${exposure.formatExtendedClock(finalSeconds)}",
            slotLabel = slot.id.shortLabel,
            ndStops = stack.effectiveStops,
            baseShutterSeconds = base,
            adjustedShutterSeconds = result.adjustedShutterSeconds,
            basisIncludesAdjusted = includesAdjusted,
            filmName = filmName,
            filterSummary = summary.takeIf { it.isNotEmpty() },
            filterReferenceText = FilterSummaryReferencePresenter.referenceText(
                summary,
                referenceVocabulary(),
            ),
        )
    }

    /** Whole-seconds secondary for clock-band values (1 min .. 1 day); null otherwise. */
    private fun secondsComparison(seconds: Double): String? {
        if (!seconds.isFinite() || seconds < 60 || seconds >= 86_400) return null
        return "${Math.round(seconds)}s"
    }

    private fun comparisonSource(result: ShootingResult): TargetShutterPresenter.ComparisonSource {
        // Compare the target against the corrected exposure when a usable number
        // exists (including an out-of-range "outside guidance" value). Digital
        // workflow falls back to the adjusted shutter so the ↑/↓ stop guidance
        // is always shown while a target is set. Film workflow without a
        // quantified corrected exposure (limited-guidance / unsupported) must
        // not silently fall back to the intermediate adjusted shutter — the
        // comparison is unavailable instead (PTIMER-191).
        val corrected = result.correctedSeconds ?: result.reciprocity?.calculatedCorrectedSeconds
        if (corrected != null && corrected.isFinite() && corrected > 0) {
            return TargetShutterPresenter.ComparisonSource.CorrectedExposure(corrected)
        }
        return if (result.isDigital) {
            TargetShutterPresenter.ComparisonSource.AdjustedShutter(result.adjustedShutterSeconds)
        } else {
            TargetShutterPresenter.ComparisonSource.Unavailable
        }
    }

    /**
     * Top-level state: the active slot's state, carrying every slot's read-only
     * state in [CalculatorUiState.slotStates] so the camera pager renders each
     * page from its own slot (no clone-until-settle during a swipe). Every slot
     * reads its own session-owned snapshot.
     */
    private fun compute(): CalculatorUiState {
        val perSlot = session.availableSlots.map { slotId ->
            computeSlot(session.snapshot(slotId) ?: defaultSnapshot, slotId)
        }
        val activeIndex = session.availableSlots.indexOf(session.activeSlotId).coerceAtLeast(0)
        return perSlot[activeIndex].copy(slotStates = perSlot)
    }

    /** Builds a slot's read-only calculator state from its snapshot inputs. */
    private fun computeSlot(snapshot: SlotCalculatorSnapshot, slotId: CameraSlotId): CalculatorUiState {
        val current = inventory
        val film = snapshot.selectedFilmId?.let { id -> films.firstOrNull { it.id == id } }
        val profile = resolvedProfileFor(film, snapshot.selectedProfileId)
        val committedStack = filterStackOf(snapshot)
        val isActiveSlot = slotId == session.activeSlotId
        // Active slot: pending selections overlay their wheels so the
        // result follows each wheel while the set commit is open.
        val displaySelections = committedStack.wheels.mapIndexed { i, wheel ->
            if (isActiveSlot) {
                ndWheelIds.getOrNull(i)?.let { pendingNdCommits[it]?.selection } ?: wheel.selection
            } else {
                wheel.selection
            }
        }
        val displayRows = committedStack.wheels.mapIndexed { i, wheel ->
            FilterStack.resolvedRow(FilterWheel(wheel.source, displaySelections[i]), current)
                ?: committedStack.rows[i]
        }
        val effectiveStops = displayRows.sumOf { it.contributionStops } + committedStack.auxiliaryContributions.sum()
        val result = calculator.result(snapshot.shutterIndex, effectiveStops, profile)

        val filterWheels = committedStack.wheels.mapIndexed { i, wheel ->
            val wheelId = if (isActiveSlot) ndWheelIds.getOrElse(i) { i } else i
            val options = committedStack.rowOptions(i, current)
            val committedIndex = options
                .indexOfFirst { isSameSelection(it.selection, wheel.selection) }
                .coerceAtLeast(0)
            val displayedIndex = options
                .indexOfFirst { isSameSelection(it.selection, displaySelections[i]) }
                .let { if (it >= 0) it else committedIndex }
            FilterWheelUiState(
                id = wheelId,
                source = wheel.source,
                sourceName = FilterWheelPresenter.sourceName(wheel.source, current),
                sourceColor = filterSetColor(wheel.source, current),
                rows = options.map { FilterWheelPresenter.row(it, ndNotationMode) },
                selectedIndex = displayedIndex,
                committedIndex = committedIndex,
            )
        }

        val isQuiet = !isActiveSlot || (activeNdWheelIds.isEmpty() && pendingNdCommits.isEmpty())
        val slotLastSource = snapshot.restoredLastFilterSource(current)
        val candidates = snapshot.restoredCandidateFilterSetIds(current)
        // Four ND wheels without auxiliary filters, three with them
        // (FILTER-STACK-001).
        val plusVisible = committedStack.canAddWheel
        // Per source, against THIS slot's stack: the Plus control shows
        // whichever source is displayed, and an inactive page must not
        // judge its sources against the active camera's wheels. Only
        // Standard and the camera's ND-holding candidate sets are offered
        // (FILTER-PLUS-001).
        val sources = current.offeredFilterSources(candidates).map {
            FilterSourceUiOption(
                source = it,
                name = FilterWheelPresenter.sourceName(it, current),
                color = filterSetColor(it, current),
                addUnavailability = committedStack.addUnavailability(it, current),
            )
        }
        val plus = FilterPlusUiState(
            isVisible = plusVisible,
            sources = sources,
            selectedIndex = sources.indexOfFirst { it.source == slotLastSource }.coerceAtLeast(0),
            isQuiet = isQuiet,
        )

        val movingWheelId = if (isActiveSlot) ndWheelIds.firstOrNull { it in activeNdWheelIds } else null
        val isMaximum = effectiveStops >=
            FilterStack.TOTAL_LIMIT - ExposureCalculator.STABILITY_EPSILON
        val filterStatus = FilterStatusUiState(
            idleSourceSummary = sourceSummary(committedStack, current),
            movingWheelId = movingWheelId,
            rejection = if (isActiveSlot) filterRejectionNotice else null,
            totalStopsText = formatTotalStops(effectiveStops),
            totalIsMaximum = isMaximum,
        )

        val modelOptions = film?.let { f ->
            val options = modelProfiles(f)
            if (options.size > 1) options.map { ModelOption(it.id, it.selectorLabel ?: it.name) } else emptyList()
        } ?: emptyList()

        // A wheel with an ND value, or any mounted auxiliary filter,
        // zero-contribution ones included. Selected Filter Sets alone do not
        // count, nor do the Empty or Standard 0 wheels an Apply leaves
        // (RESET-004).
        val canReset = snapshot.shutterIndex != defaultShutterIndex ||
            committedStack.wheels.any { it.mountedItemId != null || (it.standardStops ?: 0.0) != 0.0 } ||
            committedStack.hasAuxiliaryFilters ||
            film != null ||
            snapshot.targetSeconds != null ||
            slotId in session.currentCustomNames()

        return CalculatorUiState(
            slots = session.availableSlots.map {
                SlotTab(it, session.identity(it).displayName, it == session.activeSlotId)
            },
            activeSlotName = session.identity(slotId).displayName,
            shutterLabels = shutterLabels,
            shutterIndex = snapshot.shutterIndex,
            ndLabels = ndLabels(),
            ndIndex = ndWheelIndex(committedStack.effectiveStops),
            filterWheels = filterWheels,
            plus = plus,
            filterStatus = filterStatus,
            auxiliarySummary = AuxiliaryFilterSummaryPresenter.displayState(committedStack.auxiliaryRows),
            mountedAuxiliaryFilters = committedStack.auxiliaryFilters,
            candidateFilterSetIds = candidates,
            ndTotalStopsText = if (committedStack.wheels.size >= 2) filterStatus.totalStopsText else null,
            // Same live basis as the total text, so the badge never
            // shows "30" without its Maximum marker mid-scroll.
            ndTotalIsMaximum = committedStack.wheels.size >= 2 && isMaximum,
            filmOptions = filmOptions(),
            selectedFilmId = snapshot.selectedFilmId,
            selectedFilmName = film?.canonicalStockName ?: "No film",
            modelOptions = modelOptions,
            selectedProfileId = snapshot.selectedProfileId,
            hasFilm = film != null,
            canReset = canReset,
            ndNotationMode = ndNotationMode,
            adjustedText = exposure.formatCoarse(result.adjustedShutterSeconds),
            adjustedSecondsText = secondsComparison(result.adjustedShutterSeconds),
            adjustedStartEnabled = result.adjustedShutterSeconds.isFinite() && result.adjustedShutterSeconds > 0,
            // Show the computed corrected value even when out of range ("outside
            // guidance") so the main matches the Details sheet; only truly-no-value
            // (limited guidance) reads "No corrected value".
            correctedText = (result.correctedSeconds ?: result.reciprocity?.calculatedCorrectedSeconds)
                ?.takeIf { it.isFinite() && it > 0 }?.let { exposure.formatCoarse(it) },
            correctedSecondsText = (result.correctedSeconds ?: result.reciprocity?.calculatedCorrectedSeconds)
                ?.let { secondsComparison(it) },
            correctedStartEnabled = (result.correctedSeconds ?: result.reciprocity?.calculatedCorrectedSeconds ?: 0.0)
                .let { it.isFinite() && it > 0 },
            confidenceLabel = result.confidenceLabel,
            startEnabled = result.startEnabled,
            hint = result.hint,
            targetDisplay = TargetShutterPresenter.makeDisplayState(snapshot.targetSeconds, comparisonSource(result)),
        )
    }

    private fun filterSetColor(source: FilterSource, inventory: FilterInventory): FilterSetColor? =
        source.filterSetId?.let { inventory.filterSet(it)?.color }

    /**
     * Idle source identity for a stack containing any Filter Set wheel or
     * mounted auxiliary filter (FILTER-STACK-008): each source once in
     * main-row order — the auxiliary filters' sets first, then the wheels'
     * settled left-to-right order — with its ND-wheel count and, for a
     * Filter Set, its user-selected source color. `null` for a
     * Standard-only stack, which keeps the existing ND status behavior.
     */
    private fun sourceSummary(
        stack: FilterStack,
        inventory: FilterInventory,
    ): List<FilterSourceSummaryItem>? {
        if (stack.wheels.none { it.source != FilterSource.Standard } && !stack.hasAuxiliaryFilters) return null
        val counts = LinkedHashMap<FilterSource, Int>()
        for (mount in stack.auxiliaryFilters) counts.getOrPut(FilterSource.FilterSet(mount.filterSetId)) { 0 }
        for (wheel in stack.wheels) counts[wheel.source] = (counts[wheel.source] ?: 0) + 1
        return counts.map { (source, count) ->
            FilterSourceSummaryItem(
                source = source,
                name = FilterWheelPresenter.sourceName(source, inventory),
                count = count,
                color = filterSetColor(source, inventory),
            )
        }
    }

    /**
     * Two selections are the same row. Standard values compare within the
     * shared stability epsilon so a restored ladder value never reads as a
     * different row than the one the picker offers.
     */
    private fun isSameSelection(lhs: FilterWheelSelection, rhs: FilterWheelSelection): Boolean =
        if (lhs is FilterWheelSelection.Standard && rhs is FilterWheelSelection.Standard) {
            abs(lhs.stops - rhs.stops) <= ExposureCalculator.STABILITY_EPSILON
        } else {
            lhs == rhs
        }

    /** Stack total, always in stops: "18" for whole values, one
     *  decimal ("13.2") otherwise (iOS Total-overlay parity). */
    private fun formatTotalStops(stops: Double): String {
        val rounded = Math.round(stops).toDouble()
        return if (abs(stops - rounded) <= 0.05) {
            Math.round(stops).toString()
        } else {
            String.format(java.util.Locale.US, "%.1f", stops)
        }
    }

    private fun filmOptions(): List<FilmOption> {
        val options = films.map { f ->
            val primary = f.profiles.firstOrNull()
            FilmOption(
                id = f.id,
                name = f.canonicalStockName,
                manufacturer = f.manufacturer,
                iso = f.iso,
                isUnofficial = primary?.source?.authority == ReciprocityAuthority.unofficial,
                hasReciprocityCurve = primary?.rules?.any {
                    it.formula != null || it.tableInterpolation != null
                } == true,
                isCustom = f.kind == FilmIdentityKind.custom,
            )
        }
        val presetComparator = compareBy<FilmOption, String>(java.lang.String.CASE_INSENSITIVE_ORDER) {
            it.manufacturer.orEmpty()
        }.thenBy(java.lang.String.CASE_INSENSITIVE_ORDER) { it.name }

        return listOf(FilmOption(null, "No film")) +
            options.filter { it.isCustom } +
            options.filterNot { it.isCustom }.sortedWith(presetComparator)
    }
}

/** The same stack with every Standard 0-stop wheel turned into an Empty
 *  wheel of [filterSetId] (FILTER-PLUS-006); `null` when that does not
 *  validate. */
private fun FilterStack.convertingZeroStandardWheels(filterSetId: FilterSetId, inventory: FilterInventory): FilterStack? =
    FilterStack.validated(
        wheels.map { if (it.standardStops == 0.0) FilterWheel.empty(filterSetId) else it },
        auxiliaryFilters,
        inventory,
    )
