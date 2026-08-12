from fastapi.testclient import TestClient

from kbo_fans_backend.main import app


def test_client_metrics_accepts_small_json_payload() -> None:
    response = TestClient(app).post(
        "/api/metrics/client",
        json={"event": "screen_loaded", "path": "/home", "durationMs": 42},
    )

    assert response.status_code == 200
    assert response.json()["data"] == {"accepted": True}


def test_client_metrics_rejects_oversized_body_before_logging() -> None:
    response = TestClient(app).post(
        "/api/metrics/client",
        content=(b"{" + b'"event":"' + (b"x" * 17000) + b'"}'),
        headers={"content-type": "application/json"},
    )

    assert response.status_code == 413


def test_client_metrics_rejects_non_object_json() -> None:
    response = TestClient(app).post(
        "/api/metrics/client",
        content=b"[1, 2, 3]",
        headers={"content-type": "application/json"},
    )

    assert response.status_code == 422


def test_client_metrics_rate_limits_a_single_source(monkeypatch) -> None:
    monkeypatch.setattr("kbo_fans_backend.api.routes.metrics._MAX_CLIENT_METRIC_REQUESTS", 1)
    monkeypatch.setattr("kbo_fans_backend.api.routes.metrics._client_metric_rate_state", {})

    first = TestClient(app).post(
        "/api/metrics/client",
        json={"event": "screen_loaded"},
    )
    second = TestClient(app).post(
        "/api/metrics/client",
        json={"event": "screen_loaded"},
    )

    assert first.status_code == 200
    assert second.status_code == 429
