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


class _MutableScheduleCrawler:
    def __init__(self, game_id: str):
        self.game_id = game_id
        self.calls = 0

    def get_games_by_date(self, date: str):
        self.calls += 1
        return [
            {
                "date": date,
                "time": "18:30",
                "gameId": self.game_id,
                "awayId": "HT",
                "awayName": "KIA",
                "homeId": "LG",
                "homeName": "LG",
                "stadium": "잠실",
                "status": "SCHEDULED",
            }
        ]


class _MutableMainCrawler:
    def __init__(self, game_id: str):
        self.game_id = game_id
        self.calls = 0
        self.status = "1"

    def get_kbo_game_list(self, date: str):
        self.calls += 1
        return [
            {
                "G_ID": self.game_id,
                "G_TM": "18:30",
                "GAME_STATE_SC": self.status,
                "GAME_INN_NO": "1",
                "GAME_TB_SC_NM": "말",
                "T_SCORE_CN": "1",
                "B_SCORE_CN": "2",
            }
        ]


class _RacingMainCrawler(_MutableMainCrawler):
    def __init__(self, game_id: str):
        super().__init__(game_id)
        self._lock = threading.Lock()
        self.first_started = threading.Event()
        self.second_started = threading.Event()
        self.release_first = threading.Event()

    def get_kbo_game_list(self, date: str):
        with self._lock:
            self.calls += 1
            call_number = self.calls

        if call_number == 1:
            self.first_started.set()
            if not self.release_first.wait(timeout=2):
                raise TimeoutError("normal scoreboard request was not released")
            status = "1"
        else:
            self.second_started.set()
            status = "2"

        return [
            {
                "G_ID": self.game_id,
                "G_TM": "18:30",
                "GAME_STATE_SC": status,
                "GAME_INN_NO": "1",
                "GAME_TB_SC_NM": "말",
                "T_SCORE_CN": "1",
                "B_SCORE_CN": "2",
            }
        ]


def _historical_suspended_service(tmp_path: Path):
    target_date = "2020-03-31"
    game_id = "20200331HTLG0"
    snapshot_store = JsonSnapshotStore(base_dir=str(tmp_path / "snapshots"))
    suspended_game = {
        "gameId": game_id,
        "status": "SUSPENDED",
        "awayId": "HT",
        "homeId": "LG",
        "away": {"teamId": "HT", "score": 1},
        "home": {"teamId": "LG", "score": 0},
    }
    snapshot_store.save(
        "scoreboard",
        target_date,
        {"date": target_date, "games": [suspended_game]},
    )
    snapshot_store.save("games", game_id, suspended_game)
    schedule = _MutableScheduleCrawler(game_id)
    main = _MutableMainCrawler(game_id)
    main.status = "3"
    service = ScoreboardService(
        main_crawler=main,
        schedule_crawler=schedule,
        scoreboard_crawler=_StubScoreboardCrawler(),
        snapshot_store=snapshot_store,
    )
    return service, snapshot_store, schedule, target_date, game_id


def _get_scoreboard_surface(
    service: ScoreboardService,
    surface: str,
    *,
    date: str,
    game_id: str,
    force_refresh: bool,
):
    if surface == "full":
        return service.get_scoreboard(date, force_refresh=force_refresh)
    if surface == "home":
        return service.get_home_scoreboard(date, force_refresh=force_refresh)
    if surface == "game":
        return service.get_game(game_id, force_refresh=force_refresh)
    raise AssertionError(f"unsupported scoreboard surface: {surface}")


def _scoreboard_surface_status(payload: dict, surface: str) -> str:
    if surface == "game":
        return payload["status"]
    return payload["games"][0]["status"]


def test_historical_suspended_scoreboard_refreshes_and_replaces_snapshot(
    tmp_path: Path,
) -> None:
    service, snapshot_store, schedule, target_date, _ = _historical_suspended_service(tmp_path)

    payload = service.get_scoreboard(target_date)

    assert payload["games"][0]["status"] == "FINAL"
    assert schedule.calls == 1
    assert snapshot_store.load_payload("scoreboard", target_date) == payload


def test_historical_suspended_home_scoreboard_refreshes_source(tmp_path: Path) -> None:
    service, _, schedule, target_date, _ = _historical_suspended_service(tmp_path)

    payload = service.get_home_scoreboard(target_date)

    assert payload["games"][0]["status"] == "FINAL"
    assert schedule.calls == 1


def test_historical_suspended_prime_home_scoreboard_refreshes_source(tmp_path: Path) -> None:
    service, _, schedule, target_date, _ = _historical_suspended_service(tmp_path)

    payload = service.prime_home_scoreboard(target_date)

    assert payload["games"][0]["status"] == "FINAL"
    assert schedule.calls == 1


def test_historical_suspended_compact_scoreboard_refreshes_source(tmp_path: Path) -> None:
    service, _, schedule, target_date, _ = _historical_suspended_service(tmp_path)

    payload = service.get_compact_scoreboard(target_date, my_team="LG")

    assert payload["games"][0]["status"] == "FINAL"
    assert schedule.calls == 1


def test_historical_suspended_game_refreshes_and_replaces_snapshot(tmp_path: Path) -> None:
    service, snapshot_store, schedule, _, game_id = _historical_suspended_service(tmp_path)

    payload = service.get_game(game_id)

    assert payload is not None
    assert payload["status"] == "FINAL"
    assert schedule.calls == 1
    assert snapshot_store.load_payload("games", game_id) == payload


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


