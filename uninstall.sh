#!/bin/bash

# ============================================
# YouTube Streaming Dashboard Uninstaller
# ============================================

set -e

APP_NAME="yt-streaming-dashboard"
INSTALL_DIR="/opt/$APP_NAME"

echo "🗑️  YouTube Streaming Dashboard - Uninstaller"
echo "=============================================="

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
   echo "⚠️  Please run as root: sudo bash uninstall.sh"
   exit 1
fi

# Confirm uninstall
read -p "⚠️  This will remove ALL data. Continue? (yes/no): " confirm
if [ "$confirm" != "yes" ]; then
    echo "❌ Uninstall cancelled"
    exit 0
fi

echo ""
echo "🛑 Stopping service..."
systemctl stop $APP_NAME || true

echo "🗑️  Removing systemd service..."
systemctl disable $APP_NAME || true
rm -f /etc/systemd/system/$APP_NAME.service
systemctl daemon-reload

echo "🗑️  Removing application files..."
rm -rf $INSTALL_DIR

echo ""
echo "✅ Uninstall complete!"
echo ""
echo "Note: Go, Node.js, and system dependencies are kept."
echo "To remove them manually:"
echo "  apt remove nodejs"
echo "  rm -rf /usr/local/go"
