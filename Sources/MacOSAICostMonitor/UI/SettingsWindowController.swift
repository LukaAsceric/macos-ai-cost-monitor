import AppKit
import SwiftUI

@MainActor
public final class SettingsWindowController: NSWindowController {
    public init(model: CostMonitorModel, logStore: AppLogStore, updateManager: UpdateManager) {
        let rootView = SettingsRootView(model: model, logStore: logStore, updateManager: updateManager)
        let hostingController = NSHostingController(rootView: rootView)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "AI Cost Monitor Settings"
        window.styleMask = [.titled, .closable]
        window.setContentSize(NSSize(width: 900, height: 620))
        window.center()
        window.isReleasedWhenClosed = false
        window.toolbarStyle = .unified
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func present() {
        guard let window else { return }
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window.makeKeyAndOrderFront(nil)
    }
}
