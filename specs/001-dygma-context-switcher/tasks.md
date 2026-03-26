# Tasks: Dygma Context Switcher for macOS

**Input**: Design documents from `/specs/001-dygma-context-switcher/`
**Prerequisites**: plan.md ✓, spec.md ✓, research.md ✓, data-model.md ✓, contracts/ ✓

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.
**Tests**: Unit test tasks included for the core logic layer (config, mapping lookup, serial protocol, debounce). No UI tests.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no shared dependencies)
- **[Story]**: User story this task belongs to (US1–US5)
- Exact file paths per plan.md project structure

---

## Phase 1: Setup (Project Initialization)

**Purpose**: Create the Xcode project, configure app identity, and establish build infrastructure.

- [x] T001 Create macOS App Xcode project named `DygmaContextSwitcher` (Swift, SwiftUI app lifecycle, bundle ID `com.yourname.dygmacontextswitcher`, deployment target macOS 13.0) with folder structure per plan.md: `DygmaContextSwitcher/{App,MenuBar,Core,Serial,Config,UI,Logging}/`
- [x] T002 Configure `DygmaContextSwitcher/App/Info.plist`: set `LSUIElement = YES` (hides Dock icon), `LSMinimumSystemVersion = 13.0`, `NSPrincipalClass = NSApplication`
- [x] T003 [P] Add ORSSerialPort Swift Package dependency in Xcode (URL: `https://github.com/armadsen/ORSSerialPort`, version Up Next Major from 2.1.0, target: DygmaContextSwitcher)
- [x] T004 [P] Create `DygmaContextSwitcher/Resources/Assets.xcassets` menu bar icon set: three SF Symbol-based template images named `menubar-on` (keyboard), `menubar-off` (keyboard.slash), `menubar-error` (keyboard + exclamationmark.triangle badge); set `isTemplate = true`
- [x] T005 [P] Create `DygmaContextSwitcherTests` test target in Xcode with XCTest framework; create folder structure `DygmaContextSwitcherTests/{Mocks}/`

**Checkpoint**: Project builds cleanly on macOS 13+ with no errors.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Core data model, config persistence, logging, and test mocks that every user story depends on.

**⚠️ CRITICAL**: No user story work can begin until this phase is complete.

- [x] T006 Create `DygmaContextSwitcher/Config/Configuration.swift` with all Codable structs: `AppConfig` (root, version: Int = 1), `DeviceConfig` (autoDetect + serial only — no mode field, USB-only), `SerialConfig`, `DefaultProfile`, `AppMapping` (bundleIdentifier + displayName + profile), `MappingProfile` (all fields optional), `RuntimePreferences`, `LoggingConfig` — with CodingKeys and `decodeIfPresent` defaults. `FallbackConfig` and `DeviceMode` enum removed (wireless/BT not supported).
- [x] T007 [P] Create `DygmaContextSwitcher/Config/ConfigStore.swift`: `load()` reads from `FileManager.default.urls(for:.applicationSupportDirectory, in:.userDomainMask)[0]/DygmaContext/config.json` (returns built-in defaults if missing/corrupt); `save(_ config:)` writes atomically via `Data.write(to:options:.atomic)`; `createDirectoryIfNeeded()`; version migration stub for future versions
- [x] T008 [P] Create `DygmaContextSwitcher/Logging/AppLogger.swift`: structured file logger writing to `~/Library/Logs/DygmaContext/dygma-context.log` via `FileManager`; configurable level (debug/info/warning/error); in-memory ring buffer of last 200 lines (published `@Published var recentLines: [String]`) for Settings UI; `export() -> URL` writes buffer to temp file
- [x] T009 [P] Create `DygmaContextSwitcher/Serial/SerialPortProtocol.swift`: protocol with `open() throws`, `close()`, `send(_ data: Data) throws`, `var isOpen: Bool`, `var delegate: (any SerialPortDelegate)?`; plus `SerialPortDelegate` protocol with `didReceiveData(_ data: Data)` and `portWasRemovedFromSystem()`
- [x] T010 [P] Create `DygmaContextSwitcherTests/Mocks/MockSerialPort.swift`: implements `SerialPortProtocol`; records `sentData: [Data]`; configurable `shouldThrowOnOpen: Bool`; manually fires `delegate?.didReceiveData()` via `simulateResponse(_ string: String)` helper
- [x] T011 Create `DygmaContextSwitcher/App/DygmaContextSwitcherApp.swift`: `@main` struct conforming to `App`; sets `NSApp.setActivationPolicy(.accessory)` to suppress Dock icon; instantiates `AppDelegate` via `@NSApplicationDelegateAdaptor`
- [x] T012 Create `DygmaContextSwitcher/App/AppDelegate.swift`: `NSApplicationDelegate` skeleton with `applicationDidFinishLaunching`; holds references to `MenuBarController`, `ProfileSwitcher`, `ConfigStore`; loads config on launch

