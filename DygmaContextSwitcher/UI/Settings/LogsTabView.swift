import SwiftUI
import AppKit

struct LogsTabView: View {
    @ObservedObject var logger = AppLogger.shared

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(logger.recentLines.enumerated()), id: \.offset) { _, line in
                            Text(line)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(lineColor(for: line))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        Color.clear.frame(height: 1).id("bottom")
                    }
                    .padding(8)
                }
                .onChange(of: logger.recentLines.count, perform: { _ in
                    proxy.scrollTo("bottom")
                })
            }

            Divider()

            HStack {
                Text("\(logger.recentLines.count) lines")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Export…") { exportLogs() }
                    .controlSize(.small)
            }
            .padding(10)
        }
    }

    private func lineColor(for line: String) -> Color {
        if line.contains("[ERROR]")   { return .red }
        if line.contains("[WARNING]") { return .orange }
        if line.contains("[DEBUG]")   { return .gray }
        return .primary
    }

    private func exportLogs() {
        let exportURL = logger.export()
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "dygma-context-export.log"
        panel.begin { response in
            guard response == .OK, let dest = panel.url else { return }
            try? FileManager.default.copyItem(at: exportURL, to: dest)
        }
    }
}
