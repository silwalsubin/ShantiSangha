#!/usr/bin/env python3
"""
Deep health checks for the ShantiSangha backend. Called by health_check.sh
after the public /health endpoint and AWS auth have already been verified.

Three checks:
  1. ECS service: running/desired count, deployment rollout state, last event
  2. Image freshness + per-task health: latest ECR digest vs each running
     task's container digest; per-task lastStatus, healthStatus, stoppedReason
  3. CloudWatch errors: groups [ERR]/[FTL] entries by normalized message so
     50 instances of the same error read as one issue, not 50

Exit codes: 0 = green, 1 = yellow (issues but running), 2 = red (down/broken).
"""
import json
import os
import re
import subprocess
import sys
from collections import Counter
from datetime import datetime, timezone

REGION       = os.environ.get("AWS_REGION", "us-east-1")
ECS_CLUSTER  = os.environ.get("ECS_CLUSTER", "shantisangha-cluster")
ECS_SERVICE  = os.environ.get("ECS_SERVICE", "shantisangha-api")
ECR_REPO     = os.environ.get("ECR_REPO", "shantisangha-api")
LOG_GROUP    = os.environ.get("LOG_GROUP", "/ecs/shantisangha-api")
WINDOW_MIN   = int(os.environ.get("WINDOW_MIN", "30"))

USE_COLOR = sys.stdout.isatty() and os.environ.get("NO_COLOR") != "1"
C_GREEN   = "\033[32m" if USE_COLOR else ""
C_YELLOW  = "\033[33m" if USE_COLOR else ""
C_RED     = "\033[31m" if USE_COLOR else ""
C_DIM     = "\033[2m"  if USE_COLOR else ""
C_BOLD    = "\033[1m"  if USE_COLOR else ""
C_RESET   = "\033[0m"  if USE_COLOR else ""

# Verdict accumulates across checks. "yellow" upgrades from "green" but never
# downgrades; "red" wins absolutely. Same logic the bash wrapper uses.
verdict = "green"


def upgrade(level):
    global verdict
    order = {"green": 0, "yellow": 1, "red": 2}
    if order[level] > order[verdict]:
        verdict = level


def section(title): print(f"\n{C_BOLD}== {title} =={C_RESET}")
def ok(msg):        print(f"{C_GREEN}✔{C_RESET} {msg}")
def warn(msg):      upgrade("yellow"); print(f"{C_YELLOW}!{C_RESET} {msg}")
def fail(msg):      upgrade("red");    print(f"{C_RED}✗{C_RESET} {msg}")
def note(msg):      print(f"{C_DIM}{msg}{C_RESET}")


def aws(args, timeout=15):
    """Run an AWS CLI command. Returns parsed JSON, or None on any failure."""
    try:
        result = subprocess.run(
            ["aws"] + args + ["--region", REGION, "--output", "json"],
            capture_output=True, text=True, timeout=timeout,
        )
        if result.returncode != 0:
            return None
        return json.loads(result.stdout) if result.stdout.strip() else None
    except (subprocess.TimeoutExpired, json.JSONDecodeError, FileNotFoundError):
        return None


def short_digest(digest: str) -> str:
    """sha256:abc123def4...xyz -> sha256:abc123def4… (readable but identifying)."""
    if not digest:
        return "(none)"
    if digest.startswith("sha256:"):
        return digest[:14] + "…"
    return digest[:8] + "…"


# Threshold beyond which an IN_PROGRESS rollout is considered stuck. A
# normal Fargate rolling deploy completes in a few minutes; if it's been
# trying to land for longer than this, something's actively failing.
ROLLOUT_STUCK_MINUTES = 10

# Phrases that show up in ECS service events when tasks fail to start or
# get killed by health checks. We count occurrences in recent events to
# detect a crash-loop pattern.
_FAILURE_PATTERNS = [
    "failed to start",
    "failed container health checks",
    "essential container",
    "stopped",
    "deployment failed",
    "unable to place a task",
    "cannot pull container image",
    "task failed elb health checks",
]


