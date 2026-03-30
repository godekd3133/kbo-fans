from __future__ import annotations

from typing import Any, Optional

from kbo_fans_backend.crawlers.schedule import ScheduleCrawler
from kbo_fans_backend.crawlers.scoreboard import ScoreboardCrawler


class ScoreboardService:
    def __init__(
        self,
        schedule_crawler: Optional[ScheduleCrawler] = None,
        scoreboard_crawler: Optional[ScoreboardCrawler] = None,
    ) -> None:
        self.schedule_crawler = schedule_crawler or ScheduleCrawler()
        self.scoreboard_crawler = scoreboard_crawler or ScoreboardCrawler()

    def get_scoreboard(self, date: str) -> dict[str, Any]:
        games = self.schedule_crawler.get_games_by_date(date)
        enriched_games = []
        for game in games:
            detail = self.scoreboard_crawler.get_game_scoreboard(game["gameId"])
            enriched_games.append({**game, **detail})

        return {
            "date": date,
            "games": enriched_games,
        }
