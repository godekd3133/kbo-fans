from __future__ import annotations

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
        if cached is not None:
            return cached

        snapshot_key = self._team_players_snapshot_key(team_id, season)
        snapshot = self.snapshot_store.load_payload("team_players", snapshot_key)
        if snapshot is not None:
            return snapshot

        try:
            payload = {
                "teamId": team_id,
                "season": season,
                "players": self.crawler.get_team_players(team_id, season),
            }
        except Exception:
            stale = self._team_players_cache.get_stale(cache_key)
            if stale is not None:
                return stale
            if snapshot is not None:
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
        if snapshot is not None:
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
            if stale is not None:
                return stale
            if snapshot is not None:
                return snapshot
            raise

        self._player_detail_cache.set(cache_key, payload)
        self.snapshot_store.save("player_detail", snapshot_key, payload)
        return payload

    def _get_cached_team_players(
        self, cache_key: Tuple[str, int]
    ) -> Optional[Dict[str, Any]]:
        return self._team_players_cache.get(cache_key)

    @staticmethod
    def _team_players_snapshot_key(team_id: str, season: int) -> str:
        return f"{team_id}-{season}"

    @staticmethod
    def _player_detail_snapshot_key(
        player_id: str, season: int, player_type: Optional[str]
    ) -> str:
        return f"{player_id}-{season}-{player_type or 'auto'}"
