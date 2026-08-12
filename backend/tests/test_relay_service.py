from pathlib import Path

import pytest

from kbo_fans_backend.services.relay import RelayService
from kbo_fans_backend.storage import JsonSnapshotStore
from kbo_fans_backend.utils.kbo_time import current_kbo_date


class _StubScoreboardService:
    def __init__(self, game):
        self._game = game
        self.force_refresh = False

    def get_game(self, game_id: str, force_refresh: bool = False):
        self.force_refresh = force_refresh
        return self._game


class _FailingRelayCrawler:
    def get_relay(self, game_id: str):
        raise RuntimeError("relay unavailable")


class _StubRelayCrawler:
    def __init__(self, payload):
        self._payload = payload

    def get_relay(self, game_id: str):
        return self._payload


def test_relay_service_builds_summary_items_for_final_game(tmp_path: Path) -> None:
    service = RelayService(
        relay_crawler=_FailingRelayCrawler(),
        scoreboard_service=_StubScoreboardService(
            {
                "gameId": "20260329LTSS0",
                "status": "FINAL",
                "away": {
                    "shortName": "롯데",
                    "score": 6,
                    "scores": [0, 0, 0, 1, 1, 0, 4, 0, 0],
                },
                "home": {
                    "shortName": "삼성",
                    "score": 2,
                    "scores": [0, 0, 0, 0, 1, 0, 1, 0, 0],
                },
            }
        ),
        snapshot_store=JsonSnapshotStore(base_dir=str(tmp_path / "snapshots")),
    )

    relay = service.get_relay("20260329LTSS0")

    assert relay["currentAtBat"] is None
    assert relay["relayItems"][0]["text"] == "4회초 롯데 1득점"
    assert relay["relayItems"][1]["text"] == "5회초 롯데 1득점"
    assert relay["relayItems"][2]["text"] == "5회말 삼성 1득점"
    assert relay["relayItems"][3]["text"] == "7회초 롯데 4득점"
    assert relay["relayItems"][4]["text"] == "7회말 삼성 1득점"
    assert relay["relayItems"][-1]["event"] == "GAME_END"


def test_relay_service_ignores_malformed_historical_snapshot(tmp_path: Path) -> None:
    game_id = "20260329LTSS0"
    store = JsonSnapshotStore(base_dir=str(tmp_path / "snapshots"))
    store.save("relay", game_id, [])
    service = RelayService(
        relay_crawler=_FailingRelayCrawler(),
        scoreboard_service=_StubScoreboardService(
            {"gameId": game_id, "status": "FINAL", "away": {}, "home": {}}
        ),
        snapshot_store=store,
    )

    relay = service.get_relay(game_id)

    assert relay["gameId"] == game_id
    assert relay["currentAtBat"] is None


def test_relay_service_summary_items_normalize_team_codes(tmp_path: Path) -> None:
    service = RelayService(
        relay_crawler=_FailingRelayCrawler(),
        scoreboard_service=_StubScoreboardService(
            {
                "gameId": "20260624SSSK0",
                "status": "FINAL",
                "away": {
                    "teamId": "SS",
                    "shortName": "SS",
                    "score": 1,
                    "scores": [1],
                },
                "home": {
                    "teamId": "SK",
                    "shortName": "SK",
                    "score": 2,
                    "scores": [2],
                },
            }
        ),
        snapshot_store=JsonSnapshotStore(base_dir=str(tmp_path / "snapshots")),
    )

    relay = service.get_relay("20260624SSSK0")

    assert relay["relayItems"][0]["text"] == "1회초 삼성 1득점"
    assert relay["relayItems"][1]["text"] == "1회말 SSG 2득점"


