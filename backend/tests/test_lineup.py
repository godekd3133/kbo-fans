import concurrent.futures
import threading
from datetime import date

import pytest

from kbo_fans_backend.services.lineup import LineupService
from kbo_fans_backend.storage import JsonSnapshotStore
from kbo_fans_backend.utils.kbo_time import current_kbo_date
from kbo_fans_backend.utils.source_cache import KboSourceCache


class _StubLineupCrawler:
    def get_lineup(self, game_id: str):
        return {
            "gameId": game_id,
            "away": {
                "teamId": "LG",
                "teamName": "LG",
                "lineup": [{"order": 1, "position": "CF", "name": "홍창기"}],
            },
            "home": {
                "teamId": "OB",
                "teamName": "두산",
                "lineup": [{"order": 1, "position": "SS", "name": "박준영"}],
            },
        }


class _StubBoxscoreCrawler:
    def get_boxscore(self, game_id: str):
        return {
            "gameId": game_id,
            "away": {"pitchers": [{"name": "LG박스선발"}]},
            "home": {"pitchers": [{"name": "두산박스선발"}]},
        }


class _BlockingLineupCrawler(_StubLineupCrawler):
    def __init__(self) -> None:
        self.started = threading.Event()
        self.release = threading.Event()

    def get_lineup(self, game_id: str):
        self.started.set()
        assert self.release.wait(timeout=2)
        return super().get_lineup(game_id)


class _BlockingBoxscoreCrawler(_StubBoxscoreCrawler):
    def __init__(self) -> None:
        self.started = threading.Event()
        self.release = threading.Event()

    def get_boxscore(self, game_id: str):
        self.started.set()
        assert self.release.wait(timeout=2)
        return super().get_boxscore(game_id)


class _StubMainCrawler:
    def get_kbo_game_list(self, date: str):
        return [
            {
                "G_ID": f"{date.replace('-', '')}LGOB0",
                "T_PIT_P_ID": 55130,
                "T_PIT_P_NM": "톨허스트 ",
                "B_PIT_P_ID": 55268,
                "B_PIT_P_NM": "최민석 ",
            }
        ]


class _FailingMainCrawler:
    def get_kbo_game_list(self, date: str):
        raise AssertionError("lineup should use the shared main source")


class _StubPlayerStatsService:
    def get_team_players(self, team_id: str, season: int):
        players = {
            "LG": [
                {
                    "id": "78224",
                    "name": "홍창기",
                    "imageUrl": "https://img.test/2026/78224.jpg",
                }
            ],
            "OB": [
                {
                    "id": "66203",
                    "name": "박준영",
                    "imageUrl": "https://img.test/2026/66203.jpg",
                }
            ],
        }
        return {"teamId": team_id, "season": season, "players": players.get(team_id, [])}


class _EmptyPlayerStatsService:
    def get_team_players(self, team_id: str, season: int):
        return {"teamId": team_id, "season": season, "players": []}


def test_current_lineup_does_not_wait_for_optional_player_enrichment(tmp_path) -> None:
    class CountingPlayerStatsService:
        def __init__(self) -> None:
            self.calls = 0

        def get_team_players(self, team_id: str, season: int):
            self.calls += 1
            return {
                "teamId": team_id,
                "season": season,
                "players": [
                    {
                        "id": "78224",
                        "name": "홍창기",
                        "imageUrl": "https://img.test/2026/78224.jpg",
                    }
                ],
            }

    player_stats = CountingPlayerStatsService()
    service = LineupService(
        lineup_crawler=_StubLineupCrawler(),
        boxscore_crawler=_StubBoxscoreCrawler(),
        main_crawler=_StubMainCrawler(),
        snapshot_store=JsonSnapshotStore(base_dir=str(tmp_path)),
        player_stats_service=player_stats,
        today_provider=lambda: date(2026, 8, 27),
    )

    payload = service.get_lineup("20260827LGOB0")

    assert payload["away"]["lineup"] == [
        {"order": 1, "position": "CF", "name": "홍창기"}
    ]
    assert payload["home"]["lineup"] == [
        {"order": 1, "position": "SS", "name": "박준영"}
    ]
    assert player_stats.calls == 0


