"""Test fixtures shared across the wisecat suite.

Default every test to `WISECAT_GBM_ENABLED` unset so the legacy-path tests
in `test_strategies.py` and `test_backtest.py` stay deterministic when the
suite is run from a shell that happens to have the var exported (e.g. an
operator validating a Lambda image locally before deploy).

Tests that exercise the GBM path opt in by calling
`monkeypatch.setenv("WISECAT_GBM_ENABLED", "1")` themselves — `setenv` runs
after this `delenv`, so the opt-in still takes effect.
"""

import pytest


@pytest.fixture(autouse=True)
def _disable_gbm_by_default(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.delenv("WISECAT_GBM_ENABLED", raising=False)
