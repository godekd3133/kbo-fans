import threading
import time
from concurrent.futures import ThreadPoolExecutor
from datetime import date as date_type

import pytest
from fastapi.testclient import TestClient

from kbo_fans_backend.api.routes import (
    games,
    home,
    players,
    records,
    schedule,
    scoreboard,
    standings,
    teams,
)
from kbo_fans_backend.api.runtime_services import team_stats_service
from kbo_fans_backend.main import app
from kbo_fans_backend.services.home import HomeService
from kbo_fans_backend.utils.resilience import UpstreamDeadlineExceeded


class _EmptyScoreboardService:
    def get_home_scoreboard(self, date: str):
        return {"date": date, "games": []}


class _BlockingScoreboardService:
    def __init__(self) -> None:
        self.calls = 0
        self.started = threading.Event()
        self.release = threading.Event()

    def get_home_scoreboard(self, date: str):
        self.calls += 1
        self.started.set()
        assert self.release.wait(timeout=2)
        return {"date": date, "games": []}


class _FailingScheduleService:
    def get_month_schedule(self, month: str):
        raise RuntimeError("schedule unavailable")


class _EmptyScheduleService:
    def get_month_schedule(self, month: str):
        return {"month": month, "days": []}


class _MonthBoundaryScheduleService:
    def __init__(self) -> None:
        self.requested_months = []

    def get_month_schedule(self, month: str):
        self.requested_months.append(month)
        if month == "2026-06":
            return {
                "month": month,
                "days": [
                    {
                        "date": "2026-06-30",
                        "games": [
                            {
                                "gameId": "20260630LTOB0",
                                "awayId": "LT",
                                "awayName": "롯데",
                                "awayScore": 0,
                                "homeId": "OB",
                                "homeName": "두산",
                                "homeScore": 5,
                                "stadium": "잠실",
                                "status": "FINAL",
                            }
                        ],
                    }
                ],
            }
        return {
            "month": month,
            "days": [
                {
                    "date": "2026-07-01",
                    "games": [
                        {
                            "gameId": "20260701LTOB0",
                            "awayId": "LT",
                            "awayName": "롯데",
                            "awayScore": 0,
                            "homeId": "OB",
                            "homeName": "두산",
                            "homeScore": 0,
                            "stadium": "잠실",
                            "status": "SCHEDULED",
                        }
                    ],
                }
            ],
        }


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


class _BlockingRecordsOverviewService:
    def __init__(self) -> None:
        self.started = threading.Event()
        self.release = threading.Event()

    def get_overview(self, season: int):
        self.started.set()
        assert self.release.wait(timeout=2)
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
    assert teams.service is games.boxscore_service.player_stats_service
    assert players.service is teams.service
    assert teams.team_stats_service is team_stats_service


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


def test_current_scheduled_home_uses_short_cache_instead_of_stable_cache(monkeypatch) -> None:
    monkeypatch.setattr(
        "kbo_fans_backend.services.home.current_kbo_date",
        lambda: date_type(2026, 8, 9),
    )
    service = HomeService(
        scoreboard_service=_EmptyScoreboardService(),
        schedule_service=_EmptyScheduleService(),
        standings_service=_EmptyStandingsService(),
        records_overview_service=_EmptyRecordsOverviewService(),
    )

    payload = service.get_home("2026-08-09", my_team="LG")
    cache_key = "2026-08-09|LG"

    assert service._current_cache.ttl_seconds == 30
    assert service._current_cache.get(cache_key) == payload
    assert service._stable_cache.get(cache_key) is None


def test_concurrent_home_requests_share_one_aggregate_load() -> None:
    scoreboard = _BlockingScoreboardService()
    service = HomeService(
        scoreboard_service=scoreboard,
        schedule_service=_EmptyScheduleService(),
        standings_service=_EmptyStandingsService(),
        records_overview_service=_EmptyRecordsOverviewService(),
    )

    with ThreadPoolExecutor(max_workers=2) as executor:
        first = executor.submit(service.get_home, "2099-01-01")
        assert scoreboard.started.wait(timeout=2)
        second = executor.submit(service.get_home, "2099-01-01")
        time.sleep(0.05)
        scoreboard.release.set()
        assert first.result(timeout=2) == second.result(timeout=2)

    assert scoreboard.calls == 1


def test_current_home_aggregate_exits_when_one_section_never_completes() -> None:
    records = _BlockingRecordsOverviewService()
    service = HomeService(
        scoreboard_service=_EmptyScoreboardService(),
        schedule_service=_EmptyScheduleService(),
        standings_service=_EmptyStandingsService(),
        records_overview_service=records,
        aggregate_timeout_seconds=0.05,
    )

    started_at = time.monotonic()
    try:
        with pytest.raises(UpstreamDeadlineExceeded, match="home records overview"):
            service.get_home("2999-01-01", my_team="LG")
        assert records.started.wait(timeout=0.5)
    finally:
        records.release.set()

    assert time.monotonic() - started_at < 0.3