def test_current_lineup_skips_immutable_snapshot_read(tmp_path) -> None:
    today = current_kbo_date()
    game_id = f"{today:%Y%m%d}LGOB0"

    class NoCurrentLineupSnapshotStore(JsonSnapshotStore):
        def load(self, namespace: str, key: str):
            if namespace == "lineup":
                raise AssertionError("current lineup must not read immutable snapshot")
            return super().load(namespace, key)

    service = LineupService(
        lineup_crawler=_StubLineupCrawler(),
        boxscore_crawler=_StubBoxscoreCrawler(),
        main_crawler=_StubMainCrawler(),
        snapshot_store=NoCurrentLineupSnapshotStore(base_dir=str(tmp_path)),
        player_stats_service=_EmptyPlayerStatsService(),
        today_provider=lambda: today,
    )

    payload = service.get_lineup(game_id)

    assert payload["gameId"] == game_id


def test_lineup_forwards_force_refresh_to_shared_boxscore_service(tmp_path) -> None:
    game_id = "29990101LGOB0"

    class RecordingBoxscoreService:
        def __init__(self) -> None:
            self.calls = []

        def get_boxscore(self, requested_game_id: str, force_refresh: bool = False):
            self.calls.append((requested_game_id, force_refresh))
            return {
                "gameId": requested_game_id,
                "away": {"pitchers": []},
                "home": {"pitchers": []},
            }

    boxscore = RecordingBoxscoreService()
    service = LineupService(
        lineup_crawler=_StubLineupCrawler(),
        boxscore_service=boxscore,
        main_crawler=_StubMainCrawler(),
        snapshot_store=JsonSnapshotStore(base_dir=str(tmp_path)),
        player_stats_service=_EmptyPlayerStatsService(),
    )

    service.get_lineup(game_id, force_refresh=True)

    assert boxscore.calls == [(game_id, True)]


def test_lineup_and_boxscore_crawls_start_together(tmp_path) -> None:
    lineup = _BlockingLineupCrawler()
    boxscore = _BlockingBoxscoreCrawler()
    service = LineupService(
        lineup_crawler=lineup,
        boxscore_crawler=boxscore,
        main_crawler=_StubMainCrawler(),
        snapshot_store=JsonSnapshotStore(base_dir=str(tmp_path)),
        player_stats_service=_EmptyPlayerStatsService(),
        today_provider=lambda: date(2026, 8, 28),
    )

    with concurrent.futures.ThreadPoolExecutor(max_workers=1) as executor:
        request = executor.submit(service.get_lineup, "20260827LGOB0")
        assert lineup.started.wait(timeout=1)
        try:
            assert boxscore.started.wait(timeout=0.5)
        finally:
            lineup.release.set()
            boxscore.release.set()
        payload = request.result(timeout=2)

    assert payload["gameId"] == "20260827LGOB0"


def test_lineup_starts_main_lookup_with_lineup_and_boxscore(tmp_path) -> None:
    lineup = _BlockingLineupCrawler()
    boxscore = _BlockingBoxscoreCrawler()

    class ObservedMainCrawler(_StubMainCrawler):
        def __init__(self) -> None:
            self.started = threading.Event()

        def get_kbo_game_list(self, date: str):
            self.started.set()
            return super().get_kbo_game_list(date)

    main = ObservedMainCrawler()
    service = LineupService(
        lineup_crawler=lineup,
        boxscore_crawler=boxscore,
        main_crawler=main,
        snapshot_store=JsonSnapshotStore(base_dir=str(tmp_path)),
        player_stats_service=_EmptyPlayerStatsService(),
        today_provider=lambda: date(2026, 8, 28),
    )
    result = {}

    def load() -> None:
        result["payload"] = service.get_lineup("20260827LGOB0")

    thread = threading.Thread(target=load)
    thread.start()
    assert lineup.started.wait(timeout=1)
    assert boxscore.started.wait(timeout=1)
    try:
        assert main.started.wait(timeout=0.5)
    finally:
        lineup.release.set()
        boxscore.release.set()
        thread.join(timeout=2)

    assert not thread.is_alive()
    assert result["payload"]["gameId"] == "20260827LGOB0"


