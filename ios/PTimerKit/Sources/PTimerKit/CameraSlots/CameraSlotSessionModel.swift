// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import Combine
import Foundation
import PTimerCore

/// One managed camera in the global camera list.
public struct CameraListEntry: Equatable, Identifiable {
    public let id: CameraSlotID
    /// Stored, trimmed, non-empty name.
    public var name: String
    /// Whether the camera is included in the shooting pager.
    public var isDisplayed: Bool

    public init(id: CameraSlotID, name: String, isDisplayed: Bool = true) {
        self.id = id
        self.name = name
        self.isDisplayed = isDisplayed
    }
}

/// `CameraSlotSessionModel` owns the managed camera list: the global
/// order, each camera's name and pager inclusion, the active camera
/// (or the explicit absence of one), the identities ever issued, and
/// the calculator snapshot of every camera that is not currently
/// active. The active camera's live state remains on `CalculatorModel`
/// + `FilmSelectionModel`; inactive snapshots stay here untouched so
/// switching restores a camera's inputs without any reset behavior.
///
/// The model holds session state only. Snapshot capture / load is
/// orchestrated by the `ExposureCalculatorViewModel` facade so the
/// other feature models keep owning their own state types.
@MainActor
public final class CameraSlotSessionModel: ObservableObject {
    /// The managed list in global user-defined order.
    @Published public private(set) var cameras: [CameraListEntry]

    /// The active camera, or `nil` when no camera is displayed.
    @Published public private(set) var activeSlotID: CameraSlotID?

    /// Every identity ever issued, including deleted cameras, so a new
    /// identity can never reuse one that old timer records may carry.
    public private(set) var issuedIDs: Set<CameraSlotID>

    /// Snapshots for cameras that are not currently active. The active
    /// camera's snapshot is intentionally absent.
    private var inactiveSnapshots: [CameraSlotID: CameraSlotCalculatorSnapshot]

    private let generateID: () -> CameraSlotID

    /// Seeds the fresh-install list: `camera1` ... `camera4`, in that
    /// order, shown in the pager, with localized `Camera N` names
    /// frozen as stored text.
    public nonisolated static func seededCameras() -> [CameraListEntry] {
        CameraSlotID.legacyOrdered.enumerated().map { index, id in
            CameraListEntry(id: id, name: CameraNaming.defaultName(number: index + 1))
        }
    }

    public init(
        cameras: [CameraListEntry] = CameraSlotSessionModel.seededCameras(),
        activeSlotID: CameraSlotID? = .camera1,
        issuedIDs: Set<CameraSlotID> = [],
        snapshots: [CameraSlotID: CameraSlotCalculatorSnapshot] = [:],
        generateID: @escaping () -> CameraSlotID = { CameraSlotID.generate() }
    ) {
        let unique = Self.uniqueEntries(cameras)
        self.cameras = unique
        self.generateID = generateID
        self.issuedIDs = issuedIDs.union(unique.map(\.id))
        let displayed = unique.filter(\.isDisplayed).map(\.id)
        let resolvedActive: CameraSlotID?
        if let activeSlotID, displayed.contains(activeSlotID) {
            resolvedActive = activeSlotID
        } else {
            resolvedActive = displayed.first
        }
        self.activeSlotID = resolvedActive
        let ids = Set(unique.map(\.id))
        self.inactiveSnapshots = snapshots.filter {
            ids.contains($0.key) && $0.key != resolvedActive
        }
    }

    // MARK: - Reads

    /// Cameras included in the shooting pager, in global order.
    public var displayedCameras: [CameraListEntry] {
        cameras.filter(\.isDisplayed)
    }

    public var displayedSlotIDs: [CameraSlotID] {
        displayedCameras.map(\.id)
    }

    public func entry(for slotID: CameraSlotID) -> CameraListEntry? {
        cameras.first { $0.id == slotID }
    }

    /// Identity for the active camera, or `nil` when none is active.
    public var activeSlot: CameraSlotIdentity? {
        activeSlotID.flatMap { identity(for: $0) }
    }

    /// Identity for a camera in the list, or `nil` for an unknown id.
    public func identity(for slotID: CameraSlotID) -> CameraSlotIdentity? {
        entry(for: slotID).map { CameraSlotIdentity(id: $0.id, displayName: $0.name) }
    }

    // MARK: - List edits

