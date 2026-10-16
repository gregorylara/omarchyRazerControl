#!/usr/bin/env python3
"""
Razer Control CLI (razer_ctl.py)
Direct HID & Profile Controller for Razer Peripherals in Omarchy Shell
"""

import sys
import os
import glob
import json
import time
import struct
import time
import fcntl
import argparse
from pathlib import Path

# Paths
SCRIPT_DIR = Path(__file__).resolve().parent
STATE_DIR = Path.home() / ".local" / "state" / "omarchy" / "razer"
PROFILES_FILE = STATE_DIR / "profiles.json"
TEMPLATE_PROFILES_FILE = SCRIPT_DIR / "profiles.json"

# Razer USB Vendor ID
RAZER_VID = 0x1532

# Chroma LED zones (extended matrix LED IDs). Not every device has every zone;
# the connected device is probed to find which ones answer.
LED_ZONES = {
    "logo": 0x04,
    "scroll": 0x01,
    "underglow": 0x0A,
    "left": 0x11,
    "right": 0x10,
    "backlight": 0x05,
}
ZONE_ORDER = ["logo", "scroll", "underglow", "left", "right", "backlight"]
# Broadcast LED ID: one command updates every zone and keeps animations in phase
ALL_LEDS = 0x00

# Razer report status byte
STATUS_BUSY = 0x01
STATUS_OK = 0x02

# Known Razer Mouse Hardware Database (by USB Product ID)
# Fallback auto-probing is used automatically for any Razer PID not listed here.
DEVICE_DB = {
    # Viper Series
    0x0078: {"name": "Razer Viper", "tx_id": 0x1F, "max_dpi": 16000, "supports_8k": False, "profile_mode": "dpi_led"},
    0x007A: {"name": "Razer Viper Ultimate (Wired)", "tx_id": 0x3F, "max_dpi": 20000, "supports_8k": False, "profile_mode": "dpi_led"},
    0x007B: {"name": "Razer Viper Ultimate (Wireless)", "tx_id": 0x3F, "max_dpi": 20000, "supports_8k": False, "profile_mode": "dpi_led", "is_dongle": True},
    0x008A: {"name": "Razer Viper Mini", "tx_id": 0x1F, "max_dpi": 8500, "supports_8k": False, "profile_mode": "dpi_led"},
    0x0091: {"name": "Razer Viper 8KHz", "tx_id": 0x1F, "max_dpi": 20000, "supports_8k": True, "profile_mode": "dpi_led"},
    0x00A5: {"name": "Razer Viper V2 Pro (Wired)", "tx_id": 0x1F, "max_dpi": 30000, "supports_8k": True, "profile_mode": "dpi_led"},
    0x00A6: {"name": "Razer Viper V2 Pro (Wireless)", "tx_id": 0x1F, "max_dpi": 30000, "supports_8k": True, "profile_mode": "dpi_led", "is_dongle": True},
    0x00B6: {"name": "Razer Viper V3 Pro (Wired)", "tx_id": 0x1F, "max_dpi": 35000, "supports_8k": True, "profile_mode": "dpi_led"},
    0x00B7: {"name": "Razer Viper V3 Pro (Wireless)", "tx_id": 0x1F, "max_dpi": 35000, "supports_8k": True, "profile_mode": "dpi_led", "is_dongle": True},
    0x00B8: {"name": "Razer Viper V3 HyperSpeed", "tx_id": 0x1F, "max_dpi": 30000, "supports_8k": True, "profile_mode": "dpi_led", "is_dongle": True},
    # DeathAdder Series
    0x006E: {"name": "Razer DeathAdder Essential", "tx_id": 0x1F, "max_dpi": 6400, "supports_8k": False, "profile_mode": "dpi_led"},
    0x0084: {"name": "Razer DeathAdder V2", "tx_id": 0x1F, "max_dpi": 20000, "supports_8k": False, "profile_mode": "onboard_slot"},
    0x007C: {"name": "Razer DeathAdder V2 Pro (Wired)", "tx_id": 0x3F, "max_dpi": 20000, "supports_8k": False, "profile_mode": "onboard_slot"},
    0x007D: {"name": "Razer DeathAdder V2 Pro (Wireless)", "tx_id": 0x3F, "max_dpi": 20000, "supports_8k": False, "profile_mode": "onboard_slot", "is_dongle": True},
    0x008C: {"name": "Razer DeathAdder V2 Mini", "tx_id": 0x1F, "max_dpi": 8500, "supports_8k": False, "profile_mode": "dpi_led"},
    0x00B2: {"name": "Razer DeathAdder V3", "tx_id": 0x1F, "max_dpi": 30000, "supports_8k": True, "profile_mode": "dpi_led"},
    0x00A7: {"name": "Razer DeathAdder V3 Pro (Wired)", "tx_id": 0x1F, "max_dpi": 30000, "supports_8k": True, "profile_mode": "dpi_led"},
    0x00A8: {"name": "Razer DeathAdder V3 Pro (Wireless)", "tx_id": 0x1F, "max_dpi": 30000, "supports_8k": True, "profile_mode": "dpi_led", "is_dongle": True},
    # Basilisk Series
    0x0085: {"name": "Razer Basilisk V2", "tx_id": 0x1F, "max_dpi": 20000, "supports_8k": False, "profile_mode": "onboard_slot"},
    0x0086: {"name": "Razer Basilisk Ultimate (Wired)", "tx_id": 0x3F, "max_dpi": 20000, "supports_8k": False, "profile_mode": "onboard_slot"},
    0x0088: {"name": "Razer Basilisk Ultimate (Wireless)", "tx_id": 0x3F, "max_dpi": 20000, "supports_8k": False, "profile_mode": "onboard_slot", "is_dongle": True},
    0x0099: {"name": "Razer Basilisk V3", "tx_id": 0x1F, "max_dpi": 26000, "supports_8k": False, "profile_mode": "onboard_slot"},
    0x00AA: {"name": "Razer Basilisk V3 Pro (Wired)", "tx_id": 0x1F, "max_dpi": 30000, "supports_8k": True, "profile_mode": "onboard_slot"},
    0x00AB: {"name": "Razer Basilisk V3 Pro (Wireless)", "tx_id": 0x1F, "max_dpi": 30000, "supports_8k": True, "profile_mode": "onboard_slot", "is_dongle": True},
    # Naga, Cobra, Mamba, Orochi Series
    0x008F: {"name": "Razer Naga Pro (Wired)", "tx_id": 0x1F, "max_dpi": 20000, "supports_8k": False, "profile_mode": "onboard_slot"},
    0x0090: {"name": "Razer Naga Pro (Wireless)", "tx_id": 0x1F, "max_dpi": 20000, "supports_8k": False, "profile_mode": "onboard_slot", "is_dongle": True},
    0x0096: {"name": "Razer Naga X", "tx_id": 0x1F, "max_dpi": 18000, "supports_8k": False, "profile_mode": "dpi_led"},
    0x00A9: {"name": "Razer Cobra", "tx_id": 0x1F, "max_dpi": 8500, "supports_8k": False, "profile_mode": "dpi_led"},
    0x00AC: {"name": "Razer Cobra Pro", "tx_id": 0x1F, "max_dpi": 30000, "supports_8k": True, "profile_mode": "onboard_slot"},
    0x006C: {"name": "Razer Mamba Elite", "tx_id": 0x1F, "max_dpi": 16000, "supports_8k": False, "profile_mode": "onboard_slot"},
    0x0094: {"name": "Razer Orochi V2", "tx_id": 0x3F, "max_dpi": 18000, "supports_8k": False, "profile_mode": "dpi_led", "is_dongle": True},
}

