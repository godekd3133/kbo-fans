from datetime import date as date_type
from datetime import timedelta

import pytest

from kbo_fans_backend.services.boxscore import BoxscoreService
from kbo_fans_backend.storage import JsonSnapshotStore


class _StubBoxscoreCrawler:
    def __init__(self):
        self.calls = []

    def get_boxscore(self, game_id: str):
        self.calls.append(game_id)
        if game_id == "20260330KTLG0":
            return {
                "gameId": game_id,
                "away": {"teamId": "KT", "batters": [], "pitchers": []},
                "home": {"teamId": "LG", "batters": [], "pitchers": []},
            }
        return {
            "gameId": game_id,
            "away": {
                "teamId": "KT",
                "batters": [{"name": "A"}],
                "pitchers": [{"name": "P"}],
            },
            "home": {
                "teamId": "LG",
                "batters": [{"name": "B"}],
                "pitchers": [{"name": "Q"}],
            },
        }


class _StubScheduleService:
    def get_month_schedule(self, month: str):
        return {
            "month": month,
            "days": [
                {
                    "date": "2026-03-29",
                    "games": [
                        {
                            "gameId": "20260329KTLG0",
                            "awayId": "KT",
                            "homeId": "LG",
                        }
                    ],
                }
            ],
        }


def test_boxscore_service_retries_with_adjacent_canonical_game_id(tmp_path) -> None:
    crawler = _StubBoxscoreCrawler()
    service = BoxscoreService(
        crawler=crawler,
        schedule_service=_StubScheduleService(),
        snapshot_store=JsonSnapshotStore(base_dir=str(tmp_path)),
    )

    payload = service.get_boxscore("20260330KTLG0")

    assert crawler.calls == ["20260330KTLG0", "20260329KTLG0"]
    assert payload["gameId"] == "20260330KTLG0"
    assert payload["sourceGameId"] == "20260329KTLG0"
    assert payload["away"]["batters"] == [{"name": "A"}]
    assert payload["home"]["pitchers"] == [{"name": "Q"}]


def test_boxscore_service_does_not_retry_adjacent_game_for_current_game(
    tmp_path,
) -> None:
    today = date_type.today()
    today_game_id = f"{today:%Y%m%d}SKWO0"
    yesterday_game_id = f"{today - timedelta(days=1):%Y%m%d}SKWO0"

    class CurrentGameCrawler:
        def __init__(self):
            self.calls = []

        def get_boxscore(self, game_id: str):
            self.calls.append(game_id)
            if game_id == today_game_id:
                return {
                    "gameId": game_id,
                    "officialAvailable": False,
                    "away": {"teamId": "SK", "batters": [], "pitchers": []},
                    "home": {"teamId": "WO", "batters": [], "pitchers": []},
                }
            return {
                "gameId": game_id,
                "officialAvailable": True,
                "away": {
                    "teamId": "SK",
                    "batters": [{"name": "old"}],
                    "pitchers": [],
                },
                "home": {
                    "teamId": "WO",
                    "batters": [],
                    "pitchers": [{"name": "old"}],
                },
            }

    class CurrentScheduleService:
        def get_month_schedule(self, month: str):
            return {
                "month": month,
                "days": [
                    {
                        "date": (today - timedelta(days=1)).isoformat(),
                        "games": [
                            {
                                "gameId": yesterday_game_id,
                                "awayId": "SK",
                                "homeId": "WO",
                            }
                        ],
                    }
                ],
            }

    crawler = CurrentGameCrawler()
    service = BoxscoreService(
        crawler=crawler,
        schedule_service=CurrentScheduleService(),
        snapshot_store=JsonSnapshotStore(base_dir=str(tmp_path)),
    )

    payload = service.get_boxscore(today_game_id)

    assert crawler.calls == [today_game_id]
    assert payload["gameId"] == today_game_id
    assert payload["officialAvailable"] is False
    assert payload["away"]["batters"] == []


def test_boxscore_service_uses_snapshot_first_for_past_game(tmp_path) -> None:
    class FailingCrawler:
        def get_boxscore(self, game_id: str):
            raise AssertionError("crawler should not be called")

    snapshot_store = JsonSnapshotStore(base_dir=str(tmp_path))
    snapshot_store.save(
        "boxscore",
        "20260330KTLG0",
        {
            "gameId": "20260330KTLG0",
            "away": {"teamId": "KT", "batters": [{"name": "A"}], "pitchers": []},
            "home": {"teamId": "LG", "batters": [], "pitchers": [{"name": "P"}]},
        },
    )
    service = BoxscoreService(
        crawler=FailingCrawler(),
        snapshot_store=snapshot_store,
    )

    payload = service.get_boxscore("20260330KTLG0")

    assert payload["away"]["batters"] == [{"name": "A"}]
    assert payload["home"]["pitchers"] == [{"name": "P"}]


def test_boxscore_service_marks_empty_payload_as_not_official() -> None:
    class EmptyCrawler:
        def get_boxscore(self, game_id: str):
            return {
                "gameId": game_id,
                "officialAvailable": False,
                "away": {"teamId": "OB", "batters": [], "pitchers": []},
                "home": {"teamId": "SS", "batters": [], "pitchers": []},
            }

    class EmptyScheduleService:
        def get_month_schedule(self, month: str):
            return {"month": month, "days": []}

    service = BoxscoreService(
        crawler=EmptyCrawler(),
        schedule_service=EmptyScheduleService(),
    )

    payload = service.get_boxscore("20260330OBSS0")

    assert payload["officialAvailable"] is False
    assert payload["away"]["batters"] == []
    assert payload["home"]["pitchers"] == []


def test_boxscore_service_does_not_use_snapshot_for_current_game_failure(tmp_path) -> None:
    class FailingCrawler:
        def get_boxscore(self, game_id: str):
            raise RuntimeError("boxscore unavailable")

    snapshot_store = JsonSnapshotStore(base_dir=str(tmp_path))
    snapshot_store.save(
        "boxscore",
        "29990101KTLG0",
        {
            "gameId": "29990101KTLG0",
            "away": {"teamId": "KT", "batters": [{"name": "A"}], "pitchers": []},
            "home": {"teamId": "LG", "batters": [], "pitchers": [{"name": "P"}]},
        },
    )
    service = BoxscoreService(
        crawler=FailingCrawler(),
        snapshot_store=snapshot_store,
    )

    with pytest.raises(RuntimeError, match="boxscore unavailable"):
        service.get_boxscore("29990101KTLG0")


def test_boxscore_service_does_not_snapshot_live_context_payload(tmp_path) -> None:
    class LiveContextCrawler:
        def get_boxscore(self, game_id: str):
            return {
                "gameId": game_id,
                "officialAvailable": False,
                "liveContextAvailable": True,
                "away": {
                    "teamId": "OB",
                    "batters": [
                        {
                            "name": "양석환",
                            "liveContext": True,
                            "contextLabel": "3회초 현재 타자",
                        }
                    ],
                    "pitchers": [],
                },
                "home": {
                    "teamId": "LG",
                    "batters": [],
                    "pitchers": [
                        {
                            "name": "임찬규",
                            "liveContext": True,
                            "decision": "LIVE",
                            "contextLabel": "3회초 현재 투수",
                        }
                    ],
                },
            }

    snapshot_store = JsonSnapshotStore(base_dir=str(tmp_path))
    service = BoxscoreService(
        crawler=LiveContextCrawler(),
        snapshot_store=snapshot_store,
    )

    payload = service.get_boxscore("20260620OBLG0")

    assert payload["liveContextAvailable"] is True
    assert snapshot_store.load_payload("boxscore", "20260620OBLG0") is None
