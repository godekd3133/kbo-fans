from fastapi.testclient import TestClient

from kbo_fans_backend.api.routes import games, home, players, push, schedule, scoreboard, teams
from kbo_fans_backend.main import app

client = TestClient(app)


def test_home_rejects_unknown_my_team_before_service(monkeypatch) -> None:
    monkeypatch.setattr(
        home.service,
        "get_home",
        lambda *args, **kwargs: (_ for _ in ()).throw(AssertionError("home service must not run")),
    )

    response = client.get("/api/home", params={"myTeam": "ZZ"})

    assert response.status_code == 422


def test_home_normalizes_lowercase_my_team_before_service(monkeypatch) -> None:
    captured = {}

    def get_home(target_date: str, my_team: str):
        captured.update({"date": target_date, "myTeam": my_team})
        return captured

    monkeypatch.setattr(home.service, "get_home", get_home)

    response = client.get(
        "/api/home",
        params={"date": "2026-04-01", "myTeam": "lg"},
    )

    assert response.status_code == 200
    assert captured == {"date": "2026-04-01", "myTeam": "LG"}


def test_compact_scoreboard_rejects_unknown_my_team_before_service(monkeypatch) -> None:
    monkeypatch.setattr(
        scoreboard.service,
        "get_compact_scoreboard",
        lambda *args, **kwargs: (_ for _ in ()).throw(
            AssertionError("scoreboard service must not run")
        ),
    )

    response = client.get("/api/scoreboard/compact", params={"myTeam": "ZZ"})

    assert response.status_code == 422


def test_compact_scoreboard_normalizes_lowercase_my_team(monkeypatch) -> None:
    captured = {}

    def get_compact_scoreboard(target_date: str, my_team: str):
        captured.update({"date": target_date, "myTeam": my_team})
        return captured

    monkeypatch.setattr(
        scoreboard.service,
        "get_compact_scoreboard",
        get_compact_scoreboard,
    )

    response = client.get(
        "/api/scoreboard/compact",
        params={"date": "2026-04-01", "myTeam": "lg"},
    )

    assert response.status_code == 200
    assert captured == {"date": "2026-04-01", "myTeam": "LG"}


def test_schedule_rejects_invalid_month_before_crawler(monkeypatch) -> None:
    monkeypatch.setattr(
        schedule.service,
        "get_month_schedule",
        lambda month: (_ for _ in ()).throw(AssertionError("crawler must not run")),
    )

    response = client.get("/api/schedule", params={"month": "2026-13"})

    assert response.status_code == 422


def test_schedule_rejects_out_of_supported_year_range_before_crawler(monkeypatch) -> None:
    monkeypatch.setattr(
        schedule.service,
        "get_month_schedule",
        lambda month: (_ for _ in ()).throw(AssertionError("crawler must not run")),
    )

    for month in ("0001-01", "9999-12"):
        response = client.get("/api/schedule", params={"month": month})
        assert response.status_code == 422


def test_game_rejects_malformed_id_before_scoreboard_lookup(monkeypatch) -> None:
    monkeypatch.setattr(
        games.scoreboard_service,
        "get_game",
        lambda *args, **kwargs: (_ for _ in ()).throw(AssertionError("scoreboard must not run")),
    )

    for game_id in ("bad!", "abcdefgh", "20261301KTLG0", "20260604ZZLG0"):
        response = client.get(f"/api/game/{game_id}")
        assert response.status_code == 422


def test_team_routes_reject_unbounded_identifiers_and_seasons(monkeypatch) -> None:
    monkeypatch.setattr(
        teams.service,
        "get_team_players",
        lambda *args, **kwargs: (_ for _ in ()).throw(AssertionError("crawler must not run")),
    )

    response = client.get("/api/team/TOOLONG/players", params={"season": 9999})

    assert response.status_code == 422


def test_team_routes_reject_unknown_team_before_crawler(monkeypatch) -> None:
    monkeypatch.setattr(
        teams.team_stats_service,
        "get_team_stats",
        lambda *args, **kwargs: (_ for _ in ()).throw(
            AssertionError("team stats crawler must not run")
        ),
    )

    response = client.get("/api/team/ZZ/stats", params={"season": 2026})

    assert response.status_code == 422


def test_player_route_rejects_unknown_player_type_before_crawler(monkeypatch) -> None:
    monkeypatch.setattr(
        players.service,
        "get_player_detail",
        lambda *args, **kwargs: (_ for _ in ()).throw(
            AssertionError("player crawler must not run")
        ),
    )

    response = client.get(
        "/api/player/12345",
        params={"season": 2025, "player_type": "catcher"},
    )

    assert response.status_code == 422


def test_current_data_routes_reject_invalid_civil_dates_before_services(monkeypatch) -> None:
    monkeypatch.setattr(
        scoreboard.service,
        "get_scoreboard",
        lambda *args, **kwargs: (_ for _ in ()).throw(
            AssertionError("scoreboard service must not run")
        ),
    )
    monkeypatch.setattr(
        home.service,
        "get_home",
        lambda *args, **kwargs: (_ for _ in ()).throw(AssertionError("home service must not run")),
    )

    for path, date_value in (
        ("/api/scoreboard", "not-a-date"),
        ("/api/scoreboard/home", "2026-02-30"),
        ("/api/scoreboard/compact", "2026-99-99"),
        ("/api/home", "2026-99-99"),
        ("/api/scoreboard", "0001-01-01"),
        ("/api/scoreboard/home", "9999-12-31"),
        ("/api/scoreboard/compact", "0001-01-01"),
        ("/api/home", "9999-12-31"),
    ):
        response = client.get(path, params={"date": date_value})
        assert response.status_code == 422


def test_live_activity_sync_rejects_invalid_civil_date_before_sync(monkeypatch) -> None:
    monkeypatch.setattr(push, "_ensure_sync_allowed", lambda *args, **kwargs: None)
    monkeypatch.setattr(
        push.live_activity_sync_service,
        "sync_date",
        lambda *args, **kwargs: (_ for _ in ()).throw(AssertionError("sync service must not run")),
    )

    response = client.post(
        "/api/push/live-activity/sync-scoreboard",
        params={"date": "2026-00-10"},
    )

    assert response.status_code == 422

    for date_value in ("0001-01-01", "9999-12-31"):
        response = client.post(
            "/api/push/live-activity/sync-scoreboard",
            params={"date": date_value},
        )
        assert response.status_code == 422
