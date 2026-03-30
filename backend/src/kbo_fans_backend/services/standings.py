from __future__ import annotations

from typing import Any, Optional

from kbo_fans_backend.crawlers.standings import StandingsCrawler


class StandingsService:
    def __init__(self, crawler: Optional[StandingsCrawler] = None) -> None:
        self.crawler = crawler or StandingsCrawler()

    def get_standings(self, season: int) -> dict[str, Any]:
        return self.crawler.get_standings(season)
