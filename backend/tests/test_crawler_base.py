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
