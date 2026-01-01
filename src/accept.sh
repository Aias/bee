#!/bin/bash

BEE_DIR="$HOME/Code/bee"
CONTENT_DIR="$BEE_DIR/content"
PENDING_FILE="$CONTENT_DIR/pending.md"
JOURNAL_FILE="$CONTENT_DIR/journal.md"

# Full path for launchd compatibility
NOTIFIER="/opt/homebrew/bin/terminal-notifier"

# Check if there's a pending entry
if [ ! -f "$PENDING_FILE" ]; then
  $NOTIFIER -title "Bee" -message "No pending entry to save"
  exit 1
fi

ENTRY=$(cat "$PENDING_FILE")
TIMESTAMP=$(date "+%Y-%m-%d %H:%M")

# Prepend to journal (newest first)
TEMP_FILE=$(mktemp)
echo "## $TIMESTAMP" > "$TEMP_FILE"
echo "" >> "$TEMP_FILE"
echo "$ENTRY" >> "$TEMP_FILE"
echo "" >> "$TEMP_FILE"
cat "$JOURNAL_FILE" >> "$TEMP_FILE" 2>/dev/null || true
mv "$TEMP_FILE" "$JOURNAL_FILE"

# Clear the pending file
rm "$PENDING_FILE"

# Confirm
$NOTIFIER -title "Bee" -message "Entry saved to journal" -sound Pop
