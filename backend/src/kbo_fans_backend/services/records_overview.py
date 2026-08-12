from __future__ import annotations

from typing import Any, Dict, List, Optional

from kbo_fans_backend.crawlers.records_overview import RecordsOverviewCrawler
from kbo_fans_backend.storage import JsonSnapshotStore
from kbo_fans_backend.utils.kbo_time import current_kbo_year
from kbo_fans_backend.utils.player_images import kbo_player_image_url
from kbo_fans_backend.utils.ttl_cache import TtlCache


class RecordsOverviewService:
    _OVERVIEW_CACHE_TTL_SECONDS = 300
    _RANKED_METRICS = (
        "avg",
        "hr",
        "ops",
        "opsPlus",
        "era",
        "wins",
        "saves",
        "strikeouts",
    )

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
        if not RecordsOverviewCrawler.is_supported_season(season):
            return RecordsOverviewCrawler.empty_overview(season)

        cached = self._overview_cache.get(season)
        if cached is not None and self._has_overview_identity(cached, season):
            normalized_cached = self._normalize_overview_payload(cached, season)
            if self._is_reusable_ranked_payload(normalized_cached):
                return normalized_cached

        snapshot_record = self.snapshot_store.load("records_overview", str(season))
        snapshot = snapshot_record.get("payload") if snapshot_record is not None else None
        if self._can_use_snapshot_before_crawling(season, snapshot):
            payload = self._normalize_overview_payload(snapshot, season)
            self._overview_cache.set(season, payload)
            return payload
        try:
            payload = self.crawler.get_overview(season)
        except Exception:
            stale = self._overview_cache.get_stale(season)
            if (
                self._is_historical_season(season)
                and self._has_overview_identity(stale, season)
            ):
                normalized_stale = self._normalize_overview_payload(stale, season)
                if self._is_reusable_ranked_payload(normalized_stale):
                    return normalized_stale
            if self._can_use_snapshot_after_failure(season, snapshot):
                return self._normalize_overview_payload(snapshot, season)
            raise

        payload = self._normalize_overview_payload(payload, season)
        if self._is_reusable_ranked_payload(payload):
            self._overview_cache.set(season, payload)
            self.snapshot_store.save("records_overview", str(season), payload)
        return payload

    def get_leaderboard(self, season: int, metric: str) -> Dict[str, Any]:
        if not RecordsOverviewCrawler.is_supported_season(season):
            return {"season": season, "metric": metric, "leaders": []}

        cache_key = f"{season}:{metric}"
        cached = self._leaderboard_cache.get(cache_key)
        if cached is not None and self._has_leaderboard_identity(cached, season, metric):
            normalized_cached = self._normalize_leaderboard_payload(cached, season, metric)
            if self._is_reusable_ranked_payload(normalized_cached):
                return normalized_cached

        snapshot_record = self.snapshot_store.load("leaderboard", cache_key)
        snapshot = snapshot_record.get("payload") if snapshot_record is not None else None
        if self._can_use_snapshot_before_crawling(season, snapshot, metric=metric):
            payload = self._normalize_leaderboard_payload(snapshot, season, metric)
            self._leaderboard_cache.set(cache_key, payload)
            return payload
        try:
            leaders = self.crawler.get_leaderboard(season, metric)
        except Exception:
            stale = self._leaderboard_cache.get_stale(cache_key)
            if (
                self._is_historical_season(season)
                and self._has_leaderboard_identity(stale, season, metric)
            ):
                normalized_stale = self._normalize_leaderboard_payload(
                    stale,
                    season,
                    metric,
                )
                if self._is_reusable_ranked_payload(normalized_stale):
                    return normalized_stale
            if self._can_use_snapshot_after_failure(season, snapshot, metric=metric):
                return self._normalize_leaderboard_payload(snapshot, season, metric)
            raise

        payload = self._normalize_leaderboard_payload(
            {"season": season, "metric": metric, "leaders": leaders},
            season,
            metric,
        )
        if self._is_reusable_ranked_payload(payload):
            self._leaderboard_cache.set(cache_key, payload)
            self.snapshot_store.save("leaderboard", cache_key, payload)
        return payload

    def _normalize_overview_payload(self, payload: Dict[str, Any], season: int) -> Dict[str, Any]:
        normalized = dict(payload)
        normalized["season"] = normalized.get("season", season)
        leaders = dict(normalized.get("leaders") or {})
        for metric in (
            "avg",
            "hr",
            "ops",
            "opsPlus",
            "era",
            "wins",
            "saves",
            "strikeouts",
        ):
            leaders[metric] = self._normalize_leaders(leaders.get(metric), limit=5)
        if not leaders.get("opsPlus"):
            ops_leaders = leaders.get("ops") or []
            leaders["opsPlus"] = self._normalize_leaders(
                RecordsOverviewCrawler._build_ops_plus_leaders(ops_leaders),
                limit=5,
            )
        normalized["leaders"] = leaders
        normalized["featured"] = self._build_canonical_featured(
            leaders=leaders,
            season=season,
        )
        return normalized

    def _normalize_leaderboard_payload(
        self,
        payload: Dict[str, Any],
        season: int,
        metric: str,
    ) -> Dict[str, Any]:
        normalized = dict(payload)
        normalized["season"] = normalized.get("season", season)
        normalized["metric"] = normalized.get("metric", metric)
        normalized["leaders"] = self._normalize_leaders(normalized.get("leaders"))
        return normalized

    @staticmethod
    def _normalize_leaders(
        leaders: Optional[List[Dict[str, Any]]],
        limit: Optional[int] = None,
    ) -> List[Dict[str, Any]]:
        if not leaders:
            return []
        ranked: List[Dict[str, Any]] = []
        for leader in leaders:
            if not isinstance(leader, dict):
                continue
            try:
                int(leader.get("rank"))
            except (TypeError, ValueError):
                continue
            ranked.append(leader)
        ranked.sort(key=lambda leader: int(leader["rank"]))
        if limit is not None:
            ranked = ranked[:limit]
        return ranked

    def _can_use_snapshot_after_failure(
        self,
        season: int,
        snapshot: Optional[Dict[str, Any]],
        *,
        metric: Optional[str] = None,
    ) -> bool:
        if metric is None:
            has_identity = self._has_overview_identity(snapshot, season)
        else:
            has_identity = self._has_leaderboard_identity(snapshot, season, metric)
        if not has_identity:
            return False
        return self._is_historical_season(season) and self._is_reusable_ranked_payload(snapshot)

    def _can_use_snapshot_before_crawling(
        self,
        season: int,
        snapshot: Optional[Dict[str, Any]],
        *,
        metric: Optional[str] = None,
    ) -> bool:
        if metric is None:
            has_identity = self._has_overview_identity(snapshot, season)
        else:
            has_identity = self._has_leaderboard_identity(snapshot, season, metric)
        if not has_identity:
            return False
        return self._is_historical_season(season) and self._is_reusable_ranked_payload(snapshot)

    @staticmethod
    def _has_overview_identity(payload: Any, season: int) -> bool:
        return isinstance(payload, dict) and payload.get("season") == season

    @staticmethod
    def _has_leaderboard_identity(payload: Any, season: int, metric: str) -> bool:
        return (
            isinstance(payload, dict)
            and payload.get("season") == season
            and payload.get("metric") == metric
        )

    @staticmethod
    def _is_reusable_ranked_payload(payload: Dict[str, Any]) -> bool:
        if not isinstance(payload, dict):
            return False
        leaders = payload.get("leaders")
        if isinstance(leaders, list):
            return RecordsOverviewService._leaders_start_at_rank_one(leaders)
        if not isinstance(leaders, dict):
            return False

        ranked_groups = [
            leaders.get(metric)
            for metric in RecordsOverviewService._RANKED_METRICS
            if isinstance(leaders.get(metric), list) and leaders.get(metric)
        ]
        return bool(ranked_groups) and all(
            RecordsOverviewService._leaders_start_at_rank_one(group)
            for group in ranked_groups
        )

    @staticmethod
    def _leaders_start_at_rank_one(leaders: List[Dict[str, Any]]) -> bool:
        if not leaders or not isinstance(leaders[0], dict):
            return False
        try:
            return int(leaders[0].get("rank")) == 1
        except (TypeError, ValueError):
            return False

    @staticmethod
    def _is_historical_season(season: int) -> bool:
        return season < current_kbo_year()

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
                label=(
                    "시즌 탈삼진 리더"
                    if self._first_leader(leaders, "strikeouts")
                    else "시즌 ERA 리더"
                ),
                leader=(
                    self._first_leader(leaders, "strikeouts")
                    or self._first_leader(leaders, "era")
                ),
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
