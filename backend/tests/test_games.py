from fastapi.testclient import TestClient

from kbo_fans_backend.api.routes import games
from kbo_fans_backend.main import app


def test_get_game_returns_game_payload(monkeypatch) -> None:
    expected_game = {
        "gameId": "20260330KTLG0",
        "status": "FINAL",
        "inning": "경기종료",
        "stadium": "잠실",
        "startTime": "18:30",
        "away": {
            "teamId": "KT",
            "teamName": "KT 위즈",
            "shortName": "KT",
            "score": 5,
            "scores": [0, 1, 0, 0, 2, 0, 0, 1, 1],
            "hits": 10,
            "errors": 0,
            "balls": 4,
        },
        "home": {
            "teamId": "LG",
            "teamName": "LG 트윈스",
            "shortName": "LG",
            "score": 3,
            "scores": [0, 0, 0, 1, 0, 0, 2, 0, 0],
            "hits": 8,
            "errors": 1,
            "balls": 2,
        },
    }
    monkeypatch.setattr(games.scoreboard_service, "get_game", lambda game_id: expected_game)
    client = TestClient(app)

    response = client.get("/api/game/20260330KTLG0")

    assert response.status_code == 200
    body = response.json()
    assert body["success"] is True
    assert body["data"]["game"] == expected_game


def test_get_game_returns_404_when_missing(monkeypatch) -> None:
    monkeypatch.setattr(games.scoreboard_service, "get_game", lambda game_id: None)
    client = TestClient(app)

    response = client.get("/api/game/20260330KTLG0")

    assert response.status_code == 404
    body = response.json()
    assert body["detail"] == "해당 경기를 찾을 수 없습니다"


def test_get_relay_returns_empty_payload() -> None:
    client = TestClient(app)

    response = client.get("/api/game/20260330KTLG0/relay")

    assert response.status_code == 200
    body = response.json()
    assert body["success"] is True
    assert body["data"]["gameId"] == "20260330KTLG0"
    assert "currentAtBat" in body["data"]
    assert "relayItems" in body["data"]
