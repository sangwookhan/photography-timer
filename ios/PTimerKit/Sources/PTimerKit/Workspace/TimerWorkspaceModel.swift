// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import Combine
import Foundation
import PTimerCore

/// `TimerWorkspaceModel` owns the timer-workspace slice. The model owns:
/// - the `any TimerManaging` instance (the live timer state machine)
/// - timer metadata persistence (the `*Storing` store + the
///   `timerMetadata` dict + `nextTimerOrder`)
/// - the published `timers: [RunningTimerItem]` collection that views
///   bind to
/// - the timer lifecycle operations the ViewModel previously hosted
///   (`pause` / `resume` / `remove` / `clearCompletedTimers` /
///   `start(id:duration:name:basisSummary:)`)
/// - the `completedRelativeTimeFormatter` used to drive the
///   terminal "N minutes ago" refresh schedule for completed and
///   canceled history rows.
///
/// This model carries timer state only. Cross-cutting "start timer
/// from calculation result" wiring belongs to `WorkspaceCoordinator`
/// and the view-model facade.
@MainActor
public final class TimerWorkspaceModel: ObservableObject {
    @Published public private(set) var timers: [RunningTimerItem] = []

    /// Exposed to the ViewModel so it can construct the "Tri-X 400 - 2s"
    /// timer name from the active calc/film state before delegating to
    /// `start(id:duration:metadata:)`. Kept private(set) — only the
    /// model mutates it via persistence + lifecycle paths.
    public private(set) var nextTimerOrder = 1

    public let sessions: ShootingSessionLedger
    @Published public var shortenedSessionIntervals = false {
        didSet { timingStore.saveShortenedIntervals(shortenedSessionIntervals) }
    }
    private let timingStore: ShootingSessionTimingStoring
    @Published public private(set) var startError: String?
    private var pendingStart: (id: UUID, duration: TimeInterval)?

    public let cancellationNotice: TimerCancellationNoticeModel
    public let timerManager: any TimerManaging

    private let metadataPersistenceStore: TimerMetadataPersistenceStoring
    private let completedRelativeTimeFormatter = CompletedRelativeTimeFormatter()
    private var timerMetadata: [UUID: TimerMetadataEntry] = [:]
    private var cancellables: Set<AnyCancellable> = []
    private var completedTimeContextRefreshTimer: Timer?

    /// Closure used to derive the human-readable fallback name for a
    /// timer whose metadata entry was not registered (e.g., a timer
    /// that survived a relaunch where the metadata snapshot was
    /// cleared). Provided as a closure so the model can format a
    /// fallback timer label without holding a direct reference to
    /// `ExposureCalculator`.
    private let defaultName: (TimeInterval) -> String

    public init(
        timerManager: any TimerManaging,
        metadataPersistenceStore: TimerMetadataPersistenceStoring,
        defaultName: @escaping (TimeInterval) -> String,
        sessionStore: ShootingSessionStoring = NoOpShootingSessionStore(),
        timingStore: ShootingSessionTimingStoring = NoOpShootingSessionTimingStore()
    ) {
        self.timingStore = timingStore
        self.shortenedSessionIntervals = timingStore.loadShortenedIntervals()
        self.sessions = ShootingSessionLedger(store: sessionStore)
        self.cancellationNotice = TimerCancellationNoticeModel(timerManager: timerManager)
        self.timerManager = timerManager
        self.metadataPersistenceStore = metadataPersistenceStore
        self.defaultName = defaultName

        restorePersistedTimerMetadata()
        timerManager.timersPublisher
            .sink { [weak self] states in
                MainActor.assumeIsolated { self?.syncTimers(with: states) }
            }
            .store(in: &cancellables)
    }

    // MARK: - Lifecycle