def test_lineup_failure_does_not_wait_for_boxscore_future(tmp_path) -> None:
    barrier = threading.Barrier(2)
    boxscore_started = threading.Event()
    boxscore_release = threading.Event()
    errors = []

    class FailingLineupCrawler:
        def get_lineup(self, game_id: str):
            barrier.wait(timeout=0.5)
            raise RuntimeError("lineup unavailable")

    class BlockingBoxscoreCrawler:
        def get_boxscore(self, game_id: str):
            barrier.wait(timeout=0.5)
            boxscore_started.set()
            boxscore_release.wait(timeout=2)
            return {
                "gameId": game_id,
                "away": {"pitchers": []},
                "home": {"pitchers": []},
            }

    service = LineupService(
        lineup_crawler=FailingLineupCrawler(),
        boxscore_crawler=BlockingBoxscoreCrawler(),
        main_crawler=_StubMainCrawler(),
        snapshot_store=JsonSnapshotStore(base_dir=str(tmp_path)),
        player_stats_service=_EmptyPlayerStatsService(),
        today_provider=lambda: date(2026, 8, 28),
    )

    def request() -> None:
        try:
            service.get_lineup("20260827LGOB0")
        except BaseException as error:
            errors.append(error)

    thread = threading.Thread(target=request)
    thread.start()
    assert boxscore_started.wait(timeout=1)
    try:
        thread.join(timeout=0.2)
        assert not thread.is_alive()
    finally:
        boxscore_release.set()
        thread.join(timeout=2)

    assert len(errors) == 1
    assert str(errors[0]) == "lineup unavailable"


def test_boxscore_failure_does_not_wait_for_lineup_future(tmp_path) -> None:
    barrier = threading.Barrier(2)
    lineup_started = threading.Event()
    lineup_release = threading.Event()
    errors = []

    class BlockingLineupCrawler:
        def get_lineup(self, game_id: str):
            barrier.wait(timeout=0.5)
            lineup_started.set()
            assert lineup_release.wait(timeout=2)
            return _StubLineupCrawler().get_lineup(game_id)

    class FailingBoxscoreCrawler:
        def get_boxscore(self, game_id: str):
            barrier.wait(timeout=0.5)
            raise RuntimeError("boxscore unavailable")

    service = LineupService(
        lineup_crawler=BlockingLineupCrawler(),
        boxscore_crawler=FailingBoxscoreCrawler(),
        main_crawler=_StubMainCrawler(),
        snapshot_store=JsonSnapshotStore(base_dir=str(tmp_path)),
        player_stats_service=_EmptyPlayerStatsService(),
        today_provider=lambda: date(2026, 8, 28),
    )

    def request() -> None:
        try:
            service.get_lineup("20260827LGOB0")
        except BaseException as error:
            errors.append(error)

    thread = threading.Thread(target=request)
    thread.start()
    assert lineup_started.wait(timeout=1)
    try:
        thread.join(timeout=0.2)
        assert not thread.is_alive()
    finally:
        lineup_release.set()
        thread.join(timeout=2)

    assert len(errors) == 1
    assert str(errors[0]) == "boxscore unavailable"


def test_historical_lineup_does_not_block_on_optional_player_enrichment(tmp_path) -> None:
    game_id = "20260827LGOB0"

    class BlockingPlayerStatsService:
        def __init__(self) -> None:
            self.started = threading.Event()
            self.release = threading.Event()

        def get_team_players(self, team_id: str, season: int):
            self.started.set()
            assert self.release.wait(timeout=2)
            return {"teamId": team_id, "season": season, "players": []}

    player_stats = BlockingPlayerStatsService()
    service = LineupService(
        lineup_crawler=_StubLineupCrawler(),
        boxscore_crawler=_StubBoxscoreCrawler(),
        main_crawler=_StubMainCrawler(),
        snapshot_store=JsonSnapshotStore(base_dir=str(tmp_path)),
        player_stats_service=player_stats,
        today_provider=lambda: date(2026, 8, 28),
    )

    with concurrent.futures.ThreadPoolExecutor(max_workers=1) as executor:
        request = executor.submit(service.get_lineup, game_id)
        assert player_stats.started.wait(timeout=1)
        try:
            payload = request.result(timeout=1)
        finally:
            player_stats.release.set()

    assert payload["away"]["lineup"][0]["name"] == "홍창기"
    assert payload["home"]["lineup"][0]["name"] == "박준영"


def test_lineup_starter_images_are_built_from_main_game(tmp_path) -> None:
    service = LineupService(
        lineup_crawler=_StubLineupCrawler(),
        boxscore_crawler=_StubBoxscoreCrawler(),
        main_crawler=_StubMainCrawler(),
        snapshot_store=JsonSnapshotStore(base_dir=str(tmp_path)),
        player_stats_service=_StubPlayerStatsService(),
    )

    payload = service.get_lineup("20260425LGOB0")

    assert payload["away"]["starter"]["id"] == "55130"
    assert payload["away"]["starter"]["name"] == "톨허스트"
    assert payload["away"]["starter"]["imageUrl"].endswith("/2026/55130.jpg")
    assert payload["home"]["starter"]["id"] == "55268"
    assert payload["home"]["starter"]["name"] == "최민석"
    assert payload["home"]["starter"]["imageUrl"].endswith("/2026/55268.jpg")