def test_relay_service_does_not_summary_fallback_for_live_game() -> None:
    service = RelayService(
        relay_crawler=_FailingRelayCrawler(),
        scoreboard_service=_StubScoreboardService(
            {
                "gameId": "20260330KTLG0",
                "status": "LIVE",
                "current": {
                    "balls": 2,
                    "strikes": 1,
                    "outs": 1,
                    "batterName": "홍길동",
                    "pitcherName": "김투수",
                },
                "away": {"shortName": "KT", "score": 1, "scores": [1]},
                "home": {"shortName": "LG", "score": 0, "scores": [0]},
            }
        ),
    )

    with pytest.raises(RuntimeError, match="relay unavailable"):
        service.get_relay("20260330KTLG0")


def test_relay_service_does_not_hide_crawler_failure_when_game_is_unknown(
    tmp_path: Path,
) -> None:
    service = RelayService(
        relay_crawler=_FailingRelayCrawler(),
        scoreboard_service=_StubScoreboardService(None),
        snapshot_store=JsonSnapshotStore(base_dir=str(tmp_path / "snapshots")),
    )

    with pytest.raises(RuntimeError, match="relay unavailable"):
        service.get_relay("20260719KTLG0")


def test_relay_service_forwards_force_refresh_to_game_lookup() -> None:
    scoreboard = _StubScoreboardService(
        {
            "gameId": "20260719KTLG0",
            "status": "LIVE",
            "away": {"shortName": "KT", "score": 1, "scores": [1]},
            "home": {"shortName": "LG", "score": 0, "scores": [0]},
        }
    )
    service = RelayService(
        relay_crawler=_StubRelayCrawler(
            {
                "gameId": "20260719KTLG0",
                "currentAtBat": None,
                "relayItems": [
                    {
                        "seqNo": 1,
                        "inning": 1,
                        "half": "top",
                        "event": "HIT",
                        "isScoring": False,
                        "text": "강백호: 중전 안타",
                        "pitchSequence": None,
                    }
                ],
            }
        ),
        scoreboard_service=scoreboard,
    )

    service.get_relay("20260719KTLG0", force_refresh=True)

    assert scoreboard.force_refresh is True


def test_relay_service_uses_full_relay_for_final_game_when_available() -> None:
    service = RelayService(
        relay_crawler=_StubRelayCrawler(
            {
                "gameId": "20260329LTSS0",
                "currentAtBat": None,
                "relayItems": [
                    {
                        "seqNo": 142,
                        "inning": 7,
                        "half": "top",
                        "event": "HIT",
                        "isScoring": True,
                        "text": "나승엽: 2타점 적시 2루타",
                        "pitchSequence": "B-S-F-HIT",
                    },
                    {
                        "seqNo": 141,
                        "inning": 7,
                        "half": "top",
                        "event": "SUBSTITUTION",
                        "isScoring": False,
                        "text": "대타 정훈 : 김민석",
                        "pitchSequence": None,
                    },
                ],
            }
        ),
        scoreboard_service=_StubScoreboardService(
            {
                "gameId": "20260329LTSS0",
                "status": "FINAL",
                "away": {
                    "shortName": "롯데",
                    "score": 6,
                    "scores": [0, 0, 0, 1, 1, 0, 4, 0, 0],
                },
                "home": {
                    "shortName": "삼성",
                    "score": 2,
                    "scores": [0, 0, 0, 0, 1, 0, 1, 0, 0],
                },
            }
        ),
    )

    relay = service.get_relay("20260329LTSS0")

    assert relay["relayItems"][0]["event"] == "HIT"
    assert relay["relayItems"][0]["text"] == "나승엽: 2타점 적시 2루타"
    assert relay["relayItems"][1]["event"] == "SUBSTITUTION"


