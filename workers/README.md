# Faktory Workers

Ruby workers that process jobs from the Faktory queue.

## Setup

```bash
cd workers
bundle install
```

## Configuration

Set these environment variables (add to your shell profile):

```bash
# Faktory connection (use your server's Tailscale IP)
export FAKTORY_URL="tcp://:your-password@100.x.x.x:7419"

# Which queues this machine should process
export FAKTORY_QUEUES="work-laptop,any"  # For work machine
# export FAKTORY_QUEUES="personal-mac,any"  # For personal machine
```

## Running the Worker

```bash
# Run directly
bundle exec ruby worker.rb

# Or with faktory-worker CLI
bundle exec faktory-worker -r ./worker.rb
```

## Job Types

| Job | Queue | Requires | Description |
|-----|-------|----------|-------------|
| `EmailCleanupJob` | work-laptop | Chrome, unlocked | Runs auto-archive-inbox skill |
| `GranolaSyncJob` | any | granola-cli | Syncs meeting notes to ~/Documents/granola-notes |
| `ClaudeJob` | any | Claude CLI | Generic job that runs any Claude prompt |

## Enqueuing Jobs

```bash
# From this machine
./bin/enqueue EmailCleanupJob
./bin/enqueue GranolaSyncJob '{"force": true}'

# Generic Claude task
./bin/enqueue ClaudeJob '"Summarize my calendar for today"'
```

## Adding New Jobs

Create a new file in `jobs/`:

```ruby
# jobs/my_new_job.rb
class MyNewJob
  include Faktory::Job

  faktory_options queue: "any"  # or "work-laptop", "personal-mac"

  def perform(options = {})
    # Your job logic here
    LOGGER.info "Running MyNewJob..."
  end
end
```

## Running as a LaunchAgent (macOS)

See `../launchagents/` for LaunchAgent plists you can install to run the worker automatically.