**Checkpoint**: App launches, Dock icon is hidden, config loads/saves correctly, logger writes to file.

---

## Phase 3: User Story 1 — Automatic Layer Switching (Priority: P1) 🎯 MVP

**Goal**: App monitors foreground app changes and silently sends the correct `layer.moveTo N` command to the keyboard within 300ms, with debounce and idempotency.

**Independent Test**: Connect Dygma Defy via USB, add one mapping in config.json manually, launch app, switch to mapped app → keyboard changes layer within 300ms. Switch back to unmapped app → default layer applied. Rapidly switch apps → only one command sent.

### Implementation for User Story 1

- [x] T013 Create `DygmaContextSwitcher/Serial/SerialPortActor.swift`: `@MainActor` class using POSIX `open()`/`tcsetattr()`/`cfsetspeed()` for port config; `DispatchSource.makeReadSource(fileDescriptor:queue:.main)` for async reads (ORSSerialPort delegate approach abandoned — callbacks never fired under Swift concurrency); `sendCommand(_ text: String) async throws -> String` uses `withCheckedThrowingContinuation`; 2-second timeout; CRLF→LF normalization; response buffer accumulates until `\n.\n` terminator
- [x] T014 Create `DygmaContextSwitcher/Serial/FocusAPIClient.swift`: `@MainActor` class holding `SerialPortActor`; `probe() async throws -> Bool` (sends `version\n`, checks for non-empty response — `help` was too slow for 2s timeout); `moveToLayer(_ n: Int) async throws`; `setBrightness(_ v: Int) async throws`; `setTheme(_ name: String) async throws`; `connect(portPath: String) async throws`; `disconnect()`; each method only sends if field is non-nil (partial apply contract)
- [x] T015 [P] Create `DygmaContextSwitcher/Core/MappingLookup.swift`: `lookup(bundleId: String, mappings: [AppMapping], defaults: DefaultProfile) -> (layer: Int?, brightness: Int?, theme: String?)` returns merged partial profile; `var lastAppliedLayer: Int?` for idempotency (skip `layer.moveTo` if unchanged); unit-testable pure function
- [x] T016 [P] Create `DygmaContextSwitcher/Core/AppEventMonitor.swift`: observes `NSWorkspace.didActivateApplicationNotification`; extracts `bundleIdentifier` and `localizedName` from `NSWorkspace.applicationUserInfoKey`; debounces via `DispatchWorkItem` cancel-and-reschedule at configurable interval (default 150ms); calls `onAppActivated: (String, String) -> Void` closure
- [x] T017 Create `DygmaContextSwitcher/Core/ProfileSwitcher.swift`: `@MainActor` orchestrator; `handleAppActivated(bundleId:displayName:) async` runs lookup → idempotency check → partial apply via `FocusAPIClient`; `setEnabled(_ enabled: Bool) async` opens/closes port per `closePortWhenDisabled`; `handleConnectionChange(_ status: ConnectionStatus) async` updates `RuntimeState`; publishes `@Published var runtimeState: RuntimeState`
- [x] T018 Wire US1 in `DygmaContextSwitcher/App/AppDelegate.swift`: instantiate `ConfigStore`, `FocusAPIClient`, `ProfileSwitcher`, `AppEventMonitor`; connect `AppEventMonitor.onAppActivated` → `ProfileSwitcher.handleAppActivated`; call `ProfileSwitcher.setEnabled(config.runtime.enabled)` on launch
- [x] T019 [P] Write `DygmaContextSwitcherTests/ConfigStoreTests.swift`: test load from missing file returns defaults; test save/load roundtrip preserves all fields; test corrupt JSON returns defaults; test path uses FileManager (not hardcoded)
- [x] T020 [P] Write `DygmaContextSwitcherTests/MappingLookupTests.swift`: test bundle ID hit returns correct layer; test miss returns default layer; test nil layer in mapping skips layer command; test same layer as lastApplied triggers idempotency skip; test partial profile (layer only, brightness only)
- [x] T021 [P] Write `DygmaContextSwitcherTests/FocusAPIClientTests.swift`: using `MockSerialPort`; test `moveToLayer` sends `layer.moveTo 2\n`; test `probe()` returns true when response contains `layer.moveTo`; test 2-second timeout throws `TimeoutError`; test `ERR_` response throws `FocusError`; test response parsing handles multi-line response before `.` terminator
- [x] T022 [P] Write `DygmaContextSwitcherTests/AppEventMonitorTests.swift`: test rapid events within debounce window produce only one callback; test single event after debounce produces callback; test bundle ID extracted from notification userInfo

