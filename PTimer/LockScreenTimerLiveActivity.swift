import ActivityKit
import Foundation

struct TimerTargetLiveActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        let timerName: String
        let endDate: Date
    }

    let timerID: UUID
}