# Wireless PIDs whose *dongle* interface keeps answering with stale data while
# the cable is in; when both wired and dongle are present the wired node wins.
WIRELESS_DONGLE_PIDS = {pid for pid, meta in DEVICE_DB.items() if meta.get("is_dongle")}

# Response handling: the device answers asynchronously, and until it does the
# feature report still holds our own request with status 0x01 (BUSY --
# razercommon.h: BUSY 0x01, SUCCESSFUL 0x02, FAILURE 0x03, TIMEOUT 0x04,
# NOT_SUPPORTED 0x05).
RAZER_STATUS_BUSY = 0x01       # command accepted, device hasn't answered yet
RESPONSE_TIMEOUT_S = 0.3
RESPONSE_POLL_S = 0.005

# Linux HIDRAW IOCTL definitions
def _IOC(dir_, typ, nr, size):
    return (dir_ << 30) | (ord(typ) << 8) | nr | (size << 16)

IOC_READ = 2
IOC_WRITE = 1
HIDIOCSFEATURE_91 = _IOC(IOC_READ | IOC_WRITE, 'H', 0x06, 91)
HIDIOCGFEATURE_91 = _IOC(IOC_READ | IOC_WRITE, 'H', 0x07, 91)

# Default Profiles
DEFAULT_PROFILES_DATA = {
    "activeProfile": "onboard-3",
    "profiles": [
        {
            "id": "onboard-1",
            "name": "Profile 1 (Default / Yellow)",
            "isOnboard": True,
            "onboardSlot": 1,
            "badgeColor": "#FFFF00",
            "dpi": 2400,
            "dpi_stages": [2400, 3400, 4800, 5000, 5200],
            "active_stage": 1,
            "poll_rate": 8000,
            "brightness": 100,
            "effect": "static",
            "effect_color": "#FFFF00"
        },
        {
            "id": "onboard-2",
            "name": "Profile 2 (FPS Ultra / Red)",
            "isOnboard": True,
            "onboardSlot": 2,
            "badgeColor": "#FF0000",
            "dpi": 3400,
            "dpi_stages": [2400, 3400, 4800, 5000, 5200],
            "active_stage": 2,
            "poll_rate": 8000,
            "brightness": 100,
            "effect": "static",
            "effect_color": "#FF0000"
        },
        {
            "id": "onboard-3",
            "name": "Profile 3 (MOBA / Green)",
            "isOnboard": True,
            "onboardSlot": 3,
            "badgeColor": "#00FF00",
            "dpi": 4800,
            "dpi_stages": [2400, 3400, 4800, 5000, 5200],
            "active_stage": 3,
            "poll_rate": 8000,
            "brightness": 100,
            "effect": "static",
            "effect_color": "#00FF00"
        },
        {
            "id": "onboard-4",
            "name": "Profile 4 (Productivity / Blue)",
            "isOnboard": True,
            "onboardSlot": 4,
            "badgeColor": "#0066FF",
            "dpi": 5000,
            "dpi_stages": [2400, 3400, 4800, 5000, 5200],
            "active_stage": 4,
            "poll_rate": 8000,
            "brightness": 100,
            "effect": "static",
            "effect_color": "#0066FF"
        },
        {
            "id": "onboard-5",
            "name": "Profile 5 (Stealth / Cyan)",
            "isOnboard": True,
            "onboardSlot": 5,
            "badgeColor": "#00FFFF",
            "dpi": 5200,
            "dpi_stages": [2400, 3400, 4800, 5000, 5200],
            "active_stage": 5,
            "poll_rate": 8000,
            "brightness": 100,
            "effect": "static",
            "effect_color": "#00FFFF"
        }
    ]
}

