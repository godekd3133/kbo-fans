from datetime import datetime, timezone

from kbo_fans_backend.scheduler.live_activity_sync_loop import (
    maybe_send_smart_daily_baseball_info,
)
from kbo_fans_backend.services.push_registry import PushRegistry


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
    assert {
        call.get("team_id")
        for call in push_service.calls
        if call["kind"] == "lineup_day"
    } >= {"LG", "KT"}
    assert any(
        call.get("topic") == "baseball_info_ALL"
        and call["kind"] == "lineup_day"
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
