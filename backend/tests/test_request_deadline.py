from __future__ import annotations

import concurrent.futures
import threading
import time
from typing import Optional

from fastapi.testclient import TestClient

from kbo_fans_backend.api.routes import home as home_routes
from kbo_fans_backend.api.routes import metrics as metrics_routes
from kbo_fans_backend.core.config import get_settings
from kbo_fans_backend.main import create_app
from kbo_fans_backend.utils.resilience import UpstreamBusyError, UpstreamDeadlineExceeded


def test_data_get_returns_json_504_when_sync_service_never_completes(monkeypatch) -> None:
    entered = threading.Event()
    release = threading.Event()

    def blocking_home(date: str, my_team: Optional[str] = None):
        entered.set()
        release.wait()
        return {"date": date, "myTeam": my_team}

    monkeypatch.setattr(home_routes.service, "get_home", blocking_home)
    monkeypatch.setenv("DATA_REQUEST_TIMEOUT_SECONDS", "0.05")
    monkeypatch.setenv("DATA_REQUEST_MAX_CONCURRENCY", "1")
    monkeypatch.setenv("DATA_REQUEST_QUEUE_TIMEOUT_SECONDS", "0.01")
    get_settings.cache_clear()
    app = create_app()

    try:
        with TestClient(app) as client:
            executor = concurrent.futures.ThreadPoolExecutor(max_workers=1)
            try:
                started_at = time.monotonic()
                request = executor.submit(client.get, "/api/home?date=2026-08-13")
                assert entered.wait(timeout=0.5)
                response = request.result(timeout=0.5)
                response_elapsed = time.monotonic() - started_at
            finally:
                release.set()
                executor.shutdown(wait=True)
    finally:
        release.set()
        get_settings.cache_clear()

    assert response_elapsed < 0.5
    assert response.status_code == 504
    assert response.headers["cache-control"] == "no-store"
    assert response.json()["success"] is False
    assert response.json()["data"] is None
    assert response.json()["error"] == {
        "code": "UPSTREAM_DEADLINE_EXCEEDED",
        "message": "데이터 응답 시간이 초과되었습니다. 잠시 후 다시 시도해주세요.",
    }
    assert response.json()["timestamp"]


def test_data_get_returns_fast_503_when_timed_out_sync_work_still_occupies_bulkhead(
    monkeypatch,
) -> None:
    entered = threading.Event()
    release = threading.Event()
    completed = threading.Event()
    calls = 0

    def blocking_home(date: str, my_team: Optional[str] = None):
        nonlocal calls
        calls += 1
        entered.set()
        release.wait()
        completed.set()
        return {"date": date, "myTeam": my_team}

    monkeypatch.setattr(home_routes.service, "get_home", blocking_home)
    monkeypatch.setenv("DATA_REQUEST_TIMEOUT_SECONDS", "0.05")
    monkeypatch.setenv("DATA_REQUEST_MAX_CONCURRENCY", "1")
    monkeypatch.setenv("DATA_REQUEST_QUEUE_TIMEOUT_SECONDS", "0.02")
    get_settings.cache_clear()
    app = create_app()

    try:
        with TestClient(app) as client:
            executor = concurrent.futures.ThreadPoolExecutor(max_workers=1)
            try:
                first_request = executor.submit(
                    client.get,
                    "/api/home?date=2026-08-13",
                )
                assert entered.wait(timeout=0.5)
                first_response = first_request.result(timeout=0.5)
                assert first_response.status_code == 504

                started_at = time.monotonic()
                second_response = client.get("/api/home?date=2026-08-13")
                elapsed = time.monotonic() - started_at

                release.set()
                assert completed.wait(timeout=0.5)
                recovery_deadline = time.monotonic() + 0.5
                while True:
                    recovered_response = client.get("/api/home?date=2026-08-13")
                    if recovered_response.status_code != 503:
                        break
                    assert time.monotonic() < recovery_deadline
                    time.sleep(0.01)
            finally:
                release.set()
                executor.shutdown(wait=True)
    finally:
        release.set()
        get_settings.cache_clear()

    assert elapsed < 0.2
    assert second_response.status_code == 503
    assert second_response.headers["retry-after"] == "1"
    assert second_response.headers["cache-control"] == "no-store"
    assert second_response.json()["success"] is False
    assert second_response.json()["error"]["code"] == "UPSTREAM_BUSY"
    assert recovered_response.status_code == 200
    assert recovered_response.json()["data"]["date"] == "2026-08-13"
    assert calls == 2


