# Contract: Dygma Focus API

**Version**: v1 (Dygma Defy firmware)
**Transport**: USB serial, 115200 baud, 8N1
**Library**: ORSSerialPort

---

## Wire Protocol

### Request

Plain ASCII text followed by a newline:

```
<command>\n
```

Example: `layer.moveTo 2\n`

### Response

One or more ASCII lines terminated by a line containing exactly `.` followed by a newline:

```
<line1>\n
<line2>\n
.\n
```

Single-value example (`layer.moveTo 2`):
```
.\n
```
(empty response body — command acknowledged)

Multi-line example (`help`):
```
layer.moveTo\n
led.brightness\n
led.theme\n
keymap.default\n
.\n
```

### Error Response

Response body begins with `ERR_`:

```
ERR_UNKNOWN_COMMAND\n
.\n
```

---

## Device Identification (Probe)

Send `help\n`. A Dygma Defy is identified when the response contains at least one of:
- `layer.moveTo`
- `keymap.default`

This probe is non-destructive and safe to send to any serial device.

---

## Commands Used by This Application

### `help`

List all supported commands.

**Usage**: Device discovery probe; sent once at connection time.

**Response**: Newline-separated list of command names, terminated by `.`

---

### `layer.moveTo N`

Switch to layer N.

**Parameters**:
- `N`: Integer 0–9 (firmware supports up to 10 layers)

**Response**: Empty (acknowledged by `.` only)

**Conditions**: Only sent when `N` differs from the last applied layer (idempotency check).

---

### `led.brightness N`

Set LED brightness.

**Parameters**:
- `N`: Integer (range defined by firmware; not validated by this application in v1)

**Response**: Empty (acknowledged by `.` only)

**Conditions**: Only sent when a mapping or default profile explicitly specifies `ledBrightness`.

---

### `led.theme <name>`

Set LED theme by name.

**Parameters**:
- `<name>`: Opaque string matching a theme name stored on the keyboard. Not validated by this application.

**Response**: Empty or `ERR_` if theme not found.

**Conditions**: Only sent when a mapping or default profile explicitly specifies `ledTheme`.

---

## Timeout & Error Handling

| Scenario | Behaviour |
|---|---|
| No response within **2 seconds** | Command declared failed; error state triggered |
| Response begins with `ERR_` | Logged as warning; UI not changed unless repeated failures |
| Port returns EBUSY on open | `connectionStatus = .portBusy`; backoff retry |
| Port removed mid-session | `serialPortWasRemovedFromSystem:` fires; `connectionStatus = .disconnected`; backoff retry |

---

## Backoff Sequence

On connection failure or timeout, retry with exponential backoff:

```
1s → 2s → 4s → 8s → 16s → 30s (cap)
```

Once the 30s cap is reached, the app settles into stable `.disconnected` state. Auto-reconnect resumes immediately when an IOKit USB attach notification is received.

---

## Non-Destructive Partial Apply

Only commands for explicitly configured fields are sent per mapping switch. If a mapping specifies only `layer`, only `layer.moveTo N` is sent. LED state is not touched. This preserves any LED configuration set externally (e.g., by Bazecor).
