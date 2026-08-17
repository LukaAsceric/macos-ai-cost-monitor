import SwiftUI

@MainActor
public struct SettingsRootView: View {
    public enum Section: String, CaseIterable, Identifiable, Hashable {
        case general
        case provider
        case reporting
        case console

        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .general: return "General"
            case .provider: return "Provider"
            case .reporting: return "Reporting"
            case .console: return "Console"
            }
        }

        public var icon: String {
            switch self {
            case .general: return "gearshape"
            case .provider: return "network"
            case .reporting: return "chart.bar"
            case .console: return "terminal"
            }
        }
    }

    @ObservedObject private var model: CostMonitorModel
    @ObservedObject private var logStore: AppLogStore
    @State private var selection: Section? = .general

    public init(model: CostMonitorModel, logStore: AppLogStore) {
        self.model = model
        self.logStore = logStore
    }

    public var body: some View {
        NavigationSplitView {
            List(Section.allCases, selection: $selection) { section in
                Label(section.title, systemImage: section.icon)
                    .tag(section)
            }
            .listStyle(.sidebar)
            .navigationTitle("AI Cost Monitor")
        } detail: {
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(minWidth: 760, minHeight: 500)
    }

    @ViewBuilder
    private var detail: some View {
        switch selection ?? .general {
        case .general:
            GeneralSettingsSection(model: model)
        case .provider:
            ProviderSettingsSection(model: model)
        case .reporting:
            ReportingSettingsSection(model: model)
        case .console:
            ConsoleView(logStore: logStore)
        }
    }
}

@MainActor
private struct GeneralSettingsSection: View {
    @ObservedObject var model: CostMonitorModel

