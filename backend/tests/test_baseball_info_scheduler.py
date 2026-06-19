from kbo_fans_backend.scheduler import baseball_info


def test_baseball_info_scheduler_sends_weekly_check_on_monday(monkeypatch) -> None:
    captured = {}

    class FakePushService:
        def send_baseball_info(self, **kwargs):
            captured.update(kwargs)
            return {"sent": True, "kind": kwargs["kind"], "messages": []}

    monkeypatch.setattr(baseball_info, "PushService", FakePushService)

    result = baseball_info.send_once(date="2026-06-22")

    assert result["sent"] is True
    assert result["kind"] == "weekly_check"
    assert captured["date"] == "2026-06-22"
    assert captured["kind"] == "weekly_check"


def test_baseball_info_scheduler_skips_non_monday_without_explicit_kind(
    monkeypatch,
) -> None:
    class FakePushService:
        def send_baseball_info(self, **kwargs):
            raise AssertionError("non-Monday default should not send")

    monkeypatch.setattr(baseball_info, "PushService", FakePushService)

    result = baseball_info.send_once(date="2026-06-23")

    assert result == {
        "sent": False,
        "date": "2026-06-23",
        "reason": "no scheduled baseball info prompt",
    }


def test_baseball_info_scheduler_uses_explicit_kind_on_any_day(monkeypatch) -> None:
    captured = {}

    class FakePushService:
        def send_baseball_info(self, **kwargs):
            captured.update(kwargs)
            return {"sent": True, "kind": kwargs["kind"], "messages": []}

    monkeypatch.setattr(baseball_info, "PushService", FakePushService)

    result = baseball_info.send_once(date="2026-06-23", kind="records_check")

    assert result["sent"] is True
    assert captured["kind"] == "records_check"
    assert captured["date"] == "2026-06-23"
