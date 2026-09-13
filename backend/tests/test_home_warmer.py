from __future__ import annotations

import time
from types import SimpleNamespace

import kbo_fans_backend.api.runtime_services as runtime_services
from kbo_fans_backend.main import _start_home_sections_warmer


def test_home_sections_warmer_retries_failed_cycle_before_next_interval(
    monkeypatch,
) -> None:
    calls = []

    class _FailingThenOkHomeService:
        def get_home(self, date: str):
            calls.append(date)
            if len(calls) == 1:
                raise RuntimeError("warm failed once")
            return {"date": date}

    monkeypatch.setattr(
        runtime_services,
        "home_service",
        _FailingThenOkHomeService(),
    )

    settings = SimpleNamespace(
        home_sections_warm_enabled=True,
        # Interval clamps at 30s; the retry delay must fire well before it.
        home_sections_warm_interval_seconds=3600.0,
        home_sections_warm_retry_seconds=5.0,
    )
    stop_event = _start_home_sections_warmer(settings)
    assert stop_event is not None
    try:
        deadline = time.monotonic() + 8.0
        while len(calls) < 2 and time.monotonic() < deadline:
            time.sleep(0.05)
    finally:
        stop_event.set()

    assert len(calls) >= 2


def test_home_sections_warmer_disabled_returns_none() -> None:
    settings = SimpleNamespace(
        home_sections_warm_enabled=False,
        home_sections_warm_interval_seconds=240.0,
        home_sections_warm_retry_seconds=60.0,
    )
    assert _start_home_sections_warmer(settings) is None
