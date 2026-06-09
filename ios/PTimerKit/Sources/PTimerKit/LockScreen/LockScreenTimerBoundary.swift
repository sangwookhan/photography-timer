import Foundation
import PTimerCore

/// Platform-neutral lock-screen timer boundary. The ActivityKit-backed exposer
/// and the Live Activity attributes stay in the app target and depend on these.
public struct LockScreenTimerTarget: Equatable {
    public let representativeTimerID: UUID
    public let representativeTimerName: String
    public let representativeEndDate: Date
    public let scheduledTargets: [ScheduledTimerTarget]

    public init(
        representativeTimerID: UUID,
        representativeTimerName: String,
        representativeEndDate: Date,
        scheduledTargets: [ScheduledTimerTarget]
    ) {
        self.representativeTimerID = representativeTimerID
        self.representativeTimerName = representativeTimerName
        self.representativeEndDate = representativeEndDate
        self.scheduledTargets = scheduledTargets
    }
}

public protocol LockScreenTimerTargetExposing {
    @MainActor func expose(_ target: LockScreenTimerTarget)
    @MainActor func clear()
}

public struct NoOpLockScreenTimerTargetExposer: LockScreenTimerTargetExposing {
    public init() {}
    public func expose(_ target: LockScreenTimerTarget) {}
    public func clear() {}
}
