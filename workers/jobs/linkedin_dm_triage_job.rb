# frozen_string_literal: true

# Job for triaging unread LinkedIn messages into Jira tasks
class LinkedinDmTriageJob < BrowserJob
  faktory_options queue: 'work-web', unique_for: 86_400

  def playwright_session
    "linkedin"
  end

  def action_prompt(options)
    <<~ACTION.strip
      Triage my unread LinkedIn messages into Jira tasks. Use playwright-cli via Bash for LinkedIn browsing and Atlassian MCP tools for Jira.

      ## Browser Automation

      Use playwright-cli via Bash for all LinkedIn browser interaction. Session: -s=linkedin

      Key commands:
      - playwright-cli -s=linkedin goto <url>              # navigate
      - playwright-cli -s=linkedin snapshot                 # get element refs
      - playwright-cli -s=linkedin click <ref>              # click element
      - playwright-cli -s=linkedin fill <ref> "<text>"      # fill input
      - playwright-cli -s=linkedin screenshot --filename=<file>  # verify visually

      Always run `snapshot` to get refs before clicking. Read the snapshot output to find the correct ref.

      ## Steps

      1. Navigate to #{Config.get("linkedin.feed_url")} using `playwright-cli -s=linkedin goto`
      2. Once the feed loads, run `snapshot` and look for the Messaging icon/button in the top navigation bar (or a messaging panel at the bottom right) and click its ref to open messages
      3. Run `snapshot` again and identify unread message conversations (they'll appear bold or have unread indicators/dots)
      4. For each unread message:
         a. Click the conversation ref to open it and read enough to understand the topic
         b. Note the person's name and a brief summary of what the message is about
         c. Get the current URL using `playwright-cli -s=linkedin evaluate "window.location.href"` — this is the direct link to the conversation
         d. Search Jira project #{Config.get("jira.project_key")} for existing open tasks with summary containing "LI-DM:" and that person's name using the Atlassian MCP searchJiraIssuesUsingJql tool with cloudId "#{Config.get("jira.cloud_id")}" and JQL like: project = #{Config.get("jira.project_key")} AND summary ~ "LI-DM: PersonName" AND status != Done
         e. If no existing task found, create a new Jira Task in project #{Config.get("jira.project_key")} using the Atlassian MCP createJiraIssue tool with:
            - summary: "LI-DM: {PersonName} about {brief topic}" — for group messages, use the first person's name plus a count like "LI-DM: Kyle +2 about project timeline" (meaning Kyle and 2 others)
            - description: A brief summary of the message content and any action needed
            - additional_fields: {"url": "{linkedin_conversation_url}"}
      5. Skip any messages that are clearly spam, recruiter templates, or automated LinkedIn notifications — only create tasks for genuine conversations that need a response
      6. After processing all messages, summarize how many were found, how many were skipped as spam, and how many Jira tasks were created vs already existed
    ACTION
  end
end
