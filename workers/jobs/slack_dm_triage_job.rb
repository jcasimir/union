# frozen_string_literal: true

# Job for triaging unread Slack DMs into Jira tasks
#
# Usage:
#   enqueue SlackDmTriageJob '{"workspace": "greatminds"}'
#   enqueue SlackDmTriageJob '{"workspace": "turing"}'
class SlackDmTriageJob < BrowserJob
  faktory_options queue: 'work-web', unique_for: 86_400

  def action_prompt(options)
    workspace_key = options["workspace"] || "greatminds"
    workspaces = Config.get("slack.workspaces")
    workspace = workspaces[workspace_key]
    raise "Unknown workspace: #{workspace_key}" unless workspace

    prefix = workspace["prefix"]
    <<~ACTION.strip
      Triage my unread Slack DMs into Jira tasks. Use Chrome MCP browser tools (mcp__claude-in-chrome__*) for Slack and Atlassian MCP tools for Jira.

      Steps:
      1. Navigate directly to #{workspace["url"]}/unreads in Chrome (do NOT go to slack.com — go to the workspace URL directly to avoid app redirect)
      2. Look at the Direct Messages section for unread DM conversations (they'll appear bold or have unread indicators)
      3. For each unread DM:
         a. Open the conversation and read enough to understand the topic
         b. Note the person's name and a brief summary of what the DM is about
         c. Copy the URL from the browser address bar — this is the direct link to the DM
         d. Search Jira project #{Config.get("jira.project_key")} for existing open tasks with summary containing "#{prefix}:" and that person's name using the Atlassian MCP searchJiraIssuesUsingJql tool with cloudId "#{Config.get("jira.cloud_id")}" and JQL like: project = #{Config.get("jira.project_key")} AND summary ~ "#{prefix}: PersonName" AND status != Done
         e. If no existing task found, create a new Jira Task in project #{Config.get("jira.project_key")} using the Atlassian MCP createJiraIssue tool with:
            - summary: "#{prefix}: {PersonName} about {brief topic}" — for group DMs, use the first person's name plus a count like "#{prefix}: Kyle +2 about project timeline" (meaning Kyle and 2 others)
            - description: A brief summary of the DM content and any action needed
            - additional_fields: {"url": "{slack_dm_url}"}
         f. In the message input box, type: /remind me to respond to this DM in 1 hour
            Then press Enter to send the remind command
      4. After processing all DMs, summarize how many were found and how many Jira tasks were created vs already existed
    ACTION
  end
end
