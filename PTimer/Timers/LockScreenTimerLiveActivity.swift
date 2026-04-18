import ActivityKit
import Foundation

struct LockScreenTimerScheduledTarget: Codable, Equatable, Hashable {
    let timerID: UUID
    let timerName: String
    let endDate: Date
}

struct TimerTargetLiveActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        let representativeTimerName: String
        let representativeEndDate: Date
        let scheduledTargets: [LockScreenTimerScheduledTarget]

        func displayTarget(at now: Date) -> LockScreenTimerScheduledTarget? {
            scheduledTargets.first(where: { $0.endDate > now })
        }
    }

    let surfaceID: String

    static let lockScreenSurfaceID = "lock-screen-target-surface"
}
