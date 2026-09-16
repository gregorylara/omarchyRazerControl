#!/bin/bash
set -e

RULE_SRC="$(dirname "$0")/99-razer-omarchy.rules"
RULE_DEST="/etc/udev/rules.d/99-razer-omarchy.rules"

echo "=========================================================="
echo " Omarchy Razer Control - Hardware Permissions Setup"
echo "=========================================================="

if [ "$EUID" -ne 0 ]; then
    echo "Elevating privileges with sudo or pkexec..."
    if command -v sudo >/dev/null 2>&1; then
        exec sudo "$0" "$@"
    elif command -v pkexec >/dev/null 2>&1; then
        exec pkexec "$0" "$@"
    else
        echo "Error: root privileges required to install udev rules."
        exit 1
    fi
fi

echo "Installing $RULE_DEST..."
cp "$RULE_SRC" "$RULE_DEST"
chmod 644 "$RULE_DEST"

echo "Reloading udev rules..."
udevadm control --reload-rules
udevadm trigger --subsystem-match=hidraw

echo "Setup complete! Razer mice now have user-level access."
echo "Unplug and replug your Razer mouse if changes do not appear immediately."
