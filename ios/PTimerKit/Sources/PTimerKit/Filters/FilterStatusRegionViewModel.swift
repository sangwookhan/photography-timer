// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import Combine
import Foundation

/// Observable presentation state of the single status region
/// (FILTER-STACK-008): owns the visible content and its timing so exactly one
/// content is ever displayed and a stale timer can never replace
/// newer content. Held content stays until replaced or cleared; the
/// Standard-only idle total fades after `fadeDelay`; and when a
/// movement or Plus browse settles into the persistent idle summary,
/// the settled expanded information lingers for the same interval
/// before the summary returns (FILTER-STACK-008). A rejection has its
/// own notice interval, so the summary returns as soon as it clears.
@MainActor
public final class FilterStatusRegionViewModel: ObservableObject {
    @Published public private(set) var visibleContent: FilterStatusRegionContent?
    /// Fixed product interval for the idle total and the post-settle
    /// linger; a test seam only.
    var fadeDelay: TimeInterval = 1.5
    private var timerTask: Task<Void, Never>?
    private var pendingContent: FilterStatusRegionContent?
    private var generation = 0

    public init() {}

    /// Applies the latest composed content. Any pending timer belongs
    /// to a previous state and is cancelled first.
    public func apply(_ content: FilterStatusRegionContent?) {
        timerTask?.cancel()
        timerTask = nil
        pendingContent = nil
        generation += 1
        guard let content else {
            visibleContent = nil
            return
        }
        if content.isPersistentIdle, let current = visibleContent, current.isHeld, !current.isWarning, !current.isPersistentIdle {
            // Settlement after movement or browsing: keep the expanded
            // information for the transient interval, then return to
            // the source summary.
            pendingContent = content
            schedule { $0.visibleContent = content }
            return
        }
        visibleContent = content
        guard !content.isHeld else {
            return
        }
        schedule { $0.visibleContent = nil }
    }

    private func schedule(_ body: @escaping @MainActor (FilterStatusRegionViewModel) -> Void) {
        let token = generation
        timerTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64((self?.fadeDelay ?? 0) * 1_000_000_000))
            guard let self, !Task.isCancelled, self.generation == token else {
                return
            }
            self.pendingContent = nil
            body(self)
        }
    }

    /// Test seam: fires the pending timer as if the interval elapsed,
    /// with the same token check the timer applies.
    func fireFadeIfPending(token: Int? = nil) {
        guard timerTask != nil else { return }
        if let token, token != generation { return }
        timerTask?.cancel()
        timerTask = nil
        visibleContent = pendingContent
        pendingContent = nil
    }

    var currentGeneration: Int { generation }
}
