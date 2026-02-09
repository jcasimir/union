# frozen_string_literal: true

# Job for triaging unread Slack DMs into Jira tasks
#
# Usage:
#   enqueue SlackDmTriageJob '{"workspace": "greatminds"}'
#   enqueue SlackDmTriageJob '{"workspace": "turing"}'
class SlackDmTriageJob < BrowserJob
  faktory_options queue: 'work-web', unique_for: 86_400

  def playwright_session
    "slack-#{@workspace_key || "greatminds"}"
  end

  def action_prompt(options)
    @workspace_key = options["workspace"] || "greatminds"
    workspaces = Config.get("slack.workspaces")
    workspace = workspaces[@workspace_key]
    raise "Unknown workspace: #{@workspace_key}" unless workspace

    session = "slack-#{@workspace_key}"
    prefix = workspace["prefix"]
    <<~ACTION.strip
      Triage my unread Slack DMs into Jira tasks. Use playwright-cli via Bash for Slack browsing and Atlassian MCP tools for Jira.

      ## Browser Automation

      Use playwright-cli via Bash for all Slack browser interaction. Session: -s=#{session}

      Key commands:
      - playwright-cli -s=#{session} goto <url>              # navigate
      - playwright-cli -s=#{session} snapshot                 # get element refs
      - playwright-cli -s=#{session} click <ref>              # click element
      - playwright-cli -s=#{session} fill <ref> "<text>"      # fill input
      - playwright-cli -s=#{session} screenshot --filename=<file>  # verify visually

      Always run `snapshot` to get refs before clicking. Read the snapshot output to find the correct ref.

      ## Steps

      1. Navigate directly to #{workspace["url"]}/unreads using `playwright-cli -s=#{session} goto` (do NOT go to slack.com — go to the workspace URL directly to avoid app redirect)
      2. Run `snapshot` and look at the Direct Messages section for unread DM conversations (they'll appear bold or have unread indicators)
      3. For each unread DM:
         a. Click the conversation ref and read enough to understand the topic
         b. Note the person's name and a brief summary of what the DM is about
         c. Get the current URL using `playwright-cli -s=#{session} evaluate "window.location.href"` — this is the direct link to the DM
         d. Search Jira project #{Config.get("jira.project_key")} for existing open tasks with summary containing "#{prefix}:" and that person's name using the Atlassian MCP searchJiraIssuesUsingJql tool with cloudId "#{Config.get("jira.cloud_id")}" and JQL like: project = #{Config.get("jira.project_key")} AND summary ~ "#{prefix}: PersonName" AND status != Done
         e. If no existing task found, create a new Jira Task in project #{Config.get("jira.project_key")} using the Atlassian MCP createJiraIssue tool with:
            - summary: "#{prefix}: {PersonName} about {brief topic}" — for group DMs, use the first person's name plus a count like "#{prefix}: Kyle +2 about project timeline" (meaning Kyle and 2 others)
            - description: A brief summary of the DM content and any action needed
            - additional_fields: {"url": "{slack_dm_url}"}
         f. Find the message input ref and type: /remind me to respond to this DM in 1 hour
            Then press Enter to send the remind command
      4. After processing all DMs, summarize how many were found and how many Jira tasks were created vs already existed
    ACTION
  end
end
