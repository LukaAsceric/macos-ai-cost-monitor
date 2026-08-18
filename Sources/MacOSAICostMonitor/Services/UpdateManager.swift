import Foundation
import Combine
@preconcurrency import Sparkle

public enum UpdateConfiguration {
    public static let feedURL = URL(string: "https://github.com/LukaAsceric/macos-ai-cost-monitor/releases/latest/download/appcast.xml")!

    public static func isValid(
        bundleURL: URL,
        bundleIdentifier: String?,
        feedURLString: String?,
        publicKey: String?
    ) -> Bool {
        guard bundleURL.pathExtension.caseInsensitiveCompare("app") == .orderedSame,
              bundleIdentifier?.isEmpty == false,
              let feedURL = URL(string: feedURLString ?? ""),
              feedURL.scheme?.lowercased() == "https",
              feedURL.host?.isEmpty == false,
              let publicKeyData = Data(base64Encoded: publicKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""),
              publicKeyData.count == 32
        else {
            return false
        }
        return true
    }
}

@MainActor
public final class UpdateManager: NSObject, ObservableObject {
    @Published public private(set) var isConfigured = false
    @Published public private(set) var canCheckForUpdates = false
    @Published public private(set) var automaticUpdates = false
    @Published public private(set) var canConfigureAutomaticUpdates = false
    @Published public private(set) var status = "Updates are unavailable for this build."

    private let updaterController: SPUStandardUpdaterController?

    public override convenience init() {
        let bundle = Bundle.main
        self.init(
            bundleURL: bundle.bundleURL,
            bundleIdentifier: bundle.bundleIdentifier,
            feedURLString: bundle.object(forInfoDictionaryKey: "SUFeedURL") as? String,
            publicKey: bundle.object(forInfoDictionaryKey: "SUPublicEDKey") as? String
        )
    }

    public init(
        bundleURL: URL,
        bundleIdentifier: String?,
        feedURLString: String?,
        publicKey: String?
    ) {
        let valid = UpdateConfiguration.isValid(
            bundleURL: bundleURL,
            bundleIdentifier: bundleIdentifier,
            feedURLString: feedURLString,
            publicKey: publicKey
        )
        isConfigured = valid

        let isCurrentApplicationBundle = bundleURL.standardizedFileURL == Bundle.main.bundleURL.standardizedFileURL
        if valid && isCurrentApplicationBundle {
            let controller = SPUStandardUpdaterController(
                startingUpdater: false,
                updaterDelegate: nil,
                userDriverDelegate: nil
            )
            updaterController = controller
            automaticUpdates = controller.updater.automaticallyDownloadsUpdates
            canConfigureAutomaticUpdates = controller.updater.allowsAutomaticUpdates
            status = "Signed updates are available."
        } else {
            updaterController = nil
            status = valid
                ? "Updates are configured for the packaged app bundle."
                : bundleURL.pathExtension.caseInsensitiveCompare("app") == .orderedSame
                    ? "Updates need a signed Sparkle public key in this release."
                    : "Updates are available only when the app runs from an .app bundle."
        }

        super.init()
        refreshAvailability()
    }

    public func start() {
        guard let updaterController else { return }
        updaterController.startUpdater()
        refreshAvailability()
    }

    public func checkForUpdates() {
        guard let updaterController, updaterController.updater.canCheckForUpdates else { return }
        updaterController.checkForUpdates(nil)
        refreshAvailability()
    }

    public func setAutomaticUpdates(_ enabled: Bool) {
        guard let updaterController, updaterController.updater.allowsAutomaticUpdates else { return }
        guard updaterController.updater.automaticallyChecksForUpdates else {
            automaticUpdates = false
            return
        }
        updaterController.updater.automaticallyDownloadsUpdates = enabled
        automaticUpdates = updaterController.updater.automaticallyDownloadsUpdates
    }

    public func refreshAvailability() {
        canCheckForUpdates = updaterController?.updater.canCheckForUpdates ?? false
    }
}
