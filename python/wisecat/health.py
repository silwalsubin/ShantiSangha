"""CLI health probe — pulls a live AAPL quote, prints it, exits.

  $ python -m wisecat.health
"""

import logging
import sys

from .finnhub_client import FinnhubUnavailable, get_quotes

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
logger = logging.getLogger("wisecat.health")


def main() -> int:
    try:
        quotes = get_quotes(["AAPL"])
    except FinnhubUnavailable as e:
        logger.error("finnhub unavailable: %s", e)
        return 1

    payload = quotes.get("AAPL")
    if not payload:
        logger.error("no AAPL quote returned")
        return 1

    logger.info(
        "AAPL last=%s prev_close=%s high=%s low=%s",
        payload.get("price"),
        payload.get("prev_close"),
        payload.get("day_high"),
        payload.get("day_low"),
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
