# Implementation Plan: Dygma Context Switcher for macOS

**Branch**: `001-dygma-context-switcher` | **Date**: 2026-03-16 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/001-dygma-context-switcher/spec.md`

---

## Summary

A native macOS menu bar application (Swift + SwiftUI/AppKit) that automatically switches the active layer on a Dygma Defy keyboard based on which app is in the foreground. The app communicates with the keyboard via USB serial using the Focus API (ORSSerialPort), detects apps by bundle identifier via NSWorkspace notifications, and stores all configuration in a versioned JSON file. No Dock icon; controlled entirely from a menu bar icon with three visual states (on/off/error) and a SwiftUI settings window.

---

## Technical Context

**Language/Version**: Swift 5.9+
**Primary Dependencies**: ORSSerialPort (SPM), AppKit, SwiftUI, IOKit, ServiceManagement
**Storage**: JSON config file — `~/Library/Application Support/DygmaContext/config.json` (atomic writes via `Data.write(options:.atomic)`)
**Testing**: XCTest with protocol-based mocks (no hardware required)
**Target Platform**: macOS 13.0 (Ventura) and later
**Project Type**: macOS desktop app (menu bar agent, no Dock icon)
**Performance Goals**: Layer switch applied within 300ms of app activation; enable/disable toggle within 200ms
**Constraints**: No hardcoded user paths; no Accessibility permission required; exclusive serial port access; no polling; USB only (Focus API does not operate over BT/RF)
**Scale/Scope**: Single-user, single-device, up to ~50 app mappings

---

## Constitution Check

*Constitution file is a blank template — no project-specific gates defined. No violations to evaluate. Proceeding.*

---

## Project Structure

### Documentation (this feature)

```
specs/001-dygma-context-switcher/
├── spec.md              ✓ (spec)
├── plan.md              ✓ (this file)
├── research.md          ✓ (Phase 0)
├── data-model.md        ✓ (Phase 1)
├── quickstart.md        ✓ (Phase 1)
├── contracts/
│   ├── focus-api.md     ✓ (Phase 1)
│   └── config-schema.json ✓ (Phase 1)
├── checklists/
│   └── requirements.md  ✓ (existing)
└── tasks.md             (Phase 2 — /speckit.tasks)
```

### Source Code (repository root)

```
DygmaContextSwitcher/                      # Xcode project root
├── DygmaContextSwitcher.xcodeproj/
├── DygmaContextSwitcher/                  # App target sources
│   ├── App/
│   │   ├── DygmaContextSwitcherApp.swift  # @main entry; sets up AppDelegate + scenes
│   │   ├── AppDelegate.swift              # NSApplicationDelegate; owns MenuBarController
│   │   └── Info.plist                     # LSUIElement=YES; LSMinimumSystemVersion=13.0
│   ├── MenuBar/
│   │   ├── MenuBarController.swift        # NSStatusItem, NSMenu, icon state management
│   │   └── MenuBarViewModel.swift         # @MainActor ObservableObject; bridges RuntimeState → menu
│   ├── Core/
│   │   ├── ProfileSwitcher.swift          # Orchestrator: monitor → lookup → apply
│   │   ├── AppEventMonitor.swift          # NSWorkspace.didActivateApplicationNotification + debounce
│   │   └── MappingLookup.swift            # Bundle ID → MappingProfile lookup + default fallback
│   ├── Serial/
│   │   ├── SerialPortActor.swift          # Swift actor wrapping ORSSerialPort; command/response
│   │   ├── FocusAPIClient.swift           # Focus protocol: commands, response parsing, backoff
│   │   └── DeviceDiscovery.swift          # IOKit enumeration + probe + hotplug notifications
│   ├── Config/
│   │   ├── Configuration.swift            # Codable structs (mirrors data-model.md exactly)
│   │   └── ConfigStore.swift              # Load/save with atomic writes; version migration
│   ├── UI/
│   │   ├── SettingsWindowManager.swift    # NSWindow + NSHostingController singleton
│   │   ├── Settings/
│   │   │   ├── SettingsView.swift         # TabView: Status | Mappings | Device | Logs
│   │   │   ├── StatusTabView.swift        # Connection status, current app, current layer
│   │   │   ├── MappingsTabView.swift      # Mapping list with Test/Delete; Add App button
│   │   │   ├── DeviceTabView.swift        # Mode selector, auto-detect toggle, port, baud
│   │   │   └── LogsTabView.swift          # Last 200 log lines, Export button
│   │   └── AppPicker/
│   │       ├── AppPickerView.swift        # SwiftUI: running apps list + Browse button
│   │       └── AppPickerViewModel.swift   # NSWorkspace.runningApplications + NSOpenPanel
│   └── Logging/
│       └── AppLogger.swift                # Structured file logger; tail buffer for UI
│
├── DygmaContextSwitcherTests/             # Test target
│   ├── ConfigStoreTests.swift             # Load/save roundtrip, version migration, defaults
│   ├── MappingLookupTests.swift           # Bundle ID hit, miss, default fallback, idempotency
│   ├── FocusAPIClientTests.swift          # Command formatting, response parsing, timeout, error
│   ├── AppEventMonitorTests.swift         # Debounce: only final event in window triggers apply
│   └── Mocks/
│       ├── MockSerialPort.swift           # Implements SerialPortProtocol; records writes
│       └── MockDeviceDiscovery.swift      # Simulates connected/disconnected/busy states
│
└── Resources/
    └── Assets.xcassets/                   # App icon + 3 menu bar icon states (SF Symbols)
