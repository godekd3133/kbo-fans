import pytest

from kbo_fans_backend.services.lineup import LineupService
from kbo_fans_backend.services.push_registry import PushRegistry
from kbo_fans_backend.storage import JsonSnapshotStore


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


class _NoopPushService:
    def send_lineup_opened(self, **kwargs):
        return None


class _RecordingPushService:
    def __init__(self, registry: PushRegistry) -> None:
        self.registry = registry
        self.calls = []

    def send_lineup_opened(self, **kwargs):
        self.calls.append(kwargs)
        return {"sent": True}


def test_lineup_starter_images_are_built_from_main_game(tmp_path) -> None:
    service = LineupService(
        lineup_crawler=_StubLineupCrawler(),
        boxscore_crawler=_StubBoxscoreCrawler(),
        main_crawler=_StubMainCrawler(),
        snapshot_store=JsonSnapshotStore(base_dir=str(tmp_path)),
        push_service=_NoopPushService(),
        player_stats_service=_StubPlayerStatsService(),
    )

    payload = service.get_lineup("20260425LGOB0")

    assert payload["away"]["starter"]["id"] == "55130"
    assert payload["away"]["starter"]["name"] == "톨허스트"
    assert payload["away"]["starter"]["imageUrl"].endswith("/2026/55130.jpg")
    assert payload["home"]["starter"]["id"] == "55268"
    assert payload["home"]["starter"]["name"] == "최민석"
    assert payload["home"]["starter"]["imageUrl"].endswith("/2026/55268.jpg")


def test_lineup_rows_are_enriched_with_player_images(tmp_path) -> None:
    service = LineupService(
        lineup_crawler=_StubLineupCrawler(),
        boxscore_crawler=_StubBoxscoreCrawler(),
        main_crawler=_StubMainCrawler(),
        snapshot_store=JsonSnapshotStore(base_dir=str(tmp_path)),
        push_service=_NoopPushService(),
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
        push_service=_NoopPushService(),
        player_stats_service=_EmptyPlayerStatsService(),
    )

    payload = service.get_lineup("20260425LGOB0")

    assert payload["away"]["lineup"] == [{"name": "홍창기"}]
    assert payload["home"]["lineup"] == [{"name": "박준영"}]


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
        push_service=_NoopPushService(),
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
            raise RuntimeError("boxscore unavailable")

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
        push_service=_NoopPushService(),
    )

    with pytest.raises(RuntimeError, match="lineup unavailable"):
        service.get_lineup("29990101LGOB0")


def test_lineup_service_marks_lineup_opened_after_push(tmp_path) -> None:
    registry = PushRegistry(str(tmp_path / "push_registry.json"))
    push_service = _RecordingPushService(registry)
    service = LineupService(
        lineup_crawler=_StubLineupCrawler(),
        boxscore_crawler=_StubBoxscoreCrawler(),
        main_crawler=_StubMainCrawler(),
        snapshot_store=JsonSnapshotStore(base_dir=str(tmp_path)),
        push_service=push_service,
        player_stats_service=_StubPlayerStatsService(),
    )

    service.get_lineup("20260425LGOB0")

    assert len(push_service.calls) == 1
    assert registry.pregame_alert_sent("20260425LGOB0", "lineup_opened") is True


def test_lineup_service_skips_lineup_opened_when_scheduler_already_sent(tmp_path) -> None:
    registry = PushRegistry(str(tmp_path / "push_registry.json"))
    registry.mark_pregame_alert_sent("20260425LGOB0", "lineup_opened")
    push_service = _RecordingPushService(registry)
    service = LineupService(
        lineup_crawler=_StubLineupCrawler(),
        boxscore_crawler=_StubBoxscoreCrawler(),
        main_crawler=_StubMainCrawler(),
        snapshot_store=JsonSnapshotStore(base_dir=str(tmp_path)),
        push_service=push_service,
        player_stats_service=_StubPlayerStatsService(),
    )

    service.get_lineup("20260425LGOB0")

    assert push_service.calls == []
