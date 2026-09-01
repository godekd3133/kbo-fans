from __future__ import annotations

from kbo_fans_backend.scheduler.live_game_data_loop import LiveGameDataWarmer
from kbo_fans_backend.services.live_game_data import LiveGameDataWarmService
from kbo_fans_backend.services.relay import RelayService
from kbo_fans_backend.services.scoreboard import ScoreboardService
from kbo_fans_backend.storage import JsonSnapshotStore


def _official_boxscore(game_id: str) -> dict:
    return {
        "gameId": game_id,
        "availability": "official",
        "officialAvailable": True,
        "liveContextAvailable": False,
        "source": "official_endpoint",
        "away": {
            "teamId": game_id[8:10],
            "batters": [{"name": "A", "atBats": 4, "hits": 1}],
            "pitchers": [{"name": "P", "innings": "1.0"}],
        },
        "home": {
            "teamId": game_id[10:12],
            "batters": [{"name": "B", "atBats": 3, "hits": 1}],
            "pitchers": [{"name": "Q", "innings": "1.0"}],
        },
    }


def _lineup(game_id: str) -> dict:
    return {
        "gameId": game_id,
        "away": {"teamId": game_id[8:10], "lineup": [{"name": "A"}]},
        "home": {"teamId": game_id[10:12], "lineup": [{"name": "B"}]},
    }


def _relay(game_id: str) -> dict:
    return {
        "gameId": game_id,
        "currentAtBat": None,
        "relayItems": [
            {
                "seqNo": 1,
                "inning": 1,
                "half": "top",
                "event": "HIT",
                "isScoring": False,
                "text": "A: 안타",
                "pitchSequence": "B-S-HIT",
            }
        ],
    }


def test_snapshot_store_reads_fresh_runtime_payload_and_rejects_stale_payload(tmp_path) -> None:
    store = JsonSnapshotStore(base_dir=str(tmp_path))
    store.save("runtime_test", "fresh", {"value": 1})

    assert store.load_recent_payload("runtime_test", "fresh", 60) == {"value": 1}

    stale_path = tmp_path / "runtime_test" / "stale.json"
    stale_path.parent.mkdir(parents=True, exist_ok=True)
    stale_path.write_text(
        '{"savedAt":"2000-01-01T00:00:00+00:00","payload":{"value":2}}',
        encoding="utf-8",
    )

    assert store.load_recent_payload("runtime_test", "stale", 60) is None


def test_boxscore_uses_shared_runtime_snapshot_before_crawling(tmp_path) -> None:
    from kbo_fans_backend.services.boxscore import BoxscoreService

    game_id = "20260901KTLG0"
    expected = _official_boxscore(game_id)
    store = JsonSnapshotStore(base_dir=str(tmp_path))
    store.save("runtime_boxscore", game_id, expected)

    class FailingCrawler:
        def get_boxscore(self, _game_id: str):
            raise AssertionError("runtime snapshot should be returned")

    class Schedule:
        def get_schedule_game(self, _game_id: str):
            return {"gameId": game_id, "status": "LIVE"}

    service = BoxscoreService(
        crawler=FailingCrawler(),
        schedule_service=Schedule(),
        snapshot_store=store,
        runtime_cache_max_age_seconds=60,
    )

    assert service.get_boxscore(game_id) == expected


def test_game_summary_uses_shared_runtime_snapshot_before_crawling(tmp_path) -> None:
    game_id = "20260901KTLG0"
    expected = {
        "gameId": game_id,
        "status": "LIVE",
        "away": {"teamId": "KT", "score": 1},
        "home": {"teamId": "LG", "score": 2},
    }
    store = JsonSnapshotStore(base_dir=str(tmp_path))
    store.save("runtime_games", game_id, expected)

    class FailingCrawler:
        def get_games_by_date(self, _date: str):
            raise AssertionError("runtime snapshot should be returned")

    service = ScoreboardService(
        schedule_crawler=FailingCrawler(),
        snapshot_store=store,
        runtime_cache_max_age_seconds=60,
    )

    assert service.get_game(game_id) == expected


def test_relay_uses_shared_runtime_snapshot_before_crawling(tmp_path) -> None:
    game_id = "20260901KTLG0"
    expected = _relay(game_id)
    store = JsonSnapshotStore(base_dir=str(tmp_path))
    store.save("runtime_relay", game_id, expected)

    class FailingCrawler:
        def get_relay(self, _game_id: str):
            raise AssertionError("runtime snapshot should be returned")

    class Scoreboard:
        def get_game(self, _game_id: str, force_refresh: bool = False):
            raise AssertionError("runtime snapshot should avoid game lookup")

    service = RelayService(
        relay_crawler=FailingCrawler(),
        scoreboard_service=Scoreboard(),
        snapshot_store=store,
        runtime_cache_max_age_seconds=60,
    )

    assert service.get_relay(game_id) == expected


