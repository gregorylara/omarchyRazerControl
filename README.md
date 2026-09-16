# Oma Razer Control (`oma.razer`)

Razer mouse status, DPI control, polling rate (up to 8000 Hz), Chroma RGB lighting, and **on-board memory profiles** for the [Omarchy](https://omarchy.org) bar.

Designed for Razer mice (including the **Razer Viper 8KHz**, Viper Ultimate, Basilisk V2/V3, DeathAdder V2/V3, and more). Monitor DPI in real time, switch between hardware DPI stages, tune polling rate up to 8000 Hz, customize lighting effects, and save/switch profiles directly inside the mouse's internal flash memory.

---

## Features

- 󰍽 **Live DPI in the Bar**: Real-time display of current DPI in the status bar (e.g. `󰍽 1600`).
- ⚡ **Full 8000 Hz Polling Rate**: Native support for hyper-polling rates (125, 500, 1000, 2000, 4000, and 8000 Hz) for high-performance esports sensors.
- 💾 **On-Board Memory Profiles (1–5)**: Direct access to the 5 internal hardware profiles (White, Red, Green, Blue, Cyan) stored in the mouse's onboard flash memory, plus local custom profiles.
- 🎯 **5-Stage DPI Presets & Precision Slider**: Instant stage switching (400, 800, 1600, 3200, 6400) or continuous fine-tuning from 100 to 20,000+ DPI.
- 🌈 **Chroma RGB Lighting**: Brightness slider (0–100%), modes (Static, Spectrum Cycling, Breathing, Off), and quick color palette (Razer Green, Cyan, Sky Blue, Purple, Red, White).
- 🚀 **Zero Heavy Daemons Required**: Uses lightweight direct USB HID communication with fallback and zero persistent background resource overhead.
- 🎨 **Adaptive Omarchy Theme**: Seamlessly matches your active Omarchy theme colors, fonts, and styling.

---

## One-Time Hardware Setup (udev)

To allow direct communication with your Razer mouse without needing elevated permissions or root privileges:

```sh
cd ~/Projects/omarchyRazerControl
./setup.sh
```

This installs `99-razer-omarchy.rules` into `/etc/udev/rules.d/` and reloads `udevadm`. You can also trigger this directly from the warning banner inside the plugin panel.

---

## Installation in Omarchy

### Option 1: Link directly into Omarchy plugins
To test and develop with hot-reloading:

```sh
mkdir -p ~/.config/omarchy/plugins
ln -s ~/Projects/omarchyRazerControl ~/.config/omarchy/plugins/oma.razer
omarchy plugin enable oma.razer --section right
```

### Option 2: Add via Omarchy CLI
```sh
omarchy plugin add https://github.com/gregorylara/omarchyRazerControl.git --enable
```

---

## Shell IPC Commands

You can control your mouse from scripts, terminal shortcuts, or keybindings via the Omarchy shell IPC:

```sh
omarchy-shell oma.razer open                 # Open the Razer control panel
omarchy-shell oma.razer close                # Close the panel
omarchy-shell oma.razer toggle               # Toggle open/close
omarchy-shell oma.razer refresh              # Force query device status
omarchy-shell oma.razer dpi 1600             # Set DPI directly to 1600
omarchy-shell oma.razer stage 2              # Switch to DPI Stage 2
omarchy-shell oma.razer poll 8000            # Set polling rate to 8000 Hz
omarchy-shell oma.razer profile 2            # Switch to On-Board Profile 2 (Red)
omarchy-shell oma.razer brightness 80        # Set LED brightness to 80%
```

---

## CLI Backend (`razer_ctl.py`)

You can also use the backend CLI independently from terminal or scripts:

```sh
./razer_ctl.py status --json                 # Print JSON state
./razer_ctl.py set-dpi 800                   # Set DPI to 800
./razer_ctl.py set-stage 3                   # Activate stage 3
./razer_ctl.py set-poll-rate 8000            # Set 8000Hz polling rate
./razer_ctl.py set-effect static --color "#00FF66" # Set Razer green static LED
./razer_ctl.py profile switch 2              # Switch to onboard slot 2
./razer_ctl.py profile save --slot 2         # Burn current settings to slot 2
```

---

## Configuration (`shell.json`)

Settings can be customized directly in `~/.config/omarchy/shell.json` under your bar layout entry:

```json
{
  "id": "oma.razer",
  "showDpiInBar": true,
  "onlyWhenConnected": false,
  "notifyOnConnect": true
}
```

| Option | Type | Default | Description |
|---|---|---|---|
| `showDpiInBar` | boolean | `true` | Show numeric DPI next to the mouse icon in the bar |
| `onlyWhenConnected` | boolean | `false` | Hide widget when mouse is disconnected |
| `notifyOnConnect` | boolean | `true` | Send desktop notification when mouse connects |

---

## License

MIT License. See [LICENSE](LICENSE) for details.