    /// Adds a camera named `name` at the end of the list, shown in the
    /// pager and active. The name comes from the automatic-name sequence,
    /// which the caller has already advanced durably; the model never
    /// derives it from the current cameras. The caller has also stashed
    /// the outgoing camera's snapshot.
    @discardableResult
    public func addCamera(named name: String) -> CameraSlotID {
        var id = generateID()
        while issuedIDs.contains(id) {
            id = generateID()
        }
        issuedIDs.insert(id)
        cameras.append(CameraListEntry(id: id, name: name))
        inactiveSnapshots.removeValue(forKey: id)
        activeSlotID = id
        return id
    }

    /// Renames a camera. The name is trimmed; a blank name is rejected
    /// and leaves the stored name unchanged. Returns whether it applied.
    @discardableResult
    public func renameCamera(_ slotID: CameraSlotID, to name: String) -> Bool {
        guard let trimmed = CameraNaming.trimmedName(name),
              let index = cameras.firstIndex(where: { $0.id == slotID }) else {
            return false
        }
        cameras[index].name = trimmed
        return true
    }

    /// Shows or hides one camera. Hiding preserves name, calculator
    /// state, and list position.
    public func setDisplayed(_ isDisplayed: Bool, for slotID: CameraSlotID) {
        if isDisplayed {
            guard let index = cameras.firstIndex(where: { $0.id == slotID }),
                  !cameras[index].isDisplayed else { return }
            cameras[index].isDisplayed = true
            if activeSlotID == nil {
                activeSlotID = slotID
            }
        } else {
            hideCameras([slotID])
        }
    }

    /// Hides several cameras in one change; ids no longer present are
    /// ignored. The active camera follows CAMERA-PAGER-003.
    public func hideCameras(_ slotIDs: Set<CameraSlotID>) {
        let before = cameras
        for index in cameras.indices where slotIDs.contains(cameras[index].id) {
            cameras[index].isDisplayed = false
        }
        resolveActiveAfterRemoval(previous: before)
    }

    /// Deletes several cameras and their calculator state in one
    /// change; ids no longer present are ignored. Identities stay in
    /// the issued set so they are never reused.
    public func deleteCameras(_ slotIDs: Set<CameraSlotID>) {
        let before = cameras
        cameras.removeAll { slotIDs.contains($0.id) }
        for slotID in slotIDs {
            inactiveSnapshots.removeValue(forKey: slotID)
        }
        resolveActiveAfterRemoval(previous: before)
    }

    /// Moves cameras in the global order (`List.onMove` semantics).
    public func moveCameras(fromOffsets source: IndexSet, toOffset destination: Int) {
        var reordered = cameras
        let moving = source.sorted().map { reordered[$0] }
        for index in source.sorted(by: >) {
            reordered.remove(at: index)
        }
        let removedBefore = source.filter { $0 < destination }.count
        let insertion = max(0, min(reordered.count, destination - removedBefore))
        reordered.insert(contentsOf: moving, at: insertion)
        cameras = reordered
    }

    /// Moves one camera by `delta` positions (non-drag reorder).
    public func moveCamera(_ slotID: CameraSlotID, by delta: Int) {
        guard let index = cameras.firstIndex(where: { $0.id == slotID }) else { return }
        let target = max(0, min(cameras.count - 1, index + delta))
        guard target != index else { return }
        let entry = cameras.remove(at: index)
        cameras.insert(entry, at: target)
    }

    /// CAMERA-PAGER-003: when the active camera was hidden or removed,
    /// the next displayed camera in the resulting global order becomes
    /// active; with none after it, the first displayed camera; with no
    /// displayed camera, none.
    private func resolveActiveAfterRemoval(previous: [CameraListEntry]) {
        guard let active = activeSlotID else { return }
        if let current = entry(for: active), current.isDisplayed {
            return
        }
        let activeIndex = previous.firstIndex { $0.id == active } ?? -1
        let survivorsAfter = previous
            .dropFirst(activeIndex + 1)
            .compactMap { old in entry(for: old.id) }
            .filter(\.isDisplayed)
        activeSlotID = survivorsAfter.first?.id ?? displayedCameras.first?.id
    }

    // MARK: - Snapshots

    /// Snapshot stored for a camera that is not active. Returns nil
    /// for the active camera and for unknown ids.
    public func snapshot(forInactiveSlot slotID: CameraSlotID) -> CameraSlotCalculatorSnapshot? {
        guard slotID != activeSlotID, entry(for: slotID) != nil else {
            return nil
        }
        return inactiveSnapshots[slotID] ?? .initial
    }

