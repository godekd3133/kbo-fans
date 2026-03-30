from __future__ import annotations

from typing import Any, Dict, Optional

from kbo_fans_backend.crawlers.player_stats import PlayerStatsCrawler


class PlayerStatsService:
    def __init__(self, crawler: Optional[PlayerStatsCrawler] = None) -> None:
        self.crawler = crawler or PlayerStatsCrawler()

    def get_team_players(self, team_id: str, season: int) -> Dict[str, Any]:
        return {
            "teamId": team_id,
            "season": season,
            "players": self.crawler.get_team_players(team_id, season),
        }

    def get_player_detail(
        self, player_id: str, season: int, player_type: Optional[str] = None
    ) -> Dict[str, Any]:
        return self.crawler.get_player_detail(
            player_id=player_id,
            player_type=player_type,
            season=season,
            include_recent=True,
        )
