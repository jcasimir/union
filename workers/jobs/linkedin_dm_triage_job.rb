# frozen_string_literal: true

# Job for triaging unread LinkedIn messages into Jira tasks
class LinkedinDmTriageJob < BrowserJob
  faktory_options queue: 'work-web', unique_for: 86_400

  def action_prompt(options)
    <<~ACTION.strip
      Triage my unread LinkedIn messages into Jira tasks. Use Chrome MCP browser tools (mcp__claude-in-chrome__*) for LinkedIn and Atlassian MCP tools for Jira.

      Steps:
      1. Navigate to #{Config.get("linkedin.feed_url")} in Chrome
      2. Once the feed loads, look for the Messaging icon/button in the top navigation bar (or a messaging panel at the bottom right) and click it to open messages
      3. Identify unread message conversations (they'll appear bold or have unread indicators/dots)
      4. For each unread message:
         a. Click the conversation to open it and read enough to understand the topic
         b. Note the person's name and a brief summary of what the message is about
         c. Copy the URL from the browser address bar — this is the direct link to the conversation (or note the person's name for the URL)
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