def test_lineup_uses_shared_main_source_for_starter_metadata(tmp_path) -> None:
    main_source = KboSourceCache(
        lambda date: _StubMainCrawler().get_kbo_game_list(date),
        ttl_seconds=8,
    )
    service = LineupService(
        lineup_crawler=_StubLineupCrawler(),
        boxscore_crawler=_StubBoxscoreCrawler(),
        main_crawler=_FailingMainCrawler(),
        main_source=main_source,
        snapshot_store=JsonSnapshotStore(base_dir=str(tmp_path)),
        player_stats_service=_EmptyPlayerStatsService(),
    )

    payload = service.get_lineup("20260425LGOB0")

    assert payload["away"]["starter"]["id"] == "55130"
    assert payload["home"]["starter"]["id"] == "55268"


def test_lineup_rows_are_enriched_with_player_images(tmp_path) -> None:
    service = LineupService(
        lineup_crawler=_StubLineupCrawler(),
        boxscore_crawler=_StubBoxscoreCrawler(),
        main_crawler=_StubMainCrawler(),
        snapshot_store=JsonSnapshotStore(base_dir=str(tmp_path)),
        player_stats_service=_StubPlayerStatsService(),
    )

    payload = service.get_lineup("20260425LGOB0")

    assert payload["away"]["lineup"][0]["id"] == "78224"
    assert payload["away"]["lineup"][0]["imageUrl"] == "https://img.test/2026/78224.jpg"
    assert payload["home"]["lineup"][0]["id"] == "66203"
    assert payload["home"]["lineup"][0]["imageUrl"] == "https://img.test/2026/66203.jpg"


def test_lineup_service_uses_snapshot_first_for_past_game(tmp_path) -> None:
    class FailingLineupCrawler:
        def get_lineup(self, game_id: str):
            raise AssertionError("lineup crawler should not be called")

    class FailingBoxscoreCrawler:
        def get_boxscore(self, game_id: str):
            raise AssertionError("boxscore crawler should not be called")

    snapshot_store = JsonSnapshotStore(base_dir=str(tmp_path))
    snapshot_store.save(
        "lineup",
        "20260425LGOB0",
        {
            "gameId": "20260425LGOB0",
            "away": {"teamId": "LG", "lineup": [{"name": "홍창기"}]},
            "home": {"teamId": "OB", "lineup": [{"name": "박준영"}]},
        },
    )
    service = LineupService(
        lineup_crawler=FailingLineupCrawler(),
        boxscore_crawler=FailingBoxscoreCrawler(),
        main_crawler=_StubMainCrawler(),
        snapshot_store=snapshot_store,
        player_stats_service=_EmptyPlayerStatsService(),
    )

    payload = service.get_lineup("20260425LGOB0")

    assert payload["away"]["lineup"] == [{"name": "홍창기"}]
    assert payload["home"]["lineup"] == [{"name": "박준영"}]


def test_lineup_service_rejects_snapshot_for_another_game(tmp_path) -> None:
    class FailingLineupCrawler:
        def get_lineup(self, game_id: str):
            raise RuntimeError("lineup unavailable")

    class FailingBoxscoreCrawler:
        def get_boxscore(self, game_id: str):
            return {
                "gameId": game_id,
                "away": {"pitchers": []},
                "home": {"pitchers": []},
            }

    game_id = "20260425LGOB0"
    snapshot_store = JsonSnapshotStore(base_dir=str(tmp_path))
    snapshot_store.save(
        "lineup",
        game_id,
        {
            "gameId": "20260424KTLG0",
            "away": {"teamId": "KT", "lineup": [{"name": "잘못된 원정"}]},
            "home": {"teamId": "LG", "lineup": [{"name": "잘못된 홈"}]},
        },
    )
    service = LineupService(
        lineup_crawler=FailingLineupCrawler(),
        boxscore_crawler=FailingBoxscoreCrawler(),
        snapshot_store=snapshot_store,
        today_provider=lambda: date(2026, 5, 1),
    )

    with pytest.raises(RuntimeError, match="lineup unavailable"):
        service.get_lineup(game_id)


