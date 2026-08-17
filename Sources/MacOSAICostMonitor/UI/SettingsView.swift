import SwiftUI

@MainActor
public struct SettingsView: View {
    @ObservedObject private var model: CostMonitorModel
    @ObservedObject private var preferences: ReportingPreferences
    @Environment(\.dismiss) private var dismiss
    @State private var key = ""
    @State private var errorMessage: String?

    public init(model: CostMonitorModel) {
        self.model = model
        self.preferences = model.preferences
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Provider settings")
                .font(.title3.weight(.semibold))

            GroupBox("Connection") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Use a management API key with activity access. The key is stored in macOS Keychain.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    SecureField("Management API key", text: $key)
                        .textFieldStyle(.roundedBorder)
                }
                .padding(4)
            }

            GroupBox("Report") {
                VStack(alignment: .leading, spacing: 10) {
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
                    Text("OpenRouter reports activity by completed UTC day. The local timezone is not used to redefine the API date.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(4)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Button("Save key") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 440)
        .onChange(of: preferences.reportRange) { _ in model.applyPreferenceChanges() }
        .onChange(of: preferences.decimalPlaces) { _ in model.applyPreferenceChanges() }
        .onChange(of: preferences.refreshInterval) { _ in model.applyPreferenceChanges() }
        .onChange(of: preferences.includeByokInHeadline) { _ in model.applyPreferenceChanges() }
    }

    private func save() {
        Task {
            do {
                try await model.saveManagementKey(key)
                key = ""
                dismiss()
            } catch {
                errorMessage = "The key could not be saved to Keychain."
            }
        }
    }
}
