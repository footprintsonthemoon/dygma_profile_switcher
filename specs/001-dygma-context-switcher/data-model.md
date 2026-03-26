# Data Model: Dygma Context Switcher for macOS

**Feature**: `001-dygma-context-switcher`
**Date**: 2026-03-16

---

## Persistent Entities (config.json)

### Configuration (root)

Top-level persisted struct. Written atomically to `~/Library/Application Support/DygmaContext/config.json`.

| Field | Type | Required | Default | Validation |
|---|---|---|---|---|
| `version` | Int | yes | `1` | Must equal supported version (currently 1); triggers migration if lower |
| `device` | DeviceConfig | yes | — | See below |
| `defaults` | DefaultProfile | yes | — | See below |
| `mappings` | [AppMapping] | yes | `[]` | Each entry must have unique `bundleIdentifier` |
| `fallback` | FallbackConfig | yes | — | See below |
| `runtime` | RuntimePreferences | yes | — | See below |
| `logging` | LoggingConfig | yes | — | See below |

---

### DeviceConfig

Describes how to connect to the Dygma Defy.

| Field | Type | Required | Default | Validation |
|---|---|---|---|---|
| `mode` | String (enum) | yes | `"usb"` | Must be one of: `usb`, `wireless`, `bluetooth` |
| `autoDetect` | Bool | yes | `true` | — |
| `serial` | SerialConfig | yes | — | Required when mode = usb |

#### SerialConfig

| Field | Type | Required | Default | Validation |
|---|---|---|---|---|
| `portPath` | String? | no | `nil` | Valid `/dev/cu.*` path; `nil` when autoDetect=true and no port found yet |
| `baudRate` | Int | yes | `115200` | Must be a positive integer; standard value is 115200 |

---

### DefaultProfile

The keyboard profile applied when the active app has no matching mapping. All fields are optional — only specified fields are applied (non-destructive partial apply).

| Field | Type | Required | Default | Validation |
|---|---|---|---|---|
| `layer` | Int? | no | `0` | 0–9 inclusive |
| `ledTheme` | String? | no | `nil` | Opaque string, passed through to Focus API |
| `ledBrightness` | Int? | no | `nil` | Value range defined by keyboard firmware; no validation in v1 |
| `debounceMs` | Int | yes | `150` | Must be ≥ 0 |

---

### AppMapping

A rule mapping a specific application to a keyboard profile. Matched by `bundleIdentifier` at runtime.

| Field | Type | Required | Default | Validation |
|---|---|---|---|---|
| `bundleIdentifier` | String | yes | — | Non-empty; must be unique across all mappings (e.g. `com.steinberg.dorico5`) |
| `displayName` | String | yes | — | Non-empty; captured automatically by app picker, used for UI display only |
| `profile` | MappingProfile | yes | — | At least one profile field must be specified |

#### MappingProfile

All fields optional — only specified fields are sent to the keyboard (non-destructive partial apply).

| Field | Type | Required | Default | Validation |
|---|---|---|---|---|
| `layer` | Int? | no | `nil` | 0–9 inclusive |
| `ledTheme` | String? | no | `nil` | Opaque string |
| `ledBrightness` | Int? | no | `nil` | No range validation in v1 |

**Invariant**: At least one of `layer`, `ledTheme`, or `ledBrightness` must be non-nil. An all-nil profile is invalid.

---

### FallbackConfig

Configuration for the optional HID shortcut fallback (v2 feature; present in config for forward compatibility).

| Field | Type | Required | Default | Validation |
|---|---|---|---|---|
| `enabled` | Bool | yes | `false` | Must be `false` in v1 |
| `type` | String? | no | `nil` | `"hidShortcut"` when enabled; nil in v1 |
| `shortcutMap` | [String: String]? | no | `nil` | Key: display name, Value: shortcut string |

---

### RuntimePreferences

User preferences that affect runtime behavior and persist across launches.

| Field | Type | Required | Default | Validation |
|---|---|---|---|---|
| `enabled` | Bool | yes | `true` | Controls whether layer switching is active |
| `closePortWhenDisabled` | Bool | yes | `true` | Whether to release serial port when switching is disabled |

---

### LoggingConfig

| Field | Type | Required | Default | Validation |
|---|---|---|---|---|
| `level` | String (enum) | yes | `"info"` | One of: `debug`, `info`, `warning`, `error` |
| `path` | String | yes | `"~/Library/Logs/DygmaContext/"` | Expanded at runtime via `FileManager`; never hardcoded |

---

## Transient State (in-memory only, never persisted)

### RuntimeState

Held by the core controller; drives menu bar icon and status display.

| Field | Type | Description |
|---|---|---|
| `isEnabled` | Bool | Whether layer switching is active (mirrors `RuntimePreferences.enabled`) |
| `connectionStatus` | ConnectionStatus | `.connected`, `.disconnected`, `.portBusy`, `.error(String)` |
| `portPath` | String? | Currently open port path; nil if disconnected |
| `lastActiveAppBundleId` | String? | Bundle ID of last foreground app |
| `lastActiveAppDisplayName` | String? | Display name of last foreground app |
| `lastAppliedLayer` | Int? | Last layer index sent to keyboard; used for idempotency check |

### ConnectionStatus (enum)

| Case | Description |
|---|---|
| `.connected` | Serial port open, Focus API probe succeeded |
| `.disconnected` | No port open; device not found or not yet detected |
| `.portBusy` | Port found but `open()` returned EBUSY (e.g., Bazecor connected) |
| `.error(String)` | Other error with message |

---

## State Transitions

```
App Launch
    └─► Load config
            ├─► runtime.enabled = true  → DeviceDiscovery → connected / portBusy / disconnected
            └─► runtime.enabled = false → disconnected (port not opened)

User toggles Enabled ON
    └─► DeviceDiscovery → open port → Focus probe
            ├─► success → connected; apply mapping for current frontmost app
            └─► failure → portBusy or error; backoff retry (1s→30s cap)

User toggles Enabled OFF
    └─► Close serial port → disconnected; stop applying mappings

App activation event (NSWorkspace notification)
    └─► Debounce (150ms)
            └─► Lookup bundleId in mappings
                    ├─► match found    → partial apply profile fields (non-destructive)
                    └─► no match      → apply default profile fields (non-destructive)
                            └─► same layer already active? → skip (idempotent)

USB device removed (IOKit / ORSSerialPort callback)
    └─► connectionStatus = .disconnected; backoff retry

USB device attached (IOKit notification)
    └─► if enabled → cancel backoff → DeviceDiscovery → reconnect

App quits
    └─► Serial port closed (OS reclaims); no keyboard state change
```

---

## Config File Location

Resolved at runtime, never hardcoded:

```
~/Library/Application Support/DygmaContext/config.json
```

Via: `FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("DygmaContext/config.json")`

## Log File Location

```
~/Library/Logs/DygmaContext/dygma-context.log
```

Via: `FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0].appendingPathComponent("Logs/DygmaContext/")`