def test_lineup_service_ignores_malformed_historical_snapshot(tmp_path) -> None:
    class FailingLineupCrawler:
        def get_lineup(self, game_id: str):
            raise RuntimeError("lineup unavailable")

    class FailingBoxscoreCrawler:
        def get_boxscore(self, game_id: str):
            return {
                "gameId": game_id,
                "away": {"pitchers": []},
                "home": {"pitchers": []},
            }

    game_id = "20260425LGOB0"
    snapshot_store = JsonSnapshotStore(base_dir=str(tmp_path))
    snapshot_store.save("lineup", game_id, [])
    service = LineupService(
        lineup_crawler=FailingLineupCrawler(),
        boxscore_crawler=FailingBoxscoreCrawler(),
        snapshot_store=snapshot_store,
        today_provider=lambda: date(2026, 5, 1),
    )

    with pytest.raises(RuntimeError, match="lineup unavailable"):
        service.get_lineup(game_id)


def test_lineup_service_enriches_past_snapshot_with_missing_player_images(tmp_path) -> None:
    class FailingLineupCrawler:
        def get_lineup(self, game_id: str):
            raise AssertionError("lineup crawler should not be called")

    class FailingBoxscoreCrawler:
        def get_boxscore(self, game_id: str):
            raise AssertionError("boxscore crawler should not be called")

    snapshot_store = JsonSnapshotStore(base_dir=str(tmp_path))
    snapshot_store.save(
        "lineup",
        "20260425LGOB0",
        {
            "gameId": "20260425LGOB0",
            "away": {"teamId": "LG", "lineup": [{"name": "홍창기"}]},
            "home": {"teamId": "OB", "lineup": [{"name": "박준영"}]},
        },
    )
    service = LineupService(
        lineup_crawler=FailingLineupCrawler(),
        boxscore_crawler=FailingBoxscoreCrawler(),
        main_crawler=_StubMainCrawler(),
        snapshot_store=snapshot_store,
        player_stats_service=_StubPlayerStatsService(),
    )

    payload = service.get_lineup("20260425LGOB0")

    assert payload["away"]["lineup"][0]["id"] == "78224"
    assert payload["away"]["lineup"][0]["imageUrl"] == "https://img.test/2026/78224.jpg"
    assert payload["home"]["lineup"][0]["id"] == "66203"
    assert payload["home"]["lineup"][0]["imageUrl"] == "https://img.test/2026/66203.jpg"
    saved = snapshot_store.load_payload("lineup", "20260425LGOB0")
    assert saved["away"]["lineup"][0]["id"] == "78224"


def test_lineup_service_does_not_use_snapshot_for_current_game_failure(tmp_path) -> None:
    class FailingLineupCrawler:
        def get_lineup(self, game_id: str):
            raise RuntimeError("lineup unavailable")

    class FailingBoxscoreCrawler:
        def get_boxscore(self, game_id: str):
            return {
                "gameId": game_id,
                "away": {"pitchers": []},
                "home": {"pitchers": []},
            }

    snapshot_store = JsonSnapshotStore(base_dir=str(tmp_path))
    snapshot_store.save(
        "lineup",
        "29990101LGOB0",
        {
            "gameId": "29990101LGOB0",
            "away": {"teamId": "LG", "lineup": [{"name": "홍창기"}]},
            "home": {"teamId": "OB", "lineup": [{"name": "박준영"}]},
        },
    )
    service = LineupService(
        lineup_crawler=FailingLineupCrawler(),
        boxscore_crawler=FailingBoxscoreCrawler(),
        main_crawler=_StubMainCrawler(),
        snapshot_store=snapshot_store,
    )

    with pytest.raises(RuntimeError, match="lineup unavailable"):
        service.get_lineup("29990101LGOB0")


def test_lineup_query_does_not_emit_lineup_opened_push(tmp_path) -> None:
    service = LineupService(
        lineup_crawler=_StubLineupCrawler(),
        boxscore_crawler=_StubBoxscoreCrawler(),
        main_crawler=_StubMainCrawler(),
        snapshot_store=JsonSnapshotStore(base_dir=str(tmp_path)),
        player_stats_service=_StubPlayerStatsService(),
        today_provider=lambda: date(2026, 4, 25),
    )

    payload = service.get_lineup("20260425LGOB0")

    assert payload["gameId"] == "20260425LGOB0"
    assert not (tmp_path / "push_registry.json").exists()