def _parse_iso(ts):
    """ECS returns timestamps as ISO strings. Return a UTC datetime, or None."""
    if not ts:
        return None
    s = str(ts).replace("Z", "+00:00")
    try:
        return datetime.fromisoformat(s).astimezone(timezone.utc)
    except (ValueError, TypeError):
        return None


def _age_minutes(ts) -> float | None:
    dt = _parse_iso(ts)
    if not dt:
        return None
    return (datetime.now(timezone.utc) - dt).total_seconds() / 60


# ── 1. ECS service status ───────────────────────────────────────────────────
def check_ecs_service():
    section(f"ECS service ({ECS_CLUSTER} / {ECS_SERVICE})")
    data = aws(["ecs", "describe-services", "--cluster", ECS_CLUSTER,
                "--services", ECS_SERVICE])
    if not data:
        fail("Could not describe ECS service (check names or IAM)")
        return

    s = ((data.get("services") or [{}])[0])
    running = s.get("runningCount", "?")
    desired = s.get("desiredCount", "?")
    pending = s.get("pendingCount", 0)
    deps    = s.get("deployments") or []

    # Deployment health — the difference between "rolling out smoothly" and
    # "stuck retrying" is in `rolloutState` + `failedTasks` + `createdAt`.
    rollout = "?"
    deploy_label = "no deployments"
    deploy_age = None
    failed_tasks = 0
    rollout_reason = ""
    if deps:
        p = deps[0]
        rollout = p.get("rolloutState", "?")
        deploy_label = f"{p.get('status', '?')} (rollout {rollout})"
        deploy_age = _age_minutes(p.get("createdAt"))
        failed_tasks = p.get("failedTasks", 0) or 0
        rollout_reason = (p.get("rolloutStateReason") or "").strip()

    # Verdict on task counts vs deployment health
    if running == 0 and desired != 0:
        fail(f"0/{desired} tasks running, {deploy_label}")
    elif running == desired and pending == 0 and desired != 0:
        if rollout == "IN_PROGRESS" and deploy_age and deploy_age > ROLLOUT_STUCK_MINUTES:
            fail(f"{running}/{desired} tasks running but rollout has been "
                 f"IN_PROGRESS for {deploy_age:.0f} min — stuck deploy")
        elif rollout == "IN_PROGRESS":
            warn(f"{running}/{desired} tasks running, {deploy_label}")
        elif rollout == "FAILED":
            fail(f"{running}/{desired} tasks running, {deploy_label}")
        else:
            ok(f"{running}/{desired} tasks running, {deploy_label}")
    else:
        warn(f"{running}/{desired} tasks running ({pending} pending), {deploy_label}")

    # Surface deployment metadata that explains a stuck rollout
    if deploy_age is not None:
        note(f"  deployment age: {deploy_age:.1f} min")
    if failed_tasks > 0:
        fail(f"deployment has {failed_tasks} failed task launch(es) — "
             f"new image is crashing on start")
    if rollout_reason:
        note(f"  rollout reason: {rollout_reason}")

    # Look at recent events for crash-loop patterns. If many recent events
    # match failure phrases, that confirms ECS is repeatedly trying and
    # failing to launch new tasks.
    events = s.get("events") or []
    recent_events = events[:15]   # ECS returns newest-first
    failure_event_count = 0
    for e in recent_events:
        msg = (e.get("message") or "").lower()
        if any(p in msg for p in _FAILURE_PATTERNS):
            failure_event_count += 1
    if failure_event_count >= 3:
        fail(f"{failure_event_count} of the last {len(recent_events)} service events "
             f"indicate task failures — service is crash-looping")
    elif failure_event_count > 0:
        warn(f"{failure_event_count} of the last {len(recent_events)} service events "
             f"indicate task failures")

    if events:
        e = events[0]
        msg = (e.get("message") or "").strip()
        created = str(e.get("createdAt", ""))
        note(f"  last event: {created} :: {msg}")


