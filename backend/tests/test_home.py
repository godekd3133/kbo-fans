from fastapi.testclient import TestClient

from kbo_fans_backend.api.routes import home
from kbo_fans_backend.main import app


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
