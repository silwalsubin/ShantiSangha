# Wise Cat — Python service

FastAPI service that talks to Finnhub and computes technical scores for tickers.
The .NET backend (`ShantiSangha.Trading`) calls this; nothing else does.

## First-time setup

1. Sign up at https://finnhub.io and grab your API key from the dashboard.
   Free tier: 60 calls/min, 15-min delayed US stock quotes, daily candles included.
   (For sub-second SIP real-time later, upgrade the plan — same API key, no code change.)

2. Add the key to GitHub repo secrets as `TF_VAR_FINNHUB_API_KEY`. The Terraform workflow picks it up automatically (see `.github/workflows/terraform.yml`), writes it to AWS Secrets Manager (`shantisangha/finnhub_api_key`), and the ECS task definition injects it as `WISECAT_FINNHUB_API_KEY` at runtime.

   Then run the Terraform workflow (manual `apply` via workflow_dispatch) to provision the new ECS service + secrets.

## Local dev

```
cd python
python -m venv .venv && source .venv/bin/activate
pip install -r wisecat/requirements.txt

cat > wisecat/.env <<EOF
WISECAT_INTERNAL_KEY=devkey
WISECAT_FINNHUB_API_KEY=YOUR_KEY
EOF

python -m wisecat.health    # prints a live AAPL quote
uvicorn wisecat.main:app --reload --port 8000
```

Then:

```
# /score is pure compute — caller passes cached bars (the .NET side does this in production)
curl -H "Authorization: Bearer devkey" \
     -H "Content-Type: application/json" \
     -d '{"items":[{"ticker":"AAPL","bars":[{"date":"2026-04-01","open":170,"high":171,"low":169,"close":170.5,"volume":1000000}]}]}' \
     http://127.0.0.1:8000/score

# /history hits Finnhub — the .NET side calls this for delta-only backfill
curl -H "Authorization: Bearer devkey" \
     "http://127.0.0.1:8000/history/AAPL?from_date=2026-05-01"
```

## Tests

```
cd python
pytest wisecat/tests
```

## Endpoints

| Path | Auth | Hits Finnhub? | Purpose |
| --- | --- | --- | --- |
| `GET /healthz` | none | yes (cheap probe) | ECS health |
| `POST /score` | bearer | **no** | pure compute — caller passes bars |
| `GET /quote/{ticker}` | bearer | yes | live quote (15-min delayed on free Finnhub) |
| `GET /history/{ticker}?from_date=YYYY-MM-DD` | bearer | yes | delta backfill of OHLCV |

The .NET side caches all OHLCV in `TickerDailyClose` and only calls `/history` for missing dates, then passes the merged bars to `/score`.

## Limits

- Free tier: 60 calls/min. Daily job batches `len(tickers)` quotes + history calls; keep total watchlist tickers under ~30 to stay safely below limit during refresh.
- `prev_close`/`day_high`/`day_low` are returned but the .NET side currently ignores them; available for future use.
