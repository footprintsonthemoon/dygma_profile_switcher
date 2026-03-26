import Foundation

/// High-level Focus API client.
/// Sends Focus protocol commands via SerialPortActor.
/// Only sends commands for explicitly configured fields (non-destructive partial apply).
@MainActor
final class FocusAPIClient: ObservableObject {

    private let actor = SerialPortActor()
    private(set) var portPath: String?

    // MARK: - Connection

    func connect(portPath: String, baudRate: Int = 115_200) async throws {
        try await actor.connect(portPath: portPath, baudRate: baudRate)
        self.portPath = portPath
        AppLogger.shared.log("FocusAPIClient connected to \(portPath)", level: .info)
    }

    func disconnect() async {
        await actor.disconnect()
        portPath = nil
        AppLogger.shared.log("FocusAPIClient disconnected", level: .info)
    }

    var isConnected: Bool {
        get async { await actor.isConnected }
    }

    // MARK: - Device Probe

    /// Sends `help` and returns true if response includes Focus API signatures.
    func probe() async throws -> Bool {
        let response = try await sendRaw("version")
        let nonEmpty = !response.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        AppLogger.shared.log("Probe version response: \"\(response.prefix(80))\" match=\(nonEmpty)", level: .info)
        return nonEmpty
    }

    // MARK: - Layer

    func moveToLayer(_ index: Int) async throws {
        AppLogger.shared.log("layer.moveTo \(index)", level: .debug)
        let response = try await sendRaw("layer.moveTo \(index)")
        checkError(response, command: "layer.moveTo \(index)")
    }

    // MARK: - LED

    func setBrightness(_ value: Int) async throws {
        AppLogger.shared.log("led.brightness \(value)", level: .debug)
        let response = try await sendRaw("led.brightness \(value)")
        checkError(response, command: "led.brightness \(value)")
    }

    func setTheme(_ name: String) async throws {
        AppLogger.shared.log("led.theme \(name)", level: .debug)
        let response = try await sendRaw("led.theme \(name)")
        checkError(response, command: "led.theme \(name)")
    }

    // MARK: - Partial Profile Apply

    /// Applies only the non-nil fields of a profile (non-destructive).
    func applyProfile(_ profile: MappingProfile) async throws {
        if let layer = profile.layer       { try await moveToLayer(layer) }
        if let brightness = profile.ledBrightness { try await setBrightness(brightness) }
        if let theme = profile.ledTheme    { try await setTheme(theme) }
    }

    // MARK: - Internal

    private func sendRaw(_ command: String) async throws -> String {
        try await actor.sendCommand(command)
    }

    private func checkError(_ response: String, command: String) {
        if response.hasPrefix("ERR_") {
            AppLogger.shared.log("Command '\(command)' returned: \(response)", level: .warning)
        }
    }
}
