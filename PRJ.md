A "bee" is one of a "hive"/"swarm"/"colony" of terminal agents that run at intervals on a user's system.
A bee is responsible for doing autonomous tasks with clear intents, guardrails, and context.
Bees may be expected to gather their own context, run web searches, write code, create and modify files, make art, or any number of things the user might ask them to do.
Each bee has settings and instructions defined in a file (or possibly stored in a database) that is used to configure the bee's behavior and give it a purpose and direction.
Bees are expected to work autonomously, but they may prompt the user for input during their tasks, or require confirmation before completing a task.
Each bee has a set schedule or set of triggers, but may also be triggered manually.
The bees can be enabled or disabled, and there should be an idle or running status so the user knows which bees are currently active.

---

# Bee v2: macOS Menu Bar App with Multi-Bee Support

## Overview

Pivot from shell-based ambient journaling to a native SwiftUI menu bar app that manages multiple "bees"—scheduled AI agents following the Agent Skills specification.

---

## Architecture

```
~/.bee/
├── hive.yaml              # Central manifest (GUI-managed)
├── journal-bee/           # Converted from current implementation
│   ├── SKILL.md           # Agent Skills spec: frontmatter + instructions
│   └── scripts/
│       └── gather-context.sh
├── another-bee/
│   ├── SKILL.md
│   └── scripts/
└── logs/
    ├── journal-bee/
    │   └── 2024-01-02T10-30-00.log
    └── another-bee/
```

### Core Components

| Component       | Technology           | Purpose                              |
| --------------- | -------------------- | ------------------------------------ |
| Menu bar app    | Swift/SwiftUI        | Scheduler, UI, bee lifecycle         |
| Bees            | Agent Skills folders | SKILL.md + scripts/ per spec         |
| hive.yaml       | YAML                 | Schedules, CLI config, enabled state |
| Agent execution | CLI subprocess       | `claude`, `codex`, `cursor` headless |

---

## hive.yaml Schema

```yaml
version: 1
defaults:
  cli: claude # Global default agent CLI
  overlap: skip # skip | queue | parallel

bees:
  journal-bee:
    enabled: true
    schedule: "*/5 * * * *" # Cron syntax
    # cli: codex                 # Per-bee override
    # overlap: queue             # Per-bee override
    # memory: 5                  # Opt-in: access last N runs

  another-bee:
    enabled: false
    schedule: "0 9 * * *" # Daily at 9am
```

---

## Bee Structure (Agent Skills Compliant)

