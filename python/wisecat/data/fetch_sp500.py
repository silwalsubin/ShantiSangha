"""Fetch the S&P 500 component list from Wikipedia and write it to
`sp500.txt` next to this file. Re-run any time the user wants a fresh
snapshot — index membership rotates ~20 names a year.

CLI:
    python -m wisecat.data.fetch_sp500
"""

from __future__ import annotations

from io import StringIO
from pathlib import Path

import httpx
import pandas as pd

WIKIPEDIA_URL = "https://en.wikipedia.org/wiki/List_of_S%26P_500_companies"
# Wikipedia returns 403 to bare urllib. A real-looking User-Agent is enough
# to be served the page; their robots.txt allows automated access for
# read-only article fetches.
USER_AGENT = (
    "ShantiSangha-WiseCat/1.0 "
    "(+https://shantisangha.com; tuning helper for an internal trading-signal ensemble)"
)


def fetch_sp500_tickers() -> list[str]:
    """Returns the current S&P 500 ticker list, sorted, deduplicated, and
    yfinance-normalized (Wikipedia uses BRK.B / BF.B; yfinance wants
    BRK-B / BF-B).
    """
    resp = httpx.get(WIKIPEDIA_URL, headers={"User-Agent": USER_AGENT}, timeout=30.0)
    resp.raise_for_status()
    tables = pd.read_html(StringIO(resp.text))
    # Page has multiple tables; component table is the first with a "Symbol" column.
    df = next(t for t in tables if "Symbol" in t.columns)
    tickers = (
        df["Symbol"].astype(str)
        .str.strip()
        .str.replace(".", "-", regex=False)  # BRK.B → BRK-B
        .tolist()
    )
    return sorted(set(t for t in tickers if t and t != "nan"))


def main() -> None:
    tickers = fetch_sp500_tickers()
    out = Path(__file__).parent / "sp500.txt"
    with open(out, "w") as f:
        f.write("# S&P 500 components — fetched from Wikipedia.\n")
        f.write(f"# To refresh: python -m wisecat.data.fetch_sp500\n")
        f.write("# Lines starting with `#` and blank lines are ignored.\n")
        f.write("# Tickers without enough history at the requested start date are skipped automatically.\n")
        for t in tickers:
            f.write(f"{t}\n")
    print(f"wrote {len(tickers)} tickers to {out}")


if __name__ == "__main__":
    main()
