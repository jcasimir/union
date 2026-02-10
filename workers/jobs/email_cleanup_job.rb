# frozen_string_literal: true

# Job for automated email inbox cleanup
class EmailCleanupJob < BrowserJob
  faktory_options queue: 'work-web', unique_for: 10_800

  def playwright_session
    "outlook"
  end

  def action_prompt(options)
    <<~ACTION.strip
      Automatically scan and archive low-priority emails from Outlook Web inbox.

      ## Browser Automation

      Use playwright-cli via Bash for all browser interaction. Session: -s=outlook

      Key commands:
      - playwright-cli -s=outlook goto <url>              # navigate
      - playwright-cli -s=outlook snapshot                 # get element refs
      - playwright-cli -s=outlook click <ref>              # click element
      - playwright-cli -s=outlook fill <ref> "<text>"      # fill input
      - playwright-cli -s=outlook screenshot --filename=<file>  # verify visually

      Always run `snapshot` to get refs before clicking. Read the snapshot output to find the correct ref.

      ## Archive Confidence Scoring

      ### High Confidence (95%) - Always Archive
      - Transient auth codes: Slack confirmation codes, Anthropic login links, verification codes
      - Automated digests: Confluence daily/weekly digest, Jira digest notifications
      - System notifications: Automated "no-reply" sender addresses

      ### Medium-High Confidence (90%) - Archive
      - Meeting responses: Subject contains "Accepted", "Meeting accepted", "Declined" (but NOT "Declined:" which may need attention)
      - Calendar notifications: Calendly "New Event:" notifications
      - Automated updates: Technology Bi-Weekly, newsletter-style recurring emails

      ### Medium Confidence (70-85%) - Review Case-by-Case
      - Company announcements, document shares without urgent context, non-actionable reminders

      ### Low Confidence (< 70%) - Keep in Inbox
      - ACTION ITEM in subject
      - Direct requests from colleagues with questions
      - IT tickets (TSD-* responses)
      - Warnings/alerts: suspension warnings, security alerts, deadline reminders
      - New meeting invites (not responses)

      ### Subject patterns to archive
      confirmation code, Secure link to log in, New Event:, Meeting accepted, Accepted:, daily digest, weekly digest, Technology Bi-Weekly

      ### Subject patterns to protect (never archive)
      ACTION ITEM, URGENT, TSD-\\d+, will be suspended, password expir, security alert

      ### Sender patterns to archive
      no-reply@, noreply@, notifications@, confluence@, jira@, calendly.com, slack.com

      ## Steps

      1. Navigate to #{Config.get("outlook.inbox_url")} using `playwright-cli -s=outlook goto`
      2. Run `snapshot` and scan the inbox, extracting for each email: sender name/email, subject, date, preview text
      3. Scroll down to load more emails. Repeat until end of inbox or emails older than 30 days
      4. Score each email using the confidence criteria above (default threshold: 85%)
      5. For emails meeting threshold: right-click the email row, select "Archive" from context menu, wait for confirmation, continue to next
      6. Write a summary log to `logs/email-cleanup/YYYY-MM-DD_HHMMSS.md` (create the directory if needed). Include:
         - Date/time and total scanned, total archived
         - List of archived items with subject, sender, score, reason
         - List of kept items below threshold
         - List of protected items that are never archived

      ## Error Handling
      - If archive action fails on an email, log and continue to next
      - If scroll doesn't load new emails after 3 attempts, assume end of inbox
      - Always output summary even if errors occur
    ACTION
  end
end