def test_current_home_my_team_recent_results_cross_month_boundary() -> None:
    schedule_service = _MonthBoundaryScheduleService()
    service = HomeService(
        scoreboard_service=_EmptyScoreboardService(),
        schedule_service=schedule_service,
        standings_service=_EmptyStandingsService(),
        records_overview_service=_EmptyRecordsOverviewService(),
    )

    payload = service.get_home("2026-07-01", my_team="OB")

    brief = payload["myTeamBrief"]
    assert schedule_service.requested_months == ["2026-07", "2026-06"]
    assert brief["recentGamesCount"] == 1
    assert brief["recentWins"] == 1
    assert brief["recentSummaries"] == [
        {
            "gameId": "20260630LTOB0",
            "result": "승",
            "opponentName": "롯데",
            "score": "5:0",
        }
    ]


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
    assert payload["kboBrief"]["items"][0]["route"] == "/schedule"


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


def test_my_team_game_quick_item_normalizes_team_codes() -> None:
    service = HomeService.__new__(HomeService)

    items = service._build_quick_items(
        my_team_brief={
            "teamId": "SS",
            "teamLabel": "삼성 라이온즈",
            "todayGameId": "20260624SSSK0",
        },
        overview={"leaders": {"hr": []}},
        games=[
            {
                "gameId": "20260624SSSK0",
                "inning": "7회말",
                "stadium": "대구",
                "away": {"teamId": "SS", "shortName": "SS", "score": 4},
                "home": {"teamId": "SK", "shortName": "SK", "score": 3},
            }
        ],
        season=2026,
    )

    assert items[0]["title"] == "삼성 4 : 3 SSG"


