# DygmaContextSwitcher

A native macOS menu bar app that automatically switches your [Dygma Defy](https://dygma.com/products/dygma-defy) keyboard layer based on the active foreground application — silently, within milliseconds, without any manual input.

Switch to Dorico and your keyboard moves to your music layer. Switch to Terminal and it moves to your coding layer. Switch back to your browser and it returns to default. You never touch the keyboard layers manually again.

![macOS 13+](https://img.shields.io/badge/macOS-13%2B-blue)
![Swift 5.9](https://img.shields.io/badge/Swift-5.9-orange)
![License: MIT](https://img.shields.io/badge/License-MIT-green)

---

## Features

- **Automatic layer switching** — reacts to `NSWorkspace` app-activation events, no polling
- **Debounced** — waits 150ms before applying so rapid app switches don't flood the keyboard
- **Idempotent** — skips the command if the requested layer is already active
- **Non-destructive partial apply** — only sends the commands you've configured; unset fields (LED theme, brightness) are left as-is
- **LED brightness per mapping** — optionally override brightness for each app
- **Auto-detect keyboard** — finds the Dygma Defy on USB automatically via IOKit + Focus API probe
- **Hotplug reconnect** — reconnects automatically when you replug the keyboard, with exponential backoff
- **Bazecor-friendly** — releases the serial port when disabled so Bazecor can connect; re-acquires on re-enable
- **Menu bar icon** — three visual states: connected (green dot), error/busy (orange dot), disabled (dimmed)
- **Status submenu** — shows current port, last active app, last applied layer
- **Start at Login** — uses modern `SMAppService` API (macOS 13+)
- **Portable config** — JSON file in `~/Library/Application Support/DygmaContext/config.json`; copy it to another Mac and everything works
- **No Dock icon** — runs as a background agent (menu bar only)
- **Structured logging** — writes to `~/Library/Logs/DygmaContext/`; viewable and exportable from the Settings window

---

## Requirements

| Requirement | Details |
|---|---|
| macOS | 13.0 Ventura or later |
| Keyboard | Dygma Defy (USB connection) |
| Connection | USB only — the Focus API does not operate over Bluetooth or 2.4GHz RF |
| Xcode | 15 or later (to build from source) |

---

## Installation

### Pre-built (recommended)

1. Download `DygmaContextSwitcher.app.zip` from the [latest release](../../releases/latest)
2. Unzip and drag `DygmaContextSwitcher.app` to your `/Applications` folder
3. Launch it — the keyboard icon appears in your menu bar

On first launch, macOS may show a Gatekeeper warning. To allow it:

```
System Settings → Privacy & Security → scroll down → "Open Anyway"
```

### Build from source

See [Building from Source](#building-from-source) below.

---

## Quick Start

1. **Connect your Dygma Defy via USB**
2. **Launch the app** — it auto-detects the keyboard and shows a green dot in the menu bar
3. **Open Settings** from the menu bar icon → **Mappings** tab
4. **Click "Add App"** — pick a running app or browse installed apps
5. **Set the layer** (1–10, displayed as Bazecor numbers) and optionally a brightness
6. **Switch to that app** — the keyboard layer changes automatically

> **Layer numbering**: Layers are shown 1-based in the UI (matching Bazecor), stored 0-based internally.

---

## Settings Window

### Status Tab
Shows live connection state, current active app, and the resolved layer and brightness being applied.

### Mappings Tab
Add, edit, and remove app-to-layer mappings. Each mapping has:
- **App** — selected via picker (running apps or installed .app bundles); bundle ID captured automatically
- **Layer** — stepper, 1–10 (Bazecor numbering)
- **Brightness** — stepper, 0–255 (optional override)
- **Test** button — applies the mapping immediately without switching apps

### Device Tab
- **Auto-detect toggle** — finds the keyboard automatically on startup and replug
- **Manual port path** — enter `/dev/cu.usbmodem…` if auto-detect is off
- **Re-detect Keyboard** — triggers an immediate discovery scan

### Logs Tab
Tail of the last 200 log lines. Export button saves the full log to a file.

---

## Configuration File

Located at `~/Library/Application Support/DygmaContext/config.json`. Human-readable JSON — you can edit it directly or copy it between Macs.

```json
{
  "version": 1,
  "device": {
    "autoDetect": true,
    "serial": {
      "portPath": "/dev/cu.usbmodem8301",
      "baudRate": 115200
    }
  },
  "defaults": {
    "layer": 0,
    "ledBrightness": 110,
    "debounceMs": 150
  },
  "mappings": [
    {
      "id": "…",
      "bundleIdentifier": "com.steinberg.dorico5",
      "displayName": "Dorico 6",
      "profile": {
        "layer": 2,
        "ledBrightness": 140
      }
    }
  ],
  "runtime": {
    "enabled": true,
    "closePortWhenDisabled": true
  },
  "logging": {
    "level": "info",
    "path": "~/Library/Logs/DygmaContext/"
  }
}
```

**To transfer settings to another Mac**: copy the file to `~/Library/Application Support/DygmaContext/config.json` on the new machine. All mappings and preferences are preserved — no code changes required.

---

## Tests

### Running the tests

```bash
make test
```

All 25 tests should pass with no failures.

### Test suites

| Suite | Tests | What is covered |
|---|---|---|
| `ConfigStoreTests` | 6 | Load from missing file returns defaults; save/load roundtrip; corrupt JSON falls back to defaults; out-of-range layer rejected on load; all-nil mapping profile rejected; config path never contains unexpanded `~` |
| `MappingLookupTests` | 8 | Bundle ID hit returns correct layer and brightness; miss returns default layer and brightness; idempotency skip when same layer already active; idempotency not triggered on different layer; partial mapping (layer only) falls back to default brightness; `recordApplied` updates cache; `resetCache` clears state; nil layer in mapping stays nil |
| `FocusAPIClientTests` | 7 | Focus API command string format; probe response detection (`layer.moveTo` marker); response terminator parsing (`\n.\n`); `ERR_` prefix detection; partial apply only sends non-nil fields; backoff sequence correctness (1→2→4→8→16→30); `MockSerialPort` records sent data, throws when busy, throws when not open |
| `AppEventMonitorTests` | 4 | Rapid events within debounce window produce exactly one callback for the last app; single event after debounce fires correctly; bundle ID extracted correctly from notification |

### Coverage

The test suite covers the **core logic layer** — the components that have no UI or hardware dependency and can be tested deterministically:

| Layer | Approach | Source lines |
|---|---|---|
| Config (load/save/validate) | Unit tests with temp files | ~102 |
| Mapping lookup + idempotency | Unit tests, pure logic | ~56 |
| Focus API protocol + parsing | Unit tests with `MockSerialPort` | ~61 |
| App event debounce | Unit tests with synthetic `NSWorkspace` notifications | ~59 |
| **Tested subtotal** | | **~278 lines** |
| Serial hardware (`SerialPortActor`, `DeviceDiscovery`) | Not tested — requires physical USB device | ~274 lines |
| UI (`SwiftUI` views, `MenuBarController`) | Not tested — requires running app | ~793 lines |
| Orchestration (`ProfileSwitcher`, `AppDelegate`) | Not tested — integration concerns | ~229 lines |
| **Total source** | | **~1,828 lines** |

**Unit test coverage: ~15% of total lines, ~100% of testable pure-logic code.**

The untested layers (serial hardware, UI, orchestration) are validated manually via the running app. Hardware-dependent code cannot be usefully unit-tested without a physical Dygma Defy connected.

---

## Building from Source

### Prerequisites

- Xcode 15 or later
- macOS 13 SDK
- `make` (included with Xcode Command Line Tools)

### Clone and build

```bash
git clone https://github.com/footprintsonthemoon/dygma-context-switcher.git
cd dygma-context-switcher
make build
```

### Run from build directory

```bash
make run
```

### Build Release and install to /Applications

```bash
make install
```

### Run tests

```bash
make test
```

### Other make targets

| Target | Description |
|---|---|
| `make build` | Debug build |
| `make release` | Release build (no install) |
| `make install` | Release build + copy to `/Applications` |
| `make run` | Debug build + launch |
| `make test` | Run unit test suite |
| `make clean` | Remove build artifacts |
| `make open` | Open project in Xcode |

### Dependencies

[ORSSerialPort](https://github.com/armadsen/ORSSerialPort) is fetched automatically via Swift Package Manager when you open the project or run `make build`.

---

## How It Works

1. `AppEventMonitor` subscribes to `NSWorkspace.didActivateApplicationNotification`
2. Events are debounced (150ms default) via a cancel-and-reschedule `DispatchWorkItem`
3. `MappingLookup` resolves the bundle ID to a layer + optional LED settings, falling back to defaults for unmapped apps
4. If the resolved layer differs from the last-applied layer (idempotency check), `FocusAPIClient` sends `layer.moveTo N` over a POSIX serial connection to the keyboard
5. `DeviceDiscovery` uses IOKit to enumerate USB serial devices, probes each with `version\n`, and identifies the Dygma Defy by its response
6. Hotplug events (USB attach/detach) are delivered via `IOServiceAddMatchingNotification` — no polling

The serial port uses POSIX `open()`/`tcsetattr()` directly with `DispatchSource.makeReadSource` for async reads, bridged into Swift concurrency via `withCheckedThrowingContinuation`. Each Focus API command has a 2-second timeout.

---

## Coexistence with Bazecor

DygmaContextSwitcher and Bazecor **cannot run simultaneously** — the USB serial port can only be held by one application at a time.

To use Bazecor:
1. Click the menu bar icon → toggle **Enabled** off — the app releases the port immediately
2. Open and use Bazecor normally
3. Quit Bazecor, then toggle **Enabled** back on — the app reconnects automatically

> If you forget to disable the switcher first, Bazecor will show a connection error. Just toggle Enabled off and try again.

---

## Limitations

- **USB only** — the Dygma Focus API operates exclusively over USB serial. Bluetooth and 2.4GHz RF are not supported because there is no programmatic interface to the keyboard over these transports.
- **Single keyboard** — one Dygma Defy at a time. Multi-device support is out of scope for v1.
- **No LED theme switching** — `led.theme` is not implemented. Layer and brightness are the supported profile fields.
- **No Accessibility permission required** — the app does not use any Accessibility APIs.

---

## Contributing

Pull requests welcome. Please:

1. Fork the repository
2. Create a branch: `git checkout -b my-feature`
3. Make your changes and add tests where appropriate
4. Run `make test` to verify
5. Open a pull request

For significant changes, open an issue first to discuss the approach.

---

## License

MIT License — see [LICENSE](LICENSE) for details.

You are free to use, modify, and distribute this software for any purpose, including commercial use, with no obligation beyond preserving the copyright notice.
