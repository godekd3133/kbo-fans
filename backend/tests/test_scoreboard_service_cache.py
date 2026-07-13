import json
import threading
import time
from pathlib import Path

import pytest

from kbo_fans_backend.services.scoreboard import ScoreboardService
from kbo_fans_backend.storage import JsonSnapshotStore
from kbo_fans_backend.storage.live_scoreboard_store import LiveScoreboardStore
from kbo_fans_backend.utils.kbo_time import current_kbo_date


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


class _FailingScheduleCrawler:
    def get_games_by_date(self, date: str):
        raise RuntimeError("schedule unavailable")


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


def test_get_home_scoreboard_does_not_fetch_per_game_detail(tmp_path: Path) -> None:
    schedule = _MultiGameScheduleCrawler()
    main = _MultiGameMainCrawler()
    scoreboard = _TrackingScoreboardCrawler()
    service = ScoreboardService(
        main_crawler=main,
        schedule_crawler=schedule,
        scoreboard_crawler=scoreboard,
        snapshot_store=JsonSnapshotStore(base_dir=str(tmp_path / "snapshots")),
    )

    payload = service.get_home_scoreboard("2026-03-31")

    assert payload["date"] == "2026-03-31"
    assert [game["gameId"] for game in payload["games"]] == [
        "20260331HTLG0",
        "20260331OBSS0",
    ]
    assert [game["status"] for game in payload["games"]] == ["FINAL", "FINAL"]
    assert schedule.calls == 1
    assert main.calls == 1
    assert scoreboard.game_ids == []


def test_get_home_scoreboard_uses_fresh_live_state_without_crawling(
    tmp_path: Path,
) -> None:
    live_store = LiveScoreboardStore(
        path=str(tmp_path / "runtime" / "live_scoreboard.json"),
        max_age_seconds=8,
    )
    expected = {
        "date": "2999-03-31",
        "games": [
            {
                "gameId": "29990331HTLG0",
                "status": "LIVE",
                "inning": "7회말",
                "away": {"teamId": "HT", "score": 3},
                "home": {"teamId": "LG", "score": 4},
            }
        ],
    }
    live_store.save("2999-03-31", expected)
    schedule = _FailingScheduleCrawler()
    service = ScoreboardService(
        main_crawler=_StubMainCrawler(),
        schedule_crawler=schedule,
        scoreboard_crawler=_StubScoreboardCrawler(),
        snapshot_store=JsonSnapshotStore(base_dir=str(tmp_path / "snapshots")),
        live_scoreboard_store=live_store,
    )

    payload = service.get_home_scoreboard("2999-03-31")

    assert payload == expected


def test_get_home_scoreboard_ignores_stale_live_state_on_failure(
    tmp_path: Path,
) -> None:
    live_path = tmp_path / "runtime" / "live_scoreboard.json"
    _write_live_scoreboard_record(
        live_path,
        "2999-03-31",
        {
            "date": "2999-03-31",
            "games": [
                {
                    "gameId": "29990331HTLG0",
                    "status": "LIVE",
                    "inning": "7회말",
                    "away": {"teamId": "HT", "score": 3},
                    "home": {"teamId": "LG", "score": 4},
                }
            ],
        },
        saved_at="2000-01-01T00:00:00+00:00",
    )
    service = ScoreboardService(
        main_crawler=_StubMainCrawler(),
        schedule_crawler=_FailingScheduleCrawler(),
        scoreboard_crawler=_StubScoreboardCrawler(),
        snapshot_store=JsonSnapshotStore(base_dir=str(tmp_path / "snapshots")),
        live_scoreboard_store=LiveScoreboardStore(
            path=str(live_path),
            max_age_seconds=8,
        ),
    )

    with pytest.raises(RuntimeError):
        service.get_home_scoreboard("2999-03-31")


def test_prime_home_scoreboard_writes_live_state_for_other_workers(
    tmp_path: Path,
) -> None:
    live_store = LiveScoreboardStore(
        path=str(tmp_path / "runtime" / "live_scoreboard.json"),
        max_age_seconds=8,
    )
    writer = ScoreboardService(
        main_crawler=_StubMainCrawler(),
        schedule_crawler=_StubScheduleCrawler(),
        scoreboard_crawler=_StubScoreboardCrawler(),
        snapshot_store=JsonSnapshotStore(base_dir=str(tmp_path / "writer_snapshots")),
        live_scoreboard_store=live_store,
    )

    expected = writer.prime_home_scoreboard("2999-03-31")
    reader = ScoreboardService(
        main_crawler=_StubMainCrawler(),
        schedule_crawler=_FailingScheduleCrawler(),
        scoreboard_crawler=_StubScoreboardCrawler(),
        snapshot_store=JsonSnapshotStore(base_dir=str(tmp_path / "reader_snapshots")),
        live_scoreboard_store=LiveScoreboardStore(
            path=str(tmp_path / "runtime" / "live_scoreboard.json"),
            max_age_seconds=8,
        ),
    )

    assert reader.get_home_scoreboard("2999-03-31") == expected


