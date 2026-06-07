import Foundation
import PTimerCore

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
    /// Captured-at-start flag: true when the timer was started from a
    /// formula prediction outside the supported range. Optional so
    /// older snapshots decode unchanged; the default decoded value is
    /// `false`.
    let isOutsideManufacturerGuidance: Bool?
    /// Bundled identity summary
    /// (`profile name · ISO N · source type · formula`) captured at
    /// start time for timers started from a custom `.userDefined`
    /// profile. Optional and additive so older snapshots decode
    /// unchanged; the workspace renders this line under the film
    /// name so the timer card stays readable after the source
    /// profile is later deleted.
    let customProfileSummary: String?

    init(
        id: UUID,
        order: Int,
        name: String,
        basisSummary: String,
        cameraSlotIDRaw: String? = nil,
        cameraSlotDisplayName: String? = nil,
        filmDisplayName: String? = nil,
        filmProfileQualifier: String? = nil,
        exposureSourceRaw: String? = nil,
        isOutsideManufacturerGuidance: Bool? = nil,
        customProfileSummary: String? = nil
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
        self.isOutsideManufacturerGuidance = isOutsideManufacturerGuidance
        self.customProfileSummary = customProfileSummary
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case order
        case name
        case basisSummary
        case cameraSlotIDRaw
        case cameraSlotDisplayName
        case filmDisplayName
        case filmProfileQualifier
        case exposureSourceRaw
        case isOutsideManufacturerGuidance
        case customProfileSummary
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.order = try container.decode(Int.self, forKey: .order)
        self.name = try container.decode(String.self, forKey: .name)
        self.basisSummary = try container.decode(String.self, forKey: .basisSummary)
        self.cameraSlotIDRaw = try container.decodeIfPresent(String.self, forKey: .cameraSlotIDRaw)
        self.cameraSlotDisplayName = try container.decodeIfPresent(String.self, forKey: .cameraSlotDisplayName)
        self.filmDisplayName = try container.decodeIfPresent(String.self, forKey: .filmDisplayName)
        self.filmProfileQualifier = try container.decodeIfPresent(String.self, forKey: .filmProfileQualifier)
        self.exposureSourceRaw = try container.decodeIfPresent(String.self, forKey: .exposureSourceRaw)
        self.isOutsideManufacturerGuidance = try container.decodeIfPresent(
            Bool.self,
            forKey: .isOutsideManufacturerGuidance
        )
        self.customProfileSummary = try container.decodeIfPresent(
            String.self,
            forKey: .customProfileSummary
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(order, forKey: .order)
        try container.encode(name, forKey: .name)
        try container.encode(basisSummary, forKey: .basisSummary)
        try container.encodeIfPresent(cameraSlotIDRaw, forKey: .cameraSlotIDRaw)
        try container.encodeIfPresent(cameraSlotDisplayName, forKey: .cameraSlotDisplayName)
        try container.encodeIfPresent(filmDisplayName, forKey: .filmDisplayName)
        try container.encodeIfPresent(filmProfileQualifier, forKey: .filmProfileQualifier)
        try container.encodeIfPresent(exposureSourceRaw, forKey: .exposureSourceRaw)
        try container.encodeIfPresent(
            isOutsideManufacturerGuidance,
            forKey: .isOutsideManufacturerGuidance
        )
        try container.encodeIfPresent(customProfileSummary, forKey: .customProfileSummary)
    }
}

struct PersistentTimerMetadataCollection: Codable, Equatable {
    let nextTimerOrder: Int
    let timers: [PersistentTimerMetadataSnapshot]
}

protocol TimerMetadataPersistenceStoring {
    func loadSnapshot() -> PersistentTimerMetadataCollection?
    func saveSnapshot(_ snapshot: PersistentTimerMetadataCollection)
    func clearSnapshot()
}

struct NoOpTimerMetadataPersistenceStore: TimerMetadataPersistenceStoring {
    func loadSnapshot() -> PersistentTimerMetadataCollection? { nil }
    func saveSnapshot(_ snapshot: PersistentTimerMetadataCollection) {}
    func clearSnapshot() {}
}

struct UserDefaultsTimerMetadataStore: TimerMetadataPersistenceStoring {
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

    func loadSnapshot() -> PersistentTimerMetadataCollection? {
        guard let data = userDefaults.data(forKey: snapshotKey) else {
            return nil
        }

        return try? decoder.decode(PersistentTimerMetadataCollection.self, from: data)
    }

    func saveSnapshot(_ snapshot: PersistentTimerMetadataCollection) {
        guard let data = try? encoder.encode(snapshot) else {
            return
        }

        userDefaults.set(data, forKey: snapshotKey)
    }

    func clearSnapshot() {
        userDefaults.removeObject(forKey: snapshotKey)
    }
}
