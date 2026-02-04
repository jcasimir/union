#!/usr/bin/env ruby
# frozen_string_literal: true

require "faktory_worker_ruby"
require "open3"
require "logger"
require "json"

# Configure logging
LOGGER = Logger.new($stdout)
LOGGER.level = Logger::INFO

# Load all job classes
Dir[File.join(__dir__, "jobs", "*.rb")].each { |f| require f }

# Faktory configuration
Faktory.configure_worker do |config|
  # Queues this worker processes (in priority order)
  # Set via FAKTORY_QUEUES env var, e.g., "work-laptop,any"
  queues = ENV.fetch("FAKTORY_QUEUES", "any").split(",")
  config.queues = queues

  LOGGER.info "Worker configured for queues: #{queues.join(', ')}"
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

# Start the worker if run directly
if __FILE__ == $PROGRAM_NAME
  LOGGER.info "Starting Faktory worker..."
  LOGGER.info "FAKTORY_URL: #{ENV['FAKTORY_URL']&.gsub(/:[^:@]+@/, ':***@')}"

  # Run the worker
  Faktory::CLI.new.run
end
