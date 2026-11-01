import Foundation
import UIKit
import UserNotifications

extension Notification.Name {
    static let spyderChatDeviceToken = Notification.Name("spyder.chat.apns.registered")
    static let spyderChatOpenRequested = Notification.Name("spyder.chat.push.open")
}

/// App delegate receives a fresh APNs token. No chat plaintext or private keys are included.
final class SpyderPushAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        NotificationCenter.default.post(name: .spyderChatDeviceToken, object: nil,
                                        userInfo: ["token": deviceToken])
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        NotificationCenter.default.post(name: .spyderChatDeviceToken, object: nil,
                                        userInfo: ["error": error.localizedDescription])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .badge])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        // A locked wallet must be unlocked before opening a chat.
        UserDefaults.standard.set(true, forKey: "spyder.chat.push.open.pending")
        NotificationCenter.default.post(name: .spyderChatOpenRequested, object: nil)
        completionHandler()
    }
}
