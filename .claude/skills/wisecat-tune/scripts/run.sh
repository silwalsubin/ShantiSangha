#!/usr/bin/env bash
# Wrapper for `python -m wisecat.tune_basket`. Activates the wisecat venv
# (creating + installing if missing), then runs the basket tune.
#
# Usage:
#   bash .claude/skills/wisecat-tune/scripts/run.sh                # NASDAQ-100, --start 2014-01-01, 8 workers
#   bash .claude/skills/wisecat-tune/scripts/run.sh --start 2018-01-01
#   bash .claude/skills/wisecat-tune/scripts/run.sh --tickers AAPL,MSFT,NVDA
#
# All extra args are passed straight through to wisecat.tune_basket. The
# default `--start 2014-01-01 --workers 8` is applied only when those flags
# are absent.

set -euo pipefail

# Repo root = parent of .claude/skills/wisecat-tune/scripts/run.sh
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"
PY_DIR="$REPO_ROOT/python"
VENV="$PY_DIR/.venv"

cd "$PY_DIR"

if [ ! -f "$VENV/bin/python" ]; then
    echo "[wisecat-tune] creating venv at $VENV…" >&2
    python3 -m venv "$VENV"
    "$VENV/bin/pip" install --quiet --upgrade pip
fi

# Install / sync deps if requirements.txt is newer than the marker file.
MARKER="$VENV/.requirements-installed"
REQ="$PY_DIR/wisecat/requirements.txt"
if [ ! -f "$MARKER" ] || [ "$REQ" -nt "$MARKER" ]; then
    echo "[wisecat-tune] installing wisecat requirements…" >&2
    "$VENV/bin/pip" install --quiet -r "$REQ"
    touch "$MARKER"
fi

# Default args inserted only when caller didn't supply them.
ARGS=("$@")
HAS_START=false
HAS_WORKERS=false
for arg in "${ARGS[@]}"; do
    case "$arg" in
        --start|--start=*) HAS_START=true ;;
        --workers|--workers=*) HAS_WORKERS=true ;;
    esac
done
$HAS_START   || ARGS+=(--start 2014-01-01)
$HAS_WORKERS || ARGS+=(--workers 8)

exec "$VENV/bin/python" -m wisecat.tune_basket "${ARGS[@]}"
