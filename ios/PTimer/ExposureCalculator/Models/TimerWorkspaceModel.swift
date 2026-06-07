import Combine
import PTimerCore
import Foundation

/// `TimerWorkspaceModel` owns the timer-workspace slice. The model owns:
/// - the `TimerManager` instance (the live timer state machine)
/// - timer metadata persistence (the `*Storing` store + the
///   `timerMetadata` dict + `nextTimerOrder`)
/// - the published `timers: [RunningTimerItem]` collection that views
///   bind to
/// - the timer lifecycle operations the ViewModel previously hosted
///   (`pause` / `resume` / `remove` / `clearCompletedTimers` /
///   `start(id:duration:name:basisSummary:)`)
/// - the `completedRelativeTimeFormatter` used to drive the
///   "Completed N minutes ago" refresh schedule.
///
/// This model carries timer state only. Cross-cutting "start timer
/// from calculation result" wiring belongs to `WorkspaceCoordinator`
/// and the view-model facade.
@MainActor
final class TimerWorkspaceModel: ObservableObject {
    @Published private(set) var timers: [RunningTimerItem] = []

    /// Exposed to the ViewModel so it can construct the "Tri-X 400 - 2s"
    /// timer name from the active calc/film state before delegating to
    /// `start(id:duration:metadata:)`. Kept private(set) — only the
    /// model mutates it via persistence + lifecycle paths.
    private(set) var nextTimerOrder = 1

    let timerManager: TimerManager

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

    init(
        timerManager: TimerManager,
        metadataPersistenceStore: TimerMetadataPersistenceStoring,
        defaultName: @escaping (TimeInterval) -> String
    ) {
        self.timerManager = timerManager
        self.metadataPersistenceStore = metadataPersistenceStore
        self.defaultName = defaultName

        restorePersistedTimerMetadata()
        timerManager.$timers
            .sink { [weak self] states in
                self?.syncTimers(with: states)
            }
            .store(in: &cancellables)
    }

    // MARK: - Lifecycle

    /// Starts a timer with the given metadata. Returns the timer's id
    /// on success; nil if `TimerManager` rejected the duration.
    /// The model writes metadata before calling `TimerManager`, rolls
    /// metadata back on failure, and bumps `nextTimerOrder` on success.
    @discardableResult
    func startTimer(
        id: UUID = UUID(),
        duration: TimeInterval,
        name: String,
        basisSummary: String,
        cameraSlot: CameraSlotIdentity? = nil,
        filmDisplayName: String? = nil,
        filmProfileQualifier: String? = nil,
        exposureSource: ExposureTimerSource? = nil,
        isOutsideManufacturerGuidance: Bool = false,
        customProfileSummary: String? = nil
    ) -> UUID? {
        let order = nextTimerOrder
        timerMetadata[id] = TimerMetadataEntry(
            order: order,
            name: name,
            basisSummary: basisSummary,
            cameraSlot: cameraSlot,
            filmDisplayName: filmDisplayName,
            filmProfileQualifier: filmProfileQualifier,
            exposureSource: exposureSource,
            isOutsideManufacturerGuidance: isOutsideManufacturerGuidance,
            customProfileSummary: customProfileSummary
        )

        guard timerManager.start(id: id, duration: duration) != nil else {
            timerMetadata.removeValue(forKey: id)
            return nil
        }

        nextTimerOrder += 1
        persistTimerMetadata()
        return id
    }

    /// Starts a new timer cloned from a completed source timer. The
    /// new timer gets a fresh id, order, and runtime lifecycle from
    /// `TimerManager`; identity-bearing fields (camera slot, film
    /// name, profile qualifier, exposure source) come from the
    /// source's already-captured metadata. The source timer is read
    /// only — its runtime state, ordering, and persisted metadata are
    /// untouched.
    ///
    /// Returns the new timer's id on success; `nil` when `source` is
    /// not in the `completed` state or `TimerManager` rejected the
    /// duration. The completed-status guard lets the UI route every
    /// row through this path while staying inert for running or
    /// paused rows.
    @discardableResult
    func startTimer(
        cloningCompleted source: RunningTimerItem,
        id: UUID = UUID()
    ) -> UUID? {
        guard source.status == .completed else {
            return nil
        }

        return startTimer(
            id: id,
            duration: source.duration,
            name: source.name,
            basisSummary: source.basisSummary,
            cameraSlot: source.cameraSlot,
            filmDisplayName: source.filmDisplayName,
            filmProfileQualifier: source.filmProfileQualifier,
            exposureSource: source.exposureSource,
            isOutsideManufacturerGuidance: source.isOutsideManufacturerGuidance,
            customProfileSummary: source.customProfileSummary
        )
    }

