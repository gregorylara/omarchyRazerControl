# Changelog

All notable changes to Oma Razer Control are documented in this file.

## [2.0.0] - 2026-10-16

Version 2.0 is the largest update to the plugin so far.

### Added
- **Profile Settings editor**: a dedicated view for editing each on-board profile (P1–P5): indicator color, DPI for every stage, polling rate and Chroma lighting. It has a **Save Changes** button pinned to the bottom of the panel.
- **Instant profile switching**: cached profile settings appear in the panel immediately, with an animated switching indicator on the profile buttons.
- **Bottom button sync**: the LED and profile button on the underside of the mouse are mapped to P1–P5 (Yellow, Red, Green, Blue, Cyan) and stay in sync with the panel in both directions.
- **Multi-model support**: a `DEVICE_DB` with known Viper, DeathAdder, Basilisk, Naga, Cobra, Mamba and Orochi models (wired and wireless).
- **Capability auto-probing** for unknown Razer mice: transaction ID fallback (`0x1F` / `0x3F` / `0xFF`), 8 kHz polling detection, and profile-button mode detection (`dpi_led` or `onboard_slot`).
- **Per-device DPI limits**: sliders and inputs adapt to the connected sensor's maximum DPI.
- `profile update --slot <1-5>` and `set-dpi-stages` CLI subcommands.
- `settings` IPC command (`omarchy-shell oma.razer settings`) that opens the Profile Settings view.
- `max_dpi` and `profile_mode` fields in `razer_ctl.py status --json`.

### Changed
- New default profiles: shared stages `2400 / 3400 / 4800 / 5000 / 5200` at 8000 Hz, with P1–P5 set to stages 1–5 and matching static colors. P3 (Green) is the default active profile.
- All panel buttons, cards, inputs and swatches use square corners to match the Omarchy look.
- The Settings view replaces the main view while it is open, which keeps the panel focused.
- DPI values snap to steps of 50.

### Fixed
- Scrolling the panel with the mouse wheel no longer changes the DPI or brightness sliders.
- Saving a profile no longer changes the bottom LED to the wrong color.
- Switching profiles now updates the sensor DPI immediately.
- udev rule now grants `MODE="0666"` so the shell can access the device without root.

## [1.0.0]

- First release: live DPI in the bar, on-board profile switching, 5-stage DPI, polling rates up to 8000 Hz, Chroma RGB lighting with multi-zone support, battery status, and an IPC API.
