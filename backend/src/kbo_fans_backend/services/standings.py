from __future__ import annotations

from typing import Any, Optional

from kbo_fans_backend.crawlers.standings import StandingsCrawler
from kbo_fans_backend.storage import JsonSnapshotStore
from kbo_fans_backend.utils.kbo_time import current_kbo_year
from kbo_fans_backend.utils.ttl_cache import TtlCache


class StandingsService:
    _CACHE_TTL_SECONDS = 300

    def __init__(
        self,
        crawler: Optional[StandingsCrawler] = None,
        snapshot_store: Optional[JsonSnapshotStore] = None,
    ) -> None:
        self.crawler = crawler or StandingsCrawler()
        self.snapshot_store = snapshot_store or JsonSnapshotStore()
        self._cache: TtlCache[int, dict[str, Any]] = TtlCache(self._CACHE_TTL_SECONDS)

    def get_standings(self, season: int) -> dict[str, Any]:
        cached = self._cache.get(season)
        if cached is not None:
            return cached

        snapshot_record = self.snapshot_store.load("standings_latest", str(season))
        snapshot = snapshot_record.get("payload") if snapshot_record is not None else None
        if self._can_use_snapshot_before_crawling(season, snapshot):
            self._cache.set(season, snapshot)
            return snapshot
        try:
            payload = self.crawler.get_standings(season)
        except Exception:
            stale = self._cache.get_stale(season)
            if self._is_historical_season(season) and stale is not None:
                return stale
            if self._can_use_snapshot_after_failure(season, snapshot):
                return snapshot
            raise

        self._cache.set(season, payload)
        self.snapshot_store.save("standings_latest", str(season), payload)
        updated_at = payload.get("updatedAt")
        if isinstance(updated_at, str) and len(updated_at) >= 10:
            self.snapshot_store.save(
                "standings_daily",
                f"{season}-{updated_at[:10]}",
                payload,
            )
        return payload

    def _can_use_snapshot_after_failure(
        self,
        season: int,
        snapshot: Optional[dict[str, Any]],
    ) -> bool:
        if snapshot is None:
            return False
        return self._is_historical_season(season)

    def _can_use_snapshot_before_crawling(
        self,
        season: int,
        snapshot: Optional[dict[str, Any]],
    ) -> bool:
        if snapshot is None:
            return False
        return self._is_historical_season(season)

    @staticmethod
    def _is_historical_season(season: int) -> bool:
        return season < current_kbo_year()
