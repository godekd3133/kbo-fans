from __future__ import annotations

from typing import Any, Dict, Optional
from kbo_fans_backend.crawlers.records_overview import RecordsOverviewCrawler
from kbo_fans_backend.storage import JsonSnapshotStore
from kbo_fans_backend.utils.ttl_cache import TtlCache


class RecordsOverviewService:
    _OVERVIEW_CACHE_TTL_SECONDS = 300

    def __init__(
        self,
        crawler: Optional[RecordsOverviewCrawler] = None,
        snapshot_store: Optional[JsonSnapshotStore] = None,
    ) -> None:
        self.crawler = crawler or RecordsOverviewCrawler()
        self.snapshot_store = snapshot_store or JsonSnapshotStore()
        self._overview_cache: TtlCache[int, Dict[str, Any]] = TtlCache(
            self._OVERVIEW_CACHE_TTL_SECONDS
        )
        self._leaderboard_cache: TtlCache[str, Dict[str, Any]] = TtlCache(
            self._OVERVIEW_CACHE_TTL_SECONDS
        )

    def get_overview(self, season: int) -> Dict[str, Any]:
        cached = self._overview_cache.get(season)
        if cached is not None:
            return cached

        snapshot = self.snapshot_store.load_payload("records_overview", str(season))
        if snapshot is not None:
            self._overview_cache.set(season, snapshot)
            return snapshot

        try:
            payload = self.crawler.get_overview(season)
        except Exception:
            stale = self._overview_cache.get_stale(season)
            if stale is not None:
                return stale
            if snapshot is not None:
                return snapshot
            raise

        self._overview_cache.set(season, payload)
        self.snapshot_store.save("records_overview", str(season), payload)
        return payload

    def get_leaderboard(self, season: int, metric: str) -> Dict[str, Any]:
        cache_key = f"{season}:{metric}"
        cached = self._leaderboard_cache.get(cache_key)
        if cached is not None:
            return cached

        try:
            leaders = self.crawler.get_leaderboard(season, metric)
        except Exception:
            stale = self._leaderboard_cache.get_stale(cache_key)
            if stale is not None:
                return stale
            raise

        payload = {"season": season, "metric": metric, "leaders": leaders}
        self._leaderboard_cache.set(cache_key, payload)
        return payload
