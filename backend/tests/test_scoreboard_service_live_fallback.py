from pathlib import Path

from kbo_fans_backend.services.scoreboard import ScoreboardService
from kbo_fans_backend.storage import JsonSnapshotStore


class _StubScheduleCrawler:
    def get_games_by_date(self, date: str):
        return [
            {
                "date": date,
                "time": "18:30",
                "gameId": "20260331OBSS0",
                "awayId": "OB",
                "awayName": "두산",
                "homeId": "SS",
                "homeName": "삼성",
                "stadium": "대구",
                "status": "SCHEDULED",
            }
        ]


class _StubMainCrawler:
    def get_kbo_game_list(self, date: str):
        return [
            {
                "G_ID": "20260331OBSS0",
                "G_TM": "18:30",
                "GAME_STATE_SC": "2",
                "GAME_INN_NO": 8,
                "GAME_TB_SC_NM": "말",
                "T_SCORE_CN": "5",
                "B_SCORE_CN": "2",
                "BALL_CN": 0,
                "STRIKE_CN": 0,
                "OUT_CN": 2,
                "B_P_NM": "디아즈",
                "T_P_NM": "이병헌",
            }
        ]


class _StubScoreboardCrawler:
    def get_game_scoreboard(self, game_id: str):
        return {
            "inning": "예정",
            "stadium": "대구",
            "crowd": 0,
            "startTime": None,
            "away": {
                "teamId": "OB",
                "teamName": "두산 베어스",
                "shortName": "두산",
                "logoUrl": None,
                "score": None,
                "scores": [None] * 9,
                "hits": None,
                "errors": None,
                "balls": None,
            },
            "home": {
                "teamId": "SS",
                "teamName": "삼성 라이온즈",
                "shortName": "삼성",
                "logoUrl": None,
                "score": None,
                "scores": [None] * 9,
                "hits": None,
                "errors": None,
                "balls": None,
            },
        }

    def get_view1_scoreboard_detail(self, game_id: str):
        return {
            "awayScores": [0, 0, 1, 3, 1, 0, 0, 0, None],
            "homeScores": [0, 0, 1, 0, 0, 0, 1, 0, None],
            "awayTotals": {"hits": 10, "errors": 0, "balls": 6},
            "homeTotals": {"hits": 4, "errors": 0, "balls": 1},
        }


def test_live_scoreboard_uses_view1_fallback_for_totals_and_main_inning(
    tmp_path: Path,
) -> None:
    service = ScoreboardService(
        main_crawler=_StubMainCrawler(),
        schedule_crawler=_StubScheduleCrawler(),
        scoreboard_crawler=_StubScoreboardCrawler(),
        snapshot_store=JsonSnapshotStore(base_dir=str(tmp_path / "snapshots")),
    )

    payload = service.get_home_scoreboard("2026-03-31")
    game = payload["games"][0]

    assert game["status"] == "LIVE"
    assert game["inning"] == "8회말"
    assert game["away"]["score"] == 5
    assert game["home"]["score"] == 2
    assert game["away"]["scores"] == [0, 0, 1, 3, 1, 0, 0, 0, None]
    assert game["home"]["scores"] == [0, 0, 1, 0, 0, 0, 1, 0, None]
    assert game["away"]["hits"] == 10
    assert game["away"]["errors"] == 0
    assert game["away"]["balls"] == 6
    assert game["home"]["hits"] == 4
    assert game["home"]["errors"] == 0
    assert game["home"]["balls"] == 1


class _FinalMainCrawler:
    def get_kbo_game_list(self, date: str):
        return [
            {
                "G_ID": "20260331OBSS0",
                "G_TM": "18:30",
                "GAME_STATE_SC": "3",
                "GAME_INN_NO": 9,
                "GAME_TB_SC_NM": "초",
                "T_SCORE_CN": "5",
                "B_SCORE_CN": "2",
            }
        ]


def test_final_scoreboard_uses_view1_when_scroll_table_is_empty(
    tmp_path: Path,
) -> None:
    service = ScoreboardService(
        main_crawler=_FinalMainCrawler(),
        schedule_crawler=_StubScheduleCrawler(),
        scoreboard_crawler=_StubScoreboardCrawler(),
        snapshot_store=JsonSnapshotStore(base_dir=str(tmp_path / "snapshots")),
    )

    game = service.get_game("20260331OBSS0")

    assert game is not None
    assert game["status"] == "FINAL"
    assert game["inning"] == "경기종료"
    assert game["away"]["score"] == 5
    assert game["home"]["score"] == 2
    assert game["away"]["scores"] == [0, 0, 1, 3, 1, 0, 0, 0, None]
    assert game["home"]["scores"] == [0, 0, 1, 0, 0, 0, 1, 0, None]
    assert game["away"]["hits"] == 10
    assert game["home"]["hits"] == 4
