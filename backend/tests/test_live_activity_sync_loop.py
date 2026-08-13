import logging
import threading
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone

import pytest

from kbo_fans_backend.scheduler import live_activity_sync as live_activity_sync_scheduler
from kbo_fans_backend.scheduler import live_activity_sync_loop
from kbo_fans_backend.scheduler.live_activity_sync_loop import (
    ScoreboardWarmer,
    maybe_send_smart_daily_baseball_info,
)
from kbo_fans_backend.services.push_registry import PushRegistry


def test_scoreboard_warmer_keeps_running_while_sync_delivery_is_blocked(
    monkeypatch,
) -> None:
    sync_delivery_started = threading.Event()
    release_sync_delivery = threading.Event()
    warmed_twice = threading.Event()
    calls = []
    calls_guard = threading.Lock()

    class _FakeScoreboardService:
        def prime_home_scoreboard(self, date: str) -> dict:
            with calls_guard:
                calls.append(date)
                if len(calls) >= 2:
                    warmed_twice.set()
            return {"date": date, "games": []}

    def block_sync_delivery(_date: str) -> dict:
        sync_delivery_started.set()
        assert release_sync_delivery.wait(timeout=2)
        return {"date": "2026-08-13", "sent": True}

    warmer = ScoreboardWarmer(
        scoreboard_service=_FakeScoreboardService(),
        interval_seconds=0.01,
        date_provider=lambda: "2026-08-13",
    )
    result = []
    configured_warm_intervals = []
    main_thread = threading.Thread(
        target=lambda: result.append(
            live_activity_sync_loop.main(
                [
                    "--date",
                    "2026-08-13",
                    "--interval-seconds",
                    "60",
                    "--scoreboard-warm-interval-seconds",
                    "5",
                ]
            )
        )
    )

    monkeypatch.setattr(live_activity_sync_loop, "sync_once", block_sync_delivery)

    def build_warmer(**kwargs):
        configured_warm_intervals.append(kwargs["interval_seconds"])
        return warmer

    monkeypatch.setattr(live_activity_sync_loop, "ScoreboardWarmer", build_warmer)
    monkeypatch.setattr(live_activity_sync_loop.signal, "signal", lambda *args: None)
    monkeypatch.setattr(live_activity_sync_loop, "_SHOULD_STOP", False)

    stopped_while_sync_blocked = False
    main_thread.start()
    try:
        assert sync_delivery_started.wait(timeout=1)
        assert warmed_twice.wait(timeout=1)
        assert main_thread.is_alive()
        assert calls[:2] == ["2026-08-13", "2026-08-13"]
    finally:
        live_activity_sync_loop._handle_stop(None, None)
        warmer.join(timeout=1)
        stopped_while_sync_blocked = not warmer.is_alive() and main_thread.is_alive()
        release_sync_delivery.set()
        main_thread.join(timeout=1)

    assert stopped_while_sync_blocked is True
    assert warmer.is_alive() is False
    assert main_thread.is_alive() is False
    assert result == [0]
    assert configured_warm_intervals == [5]


def test_scoreboard_warm_interval_requires_live_state_freshness_jitter(
    monkeypatch,
) -> None:
    monkeypatch.setenv("LIVE_SCOREBOARD_MAX_AGE_SECONDS", "20")

    live_activity_sync_loop._validate_scoreboard_warm_interval(15)

    with pytest.raises(SystemExit, match="must be at least 21"):
        live_activity_sync_loop._validate_scoreboard_warm_interval(16)


def test_scoreboard_warmer_continues_after_release_safe_failure(caplog) -> None:
    warmed_after_failure = threading.Event()
    calls = []

    class _FlakyScoreboardService:
        def prime_home_scoreboard(self, date: str) -> dict:
            calls.append(date)
            if len(calls) == 1:
                raise RuntimeError("sensitive-upstream-detail")
            warmed_after_failure.set()
            return {"date": date, "games": []}

    warmer = ScoreboardWarmer(
        scoreboard_service=_FlakyScoreboardService(),
        interval_seconds=0.01,
        date_provider=lambda: "2026-08-13",
    )

    with caplog.at_level(logging.WARNING):
        warmer.start()
        try:
            assert warmed_after_failure.wait(timeout=1)
        finally:
            warmer.stop()
            warmer.join(timeout=1)

    assert calls[:2] == ["2026-08-13", "2026-08-13"]
    assert "RuntimeError" in caplog.text
    assert "sensitive-upstream-detail" not in caplog.text
    assert warmer.is_alive() is False


