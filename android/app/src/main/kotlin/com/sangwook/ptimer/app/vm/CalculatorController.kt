// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

package com.sangwook.ptimer.app.vm

import com.sangwook.ptimer.app.calc.ShootingCalculator
import com.sangwook.ptimer.app.calc.ShootingResult
import com.sangwook.ptimer.core.customfilm.CustomFormulaFilmInput
import com.sangwook.ptimer.core.customfilm.CustomTableFilmInput
import com.sangwook.ptimer.core.exposure.ExposureCalculator
import com.sangwook.ptimer.core.exposure.ExposureScale
import com.sangwook.ptimer.core.exposure.NDNotationFormatter
import com.sangwook.ptimer.core.exposure.NDNotationMode
import com.sangwook.ptimer.core.exposure.NDStep
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
import com.sangwook.ptimer.core.slots.CameraSlotSession
import com.sangwook.ptimer.core.slots.SlotCalculatorSnapshot
import com.sangwook.ptimer.core.slots.canonicalNDStops
import com.sangwook.ptimer.core.slots.canonicalNdStackStops
import kotlin.math.abs
import kotlin.math.roundToInt
import com.sangwook.ptimer.core.target.TargetShutterDisplayState
import com.sangwook.ptimer.core.target.TargetShutterPresenter
import com.sangwook.ptimer.core.timer.TimerIdentity
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
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

/**
 * One ND filter wheel of the stack (PTIMER-199). [id] is the wheel's
 * stable identity (monotonic from 101, position-independent — the
 * Compose row keys on it so the commit sort animates as movement);
 * [labels] is the wheel's budget-truncated ladder in the current
 * notation; [selectedIndex] points at the wheel's DISPLAY value
 * (pending selection while the set commit is open, committed value
 * otherwise).
 */
data class NdWheelUiState(
    val id: Int,
    val labels: List<String>,
    val selectedIndex: Int,
)
data class SlotTab(val id: CameraSlotId, val displayName: String, val isActive: Boolean)

/** Immutable state the shooting calculator surface renders. */
data class CalculatorUiState(
    val slots: List<SlotTab>,
    val activeSlotName: String,
    val shutterLabels: List<String>,
    val shutterIndex: Int,
    val ndLabels: List<String>,
    val ndIndex: Int,
    /** ND wheel stack (PTIMER-199): 1..4 wheels in display order. */
    val ndWheels: List<NdWheelUiState> = emptyList(),
    /** Layout presence of the Add control (C1, committed-only). */
    val showsAddNdWheel: Boolean = false,
    /** Add availability (presence AND the machine is quiet). */
    val canAddNdWheel: Boolean = false,
    /** True while a removable 0-stop wheel exists on the COMMITTED
     *  stack (drives the UI-hosted 4-second fire-time cleanup
     *  timer's presence; the timer itself re-judges at fire time). */
    val canRemoveEmptyNdWheel: Boolean = false,
    /** True only while the one-shot cleanup would actually run NOW —
     *  a removable zero exists AND the machine is quiet. Gates the
     *  TalkBack "Remove empty filter" custom action so assistive
     *  users are never offered a command that would no-op. */
    val canCleanupEmptyNdWheels: Boolean = false,
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
)

/**
 * Owns the shooting calculator surface across camera slots: base-shutter /
 * ND wheel indices, film + alternate-model selection, and the derived
 * result for the active slot. Per-slot state lives in the [CameraSlotSession],
 * which owns a stable snapshot for every slot; the controller reads and mutates
 * the active slot's snapshot in place, so a slot switch just re-points the
 * active slot without capturing or restoring live state. Start delegates the
 * computed duration + captured identity to the timer workspace via [onStart].
 * Pure of Android; deterministic and unit-testable.
 */
