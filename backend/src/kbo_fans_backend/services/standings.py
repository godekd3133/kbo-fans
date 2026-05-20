from __future__ import annotations

from datetime import datetime, timedelta, timezone
from typing import Any, Optional

from kbo_fans_backend.crawlers.standings import StandingsCrawler
from kbo_fans_backend.storage import JsonSnapshotStore
from kbo_fans_backend.utils.ttl_cache import TtlCache


class StandingsService:
    _CACHE_TTL_SECONDS = 300
    _CURRENT_SEASON_SNAPSHOT_MAX_AGE = timedelta(hours=6)

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
        try:
            payload = self.crawler.get_standings(season)
        except Exception:
            stale = self._cache.get_stale(season)
            if self._is_historical_season(season) and stale is not None:
                return stale
            if self._can_use_snapshot_after_failure(season, snapshot_record, snapshot):
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
        snapshot_record: Optional[dict[str, Any]],
        snapshot: Optional[dict[str, Any]],
    ) -> bool:
        if snapshot is None:
            return False
        return self._is_historical_season(season) or self._is_fresh_snapshot(snapshot_record)

    @staticmethod
    def _is_historical_season(season: int) -> bool:
        return season < datetime.now(timezone.utc).year

    def _is_fresh_snapshot(self, snapshot_record: Optional[dict[str, Any]]) -> bool:
        if snapshot_record is None:
            return False
        saved_at_raw = snapshot_record.get("savedAt")
        if not isinstance(saved_at_raw, str) or not saved_at_raw:
            return False
        try:
            saved_at = datetime.fromisoformat(saved_at_raw.replace("Z", "+00:00"))
        except ValueError:
            return False
        if saved_at.tzinfo is None:
            saved_at = saved_at.replace(tzinfo=timezone.utc)
        return datetime.now(timezone.utc) - saved_at <= self._CURRENT_SEASON_SNAPSHOT_MAX_AGE
