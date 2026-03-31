from kbo_fans_backend.services.scoreboard import ScoreboardService


class _StubScheduleCrawler:
    def __init__(self):
        self.calls = 0

    def get_games_by_date(self, date: str):
        self.calls += 1
        return [
            {
                "date": date,
                "time": "18:30",
                "gameId": "20260331HTLG0",
                "awayId": "HT",
                "awayName": "KIA",
                "homeId": "LG",
                "homeName": "LG",
                "stadium": "잠실",
                "status": "SCHEDULED",
            }
        ]


class _StubMainCrawler:
    def __init__(self):
        self.calls = 0

    def get_kbo_game_list(self, date: str):
        self.calls += 1
        return [{"G_ID": "20260331HTLG0", "G_TM": "18:30", "GAME_STATE_SC": "1"}]


class _StubScoreboardCrawler:
    def __init__(self):
        self.calls = 0

    def get_game_scoreboard(self, game_id: str):
        self.calls += 1
        return {
            "inning": "18:30 예정",
            "stadium": "잠실",
            "crowd": None,
            "startTime": "18:30",
            "away": {
                "teamId": "HT",
                "teamName": "KIA 타이거즈",
                "shortName": "KIA",
                "logoUrl": None,
                "score": None,
                "scores": [None] * 9,
                "hits": None,
                "errors": None,
                "balls": None,
            },
            "home": {
                "teamId": "LG",
                "teamName": "LG 트윈스",
                "shortName": "LG",
                "logoUrl": None,
                "score": None,
                "scores": [None] * 9,
                "hits": None,
                "errors": None,
                "balls": None,
            },
        }


def test_get_scoreboard_uses_ttl_cache_for_same_date() -> None:
    schedule = _StubScheduleCrawler()
    main = _StubMainCrawler()
    scoreboard = _StubScoreboardCrawler()
    service = ScoreboardService(
        main_crawler=main,
        schedule_crawler=schedule,
        scoreboard_crawler=scoreboard,
    )

    first = service.get_scoreboard("2026-03-31")
    second = service.get_scoreboard("2026-03-31")

    assert first == second
    assert schedule.calls == 1
    assert main.calls == 1
    assert scoreboard.calls == 0
