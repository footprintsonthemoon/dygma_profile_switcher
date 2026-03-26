# Quickstart: Dygma Context Switcher for macOS

**Prerequisites**: macOS 13 (Ventura) or later, Xcode 15+, Dygma Defy connected via USB.

---

## 1. Clone & Open

```bash
git clone <repo-url>
cd dygma_profile_switcher
open DygmaContextSwitcher.xcodeproj
```

## 2. Add ORSSerialPort Dependency

In Xcode: **File → Add Package Dependencies…**
- URL: `https://github.com/armadsen/ORSSerialPort`
- Version: Up Next Major from `2.1.0`
- Target: `DygmaContextSwitcher`

## 3. Build & Run

Select scheme **DygmaContextSwitcher** → target **My Mac** → press **⌘R**.

The app starts in the background — look for the keyboard icon in the menu bar (no Dock icon).

## 4. First-Time Setup

1. Click the menu bar icon → **Open Settings…**
2. Go to the **Device** tab → click **Re-detect Keyboard** (or toggle Auto-detect on)
3. If found, status shows the port path and "Connected"
4. Go to **Mappings** tab → click **Add App**
5. Select an app from the running apps list (or click "Browse…" to pick from `/Applications`)
6. Set Layer (0–9) and optionally LED brightness
7. Click **Save** — the mapping is active immediately

## 5. Test a Mapping

On the **Mappings** tab, click the **Test** button next to a mapping. The keyboard switches to that layer immediately.

## 6. Enable Start at Login

Menu bar icon → **Start at Login** (toggle on). The app will launch automatically on next login.

---

## Config File Location

```
~/Library/Application Support/DygmaContext/config.json
```

Copy this file to another Mac to transfer all mappings without reinstalling.

## Log File Location

```
~/Library/Logs/DygmaContext/dygma-context.log
```

View live in Settings → **Logs** tab, or export from there.

---

## Coexistence with Bazecor

When you need Bazecor to access the keyboard:

1. Menu bar icon → uncheck **Enabled**
2. The serial port is released immediately
3. Open Bazecor — it can now connect
4. When done, re-enable from the menu bar

---

## Running Tests

```bash
# In Xcode: ⌘U
# Or from terminal:
xcodebuild test -scheme DygmaContextSwitcher -destination 'platform=macOS'
```
