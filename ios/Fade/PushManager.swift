import SwiftUI
import UIKit
import UserNotifications

/// Asks permission for notifications and gives Apple's device token to the server.
/// Needs the paid Apple Developer account and the Push Notifications capability to actually deliver anything
/// (see TESTING.md); without them everything here fails quietly.
@MainActor
final class PushManager {
    static let shared = PushManager()

    /// Shows the iOS permission prompt (first time only), then registers for pushes.
    func requestPermissionAndRegister() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let granted = (try? await center.requestAuthorization(options: [.alert, .badge, .sound])) ?? false
        if granted { UIApplication.shared.registerForRemoteNotifications() }
        return granted
    }

    /// On launch: if the user already said yes, make sure the server has this phone's current token.
    func registerIfAuthorized() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        if settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional {
            UIApplication.shared.registerForRemoteNotifications()
        }
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    /// Called with the token Apple gave this phone.
    func register(token: String) async {
        #if DEBUG
        let environment = "sandbox"       // Xcode builds talk to Apple's test push servers
        #else
        let environment = "production"    // TestFlight and App Store builds
        #endif
        struct Params: Encodable {
            let token: String
            let environment: String
            enum CodingKeys: String, CodingKey {
                case token = "p_token"
                case environment = "p_environment"
            }
        }
        _ = try? await supabase.rpc("register_device_token", params: Params(token: token, environment: environment)).execute()
    }

    func unregister(token: String) async {
        _ = try? await supabase.rpc("unregister_device_token", params: ["p_token": token]).execute()
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let hex = deviceToken.map { String(format: "%02x", $0) }.joined()
        Task { @MainActor in await PushManager.shared.register(token: hex) }
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        // Normal in the simulator and on builds without the Push Notifications capability. Nothing to do.
    }
}