def test_kbo_brief_record_item_uses_player_image_and_detail_route() -> None:
    service = HomeService.__new__(HomeService)

    item = service._build_record_brief_item(
        {
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
        season=2026,
    )

    assert item is not None
    assert item["title"] == "김도영 13홈런"
    assert item["route"] == "/records/player/52605?season=2026"
    assert item["imageUrl"].endswith("/2026/52605.jpg")
    assert item["fallbackLabel"] == "김도영"


def test_kbo_brief_surfaces_high_error_game() -> None:
    service = HomeService.__new__(HomeService)

    brief = service._build_kbo_brief(
        today="2026-06-29",
        my_team=None,
        games=[
            {
                "gameId": "20260629OBLG0",
                "status": "FINAL",
                "inning": "경기종료",
                "stadium": "잠실",
                "away": {
                    "teamId": "OB",
                    "shortName": "두산",
                    "score": 4,
                    "hits": 8,
                    "errors": 3,
                },
                "home": {
                    "teamId": "LG",
                    "shortName": "LG",
                    "score": 6,
                    "hits": 10,
                    "errors": 2,
                },
            }
        ],
        standings=[],
        overview={"leaders": {"avg": [], "hr": []}},
    )

    defense_items = [item for item in brief["items"] if item["type"] == "defense_issue"]
    assert defense_items
    assert defense_items[0]["eyebrow"] == "실책 많은 경기"
    assert defense_items[0]["title"] == "두산-LG 합계 5실책"
    assert defense_items[0]["subtitle"] == "두산 3실책 · LG 2실책"
    assert defense_items[0]["route"] == "/game/20260629OBLG0"


def test_kbo_brief_surfaces_team_error_rank_for_day() -> None:
    service = HomeService.__new__(HomeService)

    brief = service._build_kbo_brief(
        today="2026-06-29",
        my_team=None,
        games=[
            {
                "gameId": "20260629OBLG0",
                "status": "FINAL",
                "inning": "경기종료",
                "stadium": "잠실",
                "away": {"teamId": "OB", "shortName": "두산", "score": 4, "errors": 3},
                "home": {"teamId": "LG", "shortName": "LG", "score": 6, "errors": 2},
            },
            {
                "gameId": "20260629HTSS0",
                "status": "FINAL",
                "inning": "경기종료",
                "stadium": "대구",
                "away": {"teamId": "HT", "shortName": "KIA", "score": 5, "errors": 1},
                "home": {"teamId": "SS", "shortName": "삼성", "score": 3, "errors": 0},
            },
        ],
        standings=[],
        overview={"leaders": {"avg": [], "hr": []}},
    )

    rank_items = [item for item in brief["items"] if item["type"] == "defense_rank"]
    assert rank_items
    assert rank_items[0]["eyebrow"] == "팀별 실책"
    assert rank_items[0]["title"] == "두산 3개 · LG 2개"
    assert rank_items[0]["subtitle"] == "6월 29일 경기 기준 · 실책 많은 팀 순"
    assert rank_items[0]["route"] == "/schedule"


def test_kbo_brief_uses_avg_leader_when_available() -> None:
    service = HomeService.__new__(HomeService)

    brief = service._build_kbo_brief(
        today="2026-06-30",
        my_team=None,
        games=[],
        standings=[],
        overview={
            "leaders": {
                "avg": [
                    {
                        "rank": 1,
                        "playerId": "64166",
                        "name": "홍창기",
                        "teamId": "LG",
                        "value": "0.351",
                    }
                ],
                "hr": [],
            }
        },
    )

    avg_items = [item for item in brief["items"] if item["type"] == "batting_leader"]
    assert avg_items
    assert avg_items[0]["eyebrow"] == "6월 현재 타율"
    assert avg_items[0]["title"] == "홍창기 타율 0.351"
    assert avg_items[0]["route"] == "/records/player/64166?season=2026"
    assert avg_items[0]["imageUrl"].endswith("/2026/64166.jpg")


def test_kbo_brief_surfaces_my_team_record_milestone() -> None:
    service = HomeService.__new__(HomeService)

    brief = service._build_kbo_brief(
        today="2026-07-01",
        my_team="HT",
        games=[],
        standings=[],
        overview={
            "leaders": {
                "avg": [],
                "hr": [],
                "milestones": [
                    {
                        "rank": 3,
                        "playerId": "78224",
                        "playerType": "hitter",
                        "metricKey": "TB",
                        "name": "최형우",
                        "teamId": "HT",
                        "value": "2000",
                        "milestoneLabel": "2000루타",
                        "allTimeRank": 3,
                    }
                ],
            }
        },
    )

    milestone_items = [item for item in brief["items"] if item["type"] == "record_milestone"]

    assert milestone_items
    assert milestone_items[0]["eyebrow"] == "기록 달성"
    assert milestone_items[0]["title"] == "최형우 2000루타 달성"
    assert milestone_items[0]["subtitle"] == "KIA 타이거즈 · 역대 3번째"
    assert milestone_items[0]["route"] == "/records/player/78224?season=2026"
    assert milestone_items[0]["teamIds"] == ["HT"]


def test_quick_items_include_hitter_and_pitcher_brief_cards_together() -> None:
    service = HomeService.__new__(HomeService)

    items = service._build_quick_items(
        my_team_brief=None,
        overview={
            "leaders": {"hr": []},
            "featured": {
                "todayHitter": {
                    "label": "오늘의 타자",
                    "playerId": "64166",
                    "name": "홍창기",
                    "teamId": "LG",
                    "headline": "타율 1위",
                },
                "todayPitcher": {
                    "label": "오늘의 투수",
                    "playerId": "50126",
                    "name": "폰세",
                    "teamId": "HH",
                    "headline": "ERA 1위",
                },
            },
        },
        games=[],
        season=2026,
    )

    assert [item["title"] for item in items] == ["홍창기", "폰세"]
    assert items[0]["route"] == "/records/player/64166?season=2026"
    assert items[1]["route"] == "/records/player/50126?season=2026"


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


def test_my_team_brief_keeps_recent_five_results() -> None:
    service = HomeService.__new__(HomeService)

    schedule_days = []
    for day in range(10, 16):
        schedule_days.append(
            {
                "date": f"2026-05-{day}",
                "games": [
                    {
                        "gameId": f"202605{day}OBLG0",
                        "awayId": "OB",
                        "awayName": "두산",
                        "awayScore": day - 9,
                        "homeId": "LG",
                        "homeName": "LG",
                        "homeScore": day - 8,
                        "stadium": "잠실",
                        "status": "FINAL",
                    }
                ],
            }
        )

    brief = service._build_my_team_brief(
        my_team="LG",
        games=[],
        schedule_days=schedule_days,
        standings=[],
        today="2026-05-16",
    )

    assert brief is not None
    assert brief["recentGamesCount"] == 5
    assert len(brief["recentSummaries"]) == 5
    assert brief["recentSummaries"][0]["gameId"] == "20260515OBLG0"


def test_standings_preview_returns_all_teams_in_rank_order() -> None:
    service = HomeService.__new__(HomeService)

    standings = [
        {
            "rank": rank,
            "teamId": team_id,
            "teamName": team_id,
            "wins": 10 - rank,
            "losses": rank,
            "draws": 0,
            "pct": ".500",
            "gb": str(rank - 1),
        }
        for rank, team_id in enumerate(["HT", "OB", "SS", "SK", "NC", "LG"], start=1)
    ]

    preview = service._build_standings_preview(standings=standings, my_team="LG")

    assert [item["teamId"] for item in preview] == ["HT", "OB", "SS", "SK", "NC", "LG"]
    assert preview[-1]["rank"] == 6


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

    assert brief["title"] == "KBO 소식"
    assert brief["items"][0]["type"] == "record_radar"
    assert brief["items"][0]["route"] == "/records/player/52605?season=2026"
    assert any(item["title"] == "두산 vs LG" for item in brief["items"])
