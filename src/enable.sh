#!/bin/bash
set -e

PLIST_NAME="com.bee.compose.plist"
PLIST_SRC="$HOME/Code/bee/$PLIST_NAME"
PLIST_DST="$HOME/Library/LaunchAgents/$PLIST_NAME"

# Symlink plist to LaunchAgents
ln -sf "$PLIST_SRC" "$PLIST_DST"

# Load the job
launchctl load "$PLIST_DST"

echo "Bee enabled. Compose will run every minute."
