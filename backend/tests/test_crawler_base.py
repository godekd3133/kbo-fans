import concurrent.futures
import threading

import pytest

import kbo_fans_backend.crawlers.base as base_module
from kbo_fans_backend.crawlers.base import BaseCrawler


def test_circuit_breaker_state_prunes_expired_and_bounds_high_cardinality_keys(
    monkeypatch,
) -> None:
    monkeypatch.setattr(BaseCrawler, "_CIRCUIT_BREAKER_MAX_KEYS", 3, raising=False)
    monkeypatch.setattr(BaseCrawler, "_CIRCUIT_BREAKER_STATE_TTL_SECONDS", 30, raising=False)
    monkeypatch.setattr(
        BaseCrawler,
        "_breaker_state",
        {
            "expired": {"failures": 3, "opened_until": 90.0, "updated_at": 50.0},
            "stale": {"failures": 1, "opened_until": 0.0, "updated_at": 60.0},
            "keep-a": {"failures": 1, "opened_until": 0.0, "updated_at": 95.0},
            "keep-b": {"failures": 2, "opened_until": 150.0, "updated_at": 99.0},
            "overflow": {"failures": 1, "opened_until": 0.0, "updated_at": 100.0},
        },
    )

    BaseCrawler._prune_breaker_state(100.0)

    assert "expired" not in BaseCrawler._breaker_state
    assert "stale" not in BaseCrawler._breaker_state
    assert set(BaseCrawler._breaker_state) == {"keep-a", "keep-b", "overflow"}


def test_parallel_crawler_requests_use_isolated_sessions(monkeypatch) -> None:
    request_sessions = []
    start_barrier = threading.Barrier(2)

    class _Response:
        text = "ok"

        def raise_for_status(self) -> None:
            return None

    class _Session:
        def __init__(self) -> None:
            self.headers = {}

        def request(self, method: str, url: str, **kwargs):
            del method, url, kwargs
            request_sessions.append(self)
            start_barrier.wait(timeout=1)
            return _Response()

    monkeypatch.setattr(base_module, "Session", _Session)
    crawler = BaseCrawler()

    with concurrent.futures.ThreadPoolExecutor(max_workers=2) as executor:
        futures = [
            executor.submit(crawler._get_text, f"https://example.test/{index}")
            for index in range(2)
        ]
        assert [future.result(timeout=1) for future in futures] == ["ok", "ok"]

    assert len(request_sessions) == 2
    assert request_sessions[0] is not request_sessions[1]
    assert all(session is not crawler.session for session in request_sessions)


def test_parallel_failures_update_circuit_breaker_without_lost_increments(monkeypatch) -> None:
    monkeypatch.setattr(BaseCrawler, "_breaker_state", {})
    start_barrier = threading.Barrier(3)

    class _FailingSession:
        def __init__(self) -> None:
            self.headers = {}

        def request(self, method: str, url: str, **kwargs):
            del method, url, kwargs
            start_barrier.wait(timeout=1)
            raise RuntimeError("upstream unavailable")

    monkeypatch.setattr(base_module, "Session", _FailingSession)
    crawler = BaseCrawler()

    with concurrent.futures.ThreadPoolExecutor(max_workers=3) as executor:
        futures = [
            executor.submit(
                crawler._request,
                "GET",
                "https://example.test",
                breaker_key="breaker-test",
            )
            for _ in range(3)
        ]
        for future in futures:
            with pytest.raises(RuntimeError, match="upstream unavailable"):
                future.result(timeout=1)

    assert BaseCrawler._breaker_state["breaker-test"]["failures"] == 3
    assert BaseCrawler._breaker_state["breaker-test"]["opened_until"] > 0
