import AppKit
import Combine
import SwiftUI

@MainActor
public final class StatusBarController: NSObject {
    private let model: CostMonitorModel
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private var stateSubscription: AnyCancellable?

    public init(model: CostMonitorModel) {
        self.model = model
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        statusItem.button?.target = self
        statusItem.button?.action = #selector(togglePopover)
        popover.behavior = .transient
        popover.animates = true
        stateSubscription = model.$state
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.updateTitle()
                }
            }
        updateTitle()
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            let view = DashboardView(model: model) { NSApp.terminate(nil) }
            popover.contentViewController = NSHostingController(rootView: view)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    private func updateTitle() {
        guard let button = statusItem.button else { return }
        switch model.state {
        case .loaded(let cost, _, let stale):
            let value = CostFormatStyle.headline(cost.usage)
            button.title = value
            button.toolTip = "OpenRouter cost for \(cost.date) UTC: \(value)"
            button.setAccessibilityLabel("OpenRouter cost for \(cost.date) UTC: \(value)\(stale ? ", stale" : "")")
        case .loading(let previous):
            button.title = previous.map { CostFormatStyle.headline($0.usage) } ?? "…"
            button.toolTip = "Refreshing OpenRouter usage"
            button.setAccessibilityLabel("Refreshing OpenRouter usage")
        case .failed(_, let previous, _):
            button.title = previous.map { CostFormatStyle.headline($0.usage) } ?? "—"
            button.toolTip = "OpenRouter usage is stale or unavailable"
            button.setAccessibilityLabel("OpenRouter usage is stale or unavailable")
        case .notConfigured:
            button.title = "—"
            button.toolTip = "OpenRouter usage is not configured"
            button.setAccessibilityLabel("OpenRouter usage is not configured")
        case .noData(let date, _, let previous):
            let value = previous.map { CostFormatStyle.headline($0.usage) } ?? "—"
            button.title = value
            button.toolTip = "No OpenRouter activity published for \(date) UTC"
            button.setAccessibilityLabel("No OpenRouter activity published for \(date) UTC; showing last known value \(value)")
        }
    }
}
