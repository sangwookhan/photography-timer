package com.sangwook.ptimer.vm

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.initializer
import androidx.lifecycle.viewmodel.viewModelFactory
import com.sangwook.ptimer.calculator.CalculatorController
import com.sangwook.ptimer.calculator.CalculatorUiState
import com.sangwook.ptimer.core.catalog.LaunchPresetFilmCatalogLoader
import com.sangwook.ptimer.core.exposure.ExposureScale
import com.sangwook.ptimer.core.reciprocity.TableAnchor
import com.sangwook.ptimer.customfilm.CreateFormulaFromTable
import com.sangwook.ptimer.customfilm.CustomFilmFactory
import com.sangwook.ptimer.customfilm.CustomFilmIdSequencer
import com.sangwook.ptimer.customfilm.CustomFilmLibrary
import com.sangwook.ptimer.customfilm.CustomFilmLibraryCodec
import com.sangwook.ptimer.customfilm.CustomFilmResult
import com.sangwook.ptimer.notifications.NoOpTimerNotifier
import com.sangwook.ptimer.notifications.TimerNotifier
import com.sangwook.ptimer.slots.CameraSlotSession
import com.sangwook.ptimer.slots.SlotSessionCodec
import com.sangwook.ptimer.timer.AlwaysExactAlarmAvailability
import com.sangwook.ptimer.timer.ExactAlarmAvailability
import com.sangwook.ptimer.timer.NoOpTimerCompletionScheduler
import com.sangwook.ptimer.timer.TimerCompletionScheduler
import com.sangwook.ptimer.timer.TimerStore
import com.sangwook.ptimer.timer.TimerWorkspaceController
import com.sangwook.ptimer.timer.TimerWorkspaceUiState
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

data class FilmRowUi(val id: String, val name: String, val manufacturer: String?, val iso: Int, val isCustom: Boolean)
data class SlotChipUi(val id: String, val label: String, val isActive: Boolean)
data class SlotsUiState(val slots: List<SlotChipUi>, val activeLabel: String)

/** One-way UI events for the shooting/timer workspace. */
sealed interface ShootingIntent {
    data class NudgeBaseShutter(val delta: Int) : ShootingIntent
    data class SetNdStops(val stops: Int) : ShootingIntent
    data class SelectFilm(val id: String?) : ShootingIntent
    data object ClearFilm : ShootingIntent
    data class SelectModel(val profileId: String?) : ShootingIntent
    data object StartAdjusted : ShootingIntent
    data object StartCorrected : ShootingIntent
    data object StartTarget : ShootingIntent
    data class SelectSlot(val id: String) : ShootingIntent
    data class RenameSlot(val id: String, val name: String) : ShootingIntent
    data class ResetSlotName(val id: String) : ShootingIntent
    data class CreateCustomFormula(val name: String, val exponent: Double, val noCorrectionThroughSeconds: Double) : ShootingIntent
    data class CreateCustomTable(val name: String, val anchors: List<Pair<Double, Double>>) : ShootingIntent
    data object CreateFormulaFromSelectedTable : ShootingIntent
    data class DeleteCustomFilm(val id: String) : ShootingIntent
    data class SetTarget(val seconds: Double) : ShootingIntent
    data object ClearTarget : ShootingIntent
    data object OpenDetails : ShootingIntent
    data object CloseDetails : ShootingIntent
    data class Pause(val id: String) : ShootingIntent
    data class Resume(val id: String) : ShootingIntent
    data class Remove(val id: String) : ShootingIntent
    data class StartAgain(val id: String) : ShootingIntent
    data class StartNew(val id: String) : ShootingIntent
    data object ClearCompleted : ShootingIntent
    data object DismissExactAlarmPrompt : ShootingIntent
}

