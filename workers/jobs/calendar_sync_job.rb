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
         - Title, start time (ISO), end time (ISO), location, attendees, your response status
      4. For events without visible IDs, construct a pseudo-ID: outlook:{title-hash}:{start-iso-timestamp}
      5. Click into events if needed to get full details (attendees, location)

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
        | jq '.items[] | {id, summary, description, start, end}'
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
          "description": "[OUTLOOK-ID: {outlook_id}]\\n\\nAttendees: {attendee_list}\\nLocation: {location}",
          "location": "{location}",
          "start": {"dateTime": "{start_iso}", "timeZone": "#{Config.get("google_calendar.timezone")}"},
          "end": {"dateTime": "{end_iso}", "timeZone": "#{Config.get("google_calendar.timezone")}"}
        }'
      ```

      ### 5. Update Existing Events
      If an event exists but details changed (title, time, location):
      ```bash
      curl -s -X PATCH "https://www.googleapis.com/calendar/v3/calendars/${OUTLOOK_CAL_ID}/events/{gcal_event_id}" \\
        -H "Authorization: Bearer $ACCESS_TOKEN" \\
        -H "Content-Type: application/json" \\
        -d '{"summary": "{updated_title}", "location": "{updated_location}"}'
      ```

      ### 6. Report Results
      Summarize: mode, date range, events processed, created, already synced, updated, errors/skipped.

      ## Tips
      - Look for data-* attributes on event elements for IDs, or check the URL when viewing details
      - Try agenda/list view if week view is hard to parse
      - Wait for loading spinners before reading page
      - Scroll to trigger lazy loading of events
    ACTION
  end
end
