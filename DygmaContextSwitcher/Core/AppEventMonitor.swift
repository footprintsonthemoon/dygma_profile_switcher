import AppKit
import Foundation

/// Observes NSWorkspace.didActivateApplicationNotification (event-driven, no polling).
/// Debounces rapid app-switching events using DispatchWorkItem cancel-and-reschedule.
final class AppEventMonitor {

    /// Called after the debounce window with the frontmost app's bundle ID and display name.
    var onAppActivated: ((_ bundleId: String, _ displayName: String) -> Void)?

    private var debounceWorkItem: DispatchWorkItem?
    private var debounceMsProvider: () -> Int

    init(debounceMsProvider: @escaping () -> Int = { 150 }) {
        self.debounceMsProvider = debounceMsProvider
    }

    // MARK: - Start / Stop

    func start() {
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleAppActivation(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
        AppLogger.shared.log("AppEventMonitor started", level: .debug)
    }

    func stop() {
        NSWorkspace.shared.notificationCenter.removeObserver(
            self,
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
        debounceWorkItem?.cancel()
        debounceWorkItem = nil
        AppLogger.shared.log("AppEventMonitor stopped", level: .debug)
    }

    // MARK: - Handler

    @objc private func handleAppActivation(_ notification: Notification) {
        // Extract the activated app from the notification (avoid frontmostApplication race).
        // Uses KVC fallback so test helpers (non-NSRunningApplication objects) also work.
        let bundleId: String?
        let displayName: String?
        let userInfoApp = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
        if let app = userInfoApp as? NSRunningApplication {
            bundleId = app.bundleIdentifier
            displayName = app.localizedName
        } else if let obj = userInfoApp as? NSObject {
            bundleId = obj.value(forKey: "bundleIdentifier") as? String
            displayName = obj.value(forKey: "localizedName") as? String
        } else {
            bundleId = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
            displayName = NSWorkspace.shared.frontmostApplication?.localizedName
        }
        guard let bundleId, let displayName else { return }

        // Cancel any pending debounced work and reschedule
        debounceWorkItem?.cancel()
        let delay = debounceMsProvider()
        let item = DispatchWorkItem { [weak self] in
            self?.onAppActivated?(bundleId, displayName)
        }
        debounceWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(delay), execute: item)
    }

    deinit { stop() }
}