    /// Starts a timer with the given metadata. Returns the timer's id
    /// on success; nil if `any TimerManaging` rejected the duration.
    /// The model writes metadata before calling `any TimerManaging`, rolls
    /// metadata back on failure, and bumps `nextTimerOrder` on success.
    @discardableResult
    public func startTimer(
        id: UUID = UUID(),
        duration: TimeInterval,
        name: String,
        basisSummary: String,
        cameraSlot: CameraSlotIdentity? = nil,
        filmDisplayName: String? = nil,
        filmProfileQualifier: String? = nil,
        exposureSource: ExposureTimerSource? = nil,
        isOutsideManufacturerGuidance: Bool = false,
        customProfileSummary: String? = nil,
        selectedModelLabel: String? = nil,
        ndStops: Double? = nil,
        baseShutterSeconds: TimeInterval? = nil,
        adjustedShutterSeconds: TimeInterval? = nil,
        filterSummary: [FilterSummaryEntry]? = nil,
        filterReferenceText: String? = nil
    ) -> UUID? {
        guard duration.isFinite, duration > 0 else { return nil }
        startError = nil
        let requestedID = pendingStart?.id ?? id
        let requestedDuration = pendingStart?.duration ?? duration
        let order = nextTimerOrder
        if pendingStart == nil {
            timerMetadata[requestedID] = TimerMetadataEntry(
                order: order,
                name: name,
                basisSummary: basisSummary,
                cameraSlot: cameraSlot,
                filmDisplayName: filmDisplayName,
                filmProfileQualifier: filmProfileQualifier,
                exposureSource: exposureSource,
                isOutsideManufacturerGuidance: isOutsideManufacturerGuidance,
                customProfileSummary: customProfileSummary,
                selectedModelLabel: selectedModelLabel,
                ndStops: ndStops,
                baseShutterSeconds: baseShutterSeconds,
                adjustedShutterSeconds: adjustedShutterSeconds,
                filterSummary: filterSummary,
                filterReferenceText: filterReferenceText,
                sessionActivity: .init(
                    startedAt: timerManager.currentDate,
                    policy: shortenedSessionIntervals ? .shortened : .normal
                )
            )
        }
        let preparation = metadataPersistenceStore.savePreparingSnapshot(metadataSnapshot(nextOrder: order + 1))
        guard preparation == .saved else {
            handleStartFailure(id: requestedID, duration: requestedDuration, outcome: preparation)
            return nil
        }
        guard timerManager.start(id: requestedID, duration: requestedDuration) != nil else {
            handleStartFailure(id: requestedID, duration: requestedDuration, outcome: timerManager.startSaveResult)
            return nil
        }
        pendingStart = nil
        nextTimerOrder += 1
        persistTimerMetadata()
        return requestedID
    }

    /// Starts a fresh timer from the source's full duration and captured
    /// setup, with a new identity and order. Running and terminal sources
    /// remain unchanged; a successful start cancels paused sources under
    /// the common pause policy. Returns nil if the duration is rejected.
    @discardableResult
    public func startTimer(
        cloning source: RunningTimerItem,
        id: UUID = UUID()
    ) -> UUID? {
        startTimer(cloningMetadataFrom: source, id: id)
    }

    /// Shared body for the Clone path: starts a new timer that reuses
    /// `source`'s duration and identity-bearing metadata.
    @discardableResult
    private func startTimer(
        cloningMetadataFrom source: RunningTimerItem,
        id: UUID
    ) -> UUID? {
        startTimer(
            id: id,
            duration: source.duration,
            name: source.name,
            basisSummary: source.basisSummary,
            cameraSlot: source.cameraSlot,
            filmDisplayName: source.filmDisplayName,
            filmProfileQualifier: source.filmProfileQualifier,
            exposureSource: source.exposureSource,
            isOutsideManufacturerGuidance: source.isOutsideManufacturerGuidance,
            customProfileSummary: source.customProfileSummary,
            selectedModelLabel: source.selectedModelLabel,
            ndStops: source.ndStops,
            baseShutterSeconds: source.baseShutterSeconds,
            adjustedShutterSeconds: source.adjustedShutterSeconds,
            filterSummary: source.filterSummary,
            filterReferenceText: source.filterReferenceText
        )
    }

    private func handleStartFailure(id: UUID, duration: TimeInterval, outcome: TimerSnapshotSaveResult) {
        if outcome == .uncertain {
            pendingStart = (id, duration)
            startError = String(localized: "Timer start could not be confirmed. Try again to check the same timer.")
        } else {
            pendingStart = nil
            timerMetadata.removeValue(forKey: id)
            startError = String(localized: "Timer could not start because it could not be saved.")
        }
    }

