# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

Union is a distributed job queue for personal automation, powered by Faktory and accessible via Tailscale. It enables jobs to be enqueued from anywhere and routed to specific machines (work-web, personal-mac, or any) for execution.

## Architecture

```
Tailscale Network
├── Faktory Server (home Linux box) - Central job queue with web UI
│   └── Docker container on ports 7419 (workers) / 7420 (web UI)
│
└── Worker Machines (Macs) - Process jobs from specific queues
    └── Ruby workers using faktory_worker_ruby gem
```

**Job routing**: Jobs specify a queue (e.g., `work-web`, `any`). Workers subscribe to queues matching their machine, enabling machine-specific automation.

**Condition checking**: Jobs like `EmailCleanupJob` verify preconditions (screen unlocked, Chrome running) before executing. Failed conditions raise errors triggering Faktory retries.

## Commands

### Workers (Ruby)

```bash
cd workers
bundle install                              # Install dependencies
bundle exec ruby worker.rb                  # Run worker (processes jobs)
bundle exec faktory-worker -r ./worker.rb   # Alternative: use faktory CLI
```

### Enqueue Jobs

```bash
cd workers
./bin/enqueue EmailCleanupJob                          # Basic enqueue
./bin/enqueue GranolaSyncJob '{"force": true}'        # With options
./bin/enqueue ClaudeJob '"Run the /commit skill"'     # Generic Claude task
```

### Faktory Server (Docker)

```bash
cd faktory-server
docker-compose up -d          # Start server
docker-compose logs -f        # View logs
docker-compose down           # Stop server
```

### LaunchAgents

LaunchAgents must be installed manually by the user to avoid SentinelOne detection:

```bash
launchctl print gui/$(id -u)/com.user.faktory-worker    # Check status
tail -f /tmp/faktory-worker.log                          # View logs
launchctl bootout gui/$(id -u)/com.user.faktory-worker  # Stop
```

## Key Environment Variables

- `FAKTORY_URL` - Connection string: `tcp://:password@100.x.x.x:7419`
- `FAKTORY_QUEUES` - Comma-separated queues to process: `work-web,any`

## Adding New Jobs

Create `workers/jobs/my_job.rb`:

```ruby
class MyJob
  include Faktory::Job
  faktory_options queue: "any"  # or "work-web", "personal-mac"

  def perform(options = {})
    # Job logic here
  end
end
```

Add queue mapping to `workers/bin/enqueue` if using a custom queue.

## Important Constraints

- **LaunchAgent installation**: Must be done by the user, not Claude, to avoid security software flags
- **Screen lock detection**: `EmailCleanupJob` uses macOS Quartz API to check if screen is locked
- **Claude integration**: Jobs can invoke Claude CLI with `--dangerously-skip-permissions` for automated execution
