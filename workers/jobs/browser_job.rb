# frozen_string_literal: true

require "json"
require "fileutils"

# Base class for jobs that dispatch task files to a persistent Claude session.
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

  TASKS_DIR = File.expand_path("../tasks", __dir__)
  PENDING_DIR = File.join(TASKS_DIR, "pending")
  DONE_DIR = File.join(TASKS_DIR, "done")
  POLL_INTERVAL = 5
  POLL_TIMEOUT = 1800

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

    jid = SecureRandom.hex(12)
    write_task(jid, options)
    wait_for_result(jid)
  end

  # Subclasses must implement this
  def action_prompt(options)
    raise NotImplementedError, "#{self.class} must implement #action_prompt"
  end

  private

  def job_name
    self.class.name
  end

  def write_task(jid, options)
    FileUtils.mkdir_p(PENDING_DIR)
    task = {
      jid: jid,
      job: job_name,
      action: action_prompt(options),
      created_at: Time.now.utc.strftime("%Y-%m-%dT%H:%M:%SZ")
    }
    path = File.join(PENDING_DIR, "#{jid}.json")
    File.write(path, JSON.pretty_generate(task))
    LOGGER.info "Wrote task file: #{path}"
  end

  def wait_for_result(jid)
    result_path = File.join(DONE_DIR, "#{jid}.json")
    elapsed = 0

    while elapsed < POLL_TIMEOUT
      if File.exist?(result_path)
        result = JSON.parse(File.read(result_path))
        LOGGER.info "Task #{jid} completed: #{result['status']}"
        LOGGER.info "Output: #{result['output']}"

        if result['status'] == 'error'
          raise "#{job_name} failed: #{result['output']}"
        end

        return { success: true, output: result['output'] }
      end

      sleep POLL_INTERVAL
      elapsed += POLL_INTERVAL
      LOGGER.info "Waiting for task #{jid} result... (#{elapsed}s)" if (elapsed % 30).zero?
    end

    raise "Task #{jid} timed out after #{POLL_TIMEOUT}s - no result file found"
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