    var body: some View {
        SettingsSection(title: "General", subtitle: "Application behavior and diagnostics.") {
            SettingsCard(title: "Status") {
                LabeledContent("Provider", value: model.preferences.provider.title)
                LabeledContent("Time basis", value: "UTC completed days")
                LabeledContent("Cache", value: "Non-sensitive usage only")
                Text("The menu-bar popover stays compact. Use the OpenRouter and Reporting sections to change configuration, and Console to inspect sanitized diagnostics.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

@MainActor
private struct ProviderSettingsSection: View {
    @ObservedObject var model: CostMonitorModel
    @ObservedObject private var preferences: ReportingPreferences
    @State private var key = ""
    @State private var errorMessage: String?

    init(model: CostMonitorModel) {
        self.model = model
        self.preferences = model.preferences
    }

    var body: some View {
        SettingsSection(title: "Provider", subtitle: "Choose the service used for activity reporting.") {
            SettingsCard(title: "Provider catalog") {
                ForEach(ProviderOption.allCases) { provider in
                    HStack {
                        Image(systemName: provider == preferences.provider ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(provider == preferences.provider ? Color.accentColor : Color.secondary)
                        Text(provider.title)
                        Spacer()
                        if provider.isEnabled {
                            Text("Available")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("Coming soon")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .contentShape(Rectangle())
                    .opacity(provider.isEnabled ? 1 : 0.45)
                    .onTapGesture {
                        guard provider.isEnabled else { return }
                        preferences.provider = provider
                        model.applyPreferenceChanges()
                    }
                }
            }

            if preferences.provider == .openRouter {
                SettingsCard(title: "OpenRouter management key") {
                    Text("Create a management API key with activity access. The key is stored in macOS Keychain and never written to logs.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    SecureField("Management API key", text: $key)
                        .textFieldStyle(.roundedBorder)
                    HStack {
                        Button("Save key") { save() }
                            .disabled(key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        Button("Delete saved key", role: .destructive) {
                            do { try model.deleteManagementKey() }
                            catch { errorMessage = "The key could not be deleted from Keychain." }
                        }
                        Spacer()
                    }
                    if let errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
        }
    }

    private func save() {
        Task {
            do {
                try await model.saveManagementKey(key)
                key = ""
                errorMessage = nil
            } catch {
                errorMessage = "The key could not be saved to Keychain."
            }
        }
    }
}

@MainActor
private struct ReportingSettingsSection: View {
    @ObservedObject var model: CostMonitorModel
    @ObservedObject private var preferences: ReportingPreferences

    init(model: CostMonitorModel) {
        self.model = model
        self.preferences = model.preferences
    }

    private func applyTimeRange(_ range: ReportTimeRange) {
        guard range.isSupported else { return }
        preferences.timeRange = range
        model.applyPreferenceChanges()
    }

    var body: some View {
        SettingsSection(title: "Reporting", subtitle: "Control the range, cadence, precision, and diagnostic detail.") {
            SettingsCard(title: "Time range") {
                TimeRangeGroupView(title: "Relative ranges", ranges: [
                    .past15Minutes, .past30Minutes, .pastHour, .past3Hours,
                    .past24Hours, .past48Hours, .pastWeek, .pastMonth, .pastYear
                ], preferences: preferences, onSelect: applyTimeRange)
                TimeRangeGroupView(title: "Calendar ranges", ranges: [
                    .today, .yesterday, .thisWeek, .previousWeek,
                    .thisMonth, .previousMonth, .thisYear, .previousYear, .custom
                ], preferences: preferences, onSelect: applyTimeRange)
                TimeRangeGroupView(title: "Available from OpenRouter", ranges: [
                    .latestAvailableDay, .last30CompletedDays
                ], preferences: preferences, onSelect: applyTimeRange)
                Text("OpenRouter currently exposes completed UTC-day buckets. Minute/hour, local-calendar, and custom ranges are shown for orientation but remain disabled until a provider API can support them accurately.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            SettingsCard(title: "Display and refresh") {
                Picker("Refresh", selection: $preferences.refreshInterval) {
                    Text("Every minute").tag(TimeInterval(60))
                    Text("Every 5 minutes").tag(TimeInterval(300))
                    Text("Every 15 minutes").tag(TimeInterval(900))
                    Text("Every 30 minutes").tag(TimeInterval(1800))
                }
                Picker("Cost decimals", selection: $preferences.decimalPlaces) {
                    ForEach(2...8, id: \.self) { places in
                        Text("\(places)").tag(places)
                    }
                }
                Toggle("Include estimated BYOK in headline", isOn: $preferences.includeByokInHeadline)
                Toggle("Capture raw HTTP responses in Console", isOn: $preferences.captureRawHTTPResponses)
                Text("Raw capture is off by default. When enabled, response bodies are held only in the in-memory console and may contain account activity details.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .onChange(of: preferences.timeRange) { _ in model.applyPreferenceChanges() }
            .onChange(of: preferences.decimalPlaces) { _ in model.applyPreferenceChanges() }
            .onChange(of: preferences.refreshInterval) { _ in model.applyPreferenceChanges() }
            .onChange(of: preferences.includeByokInHeadline) { _ in model.applyPreferenceChanges() }
            .onChange(of: preferences.captureRawHTTPResponses) { _ in model.applyPreferenceChanges() }
        }
    }
}

@MainActor
private struct TimeRangeGroupView: View {
    let title: String
    let ranges: [ReportTimeRange]
    @ObservedObject var preferences: ReportingPreferences
    let onSelect: (ReportTimeRange) -> Void

    var body: some View {
        Text(title)
            .font(.subheadline.weight(.medium))
            .padding(.top, 8)
        ForEach(ranges, id: \.rawValue) { range in
            HStack {
                Text(range.badge)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 34, alignment: .leading)
                Text(range.title)
                Spacer()
                if !range.isSupported {
                    Text("Not available")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                } else if preferences.timeRange == range {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Color.accentColor)
                }
            }
            .opacity(range.isSupported ? 1 : 0.45)
            .contentShape(Rectangle())
            .onTapGesture { onSelect(range) }
        }
    }
}

@MainActor
private struct SettingsSection<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(title)
                    .font(.largeTitle.weight(.semibold))
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                content()
            }
            .padding(28)
            .frame(maxWidth: 700, alignment: .leading)
        }
    }
}

@MainActor
private struct SettingsCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Text(title)
                    .font(.headline)
                content()
            }
            .padding(6)
        }
    }
}
