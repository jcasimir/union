# frozen_string_literal: true

require "open3"
require "shellwords"

# Base class for jobs that run Claude with Playwright CLI browser automation.
# Subclasses define `action_prompt(options)` and optionally override
# `job_name` or `playwright_session`.
#
# Example:
#   class MyJob < BrowserJob
#     faktory_options queue: 'work-web', unique_for: 3_600
#
#     def playwright_session
#       "outlook"
#     end
#
#     def action_prompt(options)
#       "Do the thing using playwright-cli -s=outlook via Bash."
#     end
#   end
class BrowserJob
  include Faktory::Job

  AUTH_STATE_DIR = File.expand_path("../../.auth-state", __dir__)

  def perform(options = {})
    LOGGER.info "Starting #{job_name}..."

    unless screen_unlocked?
      raise RetryLater, "Screen is locked - will retry when unlocked"
    end

    session = playwright_session
    unless playwright_session_ready?(session)
      LOGGER.info "Playwright session '#{session}' not ready, attempting state-load..."
      state_file = File.join(AUTH_STATE_DIR, "#{session}.json")
      if File.exist?(state_file)
        system("playwright-cli", "-s=#{session}", "state-load", state_file)
      else
        raise RetryLater, "No auth state for '#{session}' — run bin/auth-check #{session}"
      end
    end

    prompt = action_prompt(options)
    LOGGER.info "Running Claude with Playwright CLI (session: #{session})..."

    stdout, stderr, status = Open3.capture3(
      File.expand_path("~/.local/bin/claude"), "--dangerously-skip-permissions", "--model", "sonnet", "-p", prompt
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

  # Override in subclasses to specify the Playwright session name
  def playwright_session
    "outlook"
  end

  private

  def job_name
    self.class.name
  end

  def screen_unlocked?
    result = `/usr/sbin/ioreg -n Root -d1 -a | /usr/bin/plutil -extract IOConsoleLocked raw - 2>/dev/null`.strip
    result == "false"
  rescue
    true
  end

  def playwright_session_ready?(session)
    output = `playwright-cli list 2>&1`
    output.include?(session)
  rescue
    false
  end

  class RetryLater < StandardError; end
end
