import SwiftUI

@main
@MainActor
struct MacOSAICostMonitorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Check for Updates…") {
                    appDelegate.updateManager.checkForUpdates()
                }
                .disabled(!appDelegate.updateManager.canCheckForUpdates)

                Button("Settings…") {
                    appDelegate.showSettings()
                }
                .keyboardShortcut(",", modifiers: [.command])
            }
        }
    }
}
