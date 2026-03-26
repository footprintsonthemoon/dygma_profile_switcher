import AppKit
import ServiceManagement
import Foundation

/// Owns the NSStatusItem and NSMenu. Observes MenuBarViewModel for state changes.
@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {

    private let statusItem: NSStatusItem
    private let viewModel: MenuBarViewModel
    private let profileSwitcher: ProfileSwitcher
    private let configStore: ConfigStore

    // Menu items that need dynamic state
    private var enabledItem: NSMenuItem!
    private var startAtLoginItem: NSMenuItem!
    private var statusMenu: NSMenu!

    private var viewModelObservation: Any?

    // MARK: - Init

    init(profileSwitcher: ProfileSwitcher, configStore: ConfigStore) {
        self.profileSwitcher = profileSwitcher
        self.configStore = configStore
        self.viewModel = MenuBarViewModel(profileSwitcher: profileSwitcher)
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        buildMenu()
        updateIcon()
        observeViewModel()
    }

    // MARK: - Menu Construction

    private func buildMenu() {
        let menu = NSMenu()
        menu.delegate = self

        // Enabled toggle
        enabledItem = NSMenuItem(title: "Enabled",
                                 action: #selector(toggleEnabled),
                                 keyEquivalent: "")
        enabledItem.target = self
        enabledItem.state = configStore.config.runtime.enabled ? .on : .off
        menu.addItem(enabledItem)

        menu.addItem(.separator())

        // Open Settings
        let settingsItem = NSMenuItem(title: "Open Settings…",
                                      action: #selector(openSettings),
                                      keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        // Re-detect
        let redetectItem = NSMenuItem(title: "Re-detect Keyboard",
                                      action: #selector(redetectKeyboard),
                                      keyEquivalent: "")
        redetectItem.target = self
        menu.addItem(redetectItem)

        menu.addItem(.separator())

        // Status submenu
        let statusParent = NSMenuItem(title: "Status", action: nil, keyEquivalent: "")
        statusMenu = NSMenu()
        statusMenu.autoenablesItems = false
        statusParent.submenu = statusMenu
        menu.addItem(statusParent)

        menu.addItem(.separator())

        // Start at Login
        startAtLoginItem = NSMenuItem(title: "Start at Login",
                                      action: #selector(toggleStartAtLogin),
                                      keyEquivalent: "")
        startAtLoginItem.target = self
        menu.addItem(startAtLoginItem)

        // Open Logs
        let logsItem = NSMenuItem(title: "Open Logs…",
                                  action: #selector(openLogs),
                                  keyEquivalent: "")
        logsItem.target = self
        menu.addItem(logsItem)

        menu.addItem(.separator())

        // Quit
        let quitItem = NSMenuItem(title: "Quit DygmaContext",
                                  action: #selector(NSApplication.terminate(_:)),
                                  keyEquivalent: "q")
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    // MARK: - NSMenuDelegate

    func menuWillOpen(_ menu: NSMenu) {
        viewModel.refreshLoginItemStatus()
        enabledItem.state = viewModel.isEnabled ? .on : .off
        startAtLoginItem.state = viewModel.isStartAtLoginEnabled ? .on : .off
        rebuildStatusSubmenu()
    }

    private func rebuildStatusSubmenu() {
        statusMenu.removeAllItems()
        for line in viewModel.statusLines {
            let item = NSMenuItem(title: line, action: nil, keyEquivalent: "")
            statusMenu.addItem(item)
        }
    }

    // MARK: - Icon Updates

    private func observeViewModel() {
        viewModelObservation = NotificationCenter.default.addObserver(
            forName: .init("MenuBarViewModelDidUpdate"),
            object: nil,
            queue: .main
        ) { [weak self] _ in self?.updateIcon() }

        // Observe via Combine on the published iconImageName
        Task { [weak self] in
            guard let self else { return }
            for await name in self.viewModel.$iconImageName.values {
                self.setIcon(name)
            }
        }
    }

    private func updateIcon() {
        setIcon(viewModel.iconImageName)
    }

    private func setIcon(_ name: String) {
        guard let button = statusItem.button else { return }

        // Template image — adapts automatically to light/dark menu bar
        let symbolName = (name == "menubar-error") ? "keyboard.badge.ellipsis" : "keyboard"
        let img = NSImage(named: name) ?? NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)
        img?.isTemplate = true
        button.image = img
        button.alphaValue = (name == "menubar-off") ? 0.4 : 1.0

        // Colored status dot shown as a small character to the right of the icon
        switch name {
        case "menubar-on":
            button.attributedTitle = statusDot(color: .systemGreen)
        case "menubar-error":
            button.attributedTitle = statusDot(color: .systemOrange)
        default:
            button.attributedTitle = NSAttributedString(string: "")
        }
    }

    private func statusDot(color: NSColor) -> NSAttributedString {
        NSAttributedString(string: "●", attributes: [
            .foregroundColor: color,
            .font: NSFont.systemFont(ofSize: 7)
        ])
    }

    // MARK: - Actions

    @objc private func toggleEnabled() {
        let newState = !viewModel.isEnabled
        enabledItem.state = newState ? .on : .off
        Task { await profileSwitcher.setEnabled(newState) }
    }

    @objc private func openSettings() {
        SettingsWindowManager.shared.showSettings()
    }

    @objc private func redetectKeyboard() {
        Task { await profileSwitcher.triggerRediscovery() }
    }

    @objc private func toggleStartAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            // .requiresApproval: open System Settings
            if let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") {
                NSWorkspace.shared.open(url)
            }
            AppLogger.shared.log("Login item toggle error: \(error.localizedDescription)", level: .warning)
        }
        viewModel.refreshLoginItemStatus()
        startAtLoginItem.state = viewModel.isStartAtLoginEnabled ? .on : .off
    }

    @objc private func openLogs() {
        let url = AppLogger.shared.logDirectoryURL
        NSWorkspace.shared.open(url)
    }
}