    public func dismissStartError() { startError = nil }

    public func sessionLabel(for timerID: UUID) -> String {
        if let membership = sessions.membership(for: timerID) { return sessions.title(for: membership.sessionID) }
        return timerMetadata[timerID]?.sessionActivity == nil
            ? String(localized: "Unassigned") : String(localized: "Session pending")
    }

    public func retrySessionAssignments() { syncTimers(with: timerManager.timers) }

    public func pauseTimer(id: UUID) {
        timerManager.pause(id: id)
    }

    public func resumeTimer(id: UUID) {
        timerManager.resume(id: id)
    }

    /// Cancels a running or paused timer, keeping it as a terminal
    /// canceled record. Unlike `removeTimer`, the metadata entry is
    /// preserved so the canceled record retains its identity and can
    /// be relaunched via the clone path.
    public func cancelTimer(id: UUID) {
        timerManager.cancel(id: id)
    }

    public func removeTimer(id: UUID) {
        timerManager.remove(id: id)
        timerMetadata.removeValue(forKey: id)
        persistTimerMetadata()
    }

    public func clearCompletedTimers() {
        let completedIDs = Set(
            timers
                .filter { $0.status == .completed }
                .map(\.id)
        )
        timerManager.removeCompletedTimers()
        completedIDs.forEach { id in
            timerMetadata.removeValue(forKey: id)
        }
        persistTimerMetadata()
    }

    public func reconcileTimersAfterAppBecomesActive() {
        timerManager.reconcile(now: nil)
    }

    // MARK: - Display helpers

    public var runningTimerCount: Int {
        timers.filter { $0.status == .running }.count
    }

    public func compactCompletedRelativeTimeText(
        for completionDate: Date?,
        relativeTo referenceDate: Date
    ) -> String {
        guard let completionDate else {
            return "--"
        }

        return completedRelativeTimeFormatter.compactString(
            from: completionDate,
            relativeTo: referenceDate
        )
    }

    public func relativeCompletedText(
        from completionDate: Date,
        relativeTo referenceDate: Date
    ) -> String {
        completedRelativeTimeFormatter.string(
            from: completionDate,
            relativeTo: referenceDate
        )
    }

    // MARK: - Persistence + sync

    private func restorePersistedTimerMetadata() {
        guard let snapshot = metadataPersistenceStore.loadSnapshot() else {
            return
        }

        nextTimerOrder = max(1, snapshot.nextTimerOrder)
        timerMetadata = Dictionary(
            uniqueKeysWithValues: snapshot.timers.map { entry -> (UUID, TimerMetadataEntry) in
                let cameraSlot: CameraSlotIdentity? = {
                    guard let raw = entry.cameraSlotIDRaw,
                          let slotID = CameraSlotID(rawValue: raw) else {
                        return nil
                    }
                    return CameraSlotIdentity(
                        id: slotID,
                        displayName: entry.cameraSlotDisplayName
                    )
                }()
                let exposureSource = entry.exposureSourceRaw
                    .flatMap { ExposureTimerSource(rawValue: $0) }
                return (
                    entry.id,
                    TimerMetadataEntry(
                        order: entry.order,
                        name: entry.name,
                        basisSummary: entry.basisSummary,
                        cameraSlot: cameraSlot,
                        filmDisplayName: entry.filmDisplayName,
                        filmProfileQualifier: entry.filmProfileQualifier,
                        exposureSource: exposureSource,
                        isOutsideManufacturerGuidance: entry.isOutsideManufacturerGuidance ?? false,
                        customProfileSummary: entry.customProfileSummary,
                        selectedModelLabel: entry.selectedModelLabel,
                        ndStops: entry.ndStops,
                        baseShutterSeconds: entry.baseShutterSeconds,
                        adjustedShutterSeconds: entry.adjustedShutterSeconds,
                        filterSummary: entry.filterSummary,
                        filterReferenceText: entry.filterReferenceText,
                        sessionActivity: entry.sessionActivity
                    )
                )
            }
        )
    }