    /// Stores the live snapshot of a camera that is about to leave the
    /// active position (or is being persisted).
    public func storeSnapshot(_ snapshot: CameraSlotCalculatorSnapshot, for slotID: CameraSlotID) {
        guard entry(for: slotID) != nil else { return }
        inactiveSnapshots[slotID] = snapshot
    }

    /// Removes and returns a camera's stored snapshot (fresh defaults
    /// when none) because that camera is becoming the live one.
    public func takeSnapshot(for slotID: CameraSlotID) -> CameraSlotCalculatorSnapshot {
        inactiveSnapshots.removeValue(forKey: slotID) ?? .initial
    }

    /// Atomic switch between displayed cameras: stores `outgoingSnapshot`
    /// for the active camera and returns the incoming camera's snapshot.
    /// A no-op switch, or a switch to a camera that is unknown or not
    /// displayed, returns nil.
    @discardableResult
    public func switchActiveSlot(
        to targetSlotID: CameraSlotID,
        capturing outgoingSnapshot: CameraSlotCalculatorSnapshot
    ) -> CameraSlotCalculatorSnapshot? {
        guard let target = entry(for: targetSlotID), target.isDisplayed,
              targetSlotID != activeSlotID else {
            return nil
        }
        if let outgoing = activeSlotID {
            inactiveSnapshots[outgoing] = outgoingSnapshot
        }
        let incoming = inactiveSnapshots.removeValue(forKey: targetSlotID) ?? .initial
        activeSlotID = targetSlotID
        return incoming
    }

    /// Read access to the inactive-snapshot dictionary for persistence.
    public func currentInactiveSnapshots() -> [CameraSlotID: CameraSlotCalculatorSnapshot] {
        inactiveSnapshots
    }

    /// Applies `transform` to every inactive snapshot (Filter Set
    /// contract: an inventory edit or deletion must follow into every
    /// camera stack that references the affected item or set).
    /// `transform` returns the replacement snapshot, or `nil` to leave
    /// that camera untouched. Publishes once when any snapshot changed.
    public func updateInactiveSnapshots(
        _ transform: (CameraSlotID, CameraSlotCalculatorSnapshot) -> CameraSlotCalculatorSnapshot?
    ) {
        var didChange = false
        for (slotID, snapshot) in inactiveSnapshots {
            guard let updated = transform(slotID, snapshot), updated != snapshot else {
                continue
            }
            inactiveSnapshots[slotID] = updated
            didChange = true
        }
        if didChange {
            objectWillChange.send()
        }
    }

    /// Scrubs `filmID` from every inactive camera snapshot so a
    /// custom-film deletion does not leave other cameras dangling on a
    /// no-longer-existing reference. Returns the touched ids.
    @discardableResult
    public func clearFilmReference(filmID: String) -> Set<CameraSlotID> {
        var touched: Set<CameraSlotID> = []
        for (slotID, snapshot) in inactiveSnapshots {
            guard snapshot.selectedPresetFilm?.id == filmID else {
                continue
            }
            var updated = snapshot
            updated.selectedPresetFilm = nil
            updated.selectedProfileOverride = nil
            inactiveSnapshots[slotID] = updated
            touched.insert(slotID)
        }
        if !touched.isEmpty {
            objectWillChange.send()
        }
        return touched
    }

    // MARK: - Restore

    /// Replaces the whole session at app-start restore time.
    public func restore(
        cameras restoredCameras: [CameraListEntry],
        activeSlotID restoredActive: CameraSlotID?,
        issuedIDs restoredIssued: Set<CameraSlotID>,
        snapshots: [CameraSlotID: CameraSlotCalculatorSnapshot]
    ) {
        let unique = Self.uniqueEntries(restoredCameras)
        cameras = unique
        issuedIDs = restoredIssued.union(unique.map(\.id))
        let displayed = unique.filter(\.isDisplayed).map(\.id)
        if let restoredActive, displayed.contains(restoredActive) {
            activeSlotID = restoredActive
        } else {
            // Absent or stale: the first displayed camera, or none when
            // nothing is displayed (the explicit no-active state).
            activeSlotID = displayed.first
        }
        let ids = Set(unique.map(\.id))
        inactiveSnapshots = snapshots.filter {
            ids.contains($0.key) && $0.key != activeSlotID
        }
    }

    private static func uniqueEntries(_ entries: [CameraListEntry]) -> [CameraListEntry] {
        var seen = Set<CameraSlotID>()
        return entries.filter { seen.insert($0.id).inserted }
    }
}
