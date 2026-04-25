---
name: app-health-check
description: "Diagnostic-only health check for the production ShantiSangha backend (ECS Fargate at api.shantisangha.com). Hits the /health endpoint, queries ECS service status, and pulls recent CloudWatch errors from the /ecs/shantisangha-api log group. Use this skill whenever the user asks 'is prod up', 'check the server', 'check the backend', 'check production', 'any errors in production', 'is the API healthy', 'check cloudwatch', 'what's wrong with prod', 'is the deploy healthy', 'health check', 'run a health check', or types `/app-health-check`. Trigger even if the user phrases it casually ('how's prod doing?'), describes a symptom ('the iOS app says backend is down'), or mentions error symptoms without naming the server explicitly. Does NOT take destructive action — read-only diagnostics."
---

# App Health Check

A diagnostic snapshot of the production backend. Tells the user, in under 30 seconds, whether the API is up, whether ECS tasks are healthy, and whether any errors have shown up in CloudWatch in the last 30 minutes.

## Why this exists

When something feels off — the iOS app shows decoding errors, push notifications stopped landing, a deploy just shipped — the user wants a single command that answers "is the backend OK?" without them having to remember the exact AWS CLI invocations. This skill bundles the three checks they always end up running by hand:

1. Is the public health endpoint responding?
2. Is the ECS service running its tasks healthily?
3. Are there ERR or FTL log entries from the last 30 minutes?

It is **read-only**. Never restart tasks, force a deploy, scale the service, rotate logs, or take any other destructive action. If the user wants to act on what the check finds, that's a separate decision they make explicitly.

## How to run it

Execute the bundled script and read its output:

```bash
bash .claude/skills/app-health-check/scripts/health_check.sh
```

The script writes a structured report to stdout. It exits 0 on green, 1 on yellow (something to look at), 2 on red (something is broken). Use the exit code as a hint, not the final word — read the body.

If the script reports that AWS CLI is not configured, surface the suggested fix in your reply (`aws configure` or set `AWS_PROFILE` / `AWS_REGION`). Do NOT try to set up credentials yourself.

## How to summarize for the user

After the script runs, give a tight verdict at the top, then a short evidence list. Aim for five lines or fewer in the common case. Examples:

**Green:**
> Backend is healthy. `/health` returned 200 in 84ms, ECS shows 2/2 tasks running, no errors in the last 30 minutes.

**Yellow (running but with recent errors):**
> Backend is up but logging errors. `/health` is 200, 2/2 tasks running. 3 `[ERR]` entries in the last 30 minutes — most recent: "FCM token refresh failed for user xyz". Worth a look but not blocking.

**Red (down or crashlooping):**
> Backend is down. `/health` returned 503. ECS shows 0/2 tasks running, last service event 2 min ago: "Task failed container health checks". Last log line before the crash: "FRIENDS_MEDIA_BUCKET_NAME is required."

When you can identify a probable root cause from the recent error log, **say it directly** — that's the highest-value signal. Don't make the user scroll through the raw output to find it.

## When the result is ambiguous

If the script's exit code disagrees with what you read in the output (e.g., exit 0 but you spot a fatal error in the logs), trust the body of the output and call it as you see it. The script's heuristic is "any [ERR] or [FTL] in the last 30 min → yellow", which can over-trigger on benign noisy errors and under-trigger on slow-burn issues.

## Don't

- Don't suggest restarts, scaling changes, or any `aws ecs update-service` invocation as part of this skill — that is a separate decision.
- Don't fetch logs older than 30 minutes by default. If the user explicitly asks for a wider window, run the underlying `aws logs filter-log-events` directly with their requested `--start-time`; don't modify the bundled script.
- Don't include large raw log dumps in your reply. Surface the most recent / most severe error line and offer to show more on request.

## Region and resource names

The script defaults to `AWS_REGION=us-east-1` and uses these resource names from the Terraform (`infrastructure/terraform/`):

- ECS cluster: `shantisangha-cluster`
- ECS service: `shantisangha-api`
- Log group: `/ecs/shantisangha-api`
- Health URL: `https://shantisangha.com/health`

If those ever change, update the constants at the top of `scripts/health_check.sh`.
