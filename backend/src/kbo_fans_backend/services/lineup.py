from __future__ import annotations

from typing import Any, Optional

from kbo_fans_backend.crawlers.boxscore import BoxscoreCrawler
from kbo_fans_backend.crawlers.lineup import LineupCrawler


class LineupService:
    def __init__(
        self,
        lineup_crawler: Optional[LineupCrawler] = None,
        boxscore_crawler: Optional[BoxscoreCrawler] = None,
    ) -> None:
        self.lineup_crawler = lineup_crawler or LineupCrawler()
        self.boxscore_crawler = boxscore_crawler or BoxscoreCrawler()

    def get_lineup(self, game_id: str) -> dict[str, Any]:
        lineup = self.lineup_crawler.get_lineup(game_id)
        boxscore = self.boxscore_crawler.get_boxscore(game_id)

        for side in ("away", "home"):
            pitchers = boxscore[side]["pitchers"]
            starter = pitchers[0] if pitchers else None
            lineup[side]["starter"] = {
                "name": starter["name"] if starter else None,
                "hand": None,
            }

        return lineup