**Checkpoint**: US1 fully functional — keyboard layer switches automatically on app change. All unit tests pass.

---

## Phase 4: User Story 2 — Menu Bar Control (Priority: P2)

**Goal**: Menu bar icon with 3 visual states (on/off/error); Enabled toggle; Open Settings; Re-detect Keyboard; Status submenu; Start at Login; Open Logs; Quit.

**Independent Test**: App running → menu bar icon visible. Toggle Enabled → icon changes to off state, switching stops. Toggle back → icon returns to on, switching resumes. Status submenu shows current port and last app.

### Implementation for User Story 2

- [x] T023 Create `DygmaContextSwitcher/MenuBar/MenuBarViewModel.swift`: `@MainActor ObservableObject`; subscribes to `ProfileSwitcher.$runtimeState`; exposes `iconImageName: String` (maps ConnectionStatus + enabled → `menubar-on/off/error`); exposes `statusLines: [String]` for status submenu items
- [x] T024 Create `DygmaContextSwitcher/MenuBar/MenuBarController.swift`: `NSStatusItem` initialized with `NSStatusBar.system.statusItem(withLength: .variableLength)`; builds `NSMenu` with all required items (Enabled checkbox, Open Settings…, Re-detect Keyboard, separator, Status submenu, separator, Start at Login checkbox, Open Logs…, Quit); observes `MenuBarViewModel` to update icon image and menu item states
- [x] T025 Wire `MenuBarController` into `DygmaContextSwitcher/App/AppDelegate.swift`: instantiate after `ProfileSwitcher` is ready; pass `ProfileSwitcher` and `MenuBarViewModel` references
- [x] T026 Implement Enabled toggle action in `DygmaContextSwitcher/MenuBar/MenuBarController.swift`: `@objc func toggleEnabled()` calls `Task { await profileSwitcher.setEnabled(!runtimeState.isEnabled) }`; persists to config via `ConfigStore.save()`
- [x] T027 Implement "Re-detect Keyboard" action stub in `DygmaContextSwitcher/MenuBar/MenuBarController.swift`: `@objc func redetectKeyboard()` — placeholder body `// wired in US4`
- [x] T028 [P] Implement "Open Logs…" action in `DygmaContextSwitcher/MenuBar/MenuBarController.swift`: `@objc func openLogs()` resolves log directory via `FileManager` and opens it with `NSWorkspace.shared.open(_:)`
- [x] T029 Implement "Start at Login" toggle in `DygmaContextSwitcher/MenuBar/MenuBarController.swift`: `@objc func toggleStartAtLogin()` calls `SMAppService.mainApp.register()` or `.unregister()`; reads `.status == .enabled` to set checkbox state; handles `.requiresApproval` by opening System Settings via `SMAppService.openSystemSettingsLoginItems()`
- [x] T030 [P] Implement Status submenu update in `DygmaContextSwitcher/MenuBar/MenuBarController.swift`: rebuild submenu items from `MenuBarViewModel.statusLines` each time menu opens (`menuWillOpen` delegate); items are read-only (`isEnabled = false`)

