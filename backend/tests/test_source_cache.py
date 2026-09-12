import threading
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

from kbo_fans_backend.services.schedule import ScheduleService
from kbo_fans_backend.services.scoreboard import ScoreboardService
from kbo_fans_backend.storage import JsonSnapshotStore
from kbo_fans_backend.utils.source_cache import KboSourceCache


def test_source_cache_coalesces_concurrent_loads() -> None:
    started = threading.Event()
    release = threading.Event()
    calls = 0

    def loader(key: str) -> dict[str, str]:
        nonlocal calls
        calls += 1
        started.set()
        assert release.wait(timeout=2)
        return {"key": key}

    source = KboSourceCache(loader, ttl_seconds=8)
    with ThreadPoolExecutor(max_workers=2) as executor:
        first = executor.submit(source.get, "2026-09")
        assert started.wait(timeout=1)
        second = executor.submit(source.get, "2026-09")
        release.set()
        assert first.result(timeout=2) == {"key": "2026-09"}
        assert second.result(timeout=2) == {"key": "2026-09"}

    assert calls == 1


def test_source_cache_force_refresh_bypasses_cached_value() -> None:
    calls = 0

    def loader(_key: str) -> int:
        nonlocal calls
        calls += 1
        return calls

    source = KboSourceCache(loader, ttl_seconds=8)

    assert source.get("main") == 1
    assert source.get("main") == 1
    assert source.get("main", force_refresh=True) == 2
    assert source.get("main") == 2
    assert calls == 2


class _SharedMonthCrawler:
    def __init__(self) -> None:
        self.calls = 0

    def get_month_schedule(self, month: str):
        self.calls += 1
        date = f"{month}-01"
        return [
            {
                "date": date,
                "gameId": f"{date.replace('-', '')}LGOB0",
                "time": "18:30",
                "awayId": "LG",
                "awayName": "LG",
                "awayScore": None,
                "homeId": "OB",
                "homeName": "두산",
                "homeScore": None,
                "stadium": "잠실",
                "status": "SCHEDULED",
            }
        ]


class _SharedMainCrawler:
    def __init__(self) -> None:
        self.calls = 0

    def get_kbo_game_list(self, date: str):
        self.calls += 1
        return [
            {
                "G_ID": f"{date.replace('-', '')}LGOB0",
                "G_TM": "18:30",
                "GAME_STATE_SC": "1",
            }
        ]


def test_shared_sources_reuse_raw_schedule_between_services(tmp_path: Path) -> None:
    month_crawler = _SharedMonthCrawler()
    main_crawler = _SharedMainCrawler()
    schedule_source = KboSourceCache(
        month_crawler.get_month_schedule,
        ttl_seconds=8,
    )
    main_source = KboSourceCache(
        main_crawler.get_kbo_game_list,
        ttl_seconds=8,
    )
    scoreboard = ScoreboardService(
        schedule_crawler=month_crawler,
        main_crawler=main_crawler,
        schedule_source=schedule_source,
        main_source=main_source,
        snapshot_store=JsonSnapshotStore(base_dir=str(tmp_path / "scoreboard")),
    )
    schedule = ScheduleService(
        schedule_crawler=month_crawler,
        main_crawler=main_crawler,
        schedule_source=schedule_source,
        main_source=main_source,
        snapshot_store=JsonSnapshotStore(base_dir=str(tmp_path / "schedule")),
    )

    scoreboard.get_home_scoreboard("2999-01-01")
    payload = schedule.get_month_schedule_for_home("2999-01")

    assert payload["month"] == "2999-01"
    assert month_crawler.calls == 1
    assert main_crawler.calls == 1
