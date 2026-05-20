from __future__ import annotations

from datetime import datetime, timedelta, timezone
from typing import Any, Dict, Optional

from kbo_fans_backend.crawlers.records_overview import RecordsOverviewCrawler
from kbo_fans_backend.storage import JsonSnapshotStore
from kbo_fans_backend.utils.ttl_cache import TtlCache
from kbo_fans_backend.utils.player_images import kbo_player_image_url


class RecordsOverviewService:
    _OVERVIEW_CACHE_TTL_SECONDS = 300
    _CURRENT_SEASON_SNAPSHOT_MAX_AGE = timedelta(hours=6)

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
            return self._normalize_overview_payload(cached, season)

        snapshot_record = self.snapshot_store.load("records_overview", str(season))
        snapshot = snapshot_record.get("payload") if snapshot_record is not None else None
        try:
            payload = self.crawler.get_overview(season)
        except Exception:
            stale = self._overview_cache.get_stale(season)
            if self._is_historical_season(season) and stale is not None:
                return self._normalize_overview_payload(stale, season)
            if self._can_use_snapshot_after_failure(season, snapshot_record, snapshot):
                return self._normalize_overview_payload(snapshot, season)
            raise

        payload = self._normalize_overview_payload(payload, season)
        self._overview_cache.set(season, payload)
        self.snapshot_store.save("records_overview", str(season), payload)
        return payload

    def get_leaderboard(self, season: int, metric: str) -> Dict[str, Any]:
        cache_key = f"{season}:{metric}"
        cached = self._leaderboard_cache.get(cache_key)
        if cached is not None:
            return cached

        snapshot_record = self.snapshot_store.load("leaderboard", cache_key)
        snapshot = snapshot_record.get("payload") if snapshot_record is not None else None
        try:
            leaders = self.crawler.get_leaderboard(season, metric)
        except Exception:
            stale = self._leaderboard_cache.get_stale(cache_key)
            if self._is_historical_season(season) and stale is not None:
                return stale
            if self._can_use_snapshot_after_failure(season, snapshot_record, snapshot):
                return snapshot
            raise

        payload = {"season": season, "metric": metric, "leaders": leaders}
        self._leaderboard_cache.set(cache_key, payload)
        self.snapshot_store.save("leaderboard", cache_key, payload)
        return payload

    def _normalize_overview_payload(self, payload: Dict[str, Any], season: int) -> Dict[str, Any]:
        normalized = dict(payload)
        normalized["season"] = normalized.get("season", season)
        leaders = dict(normalized.get("leaders") or {})
        if not leaders.get("opsPlus"):
            ops_leaders = leaders.get("ops") or []
            leaders["opsPlus"] = RecordsOverviewCrawler._build_ops_plus_leaders(ops_leaders)[:5]
        normalized["leaders"] = leaders
        normalized["featured"] = self._build_canonical_featured(
            leaders=leaders,
            season=season,
        )
        return normalized

    def _can_use_snapshot_after_failure(
        self,
        season: int,
        snapshot_record: Optional[Dict[str, Any]],
        snapshot: Optional[Dict[str, Any]],
    ) -> bool:
        if snapshot is None:
            return False
        return self._is_historical_season(season) or self._is_fresh_snapshot(snapshot_record)

    @staticmethod
    def _is_historical_season(season: int) -> bool:
        return season < datetime.now(timezone.utc).year

    def _is_fresh_snapshot(self, snapshot_record: Optional[Dict[str, Any]]) -> bool:
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

    def _build_canonical_featured(
        self, leaders: Dict[str, Any], season: int
    ) -> Dict[str, Dict[str, Any]]:
        return {
            "todayHitter": self._featured_from_leader(
                label="시즌 타율 리더",
                leader=self._first_leader(leaders, "avg"),
                season=season,
            ),
            "todayPitcher": self._featured_from_leader(
                label="시즌 ERA 리더",
                leader=self._first_leader(leaders, "era"),
                season=season,
            ),
            "monthHitter": self._featured_from_leader(
                label="시즌 홈런왕",
                leader=self._first_leader(leaders, "hr"),
                season=season,
            ),
            "monthPitcher": self._featured_from_leader(
                label="시즌 OPS 리더",
                leader=self._first_leader(leaders, "ops"),
                season=season,
            ),
        }

    @staticmethod
    def _first_leader(leaders: Dict[str, Any], metric: str) -> Optional[Dict[str, Any]]:
        metric_leaders = leaders.get(metric) or []
        if not metric_leaders:
            return None
        leader = metric_leaders[0]
        return leader if isinstance(leader, dict) else None

    @staticmethod
    def _featured_from_leader(
        label: str, leader: Optional[Dict[str, Any]], season: int
    ) -> Dict[str, Any]:
        if leader is None:
            return {"label": label}
        player_id = str(leader.get("playerId") or "")
        payload = {
            "label": label,
            "playerId": player_id,
            "playerType": leader.get("playerType"),
            "name": leader.get("name"),
            "teamId": leader.get("teamId"),
            "headline": RecordsOverviewCrawler._headline_for_leader(leader),
            "summary": f"{season} 시즌 KBO 공식 기록 기준",
        }
        if player_id:
            payload["imageUrl"] = kbo_player_image_url(season, player_id)
        return payload