# ── 1b. Recent stopped tasks (crash-loop forensics) ─────────────────────────
def check_stopped_tasks():
    """Enumerate tasks that ECS has recently STOPPED. In a healthy service
    there are zero recent stops. If we see several with stoppedReason like
    "Essential container in task exited" or non-zero exit codes, the service
    is crash-looping — this is the signal that distinguishes a stuck deploy
    from a normal rolling deploy."""
    section("Recent stopped tasks")

    list_data = aws(["ecs", "list-tasks", "--cluster", ECS_CLUSTER,
                     "--service-name", ECS_SERVICE, "--desired-status", "STOPPED"])
    if not list_data:
        warn("Could not list stopped tasks")
        return
    arns = list_data.get("taskArns") or []
    if not arns:
        ok("no recently stopped tasks (clean deploy history)")
        return

    desc = aws(["ecs", "describe-tasks", "--cluster", ECS_CLUSTER,
                "--tasks"] + arns[:10])
    if not desc:
        warn(f"{len(arns)} stopped tasks listed but couldn't describe them")
        return

    tasks = desc.get("tasks") or []
    # Filter to last 60 minutes only — ECS keeps STOPPED tasks visible for
    # an hour by default; older ones are noise.
    recent_stops = []
    for t in tasks:
        age = _age_minutes(t.get("stoppedAt"))
        if age is not None and age <= 60:
            recent_stops.append((age, t))

    if not recent_stops:
        ok("no task stops in the last 60 minutes")
        return

    # Sort newest first
    recent_stops.sort(key=lambda x: x[0])

    if len(recent_stops) >= 3:
        fail(f"{len(recent_stops)} task stops in the last 60 min — crash loop")
    else:
        warn(f"{len(recent_stops)} task stop(s) in the last 60 min")

    for age, t in recent_stops[:5]:
        arn_short  = (t.get("taskArn") or "").split("/")[-1][:12]
        reason     = (t.get("stoppedReason") or "").strip()
        containers = t.get("containers") or []
        exit_code  = (containers[0].get("exitCode") if containers else None)
        c_reason   = ((containers[0].get("reason") if containers else "") or "").strip()
        digest     = (containers[0].get("imageDigest") if containers else "") or ""

        line = f"  · {age:.1f}m ago, task {arn_short}"
        if exit_code is not None:
            line += f", exit={exit_code}"
        line += f", image {short_digest(digest)}"
        print(line)
        if reason:
            print(f"      reason: {reason[:240]}")
        if c_reason and c_reason != reason:
            print(f"      container: {c_reason[:240]}")

    # Dump the last log lines from the most recently stopped task. This is
    # the highest-signal forensic detail for stuck deploys: the [ERR]/[FTL]
    # filter misses cases where the container exits cleanly without logging
    # an error, but the raw tail of the log stream usually shows the real
    # cause (port already in use, missing dependency, etc.).
    if recent_stops:
        _, latest_task = recent_stops[0]
        latest_arn   = (latest_task.get("taskArn") or "").split("/")[-1]
        containers   = latest_task.get("containers") or []
        container_name = (containers[0].get("name") if containers else "") or ECS_SERVICE

        # Stream name follows the awslogs driver convention:
        # `<prefix>/<container-name>/<task-id>` (prefix is "ecs" per Terraform).
        # We use describe-log-streams with a prefix search instead of an
        # exact name lookup so we degrade gracefully if the convention
        # ever changes — and so we can detect the "no stream exists at
        # all" case, which itself is diagnostic (the container exited
        # before producing any stdout/stderr, so awslogs never created
        # the stream).
        stream_prefix = f"ecs/{container_name}/{latest_arn}"
        streams_data = aws(["logs", "describe-log-streams",
                            "--log-group-name", LOG_GROUP,
                            "--log-stream-name-prefix", stream_prefix,
                            "--limit", "1"])
        actual_stream = ""
        if streams_data and streams_data.get("logStreams"):
            actual_stream = streams_data["logStreams"][0].get("logStreamName") or ""

        print()
        if not actual_stream:
            warn(f"task {latest_arn[:12]} has no log stream — container exited "
                 f"before producing any stdout/stderr (very early startup failure)")
            print(f"      expected stream prefix: {stream_prefix}")
            return

        # Note: don't pass `--start-from-head false` here — the AWS CLI treats
        # --start-from-head as a boolean flag (presence = true, absence = false).
        # Adding it with the value "false" makes the CLI parser reject the call
        # silently. Default behaviour is "from the end" which is what we want.
        log_data = aws(["logs", "get-log-events",
                        "--log-group-name", LOG_GROUP,
                        "--log-stream-name", actual_stream,
                        "--limit", "30"])
        if log_data and log_data.get("events"):
            events = log_data["events"]
            print(f"  last {min(len(events), 15)} log lines from task {latest_arn[:12]}:")
            for e in events[-15:]:
                msg = (e.get("message") or "").rstrip()
                if len(msg) > 240:
                    msg = msg[:240] + "…"
                print(f"      {msg}")
        elif log_data is not None:
            note(f"  (log stream exists but is empty: {actual_stream})")
        else:
            note(f"  (couldn't read log stream {actual_stream})")


