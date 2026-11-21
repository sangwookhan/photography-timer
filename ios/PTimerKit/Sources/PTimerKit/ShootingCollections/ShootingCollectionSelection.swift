// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import Foundation
import PTimerCore

/// Transient checkbox state and confirmed time suggestions. Never persisted.
public struct ShootingCollectionSelection {
    public private(set) var selectedIDs = Set<UUID>()
    private var selectionOrder: [UUID] = []
    private static let window: TimeInterval = 30 * 60

    public init() {}

    public mutating func toggle(_ id: UUID) {
        if selectedIDs.remove(id) != nil {
            selectionOrder.removeAll { $0 == id }
        } else {
            selectedIDs.insert(id)
            selectionOrder.append(id)
        }
    }

    public func suggestedIDs(
        from history: [RunningTimerItem], collectedIDs: Set<UUID>
    ) -> [UUID] {
        suggestion(from: history, collectedIDs: collectedIDs)?.candidates.map(\.id) ?? []
    }

    public func suggestion(
        from history: [RunningTimerItem], collectedIDs: Set<UUID>
    ) -> ShootingCollectionSuggestion? {
        let eligible = history.filter {
            ($0.status == .completed || $0.status == .canceled) && !collectedIDs.contains($0.id)
        }
        guard let anchor = selectionOrder.lazy.compactMap({ id in
            eligible.first { $0.id == id }
        }).first else { return nil }
        let nearby = eligible.filter {
            !selectedIDs.contains($0.id) && abs($0.startDate.timeIntervalSince(anchor.startDate)) <= Self.window
        }.sorted {
            $0.startDate == $1.startDate ? $0.id.uuidString < $1.id.uuidString : $0.startDate < $1.startDate
        }
        var seen = Set<UUID>()
        let candidates = nearby.filter { seen.insert($0.id).inserted }
        guard !candidates.isEmpty else { return nil }
        return ShootingCollectionSuggestion(anchor: anchor, candidates: candidates)
    }

    public mutating func confirmSuggestion(
        _ preview: ShootingCollectionSuggestion, choosing candidateIDs: Set<UUID>,
        from history: [RunningTimerItem], collectedIDs: Set<UUID>
    ) {
        guard let current = suggestion(from: history, collectedIDs: collectedIDs),
              current.anchor.id == preview.anchor.id else { return }
        let inspectedIDs = Set(preview.candidates.map(\.id))
        // Only inspected, chosen, still-eligible candidates can be added.
        let additionalIDs = current.candidates.map(\.id).filter {
            inspectedIDs.contains($0) && candidateIDs.contains($0)
        }
        selectedIDs.formUnion(additionalIDs)
        selectionOrder.append(contentsOf: additionalIDs)
    }
}
