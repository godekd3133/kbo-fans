import threading
import time
from pathlib import Path

from kbo_fans_backend.services.scoreboard import ScoreboardService
from kbo_fans_backend.storage import JsonSnapshotStore


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


class _MultiGameScheduleCrawler:
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
            },
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
            },
        ]


class _MultiGameMainCrawler:
    def __init__(self):
        self.calls = 0

    def get_kbo_game_list(self, date: str):
        self.calls += 1
        return [
            {"G_ID": "20260331HTLG0", "G_TM": "18:30", "GAME_STATE_SC": "3"},
            {"G_ID": "20260331OBSS0", "G_TM": "18:30", "GAME_STATE_SC": "3"},
        ]


class _TrackingScoreboardCrawler(_StubScoreboardCrawler):
    def __init__(self):
        super().__init__()
        self.game_ids = []

    def get_game_scoreboard(self, game_id: str):
        self.game_ids.append(game_id)
        return super().get_game_scoreboard(game_id)


class _SlowScheduleCrawler(_StubScheduleCrawler):
    def __init__(self):
        super().__init__()
        self._gate = threading.Event()

    def get_games_by_date(self, date: str):
        self._gate.wait(timeout=1)
        time.sleep(0.02)
        return super().get_games_by_date(date)

    def release(self):
        self._gate.set()


def test_get_scoreboard_uses_ttl_cache_for_same_date(tmp_path: Path) -> None:
    schedule = _StubScheduleCrawler()
    main = _StubMainCrawler()
    scoreboard = _StubScoreboardCrawler()
    service = ScoreboardService(
        main_crawler=main,
        schedule_crawler=schedule,
        scoreboard_crawler=scoreboard,
        snapshot_store=JsonSnapshotStore(base_dir=str(tmp_path / "snapshots")),
    )

    first = service.get_scoreboard("2026-03-31")
    second = service.get_scoreboard("2026-03-31")

    assert first == second
    assert schedule.calls == 1
    assert main.calls == 1
    assert scoreboard.calls == 0


def test_get_game_enriches_only_requested_game(tmp_path: Path) -> None:
    schedule = _MultiGameScheduleCrawler()
    main = _MultiGameMainCrawler()
    scoreboard = _TrackingScoreboardCrawler()
    service = ScoreboardService(
        main_crawler=main,
        schedule_crawler=schedule,
        scoreboard_crawler=scoreboard,
        snapshot_store=JsonSnapshotStore(base_dir=str(tmp_path / "snapshots")),
    )

    game = service.get_game("20260331OBSS0")

    assert game is not None
    assert game["gameId"] == "20260331OBSS0"
    assert schedule.calls == 1
    assert main.calls == 1
    assert scoreboard.game_ids == ["20260331OBSS0"]


def test_get_compact_scoreboard_enriches_only_selected_game(tmp_path: Path) -> None:
    schedule = _MultiGameScheduleCrawler()
    main = _MultiGameMainCrawler()
    scoreboard = _TrackingScoreboardCrawler()
    service = ScoreboardService(
        main_crawler=main,
        schedule_crawler=schedule,
        scoreboard_crawler=scoreboard,
        snapshot_store=JsonSnapshotStore(base_dir=str(tmp_path / "snapshots")),
    )

    payload = service.get_compact_scoreboard("2026-03-31", my_team="SS")

    assert payload["date"] == "2026-03-31"
    assert [game["gameId"] for game in payload["games"]] == ["20260331OBSS0"]
    assert schedule.calls == 1
    assert main.calls == 1
    assert scoreboard.game_ids == ["20260331OBSS0"]


def test_get_scoreboard_coalesces_concurrent_same_date_requests(
    tmp_path: Path,
) -> None:
    schedule = _SlowScheduleCrawler()
    main = _StubMainCrawler()
    scoreboard = _StubScoreboardCrawler()
    service = ScoreboardService(
        main_crawler=main,
        schedule_crawler=schedule,
        scoreboard_crawler=scoreboard,
        snapshot_store=JsonSnapshotStore(base_dir=str(tmp_path / "snapshots")),
    )
    results = []

    threads = [
        threading.Thread(
            target=lambda: results.append(service.get_scoreboard("2026-03-31"))
        )
        for _ in range(3)
    ]
    for thread in threads:
        thread.start()

    schedule.release()

    for thread in threads:
        thread.join(timeout=2)

    assert len(results) == 3
    assert results[0] == results[1] == results[2]
    assert schedule.calls == 1
    assert main.calls == 1
