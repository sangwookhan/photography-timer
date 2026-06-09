import ActivityKit
import PTimerCore
import Foundation

struct TimerTargetLiveActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        let representativeTimerName: String
        let representativeEndDate: Date
        let scheduledTargets: [ScheduledTimerTarget]

        func displayTarget(at now: Date) -> ScheduledTimerTarget? {
            scheduledTargets.first(where: { $0.endDate > now })
        }
    }

    let surfaceID: String

    static let lockScreenSurfaceID = "lock-screen-target-surface"
}
