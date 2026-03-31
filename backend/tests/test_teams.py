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


def test_get_team_records_returns_partial_payload_when_players_fail(monkeypatch) -> None:
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

    client = TestClient(app)

    response = client.get("/api/team/LG/records", params={"season": 2026})

    assert response.status_code == 200
    body = response.json()
    assert body["success"] is True
    assert body["data"]["players"] == []
    assert body["data"]["teamStats"] == expected_stats
