# Research: Dygma Context Switcher for macOS

**Feature**: `001-dygma-context-switcher`
**Date**: 2026-03-16
**Status**: Complete — all NEEDS CLARIFICATION resolved

---

## R-001: Serial Communication Library

**Decision**: ORSSerialPort via Swift Package Manager

**Rationale**: ORSSerialPort is the de facto standard for macOS serial communication — proven since 2011, built on CoreFoundation/IOKit, ~1000 LOC, handles exclusive port access via BSD `O_EXCL` semantics, and fires delegate callbacks on its own background queue. Adding a Swift `actor` wrapper around it provides thread safety and async/await integration with zero boilerplate.

**Alternatives considered**:
- Raw IOKit + termios: Full control but 200+ lines of C bridge code for port enumeration, baud rate config, and exclusive access that ORSSerialPort already handles correctly.
- SwiftSerial (SPM-native): Lighter but less battle-tested for the EBUSY/reconnect scenarios this app requires.

---

## R-002: Focus API Wire Protocol

**Decision**: ASCII command + `\n` sent; response buffered until `\n.\n` terminator received; 2-second timeout per command.

**Rationale**: The Dygma Focus protocol (shared with Keyboardio Kaleidoscope-based keyboards) uses:
- **Send**: `<command>\n` — plain ASCII, e.g. `layer.moveTo 2\n`
- **Receive**: One or more ASCII lines terminated by a line containing exactly `.`, e.g. `2\n.\n`
- **Error**: Response begins with `ERR_` before the terminator
- **Device probe**: `help\n` → response includes `layer.moveTo` if device is Dygma-compatible

Response parsing: buffer incoming bytes, split on `\n`, when a line is exactly `.` the response is complete. Lines before `.` are the response content.

**Alternatives considered**:
- Custom delimiter: No benefit; `.` on its own line is unambiguous and is the firmware standard.
- Binary framing: Not supported by Dygma firmware.

---

## R-003: Command Queue & Timeout

**Decision**: Swift `actor` (`SerialPortActor`) wrapping ORSSerialPort, using `withCheckedThrowingContinuation` for async command-response pairing and `Task.sleep` for 2-second timeout enforcement.

**Rationale**: A Swift actor serializes all access automatically — no explicit locks needed. `CheckedContinuation` bridges the ORSSerialPort delegate callback (fires on a background queue) into an async context cleanly. `Task.sleep(nanoseconds:)` + `Task.cancel()` provides structured timeout without semaphores.

Backoff is implemented in a higher-level `FocusAPIClient` wrapper: sequence `1s → 2s → 4s → 8s → 16s → 30s cap`, then stable "disconnected" error state; resumes immediately on USB attach notification.

**Alternatives considered**:
- DispatchQueue + DispatchSemaphore: Verbose, error-prone, no structured cancellation.
- Combine: Heavier; overkill for a simple sequential command-response queue.

---

## R-004: App Activation Monitoring & Debounce

**Decision**: `NSWorkspace.didActivateApplicationNotification` observed via `NotificationCenter`; debounce via `DispatchWorkItem` cancel-and-reschedule on the main queue (150ms default, configurable).

**Rationale**: This is the only event-driven (non-polling) macOS API for foreground app changes. `NSWorkspace.applicationUserInfoKey` in the notification's `userInfo` provides the `NSRunningApplication` object — from which both `bundleIdentifier` and `localizedName` are read. `DispatchWorkItem` debounce is a lightweight, idiomatic pattern that cancels a pending work item when a new event arrives within the debounce window.

**Bundle ID matching**: Active app's `bundleIdentifier` is matched against stored `AppMapping.bundleIdentifier` values — stable across app updates and locale changes.

**Alternatives considered**:
- Polling `NSWorkspace.frontmostApplication` on a timer: Wastes CPU, introduces latency.
- Accessibility API `AXObserver`: Requires Accessibility permission; unnecessary since `NSWorkspace` notifications need no special entitlements.

---

## R-005: App Picker UI

**Decision**: Hybrid picker — default tab shows running apps (`NSWorkspace.runningApplications`) with icons in a SwiftUI list; secondary tab / button opens `NSOpenPanel` filtered to `.app` bundles for adding mappings for apps not currently running.

**Rationale**: Running apps list covers the 90% case and requires no navigation. `NSOpenPanel` handles the case where the target app (e.g., a DAW) isn't open at configuration time. Both flows capture `bundleIdentifier` and `localizedName` automatically — user never types either. App icons are loaded from `NSRunningApplication.icon` (running apps) or `NSWorkspace.icon(forFile:)` (file picker).

**Alternatives considered**:
- Running apps only: Fails when the target app isn't open.
- File browser only: Requires navigating to `/Applications`, more friction for common case.
- Spotlight-style search: Over-engineered for a small settings panel.

---

## R-006: USB Device Discovery & Hotplug

**Decision**: Device discovery uses `IOServiceGetMatchingServices` matching `kIOSerialBSDServiceValue` to enumerate `/dev/cu.usbmodem*` paths, then probe each with `help\n` to identify the Dygma Defy. Hotplug (attach/detach) uses `IOServiceAddMatchingNotification` dispatched on `DispatchQueue.main` — zero polling.

**Rationale**: IOKit is the native OS-level API for USB hardware events on macOS. Notifications are event-driven via Mach ports, arriving within milliseconds of physical USB activity. ORSSerialPort's `serialPortWasRemovedFromSystem:` delegate method is also monitored as a secondary signal for disconnection.

**Alternatives considered**:
- Polling `/dev/`: Wastes CPU, high latency.
- Relying solely on ORSSerialPort callbacks: Loses the ability to detect re-attach and trigger auto-reconnect independently of the port object.

