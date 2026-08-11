from __future__ import annotations

from datetime import date as date_type
from typing import Any, Optional

from kbo_fans_backend.crawlers.boxscore import BoxscoreCrawler
from kbo_fans_backend.schemas.boxscore import (
    BoxscoreAvailability,
    official_unavailable_boxscore,
)
from kbo_fans_backend.services.player_stats import PlayerStatsService
from kbo_fans_backend.services.schedule import ScheduleService
from kbo_fans_backend.storage import JsonSnapshotStore
from kbo_fans_backend.utils.kbo_time import current_kbo_date


class BoxscoreService:
    _UNAVAILABLE_STATUSES = {"SCHEDULED", "CANCELLED", "SUSPENDED"}

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
        game_status = self._game_status(game_id)
        is_historical_final = self._is_historical_final(game_id, game_status)
        can_use_historical_snapshot = self._is_past_game_id(game_id) and (
            is_historical_final or game_status in {None, "UNKNOWN"}
        )
        snapshot = self.snapshot_store.load_payload("boxscore", game_id)
        if can_use_historical_snapshot and self._is_valid_historical_snapshot(
            snapshot,
            game_id,
        ):
            return self._enrich_player_ids_and_images(snapshot, game_id)

        payload = self.crawler.get_boxscore(game_id)

        payload = self._normalize_crawler_payload(payload, game_id)
        if self._is_verified_official_payload(payload, game_id):
            if game_status in self._UNAVAILABLE_STATUSES:
                return self._official_unavailable_payload(
                    game_id,
                    reason=f"game_status_{game_status.lower()}",
                )
            payload = self._enrich_player_ids_and_images(payload, game_id)
            if game_status == "FINAL":
                self.snapshot_store.save("boxscore", game_id, payload)
            return payload

        if self._is_live_context_payload(payload, game_id):
            if game_status == "LIVE" or (
                game_status in {None, "UNKNOWN"} and not self._is_past_game_id(game_id)
            ):
                return self._enrich_player_ids_and_images(payload, game_id)
            payload = self._official_unavailable_payload(
                game_id,
                reason="live_context_not_current",
            )

        if is_historical_final:
            alternate_game_id = self._resolve_alternate_game_id(game_id)
            if alternate_game_id is not None:
                try:
                    alternate_payload = self.crawler.get_boxscore(alternate_game_id)
                    alternate_payload = self._normalize_crawler_payload(
                        alternate_payload,
                        alternate_game_id,
                    )
                    if self._is_verified_official_payload(
                        alternate_payload,
                        alternate_game_id,
                    ):
                        alternate_payload = {
                            **alternate_payload,
                            "gameId": game_id,
                            "sourceGameId": alternate_game_id,
                            "source": "adjacent_official",
                        }
                        alternate_payload = self._enrich_player_ids_and_images(
                            alternate_payload, game_id
                        )
                        self.snapshot_store.save("boxscore", game_id, alternate_payload)
                        return alternate_payload
                except Exception:
                    pass

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
                    player = players_by_name.get(self._normalize_player_name(row.get("name")))
                    if player is None:
                        continue
                    player_id = str(player.get("id") or player.get("playerId") or "").strip()
                    image_url = str(player.get("imageUrl") or "").strip()
                    if player_id and not str(row.get("playerId") or row.get("id") or "").strip():
                        row["playerId"] = player_id
                    if image_url and not str(row.get("imageUrl") or "").strip():
                        row["imageUrl"] = image_url

        return payload

    def _team_players_by_name(self, team_id: str, season: int) -> dict[str, dict[str, Any]]:
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
                if str(game.get("status") or "").upper() != "FINAL":
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

    def _normalize_crawler_payload(
        self,
        payload: Any,
        game_id: str,
    ) -> dict[str, Any]:
        if isinstance(payload, dict) and self._is_verified_official_payload(
            payload,
            game_id,
        ):
            normalized = {key: value for key, value in payload.items() if key != "sourceGameId"}
            return {
                **normalized,
                "availability": BoxscoreAvailability.OFFICIAL.value,
                "officialAvailable": True,
                "liveContextAvailable": False,
                "source": "official_endpoint",
            }

        if isinstance(payload, dict) and self._is_live_context_payload(
            payload,
            game_id,
        ):
            return {
                **payload,
                "availability": BoxscoreAvailability.LIVE_CONTEXT.value,
                "officialAvailable": False,
                "liveContextAvailable": True,
                "source": "live_context",
                "unavailableReason": str(
                    payload.get("unavailableReason") or "official_not_available"
                ),
            }

        reason = "official_not_available"
        if isinstance(payload, dict):
            reason = str(
                payload.get("unavailableReason")
                or (
                    "official_partial"
                    if payload.get("officialAvailable") is True
                    else "official_not_available"
                )
            )
        return self._official_unavailable_payload(game_id, reason=reason)

    def _is_valid_historical_snapshot(
        self,
        payload: Any,
        game_id: str,
    ) -> bool:
        if not isinstance(payload, dict) or not self._is_verified_official_payload(
            payload,
            game_id,
        ):
            return False

        source = str(payload.get("source") or "").strip()
        source_game_id = payload.get("sourceGameId")
        if source_game_id is None:
            return source == "official_endpoint"
        if source != "adjacent_official":
            return False
        if not isinstance(source_game_id, str) or source_game_id == game_id:
            return False
        return self._resolve_alternate_game_id(game_id) == source_game_id

    @classmethod
    def _is_verified_official_payload(
        cls,
        payload: dict[str, Any],
        game_id: str,
    ) -> bool:
        if payload.get("gameId") != game_id:
            return False
        if payload.get("availability") != BoxscoreAvailability.OFFICIAL.value:
            return False
        if payload.get("officialAvailable") is not True:
            return False
        if payload.get("liveContextAvailable") is not False:
            return False
        if len(game_id) < 12:
            return False

        for side, expected_team_id in (
            ("away", game_id[8:10]),
            ("home", game_id[10:12]),
        ):
            team = payload.get(side)
            if not isinstance(team, dict) or team.get("teamId") != expected_team_id:
                return False
            if not cls._has_official_batting_line(team.get("batters")):
                return False
            if not cls._has_official_pitching_line(team.get("pitchers")):
                return False
        return True

    @classmethod
    def _is_live_context_payload(
        cls,
        payload: dict[str, Any],
        game_id: str,
    ) -> bool:
        if payload.get("gameId") != game_id:
            return False
        if payload.get("officialAvailable") is not False:
            return False
        if payload.get("liveContextAvailable") is not True:
            return False
        if len(game_id) < 12:
            return False

        has_context_row = False
        for side, expected_team_id in (
            ("away", game_id[8:10]),
            ("home", game_id[10:12]),
        ):
            team = payload.get(side)
            if not isinstance(team, dict) or team.get("teamId") != expected_team_id:
                return False
            for key in ("batters", "pitchers"):
                rows = team.get(key)
                if not isinstance(rows, list):
                    continue
                has_context_row = has_context_row or any(
                    isinstance(row, dict)
                    and row.get("liveContext") is True
                    and bool(str(row.get("name") or "").strip())
                    for row in rows
                )
        return has_context_row

    @staticmethod
    def _has_official_batting_line(rows: Any) -> bool:
        if not isinstance(rows, list):
            return False
        for row in rows:
            if not isinstance(row, dict) or not str(row.get("name") or "").strip():
                continue
            for key in ("plateAppearances", "atBats", "runs", "hits", "rbi"):
                try:
                    if int(row.get(key) or 0) > 0:
                        return True
                except (TypeError, ValueError):
                    continue
        return False

    @staticmethod
    def _has_official_pitching_line(rows: Any) -> bool:
        if not isinstance(rows, list):
            return False
        for row in rows:
            if not isinstance(row, dict) or not str(row.get("name") or "").strip():
                continue
            innings = str(row.get("innings") or "").strip()
            decision = str(row.get("decision") or "").strip().upper()
            if innings not in {"", "0", "0.0"}:
                return True
            if decision not in {"", "-", "LIVE", "NONE"}:
                return True
            for key in ("hits", "strikeouts", "walks", "earnedRuns"):
                try:
                    if int(row.get(key) or 0) > 0:
                        return True
                except (TypeError, ValueError):
                    continue
        return False

    def _game_status(self, game_id: str) -> Optional[str]:
        try:
            game = self.schedule_service.get_schedule_game(game_id)
        except Exception:
            return None
        if not isinstance(game, dict):
            return None
        status = str(game.get("status") or "").strip().upper()
        return status or None

    @classmethod
    def _is_historical_final(
        cls,
        game_id: str,
        game_status: Optional[str],
    ) -> bool:
        return game_status == "FINAL" and cls._is_past_game_id(game_id)

    @staticmethod
    def _official_unavailable_payload(
        game_id: str,
        *,
        reason: str,
    ) -> dict[str, Any]:
        away_id = game_id[8:10] if len(game_id) >= 10 else ""
        home_id = game_id[10:12] if len(game_id) >= 12 else ""
        return official_unavailable_boxscore(
            game_id,
            away_id,
            home_id,
            reason=reason,
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