**Checkpoint**: US2 fully functional — menu bar icon reacts to state, toggle works, Bazecor can connect when disabled.

---

## Phase 5: User Story 3 — Mapping Configuration UI (Priority: P3)

**Goal**: SwiftUI Settings window with Status/Mappings/Device/Logs tabs. Mappings added via picker (running apps + file browser). Test button per mapping. Changes live immediately.

**Independent Test**: Open Settings from menu. Add a mapping by picking a running app. Set layer 2. Click Test → keyboard switches to layer 2. Delete the mapping → default layer applied on next switch.

### Implementation for User Story 3

- [x] T031 Create `DygmaContextSwitcher/UI/SettingsWindowManager.swift`: singleton `NSWindow` + `NSHostingController<SettingsView>`; `showSettings()` brings existing window to front (`makeKeyAndOrderFront` + `NSApp.activate`) or creates it fresh; saves/restores window frame via `setFrameAutosaveName`
- [x] T032 Wire "Open Settings…" action in `DygmaContextSwitcher/MenuBar/MenuBarController.swift`: calls `SettingsWindowManager.shared.showSettings()`
- [x] T033 Create `DygmaContextSwitcher/UI/Settings/SettingsView.swift`: `TabView` with tabs: Status (icon: `info.circle`), Mappings (icon: `keyboard`), Device (icon: `cable.connector`), Logs (icon: `doc.text`); uses `@EnvironmentObject` for `ProfileSwitcher` and `ConfigStore`
- [x] T034 [P] Create `DygmaContextSwitcher/UI/Settings/StatusTabView.swift`: shows `ConnectionStatus` label (colored dot), port path, mode; last active app display name, bundle ID, profile type (Custom mapping / Default), resolved layer (1-based), resolved brightness; auto-refreshes via `.onReceive(profileSwitcher.objectWillChange)`; LED theme row removed (not implemented in v1)
- [x] T035 [P] Create `DygmaContextSwitcher/UI/Settings/DeviceTabView.swift`: Auto-detect toggle; manual port path field (shown when auto-detect off); Re-detect button with probe result label; detected port display. Mode picker and baud rate field removed — USB is the only transport (Focus API is USB-only; BT/RF have no programmatic interface), baud rate is always 115200.
- [x] T036 Create `DygmaContextSwitcher/UI/Settings/MappingsTabView.swift`: `List` of `AppMapping` rows showing app icon (from `NSWorkspace`), display name, bundle ID; inline Layer stepper (1-based display, 0-based storage) and Brightness stepper (0–255, step 5) with `labelsHidden()` so arrows sit directly adjacent to values; "Test" button; delete button per row; "Add App" button opens `AppPickerView` as sheet
- [x] T037 Create `DygmaContextSwitcher/UI/AppPicker/AppPickerViewModel.swift`: `@MainActor ObservableObject`; `loadRunningApps()` reads `NSWorkspace.shared.runningApplications`, filters to apps with bundleIdentifier, sorts by localizedName, exposes `[(name: String, bundleId: String, icon: NSImage)]`; `browseInstalledApp()` opens `NSOpenPanel` with `directoryURL = /Applications`, `allowedContentTypes = [.applicationBundle]`, extracts `bundleIdentifier` and `localizedName` from selected `Bundle`
- [x] T038 Create `DygmaContextSwitcher/UI/AppPicker/AppPickerView.swift`: SwiftUI sheet; `List` from `AppPickerViewModel.apps` with app icon (32×32), display name; "Browse Installed Apps…" button at bottom; confirm selection captures `(bundleIdentifier, displayName)` and dismisses; displays loading state while `loadRunningApps()` runs
- [x] T039 Wire `AppPickerView` into `DygmaContextSwitcher/UI/Settings/MappingsTabView.swift`: on app selection, show inline layer (0–9 Stepper) and brightness (optional Int field) editor; on confirm, create `AppMapping`, append to `config.mappings`, call `ConfigStore.save(config)` and `ProfileSwitcher.reloadConfig()`
- [x] T040 Implement Test button in `DygmaContextSwitcher/UI/Settings/MappingsTabView.swift`: calls `Task { try await focusAPIClient.applyProfile(mapping.profile) }` (applies only non-nil fields); shows brief "Applied" confirmation label
- [x] T041 [P] Create `DygmaContextSwitcher/UI/Settings/LogsTabView.swift`: `ScrollView` with `Text` showing `AppLogger.shared.recentLines.joined(separator:"\n")`; auto-scrolls to bottom on update; "Export…" button calls `AppLogger.shared.export()` and opens `NSSavePanel` to choose destination

