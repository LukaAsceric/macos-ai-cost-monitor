import Foundation
#if canImport(UserNotifications)
import UserNotifications
#endif

public enum BudgetNotifier {
    public static func isSupportedAppBundle(bundleURL: URL, bundleIdentifier: String?) -> Bool {
        bundleURL.pathExtension.lowercased() == "app" && bundleIdentifier != nil && !(bundleIdentifier?.isEmpty ?? true)
    }

    public static func notify(amount: Decimal, limit: Decimal, bundle: Bundle = .main) {
        #if canImport(UserNotifications)
        guard isSupportedAppBundle(
            bundleURL: bundle.bundleURL,
            bundleIdentifier: bundle.bundleIdentifier
        ) else {
            return
        }

        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = "AI Cost Monitor"
            content.body = "Spend \(amount) reached the configured budget of \(limit)."
            let request = UNNotificationRequest(
                identifier: "budget-threshold",
                content: content,
                trigger: nil
            )
            center.add(request, withCompletionHandler: nil)
        }
        #endif
    }
}
