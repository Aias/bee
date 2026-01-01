#!/bin/bash
set -e

PLIST_NAME="com.bee.compose.plist"
PLIST_DST="$HOME/Library/LaunchAgents/$PLIST_NAME"

# Unload the job (ignore error if not loaded)
launchctl unload "$PLIST_DST" 2>/dev/null || true

# Remove symlink
rm -f "$PLIST_DST"

echo "Bee disabled."
