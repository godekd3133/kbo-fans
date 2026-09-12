import threading

from fastapi.testclient import TestClient

from kbo_fans_backend.api.routes import teams
from kbo_fans_backend.main import app


def test_get_team_records_returns_players_and_stats(monkeypatch) -> None:
    expected_players = [{"id": "1001", "name": "홍길동"}]
    expected_stats = {
        "teamId": "LG",
        "season": 2026,
        "hitting": {"AVG": ".280"},
        "pitching": {"ERA": "3.50"},
    }

    monkeypatch.setattr(
        teams.service,
        "get_team_players",
        lambda team_id, season: {
            "teamId": team_id,
            "season": season,
            "players": expected_players,
        },
    )
    monkeypatch.setattr(
        teams.team_stats_service,
        "get_team_stats",
        lambda team_id, season: expected_stats,
    )

    client = TestClient(app)

    response = client.get("/api/team/LG/records", params={"season": 2026})

    assert response.status_code == 200
    body = response.json()
    assert body["success"] is True
    assert body["data"]["players"] == expected_players
    assert body["data"]["teamStats"] == expected_stats


def test_get_team_records_propagates_player_failure(monkeypatch) -> None:
    expected_stats = {
        "teamId": "LG",
        "season": 2026,
        "hitting": {"AVG": ".280"},
        "pitching": {"ERA": "3.50"},
    }

    def _raise_players(team_id, season):
        raise RuntimeError("timeout")

    monkeypatch.setattr(teams.service, "get_team_players", _raise_players)
    monkeypatch.setattr(
        teams.team_stats_service,
        "get_team_stats",
        lambda team_id, season: expected_stats,
    )

    client = TestClient(app, raise_server_exceptions=False)

    response = client.get("/api/team/LG/records", params={"season": 2026})

    assert response.status_code == 500


def test_get_team_records_player_failure_does_not_wait_for_stats(monkeypatch) -> None:
    barrier = threading.Barrier(2)
    stats_started = threading.Event()
    stats_release = threading.Event()
    errors = []

    def fail_players(team_id, season):
        barrier.wait(timeout=0.5)
        raise RuntimeError("players unavailable")

    def block_stats(team_id, season):
        barrier.wait(timeout=0.5)
        stats_started.set()
        stats_release.wait(timeout=2)
        return {"teamId": team_id, "season": season}

    monkeypatch.setattr(teams.service, "get_team_players", fail_players)
    monkeypatch.setattr(teams.team_stats_service, "get_team_stats", block_stats)

    def request() -> None:
        try:
            teams.get_team_records("LG", 2026)
        except BaseException as error:
            errors.append(error)

    thread = threading.Thread(target=request)
    thread.start()
    assert stats_started.wait(timeout=1)
    try:
        thread.join(timeout=0.2)
        assert not thread.is_alive()
    finally:
        stats_release.set()
        thread.join(timeout=2)

    assert len(errors) == 1
    assert str(errors[0]) == "players unavailable"


def test_get_team_records_stats_failure_does_not_wait_for_players(monkeypatch) -> None:
    barrier = threading.Barrier(2)
    players_started = threading.Event()
    players_release = threading.Event()
    errors = []

    def block_players(team_id, season):
        barrier.wait(timeout=0.5)
        players_started.set()
        assert players_release.wait(timeout=2)
        return {"teamId": team_id, "season": season, "players": []}

    def fail_stats(team_id, season):
        barrier.wait(timeout=0.5)
        raise RuntimeError("stats unavailable")

    monkeypatch.setattr(teams.service, "get_team_players", block_players)
    monkeypatch.setattr(teams.team_stats_service, "get_team_stats", fail_stats)

    def request() -> None:
        try:
            teams.get_team_records("LG", 2026)
        except BaseException as error:
            errors.append(error)

    thread = threading.Thread(target=request)
    thread.start()
    assert players_started.wait(timeout=1)
    try:
        thread.join(timeout=0.2)
        assert not thread.is_alive()
    finally:
        players_release.set()
        thread.join(timeout=2)

    assert len(errors) == 1
    assert str(errors[0]) == "stats unavailable"
