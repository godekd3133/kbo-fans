from fastapi.testclient import TestClient

from kbo_fans_backend.api.routes import home
from kbo_fans_backend.main import app
from kbo_fans_backend.services.home import HomeService


def test_get_home_returns_aggregate_payload(monkeypatch) -> None:
    monkeypatch.setattr(
        home.service,
        "get_home",
        lambda date, my_team: {
            "date": date,
            "myTeam": my_team,
            "myTeamBrief": {
                "teamId": "LG",
                "teamLabel": "LG 트윈스",
                "standing": {"rank": 1, "teamId": "LG", "teamName": "LG 트윈스"},
                "todayGameId": "20260331HTLG0",
                "nextGame": None,
                "recentWins": 2,
                "recentLosses": 0,
                "recentDraws": 0,
                "recentGamesCount": 2,
                "recentSummaries": [],
            },
            "quickItems": [
                {
                    "eyebrow": "마이팀 순위",
                    "title": "1위 · LG 트윈스",
                    "subtitle": "2승 0패",
                    "route": "/standings",
                }
            ],
            "meta": {"generatedAt": 0},
        },
    )
    client = TestClient(app)

    response = client.get("/api/home", params={"date": "2026-03-31", "myTeam": "LG"})

    assert response.status_code == 200
    body = response.json()
    assert body["success"] is True
    assert body["data"]["date"] == "2026-03-31"
    assert body["data"]["myTeam"] == "LG"
    assert body["data"]["quickItems"][0]["route"] == "/standings"


def test_home_run_quick_item_uses_player_image_and_detail_route() -> None:
    service = HomeService.__new__(HomeService)

    items = service._build_quick_items(
        my_team_brief=None,
        overview={
            "leaders": {
                "hr": [
                    {
                        "playerId": "52605",
                        "name": "김도영",
                        "teamId": "HT",
                        "value": "13",
                    }
                ]
            }
        },
        games=[],
        season=2026,
    )

    assert items[0]["title"] == "김도영 13개"
    assert items[0]["route"] == "/records/player/52605?season=2026"
    assert items[0]["imageUrl"].endswith("/2026/52605.jpg")


def test_my_team_brief_excludes_scheduled_zero_score_from_recent_results() -> None:
    service = HomeService.__new__(HomeService)

    brief = service._build_my_team_brief(
        my_team="LG",
        games=[],
        schedule_days=[
            {
                "date": "2026-05-18",
                "games": [
                    {
                        "gameId": "20260518OBLG0",
                        "awayId": "OB",
                        "awayName": "두산",
                        "awayScore": 2,
                        "homeId": "LG",
                        "homeName": "LG",
                        "homeScore": 5,
                        "stadium": "잠실",
                        "status": "FINAL",
                    },
                ],
            },
            {
                "date": "2026-05-20",
                "games": [
                    {
                        "gameId": "20260520OBLG0",
                        "awayId": "OB",
                        "awayName": "두산",
                        "awayScore": 0,
                        "homeId": "LG",
                        "homeName": "LG",
                        "homeScore": 0,
                        "stadium": "잠실",
                        "status": "SCHEDULED",
                    },
                ],
            }
        ],
        standings=[],
        today="2026-05-20",
    )

    assert brief is not None
    assert brief["recentGamesCount"] == 1
    assert brief["recentWins"] == 1
    assert brief["recentDraws"] == 0
    assert brief["recentSummaries"] == [
        {"result": "승", "opponentName": "두산", "score": "5:2"}
    ]
