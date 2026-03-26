import Foundation
import Combine

/// Connection status for the menu bar icon and status display.
enum ConnectionStatus: Equatable {
    case connected
    case disconnected
    case portBusy
    case error(String)

    var displayString: String {
        switch self {
        case .connected:            return "Connected"
        case .disconnected:         return "Disconnected"
        case .portBusy:             return "Port in use — is Bazecor open?"
        case .error(let msg):       return "Error: \(msg)"
        }
    }
}

/// Transient runtime state (not persisted).
struct RuntimeState {
    var isEnabled: Bool = false
    var connectionStatus: ConnectionStatus = .disconnected
    var portPath: String? = nil
    var lastActiveAppDisplayName: String? = nil
    var lastActiveAppBundleId: String? = nil
    var lastAppliedLayer: Int? = nil
    // Resolved profile for the current app (populated on every activation)
    var lastActiveIsMapped: Bool = false
    var lastActiveResolvedLayer: Int? = nil
    var lastActiveResolvedBrightness: Int? = nil
}

/// Main orchestrator: bridges AppEventMonitor → MappingLookup → FocusAPIClient.
@MainActor
final class ProfileSwitcher: ObservableObject {

    @Published private(set) var runtimeState = RuntimeState()

    let focusClient: FocusAPIClient
    private let configStore: ConfigStore
    private let lookup = MappingLookup()
    private let monitor: AppEventMonitor
    private var deviceDiscovery: DeviceDiscovery?

    // Backoff state
    private var backoffTask: Task<Void, Never>?
    private static let backoffSequence = [1, 2, 4, 8, 16, 30]

    init(configStore: ConfigStore) {
        self.configStore = configStore
        self.focusClient = FocusAPIClient()
        self.monitor = AppEventMonitor(debounceMsProvider: {
            configStore.config.defaults.debounceMs
        })
        self.monitor.onAppActivated = { [weak self] (bundleId, displayName) in
            Task { await self?.handleAppActivated(bundleId: bundleId, displayName: displayName) }
        }
        // Wire device discovery
        let discovery = DeviceDiscovery(focusClient: self.focusClient)
        self.deviceDiscovery = discovery
        discovery.onDeviceAttached = { [weak self] in
            Task { await self?.handleDeviceAttached() }
        }
        discovery.onDeviceDetached = { [weak self] in
            Task { await self?.handleDeviceDetached() }
        }
    }

    // MARK: - Enable / Disable

    func setEnabled(_ enabled: Bool) async {
        runtimeState.isEnabled = enabled

        // Persist to config
        var updated = configStore.config
        updated.runtime.enabled = enabled
        try? configStore.save(updated)

        if enabled {
            deviceDiscovery?.startMonitoring()
            monitor.start()
            await connectIfNeeded()
        } else {
            monitor.stop()
            backoffTask?.cancel()
            if configStore.config.runtime.closePortWhenDisabled {
                await focusClient.disconnect()
                runtimeState.connectionStatus = .disconnected
                runtimeState.portPath = nil
            }
            runtimeState.isEnabled = false
            AppLogger.shared.log("Switching disabled", level: .info)
        }
    }

    // MARK: - App Activation

    func handleAppActivated(bundleId: String, displayName: String) async {
        guard runtimeState.isEnabled, runtimeState.connectionStatus == .connected else { return }

        runtimeState.lastActiveAppBundleId = bundleId
        runtimeState.lastActiveAppDisplayName = displayName

        let resolved = lookup.resolve(
            bundleId: bundleId,
            mappings: configStore.config.mappings,
            defaults: configStore.config.defaults
        )

        let activeMapping = configStore.config.mappings.first { $0.bundleIdentifier == bundleId }
        runtimeState.lastActiveIsMapped = activeMapping != nil
        runtimeState.lastActiveResolvedLayer = resolved.layer
        runtimeState.lastActiveResolvedBrightness = resolved.ledBrightness

        AppLogger.shared.log("App activated: \(displayName) (\(bundleId))", level: .debug)

        do {
            if let layer = resolved.layer, !resolved.layerAlreadyActive {
                try await focusClient.moveToLayer(layer)
                lookup.recordApplied(layer: layer)
                runtimeState.lastAppliedLayer = layer
            }
            if let brightness = resolved.ledBrightness {
                try await focusClient.setBrightness(brightness)
            }
            if let theme = resolved.ledTheme {
                try await focusClient.setTheme(theme)
            }
        } catch {
            AppLogger.shared.log("Apply failed for \(bundleId): \(error.localizedDescription)", level: .warning)
            await startBackoff()
        }
    }

    // MARK: - Connection

    func connectIfNeeded() async {
        guard runtimeState.connectionStatus != .connected else { return }

        let config = configStore.config
        if config.device.autoDetect {
            await triggerRediscovery()
        } else if let path = config.device.serial.portPath {
            await attemptConnect(portPath: path)
        } else {
            runtimeState.connectionStatus = .disconnected
        }
    }

    func triggerRediscovery() async {
        guard let discovery = deviceDiscovery else { return }
        AppLogger.shared.log("Starting device discovery…", level: .info)
        if let path = await discovery.discoverDevice(baudRate: configStore.config.device.serial.baudRate) {
            await attemptConnect(portPath: path)
        } else {
            runtimeState.connectionStatus = .disconnected
            AppLogger.shared.log("No Dygma Defy found during discovery", level: .warning)
        }
    }

    private func attemptConnect(portPath: String) async {
        do {
            try await focusClient.connect(portPath: portPath, baudRate: configStore.config.device.serial.baudRate)
            runtimeState.connectionStatus = .connected
            runtimeState.portPath = portPath
            lookup.resetCache()
            backoffTask?.cancel()
            // Cache port in config
            var updated = configStore.config
            updated.device.serial.portPath = portPath
            try? configStore.save(updated)
            AppLogger.shared.log("Connected to \(portPath)", level: .info)
        } catch SerialPortError.portBusy(let path) {
            runtimeState.connectionStatus = .portBusy
            runtimeState.portPath = path
            AppLogger.shared.log("Port busy: \(path)", level: .warning)
            await startBackoff()
        } catch {
            runtimeState.connectionStatus = .error(error.localizedDescription)
            AppLogger.shared.log("Connect error: \(error.localizedDescription)", level: .error)
            await startBackoff()
        }
    }

    // MARK: - Backoff

    private func startBackoff() async {
        backoffTask?.cancel()
        backoffTask = Task { [weak self] in
            for delay in Self.backoffSequence {
                try? await Task.sleep(nanoseconds: UInt64(delay) * 1_000_000_000)
                guard let self, !Task.isCancelled else { return }
                await self.connectIfNeeded()
                if self.runtimeState.connectionStatus == .connected { return }
            }
            AppLogger.shared.log("Backoff exhausted — settled in disconnected state", level: .warning)
        }
    }

    // MARK: - Hotplug Callbacks

    func handleDeviceAttached() async {
        guard runtimeState.isEnabled else { return }
        AppLogger.shared.log("USB device attached — attempting reconnect", level: .info)
        backoffTask?.cancel()
        await connectIfNeeded()
    }

    func handleDeviceDetached() async {
        AppLogger.shared.log("USB device detached", level: .info)
        await focusClient.disconnect()
        runtimeState.connectionStatus = .disconnected
        runtimeState.portPath = nil
        if runtimeState.isEnabled { await startBackoff() }
    }

    // MARK: - Config Reload

    func reloadConfig() {
        configStore.load()
        lookup.resetCache()
    }
}
