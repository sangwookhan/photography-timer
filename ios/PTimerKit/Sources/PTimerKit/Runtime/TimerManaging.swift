// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import Combine
import Foundation
import PTimerCore

/// Minimal app-facing boundary onto the timer coordinator. PTimerKit models
/// (e.g. `TimerWorkspaceModel`) depend on this protocol instead of the app's
/// concrete `TimerManager`, so they stay free of the RunLoop / UIKit OS layer.
/// The app's `TimerManager` conforms to it.
@MainActor
public protocol TimerManaging: AnyObject {
    var timers: [TimerState] { get }
    var timersPublisher: AnyPublisher<[TimerState], Never> { get }
    var currentDate: Date { get }

    @discardableResult
    func start(id: UUID, duration: TimeInterval) -> UUID?
    func pause(id: UUID)
    func resume(id: UUID)
    func cancel(id: UUID)
    func remove(id: UUID)
    func removeCompletedTimers()
    func reconcile(now: Date?)
}
