#!/usr/bin/env bash
# agent-reports/digest.sh — read-only digest of in-app agent self-reports.
#
# Reads the structured Serilog "AgentFeedback recorded:" lines from the
# /ecs/shantisangha-api CloudWatch log group, groups by type+severity,
# and surfaces recent titles. Does not touch the database, does not
# modify anything. Use CloudWatch Insights so we can parse Serilog's
# named properties cleanly instead of regexing the message body.

set -u
set -o pipefail

LOG_GROUP="${LOG_GROUP:-/ecs/shantisangha-api}"
AWS_REGION="${AWS_REGION:-us-east-1}"

since="7d"
type_filter=""
severity_filter=""
limit=10
output_format="json"

while [ $# -gt 0 ]; do
  case "$1" in
    --since) since="$2"; shift 2 ;;
    --type) type_filter="$2"; shift 2 ;;
    --severity) severity_filter="$2"; shift 2 ;;
    --limit) limit="$2"; shift 2 ;;
    --format) output_format="$2"; shift 2 ;;
    -h|--help)
      cat <<EOF
Usage: digest.sh [--since 7d] [--type issue|improvement|observation]
                 [--severity low|medium|high] [--limit 10]
                 [--format json|markdown]
EOF
      exit 0 ;;
    *) echo "unknown flag: $1" >&2; exit 2 ;;
  esac
done

# Parse a duration like "7d", "24h", "30d", "2w" into seconds.
to_seconds() {
  local s="$1"
  case "$s" in
    *h) echo $(( ${s%h} * 3600 )) ;;
    *d) echo $(( ${s%d} * 86400 )) ;;
    *w) echo $(( ${s%w} * 604800 )) ;;
    *m) echo $(( ${s%m} * 2592000 )) ;;
    *) echo "bad --since value: $s" >&2; return 1 ;;
  esac
}

window_seconds="$(to_seconds "$since")"
now="$(date +%s)"
start_time=$(( now - window_seconds ))

# Auto-detect a working SSO profile. Same trick as app-health-check.
if [ -z "${AWS_PROFILE:-}" ] && command -v aws >/dev/null 2>&1; then
  candidate="$(aws configure list-profiles 2>/dev/null | grep -v '^default$' | head -1)"
  if [ -n "$candidate" ]; then
    export AWS_PROFILE="$candidate"
  fi
fi

if ! aws sts get-caller-identity --region "$AWS_REGION" >/dev/null 2>&1; then
  if ! aws sso login --profile "${AWS_PROFILE:-default}" >/dev/null 2>&1; then
    echo "error: AWS not authenticated. Run 'aws sso login --profile ${AWS_PROFILE:-<your-profile>}' and retry." >&2
    exit 3
  fi
fi

# Build the Insights query.
#   filter chain: must mention AgentFeedback; then optional type/severity.
#   Two queries: one for grouped counts, one for recent titles.
filter_clause='filter @message like /AgentFeedback recorded/'
if [ -n "$type_filter" ]; then
  filter_clause="$filter_clause | filter AgentFeedbackType = \"$type_filter\""
fi
if [ -n "$severity_filter" ]; then
  filter_clause="$filter_clause | filter AgentFeedbackSeverity = \"$severity_filter\""
fi

counts_query="fields @timestamp
| $filter_clause
| stats count() as n by AgentFeedbackType, AgentFeedbackSeverity
| sort n desc"

recents_query="fields @timestamp, AgentFeedbackType, AgentFeedbackSeverity, AgentFeedbackTitle, AgentFeedbackId
| $filter_clause
| sort @timestamp desc
| limit $limit"

# Submit both queries in parallel, then poll until both complete.
counts_qid="$(aws logs start-query \
  --log-group-name "$LOG_GROUP" --start-time "$start_time" --end-time "$now" \
  --query-string "$counts_query" \
  --region "$AWS_REGION" --query 'queryId' --output text 2>&1)"

