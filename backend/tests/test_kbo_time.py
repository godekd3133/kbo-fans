from datetime import date, datetime, timezone

from fastapi.testclient import TestClient

from kbo_fans_backend.api.routes import home, scoreboard
from kbo_fans_backend.main import app
from kbo_fans_backend.services import boxscore as boxscore_module
from kbo_fans_backend.services import standings as standings_module
from kbo_fans_backend.services.boxscore import BoxscoreService
from kbo_fans_backend.services.standings import StandingsService
from kbo_fans_backend.storage import JsonSnapshotStore
from kbo_fans_backend.utils.kbo_time import current_kbo_date, current_kbo_year


def test_current_kbo_date_uses_seoul_day_at_utc_boundary() -> None:
    utc_now = datetime(2026, 7, 12, 15, 30, tzinfo=timezone.utc)

    assert current_kbo_date(utc_now) == date(2026, 7, 13)


def test_current_kbo_year_uses_seoul_year_at_utc_boundary() -> None:
    utc_now = datetime(2026, 12, 31, 15, 30, tzinfo=timezone.utc)

    assert current_kbo_year(utc_now) == 2027


def test_home_route_defaults_to_current_kbo_date(monkeypatch) -> None:
    captured = {}
    monkeypatch.setattr(home, "current_kbo_date_string", lambda: "2026-07-13")
    monkeypatch.setattr(
        home.service,
        "get_home",
        lambda target_date, my_team: captured.update(
            {"date": target_date, "myTeam": my_team}
        )
        or {"date": target_date},
    )

    response = TestClient(app).get("/api/home")

    assert response.status_code == 200
    assert captured == {"date": "2026-07-13", "myTeam": None}


def test_scoreboard_routes_default_to_current_kbo_date(monkeypatch) -> None:
    captured = []
    monkeypatch.setattr(scoreboard, "current_kbo_date_string", lambda: "2026-07-13")
    monkeypatch.setattr(
        scoreboard.service,
        "get_scoreboard",
        lambda target_date, force_refresh=False: captured.append(target_date)
        or {"date": target_date},
    )
    monkeypatch.setattr(
        scoreboard.service,
        "get_home_scoreboard",
        lambda target_date, force_refresh=False: captured.append(target_date)
        or {"date": target_date},
    )
    monkeypatch.setattr(
        scoreboard.service,
        "get_compact_scoreboard",
        lambda target_date, my_team=None: captured.append(target_date)
        or {"date": target_date, "myTeam": my_team},
    )
    client = TestClient(app)

    responses = [
        client.get("/api/scoreboard"),
        client.get("/api/scoreboard/home"),
        client.get("/api/scoreboard/compact"),
    ]

    assert all(response.status_code == 200 for response in responses)
    assert captured == ["2026-07-13", "2026-07-13", "2026-07-13"]


def test_scoreboard_routes_forward_force_refresh(monkeypatch) -> None:
    captured = []
    monkeypatch.setattr(
        scoreboard.service,
        "get_scoreboard",
        lambda target_date, force_refresh=False: captured.append(
            ("scoreboard", target_date, force_refresh)
        )
        or {"date": target_date},
    )
    monkeypatch.setattr(
        scoreboard.service,
        "get_home_scoreboard",
        lambda target_date, force_refresh=False: captured.append(
            ("home", target_date, force_refresh)
        )
        or {"date": target_date},
    )
    client = TestClient(app)

    responses = [
        client.get("/api/scoreboard?date=2026-07-13&forceRefresh=true"),
        client.get("/api/scoreboard/home?date=2026-07-13&forceRefresh=true"),
    ]

    assert all(response.status_code == 200 for response in responses)
    assert captured == [
        ("scoreboard", "2026-07-13", True),
        ("home", "2026-07-13", True),
    ]


def test_standings_treats_previous_utc_year_as_historical_after_kbo_new_year(
    monkeypatch,
    tmp_path,
) -> None:
    class FailingCrawler:
        def get_standings(self, season: int):
            raise AssertionError("historical snapshot should be used before crawling")

    monkeypatch.setattr(standings_module, "current_kbo_year", lambda: 2027)
    store = JsonSnapshotStore(base_dir=str(tmp_path))
    store.save(
        "standings_latest",
        "2026",
        {"season": 2026, "standings": [{"rank": 1, "teamId": "LG"}]},
    )
    service = StandingsService(crawler=FailingCrawler(), snapshot_store=store)

    payload = service.get_standings(2026)

    assert payload["season"] == 2026
    assert payload["standings"][0]["teamId"] == "LG"


def test_boxscore_treats_previous_utc_day_as_historical_after_kbo_midnight(
    monkeypatch,
    tmp_path,
) -> None:
    class FailingCrawler:
        def get_boxscore(self, game_id: str):
            raise AssertionError("historical snapshot should be used before crawling")

    class EmptyPlayerStatsService:
        def get_team_players(self, team_id: str, season: int):
            return {"teamId": team_id, "season": season, "players": []}

    game_id = "20261231KTLG0"
    monkeypatch.setattr(boxscore_module, "current_kbo_date", lambda: date(2027, 1, 1))
    store = JsonSnapshotStore(base_dir=str(tmp_path))
    store.save(
        "boxscore",
        game_id,
        {
            "gameId": game_id,
            "away": {"teamId": "KT", "batters": [{"name": "A"}], "pitchers": []},
            "home": {"teamId": "LG", "batters": [], "pitchers": [{"name": "P"}]},
        },
    )
    service = BoxscoreService(
        crawler=FailingCrawler(),
        player_stats_service=EmptyPlayerStatsService(),
        snapshot_store=store,
    )

    payload = service.get_boxscore(game_id)

    assert payload["gameId"] == game_id
    assert payload["away"]["batters"][0]["name"] == "A"
