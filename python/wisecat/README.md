# Wise Cat — Python Lambda

AWS Lambda (container image) that talks to Finnhub and computes technical
scores. The .NET API (`ShantiSangha.Trading`) invokes it directly via the AWS
SDK; IAM is the auth boundary.

## First-time setup

1. Sign up at https://finnhub.io and grab your API key.
2. Add it to GitHub repo secrets as `TF_VAR_FINNHUB_API_KEY`.
3. Bootstrap order (one time):
   - Trigger this workflow once. The image push to ECR succeeds; the Lambda
     update step exits 0 with a "function does not exist yet" message.
   - Run the Terraform workflow with `apply`. It creates the Lambda function
     pointing at the freshly-pushed image, plus the IAM role / log group.
   - Subsequent pushes to `main` (under `python/**`) build a new image and
     `aws lambda update-function-code` flips the function to it.

## Local dev

The same code can still run as a FastAPI server for local iteration — the
`wisecat.main` module exposes the same endpoints over HTTP. The Lambda entry
point is `wisecat.lambda_handler.handler`.

```
cd python
python -m venv .venv && source .venv/bin/activate
pip install -r wisecat/requirements.txt

cat > wisecat/.env <<EOF
WISECAT_FINNHUB_API_KEY=YOUR_KEY
EOF

python -m wisecat.health    # prints a live AAPL quote
uvicorn wisecat.main:app --reload --port 8000
```

## Lambda invoke shape

The .NET caller sends JSON payloads with an `action` key:

```
{"action": "score", "items": [{"ticker": "AAPL", "bars": [...], "price": 170.5}]}
{"action": "history", "ticker": "AAPL", "fromDate": "2026-04-01"}
{"action": "quote", "ticker": "AAPL"}
{"action": "healthz"}
```

On success the handler returns the response payload as-is. On failure the
handler raises and Lambda returns `FunctionError`, which the .NET side logs
and treats as "no data."

## Tests

```
cd python
pytest wisecat/tests
```
