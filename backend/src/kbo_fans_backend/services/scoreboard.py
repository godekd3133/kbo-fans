from __future__ import annotations

from typing import Any, Optional

from kbo_fans_backend.crawlers.main import MainCrawler
from kbo_fans_backend.crawlers.schedule import ScheduleCrawler
from kbo_fans_backend.crawlers.scoreboard import ScoreboardCrawler


class ScoreboardService:
    def __init__(
        self,
        main_crawler: Optional[MainCrawler] = None,
        schedule_crawler: Optional[ScheduleCrawler] = None,
        scoreboard_crawler: Optional[ScoreboardCrawler] = None,
    ) -> None:
        self.main_crawler = main_crawler or MainCrawler()
        self.schedule_crawler = schedule_crawler or ScheduleCrawler()
        self.scoreboard_crawler = scoreboard_crawler or ScoreboardCrawler()

    def get_scoreboard(self, date: str) -> dict[str, Any]:
        games = self.schedule_crawler.get_games_by_date(date)
        game_list = {game["G_ID"]: game for game in self.main_crawler.get_kbo_game_list(date)}
        enriched_games = []
        for game in games:
            detail = self.scoreboard_crawler.get_game_scoreboard(game["gameId"])
            main_game = game_list.get(game["gameId"], {})
            enriched_games.append({**game, **self._merge_main_game(main_game), **detail})

        return {
            "date": date,
            "games": enriched_games,
        }

    def _merge_main_game(self, main_game: dict[str, Any]) -> dict[str, Any]:
        if not main_game:
            return {}
        inning = self._format_inning(main_game)
        return {
            "status": self._map_status(main_game.get("GAME_STATE_SC")),
            "inning": inning,
            "startTime": main_game.get("G_TM"),
            "current": {
                "balls": main_game.get("BALL_CN"),
                "strikes": main_game.get("STRIKE_CN"),
                "outs": main_game.get("OUT_CN"),
                "batterName": main_game.get("B_P_NM"),
                "pitcherName": main_game.get("T_P_NM"),
            },
        }

    @staticmethod
    def _map_status(game_state: Any) -> str:
        return {
            "1": "SCHEDULED",
            "2": "LIVE",
            "3": "FINAL",
            "4": "CANCELLED",
            "5": "SUSPENDED",
        }.get(str(game_state), "UNKNOWN")

    def _format_inning(self, main_game: dict[str, Any]) -> str:
        status = self._map_status(main_game.get("GAME_STATE_SC"))
        if status == "FINAL":
            return "경기종료"
        if status == "SCHEDULED":
            return f"{main_game.get('G_TM', '')} 예정".strip()
        inning_no = main_game.get("GAME_INN_NO")
        half = main_game.get("GAME_TB_SC_NM")
        if inning_no and half:
            return f"{inning_no}회{half}"
        return status
