import pytest
from fastapi.testclient import TestClient

from kbo_fans_backend.api.routes import (
    games,
    home,
    records,
    schedule,
    scoreboard,
    standings,
)
from kbo_fans_backend.main import app
from kbo_fans_backend.services.home import HomeService


class _EmptyScoreboardService:
    def get_home_scoreboard(self, date: str):
        return {"date": date, "games": []}


class _FailingScheduleService:
    def get_month_schedule(self, month: str):
        raise RuntimeError("schedule unavailable")


class _EmptyScheduleService:
    def get_month_schedule(self, month: str):
        return {"month": month, "days": []}


class _FailingStandingsService:
    def get_standings(self, season: int):
        raise RuntimeError("standings unavailable")


class _EmptyStandingsService:
    def get_standings(self, season: int):
        return {"season": season, "standings": []}


class _FailingRecordsOverviewService:
    def get_overview(self, season: int):
        raise RuntimeError("records unavailable")


class _EmptyRecordsOverviewService:
    def get_overview(self, season: int):
        return {"season": season, "leaders": {"hr": []}, "featured": {}}


def test_current_data_routes_share_runtime_services() -> None:
    assert home.service.scoreboard_service is scoreboard.service
    assert home.service.schedule_service is schedule.service
    assert home.service.standings_service is standings.service
    assert home.service.records_overview_service is records.service
    assert games.scoreboard_service is scoreboard.service
    assert games.schedule_service is schedule.service
    assert games.relay_service.scoreboard_service is scoreboard.service
    assert games.boxscore_service.schedule_service is schedule.service


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
            "kboBrief": {
                "title": "오늘의 KBO 요약",
                "subtitle": "1경기 종료 · 기록과 흐름을 빠르게 확인",
                "items": [
                    {
                        "type": "game_flow",
                        "eyebrow": "1점 승부",
                        "title": "KIA 5 : 4 LG",
                        "subtitle": "경기종료 · 잠실",
                        "route": "/game/20260331HTLG0",
                        "gameId": "20260331HTLG0",
                        "teamIds": ["HT", "LG"],
                    }
                ],
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
    assert body["data"]["kboBrief"]["items"][0]["eyebrow"] == "1점 승부"
    assert body["data"]["quickItems"][0]["route"] == "/standings"


def test_current_home_does_not_mask_schedule_failure() -> None:
    service = HomeService(
        scoreboard_service=_EmptyScoreboardService(),
        schedule_service=_FailingScheduleService(),
        standings_service=_EmptyStandingsService(),
        records_overview_service=_EmptyRecordsOverviewService(),
    )

    with pytest.raises(RuntimeError, match="schedule unavailable"):
        service.get_home("2999-01-01", my_team="LG")


def test_current_home_does_not_mask_standings_failure() -> None:
    service = HomeService(
        scoreboard_service=_EmptyScoreboardService(),
        schedule_service=_EmptyScheduleService(),
        standings_service=_FailingStandingsService(),
        records_overview_service=_EmptyRecordsOverviewService(),
    )

    with pytest.raises(RuntimeError, match="standings unavailable"):
        service.get_home("2999-01-01", my_team="LG")


def test_current_home_does_not_mask_records_overview_failure() -> None:
    service = HomeService(
        scoreboard_service=_EmptyScoreboardService(),
        schedule_service=_EmptyScheduleService(),
        standings_service=_EmptyStandingsService(),
        records_overview_service=_FailingRecordsOverviewService(),
    )

    with pytest.raises(RuntimeError, match="records unavailable"):
        service.get_home("2999-01-01", my_team="LG")


def test_historical_home_keeps_partial_section_fallback() -> None:
    service = HomeService(
        scoreboard_service=_EmptyScoreboardService(),
        schedule_service=_FailingScheduleService(),
        standings_service=_FailingStandingsService(),
        records_overview_service=_FailingRecordsOverviewService(),
    )

    payload = service.get_home("2001-01-01", my_team="LG")

    assert payload["date"] == "2001-01-01"
    assert payload["myTeamBrief"]["recentGamesCount"] == 0
    assert payload["kboBrief"]["items"][0]["type"] == "offday"


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


def test_kbo_brief_summarizes_final_game_without_fake_records() -> None:
    service = HomeService.__new__(HomeService)

    brief = service._build_kbo_brief(
        today="2026-05-20",
        my_team="LG",
        games=[
            {
                "gameId": "20260520HTLG0",
                "status": "FINAL",
                "inning": "경기종료",
                "stadium": "잠실",
                "away": {
                    "teamId": "HT",
                    "shortName": "KIA",
                    "score": 5,
                    "hits": 11,
                },
                "home": {
                    "teamId": "LG",
                    "shortName": "LG",
                    "score": 4,
                    "hits": 9,
                },
            }
        ],
        standings=[],
        overview={"leaders": {"hr": []}},
    )

    assert brief["title"] == "오늘의 KBO 요약"
    assert brief["items"][0]["eyebrow"] == "1점 승부"
    assert brief["items"][0]["route"] == "/game/20260520HTLG0"
    assert all("최초" not in item["title"] for item in brief["items"])


def test_kbo_brief_deprioritizes_my_team_when_league_items_exist() -> None:
    service = HomeService.__new__(HomeService)

    brief = service._build_kbo_brief(
        today="2026-05-20",
        my_team="LG",
        games=[
            {
                "gameId": "20260520HTLG0",
                "status": "LIVE",
                "inning": "8회말",
                "stadium": "잠실",
                "away": {"teamId": "HT", "shortName": "KIA", "score": 3},
                "home": {"teamId": "LG", "shortName": "LG", "score": 3},
            },
            {
                "gameId": "20260520NCOB0",
                "status": "LIVE",
                "inning": "7회초",
                "stadium": "창원",
                "away": {"teamId": "NC", "shortName": "NC", "score": 9},
                "home": {"teamId": "OB", "shortName": "두산", "score": 7},
            },
        ],
        standings=[],
        overview={"leaders": {"hr": []}},
    )

    assert "LG" not in brief["items"][0]["teamIds"]
    assert brief["items"][0]["route"] == "/game/20260520NCOB0"


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
            },
        ],
        standings=[],
        today="2026-05-20",
    )

    assert brief is not None
    assert brief["recentGamesCount"] == 1
    assert brief["recentWins"] == 1
    assert brief["recentDraws"] == 0
    assert brief["recentSummaries"] == [
        {
            "gameId": "20260518OBLG0",
            "result": "승",
            "opponentName": "두산",
            "score": "5:2",
        }
    ]


def test_kbo_brief_builds_scheduled_game_and_record_radar_items() -> None:
    service = HomeService.__new__(HomeService)

    brief = service._build_kbo_brief(
        today="2026-05-20",
        my_team="LG",
        games=[
            {
                "gameId": "20260520OBLG0",
                "status": "SCHEDULED",
                "startTime": "18:30",
                "stadium": "잠실",
                "away": {"teamId": "OB", "shortName": "두산", "score": 0},
                "home": {"teamId": "LG", "shortName": "LG", "score": 0},
            }
        ],
        standings=[
            {"rank": 1, "teamId": "LG", "teamName": "LG 트윈스", "gb": "0"},
            {"rank": 2, "teamId": "HT", "teamName": "KIA 타이거즈", "gb": "1.5"},
        ],
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
    )

    assert brief["title"] == "오늘의 KBO 관전 포인트"
    assert brief["items"][0]["type"] == "record_radar"
    assert brief["items"][0]["route"] == "/records/player/52605?season=2026"
    assert any(item["title"] == "두산 vs LG" for item in brief["items"])
