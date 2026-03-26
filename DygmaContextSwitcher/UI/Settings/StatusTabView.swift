import SwiftUI
import Combine

struct StatusTabView: View {
    @EnvironmentObject var profileSwitcher: ProfileSwitcher

    var body: some View {
        Form {
            Section("Connection") {
                LabeledContent("Status") {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(statusColor)
                            .frame(width: 10, height: 10)
                        Text(profileSwitcher.runtimeState.connectionStatus.displayString)
                            .foregroundStyle(.secondary)
                    }
                }

                LabeledContent("Port") {
                    Text(profileSwitcher.runtimeState.portPath ?? "—")
                        .foregroundStyle(.secondary)
                }

            }

            Section("Active App") {
                LabeledContent("App") {
                    Text(profileSwitcher.runtimeState.lastActiveAppDisplayName ?? "—")
                        .foregroundStyle(.secondary)
                }

                LabeledContent("Bundle ID") {
                    Text(profileSwitcher.runtimeState.lastActiveAppBundleId ?? "—")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                LabeledContent("Profile") {
                    Text(profileSwitcher.runtimeState.lastActiveIsMapped ? "Custom mapping" : "Default")
                        .foregroundStyle(profileSwitcher.runtimeState.lastActiveIsMapped ? .primary : .secondary)
                }

                LabeledContent("Layer") {
                    Text(profileSwitcher.runtimeState.lastActiveResolvedLayer.map { "Layer \($0 + 1)" } ?? "—")
                        .foregroundStyle(.secondary)
                }

                LabeledContent("Brightness") {
                    Text(profileSwitcher.runtimeState.lastActiveResolvedBrightness.map { "\($0)" } ?? "—")
                        .foregroundStyle(.secondary)
                }

            }
        }
        .formStyle(.grouped)
        .padding()
        // Belt-and-suspenders: force re-render on every runtimeState change
        .onReceive(profileSwitcher.objectWillChange) { _ in }
    }

    private var statusColor: Color {
        switch profileSwitcher.runtimeState.connectionStatus {
        case .connected:    return .green
        case .disconnected: return .gray
        case .portBusy:     return .orange
        case .error:        return .red
        }
    }
}
