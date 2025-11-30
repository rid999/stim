#!/bin/bash

# ============================================
# YouTube Streaming Dashboard Updater
# Quick rebuild without reinstalling deps
# ============================================

set -e

APP_NAME="yt-streaming-dashboard"
INSTALL_DIR="/opt/$APP_NAME"

echo "🔄 YouTube Streaming Dashboard - Updater"
echo "========================================"

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
   echo "⚠️  Please run as root: sudo bash update.sh"
   exit 1
fi

# Check if installed
if [ ! -d "$INSTALL_DIR" ]; then
    echo "❌ Application not found at $INSTALL_DIR"
    echo "   Please run install.sh first"
    exit 1
fi

echo ""
echo "🛑 Stopping service..."
systemctl stop $APP_NAME

echo "🔨 Rebuilding frontend..."
cd $INSTALL_DIR/frontend
npm run build

echo "🔨 Rebuilding backend..."
cd $INSTALL_DIR/backend
export PATH=$PATH:/usr/local/go/bin
go build -o $INSTALL_DIR/$APP_NAME main.go

echo "🚀 Starting service..."
systemctl start $APP_NAME

echo ""
echo "✅ Update complete!"
echo ""
echo "Check status: systemctl status $APP_NAME"
