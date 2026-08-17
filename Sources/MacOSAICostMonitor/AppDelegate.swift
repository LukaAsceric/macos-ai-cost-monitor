import AppKit

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model: CostMonitorModel
    private let logStore: AppLogStore
    private var statusBarController: StatusBarController?
    private var settingsWindowController: SettingsWindowController?

    public override init() {
        let logStore = AppLogStore()
        self.logStore = logStore
        self.model = CostMonitorModel(
            provider: OpenRouterClient(),
            secretStore: KeychainStore(),
            cache: UsageCache(),
            logStore: logStore
        )
        super.init()
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        statusBarController = StatusBarController(model: model, appDelegate: self)
        Task { @MainActor [weak self] in
            guard let self else { return }
            _ = await self.model.refresh()
            self.model.startPolling(interval: self.model.preferences.refreshInterval)
        }
    }

    public func applicationWillTerminate(_ notification: Notification) {
        model.stopPolling()
    }

    public func showSettings() {
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController(model: model, logStore: logStore)
        }
        settingsWindowController?.present()
    }

}
