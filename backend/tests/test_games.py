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
    monkeypatch.setattr(
        games.scoreboard_service,
        "get_game",
        lambda game_id, force_refresh=False: expected_game,
    )
    monkeypatch.setattr(
        games.schedule_service,
        "get_schedule_game",
        lambda game_id: (_ for _ in ()).throw(AssertionError("schedule should not be called")),
    )
    client = TestClient(app)

    response = client.get("/api/game/20260330KTLG0")

    assert response.status_code == 200
    body = response.json()
    assert body["success"] is True
    assert body["data"]["game"] == expected_game


def test_get_game_forwards_force_refresh(monkeypatch) -> None:
    captured = {}
    expected_game = {
        "gameId": "20260330KTLG0",
        "status": "LIVE",
        "away": {"teamId": "KT", "score": 1},
        "home": {"teamId": "LG", "score": 2},
    }
    monkeypatch.setattr(
        games.scoreboard_service,
        "get_game",
        lambda game_id, force_refresh=False: captured.update(
            {"gameId": game_id, "forceRefresh": force_refresh}
        )
        or expected_game,
    )
    client = TestClient(app)

    response = client.get("/api/game/20260330KTLG0?forceRefresh=true")

    assert response.status_code == 200
    assert captured == {
        "gameId": "20260330KTLG0",
        "forceRefresh": True,
    }


def test_get_game_returns_404_when_missing(monkeypatch) -> None:
    monkeypatch.setattr(
        games.scoreboard_service,
        "get_game",
        lambda game_id, force_refresh=False: None,
    )
    client = TestClient(app)

    response = client.get("/api/game/20260330KTLG0")

    assert response.status_code == 404
    body = response.json()
    assert body["detail"] == "해당 경기를 찾을 수 없습니다"


def test_get_highlights_returns_youtube_search_fallback_when_video_search_is_empty(
    monkeypatch,
) -> None:
    monkeypatch.setattr(
        games.schedule_service,
        "get_schedule_game",
        lambda game_id: {
            "gameId": game_id,
            "status": "FINAL",
            "awayName": "KT 위즈",
            "homeName": "LG 트윈스",
        },
    )
    monkeypatch.setattr(
        games.youtube_highlight_service,
        "fetch_highlights",
        lambda **_: [],
    )
    client = TestClient(app)

    response = client.get("/api/game/20260629KTLG0/highlights")

    assert response.status_code == 200
    body = response.json()
    videos = body["data"]["highlightInfo"]["youtubeVideos"]
    assert videos[0]["source"] == "youtube_search_fallback"
    assert videos[0]["videoId"] == ""
    assert "youtube.com/results" in videos[0]["videoUrl"]


def test_get_relay_returns_empty_payload(monkeypatch) -> None:
    expected = {
        "gameId": "20260330KTLG0",
        "currentAtBat": None,
        "relayItems": [],
    }
    monkeypatch.setattr(
        games.relay_service,
        "get_relay",
        lambda game_id, after=None, force_refresh=False: expected,
    )
    client = TestClient(app)

    response = client.get("/api/game/20260330KTLG0/relay")

    assert response.status_code == 200
    body = response.json()
    assert body["success"] is True
    assert body["data"] == expected


def test_get_relay_forwards_force_refresh(monkeypatch) -> None:
    captured = {}
    monkeypatch.setattr(
        games.relay_service,
        "get_relay",
        lambda game_id, after=None, force_refresh=False: captured.update(
            {
                "gameId": game_id,
                "after": after,
                "forceRefresh": force_refresh,
            }
        )
        or {
            "gameId": game_id,
            "currentAtBat": None,
            "relayItems": [],
        },
    )
    client = TestClient(app)

    response = client.get(
        "/api/game/20260330KTLG0/relay?after=10&forceRefresh=true"
    )

    assert response.status_code == 200
    assert captured == {
        "gameId": "20260330KTLG0",
        "after": 10,
        "forceRefresh": True,
    }


def test_get_boxscore_returns_empty_payload_when_crawler_has_no_data(monkeypatch) -> None:
    monkeypatch.setattr(
        games.boxscore_service,
        "get_boxscore",
        lambda game_id: {
            "gameId": game_id,
            "away": {
                "teamId": "KT",
                "batters": [],
                "pitchers": [],
                "totals": {
                    "batting": {"atBats": 0, "runs": 0, "hits": 0, "rbi": 0},
                    "pitching": {
                        "innings": "0.0",
                        "hits": 0,
                        "strikeouts": 0,
                        "walks": 0,
                        "earnedRuns": 0,
                    },
                },
            },
            "home": {
                "teamId": "LG",
                "batters": [],
                "pitchers": [],
                "totals": {
                    "batting": {"atBats": 0, "runs": 0, "hits": 0, "rbi": 0},
                    "pitching": {
                        "innings": "0.0",
                        "hits": 0,
                        "strikeouts": 0,
                        "walks": 0,
                        "earnedRuns": 0,
                    },
                },
            },
        },
    )
    client = TestClient(app)

    response = client.get("/api/game/20260330KTLG0/boxscore")

    assert response.status_code == 200
    body = response.json()
    assert body["success"] is True
    assert body["data"]["away"]["batters"] == []
    assert body["data"]["home"]["pitchers"] == []
