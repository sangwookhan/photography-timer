import ActivityKit
import SwiftUI
import UIKit

@main
struct PTimerApp: App {
    @UIApplicationDelegateAdaptor(PTimerAppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

final class PTimerAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        // The calculator currently owns the app's root experience, and the
        // local hosting wrapper did not reliably stop runtime rotation. Keep
        // portrait enforced here until the calculator flow has a stronger
        // screen-level UIKit boundary or a dedicated landscape design.
        .portrait
    }
}

struct LockScreenTimerTarget: Equatable {
    let timerID: UUID
    let timerName: String
    let endDate: Date
}

protocol LockScreenTimerTargetExposing {
    @MainActor
    func expose(_ target: LockScreenTimerTarget)

    @MainActor
    func clear()
}

struct NoOpLockScreenTimerTargetExposer: LockScreenTimerTargetExposing {
    func expose(_ target: LockScreenTimerTarget) {}
    func clear() {}
}

@MainActor
final class ActivityKitLockScreenTimerTargetExposer: LockScreenTimerTargetExposing {
    private var activity: Activity<TimerTargetLiveActivityAttributes>?
    private var activeTarget: LockScreenTimerTarget?

    func expose(_ target: LockScreenTimerTarget) {
        guard activeTarget != target else {
            return
        }

        activeTarget = target

        Task {
            await upsertActivity(for: target)
        }
    }

    func clear() {
        guard activeTarget != nil || activity != nil else {
            return
        }

        activeTarget = nil
        let existingActivity = activity
        activity = nil

        Task {
            await existingActivity?.end(nil, dismissalPolicy: .immediate)
        }
    }

    private func upsertActivity(for target: LockScreenTimerTarget) async {
        let attributes = TimerTargetLiveActivityAttributes(timerID: target.timerID)
        let content = ActivityContent(
            state: TimerTargetLiveActivityAttributes.ContentState(
                timerName: target.timerName,
                endDate: target.endDate
            ),
            staleDate: target.endDate
        )

        if let activity {
            if activity.attributes.timerID == target.timerID {
                await activity.update(content)
                return
            }

            self.activity = nil
            await activity.end(nil, dismissalPolicy: .immediate)
        }

        activity = try? Activity.request(
            attributes: attributes,
            content: content
        )
    }
}
