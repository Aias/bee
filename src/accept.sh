#!/bin/bash

BEE_DIR="$HOME/Code/bee"
CONTENT_DIR="$BEE_DIR/content"
PENDING_FILE="$CONTENT_DIR/pending.md"
JOURNAL_FILE="$CONTENT_DIR/journal.md"

# Exit silently if no pending entry
[ ! -f "$PENDING_FILE" ] && exit 0

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
