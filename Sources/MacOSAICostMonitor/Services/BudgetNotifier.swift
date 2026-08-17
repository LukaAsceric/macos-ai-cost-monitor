import Foundation
#if canImport(UserNotifications)
import UserNotifications
#endif

public enum BudgetNotifier {
    public static func notify(amount: Decimal, limit: Decimal) {
        #if canImport(UserNotifications)
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