**Checkpoint**: US3 fully functional — can add/remove/test mappings from UI without restarting app.

---

## Phase 6: User Story 4 — Device Auto-Detection (Priority: P4)

**Goal**: App automatically finds the Dygma Defy's serial port on startup/replug via IOKit enumeration + Focus API probe. Hotplug reconnects automatically.

**Independent Test**: Unplug keyboard → icon shows error. Re-detect Keyboard from menu → icon returns to on within seconds. Replug keyboard with app running → reconnects automatically without user action.

### Implementation for User Story 4

- [x] T042 Create `DygmaContextSwitcher/Serial/DeviceDiscovery.swift`: `discoverDevice() async -> String?` enumerates serial ports via `IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching(kIOSerialBSDServiceValue), &iterator)`, reads `kIOCalloutDeviceKey` for each, tries `FocusAPIClient.probe()` on each — returns first matching `portPath`; stores result in config via `ConfigStore`
- [x] T043 Add USB hotplug monitoring in `DygmaContextSwitcher/Serial/DeviceDiscovery.swift`: `startMonitoring()` registers `IOServiceAddMatchingNotification` for `kIOMatchedNotification` (attach) and `kIOTerminatedNotification` (detach) dispatched on `DispatchQueue.main`; on attach fires `onDeviceAttached` closure; on detach fires `onDeviceDetached` closure; `stopMonitoring()` destroys notification port
- [x] T044 Wire `DeviceDiscovery` into `DygmaContextSwitcher/Core/ProfileSwitcher.swift`: `setEnabled(true)` calls `DeviceDiscovery.discoverDevice()` if `config.device.autoDetect`; `DeviceDiscovery.onDeviceAttached` triggers reconnect (cancel current backoff, call `FocusAPIClient.connect`); `onDeviceDetached` sets `connectionStatus = .disconnected` and starts backoff
- [x] T045 Wire "Re-detect Keyboard" menu action in `DygmaContextSwitcher/MenuBar/MenuBarController.swift`: calls `Task { await profileSwitcher.triggerRediscovery() }` which calls `DeviceDiscovery.discoverDevice()` and reconnects
- [x] T046 Wire Probe button in `DygmaContextSwitcher/UI/Settings/DeviceTabView.swift`: calls `DeviceDiscovery.discoverDevice()` and updates port dropdown with found path; shows "Not found" if nil

**Checkpoint**: US4 fully functional — keyboard auto-detected on connect, icon auto-recovers after replug.