def test_home_and_compact_share_schedule_and_main_source_cache(
    tmp_path: Path,
) -> None:
    schedule = _MultiGameScheduleCrawler()
    main = _MultiGameMainCrawler()
    service = ScoreboardService(
        main_crawler=main,
        schedule_crawler=schedule,
        scoreboard_crawler=_TrackingScoreboardCrawler(),
        snapshot_store=JsonSnapshotStore(base_dir=str(tmp_path / "snapshots")),
    )

    service.get_home_scoreboard("2999-03-31")
    compact = service.get_compact_scoreboard("2999-03-31", my_team="SS")

    assert [game["gameId"] for game in compact["games"]] == ["20260331OBSS0"]
    assert schedule.calls == 1
    assert main.calls == 1


def test_get_game_ignores_snapshot_for_non_historical_game(tmp_path: Path) -> None:
    game_id = "29990331OBSS0"
    snapshot_store = JsonSnapshotStore(base_dir=str(tmp_path / "snapshots"))
    snapshot_store.save(
        "games",
        game_id,
        {
            "gameId": game_id,
            "status": "LIVE",
            "inning": "8회초",
            "away": {"score": 0, "scores": [None] * 9},
            "home": {"score": 0, "scores": [None] * 9},
        },
    )

    class FutureScheduleCrawler:
        def __init__(self):
            self.calls = 0

        def get_games_by_date(self, date: str):
            self.calls += 1
            return [
                {
                    "date": date,
                    "time": "18:30",
                    "gameId": game_id,
                    "awayId": "OB",
                    "awayName": "두산",
                    "homeId": "SS",
                    "homeName": "삼성",
                    "stadium": "대구",
                    "status": "SCHEDULED",
                }
            ]

    class FutureMainCrawler:
        def get_kbo_game_list(self, date: str):
            return [{"G_ID": game_id, "G_TM": "18:30", "GAME_STATE_SC": "3"}]

    class FutureScoreboardCrawler(_StubScoreboardCrawler):
        def get_game_scoreboard(self, game_id: str):
            payload = super().get_game_scoreboard(game_id)
            payload["away"]["score"] = 2
            payload["away"]["scores"] = [1, 1, 0, None, None, None, None, None, None]
            payload["home"]["score"] = 10
            payload["home"]["scores"] = [3, 7, 0, None, None, None, None, None, None]
            return payload

    schedule = FutureScheduleCrawler()
    service = ScoreboardService(
        main_crawler=FutureMainCrawler(),
        schedule_crawler=schedule,
        scoreboard_crawler=FutureScoreboardCrawler(),
        snapshot_store=snapshot_store,
    )

    game = service.get_game(game_id)

    assert game is not None
    assert schedule.calls == 1
    assert game["away"]["score"] == 2
    assert game["home"]["score"] == 10


def test_get_game_uses_snapshot_for_historical_game(tmp_path: Path) -> None:
    game_id = "20200101OBSS0"
    snapshot_store = JsonSnapshotStore(base_dir=str(tmp_path / "snapshots"))
    snapshot_store.save(
        "games",
        game_id,
        {
            "gameId": game_id,
            "status": "FINAL",
            "away": {"score": 7},
            "home": {"score": 4},
        },
    )
    schedule = _StubScheduleCrawler()
    service = ScoreboardService(
        main_crawler=_StubMainCrawler(),
        schedule_crawler=schedule,
        scoreboard_crawler=_StubScoreboardCrawler(),
        snapshot_store=snapshot_store,
    )

    game = service.get_game(game_id)

    assert game is not None
    assert schedule.calls == 0
    assert game["away"]["score"] == 7
    assert game["home"]["score"] == 4


def test_get_compact_scoreboard_uses_lightweight_selected_game(tmp_path: Path) -> None:
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
    assert payload["games"][0]["status"] == "FINAL"
    assert schedule.calls == 1
    assert main.calls == 1
    assert scoreboard.game_ids == []


