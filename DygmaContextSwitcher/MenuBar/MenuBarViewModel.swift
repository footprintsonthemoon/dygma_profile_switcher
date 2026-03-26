import AppKit
import Combine
import Foundation
import ServiceManagement

/// Drives the menu bar icon and menu item state from RuntimeState.
@MainActor
final class MenuBarViewModel: ObservableObject {

    @Published private(set) var iconImageName: String = "menubar-on"
    @Published private(set) var isEnabled: Bool = true
    @Published private(set) var statusLines: [String] = []
    @Published private(set) var isStartAtLoginEnabled: Bool = false

    private var cancellables = Set<AnyCancellable>()

    init(profileSwitcher: ProfileSwitcher) {
        profileSwitcher.$runtimeState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.update(from: state)
            }
            .store(in: &cancellables)

        refreshLoginItemStatus()
    }

    // MARK: - State Mapping

    private func update(from state: RuntimeState) {
        isEnabled = state.isEnabled
        iconImageName = iconName(for: state)
        statusLines = buildStatusLines(from: state)
    }

    private func iconName(for state: RuntimeState) -> String {
        guard state.isEnabled else { return "menubar-off" }
        switch state.connectionStatus {
        case .connected:    return "menubar-on"
        case .portBusy, .error:  return "menubar-error"
        case .disconnected: return "menubar-error"
        }
    }

    private func buildStatusLines(from state: RuntimeState) -> [String] {
        var lines: [String] = []
        lines.append("Port: \(state.portPath ?? "Not connected")")
        if let app = state.lastActiveAppDisplayName {
            lines.append("Last app: \(app)")
        }
        if let layer = state.lastAppliedLayer {
            lines.append("Last layer: \(layer)")
        }
        lines.append(state.connectionStatus.displayString)
        return lines
    }

    // MARK: - Login Item

    func refreshLoginItemStatus() {
        isStartAtLoginEnabled = SMAppService.mainApp.status == .enabled
    }
}
