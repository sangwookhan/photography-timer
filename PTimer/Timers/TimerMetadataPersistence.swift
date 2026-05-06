import Foundation

/// Persisted-with-the-workspace metadata that the runtime `TimerState`
/// does not carry: human-readable `name`, `basisSummary` text, and the
/// LIFO insertion `order`. The pair (timer state + this metadata) is
/// what the workspace renders and restores across relaunches.
///
/// The schema is decoupled from `TimerState` persistence on purpose —
/// `PersistentTimerSnapshot` (in `TimerManager.swift`) owns the
/// state-machine fields; this snapshot owns the presentation tags.
/// Both keep their `UserDefaults` keys stable.
struct PersistentTimerMetadataSnapshot: Codable, Equatable {
    let id: UUID
    let order: Int
    let name: String
    let basisSummary: String
    /// Stable camera-slot identifier captured at timer start, if the
    /// timer was started from an active camera slot. Optional so
    /// older snapshots decode unchanged and timers started outside
    /// the camera-slot workflow stay decoupled from slot identity.
    let cameraSlotIDRaw: String?
    /// User-facing camera-slot label captured at timer start. Stored
    /// alongside the raw id so the workspace can render the slot
    /// label without resolving the id back to a current display
    /// name.
    let cameraSlotDisplayName: String?
    /// Canonical film stock name captured at start time. Optional
    /// because (a) older snapshots predate this field and (b) the
    /// digital (no-film) workflow legitimately has no film name. The
    /// snapshot is the source of truth at decode time — a later
    /// rename of the underlying preset must not rewrite past timers.
    let filmDisplayName: String?
    /// Profile qualifier captured at start time (e.g. `"Unofficial"`).
    /// Stored separately from `filmDisplayName` so the dock can render
    /// the qualifier as secondary text without parsing strings.
    let filmProfileQualifier: String?
    /// Raw exposure-source tag captured at start time. Persists the
    /// `rawValue` of `ExposureTimerSource` rather than the enum so a
    /// future case addition does not invalidate older snapshots.
    let exposureSourceRaw: String?

    init(
        id: UUID,
        order: Int,
        name: String,
        basisSummary: String,
        cameraSlotIDRaw: String? = nil,
        cameraSlotDisplayName: String? = nil,
        filmDisplayName: String? = nil,
        filmProfileQualifier: String? = nil,
        exposureSourceRaw: String? = nil
    ) {
        self.id = id
        self.order = order
        self.name = name
        self.basisSummary = basisSummary
        self.cameraSlotIDRaw = cameraSlotIDRaw
        self.cameraSlotDisplayName = cameraSlotDisplayName
        self.filmDisplayName = filmDisplayName
        self.filmProfileQualifier = filmProfileQualifier
        self.exposureSourceRaw = exposureSourceRaw
    }
}

struct PersistentTimerMetadataCollectionSnapshot: Codable, Equatable {
    let nextTimerOrder: Int
    let timers: [PersistentTimerMetadataSnapshot]
}

protocol TimerMetadataPersistenceStoring {
    func loadSnapshot() -> PersistentTimerMetadataCollectionSnapshot?
    func saveSnapshot(_ snapshot: PersistentTimerMetadataCollectionSnapshot)
    func clearSnapshot()
}

struct NoOpTimerMetadataPersistenceStore: TimerMetadataPersistenceStoring {
    func loadSnapshot() -> PersistentTimerMetadataCollectionSnapshot? { nil }
    func saveSnapshot(_ snapshot: PersistentTimerMetadataCollectionSnapshot) {}
    func clearSnapshot() {}
}

struct UserDefaultsTimerMetadataPersistenceStore: TimerMetadataPersistenceStoring {
    private let userDefaults: UserDefaults
    private let snapshotKey: String
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(
        userDefaults: UserDefaults = .standard,
        snapshotKey: String = "ptimer.timer-metadata.snapshot"
    ) {
        self.userDefaults = userDefaults
        self.snapshotKey = snapshotKey
    }

    func loadSnapshot() -> PersistentTimerMetadataCollectionSnapshot? {
        guard let data = userDefaults.data(forKey: snapshotKey) else {
            return nil
        }

        return try? decoder.decode(PersistentTimerMetadataCollectionSnapshot.self, from: data)
    }

    func saveSnapshot(_ snapshot: PersistentTimerMetadataCollectionSnapshot) {
        guard let data = try? encoder.encode(snapshot) else {
            return
        }

        userDefaults.set(data, forKey: snapshotKey)
    }

    func clearSnapshot() {
        userDefaults.removeObject(forKey: snapshotKey)
    }
}