Each bee folder follows [agentskills.io/specification](https://agentskills.io/specification):

**SKILL.md** (required):

```yaml
---
name: journal-bee
description: Ambient journaling bee that gathers system context and composes reflective entries
allowed-tools: Read Write Bash WebSearch
---

# Journal Bee

Gather context about the current moment and compose a brief, reflective journal entry...

## Context Sources
- Date/time, weather, system uptime
- Run scripts/gather-context.sh for additional context

## Output
Append entry to ~/Code/bee/content/journal.md after user approval via notification.
```

**scripts/** (optional): Executable scripts for context gathering, run before main prompt.

---

## Menu Bar UI

### Icon States

- **Idle**: Default bee icon
- **Running**: Spinner or animated icon
- **Pending**: Badge with count of items needing attention
- **Error**: Red indicator

### Dropdown Structure

```
┌─────────────────────────────────┐
│ 🐝 Bee                          │
├─────────────────────────────────┤
│ ▶ journal-bee      ●  5m ago   │
│   another-bee      ○  disabled │
├─────────────────────────────────┤
│ ⏸ Pause All                    │
│ ⚙ Preferences...    ⌘,         │
│ ───────────────────             │
│ Quit Bee            ⌘Q         │
└─────────────────────────────────┘
```

### Bee Detail View (drill-down)

- Recent runs with status/duration
- "Open Logs Folder" button
- Enable/disable toggle
- Schedule display
- "Run Now" button

### Preferences Window (⌘,)

- Default CLI selection
- Hive folder location
- Default overlap behavior
- "Reveal hive.yaml" button

---

## Execution Flow

1. **Scheduler tick** → Check cron schedules against current time
2. **Overlap check** → Skip/queue/parallel per bee config
3. **Context gathering** → Run scripts from `scripts/` folder
4. **Agent invocation**:
   ```bash
   claude --print --allowedTools "Read Write Bash" \
     --systemPrompt "$(cat ~/.bee/journal-bee/SKILL.md)" \
     "$(cat /tmp/bee-context-journal-bee.txt)"
   ```
5. **Output handling** → Bee determines its own actions
6. **Confirmation** → Notification for actions requiring approval
7. **Logging** → Write run output to `~/.bee/logs/{bee-name}/{timestamp}.log`

---

## Notifications & Confirmations

- **On completion**: Native macOS notification with summary
- **On error**: Immediate notification with error details

### User Interaction Protocol (AskUser)

Bees can request user input during execution via the `AskUser` tool, exposed through a local MCP server.

**Tool Interface:**
```
AskUser(message: string, options?: string[]) → { response: string, action: 'accept' | 'reject' }
```

**Flow:**
1. Bee calls `AskUser` → Notification appears
2. User clicks notification → Reply window opens
3. User selects option or types response → Accept
4. User clicks reject or dismisses → Reject (task ends)
5. Response piped back to bee via stdin

**Behavior:**
- Tool always available to all bees (automatically injected via MCP)
- Multiple pending requests stack as separate notifications
- Dismiss = reject
- Default timeout: 5 minutes → auto-reject
- Per-bee timeout configurable in hive.yaml

**Reply Window:**
- Shows bee's message and predefined options
- Free text field for custom response
- Accept / Reject buttons
- Closes immediately after response

**Process Model:**
Bees run in conversational mode (not `--print`) to support back-and-forth. App monitors stdout for MCP tool calls, pipes responses via stdin.

---

## CLI Abstraction

Support multiple agent CLIs with consistent interface:

| CLI    | Invocation                          | Notes             |
| ------ | ----------------------------------- | ----------------- |
| claude | `claude --print --allowedTools ...` | Default           |
| codex  | `codex --quiet ...`                 | OpenAI            |
| cursor | `cursor --headless ...`             | Cursor agent mode |

Global default in hive.yaml, per-bee override available.

---

## MVP Scope

### Included

- [ ] SwiftUI menu bar app shell
- [ ] Auto-discover bees from ~/.bee/
- [ ] Parse hive.yaml for schedules/config
- [ ] Timer-based scheduling (cron evaluation)
- [ ] Claude CLI subprocess execution
- [ ] Basic dropdown UI (list bees, show status)
- [ ] Manual trigger via context menu
- [ ] Immediate error notifications
- [ ] Convert journal to first bee (journal-bee)

### Deferred

- Event triggers (file watchers, git hooks)
- Shared context store between bees
- Multi-CLI support beyond Claude
- Full history viewer with search
- Opt-in memory (access previous runs)

---

## Migration Plan

1. Create ~/.bee/ directory structure
2. Convert existing scripts:
   - `compose.sh` → `journal-bee/scripts/gather-context.sh` + SKILL.md instructions
   - `accept.sh` → App handles notification → append flow
   - `journal.md` → Stays at current location, bee writes to it
3. Create initial hive.yaml with journal-bee config
4. Deprecate launchd plist (app is now the scheduler)

---

## File Changes

### New Files

- `Bee.xcodeproj/` - Xcode project for SwiftUI app
- `Bee/` - Swift source files
  - `BeeApp.swift` - App entry, menu bar setup
  - `HiveManager.swift` - Parse hive.yaml, discover bees
  - `Scheduler.swift` - Cron evaluation, timer management
  - `BeeRunner.swift` - CLI subprocess execution
  - `MenuBarView.swift` - Dropdown UI
  - `PreferencesView.swift` - Settings window
- `~/.bee/hive.yaml` - Created at first launch
- `~/.bee/journal-bee/SKILL.md` - Migrated from current scripts

### Modified Files

- `PRJ.md` - Update with new architecture
- `CLAUDE.md` - Update development instructions
- `README.md` - If exists, update user docs

### Removed/Deprecated

- `com.bee.compose.plist` - No longer needed
- `compose.sh` - Logic moves to skill + app
- `accept.sh` - Logic moves to app
- `pending.md` - App manages pending state

---

## Open Questions (Resolved)

| Question             | Decision                                |
| -------------------- | --------------------------------------- |
| App shell tech       | Native Swift/SwiftUI                    |
| Bee discovery        | Auto-scan ~/.bee/ folder                |
| Bee isolation        | Isolated (shared context future)        |
| Scheduling mechanism | App manages timers                      |
| Execution model      | CLI subprocess                          |
| Feedback verbosity   | Configurable per-bee                    |
| Config location      | SKILL.md (spec) + hive.yaml (bee layer) |
| Context scripts      | scripts/ folder per spec                |
| Confirmation UI      | Notification + menu bar escalation      |
| Error handling       | Immediate notification                  |
| Overlap handling     | Configurable (default: skip)            |
| Schedule format      | Cron syntax                             |
| Event triggers       | Future enhancement                      |
| Data location        | ~/.bee/                                 |
| History              | Drill-down per bee + log folder access  |
| Settings UI          | Preferences window (⌘,)                 |
| Bee creation         | Discovery only, no wizard               |
| Tool allowlist       | Pass via CLI flag                       |
| Memory               | Opt-in per-bee                          |
| MVP scope            | Menu bar + multi-bee                    |