recents_qid="$(aws logs start-query \
  --log-group-name "$LOG_GROUP" --start-time "$start_time" --end-time "$now" \
  --query-string "$recents_query" \
  --region "$AWS_REGION" --query 'queryId' --output text 2>&1)"

if echo "$counts_qid$recents_qid" | grep -qi 'error\|exception\|invalid'; then
  echo "error: failed to start CloudWatch Insights query." >&2
  echo "counts: $counts_qid" >&2
  echo "recents: $recents_qid" >&2
  exit 4
fi

# Poll for completion. Insights queries usually return in a few seconds;
# bail out after 60s.
poll_until_complete() {
  local qid="$1"
  for _ in $(seq 1 30); do
    status="$(aws logs get-query-results --query-id "$qid" --region "$AWS_REGION" --query 'status' --output text 2>/dev/null)"
    case "$status" in
      Complete) return 0 ;;
      Failed|Cancelled|Timeout) echo "$status" >&2; return 1 ;;
    esac
    sleep 2
  done
  echo "timeout waiting for $qid" >&2
  return 1
}

poll_until_complete "$counts_qid" || exit 5
poll_until_complete "$recents_qid" || exit 5

counts_json="$(aws logs get-query-results --query-id "$counts_qid" --region "$AWS_REGION" --output json)"
recents_json="$(aws logs get-query-results --query-id "$recents_qid" --region "$AWS_REGION" --output json)"

# Reshape into a clean digest with Python. Doing this in jq would be possible
# but uglier; Python is preinstalled on macOS and reliable for both output
# formats.
python3 - "$output_format" "$since" "$counts_json" "$recents_json" <<'PY'
import json
import sys
from collections import defaultdict

out_format, since, counts_raw, recents_raw = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
counts_doc = json.loads(counts_raw)
recents_doc = json.loads(recents_raw)

def row_to_dict(row):
    return {item["field"]: item["value"] for item in row}

# Aggregate counts by type → severity.
grouped = defaultdict(lambda: defaultdict(int))
total = 0
for row in counts_doc.get("results", []):
    r = row_to_dict(row)
    t = r.get("AgentFeedbackType", "?")
    s = r.get("AgentFeedbackSeverity", "?")
    n = int(r.get("n", "0"))
    grouped[t][s] += n
    total += n

recents = []
for row in recents_doc.get("results", []):
    r = row_to_dict(row)
    recents.append({
        "timestamp": r.get("@timestamp"),
        "type": r.get("AgentFeedbackType"),
        "severity": r.get("AgentFeedbackSeverity"),
        "title": r.get("AgentFeedbackTitle"),
        "id": r.get("AgentFeedbackId"),
    })

digest = {
    "since": since,
    "total": total,
    "by_type": {
        t: {"total": sum(sevs.values()), "by_severity": dict(sevs)}
        for t, sevs in grouped.items()
    },
    "recent": recents,
}

if out_format == "json":
    print(json.dumps(digest, indent=2))
else:
    print(f"## Agent self-reports — last {since}")
    print()
    if total == 0:
        print("_No agent self-reports in this window._")
        sys.exit(0)
    print("### Counts")
    type_order = ["issue", "improvement", "observation"]
    sev_order = ["high", "medium", "low"]
    for t in type_order + [t for t in grouped if t not in type_order]:
        if t not in grouped:
            continue
        sev_pairs = grouped[t]
        breakdown = ", ".join(
            f"{s} {sev_pairs.get(s, 0)}" for s in sev_order if s in sev_pairs
        )
        line = f"- **{t}**: {sum(sev_pairs.values())}"
        if breakdown:
            line += f"  ({breakdown})"
        print(line)
    print(f"Total: **{total}**")
    print()
    print("### Recent")
    for entry in recents:
        ts = entry["timestamp"] or "?"
        meta = f"[{entry['type'] or '?'}/{entry['severity'] or '?'}]"
        title = entry["title"] or "(no title)"
        print(f"- {ts}  {meta}  {title}")
PY
