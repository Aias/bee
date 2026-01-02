# Bee

A macOS menu bar app for running scheduled AI agents. Each "bee" is a self-contained skill that runs on a cron schedule, executing tasks via the Claude CLI.

## Requirements

- macOS 14.0+
- Xcode 15+ (for building)
- [xcodegen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)
- [Claude CLI](https://claude.ai/code) installed and authenticated

## Building

```bash
# Generate Xcode project and build
xcodegen generate
xcodebuild -project Bee.xcodeproj -scheme Bee -configuration Release build

# The app is built to:
# ~/Library/Developer/Xcode/DerivedData/Bee-*/Build/Products/Release/Bee.app
```

To install permanently, copy `Bee.app` to `/Applications`.

## Usage

Launch the app—it appears as an ant icon in the menu bar. Click to see your bees and their status.

**Menu bar actions:**
- Click a bee row to see details and recent runs
- Right-click for quick actions (Run Now, Enable/Disable, Open Logs)
- Pause All / Resume All to temporarily stop all scheduled runs
- Preferences (⌘,) for global settings

## Configuration

### Hive Configuration

Global settings live in `~/.bee/hive.yaml` (auto-created on first run):

```yaml
version: 1

defaults:
  cli: claude          # CLI to use (claude, codex, cursor)
  overlap: skip        # What to do if a bee is still running: skip, queue, parallel

bees:
  my-bee:
    enabled: true
    schedule: "*/5 * * * *"   # Cron expression
    cli: claude               # Override default CLI for this bee
    overlap: skip             # Override default overlap handling
```

### Creating a Bee

Each bee is a folder in `~/.bee/` containing a `SKILL.md` file following the [Agent Skills](https://agentskills.io) specification:

```
~/.bee/
├── hive.yaml
├── my-bee/
│   ├── SKILL.md
│   └── scripts/        # Optional: context-gathering scripts
│       └── gather.sh
└── another-bee/
    └── SKILL.md
```

### SKILL.md Format

```markdown
---
name: my-bee
description: Brief description of what this bee does
allowed-tools: Read Write WebSearch
metadata:
  display-name: My Bee
  icon: star.fill
---

Your skill instructions go here. This becomes the system prompt
when Claude runs your bee.

## Guidelines

- Be specific about what the bee should do
- Reference any files it should read or write
- The bee runs autonomously—no user interaction during execution
```

**Frontmatter fields:**
- `name` (required): Lowercase identifier matching the folder name
- `description`: Shown in the UI
- `allowed-tools`: Space-separated list of Claude CLI tools to allow
- `metadata.display-name`: Friendly name shown in the menu
- `metadata.icon`: SF Symbol name (defaults to "ant")

### Context Scripts

Place executable scripts in `scripts/` to gather context before each run. Their stdout becomes part of the prompt:

```bash
#!/bin/bash
# scripts/weather.sh
curl -s "wttr.in/?format=3"
```

Scripts run in alphabetical order. Make them executable: `chmod +x scripts/*.sh`

## User Confirmation Protocol

Bees can request user confirmation before completing critical actions using structured JSON output.

**How it works:**

Bees return JSON with a `status` field:
- `needs_confirmation` — Pauses and shows a notification with Confirm/Reject
- `completed` — Task finished successfully
- `error` — Something went wrong

**Example skill with confirmation:**

```markdown
---
name: journal-bee
allowed-tools: WebSearch Write Read
---

## Process

1. Search for current events and compose a journal entry
2. Request confirmation:
   {"status": "needs_confirmation", "confirmMessage": "Ready to add journal entry about [topic]"}
3. After confirmation, write the entry and return:
   {"status": "completed", "result": "Added journal entry about [topic]"}
```

The output schema is automatically enforced via `--json-schema`. Timeout defaults to 5 minutes (configurable via `timeout` in hive.yaml).

## Logs

Run logs are stored in `~/.bee/logs/{bee-id}/{timestamp}.log` with output and any errors.

## Cron Schedule Reference

```
┌───────────── minute (0-59)
│ ┌───────────── hour (0-23)
│ │ ┌───────────── day of month (1-31)
│ │ │ ┌───────────── month (1-12)
│ │ │ │ ┌───────────── day of week (0-6, Sun=0)
│ │ │ │ │
* * * * *
```

**Examples:**
- `*/5 * * * *` — Every 5 minutes
- `0 * * * *` — Every hour
- `0 9 * * *` — Daily at 9am
- `0 9 * * 1-5` — Weekdays at 9am
- `0 0 * * 0` — Weekly on Sunday at midnight

## Development

```bash
# Generate project
xcodegen generate

# Build debug
xcodebuild -project Bee.xcodeproj -scheme Bee -configuration Debug build

# Run from DerivedData
open ~/Library/Developer/Xcode/DerivedData/Bee-*/Build/Products/Debug/Bee.app

# Or open in Xcode
open Bee.xcodeproj
```

## Architecture

```
Bee/
├── BeeApp.swift           # App entry point, MenuBarExtra scene
├── MenuBarView.swift      # Main dropdown UI with bee list and details
├── PreferencesView.swift  # Settings window
├── HiveManager.swift      # Bee discovery and config management
├── Scheduler.swift        # Cron evaluation and timer management
├── BeeRunner.swift        # CLI subprocess execution
├── CronParser.swift       # Cron expression parsing and English conversion
└── NotificationManager.swift  # macOS notifications for errors
```
