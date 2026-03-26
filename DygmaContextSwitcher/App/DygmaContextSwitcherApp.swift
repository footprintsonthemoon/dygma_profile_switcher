import SwiftUI
import AppKit

@main
struct DygmaContextSwitcherApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // No windows — this is a menu bar only app.
        // LSUIElement=YES in Info.plist hides the Dock icon.
        Settings {
            EmptyView()
        }
    }
}