def test_live_activity_sync_scheduler_reuses_worker_service_instance(monkeypatch) -> None:
    created = []

    class _FakeSyncService:
        def __init__(self, **kwargs) -> None:
            del kwargs
            created.append(self)

        def sync_date(self, date: str) -> dict:
            return {"date": date, "service": len(created)}

    monkeypatch.setattr(
        live_activity_sync_scheduler,
        "LiveActivityScoreboardSyncService",
        _FakeSyncService,
    )
    monkeypatch.setattr(live_activity_sync_scheduler, "_sync_service_instance", None)

    first = live_activity_sync_scheduler.sync_once("2026-06-22")
    second = live_activity_sync_scheduler.sync_once("2026-06-22")

    assert first == {"date": "2026-06-22", "service": 1}
    assert second == {"date": "2026-06-22", "service": 1}
    assert len(created) == 1


def test_live_activity_sync_scheduler_closes_worker_service(monkeypatch) -> None:
    created = []

    class _FakeSyncService:
        def __init__(self, **kwargs) -> None:
            del kwargs
            self.closed = False
            created.append(self)

        def sync_date(self, date: str) -> dict:
            return {"date": date}

        def close(self) -> None:
            self.closed = True

    monkeypatch.setattr(
        live_activity_sync_scheduler,
        "LiveActivityScoreboardSyncService",
        _FakeSyncService,
    )
    monkeypatch.setattr(live_activity_sync_scheduler, "_sync_service_instance", None)

    live_activity_sync_scheduler.sync_once("2026-06-22")
    live_activity_sync_scheduler.close_sync_service()

    assert created[0].closed is True
    assert live_activity_sync_scheduler._sync_service_instance is None


class _FakeScoreboardService:
    def get_home_scoreboard(self, date):
        return {
            "date": date,
            "games": [
                {
                    "status": "SCHEDULED",
                    "startTime": "18:30",
                    "away": {"teamId": "LG"},
                    "home": {"teamId": "KT"},
                }
            ],
        }


class _FakePushService:
    def __init__(self) -> None:
        self.calls = []

    def send_baseball_info(self, **kwargs):
        self.calls.append(kwargs)
        return {"sent": True, "kind": kwargs["kind"], "messages": []}


def test_sync_loop_sends_smart_daily_baseball_info_once_per_slot(tmp_path) -> None:
    registry = PushRegistry(str(tmp_path / "push_registry.json"))
    push_service = _FakePushService()

    first = maybe_send_smart_daily_baseball_info(
        now=datetime(2026, 6, 22, 16, 0, tzinfo=timezone.utc),
        registry=registry,
        push_service=push_service,
        scoreboard_service=_FakeScoreboardService(),
        slots=["16:00"],
    )
    second = maybe_send_smart_daily_baseball_info(
        now=datetime(2026, 6, 22, 16, 0, tzinfo=timezone.utc),
        registry=registry,
        push_service=push_service,
        scoreboard_service=_FakeScoreboardService(),
        slots=["16:00"],
    )

    assert first["sent"] is True
    assert first["slot"] == "16:00"
    assert first["mode"] == "smart_daily"
    assert second == {
        "sent": False,
        "mode": "smart_daily",
        "slot": "16:00",
        "date": "2026-06-22",
        "reason": "already_sent",
    }
    assert len(push_service.calls) == 11
    assert {call.get("team_id") for call in push_service.calls if call["kind"] == "lineup_day"} >= {
        "LG",
        "KT",
    }
    assert any(
        call.get("topic") == "baseball_info_ALL" and call["kind"] == "lineup_day"
        for call in push_service.calls
    )


def test_sync_loop_skips_smart_daily_baseball_info_outside_slots(tmp_path) -> None:
    registry = PushRegistry(str(tmp_path / "push_registry.json"))
    push_service = _FakePushService()

    result = maybe_send_smart_daily_baseball_info(
        now=datetime(2026, 6, 22, 15, 40, tzinfo=timezone.utc),
        registry=registry,
        push_service=push_service,
        scoreboard_service=_FakeScoreboardService(),
        slots=["16:00"],
    )

    assert result == {
        "sent": False,
        "mode": "smart_daily",
        "reason": "not_due",
    }
    assert push_service.calls == []


def test_sync_loop_does_not_mark_smart_daily_sent_when_delivery_fails(
    tmp_path,
) -> None:
    class _FailingPushService(_FakePushService):
        def send_baseball_info(self, **kwargs):
            self.calls.append(kwargs)
            if len(self.calls) == 6:
                raise RuntimeError("temporary FCM failure")
            return {"sent": True, "kind": kwargs["kind"], "messages": []}

    registry = PushRegistry(str(tmp_path / "push_registry.json"))
    push_service = _FailingPushService()
    now = datetime(2026, 6, 22, 16, 0, tzinfo=timezone.utc)
    alert_key = "baseball_info:smart_daily:2026-06-22:16:00"

    with pytest.raises(RuntimeError, match="temporary FCM failure"):
        maybe_send_smart_daily_baseball_info(
            now=now,
            registry=registry,
            push_service=push_service,
            scoreboard_service=_FakeScoreboardService(),
            slots=["16:00"],
        )

    assert registry.scheduled_alert_sent(alert_key) is False

    retry_service = _FakePushService()
    retry = maybe_send_smart_daily_baseball_info(
        now=now,
        registry=registry,
        push_service=retry_service,
        scoreboard_service=_FakeScoreboardService(),
        slots=["16:00"],
    )

    assert retry["sent"] is True
    assert len(push_service.calls) == 6
    assert len(retry_service.calls) == 6
    assert registry.scheduled_alert_sent(alert_key) is True


