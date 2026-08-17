import AppKit
import Combine
import SwiftUI

@MainActor
public final class StatusBarController: NSObject {
    private let model: CostMonitorModel
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private var stateSubscription: AnyCancellable?
    private var preferencesSubscription: AnyCancellable?
    private var globalMouseMonitor: Any?
    private var localMouseMonitor: Any?

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
        preferencesSubscription = model.preferences.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.updateTitle()
                }
            }
        installMouseMonitors()
        updateTitle()
    }

    deinit {
        if let globalMouseMonitor {
            NSEvent.removeMonitor(globalMouseMonitor)
        }
        if let localMouseMonitor {
            NSEvent.removeMonitor(localMouseMonitor)
        }
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            closePopover()
        } else {
            let view = DashboardView(model: model) { NSApp.terminate(nil) }
            popover.contentViewController = NSHostingController(rootView: view)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    private func installMouseMonitors() {
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] _ in
            Task { @MainActor in
                self?.closePopover()
            }
        }
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            Task { @MainActor in
                guard let self, self.popover.isShown else { return }
                if self.isInsidePopover(event) || self.isInsideStatusItem(event) {
                    return
                }
                self.closePopover()
            }
            return event
        }
    }

    private func isInsidePopover(_ event: NSEvent) -> Bool {
        guard let window = popover.contentViewController?.view.window else { return false }
        return window.frame.contains(NSEvent.mouseLocation)
    }

    private func isInsideStatusItem(_ event: NSEvent) -> Bool {
        guard let window = statusItem.button?.window else { return false }
        return window.frame.contains(NSEvent.mouseLocation)
    }

    private func closePopover() {
        guard popover.isShown else { return }
        popover.performClose(nil)
    }

    private func updateTitle() {
        guard let button = statusItem.button else { return }
        switch model.state {
        case .loaded(let cost, _, let stale):
            let value = CostFormatStyle.headline(displayedUsage(for: cost), maximumFractionDigits: model.preferences.decimalPlaces)
            button.title = value
            button.toolTip = "OpenRouter cost for \(cost.date) UTC: \(value)"
            button.setAccessibilityLabel("OpenRouter cost for \(cost.date) UTC: \(value)\(stale ? ", stale" : "")")
        case .loading(let previous):
            button.title = previous.map { CostFormatStyle.headline(displayedUsage(for: $0), maximumFractionDigits: model.preferences.decimalPlaces) } ?? "…"
            button.toolTip = "Refreshing OpenRouter usage"
            button.setAccessibilityLabel("Refreshing OpenRouter usage")
        case .failed(_, let previous, _):
            button.title = previous.map { CostFormatStyle.headline(displayedUsage(for: $0), maximumFractionDigits: model.preferences.decimalPlaces) } ?? "—"
            button.toolTip = "OpenRouter usage is stale or unavailable"
            button.setAccessibilityLabel("OpenRouter usage is stale or unavailable")
        case .notConfigured:
            button.title = "—"
            button.toolTip = "OpenRouter usage is not configured"
            button.setAccessibilityLabel("OpenRouter usage is not configured")
        case .noData(let date, _, let previous):
            let value = previous.map { CostFormatStyle.headline(displayedUsage(for: $0), maximumFractionDigits: model.preferences.decimalPlaces) } ?? "—"
            button.title = value
            button.toolTip = "No OpenRouter activity published for \(date) UTC"
            button.setAccessibilityLabel("No OpenRouter activity published for \(date) UTC; showing last known value \(value)")
        }
    }

    private func displayedUsage(for cost: DailyCost) -> Decimal {
        model.preferences.includeByokInHeadline
            ? cost.usage + cost.byokUsageInference
            : cost.usage
    }
}