# ── 2. Image freshness + per-task health ────────────────────────────────────
def check_image_and_task_health():
    section("Image freshness & task health")

    # Latest ECR image — sort tagged images by push time, take newest.
    ecr_data = aws(["ecr", "describe-images", "--repository-name", ECR_REPO,
                    "--filter", "tagStatus=TAGGED"])
    ecr_digest, ecr_pushed, ecr_tags = "", "", []
    if ecr_data:
        imgs = ecr_data.get("imageDetails") or []
        imgs.sort(key=lambda i: i.get("imagePushedAt", ""), reverse=True)
        if imgs:
            ecr_digest = imgs[0].get("imageDigest", "")
            ecr_pushed = imgs[0].get("imagePushedAt", "")
            ecr_tags   = imgs[0].get("imageTags") or []

    if not ecr_digest:
        warn(f"Could not determine latest ECR image in repo {ECR_REPO}")
        return

    note(f"  latest ECR: {short_digest(ecr_digest)} pushed {ecr_pushed}")
    if ecr_tags:
        note(f"             tags: {', '.join(ecr_tags[:5])}")

    # Running task list
    list_data = aws(["ecs", "list-tasks", "--cluster", ECS_CLUSTER,
                     "--service-name", ECS_SERVICE, "--desired-status", "RUNNING"])
    if not list_data:
        warn("Could not list ECS tasks")
        return
    arns = list_data.get("taskArns") or []
    if not arns:
        fail("No running tasks in service")
        return

    desc = aws(["ecs", "describe-tasks", "--cluster", ECS_CLUSTER, "--tasks"] + arns)
    if not desc:
        warn("Could not describe tasks")
        return

    tasks = desc.get("tasks") or []
    running_digests = set()

    for t in tasks:
        arn_short = (t.get("taskArn") or "").split("/")[-1][:12]
        last      = t.get("lastStatus", "?")
        health    = t.get("healthStatus", "UNKNOWN")
        stopped   = (t.get("stoppedReason") or "").strip()
        containers = t.get("containers") or []
        c_digest = (containers[0].get("imageDigest") or "") if containers else ""
        if c_digest:
            running_digests.add(c_digest)

        is_outdated = bool(c_digest) and bool(ecr_digest) and c_digest != ecr_digest

        line = f"task {arn_short}: {last}"
        if health and health != "UNKNOWN":
            line += f", health {health}"
        line += f", image {short_digest(c_digest)}"
        if is_outdated:
            line += " (older than latest ECR)"

        if last != "RUNNING":
            fail(line)
        elif health == "UNHEALTHY":
            fail(line)
        elif is_outdated:
            warn(line)
        else:
            ok(line)

        if stopped:
            note(f"  stopped: {stopped}")

    # Aggregate verdict on image freshness. The interpretation of "older
    # image" depends on whether a deploy is actively rolling or stuck — but
    # we already raised that signal in check_ecs_service / check_stopped_tasks.
    # Here we just describe the gap so the reader can correlate.
    if running_digests == {ecr_digest}:
        ok("all running tasks are on the latest ECR image")
    elif ecr_digest in running_digests and len(running_digests) > 1:
        warn("mixed image versions across tasks — deploy in progress")
    elif running_digests and ecr_digest not in running_digests:
        # We can't tell from here alone whether this is "deploy in flight"
        # or "deploy stuck" — but the ECS service section has already raised
        # the right verdict if it's stuck (deploy age, failedTasks, crash-loop
        # event pattern). So leave this as a yellow "drift" signal and let
        # the deployment-health checks own the red verdict.
        warn("running tasks are on an OLDER image than the latest ECR push "
             "(see ECS service + stopped-tasks sections for whether the new image is stuck)")