class RazerDeviceManager:
    def __init__(self):
        self.device_info = None
        self.hidraw_path = None
        self.has_permission = False
        self.fd = None
        self._led_zones = None
        self._detect_device()

    def _detect_device(self):
        """Find Razer devices connected to the system."""
        candidates = []
        for path in sorted(glob.glob("/sys/class/hidraw/hidraw*")):
            try:
                uevent_file = os.path.join(path, "device", "uevent")
                if not os.path.isfile(uevent_file):
                    continue
                with open(uevent_file, "r") as f:
                    content = f.read()

                # Check HID_ID: bus:vid:pid
                # e.g. HID_ID=0003:00001532:00000091
                vid = None
                pid = None
                name = "Razer Device"
                for line in content.splitlines():
                    if line.startswith("HID_ID="):
                        parts = line.split("=")[1].split(":")
                        if len(parts) >= 3:
                            vid = int(parts[1], 16)
                            pid = int(parts[2], 16)
                    elif line.startswith("HID_NAME="):
                        name = line.split("=", 1)[1].strip()

                if vid == RAZER_VID:
                    dev_node = os.path.join("/dev", os.path.basename(path))
                    # Clean up repeated Razer in device name
                    clean_name = name.strip()
                    if clean_name.startswith("Razer Razer"):
                        clean_name = "Razer " + clean_name[11:].strip()
                    elif not clean_name.startswith("Razer"):
                        clean_name = "Razer " + clean_name

                    # Check interface number
                    interface = 0
                    try:
                        dev_path = os.path.realpath(path)
                        # Look for :X.interface/ in path
                        for part in dev_path.split("/"):
                            if "." in part and ":" in part:
                                sub = part.split(".")[-1]
                                if sub.isdigit():
                                    interface = int(sub)
                    except Exception:
                        pass

                    candidates.append({
                        "node": dev_node,
                        "sysfs": path,
                        "name": clean_name,
                        "vid": vid,
                        "pid": pid,
                        "interface": interface
                    })
            except Exception:
                continue

        if not candidates:
            # Check lsusb fallback
            self.device_info = {
                "connected": False,
                "name": "No Razer Device Detected",
                "pid": 0,
                "vid": RAZER_VID,
                "path": None,
                "has_permission": False
            }
            return

        # Sort candidates: prefer interface 0 or highest feature support
        # Usually interface 0 or 2 has feature report capabilities
        # A wireless Razer mouse exposes a second, wired PID while the cable is
        # in, and that interface is the live one: the dongle's battery report
        # parks at 0 (measured on the Naga Pro -- charge_level fell 12 -> 0 on
        # the dongle node while the wired node was connected). Prefer wired.
        candidates.sort(key=lambda c: c["pid"] in WIRELESS_DONGLE_PIDS)
        best = candidates[0]
        accessible = None
        for c in candidates:
            if os.access(c["node"], os.R_OK | os.W_OK):
                accessible = c
                break

        chosen = accessible if accessible else best
        self.hidraw_path = chosen["node"]
        self.has_permission = os.access(self.hidraw_path, os.R_OK | os.W_OK)
        meta = DEVICE_DB.get(chosen["pid"], {})
        self.device_info = {
            "connected": True,
            "name": meta.get("name", chosen["name"]),
            "pid": chosen["pid"],
            "vid": chosen["vid"],
            "path": self.hidraw_path,
            "has_permission": self.has_permission,
            "interface": chosen["interface"],
            "tx_id": meta.get("tx_id", 0x1F),
            "max_dpi": meta.get("max_dpi", 30000),
            "supports_8k": meta.get("supports_8k", False),
            "profile_mode": meta.get("profile_mode", "dpi_led"),
            "in_db": chosen["pid"] in DEVICE_DB,
        }

    def open_device(self):
        if not self.device_info or not self.device_info["connected"]:
            return False
        if not self.has_permission:
            return False
        try:
            self.fd = os.open(self.hidraw_path, os.O_RDWR)
            try:
                fcntl.flock(self.fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except (BlockingIOError, OSError):
                fcntl.flock(self.fd, fcntl.LOCK_EX)
            return True
        except Exception:
            self.fd = None
            return False

    def close_device(self):
        if self.fd is not None:
            try:
                fcntl.flock(self.fd, fcntl.LOCK_UN)
            except Exception:
                pass
            try:
                os.close(self.fd)
            except Exception:
                pass
            self.fd = None

    def _build_report(self, command_class, command_id, data_size, arguments, transaction_id=0x1f):
        """Construct standard 90-byte Razer HID feature report."""
        report = bytearray(90)
        report[0] = 0x00  # Status NEW
        report[1] = transaction_id
        report[2] = 0x00  # Remaining packets MSB
        report[3] = 0x00  # Remaining packets LSB
        report[4] = 0x00  # Protocol type
        report[5] = data_size
        report[6] = command_class
        report[7] = command_id
        for i, b in enumerate(arguments[:80]):
            report[8 + i] = b

        # CRC: XOR sum from index 2 to 87 inclusive
        crc = 0
        for i in range(2, 88):
            crc ^= report[i]
        report[88] = crc
        report[89] = 0x00
        return report

    def _send_recv_once(self, command_class, command_id, data_size, arguments, transaction_id):
        report = self._build_report(command_class, command_id, data_size, arguments, transaction_id)
        buf = bytearray(1 + len(report))
        buf[0] = 0x00
        buf[1:] = report

        try:
            fcntl.ioctl(self.fd, HIDIOCSFEATURE_91, bytes(buf))
        except Exception:
            return None

        deadline = time.monotonic() + RESPONSE_TIMEOUT_S
        while True:
            recv_buf = bytearray(91)
            recv_buf[0] = 0x00
            try:
                fcntl.ioctl(self.fd, HIDIOCGFEATURE_91, recv_buf)
            except Exception:
                return None
            resp = recv_buf[1:]
            if resp[0] != RAZER_STATUS_BUSY or time.monotonic() >= deadline:
                return resp
            time.sleep(RESPONSE_POLL_S)

    def send_recv_report(self, command_class, command_id, data_size, arguments, transaction_id=None):
        """Send 90-byte feature report and receive response (with automatic tx_id fallback for unknown mice)."""
        if self.fd is None:
            if not self.open_device():
                return None

        tx = transaction_id if transaction_id is not None else (self.device_info.get("tx_id", 0x1F) if self.device_info else 0x1F)
        resp = self._send_recv_once(command_class, command_id, data_size, arguments, tx)

        # If this mouse is not in DEVICE_DB and the default tx_id timed out (0x04), try 0x3F / 0xFF
        if transaction_id is None and self.device_info and not self.device_info.get("in_db") and resp and resp[0] == 0x04:
            for alt_tx in (0x1F, 0x3F, 0xFF):
                if alt_tx == tx:
                    continue
                alt_resp = self._send_recv_once(command_class, command_id, data_size, arguments, alt_tx)
                if alt_resp and alt_resp[0] == STATUS_OK:
                    self.device_info["tx_id"] = alt_tx
                    self.device_info["in_db"] = True
                    return alt_resp
        return resp

    def hw_probe_capabilities(self):
        """Dynamically probe 8KHz support and bottom button mode for unknown Razer mice."""
        if not self.device_info or not self.has_permission:
            return
        if not self.device_info.get("in_db"):
            # Probe 8000 Hz HyperPolling support (0x00, 0xC0 GET_POLLING_RATE_2)
            r_8k = self.send_recv_report(0x00, 0xC0, 2, b"\x00\x00")
            if r_8k and r_8k[0] == STATUS_OK and r_8k[9] in (0x01, 0x02, 0x04, 0x08, 0x10, 0x40):
                self.device_info["supports_8k"] = True
            # Probe bottom button assignment (0x02, 0x8C button 96): 0x06 = DPI Cycle, 0x07 = Profile Cycle
            r_btn = self.send_recv_report(0x02, 0x8C, 10, struct.pack(">BBB", 0x01, 96, 0x00) + bytes(7))
            if r_btn and r_btn[0] == STATUS_OK and len(r_btn) > 12:
                if r_btn[11] == 0x07:
                    self.device_info["profile_mode"] = "onboard_slot"
                elif r_btn[11] == 0x06:
                    self.device_info["profile_mode"] = "dpi_led"

    # Hardware Control Methods
    def hw_set_dpi(self, dpi_x, dpi_y=None, profile_slot=0):
        if dpi_y is None:
            dpi_y = dpi_x
        max_dpi = self.device_info.get("max_dpi", 30000) if self.device_info else 30000
        dpi_x = max(100, min(max_dpi, int(dpi_x)))
        dpi_y = max(100, min(max_dpi, int(dpi_y)))
        # Command 0x04, 0x05 (SET_DPI_XY)
        # arg[0] = profile_slot (0=direct, 1..5=onboard)
        # arg[1..2] = dpi_x (big-endian)
        # arg[3..4] = dpi_y (big-endian)
        args = struct.pack(">BHHxx", profile_slot, dpi_x, dpi_y)
        return self.send_recv_report(0x04, 0x05, 7, args)

    def hw_get_dpi(self, profile_slot=0):
        # Command 0x04, 0x85 (GET_DPI_XY)
        args = struct.pack(">B", profile_slot)
        resp = self.send_recv_report(0x04, 0x85, 7, args)
        if resp and len(resp) >= 15:
            # Arguments start at index 8
            # resp[8] is profile, resp[9..10] is dpi_x, resp[11..12] is dpi_y
            try:
                prof, dx, dy = struct.unpack(">BHHxx", resp[8:15])
                return dx, dy
            except Exception:
                pass
        return None

    def hw_get_bottom_led_index(self, profile_slot=0):
        """Read active bottom LED color index (1=Red, 2=Green, 3=Blue, 4=Cyan, 5=Yellow) via 0x04, 0x86."""
        resp = self.send_recv_report(0x04, 0x86, 38, struct.pack(">B", profile_slot))
        if resp and resp[0] == STATUS_OK and len(resp) > 9:
            idx = int(resp[9])
            if 1 <= idx <= 5:
                return idx
        return None

    def hw_get_active_profile(self):
        """Read active onboard profile slot (1..5) from physical mouse button (Class 0x05, Cmd 0x84)."""
        resp = self.send_recv_report(0x05, 0x84, 1, b"\x00")
        if resp and resp[0] == STATUS_OK and len(resp) > 8:
            slot = int(resp[8])
            if 1 <= slot <= 5:
                return slot
        return None

    def hw_ensure_onboard_slots(self):
        """Ensure all 5 onboard profile slots (1..5) are allocated in flash."""
        resp = self.send_recv_report(0x05, 0x81, 6, bytes(6))
        if resp and resp[0] == STATUS_OK and len(resp) >= 14:
            allocated = set(resp[9:14])
            for s in (1, 2, 3, 4, 5):
                if s not in allocated:
                    self.send_recv_report(0x05, 0x02, 1, struct.pack(">B", s))
                    time.sleep(0.01)

    def hw_set_active_profile(self, slot):
        """Switch physical onboard profile slot (1..5) (Class 0x05, Cmd 0x04)."""
        slot = max(1, min(5, int(slot)))
        self.hw_ensure_onboard_slots()
        return self.send_recv_report(0x05, 0x04, 1, struct.pack(">B", slot))

    def hw_set_dpi_stages(self, stages, active_stage=1, profile_slot=0):
        """Set up to 5 DPI stages."""
        active_stage = max(1, min(len(stages), int(active_stage)))
        stages_data = bytearray()
        for i, val in enumerate(stages[:5]):
            stages_data.extend(struct.pack(">BHHxx", i + 1, val, val))
        # pad to 5 stages if fewer
        for i in range(len(stages), 5):
            stages_data.extend(struct.pack(">BHHxx", i + 1, 0, 0))

        args = struct.pack(">BBB", profile_slot, active_stage, len(stages[:5])) + stages_data
        return self.send_recv_report(0x04, 0x06, 3 + len(stages_data), args)

    def hw_set_polling_rate(self, rate_hz, profile_slot=0):
        rate_hz = int(rate_hz)
        is_8k = self.device_info.get("supports_8k", False)
        if is_8k:
            # Command 0x00, 0x40 (SET_POLLING_RATE_2)
            # 8000 -> 0x01, 4000 -> 0x02, 2000 -> 0x04, 1000 -> 0x08, 500 -> 0x10, 125 -> 0x40
            mapping = {
                8000: 0x01,
                4000: 0x02,
                2000: 0x04,
                1000: 0x08,
                500: 0x10,
                125: 0x40
            }
            code = mapping.get(rate_hz, 0x08)
            args = struct.pack(">BB", 0x00, code)
            return self.send_recv_report(0x00, 0x40, 2, args)
        else:
            # Standard: 0x00, 0x05
            mapping = {
                1000: 0x01,
                500: 0x02,
                125: 0x08
            }
            code = mapping.get(rate_hz, 0x01)
            args = struct.pack(">B", code)
            return self.send_recv_report(0x00, 0x05, 1, args)

    def hw_get_led_zones(self):
        """Return the lighting zones the device answers for, in ZONE_ORDER."""
        if self._led_zones is not None:
            return self._led_zones
        zones = []
        for zone in ZONE_ORDER:
            # Extended matrix get brightness: 0x0f, 0x84 [VARSTORE, led, 0]
            args = struct.pack(">BBB", 0x01, LED_ZONES[zone], 0x00)
            resp = self.send_recv_report(0x0f, 0x84, 3, args)
            if resp is not None and resp[0] == STATUS_BUSY:
                time.sleep(0.02)
                resp = self.send_recv_report(0x0f, 0x84, 3, args)
            if resp is not None and resp[0] == STATUS_OK:
                zones.append(zone)
        # Devices that do not answer the probe keep the original logo-only behaviour
        self._led_zones = zones or ["logo"]
        return self._led_zones

    def _for_zone(self, zone, send):
        """Run send(led_id) for one zone, or for every zone when zone is 'all'."""
        if zone != "all":
            return send(LED_ZONES.get(zone, LED_ZONES["logo"]))
        zones = self.hw_get_led_zones()
        if len(zones) == 1:
            return send(LED_ZONES[zones[0]])
        resp = send(ALL_LEDS)
        if resp is not None and resp[0] in (STATUS_OK, STATUS_BUSY):
            return resp
        # Device rejected the broadcast ID: address each zone instead
        for z in zones:
            resp = send(LED_ZONES[z])
        return resp

    def hw_get_battery(self):
        """Battery level, raw 0-255 (razer_chroma_misc_get_battery_level: 0x07/0x80).

        The kernel driver prints this raw value in sysfs charge_level; OpenRazer's
        own tools scale it with (raw / 255) * 100 (openrazer_daemon mamba.py).
        """
        resp = self.send_recv_report(0x07, 0x80, 2, struct.pack(">BB", 0x00, 0x00))
        if resp and resp[0] == 0x02 and len(resp) > 9:
            return resp[9]
        return None

    def hw_get_charging(self):
        """1 while charging, 0 otherwise (razer_chroma_misc_get_charging_status: 0x07/0x84)."""
        resp = self.send_recv_report(0x07, 0x84, 2, struct.pack(">BB", 0x00, 0x00))
        if resp and resp[0] == 0x02 and len(resp) > 9:
            return resp[9] != 0
        return None

    def hw_set_brightness(self, brightness, zone="logo"):
        # Brightness 0-100% -> 0-255
        val = int(max(0, min(100, brightness)) * 255 / 100)
        # Extended matrix brightness: 0x0f, 0x04 [VARSTORE, led, brightness]
        return self._for_zone(zone, lambda led: self.send_recv_report(0x0f, 0x04, 3, struct.pack(">BBB", 0x01, led, val)))

    def hw_set_effect(self, effect, hex_color="#00FF66", zone="logo"):
        return self._for_zone(zone, lambda led: self._send_effect(led, effect, hex_color))

    def _send_effect(self, led, effect, hex_color):
        """Set lighting effect: static, spectrum, breathing, off matching OpenRazer extended matrix."""
        # Convert hex to RGB
        hex_clean = hex_color.lstrip("#")
        if len(hex_clean) == 6:
            r, g, b = tuple(int(hex_clean[i:i+2], 16) for i in (0, 2, 4))
        else:
            r, g, b = (0, 255, 102)

        if effect == "off":
            # razer_chroma_extended_matrix_effect_none: 0x0f, 0x02, size 6: [0x01, led, 0x00, 0x00, 0x00, 0x00]
            args = struct.pack(">BBBBBB", 0x01, led, 0x00, 0x00, 0x00, 0x00)
            return self.send_recv_report(0x0f, 0x02, 6, args)
        elif effect == "spectrum":
            # razer_chroma_extended_matrix_effect_spectrum: 0x0f, 0x02, size 6: [0x01, led, 0x03, 0x00, 0x00, 0x00]
            args = struct.pack(">BBBBBB", 0x01, led, 0x03, 0x00, 0x00, 0x00)
            return self.send_recv_report(0x0f, 0x02, 6, args)
        elif effect == "breathing":
            # razer_chroma_extended_matrix_effect_breathing_single: 0x0f, 0x02, size 9: [0x01, led, 0x02, 0x01, 0x00, 0x01, r, g, b]
            args = struct.pack(">BBBBBBBBB", 0x01, led, 0x02, 0x01, 0x00, 0x01, r, g, b)
            return self.send_recv_report(0x0f, 0x02, 9, args)
        else:
            # razer_chroma_extended_matrix_effect_static: 0x0f, 0x02, size 9: [0x01, led, 0x01, 0x00, 0x00, 0x01, r, g, b]
            args = struct.pack(">BBBBBBBBB", 0x01, led, 0x01, 0x00, 0x00, 0x01, r, g, b)
            return self.send_recv_report(0x0f, 0x02, 9, args)


# Hardware bottom LED color index mapping on Razer mice (0x04, 0x06 / 0x04, 0x86):
#   1 = Red (#FF0000)    -> Slot 2 (P2)
#   2 = Green (#00FF00)  -> Slot 3 (P3)
#   3 = Blue (#0066FF)   -> Slot 4 (P4)
#   4 = Cyan (#00FFFF)   -> Slot 5 (P5)
#   5 = Yellow (#FFFF00) -> Slot 1 (P1)
SLOT_TO_BOTTOM_LED = {1: 5, 2: 1, 3: 2, 4: 3, 5: 4}
BOTTOM_LED_TO_SLOT = {5: 1, 1: 2, 2: 3, 3: 4, 4: 5}
COLOR_TO_BOTTOM_LED = {
    "#FF0000": 1,
    "#00FF00": 2,
    "#0066FF": 3,
    "#00FFFF": 4,
    "#FFFF00": 5,
    "#FFFFFF": 5,
}


def bottom_led_for_profile(profile):
    if not profile:
        return 2
    slot = int(profile.get("onboardSlot", 3))
    if slot in SLOT_TO_BOTTOM_LED:
        return SLOT_TO_BOTTOM_LED[slot]
    badge = str(profile.get("badgeColor", "")).upper()
    if badge in COLOR_TO_BOTTOM_LED:
        return COLOR_TO_BOTTOM_LED[badge]
    return 2


def profile_for_bottom_led(led_idx, profiles):
    target_slot = BOTTOM_LED_TO_SLOT.get(int(led_idx), 3)
    for p in profiles:
        if int(p.get("onboardSlot", 0)) == target_slot:
            return p
    return profiles[0] if profiles else None


def build_bottom_button_dpi_table(profiles):
    """Build the 5-stage hardware table [Red_DPI, Green_DPI, Blue_DPI, Cyan_DPI, Yellow_DPI]
    so pressing the physical bottom button immediately switches to each profile's active DPI."""
    table = [3400, 3400, 3400, 3400, 3400]
    for led_idx in range(1, 6):
        prof = profile_for_bottom_led(led_idx, profiles)
        if prof:
            table[led_idx - 1] = max(100, min(30000, int(prof.get("dpi", 3400))))
    return table


def sync_hardware_profile_and_dpi(mgr, profile_data, all_profiles=None):
    """Sync the physical bottom LED / onboard slot and sensor DPI for the given active profile."""
    if all_profiles is None:
        all_profiles = ProfileStorage.load().get("profiles", [])
    max_dpi = mgr.device_info.get("max_dpi", 30000) if mgr.device_info else 30000
    profile_mode = mgr.device_info.get("profile_mode", "dpi_led") if mgr.device_info else "dpi_led"
    dpi = max(100, min(max_dpi, int(profile_data.get("dpi", 3400))))
    slot = max(1, min(5, int(profile_data.get("onboardSlot", 1))))

    if profile_mode == "onboard_slot":
        # Dedicated profile button mode (Naga Pro, Basilisk V3, DeathAdder V2 Pro, etc.)
        stages = [max(100, min(max_dpi, int(v))) for v in profile_data.get("dpi_stages", [2400, 3400, 4800, 5000, 5200])[:5]]
        active_stage = max(1, min(5, int(profile_data.get("active_stage", 3))))
        mgr.hw_set_active_profile(slot)
        time.sleep(0.01)
        mgr.hw_set_dpi_stages(stages, active_stage, slot)
        time.sleep(0.01)
        mgr.hw_set_dpi_stages(stages, active_stage, 0)
        time.sleep(0.01)
        mgr.hw_set_dpi(dpi, dpi, slot)
        mgr.hw_set_dpi(dpi, dpi, 0)
    else:
        # Bottom DPI LED mode (Viper 8KHz, Viper Mini, Cobra, etc.):
        # 1. Set the bottom LED color (led_idx: 1=Red, 2=Green, 3=Blue, 4=Cyan, 5=Yellow)
        #    and preload each color's profile DPI into the physical button cycle table
        led_idx = bottom_led_for_profile(profile_data)
        hw_table = [max(100, min(max_dpi, int(v))) for v in build_bottom_button_dpi_table(all_profiles)]
        hw_table[led_idx - 1] = dpi
        mgr.hw_set_dpi_stages(hw_table, led_idx, 0)
        time.sleep(0.01)
        mgr.hw_set_dpi_stages(hw_table, led_idx, 1)
        time.sleep(0.01)
        # 2. Set the exact active sensor DPI
        mgr.hw_set_dpi(dpi, dpi, 0)
        mgr.hw_set_dpi(dpi, dpi, 1)


class ProfileStorage:
    @staticmethod
    def get_storage_path():
        return PROFILES_FILE

    @staticmethod
    def load():
        path = ProfileStorage.get_storage_path()
        if path.exists():
            try:
                with open(path, "r") as f:
                    return json.load(f)
            except Exception:
                pass
        if TEMPLATE_PROFILES_FILE.exists():
            try:
                with open(TEMPLATE_PROFILES_FILE, "r") as f:
                    return json.load(f)
            except Exception:
                pass
        return DEFAULT_PROFILES_DATA

    @staticmethod
    def save(data):
        try:
            PROFILES_FILE.parent.mkdir(parents=True, exist_ok=True)
            with open(PROFILES_FILE, "w") as f:
                json.dump(data, f, indent=2)
        except Exception:
            pass


def zone_lighting(profile, zone):
    """Lighting for one zone. Values a zone does not override come from the profile-wide settings."""
    overrides = profile.get("zones", {}).get(zone, {}) if zone != "all" else {}
    return {
        "brightness": overrides.get("brightness", profile.get("brightness", 100)),
        "effect": overrides.get("effect", profile.get("effect", "spectrum")),
        "effect_color": overrides.get("effect_color", profile.get("effect_color", "#00FF66")),
    }


def set_zone_lighting(profile, zone, key, value):
    """Store a lighting value for one zone, or for every zone (clearing their overrides) when zone is 'all'."""
    zones = profile.setdefault("zones", {})
    if zone == "all":
        profile[key] = value
        for overrides in zones.values():
            overrides.pop(key, None)
    else:
        zones.setdefault(zone, {})[key] = value
    for z in [z for z, overrides in zones.items() if not overrides]:
        del zones[z]
    if not zones:
        del profile["zones"]


def get_current_state():
    mgr = RazerDeviceManager()
    storage = ProfileStorage.load()
    active_id = storage.get("activeProfile", "onboard-3")
    profiles = storage.get("profiles", [])

    # Find active profile
    active = None
    for p in profiles:
        if p["id"] == active_id:
            active = p
            break
    if not active and profiles:
        active = profiles[0]

    # Check hardware query if permitted
    hw_dpi = None
    lighting_zones = ["logo"]
    battery_pct = None
    charging = None
    if mgr.has_permission:
        try:
            mgr.hw_probe_capabilities()
            profile_mode = mgr.device_info.get("profile_mode", "dpi_led") if mgr.device_info else "dpi_led"
            hw_prof = None
            if profile_mode == "onboard_slot":
                hw_slot = mgr.hw_get_active_profile()
                if hw_slot is not None:
                    for p in profiles:
                        if int(p.get("onboardSlot", 0)) == hw_slot:
                            hw_prof = p
                            break
            else:
                # Read which color mode (1=Red, 2=Green, 3=Blue, 4=Cyan, 5=Yellow) the bottom button is on
                hw_led_idx = mgr.hw_get_bottom_led_index(0)
                if hw_led_idx is not None:
                    hw_prof = profile_for_bottom_led(hw_led_idx, profiles)

            if hw_prof and active and hw_prof["id"] != active["id"]:
                # User pressed the physical button underneath the mouse!
                active = hw_prof
                storage["activeProfile"] = active["id"]
                ProfileStorage.save(storage)
                sync_hardware_profile_and_dpi(mgr, active, profiles)
                time.sleep(0.01)
                mgr.hw_set_polling_rate(active.get("poll_rate", 8000), active.get("onboardSlot", 1))
                time.sleep(0.01)
                apply_lighting(mgr, active)

            hw_dpi = mgr.hw_get_dpi()
            lighting_zones = mgr.hw_get_led_zones()
            raw_battery = mgr.hw_get_battery()
            battery_pct = round(raw_battery / 255 * 100) if raw_battery is not None else None
            charging = mgr.hw_get_charging()
        except Exception:
            pass
        finally:
            mgr.close_device()

    status = {
        "connected": mgr.device_info["connected"] if mgr.device_info else False,
        "name": mgr.device_info["name"] if mgr.device_info else "No Razer Device",
        "pid": f"0x{mgr.device_info['pid']:04x}" if mgr.device_info and mgr.device_info["pid"] else "0x0000",
        "max_dpi": mgr.device_info.get("max_dpi", 30000) if mgr.device_info else 30000,
        "supports_8k": mgr.device_info.get("supports_8k", False) if mgr.device_info else False,
        "profile_mode": mgr.device_info.get("profile_mode", "dpi_led") if mgr.device_info else "dpi_led",
        "hidraw_path": mgr.hidraw_path,
        "has_permission": mgr.has_permission,
        "battery": battery_pct,
        "charging": charging,
        "activeProfile": active["id"] if active else "onboard-3",
        "activeProfileName": active["name"] if active else "Profile 3",
        "onboardSlot": active.get("onboardSlot", 3) if active else 3,
        "dpi": active["dpi"] if active else (hw_dpi[0] if hw_dpi else 4800),
        "dpi_stages": active.get("dpi_stages", [2400, 3400, 4800, 5000, 5200]) if active else [2400, 3400, 4800, 5000, 5200],
        "active_stage": active.get("active_stage", 3) if active else 3,
        "poll_rate": active.get("poll_rate", 8000) if active else 8000,
        "brightness": active.get("brightness", 100) if active else 100,
        "effect": active.get("effect", "static") if active else "static",
        "effect_color": active.get("effect_color", "#00FF00") if active else "#00FF00",
        "lighting_zones": lighting_zones,
        "zones": {z: zone_lighting(active or {}, z) for z in lighting_zones},
        "profiles": profiles
    }
    return status


def apply_lighting(mgr, profile):
    """Send a profile's lighting: one broadcast when every zone matches, otherwise zone by zone."""
    zones = mgr.hw_get_led_zones()
    shared = zone_lighting(profile, "all")
    if all(zone_lighting(profile, z) == shared for z in zones):
        targets = {"all": shared}
    else:
        targets = {z: zone_lighting(profile, z) for z in zones}
    for zone, light in targets.items():
        mgr.hw_set_brightness(light["brightness"], zone)
        time.sleep(0.015)
        mgr.hw_set_effect(light["effect"], light["effect_color"], zone)
        time.sleep(0.015)


def apply_profile(profile_data, all_profiles=None):
    """Send profile configuration to Razer hardware."""
    import time
    mgr = RazerDeviceManager()
    slot = profile_data.get("onboardSlot", 0)
    poll_rate = profile_data.get("poll_rate", 8000)

    if mgr.has_permission:
        try:
            sync_hardware_profile_and_dpi(mgr, profile_data, all_profiles)
            time.sleep(0.015)
            mgr.hw_set_polling_rate(poll_rate, slot)
            time.sleep(0.015)
            apply_lighting(mgr, profile_data)
        except Exception:
            pass
        finally:
            mgr.close_device()


def main():
    import time
    parser = argparse.ArgumentParser(description="Omarchy Razer Device Controller")
    sub = parser.add_subparsers(dest="cmd")

    # status
    p_status = sub.add_parser("status", help="Get device and profile status")
    p_status.add_argument("--json", action="store_true", help="Output as JSON")

    # set-dpi
    p_dpi = sub.add_parser("set-dpi", help="Set current DPI")
    p_dpi.add_argument("dpi", type=int, help="DPI value (100-30000)")
    p_dpi.add_argument("--y", type=int, default=None, help="Optional Y DPI")

    # set-stage
    p_stage = sub.add_parser("set-stage", help="Select active DPI stage (1-5)")
    p_stage.add_argument("stage", type=int, help="Stage index (1 to 5)")

    # set-dpi-stages
    p_stages = sub.add_parser("set-dpi-stages", help="Set the 5 DPI stage values")
    p_stages.add_argument("stages", nargs="+", type=int, help="5 DPI values (100-30000)")
    p_stages.add_argument("--active", type=int, default=None, help="Active stage index (1-5)")
    p_stages.add_argument("--slot", type=int, default=None, help="Target onboard slot (1-5, default active)")

    # set-poll-rate
    p_poll = sub.add_parser("set-poll-rate", help="Set polling rate in Hz")
    p_poll.add_argument("rate", type=int, help="Polling rate (125, 500, 1000, 2000, 4000, 8000)")

    # set-brightness
    p_bright = sub.add_parser("set-brightness", help="Set LED brightness (0-100)")
    p_bright.add_argument("brightness", type=int, help="Brightness percentage (0-100)")
    p_bright.add_argument("--zone", choices=["all"] + ZONE_ORDER, default="all", help="Lighting zone (default: all)")

    # set-effect
    p_fx = sub.add_parser("set-effect", help="Set RGB effect")
    p_fx.add_argument("effect", choices=["static", "spectrum", "breathing", "off"], help="Lighting effect")
    p_fx.add_argument("--color", default="#00FF66", help="Hex color code (e.g. #00FF66)")
    p_fx.add_argument("--zone", choices=["all"] + ZONE_ORDER, default="all", help="Lighting zone (default: all)")

    # profile
    p_prof = sub.add_parser("profile", help="Manage profiles")
    p_prof_sub = p_prof.add_subparsers(dest="profile_action")
    
    p_sw = p_prof_sub.add_parser("switch", help="Switch active profile")
    p_sw.add_argument("target", help="Profile ID or Onboard slot (1-5)")

    p_save = p_prof_sub.add_parser("save", help="Save current settings to active profile / mouse slot")
    p_save.add_argument("--slot", type=int, default=None, help="Target onboard memory slot (1-5)")

    p_upd = p_prof_sub.add_parser("update", help="Update settings for a specific profile slot")
    p_upd.add_argument("--slot", type=int, required=True, help="Target onboard memory slot (1-5)")
    p_upd.add_argument("--name", type=str, default=None, help="Profile name")
    p_upd.add_argument("--badge-color", type=str, default=None, help="Profile badge hex color")
    p_upd.add_argument("--dpi-stages", type=str, default=None, help="Comma-separated 5 DPI values")
    p_upd.add_argument("--active-stage", type=int, default=None, help="Active stage (1-5)")
    p_upd.add_argument("--dpi", type=int, default=None, help="Active DPI value")
    p_upd.add_argument("--poll-rate", type=int, default=None, help="Polling rate in Hz")
    p_upd.add_argument("--brightness", type=int, default=None, help="Brightness (0-100)")
    p_upd.add_argument("--effect", choices=["static", "spectrum", "breathing", "off"], default=None, help="RGB effect")
    p_upd.add_argument("--color", type=str, default=None, help="RGB effect hex color")

    args = parser.parse_args()

    if args.cmd == "status" or args.cmd is None:
        state = get_current_state()
        if getattr(args, "json", True):
            print(json.dumps(state, indent=2))
        else:
            print(f"Device: {state['name']} ({state['pid']})")
            print(f"Connected: {state['connected']} | Permissions: {state['has_permission']}")
            print(f"Active Profile: {state['activeProfileName']} (Slot {state['onboardSlot']})")
            print(f"DPI: {state['dpi']} (Stage {state['active_stage']}/5: {state['dpi_stages']})")
            print(f"Polling Rate: {state['poll_rate']} Hz")
            if state.get("battery") is not None:
                print(f"Battery: {state['battery']}%{' (charging)' if state.get('charging') else ''}")
            print(f"Lighting: {state['effect']} ({state['effect_color']}) @ {state['brightness']}%")
        return

    # Load data for modifications
    data = ProfileStorage.load()
    active_id = data.get("activeProfile", "onboard-1")
    active_prof = None
    for p in data["profiles"]:
        if p["id"] == active_id:
            active_prof = p
            break
    if not active_prof and data["profiles"]:
        active_prof = data["profiles"][0]

    slot = active_prof.get("onboardSlot", 0)

    if getattr(args, "zone", "all") != "all":
        mgr = RazerDeviceManager()
        if mgr.has_permission:
            try:
                zones = mgr.hw_get_led_zones()
            finally:
                mgr.close_device()
            if args.zone not in zones:
                print(f"Zone '{args.zone}' is not available on this device (available: {', '.join(zones)})", file=sys.stderr)
                sys.exit(1)

    if args.cmd == "set-dpi":
        val = max(100, min(30000, args.dpi))
        active_prof["dpi"] = val
        if val in active_prof.get("dpi_stages", []):
            active_prof["active_stage"] = active_prof["dpi_stages"].index(val) + 1
        ProfileStorage.save(data)
        mgr = RazerDeviceManager()
        if mgr.has_permission:
            try:
                sync_hardware_profile_and_dpi(mgr, active_prof, data["profiles"])
            finally:
                mgr.close_device()
        print(f"DPI updated to {val}")

    elif args.cmd == "set-stage":
        stage_idx = max(1, min(len(active_prof.get("dpi_stages", [])), args.stage))
        val = active_prof["dpi_stages"][stage_idx - 1]
        active_prof["active_stage"] = stage_idx
        active_prof["dpi"] = val
        ProfileStorage.save(data)
        mgr = RazerDeviceManager()
        if mgr.has_permission:
            try:
                sync_hardware_profile_and_dpi(mgr, active_prof, data["profiles"])
            finally:
                mgr.close_device()
        print(f"DPI stage switched to {stage_idx} ({val} DPI)")

    elif args.cmd == "set-dpi-stages":
        target_prof = active_prof
        if args.slot is not None:
            for p in data["profiles"]:
                if p.get("onboardSlot") == args.slot:
                    target_prof = p
                    break
        cleaned = [max(100, min(30000, int(v))) for v in args.stages[:5]]
        while len(cleaned) < 5:
            cleaned.append(cleaned[-1] if cleaned else 1600)
        target_prof["dpi_stages"] = cleaned
        stage_idx = args.active if args.active is not None else target_prof.get("active_stage", 1)
        stage_idx = max(1, min(5, int(stage_idx)))
        target_prof["active_stage"] = stage_idx
        target_prof["dpi"] = cleaned[stage_idx - 1]
        ProfileStorage.save(data)
        mgr = RazerDeviceManager()
        if mgr.has_permission:
            try:
                sync_hardware_profile_and_dpi(mgr, active_prof, data["profiles"])
            finally:
                mgr.close_device()
        print(f"DPI stages updated to {cleaned} (active stage {stage_idx})")

    elif args.cmd == "set-poll-rate":
        active_prof["poll_rate"] = args.rate
        ProfileStorage.save(data)
        mgr = RazerDeviceManager()
        if mgr.has_permission:
            try:
                mgr.hw_set_polling_rate(args.rate, slot)
            finally:
                mgr.close_device()
        print(f"Polling rate set to {args.rate} Hz")

    elif args.cmd == "set-brightness":
        b = max(0, min(100, args.brightness))
        set_zone_lighting(active_prof, args.zone, "brightness", b)
        ProfileStorage.save(data)
        mgr = RazerDeviceManager()
        if mgr.has_permission:
            try:
                mgr.hw_set_brightness(b, args.zone)
            finally:
                mgr.close_device()
        print(f"Brightness set to {b}% ({args.zone})")

    elif args.cmd == "set-effect":
        set_zone_lighting(active_prof, args.zone, "effect", args.effect)
        set_zone_lighting(active_prof, args.zone, "effect_color", args.color)
        mgr = RazerDeviceManager()
        # Picking an effect turns zones left at 0% brightness back on
        zones = mgr.hw_get_led_zones() if args.zone == "all" else [args.zone]
        dark = []
        if args.effect != "off":
            dark = [z for z in zones if zone_lighting(active_prof, z)["brightness"] == 0]
        restore = [args.zone] if dark and dark == zones else dark
        for z in restore:
            set_zone_lighting(active_prof, z, "brightness", 100)
        ProfileStorage.save(data)
        if mgr.has_permission:
            try:
                for z in restore:
                    mgr.hw_set_brightness(100, z)
                    time.sleep(0.015)
                mgr.hw_set_effect(args.effect, args.color, args.zone)
            finally:
                mgr.close_device()
        print(f"Effect set to {args.effect} ({args.color}, {args.zone})")

    elif args.cmd == "profile":
        if args.profile_action == "switch":
            target = args.target.strip()
            # If target is number 1-5, find onboard slot
            found = None
            if target.isdigit():
                slot_num = int(target)
                for p in data["profiles"]:
                    if p.get("onboardSlot") == slot_num:
                        found = p
                        break
            else:
                for p in data["profiles"]:
                    if p["id"] == target or p["name"].lower() == target.lower():
                        found = p
                        break

            if found:
                data["activeProfile"] = found["id"]
                ProfileStorage.save(data)
                apply_profile(found, data["profiles"])
                print(f"Switched to profile: {found['name']}")
            else:
                print(f"Profile '{target}' not found")
        elif args.profile_action == "save":
            slot_target = args.slot if args.slot else active_prof.get("onboardSlot", 1)
            active_prof["onboardSlot"] = slot_target
            ProfileStorage.save(data)
            apply_profile(active_prof, data["profiles"])
            print(f"Settings burned into On-Board Memory Slot {slot_target}")
        elif args.profile_action == "update":
            target_prof = None
            for p in data["profiles"]:
                if p.get("onboardSlot") == args.slot:
                    target_prof = p
                    break
            if not target_prof:
                print(f"Profile slot {args.slot} not found", file=sys.stderr)
                sys.exit(1)

            hw_changed = False
            if args.name is not None:
                target_prof["name"] = args.name
            if args.badge_color is not None:
                target_prof["badgeColor"] = args.badge_color
            if args.dpi_stages is not None:
                parts = [int(x.strip()) for x in args.dpi_stages.split(",") if x.strip()]
                cleaned = [max(100, min(30000, v)) for v in parts[:5]]
                while len(cleaned) < 5:
                    cleaned.append(cleaned[-1] if cleaned else 1600)
                target_prof["dpi_stages"] = cleaned
                stage_idx = max(1, min(5, int(target_prof.get("active_stage", 3))))
                target_prof["dpi"] = cleaned[stage_idx - 1]
                hw_changed = True
            if args.active_stage is not None:
                stage_idx = max(1, min(5, int(args.active_stage)))
                target_prof["active_stage"] = stage_idx
                stages = target_prof.get("dpi_stages", [400, 800, 1600, 3200, 6400])
                target_prof["dpi"] = stages[stage_idx - 1]
                hw_changed = True
            if args.dpi is not None:
                val = max(100, min(30000, int(args.dpi)))
                target_prof["dpi"] = val
                if val in target_prof.get("dpi_stages", []):
                    target_prof["active_stage"] = target_prof["dpi_stages"].index(val) + 1
                hw_changed = True
            if args.poll_rate is not None:
                target_prof["poll_rate"] = int(args.poll_rate)
                hw_changed = True
            if args.brightness is not None:
                set_zone_lighting(target_prof, "all", "brightness", max(0, min(100, int(args.brightness))))
                hw_changed = True
            if args.effect is not None:
                set_zone_lighting(target_prof, "all", "effect", args.effect)
                if args.effect != "off" and target_prof.get("brightness", 100) == 0:
                    set_zone_lighting(target_prof, "all", "brightness", 100)
                hw_changed = True
            if args.color is not None:
                set_zone_lighting(target_prof, "all", "effect_color", args.color)
                hw_changed = True

            # When the user edits and saves a profile in Settings, also make that profile active
            # so the mouse bottom LED and settings immediately reflect the saved profile
            data["activeProfile"] = target_prof["id"]
            ProfileStorage.save(data)
            if hw_changed:
                apply_profile(target_prof, data["profiles"])
            print(f"Updated profile slot {args.slot}")

if __name__ == "__main__":
    main()
