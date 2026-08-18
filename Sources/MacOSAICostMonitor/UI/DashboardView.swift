import SwiftUI

@MainActor
public struct DashboardView: View {
    @ObservedObject private var model: CostMonitorModel
    @ObservedObject private var preferences: ReportingPreferences
    private let onSettings: () -> Void
    private let onQuit: () -> Void

    public init(model: CostMonitorModel, onSettings: @escaping () -> Void, onQuit: @escaping () -> Void) {
        self.model = model
        self.preferences = model.preferences
        self.onSettings = onSettings
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
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("OpenRouter")
                        .font(.headline)
                }
                HStack(spacing: 5) {
                    Text("UTC")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color.secondary.opacity(0.15))
                        .clipShape(Capsule())
                    Text("Display timezone: \(preferences.displayTimeZone.identifier)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
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
            VStack(alignment: .leading, spacing: 8) {
                if stale {
                    Label("Showing the latest cached completed UTC day.", systemImage: "clock.arrow.circlepath")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                costContent(cost, stale: stale)
            }
        case .noData(let date, let fetchedAt, let previous):
            VStack(alignment: .leading, spacing: 8) {
                if let previous {
                    costContent(previous, stale: true)
                }
                emptyState("No activity is available for this completed UTC day.", systemImage: "clock")
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
                Text(CostFormatStyle.headline(displayedUsage(for: cost), maximumFractionDigits: preferences.decimalPlaces))
                    .font(.system(size: 32, weight: .semibold, design: .rounded))
                if stale {
                    Text("stale")
                        .font(.caption2)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(.orange.opacity(0.15))
                        .clipShape(Capsule())
                }
                if model.budgetExceeded {
                    Text("budget")
                        .font(.caption2)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(.red.opacity(0.15))
                        .clipShape(Capsule())
                }
            }
            if !model.series.isEmpty {
                SpendChartView(points: model.series)
                    .frame(height: 72)
            }
            HStack(spacing: 12) {
                metric("Requests", value: CostFormatStyle.tokens(cost.requests))
                metric("Sessions", value: model.sessionCount.map(String.init) ?? "—")
                metric("Credits", value: model.remainingCredits.map {
                    CostFormatStyle.headline($0, maximumFractionDigits: preferences.decimalPlaces)
                } ?? "—")
            }
            if !cost.breakdowns.isEmpty {
                Divider()
                Text("By model")
                    .font(.subheadline.weight(.medium))
                ForEach(displayedBreakdowns(cost)) { breakdown in
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(breakdown.model)
                                .lineLimit(1)
                            if !preferences.groupModelsAcrossProviders && preferences.showProviderDetails {
                                Text(breakdown.provider)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Text(CostFormatStyle.headline(breakdown.usage, maximumFractionDigits: preferences.decimalPlaces))
                            .font(.caption.monospacedDigit())
                    }
                }
            }
            if let lastUpdated = model.lastUpdated {
                updatedLabel(lastUpdated)
            }
        }
    }

    private func displayedBreakdowns(_ cost: DailyCost) -> [CostBreakdown] {
        let list = preferences.showFullBreakdown ? cost.breakdowns : Array(cost.breakdowns.prefix(5))
        guard preferences.groupModelsAcrossProviders else { return list }
        return list.groupedByModel()
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

    private func displayedUsage(for cost: DailyCost) -> Decimal {
        model.preferences.includeByokInHeadline
            ? cost.usage + cost.byokUsageInference
            : cost.usage
    }

    private func emptyState(_ message: String, systemImage: String) -> some View {
        Label(message, systemImage: systemImage)
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var footer: some View {
        HStack {
            Menu {
                ForEach(ReportTimeRange.Group.allCases) { group in
                    Section(group.title) {
                        ForEach(ReportTimeRange.options(in: group).filter(\.isSupported)) { range in
                            Button {
                                selectTimeRange(range)
                            } label: {
                                if preferences.timeRange == range {
                                    Label(range.title, systemImage: "checkmark")
                                } else {
                                    Text(range.title)
                                }
                            }
                        }
                    }
                }
            } label: {
                Label(preferences.timeRange.badge, systemImage: "calendar")
            }
            Button("Refresh now") {
                Task { _ = await model.refresh() }
            }
            .disabled(isRefreshing)
            Spacer()
            Button("Settings") { onSettings() }
            Button("Quit") { onQuit() }
        }
        .buttonStyle(.borderless)
        .font(.caption)
    }

    private func selectTimeRange(_ range: ReportTimeRange) {
        guard range.isSupported else { return }
        preferences.timeRange = range
        model.applyPreferenceChanges()
    }

    private var dateLabel: String {
        switch model.state {
        case .loaded(let cost, _, _):
            return reportDateLabel(cost.date)
        case .loading(let previous):
            return previous.map { reportDateLabel($0.date) } ?? "Latest available · UTC"
        case .noData(let date, _, _):
            return reportDateLabel(date)
        case .failed(_, let previous, _):
            return previous.map { reportDateLabel($0.date) } ?? "Latest available · UTC"
        case .notConfigured:
            return "Latest available · UTC"
        }
    }

    private func reportDateLabel(_ date: String) -> String {
        UTCCalendar.readableDayLabel(from: date)
    }

    private var isRefreshing: Bool {
        if case .loading = model.state { return true }
        return false
    }
}