def test_current_scoreboard_rejects_old_nonterminal_snapshot_on_failure(
    tmp_path: Path,
) -> None:
    today = current_kbo_date().isoformat()
    snapshot_store = JsonSnapshotStore(base_dir=str(tmp_path / "snapshots"))
    _write_snapshot_record(
        tmp_path / "snapshots",
        "scoreboard",
        today,
        {
            "date": today,
            "games": [
                {
                    "gameId": f"{today.replace('-', '')}KTSS0",
                    "status": "LIVE",
                    "away": {"score": 0},
                    "home": {"score": 0},
                }
            ],
        },
    )
    service = ScoreboardService(
        main_crawler=_StubMainCrawler(),
        schedule_crawler=_FailingScheduleCrawler(),
        scoreboard_crawler=_StubScoreboardCrawler(),
        snapshot_store=snapshot_store,
    )

    with pytest.raises(RuntimeError):
        service.get_scoreboard(today)


def test_current_scoreboard_rejects_fresh_terminal_snapshot_on_failure(
    tmp_path: Path,
) -> None:
    today = current_kbo_date().isoformat()
    snapshot_store = JsonSnapshotStore(base_dir=str(tmp_path / "snapshots"))
    expected = {
        "date": today,
        "games": [
            {
                "gameId": f"{today.replace('-', '')}KTSS0",
                "status": "FINAL",
                "away": {"score": 4},
                "home": {"score": 2},
            }
        ],
    }
    snapshot_store.save("scoreboard", today, expected)
    service = ScoreboardService(
        main_crawler=_StubMainCrawler(),
        schedule_crawler=_FailingScheduleCrawler(),
        scoreboard_crawler=_StubScoreboardCrawler(),
        snapshot_store=snapshot_store,
    )

    with pytest.raises(RuntimeError):
        service.get_scoreboard(today)


def test_current_compact_scoreboard_rejects_old_nonterminal_snapshot_on_failure(
    tmp_path: Path,
) -> None:
    today = current_kbo_date().isoformat()
    snapshot_store = JsonSnapshotStore(base_dir=str(tmp_path / "snapshots"))
    _write_snapshot_record(
        tmp_path / "snapshots",
        "scoreboard",
        today,
        {
            "date": today,
            "games": [
                {
                    "gameId": f"{today.replace('-', '')}KTSS0",
                    "status": "LIVE",
                    "awayId": "KT",
                    "homeId": "SS",
                    "away": {"score": 0},
                    "home": {"score": 0},
                }
            ],
        },
    )
    service = ScoreboardService(
        main_crawler=_StubMainCrawler(),
        schedule_crawler=_FailingScheduleCrawler(),
        scoreboard_crawler=_StubScoreboardCrawler(),
        snapshot_store=snapshot_store,
    )

    with pytest.raises(RuntimeError):
        service.get_compact_scoreboard(today, my_team="KT")


def test_current_home_scoreboard_rejects_fresh_snapshot_on_failure(
    tmp_path: Path,
) -> None:
    today = current_kbo_date().isoformat()
    snapshot_store = JsonSnapshotStore(base_dir=str(tmp_path / "snapshots"))
    snapshot_store.save(
        "scoreboard",
        today,
        {
            "date": today,
            "games": [
                {
                    "gameId": f"{today.replace('-', '')}KTSS0",
                    "status": "FINAL",
                    "awayId": "KT",
                    "homeId": "SS",
                    "away": {"score": 4},
                    "home": {"score": 2},
                }
            ],
        },
    )
    service = ScoreboardService(
        main_crawler=_StubMainCrawler(),
        schedule_crawler=_FailingScheduleCrawler(),
        scoreboard_crawler=_StubScoreboardCrawler(),
        snapshot_store=snapshot_store,
    )

    with pytest.raises(RuntimeError):
        service.get_home_scoreboard(today)


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
        threading.Thread(target=lambda: results.append(service.get_scoreboard("2026-03-31")))
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


def _write_snapshot_record(
    base_dir: Path,
    namespace: str,
    key: str,
    payload: dict,
) -> None:
    path = base_dir / namespace / f"{key}.json"
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        json.dumps(
            {
                "savedAt": "2000-01-01T00:00:00+00:00",
                "payload": payload,
            },
            ensure_ascii=False,
        ),
        encoding="utf-8",
    )


def _write_live_scoreboard_record(
    path: Path,
    date: str,
    payload: dict,
    *,
    saved_at: str,
) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        json.dumps(
            {
                "scoreboards": {
                    date: {
                        "savedAt": saved_at,
                        "payload": payload,
                    }
                }
            },
            ensure_ascii=False,
        ),
        encoding="utf-8",
    )