---

## Phase 7: User Story 5 — Start at Login & Portability (Priority: P5)

**Goal**: SMAppService login item toggle. Config file is fully portable between Macs.

**Independent Test**: Enable "Start at Login" → log out → log back in → app appears in menu bar. Copy config.json to another Mac → all mappings load correctly.

### Implementation for User Story 5

- [x] T047 Complete SMAppService integration in `DygmaContextSwitcher/MenuBar/MenuBarController.swift`: ensure `menuWillOpen` reads `SMAppService.mainApp.status` to sync checkbox state each time the menu opens; add entitlement `com.apple.security.app-sandbox = false` and `SMAppUsesLoginItem = false` in Info.plist if required by macOS 13 SMAppService
- [x] T048 Add first-launch experience in `DygmaContextSwitcher/Config/ConfigStore.swift`: if config file does not exist on load, write built-in defaults and set flag `isFirstLaunch = true`; in `AppDelegate.applicationDidFinishLaunching` check flag and call `SettingsWindowManager.shared.showSettings()` to guide new users
- [x] T049 [P] Verify portability in `DygmaContextSwitcher/Config/ConfigStore.swift`: audit all path construction — confirm zero hardcoded strings containing `/Users/` or `~`; ensure `logging.path` tilde in saved JSON is expanded at runtime via `NSString.expandingTildeInPath`; add inline comment documenting portability requirement per spec

**Checkpoint**: US5 fully functional — app launches at login, config transfers between Macs cleanly.

---

## Phase 8: Polish & Cross-Cutting Concerns

**Purpose**: Complete remaining spec requirements and harden edge cases across all stories.

- [x] T050 [P] Add config validation on load in `DygmaContextSwitcher/Config/ConfigStore.swift`: validate `layer` 0–9, `baudRate > 0`, each `AppMapping.profile` has at least one non-nil field; log warnings for invalid values and use defaults; do not crash
- [x] T051 [P] Implement `runtime.closePortWhenDisabled` behavior in `DygmaContextSwitcher/Core/ProfileSwitcher.swift`: only call `FocusAPIClient.disconnect()` in `setEnabled(false)` when `config.runtime.closePortWhenDisabled == true`; otherwise keep port open
- [x] T052 [P] Read `debounceMs` from config in `DygmaContextSwitcher/Core/AppEventMonitor.swift`: replace hardcoded 150ms with `config.defaults.debounceMs`; reload debounce interval when config changes via `ProfileSwitcher.reloadConfig()`
- [x] T053 [P] Wireless/BT removed — Focus API is USB-only, no programmatic layer switching over BT/RF; `DeviceTabView` has no mode picker; `DeviceConfig` has no `mode` field; `FR-026` satisfied by USB-only design
- [x] T054 [P] Add error display for port-busy state in `DygmaContextSwitcher/MenuBar/MenuBarViewModel.swift`: when `connectionStatus == .portBusy`, icon shows `menubar-error` and status submenu shows "Port in use — is Bazecor open?" per spec edge case
- [x] T055 [P] Finalize app icon in `DygmaContextSwitcher/Resources/Assets.xcassets`: create `AppIcon` image set (1024×1024 source); placeholder keyboard icon acceptable for v1
- [ ] T056 Run `quickstart.md` validation end-to-end: connect keyboard, launch app, confirm auto-detect, add one mapping via picker, switch to mapped app and confirm layer changes within 300ms, disable switching and confirm Bazecor can connect, re-enable, verify Start at Login persists across logout/login

---

## Dependencies & Execution Order

### Phase Dependencies

```
Phase 1 (Setup)
    └─► Phase 2 (Foundational) ← BLOCKS everything
            ├─► Phase 3 (US1 - Core Switching) ← MVP
            │       └─► Phase 4 (US2 - Menu Bar) ← requires RuntimeState from US1
            │               └─► Phase 5 (US3 - Settings UI) ← requires MenuBarController
            ├─► Phase 6 (US4 - Device Discovery) ← can start after Phase 2; wires into US1
            ├─► Phase 7 (US5 - Login/Portability) ← can start after Phase 2
            └─► Phase 8 (Polish) ← after all user stories
```

