# frozen_string_literal: true

require "open3"
require "shellwords"

# Job for automated email inbox cleanup
# Requires: Chrome running, MCP extension active, screen unlocked
class EmailCleanupJob
  include Faktory::Job

  faktory_options queue: "work-laptop"  # Only runs on work machine

  def perform(options = {})
    LOGGER.info "Starting email cleanup job..."

    # Check preconditions
    unless screen_unlocked?
      raise RetryLater, "Screen is locked - will retry when unlocked"
    end

    unless chrome_running?
      LOGGER.info "Chrome not running, attempting to launch..."
      system("open -a 'Google Chrome'")
      sleep 3
    end

    # Run the Claude auto-archive skill
    prompt = "Run the /auto-archive-inbox skill"

    stdout, stderr, status = Open3.capture3(
      "claude", "--dangerously-skip-permissions", "-p", prompt
    )

    if status.success?
      LOGGER.info "Email cleanup completed"
      { success: true, output: stdout }
    else
      LOGGER.error "Email cleanup failed: #{stderr}"
      raise "Email cleanup failed: #{stderr}"
    end
  end

  private

  def screen_unlocked?
    # Check if screen is locked on macOS
    result = `python3 -c "import Quartz; d=Quartz.CGSessionCopyCurrentDictionary(); print('unlocked' if not d.get('CGSSessionScreenIsLocked', False) else 'locked')" 2>/dev/null`.strip
    result == "unlocked"
  rescue
    true  # Assume unlocked if check fails
  end

  def chrome_running?
    system("pgrep -x 'Google Chrome' > /dev/null 2>&1")
  end

  # Custom error for jobs that should retry later
  class RetryLater < StandardError; end
end
