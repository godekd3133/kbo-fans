from __future__ import annotations

from datetime import datetime, timezone
from typing import Any, Dict, Optional, Tuple

from kbo_fans_backend.crawlers.player_stats import PlayerStatsCrawler
from kbo_fans_backend.storage import JsonSnapshotStore
from kbo_fans_backend.utils.ttl_cache import TtlCache


class PlayerStatsService:
    _TEAM_PLAYERS_CACHE_TTL_SECONDS = 300
    _PLAYER_DETAIL_CACHE_TTL_SECONDS = 300

    def __init__(
        self,
        crawler: Optional[PlayerStatsCrawler] = None,
        snapshot_store: Optional[JsonSnapshotStore] = None,
    ) -> None:
        self.crawler = crawler or PlayerStatsCrawler()
        self.snapshot_store = snapshot_store or JsonSnapshotStore()
        self._team_players_cache: TtlCache[Tuple[str, int], Dict[str, Any]] = TtlCache(
            self._TEAM_PLAYERS_CACHE_TTL_SECONDS
        )
        self._player_detail_cache: TtlCache[Tuple[str, int, str], Dict[str, Any]] = TtlCache(
            self._PLAYER_DETAIL_CACHE_TTL_SECONDS
        )

    def get_team_players(self, team_id: str, season: int) -> Dict[str, Any]:
        cache_key = (team_id, season)
        cached = self._get_cached_team_players(cache_key)
        if cached is not None and self._is_localized_team_players_payload(cached):
            return cached

        snapshot_key = self._team_players_snapshot_key(team_id, season)
        snapshot_record = self.snapshot_store.load("team_players", snapshot_key)
        snapshot = snapshot_record.get("payload") if snapshot_record is not None else None
        if self._can_use_snapshot_before_crawling(season, snapshot):
            return snapshot

        try:
            payload = {
                "teamId": team_id,
                "season": season,
                "players": self.crawler.get_team_players(team_id, season),
            }
        except Exception:
            stale = self._team_players_cache.get_stale(cache_key)
            if self._is_historical_season(season) and stale is not None:
                return stale
            if self._can_use_snapshot_after_failure(season, snapshot):
                return snapshot
            raise
        self._team_players_cache.set(cache_key, payload)
        self.snapshot_store.save("team_players", snapshot_key, payload)
        return payload

    def get_player_detail(
        self, player_id: str, season: int, player_type: Optional[str] = None
    ) -> Dict[str, Any]:
        cache_key = (player_id, season, player_type or "")
        cached = self._player_detail_cache.get(cache_key)
        if cached is not None:
            return cached

        snapshot_key = self._player_detail_snapshot_key(player_id, season, player_type)
        snapshot = self.snapshot_store.load_payload("player_detail", snapshot_key)
        if snapshot is not None and self._is_historical_season(season):
            return snapshot

        try:
            payload = self.crawler.get_player_detail(
                player_id=player_id,
                player_type=player_type,
                season=season,
                include_recent=True,
            )
        except Exception:
            stale = self._player_detail_cache.get_stale(cache_key)
            if self._is_historical_season(season) and stale is not None:
                return stale
            if snapshot is not None and self._is_historical_season(season):
                return snapshot
            raise

        self._player_detail_cache.set(cache_key, payload)
        self.snapshot_store.save("player_detail", snapshot_key, payload)
        return payload

    def _get_cached_team_players(self, cache_key: Tuple[str, int]) -> Optional[Dict[str, Any]]:
        return self._team_players_cache.get(cache_key)

    @staticmethod
    def _is_localized_team_players_payload(payload: Dict[str, Any]) -> bool:
        players = payload.get("players")
        if not isinstance(players, list) or not players:
            return True

        sample = players[0] if isinstance(players[0], dict) else {}
        name = str(sample.get("name") or "")
        position = str(sample.get("position") or "")
        role_label = str(sample.get("roleLabel") or "")

        # 한글 필드가 전혀 없고 영문 포지션 표기가 남아 있으면 예전 snapshot/cached payload로 간주.
        if any(
            keyword in position for keyword in ("Pitcher", "Catcher", "Infielder", "Outfielder")
        ):
            return False
        if any(
            keyword in role_label for keyword in ("Pitcher", "Catcher", "Infielder", "Outfielder")
        ):
            return False
        if name and name.upper() == name and " " in name:
            return False
        return True

    @staticmethod
    def _team_players_snapshot_key(team_id: str, season: int) -> str:
        return f"{team_id}-{season}"

    def _can_use_snapshot_before_crawling(
        self,
        season: int,
        snapshot: Optional[Dict[str, Any]],
    ) -> bool:
        return (
            snapshot is not None
            and self._is_historical_season(season)
            and self._is_localized_team_players_payload(snapshot)
        )

    def _can_use_snapshot_after_failure(
        self,
        season: int,
        snapshot: Optional[Dict[str, Any]],
    ) -> bool:
        if snapshot is None or not self._is_localized_team_players_payload(snapshot):
            return False
        return self._is_historical_season(season)

    @staticmethod
    def _is_historical_season(season: int) -> bool:
        return season < datetime.now(timezone.utc).year

    @staticmethod
    def _player_detail_snapshot_key(player_id: str, season: int, player_type: Optional[str]) -> str:
        return f"{player_id}-{season}-{player_type or 'auto'}"
