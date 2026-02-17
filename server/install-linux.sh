#!/usr/bin/env bash
set -euo pipefail

INSTALL_DIR="/opt/termaway"

echo "TermAway Linux Installer"
echo "========================"
echo ""

# Check for root
if [ "$EUID" -ne 0 ]; then
  echo "Error: Please run as root (sudo ./install.sh)"
  exit 1
fi

# Check Node.js
if ! command -v node &> /dev/null; then
  echo "Error: Node.js is not installed."
  echo "Install Node.js 18+ from https://nodejs.org or via your package manager:"
  echo "  curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -"
  echo "  sudo apt-get install -y nodejs"
  exit 1
fi

NODE_VERSION=$(node -v | sed 's/v//' | cut -d. -f1)
if [ "$NODE_VERSION" -lt 18 ]; then
  echo "Error: Node.js 18+ is required (found v$(node -v))."
  echo "Please upgrade Node.js."
  exit 1
fi

echo "Node.js $(node -v) found."

# Check for build tools (needed by node-pty)
if ! command -v make &> /dev/null || ! command -v gcc &> /dev/null; then
  echo ""
  echo "Warning: Build tools (make, gcc) not found."
  echo "node-pty requires native compilation. Install build tools:"
  echo "  Ubuntu/Debian: sudo apt-get install -y build-essential"
  echo "  Fedora/RHEL:   sudo dnf groupinstall 'Development Tools'"
  echo ""
  read -p "Continue anyway? [y/N] " -n 1 -r
  echo ""
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    exit 1
  fi
fi

# Determine script directory (where the tarball was extracted)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo ""
echo "Installing to ${INSTALL_DIR}..."

# Create install directory
mkdir -p "$INSTALL_DIR"

# Copy files
cp -r "$SCRIPT_DIR/server" "$INSTALL_DIR/"
cp -r "$SCRIPT_DIR/apps/web" "$INSTALL_DIR/apps/web"
mkdir -p "$INSTALL_DIR/apps"
cp "$SCRIPT_DIR/package.json" "$INSTALL_DIR/"

# Install dependencies
echo "Installing dependencies (this may take a minute)..."
cd "$INSTALL_DIR"
npm install --production

# Install systemd service
cp "$INSTALL_DIR/server/termaway.service" /etc/systemd/system/termaway.service
systemctl daemon-reload
systemctl enable termaway

echo ""
echo "========================================"
echo "  TermAway installed successfully!"
echo "========================================"
echo ""
echo "Start the server:"
echo "  sudo systemctl start termaway"
echo ""
echo "Check status:"
echo "  sudo systemctl status termaway"
echo ""
echo "View logs:"
echo "  journalctl -u termaway -f"
echo ""
echo "Set a password (recommended):"
echo "  Edit /etc/systemd/system/termaway.service"
echo "  Add: Environment=TERMAWAY_PASSWORD=your-password"
echo "  Then: sudo systemctl daemon-reload && sudo systemctl restart termaway"
echo ""
echo "Connect from your iPad or browser:"
echo "  http://$(hostname -I | awk '{print $1}'):3000"
echo ""
