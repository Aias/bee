#!/bin/bash
set -e

BEE_DIR="$HOME/Code/bee"
CONTENT_DIR="$BEE_DIR/content"
PENDING_FILE="$CONTENT_DIR/pending.md"
JOURNAL_FILE="$CONTENT_DIR/journal.md"
ACCEPT_SCRIPT="$BEE_DIR/src/accept.sh"

# Full paths for launchd compatibility
CLAUDE="/Users/nicktrombley/.local/bin/claude"
NOTIFIER="/opt/homebrew/bin/terminal-notifier"

# Light context
DATE=$(date "+%A, %B %d, %Y at %H:%M")

# Recent journal entries (first 50 lines, since newest are at top)
RECENT_ENTRIES=$(head -50 "$JOURNAL_FILE" 2>/dev/null || echo "No entries yet.")

PROMPT="You are composing prose poetry for a journal.

Current moment: $DATE

Recent entries from this journal (for continuity, avoid repetition):
---
$RECENT_ENTRIES
---

First, search the web for something happening right now—breaking news, a scientific discovery, a cultural moment, weather somewhere interesting, anything current and real. Let this anchor your piece.

Then write 3-6 lines of prose poetry. Each sentence should end with a newline. For longer sentences, you may break at a comma. The tone is observational, unhurried, finding the strange in the ordinary. Draw unexpected connections. No titles, no explanations—just the piece itself.

Output ONLY the poem, nothing else."

# Run Claude to compose the entry
$CLAUDE -p "$PROMPT" --allowedTools "WebSearch" --output-format text > "$PENDING_FILE" 2>/dev/null

# Read the composed entry for notification
ENTRY=$(cat "$PENDING_FILE")
PREVIEW=$(echo "$ENTRY" | head -c 100)

# Send notification with preview
$NOTIFIER \
  -title "Bee" \
  -subtitle "New thought composed" \
  -message "$PREVIEW..." \
  -sound default \
  -execute "$ACCEPT_SCRIPT"
