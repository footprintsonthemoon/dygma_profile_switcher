import AppKit
import Foundation

final class AppDelegate: NSObject, NSApplicationDelegate {

    // MARK: - Core Components (wired incrementally as phases complete)

    private(set) var configStore: ConfigStore = .shared
    private(set) var profileSwitcher: ProfileSwitcher?
    private(set) var menuBarController: MenuBarController?

    // MARK: - Launch

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Suppress Dock icon at runtime (belt-and-suspenders with LSUIElement plist key)
        NSApp.setActivationPolicy(.accessory)

        // Configure logger first
        configStore.load()
        AppLogger.shared.configure(level: configStore.config.logging.level)
        AppLogger.shared.log("DygmaContextSwitcher starting", level: .info)

        // Wire core components
        let switcher = ProfileSwitcher(configStore: configStore)
        self.profileSwitcher = switcher

        let menuBar = MenuBarController(profileSwitcher: switcher, configStore: configStore)
        self.menuBarController = menuBar

        // Give SettingsWindowManager the real instances
        SettingsWindowManager.shared.profileSwitcher = switcher
        SettingsWindowManager.shared.configStore = configStore

        // Start switching if enabled in config — brief delay lets USB stack settle
        Task {
            try? await Task.sleep(nanoseconds: 500_000_000)
            await switcher.setEnabled(configStore.config.runtime.enabled)
        }

        // Show settings on first launch
        if configStore.isFirstLaunch {
            SettingsWindowManager.shared.showSettings()
        }

        AppLogger.shared.log("Startup complete — enabled: \(configStore.config.runtime.enabled)", level: .info)
    }

    func applicationWillTerminate(_ notification: Notification) {
        // No keyboard state change on quit (by design — every layer has navigation shortcuts).
        AppLogger.shared.log("DygmaContextSwitcher terminating", level: .info)
    }
}