# ── 3. CloudWatch errors (grouped) ──────────────────────────────────────────
_TS_PREFIX = re.compile(r"^\[\d{2}:\d{2}:\d{2}\s+\w+\]\s*")
_ISO_TS    = re.compile(r"^\d{4}-\d{2}-\d{2}T?\S*\s+")
_UUID      = re.compile(
    r"[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}", re.IGNORECASE)
_BIG_NUM   = re.compile(r"\b\d{5,}\b")


def normalize_log_message(msg: str) -> str:
    """Normalize a Serilog message so repeated identical errors bucket together.

    Strips the `[HH:mm:ss LVL]` prefix, leading ISO timestamps, replaces
    UUIDs/GUIDs and large numbers with placeholders, then takes the first
    120 chars as the bucket key. The goal is "50 copies of the same error"
    → one bucket with count 50, not 50 separate lines.
    """
    msg = _TS_PREFIX.sub("", msg)
    msg = _ISO_TS.sub("", msg)
    msg = _UUID.sub("<uuid>", msg)
    msg = _BIG_NUM.sub("<n>", msg)
    return msg.strip()[:120]


def check_cloudwatch_errors():
    section(f"CloudWatch errors (last {WINDOW_MIN}m of {LOG_GROUP})")
    start_ms = int((datetime.now(timezone.utc).timestamp() - WINDOW_MIN * 60) * 1000)

    data = aws(["logs", "filter-log-events",
                "--log-group-name", LOG_GROUP,
                "--start-time", str(start_ms),
                "--filter-pattern", '?"[ERR]" ?"[FTL]"',
                "--max-items", "200"])
    if data is None:
        warn("Could not query CloudWatch (log group missing or IAM denial?)")
        return

    events = data.get("events") or []
    if not events:
        ok(f"no [ERR] or [FTL] entries in the last {WINDOW_MIN}m")
        return

    groups = {}
    fatal_count = 0
    for e in events:
        msg = (e.get("message") or "").strip().replace("\n", " ")
        if "[FTL]" in msg:
            fatal_count += 1
        key = normalize_log_message(msg)
        if not key:
            continue
        g = groups.setdefault(key, {"count": 0, "sample": msg, "latest_ts": 0})
        g["count"] += 1
        ts = e.get("timestamp", 0)
        if ts > g["latest_ts"]:
            g["latest_ts"] = ts
            g["sample"] = msg

    total = len(events)
    distinct = len(groups)

    if fatal_count > 0:
        fail(f"{total} error/fatal entries ({fatal_count} fatal) across {distinct} distinct issue(s)")
    else:
        warn(f"{total} error entries across {distinct} distinct issue(s)")

    # Top issues by count, recent timestamp first as tiebreaker
    sorted_groups = sorted(groups.values(),
                           key=lambda g: (g["count"], g["latest_ts"]),
                           reverse=True)
    for g in sorted_groups[:3]:
        ts_str = ""
        if g["latest_ts"]:
            dt = datetime.fromtimestamp(g["latest_ts"] / 1000, tz=timezone.utc)
            ts_str = dt.strftime("%H:%M:%S UTC")
        sample = g["sample"]
        if len(sample) > 240:
            sample = sample[:240] + "…"
        print(f"  · ×{g['count']} (last {ts_str}): {sample}")

    if distinct > 3:
        note(f"  (showing top 3 of {distinct} distinct issues)")


def main():
    check_ecs_service()
    check_stopped_tasks()
    check_image_and_task_health()
    check_cloudwatch_errors()

    # Final verdict marker — bash wrapper greps for this line to set its
    # combined exit code (it has its own verdict from the /health curl check).
    print(f"\nVERDICT:{verdict}")
    return {"green": 0, "yellow": 1, "red": 2}[verdict]


if __name__ == "__main__":
    sys.exit(main())