---

## R-007: Configuration Persistence

**Decision**: Swift `Codable` structs with a `version` field for migration, written atomically using `Data.write(to:options:.atomic)` to `~/Library/Application Support/DygmaContext/config.json` via `FileManager.default.urls(for:.applicationSupportDirectory, in:.userDomainMask)`.

**Rationale**: `Codable` is type-safe, generates human-readable JSON, and handles optional fields with defaults via `decodeIfPresent`. Atomic writes (write to temp, rename) prevent config corruption if the app crashes mid-save. Path resolution via `FileManager` ensures no hardcoded user directory paths — portable across Macs.

**Migration**: A `version` integer in the root config struct enables transparent forward migration (`if version < 2 { ... }`) without external schema tooling.

**Alternatives considered**:
- UserDefaults: No structured types, no versioning, hard to copy between Macs.
- Core Data: Massively over-engineered for a single flat JSON config.
- Property list: Less readable, harder to edit manually for portability.

---

## R-008: Menu Bar App Architecture

**Decision**: `NSStatusItem` + `NSMenu` (AppKit) with `LSUIElement = YES` in Info.plist. Settings window uses `NSWindow` + `NSHostingController` (SwiftUI content hosted in AppKit window). App entry point via `@NSApplicationMain` AppDelegate or `@main` App struct with `Settings` scene suppressed.

**Rationale**: `NSStatusItem` is the only framework-supported API for macOS menu bar items. Template images (`isTemplate = true`) automatically adapt to dark mode. `NSWindow + NSHostingController` gives explicit control over window lifecycle (singleton window, bring-to-front if already open, save frame position). `LSUIElement = YES` hides the Dock icon — standard for menu bar utilities.

**Icon states** (using SF Symbols as template images):
- On: `keyboard` — solid keyboard symbol
- Off: `keyboard` with `.slash` variant or reduced opacity overlay
- Error: `keyboard` + `exclamationmark.triangle` badge

**Alternatives considered**:
- SwiftUI `MenuBarExtra` (macOS 13+): Simpler API but loses fine-grained control over menu rebuild timing and icon state transitions.
- SwiftUI `WindowGroup` for settings: Less control over singleton window behavior; `NSWindow` approach is more reliable for background apps.

---

## R-009: Login Item (Start at Login)

**Decision**: `SMAppService.mainApp.register()` / `.unregister()` (ServiceManagement framework, macOS 13+). Status read via `SMAppService.mainApp.status == .enabled`.

**Rationale**: `SMAppService` is the modern replacement for LaunchAgent plists and the deprecated `SMLoginItemSetEnabled`. It requires no manual plist files, user approves via System Settings → General → Login Items, and it integrates cleanly with macOS 13+ security model.

**Alternatives considered**:
- Manual LaunchAgent plist: Deprecated pattern, requires writing to `~/Library/LaunchAgents/` with correct plist format and `launchctl` calls.
- `LSSharedFileList`: Removed in macOS 13.

---

## R-010: Testing Strategy

**Decision**: XCTest with protocol-based dependency injection. Core logic (config loading, bundle ID mapping lookup, debounce timer, command formatting) is extracted into testable classes/actors. Serial port abstracted behind `SerialPortProtocol`; `MockSerialPort` used in tests. No UI testing for v1.

**Rationale**: Menu bar UI is inherently difficult to automate-test. The value is in testing the logic layer: mapping lookup, debounce correctness, idempotency check, config parsing, and Focus API command formatting. Protocol-based mocks enable fast, deterministic unit tests with no hardware dependency.

**Test coverage targets**:
- Config load/save roundtrip (including version migration)
- AppMapping lookup by bundle ID (hit, miss, default fallback)
- Debounce: only final event in window triggers apply
- Idempotency: same layer, no command sent
- Focus API response parsing (complete, timeout, error)
- Backoff sequence correctness

---

## R-011: Concurrency Model

**Decision**: Swift async/await + `actor` throughout (macOS 13+ target). Main thread owned by `@MainActor` for UI updates; `SerialPortActor` for serial I/O isolation; `DispatchWorkItem` retained for debounce (simpler than `Task.sleep` for a cancellable timer pattern).

**Rationale**: macOS 13 Ventura (minimum target) fully supports Swift 5.5+ concurrency. Actors provide automatic mutual exclusion for the serial port state machine. `@MainActor` ensures all UI/menu bar updates happen on the main thread. `DispatchWorkItem` cancel-and-reschedule remains idiomatic for debounce (cancel-ability is simpler than structured Task cancellation for this use case).

**Alternatives considered**:
- DispatchQueue throughout: Works but verbose; no structured cancellation; harder to reason about thread ownership.
- Combine: Pipeline composition is over-engineered for the linear event flow here (app activated → debounce → lookup → send command).

---

## Technology Stack Summary

| Concern | Technology |
|---|---|
| Language | Swift 5.9+ |
| UI Framework | SwiftUI (settings) + AppKit (menu bar, window hosting) |
| Serial I/O | ORSSerialPort (SPM) |
| USB Hotplug | IOKit (`IOServiceAddMatchingNotification`) |
| App Monitoring | `NSWorkspace.didActivateApplicationNotification` |
| Config Persistence | Swift Codable + atomic file writes |
| Login Item | SMAppService (macOS 13+) |
| Concurrency | Swift async/await + actors |
| Testing | XCTest + protocol mocks |
| Minimum macOS | 13.0 (Ventura) |
| Xcode | 15+ |
| Build System | Xcode project (.xcodeproj) + SPM for dependencies |
