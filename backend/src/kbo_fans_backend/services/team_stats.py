from __future__ import annotations

from typing import Any, Dict, Optional, Tuple

from kbo_fans_backend.crawlers.team_stats import TeamStatsCrawler
from kbo_fans_backend.storage import JsonSnapshotStore
from kbo_fans_backend.utils.kbo_time import current_kbo_year
from kbo_fans_backend.utils.ttl_cache import TtlCache


class TeamStatsService:
    _TEAM_STATS_CACHE_TTL_SECONDS = 300

    def __init__(
        self,
        crawler: Optional[TeamStatsCrawler] = None,
        snapshot_store: Optional[JsonSnapshotStore] = None,
    ) -> None:
        self.crawler = crawler or TeamStatsCrawler()
        self.snapshot_store = snapshot_store or JsonSnapshotStore()
        self._team_stats_cache: TtlCache[Tuple[str, int], Dict[str, Any]] = TtlCache(
            self._TEAM_STATS_CACHE_TTL_SECONDS
        )

    def get_team_stats(self, team_id: str, season: int) -> Dict[str, Any]:
        cache_key = (team_id, season)
        cached = self._get_cached_team_stats(cache_key)
        if cached is not None:
            return cached

        snapshot_key = f"{team_id}-{season}"
        snapshot_record = self.snapshot_store.load("team_stats", snapshot_key)
        snapshot = snapshot_record.get("payload") if snapshot_record is not None else None
        if self._can_use_snapshot_before_crawling(team_id, season, snapshot):
            return snapshot

        try:
            payload = self.crawler.get_team_stats(team_id, season)
        except Exception:
            stale = self._team_stats_cache.get_stale(cache_key)
            if self._is_historical_season(season) and stale is not None:
                return stale
            if self._can_use_snapshot_after_failure(team_id, season, snapshot):
                return snapshot
            raise
        self._team_stats_cache.set(cache_key, payload)
        self.snapshot_store.save("team_stats", snapshot_key, payload)
        return payload

    def _get_cached_team_stats(self, cache_key: Tuple[str, int]) -> Optional[Dict[str, Any]]:
        return self._team_stats_cache.get(cache_key)

    def _can_use_snapshot_before_crawling(
        self,
        team_id: str,
        season: int,
        snapshot: Optional[Dict[str, Any]],
    ) -> bool:
        return (
            snapshot is not None
            and self._is_historical_season(season)
            and self._is_consistent_snapshot(snapshot, team_id=team_id, season=season)
        )

    def _can_use_snapshot_after_failure(
        self,
        team_id: str,
        season: int,
        snapshot: Optional[Dict[str, Any]],
    ) -> bool:
        if snapshot is None:
            return False
        return self._is_historical_season(season) and self._is_consistent_snapshot(
            snapshot,
            team_id=team_id,
            season=season,
        )

    @staticmethod
    def _is_consistent_snapshot(
        snapshot: Dict[str, Any],
        *,
        team_id: str,
        season: int,
    ) -> bool:
        if not isinstance(snapshot, dict):
            return False
        snapshot_team_id = snapshot.get("teamId")
        snapshot_season = snapshot.get("season")
        return (
            isinstance(snapshot_team_id, str)
            and snapshot_team_id.strip().upper() == team_id.strip().upper()
            and snapshot_season == season
        )

    @staticmethod
    def _is_historical_season(season: int) -> bool:
        return season < current_kbo_year()
