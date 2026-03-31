from __future__ import annotations

from typing import Any, Dict, Optional, Tuple

from kbo_fans_backend.crawlers.team_stats import TeamStatsCrawler
from kbo_fans_backend.utils.ttl_cache import TtlCache


class TeamStatsService:
    _TEAM_STATS_CACHE_TTL_SECONDS = 300

    def __init__(self, crawler: Optional[TeamStatsCrawler] = None) -> None:
        self.crawler = crawler or TeamStatsCrawler()
        self._team_stats_cache: TtlCache[Tuple[str, int], Dict[str, Any]] = TtlCache(
            self._TEAM_STATS_CACHE_TTL_SECONDS
        )

    def get_team_stats(self, team_id: str, season: int) -> Dict[str, Any]:
        cache_key = (team_id, season)
        cached = self._get_cached_team_stats(cache_key)
        if cached is not None:
            return cached

        try:
            payload = self.crawler.get_team_stats(team_id, season)
        except Exception:
            stale = self._team_stats_cache.get_stale(cache_key)
            if stale is not None:
                return stale
            raise
        self._team_stats_cache.set(cache_key, payload)
        return payload

    def _get_cached_team_stats(
        self, cache_key: Tuple[str, int]
    ) -> Optional[Dict[str, Any]]:
        return self._team_stats_cache.get(cache_key)
