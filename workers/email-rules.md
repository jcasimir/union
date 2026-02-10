# Email Cleanup Rules

Rules for automated inbox cleanup. Edit this file to change what gets archived.
The EmailCleanupJob reads this file at runtime — push changes and restart the worker.

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

## Subject patterns to archive
confirmation code, Secure link to log in, New Event:, Meeting accepted, Accepted:, daily digest, weekly digest, Technology Bi-Weekly

## Subject patterns to protect (never archive)
ACTION ITEM, URGENT, TSD-\d+, will be suspended, password expir, security alert

## Sender patterns to archive
no-reply@, noreply@, notifications@, confluence@, jira@, calendly.com, slack.com
