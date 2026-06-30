// Copyright © 2026 Sangwook Han
// SPDX-License-Identifier: Apache-2.0

import ActivityKit
import PTimerKit
import SwiftUI
import UIKit
import UserNotifications

@main
struct PTimerApp: App {
    @UIApplicationDelegateAdaptor(PTimerAppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

final class PTimerAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Observe notification taps so the silent-mode advisory can be
        // suppressed when the app is opened from a timer notification
        // (PTIMER-73). Intentionally no `willPresent` implementation: foreground
        // notifications stay suppressed, preserving pre2's not-foreground-only
        // delivery.
        UNUserNotificationCenter.current().delegate = self
        return true
    }

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

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        // The app's only notifications are timer alerts, so any tap means this
        // foreground entry came from a timer notification: suppress the passive
        // silent-mode advisory for it (PTIMER-73).
        Task { @MainActor in
            SilentModeAdvisoryController.shared.noteOpenedFromNotification()
        }
        completionHandler()
    }
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
        guard activeTarget != nil || activity != nil || hasExistingSurfaceActivity else {
            return
        }

        activeTarget = nil
        let existingActivity = resolveActivity(
            matching: TimerTargetLiveActivityAttributes.lockScreenSurfaceID
        )
        activity = nil

        Task {
            await existingActivity?.end(nil, dismissalPolicy: .immediate)
        }
    }

    private func upsertActivity(for target: LockScreenTimerTarget) async {
        let attributes = TimerTargetLiveActivityAttributes(
            surfaceID: TimerTargetLiveActivityAttributes.lockScreenSurfaceID
        )
        let content = ActivityContent(
            state: TimerTargetLiveActivityAttributes.ContentState(
                representativeTimerName: target.representativeTimerName,
                representativeEndDate: target.representativeEndDate,
                scheduledTargets: target.scheduledTargets
            ),
            staleDate: target.scheduledTargets.last?.endDate
        )

        if let existingActivity = resolveActivity(matching: attributes.surfaceID) {
            self.activity = existingActivity
            await existingActivity.update(content)
            return
        }

        activity = try? Activity.request(
            attributes: attributes,
            content: content
        )
    }

    private func resolveActivity(
        matching surfaceID: String
    ) -> Activity<TimerTargetLiveActivityAttributes>? {
        if let activity, activity.attributes.surfaceID == surfaceID {
            return activity
        }

        let existingActivities = Activity<TimerTargetLiveActivityAttributes>.activities
            .filter { $0.attributes.surfaceID == surfaceID }

        guard let firstActivity = existingActivities.first else {
            return nil
        }

        activity = firstActivity
        return firstActivity
    }

    private var hasExistingSurfaceActivity: Bool {
        Activity<TimerTargetLiveActivityAttributes>.activities.contains {
            $0.attributes.surfaceID == TimerTargetLiveActivityAttributes.lockScreenSurfaceID
        }
    }
}
