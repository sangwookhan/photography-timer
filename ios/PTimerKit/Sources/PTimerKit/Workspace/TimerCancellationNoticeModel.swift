// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import Combine
import Foundation

@MainActor
public final class TimerCancellationNoticeModel: ObservableObject {
    @Published public private(set) var pendingTimerIDs: Set<UUID> = []
    @Published public private(set) var hasPausedTimers = false
    @Published public private(set) var text: String?

    private let timerManager: any TimerManaging
    private var cancellable: AnyCancellable?
    private var dismissalTask: Task<Void, Never>?

    public init(timerManager: any TimerManaging) {
        self.timerManager = timerManager
        cancellable = timerManager.timersPublisher.sink { [weak self] timers in
            guard let self else { return }
            let pending = Set(timers.filter(\.cancellationNoticePending).map(\.id))
            if self.pendingTimerIDs != pending { self.pendingTimerIDs = pending }
            let hasPaused = timers.contains { $0.status == .paused }
            if self.hasPausedTimers != hasPaused { self.hasPausedTimers = hasPaused }
        }
    }

    /// Called by an active, visible app surface, never by restore itself.
    public func presentPendingNotice() {
        let ids = pendingTimerIDs
        guard !ids.isEmpty else { return }
        text = ids.count == 1
            ? String(localized: "Paused timer canceled")
            : String(localized: "Paused timers canceled")
        timerManager.acknowledgeCancellationNotices(ids: ids)
        dismissalTask?.cancel()
        dismissalTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            self?.text = nil
        }
    }

    public func dismiss() {
        dismissalTask?.cancel()
        text = nil
    }

    deinit { dismissalTask?.cancel() }
}
