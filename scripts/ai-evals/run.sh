#!/usr/bin/env bash
# Wrapper that:
#   1. Fetches OPENAI_API_KEY from AWS Secrets Manager (shantisangha/openai_api_key)
#   2. Activates the local venv and runs run_eval.py with whatever args you pass
#
# Usage:
#   ./run.sh --iteration baseline --runs 3
#   ./run.sh --eval marriage_grounded --runs 1 --temperature 0
#
# The OpenAI key lives only in this process — never in env files, never in
# shell history. GPT-4o is used for both response generation and judge.

set -euo pipefail

cd "$(dirname "$0")"

AWS_PROFILE="${AWS_PROFILE:-AdministratorAccess-362249013106}"

if [[ ! -d .venv ]]; then
  echo "Creating venv..."
  python3 -m venv .venv
  ./.venv/bin/pip install -q -r requirements.txt
fi

echo "Fetching OPENAI_API_KEY from AWS Secrets Manager (profile=$AWS_PROFILE)..."
OPENAI_API_KEY=$(aws --profile "$AWS_PROFILE" secretsmanager get-secret-value \
  --secret-id shantisangha/openai_api_key \
  --query SecretString --output text)

if [[ -z "$OPENAI_API_KEY" || "$OPENAI_API_KEY" != sk-* ]]; then
  echo "ERROR: OpenAI key fetch failed. Check that you are SSO-logged-in:"
  echo "  aws sso login --profile $AWS_PROFILE"
  exit 1
fi

export OPENAI_API_KEY

# Preflight OpenAI with a list-models call so a credential or quota error
# fails fast instead of mid-run.
echo "Preflighting OpenAI (20s timeout)..."
if ! ./.venv/bin/python - <<'PY'
import sys
from openai import OpenAI
print("  OpenAI: listing models...", flush=True)
try:
    client = OpenAI(timeout=20.0)
    models = client.models.list()
    print(f"  OpenAI: ok ({sum(1 for _ in models)} models visible)", flush=True)
except Exception as e:
    print(f"  OpenAI FAILED: {e.__class__.__name__}: {e}", flush=True)
    sys.exit(1)
PY
then
  echo "ERROR: preflight failed (see above)"
  exit 1
fi
echo "Preflight ok. Running eval..."

exec ./.venv/bin/python run_eval.py "$@"
