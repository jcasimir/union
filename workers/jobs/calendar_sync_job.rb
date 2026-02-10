# frozen_string_literal: true

# Job for syncing Outlook calendar to Google Calendar
#
# Usage:
#   enqueue CalendarSyncJob                        # defaults to "fast" (3 days)
#   enqueue CalendarSyncJob '{"mode": "mid"}'      # 14 days
#   enqueue CalendarSyncJob '{"mode": "full"}'     # 90 days
class CalendarSyncJob < BrowserJob
  faktory_options queue: 'work-web', unique_for: 7_200

  def playwright_session
    "outlook-calendar"
  end

  def action_prompt(options)
    mode = options["mode"] || "fast"
    <<~ACTION.strip
      Sync Outlook calendar events to Google Calendar. Use playwright-cli via Bash to read Outlook and curl via Bash for the Google Calendar API.

      ## Browser Automation

      Use playwright-cli via Bash for all browser interaction. Session: -s=outlook-calendar

      Key commands:
      - playwright-cli -s=outlook-calendar goto <url>              # navigate
      - playwright-cli -s=outlook-calendar snapshot                 # get element refs
      - playwright-cli -s=outlook-calendar click <ref>              # click element
      - playwright-cli -s=outlook-calendar fill <ref> "<text>"      # fill input
      - playwright-cli -s=outlook-calendar screenshot --filename=<file>  # verify visually

      Always run `snapshot` to get refs before clicking. Read the snapshot output to find the correct ref.

      Sync mode: #{mode}
      - fast = next 3 days
      - mid = next 14 days
      - full = next 90 days

      Target Google Calendar ID: #{Config.get("google_calendar.calendar_id")}
      Timezone: #{Config.get("google_calendar.timezone")}

      ## Environment Variables Available
      GCAL_CLIENT_ID, GCAL_CLIENT_SECRET, GCAL_REFRESH_TOKEN (already set in shell)

      ## Steps

      ### 1. Read Outlook Calendar (Browser)
      1. Navigate to #{Config.get("outlook.calendar_url")} using `playwright-cli -s=outlook-calendar goto`
      2. Run `snapshot` to get the calendar structure and element refs
      3. For each event in the date range, extract:
         - Title, start time (ISO), end time (ISO), meeting URL, attendees, your response status
      4. For events without visible IDs, construct a pseudo-ID: outlook:{title-hash}:{start-iso-timestamp}

      #### Extracting Meeting URLs (Critical)
      Almost every event has a Zoom URL. Extract it carefully:
      - In the week view snapshot, Zoom URLs appear as child elements of event buttons, e.g.:
        `- generic [ref=e649]: https://greatminds.zoom.us/j/95355532133?pwd=...`
        They also appear in the button's accessible name string.
      - Look for URLs matching `https://.*zoom.us/j/\\d+` in both the button label and child text nodes.
      - If an event does NOT have a visible Zoom URL in the week view, click into the event
        to open its detail view and look for the meeting link there. Press Escape to close the detail and continue.
      - Use the full Zoom URL (including ?pwd= and any query params) as the event's location.
      - Do NOT use the literal string "Zoom" as the location — always use the actual URL.
      - If no meeting URL can be found after checking the detail view, set location to empty string.

      ### 2. Get Google Calendar Access Token
      ```bash
      ACCESS_TOKEN=$(curl -s -X POST 'https://oauth2.googleapis.com/token' \\
        -d "client_id=${GCAL_CLIENT_ID}" \\
        -d "client_secret=${GCAL_CLIENT_SECRET}" \\
        -d "refresh_token=${GCAL_REFRESH_TOKEN}" \\
        -d 'grant_type=refresh_token' | jq -r '.access_token')
      OUTLOOK_CAL_ID="#{Config.get("google_calendar.calendar_id")}"
      ```

      ### 3. Check Existing Events in Google Calendar
      ```bash
      curl -s "https://www.googleapis.com/calendar/v3/calendars/${OUTLOOK_CAL_ID}/events" \\
        -H "Authorization: Bearer $ACCESS_TOKEN" \\
        -G \\
        --data-urlencode "timeMin=${START_DATE}T00:00:00Z" \\
        --data-urlencode "timeMax=${END_DATE}T23:59:59Z" \\
        --data-urlencode "maxResults=250" \\
        | jq '.items[] | {id, summary, description, location, start, end}'
      ```
      Find events with [OUTLOOK-ID: ...] in their description to identify already-synced events.

      ### 4. Create New Events
      For each Outlook event NOT already in Google Calendar:
      ```bash
      curl -s -X POST "https://www.googleapis.com/calendar/v3/calendars/${OUTLOOK_CAL_ID}/events" \\
        -H "Authorization: Bearer $ACCESS_TOKEN" \\
        -H "Content-Type: application/json" \\
        -d '{
          "summary": "{event_title}",
          "description": "[OUTLOOK-ID: {outlook_id}]\\n\\nAttendees: {attendee_list}",
          "location": "{zoom_url_or_empty}",
          "start": {"dateTime": "{start_iso}", "timeZone": "#{Config.get("google_calendar.timezone")}"},
          "end": {"dateTime": "{end_iso}", "timeZone": "#{Config.get("google_calendar.timezone")}"}
        }'
      ```
      IMPORTANT: The "location" field must be the full Zoom URL (e.g., https://greatminds.zoom.us/j/12345?pwd=abc),
      NOT the word "Zoom". Google Calendar makes the location clickable, so a real URL lets users join directly.

      ### 5. Update Existing Events
      For EVERY already-synced event, check if it needs a location update. PATCH the event if ANY of these are true:
      - The Google Calendar event has location "Zoom" (literal string) — replace with the real URL
      - The Google Calendar event has no location but Outlook has a Zoom URL
      - The title, start time, or end time changed

      Do NOT skip events just because the OUTLOOK-ID matches. You must compare the location field.

      ```bash
      curl -s -X PATCH "https://www.googleapis.com/calendar/v3/calendars/${OUTLOOK_CAL_ID}/events/{gcal_event_id}" \\
        -H "Authorization: Bearer $ACCESS_TOKEN" \\
        -H "Content-Type: application/json" \\
        -d '{"summary": "{title}", "location": "{zoom_url_or_empty}"}'
      ```

      ### 6. Report Results
      Summarize: mode, date range, events processed, created, already synced, updated, errors/skipped.

      ## Tips
      - In the week view snapshot, each event is a button element. The button's accessible name contains
        the title, time, and often the Zoom URL. Child generic elements also contain the URL as text.
      - Look for data-* attributes on event elements for IDs, or check the URL when viewing details
      - Try agenda/list view if week view is hard to parse
      - Wait for loading spinners before reading page
      - Scroll to trigger lazy loading of events
      - When clicking into an event for details, look for "Join" links or URLs in the detail panel
    ACTION
  end
end