    private func persistTimerMetadata() {
        guard !timerMetadata.isEmpty else {
            metadataPersistenceStore.clearSnapshot()
            return
        }

        metadataPersistenceStore.saveSnapshot(metadataSnapshot(nextOrder: nextTimerOrder))
    }

    private func metadataSnapshot(nextOrder: Int) -> PersistentTimerMetadataCollection {
        PersistentTimerMetadataCollection(
            nextTimerOrder: nextOrder,
            timers: timerMetadata
                .map { id, metadata in
                    PersistentTimerMetadataSnapshot(
                        id: id,
                        order: metadata.order,
                        name: metadata.name,
                        basisSummary: metadata.basisSummary,
                        cameraSlotIDRaw: metadata.cameraSlot?.id.rawValue,
                        cameraSlotDisplayName: metadata.cameraSlot?.displayName,
                        filmDisplayName: metadata.filmDisplayName,
                        filmProfileQualifier: metadata.filmProfileQualifier,
                        exposureSourceRaw: metadata.exposureSource?.rawValue,
                        isOutsideManufacturerGuidance: metadata.isOutsideManufacturerGuidance
                            ? true
                            : nil,
                        customProfileSummary: metadata.customProfileSummary,
                        selectedModelLabel: metadata.selectedModelLabel,
                        ndStops: metadata.ndStops,
                        baseShutterSeconds: metadata.baseShutterSeconds,
                        adjustedShutterSeconds: metadata.adjustedShutterSeconds,
                        filterSummary: metadata.filterSummary,
                        filterReferenceText: metadata.filterReferenceText,
                        sessionActivity: metadata.sessionActivity
                    )
                }
                .sorted { lhs, rhs in
                    if lhs.order != rhs.order {
                        return lhs.order < rhs.order
                    }

                    return lhs.id.uuidString < rhs.id.uuidString
                }
        )

    }

    private func syncTimers(with states: [TimerState]) {
        var validIDs = Set(states.map(\.id))
        if let pendingStart { validIDs.insert(pendingStart.id) }
        let originalCount = timerMetadata.count
        timerMetadata = timerMetadata.filter { validIDs.contains($0.key) }
        if timerMetadata.count != originalCount {
            persistTimerMetadata()
        }
        let referenceDate = timerManager.currentDate
        for state in states {
            if let activity = timerMetadata[state.id]?.sessionActivity,
               activity.startedAt != state.startDate {
                timerMetadata[state.id]?.sessionActivity = .init(startedAt: state.startDate, policy: activity.policy)
            }
        }
        sessions.reconcile(activities: states.compactMap { state in
            guard let metadata = timerMetadata[state.id], let activity = metadata.sessionActivity else { return nil }
            return (state.id, metadata.order, activity)
        })

        timers = states
            .map { state in
                let metadata = timerMetadata[state.id]
                return RunningTimerItem(
                    id: state.id,
                    order: metadata?.order ?? 0,
                    name: metadata?.name ?? defaultName(state.duration),
                    basisSummary: metadata?.basisSummary ?? "Manual timer",
                    duration: state.duration,
                    startDate: state.startDate,
                    endDate: state.endDate,
                    pausedRemainingTime: state.pausedRemainingTime,
                    pausedAt: state.pausedAt,
                    status: state.status,
                    referenceDate: referenceDate,
                    cameraSlot: metadata?.cameraSlot,
                    filmDisplayName: metadata?.filmDisplayName,
                    filmProfileQualifier: metadata?.filmProfileQualifier,
                    exposureSource: metadata?.exposureSource,
                    isOutsideManufacturerGuidance: metadata?.isOutsideManufacturerGuidance ?? false,
                    customProfileSummary: metadata?.customProfileSummary,
                    selectedModelLabel: metadata?.selectedModelLabel,
                    ndStops: metadata?.ndStops,
                    baseShutterSeconds: metadata?.baseShutterSeconds,
                    adjustedShutterSeconds: metadata?.adjustedShutterSeconds,
                    filterSummary: metadata?.filterSummary,
                    filterReferenceText: metadata?.filterReferenceText,
                    canceledRemainingTime: state.remainingAtCancel,
                    cancellationReason: state.cancellationReason
                )
            }
            .sorted(by: TimerWorkspaceOrdering.areInPresentationOrder(lhs:rhs:))

        scheduleTerminalTimeContextRefreshIfNeeded()
    }

