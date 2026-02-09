# frozen_string_literal: true

# Verifies that Playwright CLI sessions are authenticated for each
# work service. Navigates to each service URL, checks the page snapshot
# for auth indicators, and refreshes saved state files for healthy sessions.
#
# Can check all services or a single one:
#   SessionHealthJob.new.perform                          # all
#   SessionHealthJob.new.perform("service" => "outlook")  # just outlook
#
# bin/auth-check reads SERVICES from this class — add new services here only.
class SessionHealthJob
  include Faktory::Job
  faktory_options queue: "any", unique_for: 3_600

  AUTH_STATE_DIR = BrowserJob::AUTH_STATE_DIR

  # Single source of truth for all Playwright-managed services.
  # bin/auth-check reads from here — add new services only in this hash.
  SERVICES = {
    "outlook" => {
      url_key: "outlook.inbox_url",
      pattern: /inbox|focused|other/i
    },
    "outlook-calendar" => {
      url_key: "outlook.calendar_url",
      pattern: /calendar|today|week/i
    },
    "slack-greatminds" => {
      url_key: "slack.workspaces.greatminds.url",
      pattern: /unreads|threads|channel/i
    },
    "slack-turing" => {
      url_key: "slack.workspaces.turing.url",
      pattern: /unreads|threads|channel/i
    },
    "jira" => {
      url_key: nil,
      static_url: "https://digital-greatminds.atlassian.net/jira/core/projects/JC/board",
      pattern: /board|backlog|sprint/i
    },
    "linkedin" => {
      url_key: "linkedin.feed_url",
      pattern: /feed|home|network/i
    }
  }.freeze

  def perform(options = {})
    target = options["service"]
    services = target ? { target => SERVICES.fetch(target) } : SERVICES

    results = services.map { |name, config| [name, check_service(name, config)] }

    healthy = results.select { |_, ok| ok }
    unhealthy = results.reject { |_, ok| ok }

    LOGGER.info "Session health: #{healthy.length}/#{results.length} OK"
    unhealthy.each { |name, _| LOGGER.warn "Session '#{name}' unhealthy" }

    { healthy: healthy.map(&:first), unhealthy: unhealthy.map(&:first) }
  end

  def self.url_for(name)
    config = SERVICES.fetch(name)
    config[:static_url] || Config.get(config[:url_key])
  end

  private

  def check_service(name, config)
    url = config[:static_url] || Config.get(config[:url_key])

    unless session_active?(name)
      state_file = File.join(AUTH_STATE_DIR, "#{name}.json")
      if File.exist?(state_file)
        run_cli(name, "state-load", state_file)
        run_cli(name, "open", url)
      else
        LOGGER.warn "No auth state for '#{name}'"
        return false
      end
    end

    run_cli(name, "goto", url)
    sleep 2
    snapshot, ok = run_cli(name, "snapshot")
    return false unless ok

    if snapshot.match?(config[:pattern])
      run_cli(name, "state-save", File.join(AUTH_STATE_DIR, "#{name}.json"))
      true
    else
      false
    end
  end

  def session_active?(name)
    output, = run_cli("_", "list")
    output.include?(name)
  end

  def run_cli(session, *args)
    cmd = ["playwright-cli", "-s=#{session}", *args]
    output = `#{cmd.join(" ")} 2>&1`
    [output, $?.success?]
  end
end
