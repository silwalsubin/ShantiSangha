---
name: app-health-check
description: "Diagnostic-only health check for the production ShantiSangha backend (ECS Fargate at api.shantisangha.com). Hits the /health endpoint, queries ECS service status, and pulls recent CloudWatch errors from the /ecs/shantisangha-api log group. Use this skill whenever the user asks 'is prod up', 'check the server', 'check the backend', 'check production', 'any errors in production', 'is the API healthy', 'check cloudwatch', 'what's wrong with prod', 'is the deploy healthy', 'health check', 'run a health check', or types `/app-health-check`. Trigger even if the user phrases it casually ('how's prod doing?'), describes a symptom ('the iOS app says backend is down'), or mentions error symptoms without naming the server explicitly. Does NOT take destructive action — read-only diagnostics."
---

# App Health Check

A diagnostic snapshot of the production backend. Tells the user, in under 30 seconds, whether the API is up, whether the latest pushed image is actually the one running, whether tasks are healthy, and whether any errors have shown up in CloudWatch in the last 30 minutes.

## Why this exists

When something feels off — the iOS app shows decoding errors, push notifications stopped landing, a deploy just shipped — the user wants a single command that answers "is the backend OK?" without them having to remember the exact AWS CLI invocations. This skill bundles the checks they always end up running by hand:

1. **Is the public health endpoint responding?** — `/health` 200 + response time
2. **Is the ECS service running the desired number of tasks?** — running/desired count, deployment rollout state, last service event
3. **Is the latest ECR image actually the one running?** — compares the digest of the most-recently-pushed ECR image against the digest each running task is actually using. Catches "I pushed but the deploy never finished" and "the deploy rolled back to an older image" without needing to read raw logs.
4. **Are the running tasks healthy?** — per-task `lastStatus`, container `healthStatus`, and `stoppedReason` if anything was killed
5. **Are there grouped errors in CloudWatch?** — pulls `[ERR]` and `[FTL]` entries from the last 30 minutes and groups them by normalized message pattern (so 50 instances of the same error read as one issue with count 50, not 50 lines of noise). Surfaces top 3 issues by frequency, with most-recent timestamps.

It is **read-only**. Never restart tasks, force a deploy, scale the service, rotate logs, or take any other destructive action. If the user wants to act on what the check finds, that's a separate decision they make explicitly.

## How to run it

Execute the bundled script and read its output:

```bash
bash .claude/skills/app-health-check/scripts/health_check.sh
```

The script writes a structured report to stdout. It exits 0 on green, 1 on yellow (something to look at), 2 on red (something is broken). Use the exit code as a hint, not the final word — read the body.

The script auto-detects an SSO-configured profile (the first non-default one it finds in `~/.aws/config`) and proactively runs `aws sso login` against it before any AWS API call. That call is a no-op when the cached SSO token is still fresh and silently refreshes when it's expired — the only user-visible effect is a browser window if the token actually needs to be re-issued. So the common case (token still valid) just works without prompting.

If the script reports that AWS CLI is still not authenticated after the refresh attempt, surface the suggested fix in your reply (run `aws sso login --profile <name>` manually, or set `AWS_PROFILE` to a working profile). Do NOT try to set up credentials yourself.

## How to summarize for the user

After the script runs, give a tight verdict at the top, then a short evidence list. Aim for five lines or fewer in the common case. Examples:

**Green:**
> Backend is healthy. `/health` returned 200 in 84ms, ECS shows 2/2 tasks running, no errors in the last 30 minutes.

**Yellow (deploy mid-flight):**
> Deploy is rolling out. `/health` is 200, 1/1 task running but on an older image (sha256:4d39c2b…); the latest ECR push (sha256:881fc0c…) hasn't taken over yet. ECS is "draining connections on 1 task" — give it a couple more minutes.

**Yellow (running but with recent errors):**
> Backend is up but logging errors. `/health` is 200, latest image deployed, 2/2 tasks healthy. 47 `[ERR]` entries across 2 distinct issues in the last 30 minutes — most frequent (×42): "FCM token refresh failed for user <uuid>". Worth a look but not blocking.

**Red (down or crashlooping):**
> Backend is down. `/health` returned 503. ECS shows 0/2 tasks running, last service event 2 min ago: "Task failed container health checks". Top fatal error (×8): "FRIENDS_MEDIA_BUCKET_NAME is required."

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
