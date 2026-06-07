import Foundation
import PTimerCore
import UserNotifications

protocol UserNotificationCentering: AnyObject {
    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool
    func add(_ request: UNNotificationRequest) async throws
    func removePendingNotificationRequests(withIdentifiers identifiers: [String])
}

extension UNUserNotificationCenter: UserNotificationCentering {
    func add(_ request: UNNotificationRequest) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            add(request) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }
}

@MainActor
final class UserNotificationTimerCompletionScheduler: TimerCompletionNotificationScheduling {
    private let notificationCenter: UserNotificationCentering
    private let calendar: Calendar
    private var hasRequestedAuthorization = false

    init(
        notificationCenter: UserNotificationCentering = UNUserNotificationCenter.current(),
        calendar: Calendar = .current
    ) {
        self.notificationCenter = notificationCenter
        self.calendar = calendar
    }

    func requestAuthorizationIfNeeded() {
        guard !hasRequestedAuthorization else {
            return
        }

        hasRequestedAuthorization = true

        Task {
            _ = try? await notificationCenter.requestAuthorization(
                options: [.alert, .sound]
            )
        }
    }

    func scheduleCompletionNotification(for timer: TimerState) {
        guard timer.status == .running, let endDate = timer.endDate else {
            cancelCompletionNotification(forTimerID: timer.id)
            return
        }

        let content = UNMutableNotificationContent()
        content.title = "Timer Complete"
        content.body = "Your timer has finished."
        content.sound = .default
        content.userInfo = ["timerID": timer.id.uuidString]

        let trigger = UNCalendarNotificationTrigger(
            dateMatching: calendar.dateComponents(
                [.year, .month, .day, .hour, .minute, .second],
                from: endDate
            ),
            repeats: false
        )
        let request = UNNotificationRequest(
            identifier: Self.notificationIdentifier(for: timer.id),
            content: content,
            trigger: trigger
        )

        Task {
            try? await notificationCenter.add(request)
        }
    }

    func cancelCompletionNotification(forTimerID timerID: UUID) {
        notificationCenter.removePendingNotificationRequests(
            withIdentifiers: [Self.notificationIdentifier(for: timerID)]
        )
    }

    static func notificationIdentifier(for timerID: UUID) -> String {
        "timer-completion-\(timerID.uuidString.lowercased())"
    }
}
