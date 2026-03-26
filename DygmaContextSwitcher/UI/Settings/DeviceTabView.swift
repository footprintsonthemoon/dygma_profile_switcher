import SwiftUI

struct DeviceTabView: View {
    @EnvironmentObject var profileSwitcher: ProfileSwitcher
    @EnvironmentObject var configStore: ConfigStore

    @State private var probeResult: String? = nil
    @State private var isProbing = false

    private var config: Binding<AppConfig> {
        Binding(
            get: { configStore.config },
            set: { try? configStore.save($0) }
        )
    }

    var body: some View {
        Form {
            Section("Auto-Detect") {
                Toggle("Auto-detect Dygma Defy", isOn: config.device.autoDetect)

                if !configStore.config.device.autoDetect {
                    LabeledContent("Port Path") {
                        TextField("/dev/cu.usbmodem…",
                                  text: Binding(
                                    get: { configStore.config.device.serial.portPath ?? "" },
                                    set: { val in
                                        var updated = configStore.config
                                        updated.device.serial.portPath = val.isEmpty ? nil : val
                                        try? configStore.save(updated)
                                    }
                                  ))
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                    }
                }

                HStack {
                    Button(isProbing ? "Probing…" : "Re-detect Keyboard") {
                        triggerProbe()
                    }
                    .disabled(isProbing)

                    if let result = probeResult {
                        Text(result)
                            .font(.caption)
                            .foregroundStyle(result.contains("✓") ? .green : .red)
                    }
                }

                if let port = configStore.config.device.serial.portPath {
                    LabeledContent("Detected Port") {
                        Text(port)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private func triggerProbe() {
        isProbing = true
        probeResult = nil
        Task {
            await profileSwitcher.triggerRediscovery()
            await MainActor.run {
                isProbing = false
                if let port = configStore.config.device.serial.portPath {
                    probeResult = "✓ Found: \(port)"
                } else {
                    probeResult = "✗ Not found"
                }
            }
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            await MainActor.run { probeResult = nil }
        }
    }
}
