import SwiftUI

@MainActor
public struct SettingsView: View {
    @ObservedObject private var model: CostMonitorModel
    @Environment(\.dismiss) private var dismiss
    @State private var key = ""
    @State private var errorMessage: String?

    public init(model: CostMonitorModel) {
        self.model = model
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("OpenRouter Setup")
                .font(.headline)
            Text("Create a management API key with activity access in OpenRouter Settings → Management Keys. A regular inference key cannot read account activity.")
                .font(.callout)
                .foregroundStyle(.secondary)
            SecureField("Management API key", text: $key)
                .textFieldStyle(.roundedBorder)
            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Button("Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 390)
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
