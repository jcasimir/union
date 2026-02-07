# frozen_string_literal: true

require "yaml"

module Config
  class MissingKeyError < StandardError; end
  class ConfigNotFoundError < StandardError; end

  CONFIG_PATH = File.expand_path("../config.yml", __dir__)

  REQUIRED_KEYS = %w[
    faktory.url
    jira.cloud_id
    jira.project_key
    google_calendar.client_id
    google_calendar.client_secret
    google_calendar.refresh_token
    google_calendar.calendar_id
    google_calendar.timezone
    slack.workspaces
    outlook.inbox_url
    outlook.calendar_url
    linkedin.feed_url
    granola.notes_dir
  ].freeze

  @data = nil

  def self.load!
    unless File.exist?(CONFIG_PATH)
      raise ConfigNotFoundError,
        "Config file not found: #{CONFIG_PATH}\nCopy config.yml.example to config.yml and fill in your values."
    end

    @data = YAML.safe_load(File.read(CONFIG_PATH), permitted_classes: [Symbol])
  end

  def self.get(dot_path)
    load! unless @data

    keys = dot_path.split(".")
    value = @data
    keys.each do |key|
      if value.is_a?(Hash) && value.key?(key)
        value = value[key]
      else
        raise MissingKeyError, "Config key not found: #{dot_path}"
      end
    end
    value
  end

  def self.validate!
    load! unless @data

    missing = REQUIRED_KEYS.select do |dot_path|
      get(dot_path).nil?
    rescue MissingKeyError
      true
    end

    return if missing.empty?

    raise MissingKeyError,
      "Missing required config keys:\n#{missing.map { |k| "  - #{k}" }.join("\n")}\nCheck workers/config.yml"
  end

  def self.export_env!
    load! unless @data

    # Faktory gem reads FAKTORY_URL from env
    ENV["FAKTORY_URL"] ||= get("faktory.url")

    # Google Calendar credentials for curl commands in Claude sessions
    ENV["GCAL_CLIENT_ID"] ||= get("google_calendar.client_id")
    ENV["GCAL_CLIENT_SECRET"] ||= get("google_calendar.client_secret")
    ENV["GCAL_REFRESH_TOKEN"] ||= get("google_calendar.refresh_token")
  rescue MissingKeyError
    # Skip env export for keys that don't exist (e.g., on machines that don't need gcal)
  end

  def self.reset!
    @data = nil
  end
end