class CalculatorController(
    films: List<FilmIdentity>,
    private val calculator: ShootingCalculator = ShootingCalculator(),
    private val exposure: ExposureCalculator = ExposureCalculator(),
    private val onStart: (duration: Double, identity: TimerIdentity) -> Unit = { _, _ -> },
    initialSession: PersistentSlotSession? = null,
    /** Scope that owns the ND cleanup timer (PTIMER-199 §4.2.2 /
     *  PTIMER-223): the ViewModel scope in production, so the timer
     *  survives configuration changes with the state it judges. Null
     *  keeps the timer disarmed and pure state tests drive
     *  [runNdCleanupIfQuiet] directly. */
    private val ndCleanupScope: CoroutineScope? = null,
    private val ndCleanupDelayMillis: Long = 4_000,
) {
    // Catalog + custom films; replaced via [setFilms] when the custom library changes.
    private var films: List<FilmIdentity> = films

    private val shutterLabels = ExposureScale.oneThirdStopShutterCameraLabels

    /**
     * Ordered ND stop values shown on the wheel: whole stops 0…30 plus the
     * three commercial presets (PTIMER-209), in numeric order. The wheel index
     * is a position into this list, decoupled from the stop value it carries.
     */
    private val ndStopValues: List<Double> = ExposureScale.shippingNDLadder.map { it.stops }
    private val defaultShutterIndex = shutterLabels.indexOf("1/30").coerceAtLeast(0)

    // App-global ND notation display mode (PTIMER-187); display-only, never feeds calc.
    private var ndNotationMode: NDNotationMode = NDNotationMode.DEFAULT

    /** ND wheel labels for the current notation mode (same length/order as the stop ladder). */
    private fun ndLabels(): List<String> =
        ndStopValues.map { NDNotationFormatter.display(it, ndNotationMode).value }

    /** Effective (summed) ND stops for a snapshot's wheel stack. */
    private fun ndStopsOf(snapshot: SlotCalculatorSnapshot): Double =
        snapshot.canonicalNdStackStops().sum()

    /** Wheel position for a canonical stop value: the nearest ladder entry. */
    private fun ndWheelIndex(stops: Double): Int =
        ndStopValues.indices.minByOrNull { abs(ndStopValues[it] - stops) } ?: 0

    // --- ND wheel stack interaction state (PTIMER-199, iOS-parity) ---

    /** Stable identity per active-slot wheel (101+, never index-like). */
    private var ndWheelIds: List<Int> = emptyList()
    private var nextNdWheelId = 101

    /** Wheels currently in motion or under a finger (first-class
     *  Compose signals reported by the UI). Structural mutation and
     *  the set commit require this to be empty. */
    private val activeNdWheelIds = mutableSetOf<Int>()

    /** Selections recorded while wheels move, applied as ONE SET when
     *  the last wheel goes quiet. Insertion order = settle order. */
    private val pendingNdCommits = LinkedHashMap<Int, Double>()

    private fun makeNdWheelId(): Int = nextNdWheelId++

    private fun activeNdStack(): NdFilterStack =
        NdFilterStack(session.activeSnapshot.canonicalNdStackStops())

    /** Regenerates wheel identities for the active slot's stack. */
    private fun syncNdWheelIds() {
        val count = session.activeSnapshot.canonicalNdStackStops().size
        if (ndWheelIds.size != count) {
            ndWheelIds = List(count) { makeNdWheelId() }
        }
        rearmNdCleanupTimer()
    }

    /** Controller-owned self-cleaning timer for committed 0-stop
     *  wheels. (Re)armed on STRUCTURAL changes only — commit writes
     *  and identity re-syncs — never on display-value publishes, so
     *  a fresh zero always gets the full grace period. Interaction
     *  defers cleanup through the fire-time judgment in
     *  [runNdCleanupIfQuiet], not by rescheduling. */
    private var ndCleanupJob: Job? = null

    private fun rearmNdCleanupTimer() {
        ndCleanupJob?.cancel()
        ndCleanupJob = null
        val scope = ndCleanupScope ?: return
        if (!activeNdStack().canRemoveEmptyWheel) return
        ndCleanupJob = scope.launch {
            while (true) {
                delay(ndCleanupDelayMillis)
                // Fires blind; the judgment decides. A refusal (a
                // wheel was moving) re-arms; a stack that stopped
                // being cleanable ends the loop.
                if (runNdCleanupIfQuiet()) break
                if (!activeNdStack().canRemoveEmptyWheel) break
            }
        }
    }

    /** Slot switches and resets discard in-flight selections. */
    private fun clearNdInteraction() {
        activeNdWheelIds.clear()
        pendingNdCommits.clear()
    }

    /** Per-wheel ladder: the shipping ladder top-truncated to the
     *  wheel's remaining budget (derived from COMMITTED values only,
     *  so sibling ladders never reload while another wheel moves). */
    private fun ndWheelLadderStops(index: Int, stack: NdFilterStack): List<Double> {
        val budget = stack.remainingBudget(excludingWheelAt = index)
        return ndStopValues.filter { it <= budget + ExposureCalculator.STABILITY_EPSILON }
    }

    private fun isSaturated(stack: NdFilterStack): Boolean =
        stack.effectiveStops >=
            NdFilterStack.MAX_TOTAL_STOPS - ExposureCalculator.STABILITY_EPSILON

    /** C1: a new wheel must be able to hold a value above 0. */
    private fun ndLadderAllowsNewWheel(stack: NdFilterStack): Boolean {
        if (!stack.canAddWheel) return false
        val budget = NdFilterStack.MAX_TOTAL_STOPS - stack.effectiveStops
        return ndStopValues.any {
            it > 0.0 && it <= budget + ExposureCalculator.STABILITY_EPSILON
        }
    }

    /** Writes the committed stack; the legacy scalar fields carry the
     *  MAXIMUM wheel so an older build downgrades to the strongest
     *  single filter (iOS parity). */
    private fun writeNdStack(stack: NdFilterStack) {
        val maxWheel = stack.entries.max()
        session.updateActiveSnapshot {
            it.copy(
                ndStack = stack.entries,
                ndIndex = NDStep(maxWheel).wholeStops ?: maxWheel.roundToInt(),
                ndStops = ExposureScale.commercialNDPresetStop(maxWheel),
            )
        }
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
        // Activity flips the quiet-gated availability flags
        // (canAddNdWheel, canCleanupEmptyNdWheels) even when no value
        // has changed yet; equal states dedup downstream.
        publish()
    }

    /** SnapWheel emission for one wheel: records the selection (live
     *  display + pending set commit). A value equal to the wheel's
     *  committed entry clears the record — programmatic re-centers
     *  and return-to-committed scrolls leave nothing pending. */
    fun setNdWheelValue(wheelId: Int, ladderIndex: Int) {
        val wheelIndex = ndWheelIds.indexOf(wheelId)
        if (wheelIndex < 0) return
        val stack = activeNdStack()
        val ladder = ndWheelLadderStops(wheelIndex, stack)
        val stops = ladder.getOrNull(ladderIndex) ?: return
        if (abs(stops - stack.entries[wheelIndex]) <= ExposureCalculator.STABILITY_EPSILON) {
            pendingNdCommits.remove(wheelId)
        } else {
            // Provisional position: last-change order stands in until
            // the wheel settles, when setNdWheelActive(_, false) moves
            // the entry to the tail so the barrier applies in true
            // settle order.
            pendingNdCommits.remove(wheelId)
            pendingNdCommits[wheelId] = stops
        }
        publish()
        commitNdSetIfQuiet()
    }

    /** The set commit (barrier): applies pendings in settle order
     *  (the domain refuses over-30 applications; that wheel
     *  reverts), sheds zeros when the set saturates the cap (A0),
     *  sorts once with identity following the permutation, persists
     *  once via the caller's export flow. */
    private fun commitNdSetIfQuiet() {
        if (activeNdWheelIds.isNotEmpty() || pendingNdCommits.isEmpty()) return
        var applied = activeNdStack()
        for ((wheelId, stops) in pendingNdCommits) {
            val index = ndWheelIds.indexOf(wheelId)
            if (index >= 0) applied = applied.replacingWheel(index, stops)
        }
        pendingNdCommits.clear()
        val permutation = applied.commitSortPermutation()
        var sorted = applied.sortedForCommit()
        var ids = permutation.map { ndWheelIds[it] }
        if (isSaturated(sorted)) {
            while (sorted.canRemoveEmptyWheel) {
                val zeroIndex = sorted.entries.indexOfLast { it == 0.0 }
                sorted = sorted.removingEmptyWheel(at = zeroIndex)
                ids = ids.filterIndexed { i, _ -> i != zeroIndex }
            }
        }
        ndWheelIds = ids
        writeNdStack(sorted)
    }

    /** Adds a 0-stop wheel (C1 + quiet-machine gate). */
    fun addNdWheel() {
        if (activeNdWheelIds.isNotEmpty() || pendingNdCommits.isNotEmpty()) return
        val stack = activeNdStack()
        if (!ndLadderAllowsNewWheel(stack)) return
        ndWheelIds = ndWheelIds + makeNdWheelId()
        writeNdStack(stack.addingWheel())
    }

    /** Overscroll-past-zero removal: removes exactly the pulled
     *  wheel; refused while any OTHER wheel is still in motion. */
    fun removeNdWheelFromOverscroll(wheelId: Int) {
        if ((activeNdWheelIds - wheelId).isNotEmpty()) return
        activeNdWheelIds.remove(wheelId)
        pendingNdCommits.remove(wheelId)
        val index = ndWheelIds.indexOf(wheelId)
        val stack = activeNdStack()
        if (index >= 0 && stack.entries.getOrNull(index) == 0.0 && stack.entries.size > 1) {
            ndWheelIds = ndWheelIds.filterIndexed { i, _ -> i != index }
            writeNdStack(stack.removingEmptyWheel(at = index))
        }
        // Dropping the pulled wheel from the active set may be the
        // transition to quiet — this is the one mutation path besides
        // setNdWheelActive(false) that can newly satisfy the barrier,
        // so it must attempt the flush itself rather than rely on a
        // later UI event.
        commitNdSetIfQuiet()
    }

    /** A2 cleanup in one action (TalkBack command and the fire-time
     *  timer's execution path): removes ALL 0-stop wheels when a
     *  non-zero wheel exists; keeps exactly one otherwise. */
    fun cleanupEmptyNdWheels() {
        if (activeNdWheelIds.isNotEmpty() || pendingNdCommits.isNotEmpty()) return
        var stack = activeNdStack()
        if (!stack.canRemoveEmptyWheel) return
        var ids = ndWheelIds
        while (stack.canRemoveEmptyWheel) {
            val zeroIndex = stack.entries.indexOfLast { it == 0.0 }
            stack = stack.removingEmptyWheel(at = zeroIndex)
            ids = ids.filterIndexed { i, _ -> i != zeroIndex }
        }
        ndWheelIds = ids
        writeNdStack(stack)
    }

    /** Fire-time judgment for the UI-hosted 4-second timer (v2 §8):
     *  executes only when the machine is quiet and the stack is
     *  still cleanable; the caller re-arms otherwise. Returns
     *  whether a cleanup ran. */
    fun runNdCleanupIfQuiet(): Boolean {
        if (activeNdWheelIds.isNotEmpty() || pendingNdCommits.isNotEmpty()) return false
        if (!activeNdStack().canRemoveEmptyWheel) return false
        cleanupEmptyNdWheels()
        return true
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
    private val currentNdStops: Double get() = ndStopsOf(session.activeSnapshot)
    private val selectedFilmId: String? get() = session.activeSnapshot.selectedFilmId
    private val selectedProfileId: String? get() = session.activeSnapshot.selectedProfileId
    private val targetSeconds: Double? get() = session.activeSnapshot.targetSeconds

    init {
        // Normalize the restored active slot (coerce indices, drop a stale film /
        // profile reference) so a deleted custom film is not re-persisted as a
        // broken selection. Inactive slots normalize when they become active.
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
        // stack with one wheel holding the value (iOS `ndStep` setter
        // parity). The stack path goes through `setNdWheelValue`.
        val stops = ndStopValues[index.coerceIn(ndStopValues.indices)]
        clearNdInteraction()
        ndWheelIds = listOf(makeNdWheelId())
        session.updateActiveSnapshot {
            it.copy(
                ndIndex = NDStep(stops).wholeStops ?: stops.roundToInt(),
                ndStops = ExposureScale.commercialNDPresetStop(stops),
                ndStack = listOf(stops),
            )
        }
        publish()
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
        session.updateActiveSnapshot { defaultSnapshot }
        clearNdInteraction()
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
        // arriving slot gets fresh wheel identities.
        clearNdInteraction()
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
     */
    private fun normalizeSnapshot(snapshot: SlotCalculatorSnapshot): SlotCalculatorSnapshot {
        val film = snapshot.selectedFilmId?.let { id -> films.firstOrNull { it.id == id } }
        return SlotCalculatorSnapshot(
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

    private fun publish() { _state.value = compute() }

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
        return TimerIdentity(
            title = "${slot.displayName} · $filmName",
            subtitle = "$source ${exposure.formatExtendedClock(finalSeconds)}",
            slotLabel = slot.id.shortLabel,
            ndStops = currentNdStops,
            baseShutterSeconds = base,
            adjustedShutterSeconds = result.adjustedShutterSeconds,
            basisIncludesAdjusted = includesAdjusted,
            filmName = filmName,
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
        val film = snapshot.selectedFilmId?.let { id -> films.firstOrNull { it.id == id } }
        val profile = resolvedProfileFor(film, snapshot.selectedProfileId)
        val committedStack = NdFilterStack(snapshot.canonicalNdStackStops())
        val isActiveSlot = slotId == session.activeSlotId
        // Active slot: pending selections overlay their wheels so the
        // result follows each wheel while the set commit is open.
        val effectiveStops = if (isActiveSlot) {
            committedStack.entries.mapIndexed { i, committed ->
                ndWheelIds.getOrNull(i)?.let { pendingNdCommits[it] } ?: committed
            }.sum()
        } else {
            committedStack.effectiveStops
        }
        val result = calculator.result(snapshot.shutterIndex, effectiveStops, profile)
        val ndWheels = committedStack.entries.mapIndexed { i, committed ->
            val wheelId = if (isActiveSlot) ndWheelIds.getOrElse(i) { i } else i
            val display = if (isActiveSlot) pendingNdCommits[wheelId] ?: committed else committed
            val ladder = ndWheelLadderStops(i, committedStack)
            NdWheelUiState(
                id = wheelId,
                labels = ladder.map { NDNotationFormatter.display(it, ndNotationMode).value },
                selectedIndex = ladder.indexOfFirst {
                    abs(it - display) <= ExposureCalculator.STABILITY_EPSILON
                }.coerceAtLeast(0),
            )
        }
        val showsAdd = ndLadderAllowsNewWheel(committedStack)
        val modelOptions = film?.let { f ->
            val options = modelProfiles(f)
            if (options.size > 1) options.map { ModelOption(it.id, it.selectorLabel ?: it.name) } else emptyList()
        } ?: emptyList()

        val canReset = snapshot.shutterIndex != defaultShutterIndex ||
            committedStack.entries != listOf(0.0) ||
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
            ndIndex = ndWheelIndex(ndStopsOf(snapshot)),
            ndWheels = ndWheels,
            showsAddNdWheel = showsAdd,
            canAddNdWheel = showsAdd &&
                (!isActiveSlot || (activeNdWheelIds.isEmpty() && pendingNdCommits.isEmpty())),
            canRemoveEmptyNdWheel = committedStack.canRemoveEmptyWheel,
            canCleanupEmptyNdWheels = committedStack.canRemoveEmptyWheel &&
                (!isActiveSlot || (activeNdWheelIds.isEmpty() && pendingNdCommits.isEmpty())),
            ndTotalStopsText = if (committedStack.entries.size >= 2) {
                formatTotalStops(effectiveStops)
            } else {
                null
            },
            // Same live basis as the total text, so the badge never
            // shows "30" without its Maximum marker mid-scroll.
            ndTotalIsMaximum = committedStack.entries.size >= 2 &&
                effectiveStops >=
                NdFilterStack.MAX_TOTAL_STOPS - ExposureCalculator.STABILITY_EPSILON,
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