### User Story Dependencies

- **US1 (P1)**: Depends only on Foundational (Phase 2). No other story dependency.
- **US2 (P2)**: Depends on US1 (`RuntimeState`, `ProfileSwitcher`). Cannot start before US1 complete.
- **US3 (P3)**: Depends on US2 (`MenuBarController` for wiring) and US1 (`FocusAPIClient` for Test button).
- **US4 (P4)**: Depends on US1 (`FocusAPIClient.probe()`). Wires into US3 (Probe button in DeviceTabView).
- **US5 (P5)**: Depends on Phase 2 only (`ConfigStore`). Independent of US2–US4.

### Within Each User Story

- Config structs (T006) → all other tasks
- SerialPortActor (T013) → FocusAPIClient (T014)
- MappingLookup + AppEventMonitor (T015/T016, parallelizable) → ProfileSwitcher (T017)
- ProfileSwitcher (T017) → MenuBarController (T024)
- MenuBarController (T024) → SettingsWindowManager (T031)
- AppPickerViewModel (T037) → AppPickerView (T038)

### Parallel Opportunities

Within Phase 2: T007, T008, T009, T010 all parallelizable after T006
Within Phase 3: T015 and T016 parallelizable; T019–T022 all parallelizable after their implementation tasks
Within Phase 5: T034, T035, T041 parallelizable; T037 and T038 sequential

---

## Parallel Example: User Story 1

```
After T006 (Configuration.swift) is done, launch in parallel:
  Task T007: ConfigStore.swift
  Task T008: AppLogger.swift
  Task T009: SerialPortProtocol.swift
  Task T010: MockSerialPort.swift

After T013 (SerialPortActor) is done:
  Task T014: FocusAPIClient.swift (sequential — depends on T013)

After T014 is done, launch in parallel:
  Task T015: MappingLookup.swift
  Task T016: AppEventMonitor.swift

After T015 + T016 done:
  Task T017: ProfileSwitcher.swift (sequential — depends on both)

After T017 (ProfileSwitcher) is done, launch unit tests in parallel:
  Task T019: ConfigStoreTests.swift
  Task T020: MappingLookupTests.swift
  Task T021: FocusAPIClientTests.swift
  Task T022: AppEventMonitorTests.swift
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup
2. Complete Phase 2: Foundational (CRITICAL — blocks all stories)
3. Complete Phase 3: User Story 1 (core switching)
4. **STOP and VALIDATE**: Switch apps, confirm layer changes, run unit tests
5. Ship/demo the core loop

### Incremental Delivery

1. Phase 1 + 2 → Foundation ready
2. Phase 3 (US1) → **Headless MVP**: switching works, config in JSON
3. Phase 4 (US2) → **Usable**: menu bar icon + toggle; Bazecor coexistence solved
4. Phase 5 (US3) → **Configurable**: full settings UI; no manual JSON editing needed
5. Phase 6 (US4) → **Discoverable**: auto-detect; no manual port entry
6. Phase 7 (US5) → **Complete**: login item + portability
7. Phase 8 → **Polished**: all edge cases hardened

### Single-Developer Suggested Order

US1 → US4 (device discovery makes US1 testable without manual config) → US2 → US3 → US5 → Polish

---

## Notes

- `[P]` tasks write to different files — safe to parallelize
- `[Story]` label maps each task to its user story for traceability
- Config changes in Settings write immediately (no Save button) per design decision D-007
- No Dock icon at any point — verify `LSUIElement = YES` early in T002
- Serial port is opened lazily (on `setEnabled(true)` or discovery) — never on app launch
- Commit after each checkpoint phase to preserve working state
- Total: **56 tasks** across 8 phases
