# Bee

macOS menu bar app for managing scheduled AI agents ("bees") that follow the Agent Skills specification.

> **Note**: `CLAUDE.md` is symlinked to this file. Always edit `AGENTS.md`, not the symlink.

## Development Principles

**Native macOS first**: Prioritize idiomatic SwiftUI and standard Apple patterns over custom solutions. The app should feel like a native macOS citizen.

**Agent Skills compliance**: Each bee is a valid Agent Skills folder (SKILL.md + optional scripts/). Don't extend or modify the spec unless required.

## Architecture

```
Bee/
├── BeeApp.swift           # App entry, MenuBarExtra + Settings scenes
├── MenuBarView.swift      # Dropdown UI with bee list and drill-down details
├── PreferencesView.swift  # Settings window (⌘,)
├── HiveManager.swift      # Bee discovery from ~/.bee/, config load/save
├── Scheduler.swift        # Cron evaluation, timer management, overlap handling
├── BeeRunner.swift        # Claude CLI subprocess execution, logging
├── CronParser.swift       # Cron → English conversion
├── ConfirmServer.swift    # User confirmation flow via notifications
└── NotificationManager.swift  # Error notifications via UserNotifications

BeeTests/
├── TestHelpers.swift      # Shared test factories (makeBee, makeDate)
├── CronParserTests.swift  # Cron matching and English conversion
├── SchedulerTests.swift   # Trigger evaluation, overlap modes
└── HiveManagerTests.swift # Config persistence, bee discovery
```

### Testability Seams

- `HiveManager.init(hivePath:fileManager:)` — inject temp directory for isolated tests
- `Scheduler.evaluate(bees:isPaused:now:)` — inject specific date instead of `Date()`

## After Code Changes

Run formatting, linting, and tests:

```bash
swiftformat . && swiftlint --fix && xcodebuild test -scheme Bee -destination 'platform=macOS' -only-testing:BeeTests
```

Then rebuild and relaunch the app:

```bash
xcodebuild -scheme Bee -configuration Debug build && pkill -x Bee; open ~/Library/Developer/Xcode/DerivedData/Bee-*/Build/Products/Debug/Bee.app
```

## Quick Commands

```bash
# Build
xcodebuild -scheme Bee -configuration Debug build

# Run tests
xcodebuild test -scheme Bee -destination 'platform=macOS' -only-testing:BeeTests

# Format & lint
swiftformat . && swiftlint lint

# Run app
open ~/Library/Developer/Xcode/DerivedData/Bee-*/Build/Products/Debug/Bee.app

# Kill and relaunch
pkill -x Bee; open ~/Library/Developer/Xcode/DerivedData/Bee-*/Build/Products/Debug/Bee.app

# Open in Xcode
open Bee.xcodeproj
```

## Key Files

- `~/.bee/hive.yaml` — Global config (CLI, overlap policy, per-bee settings)
- `~/.bee/{bee-id}/SKILL.md` — Bee skill definition (Agent Skills spec)
- `~/.bee/{bee-id}/scripts/` — Optional context-gathering scripts
- `~/.bee/logs/{bee-id}/` — Run logs with timestamps