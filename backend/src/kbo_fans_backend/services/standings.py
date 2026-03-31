from __future__ import annotations

from typing import Any, Optional

from kbo_fans_backend.crawlers.standings import StandingsCrawler
from kbo_fans_backend.storage import JsonSnapshotStore
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

        snapshot = self.snapshot_store.load_payload("standings_latest", str(season))
        try:
            payload = self.crawler.get_standings(season)
        except Exception:
            stale = self._cache.get_stale(season)
            if stale is not None:
                return stale
            if snapshot is not None:
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
