import SwiftUI

@MainActor
public struct SettingsRootView: View {
    public enum Section: String, CaseIterable, Identifiable, Hashable {
        case general
        case openRouter
        case reporting
        case console

        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .general: return "General"
            case .openRouter: return "OpenRouter"
            case .reporting: return "Reporting"
            case .console: return "Console"
            }
        }

        public var icon: String {
            switch self {
            case .general: return "gearshape"
            case .openRouter: return "key"
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
        case .openRouter:
            OpenRouterSettingsSection(model: model)
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
                LabeledContent("Provider", value: "OpenRouter")
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
private struct OpenRouterSettingsSection: View {
    @ObservedObject var model: CostMonitorModel
    @State private var key = ""
    @State private var errorMessage: String?

    var body: some View {
        SettingsSection(title: "OpenRouter", subtitle: "Secure management-key configuration.") {
            SettingsCard(title: "Management key") {
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

    var body: some View {
        SettingsSection(title: "Reporting", subtitle: "Control the report range, cadence, precision, and headline composition.") {
            SettingsCard(title: "Report range") {
                Picker("Range", selection: $preferences.reportRange) {
                    ForEach(ReportRange.allCases) { range in
                        Text(range.title).tag(range)
                    }
                }
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
                Text("OpenRouter reports completed UTC-day buckets. The local timezone cannot redefine those API buckets into exact local-day totals.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .onChange(of: preferences.reportRange) { _ in model.applyPreferenceChanges() }
            .onChange(of: preferences.decimalPlaces) { _ in model.applyPreferenceChanges() }
            .onChange(of: preferences.refreshInterval) { _ in model.applyPreferenceChanges() }
            .onChange(of: preferences.includeByokInHeadline) { _ in model.applyPreferenceChanges() }
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
