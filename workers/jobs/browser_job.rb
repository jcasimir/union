# frozen_string_literal: true

require "open3"
require "shellwords"

# Base class for jobs that run Claude with Chrome MCP browser tools.
# Subclasses define `action_prompt(options)` and optionally override `job_name`.
#
# Example:
#   class MyJob < BrowserJob
#     faktory_options queue: 'work-web', unique_for: 3_600
#
#     def action_prompt(options)
#       "Do the thing using Chrome MCP browser tools."
#     end
#   end
class BrowserJob
  include Faktory::Job

  def perform(options = {})
    LOGGER.info "Starting #{job_name}..."

    unless screen_unlocked?
      raise RetryLater, "Screen is locked - will retry when unlocked"
    end

    unless chrome_running?
      LOGGER.info "Chrome not running, attempting to launch..."
      system("open -a 'Google Chrome'")
      sleep 3
    end

    prompt = action_prompt(options)
    LOGGER.info "Running Claude with Chrome MCP..."

    stdout, stderr, status = Open3.capture3(
      "claude", "--dangerously-skip-permissions", "--chrome", "-p", prompt
    )

    if status.success?
      LOGGER.info "#{job_name} completed successfully"
      { success: true, output: stdout }
    else
      LOGGER.error "#{job_name} failed: #{stderr}"
      raise "#{job_name} failed: #{stderr}"
    end
  end

  # Subclasses must implement this
  def action_prompt(options)
    raise NotImplementedError, "#{self.class} must implement #action_prompt"
  end

  private

  def job_name
    self.class.name
  end

  def screen_unlocked?
    result = `ioreg -n Root -d1 -a | plutil -extract IOConsoleLocked raw - 2>/dev/null`.strip
    result == "false"
  rescue
    true
  end

  def chrome_running?
    system("pgrep -x 'Google Chrome' > /dev/null 2>&1")
  end

  class RetryLater < StandardError; end
end