def test_sync_loop_does_not_mark_smart_daily_sent_after_partial_delivery(
    tmp_path,
) -> None:
    class _PartiallyFailingPushService(_FakePushService):
        def send_baseball_info(self, **kwargs):
            self.calls.append(kwargs)
            return {
                "sent": len(self.calls) != 1,
                "kind": kwargs["kind"],
                "messages": [],
            }

    registry = PushRegistry(str(tmp_path / "push_registry.json"))
    now = datetime(2026, 6, 22, 16, 0, tzinfo=timezone.utc)
    alert_key = "baseball_info:smart_daily:2026-06-22:16:00"

    push_service = _PartiallyFailingPushService()
    result = maybe_send_smart_daily_baseball_info(
        now=now,
        registry=registry,
        push_service=push_service,
        scoreboard_service=_FakeScoreboardService(),
        slots=["16:00"],
    )

    assert result["sent"] is True
    assert len(push_service.calls) == 11
    assert len(registry.scheduled_delivery_ids(alert_key)) == 10
    assert registry.scheduled_alert_sent(alert_key) is False

    retry_service = _FakePushService()
    retry = maybe_send_smart_daily_baseball_info(
        now=now,
        registry=registry,
        push_service=retry_service,
        scoreboard_service=_FakeScoreboardService(),
        slots=["16:00"],
    )

    assert retry["sent"] is True
    assert len(retry_service.calls) == 1
    assert registry.scheduled_alert_sent(alert_key) is True


def test_sync_loop_claims_smart_daily_targets_across_concurrent_workers(
    tmp_path,
) -> None:
    class _BlockingPushService(_FakePushService):
        def __init__(self) -> None:
            super().__init__()
            self._guard = threading.Lock()
            self.first_call_started = threading.Event()
            self.release_first_call = threading.Event()

        def send_baseball_info(self, **kwargs):
            with self._guard:
                self.calls.append(kwargs)
                call_number = len(self.calls)
            if call_number == 1:
                self.first_call_started.set()
                assert self.release_first_call.wait(timeout=5)
            return {"sent": True, "kind": kwargs["kind"], "messages": []}

    registry_path = str(tmp_path / "push_registry.json")
    first_registry = PushRegistry(registry_path)
    second_registry = PushRegistry(registry_path)
    push_service = _BlockingPushService()
    now = datetime(2026, 6, 22, 16, 0, tzinfo=timezone.utc)
    alert_key = "baseball_info:smart_daily:2026-06-22:16:00"

    with ThreadPoolExecutor(max_workers=2) as executor:
        first_future = executor.submit(
            maybe_send_smart_daily_baseball_info,
            now=now,
            registry=first_registry,
            push_service=push_service,
            scoreboard_service=_FakeScoreboardService(),
            slots=["16:00"],
        )
        assert push_service.first_call_started.wait(timeout=5)
        second_future = executor.submit(
            maybe_send_smart_daily_baseball_info,
            now=now,
            registry=second_registry,
            push_service=push_service,
            scoreboard_service=_FakeScoreboardService(),
            slots=["16:00"],
        )
        second_result = second_future.result(timeout=5)
        push_service.release_first_call.set()
        first_result = first_future.result(timeout=5)

    targets = [call.get("topic") or f"team:{call.get('team_id')}" for call in push_service.calls]
    assert len(push_service.calls) == 11
    assert len(set(targets)) == 11
    assert first_result["sent"] is True
    assert second_result["sent"] is True
    assert first_registry.scheduled_alert_sent(alert_key) is True


def test_completed_smart_daily_slot_cannot_recreate_delivery_claims(tmp_path) -> None:
    registry = PushRegistry(str(tmp_path / "push_registry.json"))
    alert_key = "baseball_info:smart_daily:2026-06-22:16:00"
    delivery_id = "team:LG"

    claim_id = registry.claim_scheduled_delivery(alert_key, delivery_id)

    assert claim_id is not None
    assert registry.mark_scheduled_delivery_sent(
        alert_key,
        delivery_id,
        claim_id=claim_id,
    )
    assert registry.mark_scheduled_alert_sent_if_deliveries_complete(
        alert_key,
        [delivery_id],
    )
    assert registry.claim_scheduled_delivery(alert_key, delivery_id) is None
