import AppKit

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = CostMonitorModel(
        provider: OpenRouterClient(),
        secretStore: KeychainStore(),
        cache: UsageCache()
    )
    private var statusBarController: StatusBarController?

    public func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        statusBarController = StatusBarController(model: model)
        Task { @MainActor [weak self] in
            guard let self else { return }
            _ = await self.model.refresh()
            self.model.startPolling(interval: self.model.preferences.refreshInterval)
        }
    }

    public func applicationWillTerminate(_ notification: Notification) {
        model.stopPolling()
    }
}
