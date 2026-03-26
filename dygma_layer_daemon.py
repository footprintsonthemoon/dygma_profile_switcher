#!/usr/bin/env python3
import time
import subprocess
from typing import Optional

# Dygma Layer Daemon: Wechselt die Dygma-Layer automatisch je nach aktivem Programm. Dies ist mein Proof of Concept, um die Dygma-API zu nutzen. Es ist kein offizielles Dygma-Produkt, sondern ein kleines Skript, das ich für mich selbst geschrieben habe. Es könnte Fehler enthalten und ist nicht für die breite Öffentlichkeit gedacht. Verwende es auf eigene Gefahr und passe es an deine Bedürfnisse an.

import serial  # pip3 install --user pyserial

PORT = "/dev/cu.usbmodem8301"
BAUD = 115200

# App-Name (wie macOS ihn meldet) -> Layer-Nummer
APP_TO_LAYER = {
    "Dorico 6": 2,
    # Beispiele:
    # "Visual Studio Code": 1,
    # "Terminal": 2,
    # "Google Chrome": 0,
}

POLL_INTERVAL_S = 0.30
DEFAULT_LAYER: Optional[int] = (
    None  # z.B. 0 setzen, wenn du bei "unbekannt" zurueck willst
)


def frontmost_app_name() -> str:
    # robust und schnell genug
    script = 'tell application "System Events" to get name of first application process whose frontmost is true'
    return subprocess.check_output(["osascript", "-e", script], text=True).strip()


class DygmaFocus:
    def __init__(self, port: str, baud: int):
        self.port = port
        self.baud = baud
        self.ser: Optional[serial.Serial] = None

    def open(self):
        self.ser = serial.Serial(self.port, self.baud, timeout=0.4)
        time.sleep(0.15)
        try:
            self.ser.reset_input_buffer()
        except Exception:
            pass

    def close(self):
        if self.ser:
            try:
                self.ser.close()
            finally:
                self.ser = None

    def cmd(self, s: str) -> bytes:
        if not self.ser:
            raise RuntimeError("Serial not open")
        self.ser.write((s.strip() + "\n").encode("utf-8"))
        self.ser.flush()
        time.sleep(0.05)
        return self.ser.read(4096)

    def move_to_layer(self, layer: int):
        self.cmd(f"layer.moveTo {layer}")


def main():
    focus = DygmaFocus(PORT, BAUD)

    last_app = None
    last_layer = None

    while True:
        try:
            if focus.ser is None:
                focus.open()

            app = frontmost_app_name()
            if app != last_app:
                layer = APP_TO_LAYER.get(app, DEFAULT_LAYER)

                if layer is not None and layer != last_layer:
                    focus.move_to_layer(layer)
                    last_layer = layer

                last_app = app

            time.sleep(POLL_INTERVAL_S)

        except serial.SerialException:
            # Device kurz weg, reconnect spaeter
            focus.close()
            time.sleep(1.0)
        except Exception:
            # keine Endlosschleife mit CPU-Spike
            time.sleep(0.5)


if __name__ == "__main__":
    main()
