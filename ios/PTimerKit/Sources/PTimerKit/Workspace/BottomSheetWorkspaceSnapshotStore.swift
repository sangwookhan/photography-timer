// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import Combine
import Foundation
import PTimerCore

@MainActor
public final class BottomSheetWorkspaceSnapshotStore: ObservableObject {
    @Published public private(set) var snapshot: BottomSheetWorkspaceSnapshot

    private var cancellables: Set<AnyCancellable> = []

    public init(
        initialTimers: [RunningTimerItem] = [],
        initialNDNotationMode: NDNotationMode = .stops,
        timersPublisher: AnyPublisher<[RunningTimerItem], Never>,
        ndNotationModePublisher: AnyPublisher<NDNotationMode, Never>,
        adapter: BottomSheetWorkspacePresentationAdapter
    ) {
        self.snapshot = adapter.makeSnapshot(
            from: initialTimers,
            ndNotationMode: initialNDNotationMode
        )

        // Rebuild on a change to EITHER the timers or the ND notation
        // mode so an active/completed timer's basis re-renders in the
        // new notation immediately (PTIMER-187).
        Publishers.CombineLatest(timersPublisher, ndNotationModePublisher)
            .map { timers, mode in adapter.makeSnapshot(from: timers, ndNotationMode: mode) }
            .removeDuplicates()
            .sink { [weak self] snapshot in
                self?.snapshot = snapshot
            }
            .store(in: &cancellables)
    }
}
