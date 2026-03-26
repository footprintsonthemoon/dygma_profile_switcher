import AppKit
import SwiftUI

/// Manages a singleton NSWindow hosting the SwiftUI SettingsView.
/// Calling showSettings() brings the existing window to front, or creates it fresh.
@MainActor
final class SettingsWindowManager {

    static let shared = SettingsWindowManager()

    // Set once from AppDelegate after the core objects are created
    var profileSwitcher: ProfileSwitcher!
    var configStore: ConfigStore!

    private var window: NSWindow?

    func showSettings() {
        if let existing = window, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        // Always recreate the view so it renders with current state
        window?.close()
        window = nil

        let settingsView = SettingsView()
            .environmentObject(profileSwitcher)
            .environmentObject(configStore)

        let controller = NSHostingController(rootView: settingsView)
        let win = NSWindow(contentViewController: controller)
        win.title = "DygmaContext Settings"
        win.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        win.setFrameAutosaveName("DygmaContextSettingsWindow")
        win.setContentSize(NSSize(width: 680, height: 480))
        win.center()
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = win
    }
}

