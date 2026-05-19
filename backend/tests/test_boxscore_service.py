from kbo_fans_backend.services.boxscore import BoxscoreService


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


def test_boxscore_service_retries_with_adjacent_canonical_game_id() -> None:
    crawler = _StubBoxscoreCrawler()
    service = BoxscoreService(
        crawler=crawler,
        schedule_service=_StubScheduleService(),
    )

    payload = service.get_boxscore("20260330KTLG0")

    assert crawler.calls == ["20260330KTLG0", "20260329KTLG0"]
    assert payload["away"]["batters"] == [{"name": "A"}]
    assert payload["home"]["pitchers"] == [{"name": "Q"}]


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
