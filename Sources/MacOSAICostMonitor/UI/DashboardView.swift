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
                    Text(model.displayProviderTitle)
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
            emptyState("Add a credential in Settings to begin.", systemImage: "key")
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
                if !model.providerWarnings.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(model.providerWarnings, id: \.self) { warning in
                            Label(warning, systemImage: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
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
                SpendChartView(points: model.series, timeZone: preferences.displayTimeZone)
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
                if preferences.aggregateProviders {
                    Text("By provider")
                        .font(.subheadline.weight(.medium))
                    ForEach(cost.breakdowns.groupedByService()) { group in
                        breakdownRow(title: group.service, subtitle: nil, usage: group.usage)
                        if group.showsUpstreamBreakdown {
                            ForEach(group.upstreams) { upstream in
                                breakdownRow(title: upstream.provider, subtitle: nil, usage: upstream.usage)
                                    .padding(.leading, 12)
                            }
                        }
                    }
                    Divider()
                }
                Text("By model")
                    .font(.subheadline.weight(.medium))
                ForEach(displayedBreakdowns(cost)) { breakdown in
                    breakdownRow(
                        title: breakdown.model,
                        subtitle: modelRowSubtitle(for: breakdown),
                        usage: breakdown.usage
                    )
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

    /// Aggregate rows (providers that report no per-model split) always name
    /// their source, so the costs stay attributable even without provider
    /// details. Regular model rows keep the user's provider-detail preference.
    private func modelRowSubtitle(for breakdown: CostBreakdown) -> String? {
        if breakdown.model == PrimaLabsClient.aggregateModelName {
            return breakdown.provider
        }
        if !preferences.groupModelsAcrossProviders && preferences.showProviderDetails {
            return breakdown.provider
        }
        return nil
    }

    private func breakdownRow(title: String, subtitle: String?, usage: Decimal) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .lineLimit(1)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text(CostFormatStyle.headline(usage, maximumFractionDigits: preferences.decimalPlaces))
                .font(.caption.monospacedDigit())
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

    private func displayedUsage(for cost: DailyCost) -> Decimal {
        cost.usage
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
                        ForEach(ReportTimeRange.options(in: group).filter { preferences.isTimeRangeSupported($0) }) { range in
                            Button {
                                selectTimeRange(range)
                            } label: {
                                if preferences.timeRange == range {
                                    Label(range.menuLabel, systemImage: "checkmark")
                                } else {
                                    Text(range.menuLabel)
                                }
                            }
                        }
                    }
                }
            } label: {
                Label(preferences.timeRange.menuLabel, systemImage: "calendar")
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
        guard preferences.isTimeRangeSupported(range) else { return }
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