def test_relay_service_clears_current_at_bat_for_final_full_relay() -> None:
    service = RelayService(
        relay_crawler=_StubRelayCrawler(
            {
                "gameId": "20260629SSLG0",
                "currentAtBat": {
                    "inningText": "9회 초",
                    "batter": {"name": "디아즈"},
                    "pitcher": {"name": "손주영"},
                    "ballCount": {"balls": 1, "strikes": 3, "outs": 3},
                    "baseState": "주자없음",
                },
                "relayItems": [
                    {
                        "seqNo": 142,
                        "inning": 9,
                        "half": "top",
                        "event": "OUT",
                        "isScoring": False,
                        "text": "디아즈: 플라이 아웃",
                        "pitchSequence": "B-S-F-OUT",
                    }
                ],
            }
        ),
        scoreboard_service=_StubScoreboardService(
            {
                "gameId": "20260629SSLG0",
                "status": "FINAL",
                "away": {"shortName": "삼성", "score": 3, "scores": [0]},
                "home": {"shortName": "LG", "score": 4, "scores": [0]},
            }
        ),
    )

    relay = service.get_relay("20260629SSLG0")

    assert relay["currentAtBat"] is None
    assert relay["relayItems"][0]["event"] == "OUT"


def test_relay_service_clears_current_at_bat_from_final_snapshot(tmp_path: Path) -> None:
    snapshot_store = JsonSnapshotStore(base_dir=str(tmp_path / "snapshots"))
    snapshot_store.save(
        "relay",
        "20260629SSLG0",
        {
            "gameId": "20260629SSLG0",
            "currentAtBat": {
                "inningText": "9회 초",
                "batter": {"name": "디아즈"},
                "pitcher": {"name": "손주영"},
                "ballCount": {"balls": 1, "strikes": 3, "outs": 3},
            },
            "relayItems": [
                {
                    "seqNo": 142,
                    "inning": 9,
                    "half": "top",
                    "event": "OUT",
                    "isScoring": False,
                    "text": "디아즈: 플라이 아웃",
                    "pitchSequence": "B-S-F-OUT",
                }
            ],
        },
    )
    service = RelayService(
        relay_crawler=_FailingRelayCrawler(),
        scoreboard_service=_StubScoreboardService(
            {
                "gameId": "20260629SSLG0",
                "status": "FINAL",
                "away": {"shortName": "삼성", "score": 3, "scores": [0]},
                "home": {"shortName": "LG", "score": 4, "scores": [0]},
            }
        ),
        snapshot_store=snapshot_store,
    )

    relay = service.get_relay("20260629SSLG0")

    assert relay["currentAtBat"] is None
    assert relay["relayItems"][0]["event"] == "OUT"


def test_relay_service_uses_snapshot_first_for_final_game(tmp_path: Path) -> None:
    snapshot_store = JsonSnapshotStore(base_dir=str(tmp_path / "snapshots"))
    snapshot_store.save(
        "relay",
        "20260329LTSS0",
        {
            "gameId": "20260329LTSS0",
            "currentAtBat": None,
            "relayItems": [
                {
                    "seqNo": 10,
                    "inning": 1,
                    "half": "top",
                    "event": "HIT",
                    "isScoring": False,
                    "text": "나승엽 : 우익수 앞 1루타",
                    "pitchSequence": None,
                }
            ],
        },
    )
    service = RelayService(
        relay_crawler=_FailingRelayCrawler(),
        scoreboard_service=_StubScoreboardService(
            {
                "gameId": "20260329LTSS0",
                "status": "FINAL",
                "away": {"shortName": "롯데", "score": 6, "scores": [0]},
                "home": {"shortName": "삼성", "score": 2, "scores": [0]},
            }
        ),
        snapshot_store=snapshot_store,
    )

    relay = service.get_relay("20260329LTSS0")

    assert relay["relayItems"][0]["event"] == "HIT"
    assert relay["relayItems"][0]["text"] == "나승엽 : 우익수 앞 1루타"