@pytest.mark.parametrize("surface", ["full", "home", "game"])
def test_force_refresh_wins_same_date_cache_race(
    tmp_path: Path,
    surface: str,
) -> None:
    target_date = "2999-03-31"
    game_id = "29990331HTLG0"
    schedule = _MutableScheduleCrawler(game_id)
    main = _RacingMainCrawler(game_id)
    service = ScoreboardService(
        main_crawler=main,
        schedule_crawler=schedule,
        scoreboard_crawler=_StubScoreboardCrawler(),
        snapshot_store=JsonSnapshotStore(base_dir=str(tmp_path / "snapshots")),
    )
    results = {}
    errors = []

    def request(key: str, force_refresh: bool) -> None:
        try:
            results[key] = _get_scoreboard_surface(
                service,
                surface,
                date=target_date,
                game_id=game_id,
                force_refresh=force_refresh,
            )
        except BaseException as error:
            errors.append(error)

    normal_thread = threading.Thread(target=request, args=("normal", False))
    normal_thread.start()
    assert main.first_started.wait(timeout=1)

    force_thread = threading.Thread(target=request, args=("force", True))
    force_thread.start()
    main.second_started.wait(timeout=0.25)
    main.release_first.set()

    normal_thread.join(timeout=2)
    force_thread.join(timeout=2)
    assert not normal_thread.is_alive()
    assert not force_thread.is_alive()
    assert errors == []

    final_payload = _get_scoreboard_surface(
        service,
        surface,
        date=target_date,
        game_id=game_id,
        force_refresh=False,
    )
    assert _scoreboard_surface_status(results["normal"], surface) == "SCHEDULED"
    assert _scoreboard_surface_status(results["force"], surface) == "LIVE"
    assert _scoreboard_surface_status(final_payload, surface) == "LIVE"


def test_force_refresh_home_scoreboard_bypasses_current_caches(
    tmp_path: Path,
) -> None:
    target_date = "2999-03-31"
    game_id = "29990331HTLG0"
    schedule = _MutableScheduleCrawler(game_id)
    main = _MutableMainCrawler(game_id)
    service = ScoreboardService(
        main_crawler=main,
        schedule_crawler=schedule,
        scoreboard_crawler=_StubScoreboardCrawler(),
        snapshot_store=JsonSnapshotStore(base_dir=str(tmp_path / "snapshots")),
    )

    cached = service.get_home_scoreboard(target_date)
    main.status = "2"
    refreshed = service.get_home_scoreboard(target_date, force_refresh=True)

    assert cached["games"][0]["status"] == "SCHEDULED"
    assert refreshed["games"][0]["status"] == "LIVE"
    assert schedule.calls == 2
    assert main.calls == 2


def test_force_refresh_full_scoreboard_bypasses_current_caches(
    tmp_path: Path,
) -> None:
    target_date = "2999-03-31"
    game_id = "29990331HTLG0"
    schedule = _MutableScheduleCrawler(game_id)
    main = _MutableMainCrawler(game_id)
    service = ScoreboardService(
        main_crawler=main,
        schedule_crawler=schedule,
        scoreboard_crawler=_StubScoreboardCrawler(),
        snapshot_store=JsonSnapshotStore(base_dir=str(tmp_path / "snapshots")),
    )

    cached = service.get_scoreboard(target_date)
    main.status = "2"
    refreshed = service.get_scoreboard(target_date, force_refresh=True)

    assert cached["games"][0]["status"] == "SCHEDULED"
    assert refreshed["games"][0]["status"] == "LIVE"
    assert schedule.calls == 2
    assert main.calls == 2


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


def test_force_refresh_game_bypasses_current_caches(tmp_path: Path) -> None:
    game_id = "29990331HTLG0"
    schedule = _MutableScheduleCrawler(game_id)
    main = _MutableMainCrawler(game_id)
    service = ScoreboardService(
        main_crawler=main,
        schedule_crawler=schedule,
        scoreboard_crawler=_StubScoreboardCrawler(),
        snapshot_store=JsonSnapshotStore(base_dir=str(tmp_path / "snapshots")),
    )

    cached = service.get_game(game_id)
    main.status = "2"
    refreshed = service.get_game(game_id, force_refresh=True)

    assert cached is not None
    assert refreshed is not None
    assert cached["status"] == "SCHEDULED"
    assert refreshed["status"] == "LIVE"
    assert schedule.calls == 2
    assert main.calls == 2


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


def test_force_refresh_home_scoreboard_bypasses_live_state(
    tmp_path: Path,
) -> None:
    target_date = "2999-03-31"
    game_id = "29990331HTLG0"
    live_store = LiveScoreboardStore(
        path=str(tmp_path / "runtime" / "live_scoreboard.json"),
        max_age_seconds=8,
    )
    live_store.save(
        target_date,
        {
            "date": target_date,
            "games": [{"gameId": game_id, "status": "SCHEDULED"}],
        },
    )
    schedule = _MutableScheduleCrawler(game_id)
    main = _MutableMainCrawler(game_id)
    main.status = "2"
    service = ScoreboardService(
        main_crawler=main,
        schedule_crawler=schedule,
        scoreboard_crawler=_StubScoreboardCrawler(),
        snapshot_store=JsonSnapshotStore(base_dir=str(tmp_path / "snapshots")),
        live_scoreboard_store=live_store,
    )

    cached = service.get_home_scoreboard(target_date)
    refreshed = service.get_home_scoreboard(target_date, force_refresh=True)

    assert cached["games"][0]["status"] == "SCHEDULED"
    assert refreshed["games"][0]["status"] == "LIVE"
    assert schedule.calls == 1
    assert main.calls == 1


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


def test_force_refresh_game_uses_snapshot_for_historical_game(tmp_path: Path) -> None:
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

    game = service.get_game(game_id, force_refresh=True)

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
