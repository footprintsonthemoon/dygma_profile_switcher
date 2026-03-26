# Feature Specification: Dygma Context Switcher for macOS

**Feature Branch**: `001-dygma-context-switcher`
**Created**: 2026-03-15
**Status**: Draft
**Input**: User description: "Dygma Context Switcher for macOS"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Automatic Layer Switching When Changing Apps (Priority: P1)

A user is working on their Mac with multiple applications. When they switch from their browser to Dorico 6 (music notation software), the Dygma Defy keyboard automatically and silently changes to the layer configured for Dorico — within milliseconds. The user never needs to manually change keyboard layers; it just happens. When they switch back to an unmapped app, the default layer is restored.

**Why this priority**: This is the core value of the product. Without automatic switching, the feature does not exist. Everything else is configuration and support.

**Independent Test**: Can be fully tested by connecting the keyboard via USB, adding a mapping (e.g., Dorico 6 → Layer 2), and switching between apps to verify the layer changes automatically, delivering hands-free keyboard context awareness.

**Acceptance Scenarios**:

1. **Given** the app is enabled and a mapping exists for "Dorico 6" → Layer 2, **When** the user clicks on Dorico 6 to bring it to the foreground, **Then** the keyboard switches to Layer 2 within 300ms.
2. **Given** the app is enabled and the user switches to an unmapped application, **When** the application becomes the frontmost window, **Then** the keyboard returns to the default layer within 300ms.
3. **Given** the user rapidly switches between apps within 150ms (debounce window), **When** they settle on a final app, **Then** only one layer switch command is sent for that final app.
4. **Given** the same app is already active on the current layer, **When** a re-activation event fires, **Then** no redundant command is sent to the keyboard.

---

### User Story 2 - Menu Bar Control (Enable/Disable and Quick Access) (Priority: P2)

A user wants to temporarily let Bazecor (the official Dygma configuration software) connect to their keyboard without quitting the profile switcher. They click the menu bar icon and toggle "Enabled" off. The icon visually changes to indicate it's off, the serial port is released, and Bazecor can now connect. When they're done, they re-enable it from the same menu.

**Why this priority**: The menu bar is the primary interaction surface for day-to-day use. The enable/disable toggle is essential for coexistence with Bazecor and for user control.

**Independent Test**: Can be fully tested by toggling the "Enabled" item in the menu bar and verifying that the icon changes state, layer switching stops, and Bazecor can connect while disabled.

**Acceptance Scenarios**:

1. **Given** the app is running and enabled, **When** the user clicks "Enabled" in the menu, **Then** switching is disabled within 200ms, the icon shows the "off" state, and the serial port is released.
2. **Given** the app is disabled, **When** the user clicks "Enabled" in the menu again, **Then** switching is re-enabled, the serial port is re-acquired, and the icon returns to the "on" state.
3. **Given** the keyboard is unreachable or the port is busy, **When** the app attempts to connect, **Then** the icon shows an "error" state with a warning indicator.
4. **Given** the app is running, **When** the user clicks "Open Settings…", **Then** the settings window opens.

---

### User Story 3 - Configure App-to-Layer Mappings via Settings Window (Priority: P3)

A new user sets up the profile switcher for the first time. They open Settings from the menu bar, navigate to the Mappings tab, and click "Add App". A picker GUI opens showing currently running apps and allowing browsing of installed apps — they click Dorico 6, confirm, then set Layer 2 and brightness 140. No names or identifiers are typed. They test the mapping immediately using the "Test" button without switching away from settings.

**Why this priority**: Without mapping configuration, the product cannot be personalized. This story enables users to set up and maintain their automation rules.

**Independent Test**: Can be fully tested by adding, editing, and removing a mapping in the Settings window and verifying the change is reflected in the live behavior without restarting the app.

**Acceptance Scenarios**:

1. **Given** the Settings window is open on the Mappings tab, **When** the user adds a new mapping with an app name and layer number, **Then** the mapping is saved and switching respects it immediately.
2. **Given** a mapping exists, **When** the user clicks the "Test" button for that mapping, **Then** the keyboard switches to the configured layer immediately.
3. **Given** the Settings window is open, **When** the user clicks "Add App", **Then** a picker GUI opens showing currently running apps and allowing browsing of installed .app bundles — no text entry is required.
4. **Given** a mapping exists, **When** the user deletes it, **Then** that app falls back to the default layer behavior.

---

### User Story 4 - Device Auto-Detection (Priority: P4)

A user connects their Dygma Defy via USB for the first time or after a replug. The app automatically discovers the correct serial port by scanning available USB serial devices and sending a probe command. The user does not need to know or enter the device path manually.

**Why this priority**: Without auto-detection, setup requires technical knowledge. This story makes the product accessible and portable across Macs.

**Independent Test**: Can be fully tested by unplugging and replugging the keyboard and triggering "Re-detect Keyboard" from the menu, verifying the port is found and connected without manual input.

**Acceptance Scenarios**:

1. **Given** the keyboard is connected via USB, **When** the app starts or "Re-detect Keyboard" is triggered, **Then** the correct port is found automatically and stored in configuration.
2. **Given** multiple USB serial devices are connected, **When** auto-detection runs, **Then** only the Dygma Defy is matched (via Focus API probe response).
3. **Given** the keyboard is disconnected and reconnected, **When** the app detects the reconnection, **Then** it re-establishes the connection automatically without user action.
4. **Given** no compatible device is found, **When** auto-detection completes, **Then** the icon shows an error state and the status submenu reflects "Device not found".

---

### User Story 5 - Start at Login and Portability (Priority: P5)

A user sets up the profile switcher on their work Mac and enables "Start at Login". The next day, the app starts silently in the background when they log in. Later, they copy their config file to their home Mac — all mappings and settings are preserved without any code changes.

**Why this priority**: These quality-of-life features make the product a reliable, set-and-forget tool rather than something requiring manual startup each session.

**Independent Test**: Can be fully tested by enabling "Start at Login", logging out and back in, and verifying the menu bar icon appears automatically; portability tested by copying config.json to another Mac.

**Acceptance Scenarios**:

1. **Given** the user enables "Start at Login" in the menu, **When** the user logs out and back in, **Then** the app starts automatically in the background and is visible as a menu bar icon.
2. **Given** a valid config.json from another Mac is placed in the correct directory, **When** the app starts, **Then** it loads all mappings and device settings without errors.
3. **Given** the user disables "Start at Login", **When** the user logs out and back in, **Then** the app does not start automatically.

---

### Edge Cases