def test_upstream_busy_error_returns_envelope_503_with_retry_after(monkeypatch) -> None:
    def busy_home(date: str, my_team: Optional[str] = None):
        raise UpstreamBusyError("home aggregate queue is full")

    monkeypatch.setattr(home_routes.service, "get_home", busy_home)
    get_settings.cache_clear()
    try:
        response = TestClient(create_app()).get("/api/home?date=2026-08-13")
    finally:
        get_settings.cache_clear()

    assert response.status_code == 503
    assert response.headers["retry-after"] == "1"
    assert response.json()["success"] is False
    assert response.json()["data"] is None
    assert response.json()["error"]["code"] == "UPSTREAM_BUSY"


def test_upstream_deadline_error_returns_envelope_504(monkeypatch) -> None:
    def expired_home(date: str, my_team: Optional[str] = None):
        raise UpstreamDeadlineExceeded("home aggregate deadline exceeded")

    monkeypatch.setattr(home_routes.service, "get_home", expired_home)
    get_settings.cache_clear()
    try:
        response = TestClient(create_app()).get("/api/home?date=2026-08-13")
    finally:
        get_settings.cache_clear()

    assert response.status_code == 504
    assert response.json()["success"] is False
    assert response.json()["data"] is None
    assert response.json()["error"] == {
        "code": "UPSTREAM_DEADLINE_EXCEEDED",
        "message": "데이터 응답 시간이 초과되었습니다. 잠시 후 다시 시도해주세요.",
    }


def test_health_metrics_and_push_diagnostics_bypass_saturated_data_bulkhead(
    monkeypatch,
) -> None:
    entered = threading.Event()
    release = threading.Event()

    def blocking_home(date: str, my_team: Optional[str] = None):
        entered.set()
        release.wait()
        return {"date": date, "myTeam": my_team}

    monkeypatch.setattr(home_routes.service, "get_home", blocking_home)
    monkeypatch.setattr(metrics_routes, "_client_metric_rate_state", {})
    monkeypatch.setenv("DATA_REQUEST_TIMEOUT_SECONDS", "0.05")
    monkeypatch.setenv("DATA_REQUEST_MAX_CONCURRENCY", "1")
    monkeypatch.setenv("DATA_REQUEST_QUEUE_TIMEOUT_SECONDS", "0.01")
    monkeypatch.setenv("PUSH_SYNC_SECRET", "")
    get_settings.cache_clear()
    app = create_app()

    try:
        with TestClient(app) as client:
            executor = concurrent.futures.ThreadPoolExecutor(max_workers=1)
            try:
                blocked_request = executor.submit(
                    client.get,
                    "/api/home?date=2026-08-13",
                )
                assert entered.wait(timeout=0.5)
                assert blocked_request.result(timeout=0.5).status_code == 504

                health = client.get("/api/health")
                metrics = client.post(
                    "/api/metrics/client",
                    json={"event": "deadline_test", "path": "/home"},
                )
                push_diagnostics = client.get("/api/push/config-status")
            finally:
                release.set()
                executor.shutdown(wait=True)
    finally:
        release.set()
        get_settings.cache_clear()

    assert health.status_code == 200
    assert health.json()["data"] == {"status": "ok"}
    assert metrics.status_code == 200
    assert metrics.json()["data"] == {"accepted": True}
    assert push_diagnostics.status_code == 503
    assert push_diagnostics.headers.get("retry-after") is None
    assert push_diagnostics.json() == {"detail": "Push sync secret is not configured"}
