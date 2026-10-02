import AppKit

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model: CostMonitorModel
    private let logStore: AppLogStore
    private var statusBarController: StatusBarController?
    private var settingsWindowController: SettingsWindowController?
    public let updateManager: UpdateManager

    public override init() {
        let logStore = AppLogStore()
        self.logStore = logStore
        // Credentials and usage clients are kept per provider so switching the
        // provider never overwrites the other provider's saved secret.
        let environmentByProvider: (ProviderOption) -> ProviderEnvironment = { provider in
            switch provider {
            case .primalabs:
                return ProviderEnvironment(
                    usage: PrimaLabsClient(diagnosticLogStore: logStore),
                    secrets: KeychainStore(account: ProviderOption.primalabs.keychainAccount)
                )
            default:
                return ProviderEnvironment(
                    usage: OpenRouterClient(diagnosticLogStore: logStore),
                    secrets: KeychainStore(account: ProviderOption.openRouter.keychainAccount)
                )
            }
        }
        self.model = CostMonitorModel(
            provider: OpenRouterClient(diagnosticLogStore: logStore),
            secretStore: KeychainStore(),
            cache: UsageCache(),
            logStore: logStore,
            environmentByProvider: environmentByProvider
        )
        self.updateManager = UpdateManager()
        super.init()
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        updateManager.start()
        statusBarController = StatusBarController(model: model, appDelegate: self)
        Task { @MainActor [weak self] in
            guard let self else { return }
            _ = await self.model.refresh()
            self.model.startPolling(interval: self.model.preferences.refreshInterval)
        }
    }

    public func applicationWillTerminate(_ notification: Notification) {
        statusBarController?.shutdown()
        model.stopPolling()
    }

    public func showSettings() {
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController(model: model, logStore: logStore, updateManager: updateManager)
        }
        settingsWindowController?.present()
    }

}
