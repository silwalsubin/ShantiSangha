"""Guard the all-zero neutral sentinel.

`_neutral_horizon()` must emit a probability triple of (0, 0, 0). The C#
backend (TradingSignalService.DeriveVerdict) treats sum < 0.001 as
"GBM didn't run" and emits Hold with zero conviction. If this regresses
to the old `pHold=1.0` Pydantic default, the backend will read the
fallback as a confident "fully Hold" verdict, which is the bug we just
fixed.
"""

from __future__ import annotations

import pandas as pd

from wisecat.scoring import _neutral_horizon, score_ticker


def test_neutral_horizon_is_all_zero_sentinel() -> None:
    h = _neutral_horizon()
    assert h.p_buy == 0.0
    assert h.p_hold == 0.0
    assert h.p_sell == 0.0
    assert h.expected_return == 0.0
    assert h.score == 0.0
    assert h.signals == []


def test_empty_dataframe_emits_neutral_sentinel_for_every_horizon() -> None:
    result = score_ticker("AAPL", pd.DataFrame(), price=None)
    assert result.error == "no historical data"
    for horizon, score in result.horizons.items():
        assert score.p_buy == 0.0, f"{horizon}: p_buy not zero"
        assert score.p_hold == 0.0, f"{horizon}: p_hold not zero"
        assert score.p_sell == 0.0, f"{horizon}: p_sell not zero"
