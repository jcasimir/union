# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

This is the `workers/` directory of the Union project — Ruby workers that process jobs from a Faktory queue. See the parent `../CLAUDE.md` for overall architecture (Faktory server, Tailscale networking, job routing).

## Commands

```bash
bundle install                              # Install dependencies
bundle exec ruby worker.rb                  # Run worker (listens for jobs)
bundle exec faktory-worker -r ./worker.rb   # Alternative worker runner
./bin/enqueue EmailCleanupJob               # Enqueue a job
./bin/enqueue GranolaSyncJob '{"force": true}'
rake profile:validate[name]                 # Validate a person profile
rake profile:list                           # List all profiles with completeness
rake granola:sync                           # One-off Granola sync (standalone, no Faktory needed)
rake granola:status                         # Show local vs API meeting count
```

## Runtime

- Ruby 3.3.4 (managed via mise, see `mise.toml` and `.ruby-version`)
- Single gem dependency: `faktory_worker_ruby`
- No test suite exists currently

## Code Structure

**`worker.rb`** — Entry point. Loads all jobs from `jobs/`, configures Faktory worker lifecycle hooks, and defines `ClaudeJob` (a generic job that shells out to `claude` CLI). This file is loaded by `bundle exec faktory-worker -r ./worker.rb`.

**`jobs/`** — Each file defines one job class that includes `Faktory::Job` and declares its queue via `faktory_options queue:`.

**`Rakefile`** — Standalone task runner that stubs `Faktory::Job` so job classes can be instantiated without a Faktory connection. Used for `granola:sync` and `profile:validate` tasks.

**`bin/enqueue`** — Pushes a job to Faktory using `Faktory::Client`. Contains `QUEUE_MAP` that maps job class names to queue names — update this when adding new jobs with custom queues.

**`SessionHealthJob`** — Verifies Playwright sessions are authenticated and refreshes state files. Owns the `SERVICES` constant (single source of truth for service names, URLs, and auth patterns). `bin/auth-check` reads from `SessionHealthJob::SERVICES` — add new services only in the job class.

**`bin/enqueue-scheduled`** — Called by a LaunchAgent on a cron schedule. Contains time-based logic (hour/weekday checks) to enqueue jobs at specific times.

**`lib/profile_validator.rb`** — YAML profile validator, usable standalone (`ruby lib/profile_validator.rb profile.yaml`) or via Rake tasks.

## Key Patterns

- Jobs shell out to external CLIs (`claude`, `granola`) via `Open3` rather than using Ruby libraries
- `BrowserJob` subclasses use Playwright CLI (`playwright-cli`) for browser automation via persistent named sessions, not Chrome MCP
- `BrowserJob` checks macOS preconditions (screen unlocked via `ioreg`) and Playwright session readiness before executing; failed checks raise errors that trigger Faktory retries
- `GranolaSyncJob` does idempotent one-way sync by comparing 8-char short IDs embedded in local filenames (`[abc12345]`) against API results
- The Rakefile stubs `Faktory::Job` so jobs can run outside Faktory (e.g., `rake granola:sync`)

## Adding a New Job

1. Create `jobs/my_job.rb` with `include Faktory::Job` and `faktory_options queue: "any"`
2. Add queue mapping to `QUEUE_MAP` in `bin/enqueue` if using a non-default queue
3. Add scheduling logic to `bin/enqueue-scheduled` if the job should run on a cron

## Browser Automation

All browser jobs (`BrowserJob` subclasses) use Playwright CLI (`playwright-cli`) for browser automation. Each job declares a named Playwright session (e.g., `outlook`, `slack-greatminds`, `linkedin`) and Claude is invoked with `--model sonnet` (no `--chrome` flag).

Jobs that also need Jira/Confluence access (e.g., `SlackDmTriageJob`, `LinkedinDmTriageJob`) use Atlassian MCP tools alongside Playwright CLI — these are independent of browser automation.

### Session names
| Job | Session |
|-----|---------|
| `EmailCleanupJob` | `outlook` |
| `CalendarSyncJob` | `outlook-calendar` |
| `SlackDmTriageJob` | `slack-{workspace}` (e.g., `slack-greatminds`) |
| `LinkedinDmTriageJob` | `linkedin` |

### Auth check
Run `bin/auth-check` to interactively verify Playwright sessions are authenticated for all services. It opens headed Chromium windows, checks for auth, and saves state to `.auth-state/`. Service definitions (names, URLs, auth patterns) live in `SessionHealthJob::SERVICES` — `bin/auth-check` is a thin interactive wrapper around that constant.

```bash
bin/auth-check              # check all
bin/auth-check outlook      # check one
bin/auth-check --status     # show active sessions
```

Auth state files in `.auth-state/<name>.json` can be loaded with `playwright-cli -s=<name> state-load .auth-state/<name>.json` to restore a session without re-logging in (works until the token expires).
