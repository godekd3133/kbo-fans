from __future__ import annotations

from datetime import date as date_type
from typing import Any, Optional

from kbo_fans_backend.crawlers.boxscore import BoxscoreCrawler
from kbo_fans_backend.services.player_stats import PlayerStatsService
from kbo_fans_backend.services.schedule import ScheduleService
from kbo_fans_backend.storage import JsonSnapshotStore
from kbo_fans_backend.utils.kbo_time import current_kbo_date


class BoxscoreService:
    def __init__(
        self,
        crawler: Optional[BoxscoreCrawler] = None,
        schedule_service: Optional[ScheduleService] = None,
        player_stats_service: Optional[PlayerStatsService] = None,
        snapshot_store: Optional[JsonSnapshotStore] = None,
    ) -> None:
        self.crawler = crawler or BoxscoreCrawler()
        self.schedule_service = schedule_service or ScheduleService()
        self.player_stats_service = player_stats_service or PlayerStatsService()
        self.snapshot_store = snapshot_store or JsonSnapshotStore()

    def get_boxscore(self, game_id: str) -> dict[str, Any]:
        snapshot = self.snapshot_store.load_payload("boxscore", game_id)
        if (
            snapshot is not None
            and self._is_past_game_id(game_id)
            and not self._is_empty_payload(snapshot)
        ):
            return self._enrich_player_ids_and_images(snapshot, game_id)

        try:
            payload = self.crawler.get_boxscore(game_id)
        except Exception:
            if (
                snapshot is not None
                and self._is_past_game_id(game_id)
                and not self._is_empty_payload(snapshot)
            ):
                return self._enrich_player_ids_and_images(snapshot, game_id)
            raise

        if self._is_empty_payload(payload):
            alternate_game_id = (
                self._resolve_alternate_game_id(game_id)
                if self._is_past_game_id(game_id)
                else None
            )
            if alternate_game_id is not None:
                try:
                    alternate_payload = self.crawler.get_boxscore(alternate_game_id)
                    if not self._is_empty_payload(alternate_payload):
                        alternate_payload = {
                            **alternate_payload,
                            "gameId": game_id,
                            "sourceGameId": alternate_game_id,
                        }
                        alternate_payload = self._enrich_player_ids_and_images(
                            alternate_payload, game_id
                        )
                        self.snapshot_store.save("boxscore", game_id, alternate_payload)
                        return alternate_payload
                except Exception:
                    pass

            if (
                snapshot is not None
                and self._is_past_game_id(game_id)
                and not self._is_empty_payload(snapshot)
            ):
                return self._enrich_player_ids_and_images(snapshot, game_id)
            return payload

        if payload.get("liveContextAvailable") is True and not payload.get(
            "officialAvailable", False
        ):
            return self._enrich_player_ids_and_images(payload, game_id)

        payload = self._enrich_player_ids_and_images(payload, game_id)
        self.snapshot_store.save("boxscore", game_id, payload)
        return payload

    def _enrich_player_ids_and_images(
        self, payload: dict[str, Any], game_id: str
    ) -> dict[str, Any]:
        season = self._season_from_game_id(game_id)
        if season is None:
            return payload

        for side, fallback_team_id in (
            ("away", game_id[8:10] if len(game_id) >= 10 else ""),
            ("home", game_id[10:12] if len(game_id) >= 12 else ""),
        ):
            team_payload = payload.get(side)
            if not isinstance(team_payload, dict):
                continue
            team_id = str(team_payload.get("teamId") or fallback_team_id).strip()
            players_by_name = self._team_players_by_name(team_id, season)
            if not players_by_name:
                continue
            for key in ("batters", "pitchers"):
                rows = team_payload.get(key)
                if not isinstance(rows, list):
                    continue
                for row in rows:
                    if not isinstance(row, dict):
                        continue
                    player = players_by_name.get(
                        self._normalize_player_name(row.get("name"))
                    )
                    if player is None:
                        continue
                    player_id = str(
                        player.get("id") or player.get("playerId") or ""
                    ).strip()
                    image_url = str(player.get("imageUrl") or "").strip()
                    if player_id and not str(
                        row.get("playerId") or row.get("id") or ""
                    ).strip():
                        row["playerId"] = player_id
                    if image_url and not str(row.get("imageUrl") or "").strip():
                        row["imageUrl"] = image_url

        return payload

    def _team_players_by_name(
        self, team_id: str, season: int
    ) -> dict[str, dict[str, Any]]:
        if not team_id:
            return {}
        try:
            payload = self.player_stats_service.get_team_players(team_id, season)
        except Exception:
            return {}
        players = payload.get("players") if isinstance(payload, dict) else None
        if not isinstance(players, list):
            return {}
        result: dict[str, dict[str, Any]] = {}
        for player in players:
            if not isinstance(player, dict):
                continue
            name = self._normalize_player_name(player.get("name"))
            if name:
                result[name] = player
        return result

    @staticmethod
    def _season_from_game_id(game_id: str) -> Optional[int]:
        if len(game_id) < 4:
            return None
        try:
            return int(game_id[:4])
        except ValueError:
            return None

    @staticmethod
    def _normalize_player_name(value: Any) -> str:
        return "".join(str(value or "").split()).replace("·", "").replace("ㆍ", "")

    def _resolve_alternate_game_id(self, game_id: str) -> Optional[str]:
        if len(game_id) < 12:
            return None

        month = f"{game_id[:4]}-{game_id[4:6]}"
        target_date = f"{game_id[:4]}-{game_id[4:6]}-{game_id[6:8]}"
        away_id = game_id[8:10]
        home_id = game_id[10:12]

        try:
            schedule_payload = self.schedule_service.get_month_schedule(month)
        except Exception:
            return None

        candidates = []
        for day in schedule_payload.get("days", []):
            date_str = day.get("date")
            if not date_str:
                continue
            for game in day.get("games", []):
                if game.get("awayId") != away_id or game.get("homeId") != home_id:
                    continue
                candidate_id = game.get("gameId")
                if not candidate_id or candidate_id == game_id:
                    continue
                try:
                    delta = abs(
                        (
                            date_type.fromisoformat(date_str) - date_type.fromisoformat(target_date)
                        ).days
                    )
                except ValueError:
                    continue
                candidates.append((delta, date_str, candidate_id))

        if not candidates:
            return None

        candidates.sort(key=lambda item: (item[0], item[1]))
        best_delta, _, best_game_id = candidates[0]
        if best_delta > 1:
            return None
        return best_game_id

    @staticmethod
    def _is_empty_payload(payload: dict[str, Any]) -> bool:
        away = payload.get("away", {})
        home = payload.get("home", {})
        return (
            not away.get("batters")
            and not away.get("pitchers")
            and not home.get("batters")
            and not home.get("pitchers")
        )

    @staticmethod
    def _is_past_game_id(game_id: str) -> bool:
        if len(game_id) < 8:
            return False
        try:
            game_date = date_type(
                int(game_id[:4]),
                int(game_id[4:6]),
                int(game_id[6:8]),
            )
        except ValueError:
            return False
        return game_date < current_kbo_date()
