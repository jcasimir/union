# frozen_string_literal: true

require "open3"
require "fileutils"

# Job for syncing Granola meeting notes to local files
# Does NOT require browser - uses granola-cli
class GranolaSyncJob
  include Faktory::Job

  faktory_options queue: "any"  # Can run on any machine with granola-cli

  NOTES_DIR = File.expand_path("~/Documents/granola-notes")

  def perform(options = {})
    LOGGER.info "Starting Granola sync job..."

    # Ensure output directory exists
    FileUtils.mkdir_p(NOTES_DIR)

    # Get list of recent meetings
    meetings_json = `granola-cli meeting list --format json --limit 50 2>/dev/null`

    unless $?.success?
      raise "Failed to list Granola meetings - is granola-cli installed and authenticated?"
    end

    meetings = JSON.parse(meetings_json)
    synced_count = 0

    meetings.each do |meeting|
      meeting_id = meeting["id"]
      filename = safe_filename(meeting)
      filepath = File.join(NOTES_DIR, filename)

      # Skip if already synced (could add checksum comparison later)
      next if File.exist?(filepath) && !options["force"]

      # Export meeting to markdown
      LOGGER.info "Syncing: #{meeting['title']}"
      markdown = `granola-cli meeting export #{meeting_id} --format markdown 2>/dev/null`

      if $?.success?
        File.write(filepath, markdown)
        synced_count += 1
      else
        LOGGER.warn "Failed to export meeting #{meeting_id}"
      end
    end

    LOGGER.info "Granola sync completed: #{synced_count} meetings synced"
    { success: true, synced: synced_count }
  end

  private

  def safe_filename(meeting)
    date = meeting["date"]&.split("T")&.first || "unknown"
    title = meeting["title"] || "untitled"

    # Sanitize title for filesystem
    safe_title = title
      .gsub(/[^\w\s-]/, "")
      .gsub(/\s+/, "-")
      .downcase[0..50]

    "#{date}-#{safe_title}.md"
  end
end
