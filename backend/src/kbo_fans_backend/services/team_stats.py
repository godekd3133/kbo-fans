from __future__ import annotations

from typing import Any, Dict, Optional

from kbo_fans_backend.crawlers.team_stats import TeamStatsCrawler


class TeamStatsService:
    def __init__(self, crawler: Optional[TeamStatsCrawler] = None) -> None:
        self.crawler = crawler or TeamStatsCrawler()

    def get_team_stats(self, team_id: str, season: int) -> Dict[str, Any]:
        return self.crawler.get_team_stats(team_id, season)
