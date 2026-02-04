# LaunchAgents

macOS LaunchAgents for running Faktory workers and scheduled job enqueueing.

**Important:** These must be installed manually by YOU to avoid SentinelOne flagging Claude for creating persistence mechanisms.

## Installation

1. **Edit the plists** to update:
   - `FAKTORY_URL` with your server's Tailscale IP and password
   - `FAKTORY_QUEUES` with the queues this machine should process
   - Paths if your project isn't at `~/Projects/granola-sync`

2. **Copy to LaunchAgents:**
   ```bash
   cp com.user.faktory-worker.plist ~/Library/LaunchAgents/
   cp com.user.scheduled-jobs.plist ~/Library/LaunchAgents/
   ```

3. **Load them:**
   ```bash
   launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.user.faktory-worker.plist
   launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.user.scheduled-jobs.plist
   ```

## Managing

```bash
# Check status
launchctl print gui/$(id -u)/com.user.faktory-worker

# View logs
tail -f /tmp/faktory-worker.log
tail -f /tmp/scheduled-jobs.log

# Stop
launchctl bootout gui/$(id -u)/com.user.faktory-worker

# Reload after editing
launchctl bootout gui/$(id -u)/com.user.faktory-worker
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.user.faktory-worker.plist
```

## What Each Does

| Plist | Purpose |
|-------|---------|
| `com.user.faktory-worker.plist` | Runs the Ruby worker continuously, processing jobs from the queue |
| `com.user.scheduled-jobs.plist` | Runs at 6 AM daily to enqueue scheduled jobs |

## Customizing Schedules

Edit `com.user.scheduled-jobs.plist` to change when jobs are enqueued:

```xml
<!-- Run at 9 AM on weekdays -->
<key>StartCalendarInterval</key>
<array>
    <dict>
        <key>Weekday</key><integer>1</integer>  <!-- Monday -->
        <key>Hour</key><integer>9</integer>
        <key>Minute</key><integer>0</integer>
    </dict>
    <!-- Repeat for Tue-Fri -->
</array>
```

Or edit `workers/bin/enqueue-scheduled` to add more job types and conditions.