def test_relay_service_rejects_snapshot_for_another_game(tmp_path: Path) -> None:
    game_id = "20260329LTSS0"
    snapshot_store = JsonSnapshotStore(base_dir=str(tmp_path / "snapshots"))
    snapshot_store.save(
        "relay",
        game_id,
        {
            "gameId": "20260328KTLG0",
            "currentAtBat": None,
            "relayItems": [
                {
                    "seqNo": 10,
                    "inning": 1,
                    "half": "top",
                    "event": "HIT",
                    "isScoring": False,
                    "text": "잘못된 경기의 안타",
                    "pitchSequence": "B-S-HIT",
                }
            ],
        },
    )
    service = RelayService(
        relay_crawler=_FailingRelayCrawler(),
        scoreboard_service=_StubScoreboardService(
            {
                "gameId": game_id,
                "status": "FINAL",
                "away": {"shortName": "롯데", "score": 6, "scores": [0]},
                "home": {"shortName": "삼성", "score": 2, "scores": [0]},
            }
        ),
        snapshot_store=snapshot_store,
    )

    relay = service.get_relay(game_id)

    assert relay["gameId"] == game_id
    assert all(item["text"] != "잘못된 경기의 안타" for item in relay["relayItems"])


def test_relay_service_ignores_non_dict_relay_items(tmp_path: Path) -> None:
    game_id = "20260329LTSS0"
    snapshot_store = JsonSnapshotStore(base_dir=str(tmp_path / "snapshots"))
    snapshot_store.save(
        "relay",
        game_id,
        {
            "gameId": game_id,
            "currentAtBat": None,
            "relayItems": ["malformed-item"],
        },
    )
    service = RelayService(
        relay_crawler=_FailingRelayCrawler(),
        scoreboard_service=_StubScoreboardService(
            {
                "gameId": game_id,
                "status": "FINAL",
                "away": {"shortName": "롯데", "score": 6, "scores": [0]},
                "home": {"shortName": "삼성", "score": 2, "scores": [0]},
            }
        ),
        snapshot_store=snapshot_store,
    )

    relay = service.get_relay(game_id)

    assert relay["gameId"] == game_id
    assert relay["relayItems"][-1]["event"] == "GAME_END"


def test_relay_service_does_not_use_snapshot_for_current_unknown_game(tmp_path: Path) -> None:
    game_id = f"{current_kbo_date().strftime('%Y%m%d')}LTSS0"
    snapshot_store = JsonSnapshotStore(base_dir=str(tmp_path / "snapshots"))
    snapshot_store.save(
        "relay",
        game_id,
        {
            "gameId": game_id,
            "currentAtBat": None,
            "relayItems": [
                {
                    "seqNo": 10,
                    "inning": 1,
                    "half": "top",
                    "event": "HIT",
                    "isScoring": False,
                    "text": "현재 경기의 오래된 snapshot 안타",
                    "pitchSequence": "B-S-HIT",
                }
            ],
        },
    )
    service = RelayService(
        relay_crawler=_FailingRelayCrawler(),
        scoreboard_service=_StubScoreboardService(
            {
                "gameId": game_id,
                "status": "UNKNOWN",
                "away": {"shortName": "롯데", "score": None, "scores": []},
                "home": {"shortName": "삼성", "score": None, "scores": []},
            }
        ),
        snapshot_store=snapshot_store,
    )

    relay = service.get_relay(game_id)

    assert relay["gameId"] == game_id
    assert all(
        item.get("text") != "현재 경기의 오래된 snapshot 안타"
        for item in relay["relayItems"]
    )


def test_relay_service_skips_crawler_for_scheduled_game() -> None:
    service = RelayService(
        relay_crawler=_FailingRelayCrawler(),
        scoreboard_service=_StubScoreboardService(
            {
                "gameId": "20260331HTLG0",
                "status": "SCHEDULED",
                "away": {"shortName": "KIA", "score": None, "scores": [None]},
                "home": {"shortName": "LG", "score": None, "scores": [None]},
            }
        ),
    )

    relay = service.get_relay("20260331HTLG0")

    assert relay["currentAtBat"] is None
    assert relay["relayItems"] == []