class ShootingViewModel(
    private val timerStore: TimerStore,
    private val sessionStore: TimerStore,
    private val customStore: TimerStore,
    private val notifier: TimerNotifier = NoOpTimerNotifier,
    private val scheduler: TimerCompletionScheduler = NoOpTimerCompletionScheduler,
    private val exactAlarms: ExactAlarmAvailability = AlwaysExactAlarmAvailability,
) : ViewModel() {

    private val catalog = LaunchPresetFilmCatalogLoader.loadBundledCatalog()
    private val calc = CalculatorController(catalog)
    private val timer = TimerWorkspaceController()
    private val session = CameraSlotSession()
    private var customLib = CustomFilmLibrary()
    private var customSeq = 0

    val timerState: StateFlow<TimerWorkspaceUiState> = timer.state

    private val _calcState = MutableStateFlow(calc.uiState())
    val calcState: StateFlow<CalculatorUiState> = _calcState.asStateFlow()
    private val _slotsState = MutableStateFlow(slotsSnapshot())
    val slotsState: StateFlow<SlotsUiState> = _slotsState.asStateFlow()
    private val _films = MutableStateFlow(buildFilms())
    val films: StateFlow<List<FilmRowUi>> = _films.asStateFlow()
    private val _detailsState = MutableStateFlow<com.sangwook.ptimer.details.DetailsUi?>(null)
    val detailsState: StateFlow<com.sangwook.ptimer.details.DetailsUi?> = _detailsState.asStateFlow()

    private var tickJob: Job? = null
    /** Ids we currently hold a scheduled completion alarm for (for cancel reconciliation). */
    private val scheduledIds = mutableSetOf<String>()
    /** Session flag: once the user dismisses the exact-alarm notice we stop showing it. */
    private var exactAlarmPromptDismissed = false

    private val _exactAlarmPrompt = MutableStateFlow(false)
    /**
     * True only when a timer is running, exact alarms are not currently
     * permitted, and the user has not dismissed the notice — i.e. completion is
     * on the best-effort inexact path and a one-tap fix exists. The UI surfaces
     * a compact, dismissible notice; timer usage is never blocked.
     */
    val exactAlarmPrompt: StateFlow<Boolean> = _exactAlarmPrompt.asStateFlow()

    private val _ready = MutableStateFlow(false)
    /**
     * False until the asynchronous restore (timers / custom films / camera-slot
     * session) has finished. Restore runs on [viewModelScope] and overwrites
     * calculator/slot state, so a user intent that lands before it completes
     * could be silently clobbered. While not ready, [onEvent] ignores intents
     * (see its guard); the UI can also observe this to keep controls inert.
     */
    val ready: StateFlow<Boolean> = _ready.asStateFlow()

    init {
        calc.setBaseShutterLadderIndex(nearestBaseIndex(com.sangwook.ptimer.core.exposure.CalculatorDefaults.BASE_SHUTTER_SECONDS))
        viewModelScope.launch {
            // Restore is fail-safe for PERSISTENCE only: each store's load +
            // decode runs behind its own runCatching with a documented fallback
            // (timers→none, custom→empty library, session→defaults), so a
            // throwing/corrupt store can never leave the app permanently inert.
            // The application wiring below (restoreFromJson / session.restore /
            // calc.apply) is intentionally OUTSIDE those catches, so a genuine
            // programmer error there surfaces instead of being swallowed.
            // `ready` is always set in `finally`.
            try {
                // 1) Load + decode each store independently (failures swallowed).
                val timerJson = runCatching { timerStore.load() }.getOrNull()
                val loadedCustomFilms = runCatching {
                    customStore.load()?.let { CustomFilmLibraryCodec.decode(it) }
                }.getOrNull()
                val restoredSession = runCatching {
                    sessionStore.load()?.let { SlotSessionCodec.decode(it) }
                }.getOrNull()

                // 2) Apply the loaded data (NOT swallowed — wiring errors surface).
                timer.restoreFromJson(timerJson)
                loadedCustomFilms?.let { customLib = CustomFilmLibrary(it) }
                // Seed the id sequencer from whichever library actually loaded.
                customSeq = CustomFilmIdSequencer.nextSequence(customLib.all.map { it.id })
                calc.setCustomFilms(customLib.all)
                // Session is applied AFTER custom films, so a session that
                // references a custom film id resolves it (or falls back to
                // digital via CalculatorController sanitation when absent).
                restoredSession?.let { restored ->
                    session.restore(restored.activeSlotId, restored.snapshots, restored.names)
                    calc.apply(session.snapshot(session.activeSlotId))
                }
            } finally {
                _films.value = buildFilms()
                refreshCalc(); refreshSlots(); updateOngoing(); ensureTicking()
                // (Re)schedule completion alarms for restored pending timers;
                // overdue running timers were already reconciled to completed by
                // the core restore contract, so they are not scheduled here.
                syncSchedules()
                _ready.value = true
            }
        }
    }

    /**
     * Reconcile OS-level completion alarms with the current running timers:
     * cancel alarms for timers we previously scheduled that are no longer
     * running (paused / completed / removed), and (re)schedule each running
     * timer at its expected completion. Idempotent — re-scheduling the same id
     * replaces its alarm, so repeated restore/apply paths never duplicate.
     * Wrapped so a scheduler failure can never break the timer workflow.
     */
    private fun syncSchedules() {
        runCatching {
            val targets = timer.runningCompletionTargets()
            val runningIds = targets.map { it.snapshot.id }.toSet()
            val stale = scheduledIds - runningIds
            if (stale.isNotEmpty()) scheduler.cancelAll(stale)
            targets.forEach { scheduler.schedule(it.snapshot, it.title, it.subtitle) }
            scheduledIds.clear(); scheduledIds.addAll(runningIds)
        }
        refreshExactAlarmPrompt()
    }

    /** Show the exact-alarm notice only when it can actually help (running timer + not permitted + not dismissed). */
    private fun refreshExactAlarmPrompt() {
        _exactAlarmPrompt.value =
            timer.hasRunning() && !exactAlarms.canScheduleExact() && !exactAlarmPromptDismissed
    }

    private fun updateOngoing() {
        val rep = timer.representative()
        if (rep != null) notifier.showOngoing(rep.title, rep.remainingLabel) else notifier.clearOngoing()
    }

    fun onEvent(intent: ShootingIntent) {
        // Ignore intents until the async restore completes; otherwise an early
        // user action would run against default state and then be overwritten
        // by restore (a lost-update race).
        if (!_ready.value) return
        when (intent) {
            is ShootingIntent.NudgeBaseShutter -> {
                val next = (nearestBaseIndex(calc.currentBaseSeconds()) + intent.delta)
                    .coerceIn(0, ExposureScale.oneThirdStop.shutterSteps.lastIndex)
                calc.setBaseShutterLadderIndex(next); afterCalcChange()
            }
            is ShootingIntent.SetNdStops -> { calc.setNdStops(intent.stops); afterCalcChange() }
            is ShootingIntent.SelectFilm -> { calc.selectFilm(intent.id); afterCalcChange() }
            ShootingIntent.ClearFilm -> { calc.clearFilm(); afterCalcChange() }
            is ShootingIntent.SelectModel -> { calc.selectModel(intent.profileId); afterCalcChange() }
            ShootingIntent.StartAdjusted -> startFrom(calc.adjustedAction())
            ShootingIntent.StartCorrected -> calc.correctedAction()?.let { startFrom(it) }
            ShootingIntent.StartTarget -> calc.targetAction()?.let { startFrom(it) }
            is ShootingIntent.SelectSlot -> {
                session.store(session.activeSlotId, calc.capture())
                session.activate(intent.id); calc.apply(session.snapshot(intent.id))
                refreshCalc(); refreshSlots(); persistSession()
            }
            is ShootingIntent.RenameSlot -> { session.setCustomName(intent.id, intent.name); refreshSlots(); persistSession() }
            is ShootingIntent.ResetSlotName -> { session.resetName(intent.id); refreshSlots(); persistSession() }
            is ShootingIntent.CreateCustomFormula -> {
                val id = newCustomId("formula")
                val r = CustomFilmFactory.buildFormula(id, intent.name, 100, exponent = intent.exponent, noCorrectionThroughSeconds = intent.noCorrectionThroughSeconds)
                if (r is CustomFilmResult.Success) { adoptCustom(r.film); calc.selectFilm(id); afterCalcChange() }
            }
            is ShootingIntent.CreateCustomTable -> {
                val id = newCustomId("table")
                val anchors = intent.anchors.map { TableAnchor(it.first, it.second) }
                val r = CustomFilmFactory.buildTable(id, intent.name, 100, anchors)
                if (r is CustomFilmResult.Success) { adoptCustom(r.film); calc.selectFilm(id); afterCalcChange() }
            }
            ShootingIntent.CreateFormulaFromSelectedTable -> {
                val tableId = calc.currentFilmId() ?: return
                val table = customLib.film(tableId) ?: return
                CreateFormulaFromTable.create(table, newCustomId("formula"))?.let { formula ->
                    adoptCustom(formula); calc.selectFilm(formula.id); afterCalcChange()
                }
            }
            is ShootingIntent.DeleteCustomFilm -> {
                customLib.remove(intent.id)
                if (calc.currentFilmId() == intent.id) calc.clearFilm()
                calc.setCustomFilms(customLib.all); _films.value = buildFilms(); refreshCalc(); persistCustom()
            }
            is ShootingIntent.SetTarget -> { calc.setTarget(intent.seconds); afterCalcChange() }
            ShootingIntent.ClearTarget -> { calc.clearTarget(); afterCalcChange() }
            ShootingIntent.OpenDetails -> {
                _detailsState.value = calc.details { id -> customLib.film(id) ?: catalog.firstOrNull { it.id == id } }
            }
            ShootingIntent.CloseDetails -> { _detailsState.value = null }
            is ShootingIntent.Pause -> { timer.pause(intent.id); persistTimers(); syncSchedules(); ensureTicking() }
            is ShootingIntent.Resume -> { timer.resume(intent.id); persistTimers(); syncSchedules(); ensureTicking() }
            is ShootingIntent.Remove -> { timer.remove(intent.id); persistTimers(); syncSchedules() }
            is ShootingIntent.StartAgain -> { timer.startAgain(intent.id); persistTimers(); syncSchedules(); ensureTicking() }
            is ShootingIntent.StartNew -> { timer.cloneToNew(intent.id); persistTimers(); syncSchedules(); ensureTicking() }
            ShootingIntent.ClearCompleted -> { timer.clearCompleted(); persistTimers(); syncSchedules() }
            ShootingIntent.DismissExactAlarmPrompt -> { exactAlarmPromptDismissed = true; refreshExactAlarmPrompt() }
        }
        updateOngoing()
    }

    private fun startFrom(action: com.sangwook.ptimer.calculator.StartActionState) {
        val duration = action.durationSeconds
        if (!action.enabled || duration == null) return
        val cs = _calcState.value
        val metadata = "Base ${cs.baseShutterLabel} · ND ${cs.ndStops} · Adjusted ${cs.adjustedShutterLabel}"
        timer.start("${session.activeLabel()} · ${action.filmContext}", action.subtitle, metadata, action.source, duration)
        persistTimers(); syncSchedules(); ensureTicking()
    }

    private fun adoptCustom(film: com.sangwook.ptimer.core.catalog.FilmIdentity) {
        customLib.upsert(film); calc.setCustomFilms(customLib.all); _films.value = buildFilms(); persistCustom()
    }

    private fun newCustomId(prefix: String): String = CustomFilmIdSequencer.id(prefix, customSeq++)

    private fun buildFilms(): List<FilmRowUi> =
        catalog.map { FilmRowUi(it.id, it.canonicalStockName, it.manufacturer, it.iso, false) } +
            customLib.all.map { FilmRowUi(it.id, it.canonicalStockName, it.manufacturer, it.iso, true) }

    private fun afterCalcChange() { refreshCalc(); persistSession() }
    private fun refreshCalc() { _calcState.value = calc.uiState() }
    private fun refreshSlots() { _slotsState.value = slotsSnapshot() }

    private fun slotsSnapshot(): SlotsUiState = SlotsUiState(
        slots = session.slotIds.map { SlotChipUi(it, session.label(it), it == session.activeSlotId) },
        activeLabel = session.activeLabel(),
    )

    private fun nearestBaseIndex(seconds: Double): Int {
        val ladder = ExposureScale.oneThirdStop.shutterSteps
        return ladder.indices.minByOrNull { kotlin.math.abs(ladder[it].seconds - seconds) } ?: 0
    }

    private fun ensureTicking() {
        if (tickJob != null || !timer.hasRunning()) return
        tickJob = viewModelScope.launch {
            while (timer.hasRunning()) {
                delay(TICK_MILLIS)
                val completed = timer.tick()
                completed.forEach { notifier.postCompletion(it, timer.titleOf(it) ?: "Timer", timer.subtitleOf(it)) }
                if (completed.isNotEmpty()) { persistTimers(); syncSchedules() } // consume fired alarms
                updateOngoing()
            }
            updateOngoing(); persistTimers(); tickJob = null
        }
    }

    private fun persistTimers() { val json = timer.snapshotJson(); viewModelScope.launch { timerStore.save(json) } }
    private fun persistSession() {
        session.store(session.activeSlotId, calc.capture())
        val json = SlotSessionCodec.encode(session)
        viewModelScope.launch { sessionStore.save(json) }
    }
    private fun persistCustom() { val json = CustomFilmLibraryCodec.encode(customLib.all); viewModelScope.launch { customStore.save(json) } }

    companion object {
        private const val TICK_MILLIS = 100L

        fun factory(
            timerStore: TimerStore,
            sessionStore: TimerStore,
            customStore: TimerStore,
            notifier: TimerNotifier,
            scheduler: TimerCompletionScheduler = NoOpTimerCompletionScheduler,
            exactAlarms: ExactAlarmAvailability = AlwaysExactAlarmAvailability,
        ) = viewModelFactory {
            initializer { ShootingViewModel(timerStore, sessionStore, customStore, notifier, scheduler, exactAlarms) }
        }
    }
}
