---
name: agent-reports
description: "Read-only digest of the in-app agent's self-reported issues, improvements, and observations — surfaced via the MCP `report_feedback` tool and emitted as structured Serilog lines into the production CloudWatch log group `/ecs/shantisangha-api`. Use this skill whenever the user asks about agent self-reports, MCP-reported issues, `report_feedback` entries, what the agent has been flagging, how the AI is doing, recent AI friction, agent observations, AI feedback log, 'what is the agent complaining about', 'what is claude reporting', 'show me mcp issues', 'show me agent issues', 'agent improvement ideas', 'recent agent observations'. Also trigger when the user pastes a `report_feedback` snippet, asks how the AI experience is going from the AI's perspective, or wants a digest of MCP-channel feedback. Read-only: groups and counts; does not propose code fixes or modify anything."
---

# Agent Reports — read-only digest

The in-app agent (Semantic Kernel) and any authenticated external MCP client can call the `report_feedback` MCP tool to file a quiet note — `type` in {issue, improvement, observation}, `severity` in {low, medium, high}, a title, the context, and an optional suggestion. Each call writes a row to `AgentFeedbackEntries` and a structured Serilog line that lands in CloudWatch.

This skill reads those CloudWatch lines, groups them, and reports the digest. It does not fetch from the database, does not propose code fixes, and does not modify anything.

## What the log line looks like

After [backend/ShantiSangha.AgentFeedback/Services/AgentFeedbackService.cs](backend/ShantiSangha.AgentFeedback/Services/AgentFeedbackService.cs) writes an entry, Serilog emits:

```
[14:23:45 INF] AgentFeedback recorded: type=issue severity=high title=<...> userId=<...> id=<...>   {"AgentFeedbackType": "issue", "AgentFeedbackSeverity": "high", "AgentFeedbackTitle": "...", "AgentFeedbackUserId": "...", "AgentFeedbackId": "...", "SourceContext": "ShantiSangha.AgentFeedback.Services.AgentFeedbackService", ...}
```

The structured properties (`AgentFeedbackType`, `AgentFeedbackSeverity`, `AgentFeedbackTitle`, `AgentFeedbackId`) are what the skill parses with CloudWatch Insights — much cleaner than regexing the message body.

This logging line was added on 2026-05-25. Entries written before that date exist in the `AgentFeedbackEntries` table but have no CloudWatch trace. If the user asks about historical entries beyond that cutoff, say so plainly — point them at the iOS DEBUG view in Settings (which reads `/api/agent-feedback` directly).

## How to run it

```bash
bash .claude/skills/agent-reports/scripts/digest.sh
```

Default scope: last 7 days, grouped output. Flags:

- `--since 24h` / `--since 30d` — change the time window. Anything CloudWatch supports.
- `--type issue|improvement|observation` — filter to a single category.
- `--severity low|medium|high` — filter to one severity.
- `--limit 20` — how many recent titles to surface alongside the grouped counts (default 10).
- `--format markdown` — human-readable report. Default is `json` so this skill can post-process.

The script auto-detects an SSO profile (same pattern as the `app-health-check` skill) and runs `aws sso login` once before the first AWS call. The CloudWatch Insights query usually returns in 3–8 seconds.

## How to present the result to the user

Default shape:

```
## Agent self-reports — last <window>

### Counts
- issue:        <N>   (low <a>, medium <b>, high <c>)
- improvement:  <N>   (low, medium, high)
- observation:  <N>   (low, medium, high)
Total: <T>

### Recent (most-recent first)
- 2026-05-24 09:12  [issue/high]      <title>
- 2026-05-23 19:44  [improvement/med] <title>
- ...
```

Then add a one-sentence verdict on what stands out — the highest-frequency type, or a high-severity issue that's repeating. Don't draft fixes. The user asked for a digest, not a triage.

If the digest is empty:

```
No agent self-reports in the last <window>.
```

If logging was just deployed and the digest is empty, gently note: "Logging was added on 2026-05-25; if the deploy hasn't landed yet, future reports will start appearing here."

## Stay read-only

- Do not propose code fixes for individual reports — even when the suggestion field is tempting. The user asked for a digest.
- Do not query the database, hit `/api/agent-feedback`, or attempt to enrich entries beyond what's in the log line.
- Do not delete log entries, edit retention, or restart the service.

If the user explicitly asks for fix ideas based on the digest, that's a separate ask — pivot to a normal conversation about the report content, but make the boundary visible.

## Region and resource names

- Log group: `/ecs/shantisangha-api`
- AWS region default: `us-east-1`
- Filter pattern: `AgentFeedback recorded`

If the log group name ever changes, update `LOG_GROUP` at the top of `scripts/digest.sh`.