    /// Earliest next display boundary across the terminal (completed +
    /// canceled) history rows, or `nil` when no visible relative label
    /// will change. Drives the one-shot refresh so visible history copy
    /// advances from `just now` to `1 min ago` while the sheet stays
    /// open — covering canceled rows as well as completed ones.
    func nextTerminalTimeContextRefreshDate(relativeTo referenceDate: Date) -> Date? {
        timers
            .compactMap(\.terminalAt)
            .compactMap {
                completedRelativeTimeFormatter.nextRefreshDate(
                    from: $0,
                    relativeTo: referenceDate
                )
            }
            .min()
    }

    private func scheduleTerminalTimeContextRefreshIfNeeded() {
        completedTimeContextRefreshTimer?.invalidate()
        completedTimeContextRefreshTimer = nil

        // While a timer is running the RunLoop tick path already
        // republishes with a fresh reference date every tick, so the
        // dedicated one-shot is only needed once all timers are terminal.
        guard !timers.contains(where: { $0.status == .running || $0.status == .paused }) else {
            return
        }

        let referenceDate = timerManager.currentDate
        guard let nextRefreshDate = nextTerminalTimeContextRefreshDate(
            relativeTo: referenceDate
        ) else {
            return
        }

        let refreshTimer = Timer(
            fire: nextRefreshDate,
            interval: 0,
            repeats: false
        ) { [weak self] _ in
            guard let self else {
                return
            }

            MainActor.assumeIsolated { self.syncTimers(with: self.timerManager.timers) }
        }

        completedTimeContextRefreshTimer = refreshTimer
        RunLoop.main.add(refreshTimer, forMode: .common)
    }

    deinit {
        completedTimeContextRefreshTimer?.invalidate()
    }
}

private struct TimerMetadataEntry {
    var sessionActivity: ShootingSessionActivity?
    let order: Int
    let name: String
    let basisSummary: String
    let cameraSlot: CameraSlotIdentity?
    let filmDisplayName: String?
    let filmProfileQualifier: String?
    let exposureSource: ExposureTimerSource?
    let isOutsideManufacturerGuidance: Bool
    let customProfileSummary: String?
    let selectedModelLabel: String?
    let ndStops: Double?
    let baseShutterSeconds: TimeInterval?
    let adjustedShutterSeconds: TimeInterval?
    let filterSummary: [FilterSummaryEntry]?
    let filterReferenceText: String?

    init(
        order: Int,
        name: String,
        basisSummary: String,
        cameraSlot: CameraSlotIdentity? = nil,
        filmDisplayName: String? = nil,
        filmProfileQualifier: String? = nil,
        exposureSource: ExposureTimerSource? = nil,
        isOutsideManufacturerGuidance: Bool = false,
        customProfileSummary: String? = nil,
        selectedModelLabel: String? = nil,
        ndStops: Double? = nil,
        baseShutterSeconds: TimeInterval? = nil,
        adjustedShutterSeconds: TimeInterval? = nil,
        filterSummary: [FilterSummaryEntry]? = nil,
        filterReferenceText: String? = nil,
        sessionActivity: ShootingSessionActivity? = nil
    ) {
        self.sessionActivity = sessionActivity
        self.order = order
        self.name = name
        self.basisSummary = basisSummary
        self.cameraSlot = cameraSlot
        self.filmDisplayName = filmDisplayName
        self.filmProfileQualifier = filmProfileQualifier
        self.exposureSource = exposureSource
        self.isOutsideManufacturerGuidance = isOutsideManufacturerGuidance
        self.customProfileSummary = customProfileSummary
        self.selectedModelLabel = selectedModelLabel
        self.ndStops = ndStops
        self.baseShutterSeconds = baseShutterSeconds
        self.adjustedShutterSeconds = adjustedShutterSeconds
        self.filterSummary = filterSummary
        self.filterReferenceText = filterReferenceText
    }
}
