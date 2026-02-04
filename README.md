# Union

A distributed job queue for personal automation tasks, powered by [Faktory](https://github.com/contribsys/faktory) and accessible via Tailscale.

*Union brings together your machines, your tasks, and your time.*

## Architecture

```
                    Tailscale Network
┌──────────────────────────────────────────────────────────────┐
│                                                              │
│   ┌─────────────────────┐                                    │
│   │  Faktory Server     │                                    │
│   │  (Home Linux box)   │                                    │
│   │  100.x.x.x:7419     │                                    │
│   └─────────────────────┘                                    │
│            ▲                                                 │
│            │                                                 │
│   ┌────────┴────────┐               ┌───────────────┐       │
│   │  Work MacBook   │               │ Personal Mac  │       │
│   │  Worker:        │               │ Worker:       │       │
│   │  work-laptop    │               │ personal-mac  │       │
│   └─────────────────┘               └───────────────┘       │
│                                                              │
└──────────────────────────────────────────────────────────────┘
```

## Components

| Directory | Purpose |
|-----------|---------|
| `faktory-server/` | Docker setup for Faktory server (deploy to home server) |
| `workers/` | Ruby workers that process jobs (run on each Mac) |
| `launchagents/` | macOS LaunchAgents for persistence (install manually) |

## Quick Start

### 1. Deploy Faktory Server

Copy `faktory-server/` to your home Linux server and run:

```bash
cp .env.example .env
# Edit .env with your Tailscale IP and a strong password
docker-compose up -d
```

### 2. Set Up Worker on Mac

```bash
cd workers
bundle install

# Set environment variables
export FAKTORY_URL="tcp://:your-password@100.x.x.x:7419"
export FAKTORY_QUEUES="work-laptop,any"

# Test the worker
bundle exec ruby worker.rb
```

### 3. Install LaunchAgents

Edit the plists in `launchagents/` with your configuration, then:

```bash
# YOU must run these commands (not Claude) to avoid SentinelOne detection
cp launchagents/*.plist ~/Library/LaunchAgents/
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.user.faktory-worker.plist
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.user.scheduled-jobs.plist
```

## Job Types

| Job | Queue | Requirements | Description |
|-----|-------|--------------|-------------|
| `EmailCleanupJob` | work-laptop | Chrome, screen unlocked | Auto-archive inbox emails |
| `GranolaSyncJob` | any | granola-cli installed | Sync meeting notes to local files |
| `ClaudeJob` | any | Claude CLI | Run arbitrary Claude prompts |

## Condition-Based Execution

Jobs that require specific conditions (like `EmailCleanupJob` needing an unlocked screen) will check those conditions before executing. If conditions aren't met, the job raises an error and Faktory will retry later.

## Why This Architecture?

- **Tailscale** = Secure access from anywhere without public exposure
- **Faktory** = Battle-tested job queue with web UI, retries, scheduling
- **Queues for routing** = Jobs go to specific machines (work-laptop, personal-mac, any)
- **Manual LaunchAgent install** = Avoids SentinelOne flagging Claude for persistence
