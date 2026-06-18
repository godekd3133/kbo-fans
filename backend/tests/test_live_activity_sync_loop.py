import pytest

from kbo_fans_backend.scheduler import live_activity_sync_loop


def test_live_activity_sync_loop_defaults_to_8_seconds(monkeypatch, capsys) -> None:
    sleep_intervals = []

    monkeypatch.delenv("PUSH_SYNC_INTERVAL_SECONDS", raising=False)
    monkeypatch.setattr(live_activity_sync_loop, "_SHOULD_STOP", False)
    monkeypatch.setattr(live_activity_sync_loop.signal, "signal", lambda *_: None)
    monkeypatch.setattr(live_activity_sync_loop, "current_kbo_date", lambda: "2026-06-18")
    monkeypatch.setattr(
        live_activity_sync_loop,
        "sync_once",
        lambda sync_date: {"date": sync_date, "sent": True},
    )

    def stop_after_sleep(interval_seconds: int) -> None:
        sleep_intervals.append(interval_seconds)
        live_activity_sync_loop._SHOULD_STOP = True

    monkeypatch.setattr(
        live_activity_sync_loop,
        "_sleep_until_next_run",
        stop_after_sleep,
    )

    try:
        assert live_activity_sync_loop.main([]) == 0
    finally:
        live_activity_sync_loop._SHOULD_STOP = False

    assert sleep_intervals == [8]
    assert '"date": "2026-06-18"' in capsys.readouterr().out


def test_live_activity_sync_loop_rejects_sub_8_second_interval(monkeypatch) -> None:
    monkeypatch.setattr(live_activity_sync_loop, "_SHOULD_STOP", False)

    with pytest.raises(SystemExit, match="interval-seconds must be at least 8"):
        live_activity_sync_loop.main(["--interval-seconds", "7"])
