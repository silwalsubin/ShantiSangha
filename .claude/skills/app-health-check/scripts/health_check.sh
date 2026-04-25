#!/usr/bin/env bash
# app-health-check — production diagnostic for ShantiSangha API.
# Read-only. Exits 0=green, 1=yellow (running with errors), 2=red (down).

set -u
set -o pipefail

HEALTH_URL="${HEALTH_URL:-https://shantisangha.com/health}"
ECS_CLUSTER="${ECS_CLUSTER:-shantisangha-cluster}"
ECS_SERVICE="${ECS_SERVICE:-shantisangha-api}"
LOG_GROUP="${LOG_GROUP:-/ecs/shantisangha-api}"
WINDOW_MIN="${WINDOW_MIN:-30}"
AWS_REGION="${AWS_REGION:-us-east-1}"

# ANSI color shorthand only when stdout is a terminal — keep it plain for tools.
if [ -t 1 ]; then
  C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'; C_RED=$'\033[31m'
  C_DIM=$'\033[2m';   C_BOLD=$'\033[1m';   C_RESET=$'\033[0m'
else
  C_GREEN=""; C_YELLOW=""; C_RED=""; C_DIM=""; C_BOLD=""; C_RESET=""
fi

verdict_green=0
verdict_yellow=0
verdict_red=0

section() { printf "\n${C_BOLD}== %s ==${C_RESET}\n" "$1"; }
note()    { printf "${C_DIM}%s${C_RESET}\n" "$1"; }
ok()      { printf "${C_GREEN}✔${C_RESET} %s\n" "$1"; }
warn()    { printf "${C_YELLOW}!${C_RESET} %s\n" "$1"; verdict_yellow=1; }
fail()    { printf "${C_RED}✗${C_RESET} %s\n" "$1"; verdict_red=1; }

print_summary_and_exit() {
  echo
  section "Summary"
  if [ "$verdict_red" -eq 1 ]; then
    printf "${C_RED}● RED${C_RESET}   — backend is down or critical failure detected\n"
    exit 2
  elif [ "$verdict_yellow" -eq 1 ]; then
    printf "${C_YELLOW}● YELLOW${C_RESET} — running but worth a look (or partial check)\n"
    exit 1
  else
    printf "${C_GREEN}● GREEN${C_RESET}  — all checks passed\n"
    exit 0
  fi
}

# ── 1. Public health endpoint ────────────────────────────────────────────────
section "/health endpoint"
curl_out="$(curl -s -o /tmp/healthbody.$$ -w '%{http_code} %{time_total}' \
  --max-time 10 "$HEALTH_URL" 2>/dev/null || true)"
status="${curl_out%% *}"
elapsed="${curl_out##* }"
body="$(cat /tmp/healthbody.$$ 2>/dev/null || true)"
rm -f /tmp/healthbody.$$

if [ -z "$status" ] || [ "$status" = "000" ]; then
  fail "Could not reach $HEALTH_URL (network or DNS failure)"
elif [ "$status" = "200" ]; then
  ms=$(awk -v t="$elapsed" 'BEGIN{printf "%d", t*1000}')
  ok "200 OK in ${ms}ms"
  preview="$(printf "%s" "$body" | head -c 160)"
  [ -n "$preview" ] && note "  body: $preview"
else
  fail "$status from $HEALTH_URL"
  preview="$(printf "%s" "$body" | head -c 200)"
  [ -n "$preview" ] && note "  body: $preview"
fi

# ── 2. AWS CLI availability ──────────────────────────────────────────────────
# Note: missing or unconfigured AWS CLI is a warn, not a fail — it just means
# we can't see deeper than the public health endpoint. The backend itself
# may still be perfectly fine (and the /health check above will say so).
section "AWS CLI"
if ! command -v aws >/dev/null 2>&1; then
  warn "aws CLI not installed — install with: brew install awscli"
  note "Skipping ECS and CloudWatch checks."
  print_summary_and_exit
fi

if ! aws sts get-caller-identity --region "$AWS_REGION" >/dev/null 2>&1; then
  warn "aws CLI not configured — run 'aws configure' or set AWS_PROFILE / AWS_REGION"
  note "Skipping ECS and CloudWatch checks."
  print_summary_and_exit
fi
ok "credentials resolved (region: $AWS_REGION)"

# ── 3. ECS service status ────────────────────────────────────────────────────
section "ECS service ($ECS_CLUSTER / $ECS_SERVICE)"
ecs_json="$(aws ecs describe-services \
  --cluster "$ECS_CLUSTER" --services "$ECS_SERVICE" \
  --region "$AWS_REGION" --output json 2>/dev/null || true)"

if [ -z "$ecs_json" ] || ! printf "%s" "$ecs_json" | grep -q '"services"'; then
  fail "Could not describe ECS service (check cluster/service names or IAM)"
else
  running="$(printf "%s" "$ecs_json" | python3 -c '
import json, sys
d=json.load(sys.stdin)
s=(d.get("services") or [{}])[0]
print(s.get("runningCount", "?"))
' 2>/dev/null || echo "?")"
  desired="$(printf "%s" "$ecs_json" | python3 -c '
import json, sys
d=json.load(sys.stdin)
s=(d.get("services") or [{}])[0]
print(s.get("desiredCount", "?"))
' 2>/dev/null || echo "?")"
  pending="$(printf "%s" "$ecs_json" | python3 -c '
import json, sys
d=json.load(sys.stdin)
s=(d.get("services") or [{}])[0]
print(s.get("pendingCount", 0))
' 2>/dev/null || echo "0")"
  deploy="$(printf "%s" "$ecs_json" | python3 -c '
import json, sys
d=json.load(sys.stdin)
s=(d.get("services") or [{}])[0]
deps=s.get("deployments") or []
if not deps:
    print("no deployments")
else:
    p=deps[0]
    print(f"{p.get(\"status\",\"?\")} (rollout {p.get(\"rolloutState\",\"?\")})")
' 2>/dev/null || echo "?")"
  last_event="$(printf "%s" "$ecs_json" | python3 -c '
import json, sys
d=json.load(sys.stdin)
s=(d.get("services") or [{}])[0]
ev=s.get("events") or []
if ev:
    e=ev[0]
    msg=(e.get("message") or "").strip()
    print(f"{e.get(\"createdAt\",\"\")} :: {msg}")
else:
    print("(no events)")
' 2>/dev/null || echo "(unavailable)")"

  if [ "$running" = "$desired" ] && [ "$pending" = "0" ] && [ "$desired" != "0" ]; then
    ok "$running/$desired tasks running, deployment: $deploy"
  elif [ "$running" = "0" ] && [ "$desired" != "0" ]; then
    fail "0/$desired tasks running, deployment: $deploy"
  else
    warn "$running/$desired tasks running ($pending pending), deployment: $deploy"
  fi
  note "  last event: $last_event"
fi

# ── 4. CloudWatch errors in the last $WINDOW_MIN minutes ─────────────────────
section "CloudWatch errors (last ${WINDOW_MIN}m of $LOG_GROUP)"
start_ms=$(( ( $(date +%s) - WINDOW_MIN * 60 ) * 1000 ))
log_json="$(aws logs filter-log-events \
  --log-group-name "$LOG_GROUP" \
  --start-time "$start_ms" \
  --filter-pattern '?"[ERR]" ?"[FTL]"' \
  --max-items 25 \
  --region "$AWS_REGION" \
  --output json 2>/dev/null || true)"

if [ -z "$log_json" ] || ! printf "%s" "$log_json" | grep -q '"events"'; then
  warn "Could not query CloudWatch (log group missing or IAM denial?)"
else
  count="$(printf "%s" "$log_json" | python3 -c '
import json, sys
d=json.load(sys.stdin)
print(len(d.get("events") or []))
' 2>/dev/null || echo "?")"
  if [ "$count" = "0" ]; then
    ok "no [ERR] or [FTL] entries in the last ${WINDOW_MIN}m"
  else
    warn "$count error/fatal log entries in the last ${WINDOW_MIN}m"
    printf "%s" "$log_json" | python3 -c '
import json, sys
d=json.load(sys.stdin)
events=d.get("events") or []
shown=events[-3:]   # last (most recent) up to 3 entries
for e in shown:
    msg=(e.get("message") or "").strip().replace("\n", " ")
    if len(msg) > 240:
        msg = msg[:240] + "…"
    print(f"  · {msg}")
' 2>/dev/null || true
    if [ "$count" -gt 3 ] 2>/dev/null; then
      note "  (showing 3 most recent of $count)"
    fi
  fi
fi

# ── Summary ──────────────────────────────────────────────────────────────────
print_summary_and_exit
