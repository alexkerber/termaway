#!/usr/bin/env bash
set -euo pipefail

INSTALL_DIR="/opt/termaway"

echo "TermAway Linux Uninstaller"
echo "=========================="
echo ""

# Check for root
if [ "$EUID" -ne 0 ]; then
  echo "Error: Please run as root (sudo ./uninstall.sh)"
  exit 1
fi

# Stop and disable service
if systemctl is-active --quiet termaway 2>/dev/null; then
  echo "Stopping termaway service..."
  systemctl stop termaway
fi

if systemctl is-enabled --quiet termaway 2>/dev/null; then
  echo "Disabling termaway service..."
  systemctl disable termaway
fi

# Remove service file
if [ -f /etc/systemd/system/termaway.service ]; then
  echo "Removing systemd service..."
  rm /etc/systemd/system/termaway.service
  systemctl daemon-reload
fi

# Remove install directory
if [ -d "$INSTALL_DIR" ]; then
  echo "Removing ${INSTALL_DIR}..."
  rm -rf "$INSTALL_DIR"
fi

echo ""
echo "TermAway has been uninstalled."
echo ""