- What happens when the Dygma keyboard is unplugged mid-session? → App retries with exponential backoff, shows error state, reconnects automatically when re-plugged.
- What happens when Bazecor is open and holds the serial port? → App shows "Port in use (Bazecor?)" in status, retries with backoff, does not crash.
- What happens when a mapped app (by bundle ID) is no longer installed or running? → Mapping is preserved in config but silently inactive; no error shown. The display name remains as a label in the UI.
- What happens when the config file is missing or corrupted? → App uses built-in defaults, logs a warning, creates a fresh config on first save.
- What happens when multiple apps fire activation events in rapid succession? → Debounce (150ms default) ensures only the final settled app triggers a layer switch.
- What happens when a layer number in config is out of range (e.g., 10)? → Validation rejects the value; UI shows an error and prevents saving.
- What happens when the keyboard is connected via Bluetooth or 2.4GHz RF? → Wireless layer switching is not supported in v1. The Focus API (the only programmatic interface to the keyboard) operates exclusively over USB serial. The app only supports USB connection mode.
- What happens if the config file is read-only or the directory is inaccessible? → App runs on loaded state, logs an error, and notifies the user that settings cannot be saved.
- What happens when the user quits the app? → No keyboard state change is made on exit. The keyboard remains on whatever layer was last applied. (Each layer has built-in shortcuts to navigate to other layers, so no reset is needed.)

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The system MUST monitor the frontmost application on macOS and detect changes without polling (event-driven), matching active apps against stored mappings by bundle identifier.
- **FR-002**: The system MUST map application names to keyboard layers and LED settings via a user-editable configuration file.
- **FR-003**: The system MUST apply only the profile fields explicitly configured in a mapping (layer, LED theme, LED brightness) within 300ms of a foreground app change; unspecified fields MUST be left unchanged on the keyboard (non-destructive partial apply).
- **FR-004**: The system MUST apply only the explicitly configured fields of the default profile when the active app has no configured mapping; unspecified default fields MUST be left unchanged on the keyboard.
- **FR-005**: The system MUST debounce rapid app-switching events, waiting a configurable period (default 150ms) before applying changes.
- **FR-006**: The system MUST skip applying a change if the requested layer is already active (idempotent behavior).
- **FR-007**: The system MUST auto-detect the Dygma Defy keyboard on available USB serial ports using a probe command, without requiring manual port entry.
- **FR-008**: The system MUST exclusively hold the serial port when enabled, and release it when disabled, allowing other software (e.g., Bazecor) to connect.
- **FR-009**: The system MUST reconnect to the keyboard automatically after USB replug or port recovery without user action.
- **FR-010**: The system MUST retry with exponential backoff when the serial port is busy or unavailable. Each Focus API command MUST time out after 2 seconds if no response is received. The backoff sequence starts at 1s and doubles each attempt (1s → 2s → 4s → 8s → 16s → 30s cap); once the cap is reached the app settles into a stable "disconnected" error state and resumes immediately upon USB replug detection.
- **FR-011**: The system MUST display a menu bar icon with three distinct visual states: active (on), inactive (off), and error.
- **FR-012**: The system MUST provide a menu bar menu with: Enabled toggle, Open Settings, Re-detect Keyboard, Status submenu, Start at Login toggle, Open Logs, and Quit.
- **FR-013**: The system MUST allow enabling/disabling switching from the menu bar, taking effect within 200ms.
- **FR-014**: The system MUST provide a Settings window with tabs for: Status, Mappings, Device, and Logs.
- **FR-015**: The system MUST allow users to add, edit, and remove app-to-layer mappings in the Settings window.
- **FR-016**: The system MUST provide an app picker GUI for adding mappings; users select apps by browsing currently running apps or navigating installed .app bundles — no manual entry of app names or bundle identifiers is required or permitted.
- **FR-016a**: When a user selects an app via the picker, the system MUST automatically capture and store both the bundle identifier (for matching) and the display name (for UI display).
- **FR-017**: The system MUST provide a "Test" button per mapping that immediately applies that profile to verify configuration.
- **FR-018**: The system MUST persist all configuration to a JSON file in the user's Application Support directory.
- **FR-019**: The system MUST load configuration at startup and apply the enabled/disabled state immediately.
- **FR-020**: The system MUST validate configuration on load (version, layer range 0–9, device mode values, baud rate type).
- **FR-021**: The system MUST support enabling "Start at Login" using modern macOS Login Item APIs, controllable from the menu bar.
- **FR-022**: The system MUST write structured logs to a file in the user's Logs directory, with configurable verbosity level.
- **FR-023**: The system MUST display the last 200 lines of the log in the Settings window and allow log export.
- **FR-024**: The system MUST run without a Dock icon (background/agent app style).
- **FR-025**: The system MUST store all file paths using platform-standard path resolution (no hardcoded user directory paths in code or config).
- **FR-026**: The system MUST clearly indicate in the UI that Wireless/Bluetooth connection is not supported (the Focus API is USB-only; there is no programmatic interface to the keyboard over BT or RF).

### Key Entities

