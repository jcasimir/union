#!/usr/bin/env ruby
# frozen_string_literal: true

require "faktory_worker_ruby"
require "open3"
require "logger"
require "json"

# Configure logging
LOGGER = Logger.new($stdout)
LOGGER.level = Logger::INFO

# Load config and set env vars before anything else
require_relative "lib/config"
Config.export_env!
Config.validate!

# Load all job classes
Dir[File.join(__dir__, "jobs", "*.rb")].each { |f| require f }

# Log when jobs start and finish
Faktory.configure_worker do |mgr|
  mgr.on(:startup) do
    queues = Faktory.options&.dig(:queues) || ["default"]
    LOGGER.info "Worker ready, listening on queues: #{queues.join(', ')}. Waiting for jobs..."
  end
  mgr.on(:quiet) { LOGGER.info "Worker going quiet (shutting down soon)..." }
  mgr.on(:shutdown) { LOGGER.info "Worker shutting down" }
end

# Base class for jobs that run Claude commands
class ClaudeJob
  include Faktory::Job

  def perform(task_prompt, options = {})
    LOGGER.info "Executing Claude task: #{task_prompt[0..50]}..."

    # Build the Claude command
    cmd = build_claude_command(task_prompt, options)
    LOGGER.debug "Command: #{cmd}"

    # Execute and capture output
    stdout, stderr, status = Open3.capture3(cmd)

    if status.success?
      LOGGER.info "Task completed successfully"
      { success: true, output: stdout }
    else
      LOGGER.error "Task failed: #{stderr}"
      raise "Claude task failed: #{stderr}"
    end
  end

  private

  def build_claude_command(prompt, options)
    parts = ["claude"]

    # Skip permission prompts for automated execution
    parts << "--dangerously-skip-permissions" if options["skip_permissions"] != false

    # Add the prompt
    parts << "-p"
    parts << Shellwords.escape(prompt)

    parts.join(" ")
  end
end

# Start the worker with: bundle exec faktory-worker -r ./worker.rb
