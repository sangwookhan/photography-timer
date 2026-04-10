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
