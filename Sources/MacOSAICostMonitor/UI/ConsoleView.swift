import AppKit
import SwiftUI

@MainActor
public struct ConsoleView: View {
    @ObservedObject private var logStore: AppLogStore
    private let model: CostMonitorModel?
    @State private var search = ""
    @State private var selectedLevel: LogLevel? = nil
    @State private var exportMessage: String?

    public init(logStore: AppLogStore, model: CostMonitorModel? = nil) {
        self.logStore = logStore
        self.model = model
    }

    private var filteredEntries: [LogEntry] {
        logStore.entries.filter { entry in
            let levelMatches = selectedLevel == nil || entry.level == selectedLevel
            let searchMatches = search.isEmpty || entry.message.localizedCaseInsensitiveContains(search)
            return levelMatches && searchMatches
        }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Text("Console")
                    .font(.largeTitle.weight(.semibold))
                Spacer()
                TextField("Filter logs", text: $search)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 180)
                Picker("Level", selection: $selectedLevel) {
                    Text("All levels").tag(LogLevel?.none)
                    ForEach(LogLevel.allCases) { level in
                        Text(level.title).tag(Optional(level))
                    }
                }
                .frame(width: 130)
                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(
                        AppLogStore.redactForExport(logStore.text(for: filteredEntries)),
                        forType: .string
                    )
                }
                .disabled(filteredEntries.isEmpty)
                Button("Clear") { logStore.clear() }
                    .disabled(logStore.entries.isEmpty)
                if let model {
                    Button("Export") {
                        do {
                            let url = try model.exportLogs()
                            exportMessage = url.path
                            NSWorkspace.shared.activateFileViewerSelecting([url])
                        } catch {
                            exportMessage = "Export failed"
                        }
                    }
                    .disabled(logStore.entries.isEmpty)
                }
            }
            .padding(.bottom, 14)

            if filteredEntries.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "terminal")
                        .font(.title2)
                    Text("No diagnostic entries")
                        .font(.headline)
                    Text("Refresh activity or change the filter. Logs contain metadata only and never include API keys or response bodies.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 420)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 4) {
                            ForEach(filteredEntries) { entry in
                                ConsoleRow(entry: entry)
                                    .id(entry.id)
                            }
                        }
                        .padding(14)
                    }
                    .background(Color(nsColor: .textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .onChange(of: logStore.entries.count) { _ in
                        if let last = filteredEntries.last {
                            withAnimation(.easeOut(duration: 0.15)) {
                                proxy.scrollTo(last.id, anchor: .bottom)
                            }
                        }
                    }
                }
            }

            Text("Showing \(filteredEntries.count) of \(logStore.entries.count) entries · metadata only · max \(AppLogStore.defaultCapacity)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 8)
            if let exportMessage {
                Text(exportMessage)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
        .padding(28)
    }
}

@MainActor
private struct ConsoleRow: View {
    let entry: LogEntry

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(entry.level.title.uppercased())
                .font(.caption2.weight(.bold).monospaced())
                .foregroundStyle(color)
                .frame(width: 62, alignment: .leading)
            Text(entry.line)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(entry.line)
    }

    private var color: Color {
        switch entry.level {
        case .debug: return .secondary
        case .info: return .blue
        case .warning: return .orange
        case .error: return .red
        }
    }
}