    func pauseTimer(id: UUID) {
        timerManager.pause(id: id)
    }

    func resumeTimer(id: UUID) {
        timerManager.resume(id: id)
    }

    func removeTimer(id: UUID) {
        timerManager.remove(id: id)
        timerMetadata.removeValue(forKey: id)
        persistTimerMetadata()
    }

    func clearCompletedTimers() {
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

    func reconcileTimersAfterAppBecomesActive() {
        timerManager.reconcileAfterAppBecomesActive()
    }

    // MARK: - Display helpers

    var runningTimerCount: Int {
        timers.filter { $0.status == .running }.count
    }

    func compactCompletedRelativeTimeText(
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

    func relativeCompletedText(
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
                        customProfileSummary: entry.customProfileSummary
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

        let snapshot = PersistentTimerMetadataCollection(
            nextTimerOrder: nextTimerOrder,
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
                        customProfileSummary: metadata.customProfileSummary
                    )
                }
                .sorted { lhs, rhs in
                    if lhs.order != rhs.order {
                        return lhs.order < rhs.order
                    }

                    return lhs.id.uuidString < rhs.id.uuidString
                }
        )

        metadataPersistenceStore.saveSnapshot(snapshot)
    }

    private func syncTimers(with states: [TimerState]) {
        let validIDs = Set(states.map(\.id))
        let originalCount = timerMetadata.count
        timerMetadata = timerMetadata.filter { validIDs.contains($0.key) }
        if timerMetadata.count != originalCount {
            persistTimerMetadata()
        }
        let referenceDate = timerManager.currentDate

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
                    customProfileSummary: metadata?.customProfileSummary
                )
            }
            .sorted(by: TimerWorkspaceOrdering.areInPresentationOrder(lhs:rhs:))

        scheduleCompletedTimeContextRefreshIfNeeded()
    }

    private func scheduleCompletedTimeContextRefreshIfNeeded() {
        completedTimeContextRefreshTimer?.invalidate()
        completedTimeContextRefreshTimer = nil

        guard !timers.contains(where: { $0.status == .running }) else {
            return
        }

        let referenceDate = timerManager.currentDate
        let nextRefreshDate = timers
            .filter { $0.status == .completed }
            .compactMap(\.completedAt)
            .compactMap {
                completedRelativeTimeFormatter.nextRefreshDate(
                    from: $0,
                    relativeTo: referenceDate
                )
            }
            .min()

        guard let nextRefreshDate else {
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

            self.syncTimers(with: self.timerManager.timers)
        }

        completedTimeContextRefreshTimer = refreshTimer
        RunLoop.main.add(refreshTimer, forMode: .common)
    }

    deinit {
        completedTimeContextRefreshTimer?.invalidate()
    }
}

private struct TimerMetadataEntry {
    let order: Int
    let name: String
    let basisSummary: String
    let cameraSlot: CameraSlotIdentity?
    let filmDisplayName: String?
    let filmProfileQualifier: String?
    let exposureSource: ExposureTimerSource?
    let isOutsideManufacturerGuidance: Bool
    let customProfileSummary: String?

    init(
        order: Int,
        name: String,
        basisSummary: String,
        cameraSlot: CameraSlotIdentity? = nil,
        filmDisplayName: String? = nil,
        filmProfileQualifier: String? = nil,
        exposureSource: ExposureTimerSource? = nil,
        isOutsideManufacturerGuidance: Bool = false,
        customProfileSummary: String? = nil
    ) {
        self.order = order
        self.name = name
        self.basisSummary = basisSummary
        self.cameraSlot = cameraSlot
        self.filmDisplayName = filmDisplayName
        self.filmProfileQualifier = filmProfileQualifier
        self.exposureSource = exposureSource
        self.isOutsideManufacturerGuidance = isOutsideManufacturerGuidance
        self.customProfileSummary = customProfileSummary
    }
}
