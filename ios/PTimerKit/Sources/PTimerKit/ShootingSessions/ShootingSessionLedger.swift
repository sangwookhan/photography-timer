// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import Foundation

@MainActor
public final class ShootingSessionLedger {
    public private(set) var confirmed: [UUID: ShootingSessionMembership] = [:]
    public private(set) var hasPendingAssignments = false
    private let store: ShootingSessionStoring
    private var snapshot = PersistentShootingSessions()
    private var loaded = false

    public init(store: ShootingSessionStoring) {
        self.store = store
        reloadIfNeeded()
    }

    private func reloadIfNeeded() {
        guard !loaded else { return }
        guard case .loaded(let stored) = store.loadSessions() else { return }
        snapshot = stored
        confirmed = Dictionary(stored.memberships.map { ($0.timerID, $0) }, uniquingKeysWith: { first, _ in first })
        loaded = true
    }

    /// All retained starts participate, including ones whose assignment save failed.
    /// The original policy is captured with each activity so a retry cannot apply a
    /// later debug mode retroactively.
    public func reconcile(activities: [(id: UUID, order: Int, activity: ShootingSessionActivity)]) {
        reloadIfNeeded()
        guard loaded else {
            hasPendingAssignments = !activities.isEmpty
            return
        }
        let ordered = activities.sorted {
            if $0.order != $1.order { return $0.order < $1.order }
            if $0.activity.startedAt != $1.activity.startedAt {
                return $0.activity.startedAt < $1.activity.startedAt
            }
            return $0.id.uuidString < $1.id.uuidString
        }
        var assigned = Set(snapshot.memberships.map(\.timerID))
        for item in ordered where !assigned.contains(item.id) {
            let start = item.activity.startedAt
            let latest = snapshot.latest
            let connects = latest.map {
                item.activity.policy.connects(start: start, firstStart: $0.firstStart, latestStart: $0.startedAt)
            } ?? false
            // The first Timer's stable identity also seeds its session identity.
            // A retry after an interrupted write therefore cannot create a new ID.
            let membership = ShootingSessionMembership(
                timerID: item.id,
                sessionID: connects ? (latest?.sessionID ?? item.id) : item.id,
                firstStart: connects ? (latest?.firstStart ?? start) : start,
                startedAt: start
            )
            snapshot.memberships.append(membership)
            snapshot.latest = membership
            assigned.insert(item.id)
        }
        guard snapshot.memberships.contains(where: { confirmed[$0.timerID] == nil }) else {
            hasPendingAssignments = false
            return
        }
        guard store.saveSessions(snapshot) else {
            hasPendingAssignments = true
            return
        }
        confirmed = Dictionary(snapshot.memberships.map { ($0.timerID, $0) }, uniquingKeysWith: { first, _ in first })
        hasPendingAssignments = false
    }

    public func title(for sessionID: UUID) -> String {
        var seen = Set<UUID>()
        for member in snapshot.memberships where seen.insert(member.sessionID).inserted {
            if member.sessionID == sessionID {
                return String(localized: "Session \(seen.count)")
            }
        }
        return String(localized: "Session")
    }

    public func sections(for sessionID: UUID, from snapshot: BottomSheetWorkspaceSnapshot) -> [TimerWorkspaceSection] {
        snapshot.sections.compactMap { section in
            let items = section.items.filter { confirmed[$0.id]?.sessionID == sessionID }
            return items.isEmpty ? nil : TimerWorkspaceSection(title: section.title, items: items)
        }
    }

    public func membership(for timerID: UUID) -> ShootingSessionMembership? { confirmed[timerID] }
}
