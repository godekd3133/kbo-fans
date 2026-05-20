from kbo_fans_backend.services.lineup import LineupService
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


class _NoopPushService:
    def send_lineup_opened(self, **kwargs):
        return None


def test_lineup_starter_images_are_built_from_main_game(tmp_path) -> None:
    service = LineupService(
        lineup_crawler=_StubLineupCrawler(),
        boxscore_crawler=_StubBoxscoreCrawler(),
        main_crawler=_StubMainCrawler(),
        snapshot_store=JsonSnapshotStore(base_dir=str(tmp_path)),
        push_service=_NoopPushService(),
    )

    payload = service.get_lineup("20260425LGOB0")

    assert payload["away"]["starter"]["id"] == "55130"
    assert payload["away"]["starter"]["name"] == "톨허스트"
    assert payload["away"]["starter"]["imageUrl"].endswith("/2026/55130.jpg")
    assert payload["home"]["starter"]["id"] == "55268"
    assert payload["home"]["starter"]["name"] == "최민석"
    assert payload["home"]["starter"]["imageUrl"].endswith("/2026/55268.jpg")


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
    )

    payload = service.get_lineup("20260425LGOB0")

    assert payload["away"]["lineup"] == [{"name": "홍창기"}]
    assert payload["home"]["lineup"] == [{"name": "박준영"}]
