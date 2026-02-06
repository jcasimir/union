# frozen_string_literal: true

require "open3"
require "fileutils"
require "json"

# One-way sync of Granola meeting notes to local markdown files.
# Compares local directory to API and downloads missing meetings.
#
# Uses granola-cli (npm install -g granola-cli)
# Auth: `granola auth login` imports tokens from the desktop app
class GranolaSyncJob
  include Faktory::Job

  faktory_options queue: "any"

  DEFAULT_NOTES_DIR = "~/GDrive/Meeting Notes/From Granola"
  NOTES_DIR = File.expand_path(ENV.fetch("GRANOLA_NOTES_PATH", DEFAULT_NOTES_DIR))

  def perform(options = {})
    LOGGER.info "Starting Granola sync..."

    FileUtils.mkdir_p(NOTES_DIR)

    # Fetch all meetings from API
    meetings = fetch_meetings(options["limit"] || 200)
    LOGGER.info "Found #{meetings.size} meetings in Granola"

    # Find which meeting IDs already exist locally
    local_ids = scan_local_meeting_ids
    LOGGER.info "Found #{local_ids.size} meetings synced locally"

    # Sync missing meetings
    missing = meetings.reject { |m| local_ids.include?(short_id(m["id"])) }
    LOGGER.info "#{missing.size} meetings to sync"

    synced_count = 0
    missing.each do |meeting|
      if sync_meeting(meeting, options)
        synced_count += 1
      end
    end

    LOGGER.info "Granola sync completed: #{synced_count} new meetings synced"
    { success: true, total: meetings.size, synced: synced_count }
  end

  private

  def fetch_meetings(limit)
    output, status = Open3.capture2("granola", "meeting", "list", "-o", "json", "--limit", limit.to_s)

    unless status.success?
      raise "Failed to list Granola meetings - is granola-cli installed? Run: granola auth login"
    end

    JSON.parse(output)
  end

  def scan_local_meeting_ids
    # Extract meeting IDs from filenames like: 2026-02-04-meeting-title-[abc12345].md
    ids = Dir.glob(File.join(NOTES_DIR, "*.md")).map do |path|
      filename = File.basename(path, ".md")
      # Match the [shortid] at the end of filename
      match = filename.match(/\[([a-f0-9]{8})\]$/)
      match ? match[1] : nil
    end
    ids.compact.to_set
  end

  def sync_meeting(meeting, options)
    meeting_id = meeting["id"]
    title = meeting["title"] || "Untitled"
    date = extract_date(meeting)

    LOGGER.info "Syncing: #{title} (#{date})"

    # Fetch enhanced notes (AI summary)
    content = fetch_enhanced_notes(meeting_id)

    if content.nil? || content.strip.empty?
      LOGGER.warn "  No enhanced notes available, skipping"
      return false
    end

    # Build markdown file with frontmatter
    markdown = build_markdown(meeting, content, options)

    # Write to file
    filename = build_filename(meeting)
    filepath = File.join(NOTES_DIR, filename)
    File.write(filepath, markdown)

    LOGGER.info "  Saved: #{filename}"
    true
  rescue => e
    LOGGER.error "  Failed to sync #{meeting_id}: #{e.message}"
    false
  end

  def fetch_enhanced_notes(meeting_id)
    output, status = Open3.capture2("granola", "meeting", "enhanced", meeting_id)
    status.success? ? output : nil
  end

  def fetch_transcript(meeting_id)
    output, status = Open3.capture2("granola", "meeting", "transcript", meeting_id)
    status.success? ? output : nil
  end

  def build_markdown(meeting, enhanced_notes, options)
    date = extract_date(meeting)
    title = meeting["title"] || "Untitled"
    attendees = extract_attendees(meeting)

    parts = []

    # YAML frontmatter
    parts << "---"
    parts << "title: \"#{title.gsub('"', '\\"')}\""
    parts << "date: #{date}"
    parts << "granola_id: #{meeting['id']}"
    parts << "attendees:"
    attendees.each { |a| parts << "  - #{a}" }
    parts << "---"
    parts << ""

    # Title and metadata
    parts << "# #{title}"
    parts << ""
    parts << "*#{date}*"
    parts << ""

    # Enhanced notes (AI summary)
    parts << enhanced_notes
    parts << ""

    # Optionally include transcript
    if options["include_transcript"]
      transcript = fetch_transcript(meeting["id"])
      if transcript && !transcript.strip.empty?
        parts << "---"
        parts << ""
        parts << "## Transcript"
        parts << ""
        parts << transcript
      end
    end

    parts.join("\n")
  end

  def build_filename(meeting)
    date = extract_date(meeting)
    title = meeting["title"] || "untitled"
    sid = short_id(meeting["id"])

    safe_title = title
      .gsub(/[^\w\s-]/, "")
      .gsub(/\s+/, "-")
      .downcase
      .slice(0, 50)
      .gsub(/-+$/, "")

    "#{date}-#{safe_title}-[#{sid}].md"
  end

  def extract_date(meeting)
    cal_event = meeting["google_calendar_event"]
    if cal_event && cal_event["start"]
      cal_event["start"]["date"]
    else
      meeting["created_at"]&.slice(0, 10) || "unknown"
    end
  end

  def extract_attendees(meeting)
    cal_event = meeting["google_calendar_event"]
    return [] unless cal_event && cal_event["attendees"]

    cal_event["attendees"].map { |a| a["displayName"] || a["email"] }.compact
  end

  def short_id(full_id)
    full_id.to_s.split("-").first
  end
end
