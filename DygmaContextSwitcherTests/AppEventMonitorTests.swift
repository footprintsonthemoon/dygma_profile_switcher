import XCTest
@testable import DygmaContextSwitcher

final class AppEventMonitorTests: XCTestCase {

    func testDebounceOnlyFinalEventTriggersCallback() {
        let monitor = AppEventMonitor(debounceMsProvider: { 50 })
        var callCount = 0
        var lastBundleId: String?
        monitor.onAppActivated = { bundleId, _ in
            callCount += 1
            lastBundleId = bundleId
        }
        monitor.start()

        // Simulate rapid events via the notification (we post synthetic notifications)
        let center = NSWorkspace.shared.notificationCenter
        let fakeApp1 = FakeRunningApplication(bundleId: "com.app.one", name: "App One")
        let fakeApp2 = FakeRunningApplication(bundleId: "com.app.two", name: "App Two")
        let fakeApp3 = FakeRunningApplication(bundleId: "com.app.three", name: "App Three")

        for app in [fakeApp1, fakeApp2, fakeApp3] {
            center.post(
                name: NSWorkspace.didActivateApplicationNotification,
                object: NSWorkspace.shared,
                userInfo: [NSWorkspace.applicationUserInfoKey: app]
            )
        }

        // Wait for debounce to expire
        let exp = expectation(description: "debounce fires")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1.0)

        XCTAssertEqual(callCount, 1, "Debounce should produce exactly one callback")
        XCTAssertEqual(lastBundleId, "com.app.three", "Last app in rapid sequence should be applied")

        monitor.stop()
    }

    func testSingleEventAfterDebounceTriggersCallback() {
        let monitor = AppEventMonitor(debounceMsProvider: { 50 })
        var callCount = 0
        monitor.onAppActivated = { _, _ in callCount += 1 }
        monitor.start()

        let fakeApp = FakeRunningApplication(bundleId: "com.single.app", name: "Single")
        NSWorkspace.shared.notificationCenter.post(
            name: NSWorkspace.didActivateApplicationNotification,
            object: NSWorkspace.shared,
            userInfo: [NSWorkspace.applicationUserInfoKey: fakeApp]
        )

        let exp = expectation(description: "single event fires")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { exp.fulfill() }
        wait(for: [exp], timeout: 1.0)

        XCTAssertEqual(callCount, 1)
        monitor.stop()
    }
}

// MARK: - Test Helper

/// Minimal NSRunningApplication substitute for injecting into notifications.
/// NSRunningApplication cannot be subclassed directly, so we use NSObject + dynamic casting path.
private class FakeRunningApplication: NSObject {
    @objc let bundleIdentifier: String?
    @objc let localizedName: String?

    init(bundleId: String, name: String) {
        self.bundleIdentifier = bundleId
        self.localizedName = name
    }
}
