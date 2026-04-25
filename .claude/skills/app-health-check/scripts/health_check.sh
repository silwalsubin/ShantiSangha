#!/usr/bin/env bash
# app-health-check — production diagnostic for ShantiSangha API.
# Read-only. Exits 0=green, 1=yellow (running with issues), 2=red (down).
#
# Bash handles the public /health curl, AWS profile auto-discovery, and
# SSO refresh. Deeper checks (ECS service, ECR/task image freshness, per-task
# health, CloudWatch error grouping) live in scripts/deep_checks.py since
# JSON parsing and message-pattern bucketing are cleaner in Python.

set -u
set -o pipefail

HEALTH_URL="${HEALTH_URL:-https://shantisangha.com/health}"
AWS_REGION="${AWS_REGION:-us-east-1}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Auto-discover an SSO-configured profile if AWS_PROFILE isn't already set.
# Almost always picks the actual user profile; the literal `default` profile
# usually has stale static keys and is the wrong choice.
if [ -z "${AWS_PROFILE:-}" ] && command -v aws >/dev/null 2>&1; then
  candidate="$(aws configure list-profiles 2>/dev/null | grep -v '^default$' | head -1)"
  if [ -n "$candidate" ]; then
    export AWS_PROFILE="$candidate"
  fi
fi

if [ -t 1 ]; then
  C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'; C_RED=$'\033[31m'
  C_DIM=$'\033[2m';   C_BOLD=$'\033[1m';   C_RESET=$'\033[0m'
else
  C_GREEN=""; C_YELLOW=""; C_RED=""; C_DIM=""; C_BOLD=""; C_RESET=""
fi

# Combined verdict across the bash and python phases. Python prints its own
# `VERDICT:<color>` line which we merge into ours below.
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
# Missing/unconfigured AWS CLI is a warn, not a fail — backend may still be
# perfectly fine, we just can't see deeper than the public health endpoint.
section "AWS CLI"
if ! command -v aws >/dev/null 2>&1; then
  warn "aws CLI not installed — install with: brew install awscli"
  note "Skipping ECS, ECR, and CloudWatch checks."
  print_summary_and_exit
fi

# Proactively refresh the SSO token — no-op when the cached token is already
# fresh, only opens a browser when it's actually expired.
sso_url="$(aws configure get sso_start_url --profile "${AWS_PROFILE:-default}" 2>/dev/null || true)"
if [ -n "$sso_url" ]; then
  if ! aws sso login --profile "$AWS_PROFILE" >/dev/null 2>&1; then
    note "  (sso login attempt failed — continuing with whatever cached creds exist)"
  fi
fi

if ! aws sts get-caller-identity --region "$AWS_REGION" >/dev/null 2>&1; then
  warn "aws CLI not authenticated — try 'aws sso login --profile $AWS_PROFILE' manually, or set AWS_PROFILE to a working profile"
  note "Skipping ECS, ECR, and CloudWatch checks."
  print_summary_and_exit
fi
ok "credentials resolved (region: $AWS_REGION, profile: ${AWS_PROFILE:-default})"

# ── 3. Deep checks (delegated to Python for JSON parsing + grouping) ────────
if ! command -v python3 >/dev/null 2>&1; then
  warn "python3 not found — skipping deep checks"
  print_summary_and_exit
fi

# Pipe through tee so we both stream output to the user AND capture it for the
# VERDICT line. Python script's exit code is also informative.
deep_out="$(python3 "$SCRIPT_DIR/deep_checks.py" 2>&1; echo "RC:$?")"
deep_rc="${deep_out##*RC:}"
deep_text="${deep_out%RC:*}"
printf "%s" "$deep_text"

# Merge Python's verdict into the combined verdict.
case "$(printf "%s" "$deep_text" | grep -E '^VERDICT:' | tail -1 | cut -d: -f2)" in
  red)    verdict_red=1 ;;
  yellow) verdict_yellow=1 ;;
esac

print_summary_and_exit