- **AppMapping**: A rule associating a specific application with a keyboard profile. Contains: bundle identifier (used for matching, stable across app updates and locale changes), display name (shown in UI, captured automatically at selection time), target layer (integer 0–9), optional LED theme name, optional LED brightness.
- **KeyboardProfile**: A set of keyboard settings to apply: layer index (0–9), optional LED theme name, optional LED brightness value.
- **DeviceConfig**: Describes how to connect to the Dygma keyboard: connection mode (USB/wireless/bluetooth), auto-detect flag, serial port path, baud rate.
- **DefaultProfile**: The fallback keyboard profile applied when no mapping matches the active app. Contains the same fields as KeyboardProfile.
- **RuntimeState**: Transient (non-persisted) state including: enabled/disabled flag, current connection status, last detected app name, last applied layer index.
- **Configuration**: The top-level persistent data structure versioned for forward migration, containing: device config, defaults, all app mappings, fallback settings, runtime preferences (enabled, closePortWhenDisabled), and logging settings.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Keyboard layer switches within 300ms of the user activating a mapped application.
- **SC-002**: The enable/disable toggle takes effect within 200ms, including releasing the serial port.
- **SC-003**: The keyboard is auto-detected without any manual port configuration after being connected via USB.
- **SC-004**: The app reconnects to the keyboard automatically after a USB replug, without user intervention.
- **SC-005**: A configuration file from one Mac can be copied to another Mac and loaded correctly without errors or code changes.
- **SC-006**: The app runs continuously for multiple days without crashes, memory leaks, or requiring a restart.
- **SC-007**: No redundant commands are sent to the keyboard when the same layer is already active or events are debounced.
- **SC-008**: The serial port is fully released when switching is disabled, allowing Bazecor to connect immediately after toggle.
- **SC-009**: "Start at Login" causes the app to appear in the menu bar after logout and back in without any manual action.
- **SC-010**: A first-time user can configure their first app-to-layer mapping and verify it works within 5 minutes of first launch.

## Clarifications

### Session 2026-03-15

- Q: What should happen to the keyboard's current layer state when the app quits? → A: No action — leave the keyboard in its current layer state. Every layer has built-in shortcuts to navigate to other layers, so no reset is needed or desirable.
- Q: Should app mapping match by display name, bundle ID, or both? → A: Store both — bundle ID used for matching (stable across updates/locale changes), display name shown in the UI. No manual entry of names or IDs; users select apps exclusively via a GUI app picker (browsing running apps or installed .app bundles). The switcher captures both fields automatically.
- Q: When a mapping specifies only some profile fields, what happens to unspecified fields? → A: Apply only the specified fields; leave all unspecified fields unchanged on the keyboard (non-destructive behavior).
- Q: What is the timeout for a Focus API serial command response? → A: 2 seconds per command before declaring failure and triggering error state/backoff.
- Q: What is the maximum backoff interval for reconnection retries? → A: 30 seconds maximum interval; backoff sequence starts at 1s and doubles each attempt (1s, 2s, 4s, 8s, 16s, 30s cap). App settles into a stable "disconnected" error state once the cap is reached, resuming immediately on USB replug detection.

## Assumptions

- The Dygma Defy keyboard exposes a serial (Focus API) interface over USB; this is the only supported connection mode. The keyboard also supports Bluetooth and 2.4GHz RF, but the Focus API does not operate over these transports — there is no programmatic way to switch layers wirelessly.
- The Focus API responds to a `version` command with a version string (e.g. `v2.0.0`), which is used as the device probe because `help` returns a large response that exceeds the 2-second timeout. The `version` command returns immediately and is sufficient to confirm a Dygma device.
- Layer indices are 0-based internally and in the Focus API, but displayed 1-based in the UI (matching Bazecor's numbering). Valid internal values are 0 through 9.
- App matching is performed by bundle identifier (e.g., `com.steinberg.dorico5`), not display name. Display names are stored for human-readable UI presentation only and are captured automatically by the picker — never entered manually.
- The app targets macOS 13 (Ventura) or later, enabling use of modern Login Item management APIs.
- LED theme names are opaque strings passed through to the Focus API; v1 does not enumerate or validate available theme names.
- Only one Dygma Defy keyboard is connected at a time; multi-device support is out of scope for v1.
- The user runs macOS as a standard (non-admin) user; no elevated privileges are required.
- The debounce default of 150ms is acceptable for normal human app-switching behavior; this is configurable if needed.
