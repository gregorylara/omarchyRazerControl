#!/usr/bin/env python3
"""
Razer Control CLI (razer_ctl.py)
Direct HID & Profile Controller for Razer Peripherals in Omarchy Shell
"""

import sys
import os
import glob
import json
import struct
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

# Linux HIDRAW IOCTL definitions
def _IOC(dir_, typ, nr, size):
    return (dir_ << 30) | (ord(typ) << 8) | nr | (size << 16)

IOC_READ = 2
IOC_WRITE = 1
HIDIOCSFEATURE_91 = _IOC(IOC_READ | IOC_WRITE, 'H', 0x06, 91)
HIDIOCGFEATURE_91 = _IOC(IOC_READ | IOC_WRITE, 'H', 0x07, 91)

# Default Profiles
DEFAULT_PROFILES_DATA = {
    "activeProfile": "onboard-1",
    "profiles": [
        {
            "id": "onboard-1",
            "name": "Profile 1 (Default / White)",
            "isOnboard": True,
            "onboardSlot": 1,
            "badgeColor": "#FFFFFF",
            "dpi": 1600,
            "dpi_stages": [400, 800, 1600, 3200, 6400],
            "active_stage": 3,
            "poll_rate": 1000,
            "brightness": 100,
            "effect": "spectrum",
            "effect_color": "#00FF00"
        },
        {
            "id": "onboard-2",
            "name": "Profile 2 (FPS Ultra / Red)",
            "isOnboard": True,
            "onboardSlot": 2,
            "badgeColor": "#FF0000",
            "dpi": 800,
            "dpi_stages": [400, 800, 1200, 1600, 2400],
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
            "dpi": 1200,
            "dpi_stages": [600, 1200, 1800, 2400, 3200],
            "active_stage": 2,
            "poll_rate": 1000,
            "brightness": 80,
            "effect": "breathing",
            "effect_color": "#00FF00"
        },
        {
            "id": "onboard-4",
            "name": "Profile 4 (Productivity / Blue)",
            "isOnboard": True,
            "onboardSlot": 4,
            "badgeColor": "#0066FF",
            "dpi": 1800,
            "dpi_stages": [800, 1200, 1800, 2400, 3600],
            "active_stage": 3,
            "poll_rate": 1000,
            "brightness": 50,
            "effect": "static",
            "effect_color": "#0066FF"
        },
        {
            "id": "onboard-5",
            "name": "Profile 5 (Stealth / Cyan)",
            "isOnboard": True,
            "onboardSlot": 5,
            "badgeColor": "#00FFFF",
            "dpi": 1600,
            "dpi_stages": [400, 800, 1600, 3200, 6400],
            "active_stage": 3,
            "poll_rate": 1000,
            "brightness": 0,
            "effect": "off",
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
        best = candidates[0]
        accessible = None
        for c in candidates:
            if os.access(c["node"], os.R_OK | os.W_OK):
                accessible = c
                break

        chosen = accessible if accessible else best
        self.hidraw_path = chosen["node"]
        self.has_permission = os.access(self.hidraw_path, os.R_OK | os.W_OK)
        self.device_info = {
            "connected": True,
            "name": chosen["name"],
            "pid": chosen["pid"],
            "vid": chosen["vid"],
            "path": self.hidraw_path,
            "has_permission": self.has_permission,
            "interface": chosen["interface"],
            "supports_8k": chosen["pid"] in [0x0091, 0x00B6, 0x00B7, 0x00A5] # Viper 8KHz, Viper V3 Pro, DeathAdder V3 Pro
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

    def send_recv_report(self, command_class, command_id, data_size, arguments, transaction_id=0x1f):
        """Send 90-byte feature report and receive response."""
        if self.fd is None:
            if not self.open_device():
                return None

        report = self._build_report(command_class, command_id, data_size, arguments, transaction_id)
        # Prepend report ID 0x00 for Linux HIDIOCSFEATURE (91 bytes total)
        buf = bytearray(1 + len(report))
        buf[0] = 0x00
        buf[1:] = report

        try:
            fcntl.ioctl(self.fd, HIDIOCSFEATURE_91, bytes(buf))
        except Exception:
            return None

        # Read back response via HIDIOCGFEATURE
        recv_buf = bytearray(91)
        recv_buf[0] = 0x00
        try:
            fcntl.ioctl(self.fd, HIDIOCGFEATURE_91, recv_buf)
            resp = recv_buf[1:]
            return resp
        except Exception:
            return None

    # Hardware Control Methods
    def hw_set_dpi(self, dpi_x, dpi_y=None, profile_slot=0):
        if dpi_y is None:
            dpi_y = dpi_x
        dpi_x = max(100, min(30000, int(dpi_x)))
        dpi_y = max(100, min(30000, int(dpi_y)))
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

    def hw_set_brightness(self, brightness):
        # Brightness 0-100% -> 0-255
        val = int(max(0, min(100, brightness)) * 255 / 100)
        # Extended matrix brightness: 0x0f, 0x04
        args = struct.pack(">BBB", 0x01, 0x04, val) # VARSTORE, LOGO_LED, brightness
        return self.send_recv_report(0x0f, 0x04, 3, args)

    def hw_set_effect(self, effect, hex_color="#00FF66"):
        """Set lighting effect: static, spectrum, breathing, off matching OpenRazer extended matrix."""
        # Convert hex to RGB
        hex_clean = hex_color.lstrip("#")
        if len(hex_clean) == 6:
            r, g, b = tuple(int(hex_clean[i:i+2], 16) for i in (0, 2, 4))
        else:
            r, g, b = (0, 255, 102)

        if effect == "off":
            # razer_chroma_extended_matrix_effect_none: 0x0f, 0x02, size 6: [0x01, 0x04, 0x00, 0x00, 0x00, 0x00]
            args = struct.pack(">BBBBBB", 0x01, 0x04, 0x00, 0x00, 0x00, 0x00)
            return self.send_recv_report(0x0f, 0x02, 6, args)
        elif effect == "spectrum":
            # razer_chroma_extended_matrix_effect_spectrum: 0x0f, 0x02, size 6: [0x01, 0x04, 0x03, 0x00, 0x00, 0x00]
            args = struct.pack(">BBBBBB", 0x01, 0x04, 0x03, 0x00, 0x00, 0x00)
            return self.send_recv_report(0x0f, 0x02, 6, args)
        elif effect == "breathing":
            # razer_chroma_extended_matrix_effect_breathing_single: 0x0f, 0x02, size 9: [0x01, 0x04, 0x02, 0x01, 0x00, 0x01, r, g, b]
            args = struct.pack(">BBBBBBBBB", 0x01, 0x04, 0x02, 0x01, 0x00, 0x01, r, g, b)
            return self.send_recv_report(0x0f, 0x02, 9, args)
        else:
            # razer_chroma_extended_matrix_effect_static: 0x0f, 0x02, size 9: [0x01, 0x04, 0x01, 0x00, 0x00, 0x01, r, g, b]
            args = struct.pack(">BBBBBBBBB", 0x01, 0x04, 0x01, 0x00, 0x00, 0x01, r, g, b)
            return self.send_recv_report(0x0f, 0x02, 9, args)


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


def get_current_state():
    mgr = RazerDeviceManager()
    storage = ProfileStorage.load()
    active_id = storage.get("activeProfile", "onboard-1")
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
    if mgr.has_permission:
        try:
            hw_dpi = mgr.hw_get_dpi()
        except Exception:
            pass

    status = {
        "connected": mgr.device_info["connected"] if mgr.device_info else False,
        "name": mgr.device_info["name"] if mgr.device_info else "No Razer Device",
        "pid": f"0x{mgr.device_info['pid']:04x}" if mgr.device_info and mgr.device_info["pid"] else "0x0000",
        "supports_8k": mgr.device_info.get("supports_8k", False) if mgr.device_info else False,
        "hidraw_path": mgr.hidraw_path,
        "has_permission": mgr.has_permission,
        "activeProfile": active["id"] if active else "onboard-1",
        "activeProfileName": active["name"] if active else "Profile 1",
        "onboardSlot": active.get("onboardSlot", 1) if active else 1,
        "dpi": hw_dpi[0] if hw_dpi else (active["dpi"] if active else 1600),
        "dpi_stages": active.get("dpi_stages", [400, 800, 1600, 3200, 6400]) if active else [400, 800, 1600, 3200, 6400],
        "active_stage": active.get("active_stage", 3) if active else 3,
        "poll_rate": active.get("poll_rate", 1000) if active else 1000,
        "brightness": active.get("brightness", 100) if active else 100,
        "effect": active.get("effect", "spectrum") if active else "spectrum",
        "effect_color": active.get("effect_color", "#00FF66") if active else "#00FF66",
        "profiles": profiles
    }
    return status


def apply_profile(profile_data):
    """Send profile configuration to Razer hardware."""
    import time
    mgr = RazerDeviceManager()
    slot = profile_data.get("onboardSlot", 0)
    dpi = profile_data.get("dpi", 1600)
    stages = profile_data.get("dpi_stages", [400, 800, 1600, 3200, 6400])
    active_stage = profile_data.get("active_stage", 3)
    poll_rate = profile_data.get("poll_rate", 1000)
    brightness = profile_data.get("brightness", 100)
    effect = profile_data.get("effect", "spectrum")
    effect_color = profile_data.get("effect_color", "#00FF66")

    if mgr.has_permission:
        try:
            mgr.hw_set_dpi(dpi, dpi, slot)
            time.sleep(0.015)
            mgr.hw_set_dpi_stages(stages, active_stage, slot)
            time.sleep(0.015)
            mgr.hw_set_polling_rate(poll_rate, slot)
            time.sleep(0.015)
            mgr.hw_set_brightness(brightness)
            time.sleep(0.015)
            mgr.hw_set_effect(effect, effect_color)
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

    # set-poll-rate
    p_poll = sub.add_parser("set-poll-rate", help="Set polling rate in Hz")
    p_poll.add_argument("rate", type=int, help="Polling rate (125, 500, 1000, 2000, 4000, 8000)")

    # set-brightness
    p_bright = sub.add_parser("set-brightness", help="Set LED brightness (0-100)")
    p_bright.add_argument("brightness", type=int, help="Brightness percentage (0-100)")

    # set-effect
    p_fx = sub.add_parser("set-effect", help="Set RGB effect")
    p_fx.add_argument("effect", choices=["static", "spectrum", "breathing", "off"], help="Lighting effect")
    p_fx.add_argument("--color", default="#00FF66", help="Hex color code (e.g. #00FF66)")

    # profile
    p_prof = sub.add_parser("profile", help="Manage profiles")
    p_prof_sub = p_prof.add_subparsers(dest="profile_action")
    
    p_sw = p_prof_sub.add_parser("switch", help="Switch active profile")
    p_sw.add_argument("target", help="Profile ID or Onboard slot (1-5)")

    p_save = p_prof_sub.add_parser("save", help="Save current settings to active profile / mouse slot")
    p_save.add_argument("--slot", type=int, default=None, help="Target onboard memory slot (1-5)")

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

    if args.cmd == "set-dpi":
        val = max(100, min(30000, args.dpi))
        active_prof["dpi"] = val
        if val in active_prof.get("dpi_stages", []):
            active_prof["active_stage"] = active_prof["dpi_stages"].index(val) + 1
        ProfileStorage.save(data)
        mgr = RazerDeviceManager()
        if mgr.has_permission:
            try:
                mgr.hw_set_dpi(val, args.y if args.y else val, slot)
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
                mgr.hw_set_dpi(val, val, slot)
                time.sleep(0.015)
                mgr.hw_set_dpi_stages(active_prof["dpi_stages"], stage_idx, slot)
            finally:
                mgr.close_device()
        print(f"DPI stage switched to {stage_idx} ({val} DPI)")

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
        active_prof["brightness"] = b
        ProfileStorage.save(data)
        mgr = RazerDeviceManager()
        if mgr.has_permission:
            try:
                mgr.hw_set_brightness(b)
            finally:
                mgr.close_device()
        print(f"Brightness set to {b}%")

    elif args.cmd == "set-effect":
        active_prof["effect"] = args.effect
        active_prof["effect_color"] = args.color
        restore_bright = False
        if active_prof.get("brightness", 100) == 0 and args.effect != "off":
            active_prof["brightness"] = 100
            restore_bright = True
        ProfileStorage.save(data)
        mgr = RazerDeviceManager()
        if mgr.has_permission:
            try:
                if restore_bright:
                    mgr.hw_set_brightness(100)
                    time.sleep(0.015)
                mgr.hw_set_effect(args.effect, args.color)
            finally:
                mgr.close_device()
        print(f"Effect set to {args.effect} ({args.color})")

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
                apply_profile(found)
                print(f"Switched to profile: {found['name']}")
            else:
                print(f"Profile '{target}' not found")
        elif args.profile_action == "save":
            slot_target = args.slot if args.slot else active_prof.get("onboardSlot", 1)
            active_prof["onboardSlot"] = slot_target
            ProfileStorage.save(data)
            apply_profile(active_prof)
            print(f"Settings burned into On-Board Memory Slot {slot_target}")

if __name__ == "__main__":
    main()
