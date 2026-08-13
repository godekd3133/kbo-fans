from __future__ import annotations

from typing import Any, Dict, Optional, Tuple

from kbo_fans_backend.crawlers.player_stats import PlayerStatsCrawler
from kbo_fans_backend.storage import JsonSnapshotStore
from kbo_fans_backend.utils.kbo_time import current_kbo_year
from kbo_fans_backend.utils.singleflight import SingleFlight
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
        self._team_players_singleflight: SingleFlight[Tuple[str, int]] = SingleFlight()

    def get_team_players(self, team_id: str, season: int) -> Dict[str, Any]:
        cache_key = (team_id, season)
        cached = self._get_cached_team_players(cache_key)
        if cached is not None and self._is_consistent_team_players_payload(
            cached,
            team_id=team_id,
            season=season,
        ):
            return cached

        return self._team_players_singleflight.call(
            cache_key,
            lambda: self._load_team_players(
                team_id=team_id,
                season=season,
                cache_key=cache_key,
            ),
        )

    def _load_team_players(
        self,
        *,
        team_id: str,
        season: int,
        cache_key: Tuple[str, int],
    ) -> Dict[str, Any]:
        cached = self._get_cached_team_players(cache_key)
        if cached is not None and self._is_consistent_team_players_payload(
            cached,
            team_id=team_id,
            season=season,
        ):
            return cached

        snapshot_key = self._team_players_snapshot_key(team_id, season)
        snapshot_record = self.snapshot_store.load("team_players", snapshot_key)
        snapshot = snapshot_record.get("payload") if snapshot_record is not None else None
        if self._can_use_snapshot_before_crawling(team_id, season, snapshot):
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
            if self._can_use_snapshot_after_failure(team_id, season, snapshot):
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
        if cached is not None and self._is_consistent_player_detail_payload(
            cached,
            player_id=player_id,
            season=season,
            player_type=player_type,
        ):
            return cached

        snapshot_key = self._player_detail_snapshot_key(player_id, season, player_type)
        snapshot = self.snapshot_store.load_payload("player_detail", snapshot_key)
        if (
            snapshot is not None
            and self._is_historical_season(season)
            and self._is_consistent_player_detail_payload(
                snapshot,
                player_id=player_id,
                season=season,
                player_type=player_type,
            )
        ):
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
            if (
                snapshot is not None
                and self._is_historical_season(season)
                and self._is_consistent_player_detail_payload(
                    snapshot,
                    player_id=player_id,
                    season=season,
                    player_type=player_type,
                )
            ):
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
        team_id: str,
        season: int,
        snapshot: Optional[Dict[str, Any]],
    ) -> bool:
        return (
            snapshot is not None
            and self._is_historical_season(season)
            and self._is_consistent_team_players_payload(
                snapshot,
                team_id=team_id,
                season=season,
            )
        )

    def _can_use_snapshot_after_failure(
        self,
        team_id: str,
        season: int,
        snapshot: Optional[Dict[str, Any]],
    ) -> bool:
        if snapshot is None or not self._is_consistent_team_players_payload(
            snapshot,
            team_id=team_id,
            season=season,
        ):
            return False
        return self._is_historical_season(season)

    @classmethod
    def _is_consistent_team_players_payload(
        cls,
        payload: Dict[str, Any],
        *,
        team_id: str,
        season: int,
    ) -> bool:
        if not isinstance(payload, dict):
            return False
        return (
            isinstance(payload.get("teamId"), str)
            and payload["teamId"].strip().upper() == team_id.strip().upper()
            and payload.get("season") == season
            and cls._is_localized_team_players_payload(payload)
        )

    @staticmethod
    def _is_historical_season(season: int) -> bool:
        return season < current_kbo_year()

    @staticmethod
    def _player_detail_snapshot_key(player_id: str, season: int, player_type: Optional[str]) -> str:
        return f"{player_id}-{season}-{player_type or 'auto'}"

    @staticmethod
    def _is_consistent_player_detail_payload(
        payload: Dict[str, Any],
        *,
        player_id: str,
        season: int,
        player_type: Optional[str],
    ) -> bool:
        if not isinstance(payload, dict):
            return False
        if not isinstance(payload.get("id"), str) or payload["id"].strip() != player_id.strip():
            return False
        if payload.get("season") != season:
            return False
        payload_type = str(payload.get("playerType") or "")
        if player_type and payload_type != player_type:
            return False
        position = str(payload.get("position") or "")
        role_label = str(payload.get("roleLabel") or "")
        if payload_type == "hitter" and ("투수" in position or "투수" in role_label):
            return False
        return True
