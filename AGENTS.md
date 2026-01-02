# Bee

macOS menu bar app for managing scheduled AI agents ("bees") that follow the Agent Skills specification.

## Development Principles

**Native macOS first**: Prioritize idiomatic SwiftUI and standard Apple patterns over custom solutions. Accept platform inconsistencies rather than fighting them—if Apple's components render slightly differently, that's fine. Only deviate when absolutely necessary. The app should feel like a native macOS citizen.

**Agent Skills compliance**: Each bee is a valid Agent Skills folder (SKILL.md + optional scripts/). Don't extend or modify the spec unless required.

---

## Legacy Architecture (v1)

> Note: The shell-based approach below is being replaced by the SwiftUI app. Keeping for reference during migration.

## Architecture

```
compose.sh    Gathers system context, runs Claude to compose entry, sends notification
accept.sh     Notification click handler—appends pending entry to journal
journal.md    The accumulated journal entries
pending.md    Ephemeral draft awaiting user approval (auto-deleted on accept)
```

## Context Sources

Currently:
- Date/time
- Weather (via wttr.in)
- System uptime, battery, memory
- Optional web search

Future ideas:
- Recent shell history
- Git activity
- Calendar events
- Music playing
- Screen time / active app

## Scheduling

The launchd plist (`com.bee.compose.plist`) runs `compose.sh` every 5 minutes. Install with:

```bash
ln -sf ~/Code/bee/com.bee.compose.plist ~/Library/LaunchAgents/
launchctl load ~/Library/LaunchAgents/com.bee.compose.plist
```

Unload with:
```bash
launchctl unload ~/Library/LaunchAgents/com.bee.compose.plist
```

## Manual Testing

```bash
./compose.sh   # Run once manually
```

## Logs

Check `logs/stdout.log` and `logs/stderr.log` for debugging.

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
