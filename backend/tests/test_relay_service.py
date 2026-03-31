from kbo_fans_backend.services.relay import RelayService


class _StubScoreboardService:
    def __init__(self, game):
        self._game = game

    def get_game(self, game_id: str):
        return self._game


class _FailingRelayCrawler:
    def get_relay(self, game_id: str):
        raise RuntimeError("relay unavailable")


def test_relay_service_builds_summary_items_for_final_game() -> None:
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
        )
    )

    relay = service.get_relay("20260329LTSS0")

    assert relay["currentAtBat"] is None
    assert relay["relayItems"][0]["text"] == "4회초 롯데 1득점"
    assert relay["relayItems"][1]["text"] == "5회초 롯데 1득점"
    assert relay["relayItems"][2]["text"] == "5회말 삼성 1득점"
    assert relay["relayItems"][3]["text"] == "7회초 롯데 4득점"
    assert relay["relayItems"][4]["text"] == "7회말 삼성 1득점"
    assert relay["relayItems"][-1]["event"] == "GAME_END"


def test_relay_service_builds_current_at_bat_for_live_game() -> None:
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
        )
    )

    relay = service.get_relay("20260330KTLG0")

    assert relay["currentAtBat"]["batter"]["name"] == "홍길동"
    assert relay["currentAtBat"]["pitcher"]["name"] == "김투수"
    assert relay["currentAtBat"]["ballCount"] == {
        "balls": 2,
        "strikes": 1,
        "outs": 1,
    }


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
