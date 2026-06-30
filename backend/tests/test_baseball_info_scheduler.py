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


def test_baseball_info_scheduler_passes_dry_run_to_push_service(monkeypatch) -> None:
    captured = {}

    class FakePushService:
        def send_baseball_info(self, **kwargs):
            captured.update(kwargs)
            return {"sent": False, "dryRun": kwargs["dry_run"], "messages": []}

    monkeypatch.setattr(baseball_info, "PushService", FakePushService)

    result = baseball_info.send_once(date="2026-06-22", dry_run=True)

    assert result["sent"] is False
    assert result["dryRun"] is True
    assert captured["kind"] == "weekly_check"
    assert captured["dry_run"] is True


def test_smart_daily_plan_uses_game_day_for_scheduled_team_and_rival_watch_for_idle_team() -> None:
    plan = baseball_info.build_smart_daily_plan(
        games=[
            {
                "status": "SCHEDULED",
                "startTime": "18:30",
                "away": {"teamId": "LG"},
                "home": {"teamId": "KT"},
            }
        ],
        team_id=None,
        now_time="12:00",
    )

    by_team = {item.get("teamId"): item["kind"] for item in plan if item.get("teamId")}
    league_item = next(item for item in plan if item.get("topic") == "baseball_info_ALL")
    assert by_team["LG"] == "game_day"
    assert by_team["KT"] == "game_day"
    assert by_team["HH"] == "rival_watch"
    assert league_item["kind"] == "game_day"


def test_smart_daily_plan_uses_lineup_day_near_scheduled_start() -> None:
    plan = baseball_info.build_smart_daily_plan(
        games=[
            {
                "gameId": "20260630LTOB0",
                "status": "SCHEDULED",
                "startTime": "18:30",
                "stadium": "잠실",
                "away": {"teamId": "LT", "shortName": "롯데"},
                "home": {"teamId": "OB", "shortName": "두산"},
            }
        ],
        team_id="OB",
        now_time="16:00",
    )

    assert plan == [
        {
            "teamId": "OB",
            "kind": "lineup_day",
            "gameId": "20260630LTOB0",
            "matchup": "롯데 vs 두산",
            "startTime": "18:30",
            "stadium": "잠실",
        }
    ]


def test_smart_daily_plan_uses_records_check_after_final_game() -> None:
    plan = baseball_info.build_smart_daily_plan(
        games=[
            {
                "status": "FINAL",
                "away": {"teamId": "LG"},
                "home": {"teamId": "KT"},
            }
        ],
        team_id="LG",
    )

    assert plan == [{"teamId": "LG", "kind": "records_check"}]


def test_smart_daily_plan_uses_off_day_when_league_has_no_games() -> None:
    plan = baseball_info.build_smart_daily_plan(games=[], team_id="LG")

    assert plan == [{"teamId": "LG", "kind": "off_day"}]


def test_baseball_info_scheduler_smart_daily_sends_team_specific_plan() -> None:
    captured = []

    class FakeScoreboardService:
        def get_home_scoreboard(self, date):
            return {
                "date": date,
                "games": [
                    {
                        "gameId": "20260630LTOB0",
                        "status": "SCHEDULED",
                        "startTime": "18:30",
                        "stadium": "잠실",
                        "away": {"teamId": "LT", "shortName": "롯데"},
                        "home": {"teamId": "OB", "shortName": "두산"},
                    }
                ],
            }

    class FakePushService:
        def send_baseball_info(self, **kwargs):
            captured.append(kwargs)
            return {"sent": False, "dryRun": kwargs["dry_run"], "messages": []}

    result = baseball_info.send_smart_daily(
        date="2026-06-22",
        team_id="OB",
        now_time="16:00",
        dry_run=True,
        scoreboard_service=FakeScoreboardService(),
        push_service=FakePushService(),
    )

    assert result["sent"] is False
    assert result["dryRun"] is True
    assert result["mode"] == "smart_daily"
    assert captured == [
        {
            "kind": "lineup_day",
            "date": "2026-06-22",
            "topic": None,
            "team_id": "OB",
            "game_id": "20260630LTOB0",
            "matchup": "롯데 vs 두산",
            "start_time": "18:30",
            "stadium": "잠실",
            "dry_run": True,
        }
    ]
