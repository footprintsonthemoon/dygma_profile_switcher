import AppKit
import SwiftUI

struct AppInfo: Identifiable {
    let id: String          // bundle identifier
    let displayName: String
    let icon: NSImage
}

/// Provides running apps list and NSOpenPanel-based installed app browsing.
/// No manual text entry — bundle ID and display name are captured automatically.
@MainActor
final class AppPickerViewModel: ObservableObject {

    @Published private(set) var apps: [AppInfo] = []
    @Published private(set) var isLoading = false

    // MARK: - Running Apps

    func loadRunningApps() {
        isLoading = true
        DispatchQueue.global(qos: .userInitiated).async {
            let running = NSWorkspace.shared.runningApplications
                .compactMap { app -> AppInfo? in
                    guard
                        let bundleId = app.bundleIdentifier,
                        let name = app.localizedName,
                        app.activationPolicy == .regular   // skip background-only processes
                    else { return nil }
                    let icon = app.icon ?? NSImage(systemSymbolName: "app.fill",
                                                   accessibilityDescription: nil)!
                    return AppInfo(id: bundleId, displayName: name, icon: icon)
                }
                .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }

            DispatchQueue.main.async {
                self.apps = running
                self.isLoading = false
            }
        }
    }

    // MARK: - Browse Installed Apps (NSOpenPanel)

    /// Opens an NSOpenPanel filtered to .app bundles.
    /// Calls `onSelect` with (bundleIdentifier, displayName) on success.
    func browseInstalledApp(onSelect: @escaping (String, String) -> Void) {
        let panel = NSOpenPanel()
        panel.title = "Choose an Application"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.applicationBundle]
        panel.directoryURL = FileManager.default
            .urls(for: .applicationDirectory, in: .localDomainMask).first

        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            guard let bundle = Bundle(url: url),
                  let bundleId = bundle.bundleIdentifier else { return }
            let name = bundle.infoDictionary?["CFBundleDisplayName"] as? String
                    ?? bundle.infoDictionary?["CFBundleName"] as? String
                    ?? url.deletingPathExtension().lastPathComponent
            onSelect(bundleId, name)
        }
    }
}
