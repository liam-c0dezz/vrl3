//
//  NotificationService.swift
//  Construction Estimate
//
//  Permission, APNs device registration, and notification taps.
//

import Foundation
import Auth
import Observation
import PostgREST
import Supabase
import UIKit
import UserNotifications

/// Where a notification, widget or deep link should take the user.
enum AppRoute: Equatable {
    case home
    case newEstimate
    case notifications
    case recap
    case settings

    init?(host: String?) {
        switch host?.lowercased() {
        case "home": self = .home
        case "new-estimate": self = .newEstimate
        case "notifications": self = .notifications
        case "recap": self = .recap
        case "settings": self = .settings
        default: return nil
        }
    }
}

@MainActor
@Observable
final class AppRouter {
    static let shared = AppRouter()
    /// ContentView consumes this and resets it to nil.
    var pending: AppRoute?
    private init() {}
}

@MainActor
final class NotificationService: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationService()

    private var deviceToken: String?

    func configure() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        let open = UNNotificationAction(identifier: "open", title: L("Open"), options: [.foreground])
        center.setNotificationCategories([
            UNNotificationCategory(identifier: "client_activity", actions: [open], intentIdentifiers: []),
            UNNotificationCategory(identifier: "streak_at_risk", actions: [], intentIdentifiers: []),
            UNNotificationCategory(identifier: "weekly_recap", actions: [], intentIdentifiers: []),
            UNNotificationCategory(identifier: "trial_ending", actions: [], intentIdentifiers: []),
        ])
        Task { await registerIfAuthorized() }
    }

    /// Asks iOS for permission. Only called from the pre-prompt after a win.
    func requestAuthorization() async -> Bool {
        let granted = (try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .badge, .sound])) ?? false
        if granted {
            UIApplication.shared.registerForRemoteNotifications()
        }
        return granted
    }

    func registerIfAuthorized() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        if [.authorized, .provisional, .ephemeral].contains(settings.authorizationStatus) {
            UIApplication.shared.registerForRemoteNotifications()
        }
    }

    var authorizationStatus: UNAuthorizationStatus {
        get async { await UNUserNotificationCenter.current().notificationSettings().authorizationStatus }
    }

    // MARK: APNs token

    func didRegister(deviceToken data: Data) {
        deviceToken = data.map { String(format: "%02x", $0) }.joined()
        Task { await uploadToken() }
    }

    /// Saves this device for server pushes (client approved / viewed / asked
    /// for changes). Safe to call repeatedly; the row is keyed by token.
    func uploadToken() async {
        guard let token = deviceToken, supabase.auth.currentUser != nil else { return }
        #if DEBUG
        let environment = "sandbox"
        #else
        let environment = "production"
        #endif
        let params = RegisterPushDeviceParams(
            p_token: token,
            p_platform: "ios",
            p_environment: environment,
            p_bundle_id: Bundle.main.bundleIdentifier ?? "",
            p_app_version: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        )
        _ = try? await supabase.rpc("register_push_device", params: params).execute()
    }

    /// Stops pushes to this device for the signed-out account.
    func unregisterDevice() async {
        guard let token = deviceToken else { return }
        _ = try? await supabase.rpc("unregister_push_device", params: ["p_token": token]).execute()
    }

    // MARK: Delegate

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let info = response.notification.request.content.userInfo
        let route = info["route"] as? String
        let category = info["category"] as? String ?? response.notification.request.content.categoryIdentifier
        let variant = info["variant"] as? String ?? "a"
        await MainActor.run {
            RetentionCenter.shared.log("notification_open", ["category": category, "variant": variant])
            if let route = AppRoute(host: route) {
                AppRouter.shared.pending = route
            }
        }
    }
}

private struct RegisterPushDeviceParams: Encodable {
    let p_token: String
    let p_platform: String
    let p_environment: String
    let p_bundle_id: String
    let p_app_version: String
}

/// Receives the APNs callbacks that SwiftUI does not expose.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        NotificationService.shared.configure()
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        NotificationService.shared.didRegister(deviceToken: deviceToken)
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        // Remote pushes are optional; local reminders keep working.
    }
}
