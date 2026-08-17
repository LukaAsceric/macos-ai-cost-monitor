import SwiftUI

@MainActor
public struct DashboardView: View {
    @ObservedObject private var model: CostMonitorModel
    private let onQuit: () -> Void
    @State private var showSettings = false

    public init(model: CostMonitorModel, onQuit: @escaping () -> Void) {
        self.model = model
        self.onQuit = onQuit
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            content
            Divider()
            footer
        }
        .padding(16)
        .frame(width: 390)
        .sheet(isPresented: $showSettings) {
            SettingsView(model: model)
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("OpenRouter")
                    .font(.headline)
                Text(dateLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if isRefreshing {
                ProgressView()
                    .controlSize(.small)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .notConfigured:
            emptyState("Add a management key in Settings to begin.", systemImage: "key")
        case .loading(let previous):
            if let previous {
                costContent(previous, stale: false)
            } else {
                emptyState("Refreshing usage…", systemImage: "arrow.clockwise")
            }
        case .loaded(let cost, _, let stale):
            costContent(cost, stale: stale)
        case .noData(let date, let fetchedAt, let previous):
            VStack(alignment: .leading, spacing: 8) {
                if let previous {
                    costContent(previous, stale: true)
                }
                emptyState("OpenRouter has not published activity for this UTC day yet.", systemImage: "clock")
                Text("Requested date: \(date) UTC")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let fetchedAt {
                    updatedLabel(fetchedAt)
                }
            }
        case .failed(let message, let previous, _):
            VStack(alignment: .leading, spacing: 8) {
                if let previous { costContent(previous, stale: true) }
                Label(message, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    private func costContent(_ cost: DailyCost, stale: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(CostFormatStyle.headline(cost.usage))
                    .font(.system(size: 32, weight: .semibold, design: .rounded))
                if stale {
                    Text("stale")
                        .font(.caption2)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(.orange.opacity(0.15))
                        .clipShape(Capsule())
                }
            }
            HStack(spacing: 12) {
                metric("Requests", value: CostFormatStyle.tokens(cost.requests))
                metric("Prompt", value: CostFormatStyle.tokens(cost.promptTokens))
                metric("Completion", value: CostFormatStyle.tokens(cost.completionTokens))
                metric("Reasoning", value: CostFormatStyle.tokens(cost.reasoningTokens))
            }
            metric("Estimated BYOK", value: CostFormatStyle.headline(cost.byokUsageInference))
            if !cost.breakdowns.isEmpty {
                Divider()
                Text("By model")
                    .font(.subheadline.weight(.medium))
                ForEach(cost.breakdowns.prefix(5)) { breakdown in
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(breakdown.model)
                                .lineLimit(1)
                            Text(breakdown.provider)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(CostFormatStyle.headline(breakdown.usage))
                            .font(.caption.monospacedDigit())
                    }
                }
            }
            if let lastUpdated = model.lastUpdated {
                updatedLabel(lastUpdated)
            }
        }
    }

    private func updatedLabel(_ date: Date) -> some View {
        Text("Last updated \(date.formatted(date: .omitted, time: .shortened))")
            .font(.caption2)
            .foregroundStyle(.secondary)
    }

    private func metric(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.subheadline.monospacedDigit())
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func emptyState(_ message: String, systemImage: String) -> some View {
        Label(message, systemImage: systemImage)
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var footer: some View {
        HStack {
            Button("Refresh now") {
                Task { _ = await model.refresh() }
            }
            .disabled(isRefreshing)
            Spacer()
            Button("Settings") { showSettings = true }
            Button("Quit") { onQuit() }
        }
        .buttonStyle(.borderless)
        .font(.caption)
    }

    private var dateLabel: String {
        switch model.state {
        case .loaded(let cost, _, _):
            return "\(cost.date) UTC"
        case .loading(let previous):
            return previous.map { "\($0.date) UTC" } ?? "Today · UTC"
        case .noData(let date, _, _):
            return "\(date) UTC"
        case .failed(_, let previous, _):
            return previous.map { "\($0.date) UTC" } ?? "Today · UTC"
        case .notConfigured:
            return "Today · UTC"
        }
    }

    private var isRefreshing: Bool {
        if case .loading = model.state { return true }
        return false
    }
}
