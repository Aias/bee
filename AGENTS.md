# Bee

macOS menu bar app for managing scheduled AI agents ("bees") that follow the Agent Skills specification.

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
└── NotificationManager.swift  # Error notifications via UserNotifications
```

## Quick Commands

```bash
# Build
xcodegen generate && xcodebuild -scheme Bee -configuration Debug build

# Run
open ~/Library/Developer/Xcode/DerivedData/Bee-*/Build/Products/Debug/Bee.app

# Open in Xcode
open Bee.xcodeproj
```

## Key Files

- `~/.bee/hive.yaml` — Global config (CLI, overlap policy, per-bee settings)
- `~/.bee/{bee-id}/SKILL.md` — Bee skill definition (Agent Skills spec)
- `~/.bee/{bee-id}/scripts/` — Optional context-gathering scripts
- `~/.bee/logs/{bee-id}/` — Run logs with timestamps

---

## Beads (Issue Tracking)

This project uses **bd** (beads) for issue tracking. Run `bd onboard` to get started.

### Quick Reference

```bash
bd ready              # Find available work
bd show <id>          # View issue details
bd update <id> --status in_progress  # Claim work
bd close <id>         # Complete work
bd sync               # Sync with git
```

### Landing the Plane (Session Completion)

**When ending a work session**, complete ALL steps below. Work is NOT complete until `git push` succeeds.

1. **File issues for remaining work** - Create issues for anything that needs follow-up
2. **Run quality gates** (if code changed) - Tests, linters, builds
3. **Update issue status** - Close finished work, update in-progress items
4. **Push to remote**:
   ```bash
   git pull --rebase
   bd sync
   git push
   git status  # MUST show "up to date with origin"
   ```
5. **Clean up** - Clear stashes, prune remote branches
6. **Verify** - All changes committed AND pushed
7. **Hand off** - Provide context for next session
