from __future__ import annotations

from typing import Any, Optional

from kbo_fans_backend.crawlers.boxscore import BoxscoreCrawler


class BoxscoreService:
    def __init__(self, crawler: Optional[BoxscoreCrawler] = None) -> None:
        self.crawler = crawler or BoxscoreCrawler()

    def get_boxscore(self, game_id: str) -> dict[str, Any]:
        return self.crawler.get_boxscore(game_id)