```

**Structure Decision**: Single Xcode app target with modular source groups. No frameworks or separate targets in v1 — keeps build simple and testable via XCTest without inter-target dependencies. SPM manages ORSSerialPort externally.

---

## Complexity Tracking

No constitution violations. No complexity justification required.

---

## Design Decisions

### D-001: POSIX serial port with DispatchSource (replaces ORSSerialPort actor)
`SerialPortActor` is a `@MainActor` class using POSIX `open()`/`tcsetattr()` for port setup and `DispatchSource.makeReadSource(fileDescriptor:queue:.main)` for async reads. ORSSerialPort was evaluated but its delegate callbacks never fired reliably under Swift concurrency (`@MainActor` + DispatchQueue.main mismatch). The POSIX approach fires the read handler directly on `DispatchQueue.main`, matching the `@MainActor` isolation. `withCheckedThrowingContinuation` bridges reads into async context. 2-second timeout per command.

### D-002: Non-destructive partial apply
When switching profiles, only Focus API commands for fields explicitly set in the mapping are sent. A mapping with only `layer: 3` sends only `layer.moveTo 3` — no LED commands. This preserves any state set externally by Bazecor.

### D-003: Bundle ID matching
All app matching uses `NSRunningApplication.bundleIdentifier`. Display names are UI-only labels. The app picker captures both fields automatically — no manual text entry ever.

### D-004: Hybrid app picker
Default view: SwiftUI list of `NSWorkspace.runningApplications` (sorted, with icons). Secondary path: NSOpenPanel filtered to `.app` bundles for adding mappings for apps not currently running.

### D-005: Menu bar icon with SF Symbol + colored dot
The keyboard SF Symbol is kept as a template image (auto light/dark adaptation). A colored Unicode dot (`●`) is rendered as `NSStatusBarButton.attributedTitle` alongside the image to show connection status:
- **On (connected)**: keyboard icon + green `●`
- **Error / port busy**: keyboard icon + orange `●`
- **Off (disabled)**: keyboard icon at 40% opacity, no dot
This avoids compositing non-template images while still showing a color status indicator.

### D-006: Settings window — direct dependency injection + recreate on reopen
`SettingsWindowManager.shared` stores direct references to `ProfileSwitcher` and `ConfigStore` (set from `AppDelegate` at launch) rather than resolving them lazily. If the window is visible, `showSettings()` brings it to front. If closed, it destroys the old window and creates a fresh `NSHostingController` — this guarantees the SwiftUI view renders with current state. `StatusTabView` uses `.onReceive(profileSwitcher.objectWillChange)` as belt-and-suspenders to ensure re-renders in the background accessory window context.

### D-007: Config saved on every change
No explicit "Save" button in Settings. Each change (mapping edit, device toggle, etc.) writes config atomically via `ConfigStore.save()`. In-flight saves are serialized on a background queue to avoid blocking the UI.

### D-008: Backoff sequence
On connection failure: `1s → 2s → 4s → 8s → 16s → 30s (cap)`. Settled in `.disconnected` state after cap reached. Immediately resumes on IOKit USB attach notification.

### D-009: USB-only — wireless/BT removed
Wireless (2.4GHz RF) and Bluetooth modes were investigated and removed. The Dygma Focus API operates exclusively over USB serial; there is no programmatic interface to the keyboard over BT or RF. HID shortcut injection (CGEventPost) was prototyped but is incorrect — the keyboard is an input device and cannot receive keystrokes from the Mac. `DeviceConfig` has no `mode` field; USB is the only transport. `DeviceTabView` shows no mode picker.

---

## Key Interfaces (Internal)

### SerialPortProtocol
```swift
protocol SerialPortProtocol {
    func open() throws          // Throws if port busy (EBUSY)
    func close()
    func send(_ data: Data) throws
    var isOpen: Bool { get }
    var delegate: SerialPortDelegate? { get set }
}
```
Mocked in tests; `ORSSerialPort` adapter in production.

### FocusAPIClient
```swift
// Async — caller awaits result or catches TimeoutError / FocusError
func sendCommand(_ command: FocusCommand) async throws -> FocusResponse
func probe() async throws -> Bool          // Sends `version`, checks for non-empty response
func moveToLayer(_ index: Int) async throws
func setBrightness(_ value: Int) async throws
func setTheme(_ name: String) async throws
```

### ProfileSwitcher (Orchestrator)
```swift
// Called by AppEventMonitor after debounce
func handleAppActivated(bundleId: String, displayName: String) async
// Called by MenuBarController on toggle
func setEnabled(_ enabled: Bool) async
// Called by DeviceDiscovery on connect/disconnect
func handleConnectionChange(_ status: ConnectionStatus) async
```

---

## Acceptance Criteria Cross-Reference

| Spec Criterion | Implementation Path |
|---|---|
| Layer switch < 300ms | AppEventMonitor debounce (150ms) + FocusAPIClient.moveToLayer (sync write, no ACK wait for layer) |
| Enable/disable < 200ms | MenuBarController → ProfileSwitcher.setEnabled → SerialPortActor.close() |
| Auto-detect keyboard | DeviceDiscovery.discoverDevice() → IOKit enumerate → FocusAPIClient.probe() |
| Auto-reconnect after replug | IOServiceAddMatchingNotification → DeviceDiscovery.handleAttach() → backoff cancelled |
| Config portable across Macs | All paths via FileManager; no hardcoded strings; JSON is human-readable |
| Run stably for days | Actor isolation prevents races; backoff prevents busy-loop; no polling timers |
| No redundant commands | MappingLookup caches lastAppliedLayer; skips send if unchanged |
| Port released on disable | SerialPortActor.close() called in setEnabled(false) when closePortWhenDisabled=true |
| Start at Login | SMAppService.mainApp.register() / .unregister() in MenuBarController |
| First mapping in < 5 min | App picker shows running apps with icons; no text entry; Test button for immediate verification |