def test_lineup_uses_shared_runtime_snapshot_before_crawling(tmp_path) -> None:
    from kbo_fans_backend.services.lineup import LineupService

    game_id = "20260901KTLG0"
    expected = _lineup(game_id)
    store = JsonSnapshotStore(base_dir=str(tmp_path))
    store.save("runtime_lineup", game_id, expected)

    class FailingLineupCrawler:
        def get_lineup(self, _game_id: str):
            raise AssertionError("runtime snapshot should be returned")

    class FailingBoxscoreCrawler:
        def get_boxscore(self, _game_id: str):
            raise AssertionError("runtime snapshot should avoid boxscore lookup")

    service = LineupService(
        lineup_crawler=FailingLineupCrawler(),
        boxscore_crawler=FailingBoxscoreCrawler(),
        snapshot_store=store,
        runtime_cache_max_age_seconds=60,
    )

    assert service.get_lineup(game_id) == expected


class _FakeScoreboard:
    def __init__(self, statuses):
        self.statuses = statuses
        self.calls = []

    def get_game(self, game_id: str, force_refresh: bool = False):
        self.calls.append((game_id, force_refresh))
        return {"gameId": game_id, "status": self.statuses[game_id]}


class _FakeRelay:
    def __init__(self):
        self.calls = []

    def get_relay(self, game_id: str, force_refresh: bool = False):
        self.calls.append((game_id, force_refresh))
        return _relay(game_id)

    @staticmethod
    def is_complete_payload(game_id: str, payload) -> bool:
        return isinstance(payload, dict) and payload.get("gameId") == game_id


class _FakeBoxscore:
    def __init__(self):
        self.calls = []

    def get_boxscore(self, game_id: str, force_refresh: bool = False):
        self.calls.append((game_id, force_refresh))
        return _official_boxscore(game_id)

    @staticmethod
    def is_complete_payload(game_id: str, payload) -> bool:
        return isinstance(payload, dict) and payload.get("gameId") == game_id


class _FakeLineup:
    def __init__(self):
        self.calls = []

    def get_lineup(self, game_id: str, force_refresh: bool = False):
        self.calls.append((game_id, force_refresh))
        return _lineup(game_id)

    @staticmethod
    def is_complete_payload(game_id: str, payload) -> bool:
        return isinstance(payload, dict) and payload.get("gameId") == game_id


def test_live_game_data_warm_service_retries_live_and_finalizes_once() -> None:
    live_id = "20260901KTLG0"
    final_id = "20260901LGOB0"
    scoreboard = _FakeScoreboard({live_id: "LIVE", final_id: "FINAL"})
    relay = _FakeRelay()
    boxscore = _FakeBoxscore()
    lineup = _FakeLineup()
    service = LiveGameDataWarmService(
        scoreboard_service=scoreboard,
        relay_service=relay,
        boxscore_service=boxscore,
        lineup_service=lineup,
    )

    first = service.warm_games(
        [{"gameId": live_id, "status": "LIVE"}, {"gameId": final_id, "status": "FINAL"}]
    )
    second = service.warm_games(
        [{"gameId": live_id, "status": "LIVE"}, {"gameId": final_id, "status": "FINAL"}]
    )

    assert first["liveGames"] == 1
    assert first["finalizedGames"] == 1
    assert second["liveGames"] == 1
    assert second["finalizedGames"] == 0
    assert scoreboard.calls == [
        (live_id, True),
        (final_id, True),
        (live_id, True),
    ]
    assert len(relay.calls) == 3
    assert len(boxscore.calls) == 3
    assert len(lineup.calls) == 3


def test_live_game_data_warmer_adapts_interval_without_overlap() -> None:
    warmer = LiveGameDataWarmer(
        scoreboard_service=object(),
        game_data_service=object(),
        interval_seconds=15,
        max_interval_seconds=60,
        interval_margin=0.5,
        date_provider=lambda: "2026-09-01",
    )

    assert warmer.interval_for_cycle(0.5) == 15
    assert warmer.interval_for_cycle(20) == 30
    assert warmer.interval_for_cycle(100) == 60
