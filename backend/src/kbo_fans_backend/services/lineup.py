from __future__ import annotations

from copy import deepcopy
from datetime import date as date_type
from typing import Any, Callable, Optional

from kbo_fans_backend.crawlers.boxscore import BoxscoreCrawler
from kbo_fans_backend.crawlers.lineup import LineupCrawler
from kbo_fans_backend.crawlers.main import MainCrawler
from kbo_fans_backend.services.player_stats import PlayerStatsService
from kbo_fans_backend.services.push import PushService
from kbo_fans_backend.storage import JsonSnapshotStore
from kbo_fans_backend.utils.kbo_time import current_kbo_date
from kbo_fans_backend.utils.player_images import kbo_player_image_url


def _current_kbo_date() -> date_type:
    return current_kbo_date()


class LineupService:
    _LINEUP_OPENED_ALERT_KEY = "lineup_opened"

    def __init__(
        self,
        lineup_crawler: Optional[LineupCrawler] = None,
        boxscore_crawler: Optional[BoxscoreCrawler] = None,
        main_crawler: Optional[MainCrawler] = None,
        snapshot_store: Optional[JsonSnapshotStore] = None,
        push_service: Optional[PushService] = None,
        player_stats_service: Optional[PlayerStatsService] = None,
        today_provider: Optional[Callable[[], date_type]] = None,
    ) -> None:
        self.lineup_crawler = lineup_crawler or LineupCrawler()
        self.boxscore_crawler = boxscore_crawler or BoxscoreCrawler()
        self.main_crawler = main_crawler or MainCrawler()
        self.snapshot_store = snapshot_store or JsonSnapshotStore()
        self.push_service = push_service or PushService()
        self.player_stats_service = player_stats_service or PlayerStatsService()
        self.today_provider = today_provider or _current_kbo_date

    def get_lineup(self, game_id: str) -> dict[str, Any]:
        snapshot = self.snapshot_store.load_payload("lineup", game_id)
        if (
            snapshot is not None
            and self._is_past_game_id(game_id)
            and self._has_ready_lineup(snapshot)
        ):
            enriched_snapshot = self._enrich_snapshot_if_missing_player_images(
                snapshot,
                game_id,
            )
            if enriched_snapshot != snapshot:
                self.snapshot_store.save("lineup", game_id, enriched_snapshot)
            return enriched_snapshot

        try:
            lineup = self.lineup_crawler.get_lineup(game_id)
            boxscore = self.boxscore_crawler.get_boxscore(game_id)
        except Exception:
            if (
                snapshot is not None
                and self._is_past_game_id(game_id)
                and self._has_ready_lineup(snapshot)
            ):
                return snapshot
            raise

        main_game = self._get_main_game(game_id)
        for side in ("away", "home"):
            pitchers = boxscore[side]["pitchers"]
            starter = pitchers[0] if pitchers else None
            starter_id = self._starter_id(main_game, side)
            starter_name = self._starter_name(main_game, side) or (
                starter["name"] if starter else None
            )
            lineup[side]["starter"] = {
                "id": starter_id,
                "name": starter_name,
                "hand": None,
                "imageUrl": self._starter_image_url(game_id, starter_id),
            }

        self._enrich_lineup_rows(lineup, game_id)

        if (
            self._should_send_lineup_opened_alert(game_id, snapshot, lineup)
            and not self._lineup_opened_already_sent(game_id)
        ):
            try:
                response = self.push_service.send_lineup_opened(
                    game_id=game_id,
                    away_team_id=lineup["away"]["teamId"],
                    away_team_name=lineup["away"].get("teamName") or lineup["away"]["teamId"],
                    home_team_id=lineup["home"]["teamId"],
                    home_team_name=lineup["home"].get("teamName") or lineup["home"]["teamId"],
                )
                if isinstance(response, dict) and response.get("sent"):
                    self._mark_lineup_opened_sent(game_id)
            except Exception:
                pass

        self.snapshot_store.save("lineup", game_id, lineup)
        return lineup

    def _lineup_opened_already_sent(self, game_id: str) -> bool:
        registry = getattr(self.push_service, "registry", None)
        if registry is None:
            return False
        try:
            return bool(
                registry.pregame_alert_sent(game_id, self._LINEUP_OPENED_ALERT_KEY)
            )
        except Exception:
            return False

    def _mark_lineup_opened_sent(self, game_id: str) -> None:
        registry = getattr(self.push_service, "registry", None)
        if registry is None:
            return
        try:
            registry.mark_pregame_alert_sent(game_id, self._LINEUP_OPENED_ALERT_KEY)
        except Exception:
            pass

    def _get_main_game(self, game_id: str) -> Optional[dict[str, Any]]:
        if len(game_id) < 8:
            return None
        date = f"{game_id[:4]}-{game_id[4:6]}-{game_id[6:8]}"
        try:
            return next(
                (
                    game
                    for game in self.main_crawler.get_kbo_game_list(date)
                    if game.get("G_ID") == game_id
                ),
                None,
            )
        except Exception:
            return None

    @staticmethod
    def _starter_id(main_game: Optional[dict[str, Any]], side: str) -> Optional[str]:
        if main_game is None:
            return None
        key = "T_PIT_P_ID" if side == "away" else "B_PIT_P_ID"
        value = main_game.get(key)
        if value is None:
            return None
        text = str(value).strip()
        return text or None

    @staticmethod
    def _starter_name(main_game: Optional[dict[str, Any]], side: str) -> Optional[str]:
        if main_game is None:
            return None
        key = "T_PIT_P_NM" if side == "away" else "B_PIT_P_NM"
        value = main_game.get(key)
        if value is None:
            return None
        text = str(value).strip()
        return text or None

    def _starter_image_url(self, game_id: str, starter_id: Optional[str]) -> Optional[str]:
        if not starter_id:
            return None
        season = self._season_from_game_id(game_id)
        if season is None:
            return None
        return kbo_player_image_url(season, starter_id)

    def _enrich_lineup_rows(self, lineup: dict[str, Any], game_id: str) -> None:
        season = self._season_from_game_id(game_id)
        if season is None:
            return

        for side in ("away", "home"):
            team = lineup.get(side)
            if not isinstance(team, dict):
                continue
            team_id = str(team.get("teamId") or "").strip()
            rows = team.get("lineup")
            if not team_id or not isinstance(rows, list) or not rows:
                continue

            players_by_name = self._team_players_by_name(team_id, season)
            if not players_by_name:
                continue

            for row in rows:
                if not isinstance(row, dict):
                    continue
                player = players_by_name.get(self._normalize_player_name(row.get("name")))
                if player is None:
                    continue
                player_id = str(player.get("id") or player.get("playerId") or "").strip()
                image_url = str(player.get("imageUrl") or "").strip()
                if player_id and not row.get("id"):
                    row["id"] = player_id
                if not image_url and player_id:
                    image_url = kbo_player_image_url(season, player_id)
                if image_url and not row.get("imageUrl"):
                    row["imageUrl"] = image_url

    def _enrich_snapshot_if_missing_player_images(
        self,
        snapshot: dict[str, Any],
        game_id: str,
    ) -> dict[str, Any]:
        if self._has_lineup_player_image_handles(snapshot):
            return snapshot
        enriched = deepcopy(snapshot)
        self._enrich_lineup_rows(enriched, game_id)
        return enriched

    @staticmethod
    def _has_lineup_player_image_handles(payload: dict[str, Any]) -> bool:
        for side in ("away", "home"):
            rows = payload.get(side, {}).get("lineup")
            if not isinstance(rows, list):
                continue
            for row in rows:
                if not isinstance(row, dict):
                    continue
                if not str(row.get("name") or "").strip():
                    continue
                has_player_id = bool(
                    str(row.get("id") or row.get("playerId") or "").strip()
                )
                has_image_url = bool(str(row.get("imageUrl") or "").strip())
                if not has_player_id and not has_image_url:
                    return False
        return True

    def _team_players_by_name(self, team_id: str, season: int) -> dict[str, dict[str, Any]]:
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
            key = self._normalize_player_name(player.get("name"))
            if key and key not in result:
                result[key] = player
        return result

    @staticmethod
    def _season_from_game_id(game_id: str) -> Optional[int]:
        try:
            return int(game_id[:4])
        except (TypeError, ValueError):
            return None

    @staticmethod
    def _normalize_player_name(value: Any) -> str:
        import re

        text = str(value or "")
        text = re.sub(r"\([^)]*\)", "", text)
        text = re.sub(r"\[[^\]]*\]", "", text)
        text = re.sub(r"\s+", "", text)
        text = text.replace("·", "").replace("ㆍ", "").replace(".", "")
        return re.sub(r"[^0-9A-Za-z가-힣]", "", text)

    @staticmethod
    def _should_notify_lineup_opened(
        previous: Optional[dict[str, Any]],
        current: dict[str, Any],
    ) -> bool:
        prev_ready = bool(
            previous
            and previous.get("away", {}).get("lineup")
            and previous.get("home", {}).get("lineup")
        )
        curr_ready = bool(
            current.get("away", {}).get("lineup") and current.get("home", {}).get("lineup")
        )
        return (not prev_ready) and curr_ready

    @staticmethod
    def _has_ready_lineup(payload: dict[str, Any]) -> bool:
        return bool(payload.get("away", {}).get("lineup") and payload.get("home", {}).get("lineup"))

    def _should_send_lineup_opened_alert(
        self,
        game_id: str,
        previous: Optional[dict[str, Any]],
        current: dict[str, Any],
    ) -> bool:
        return self._is_current_kbo_game_id(game_id) and self._should_notify_lineup_opened(
            previous,
            current,
        )

    def _is_current_kbo_game_id(self, game_id: str) -> bool:
        game_date = self._game_date_from_id(game_id)
        return game_date is not None and game_date == self.today_provider()

    def _is_past_game_id(self, game_id: str) -> bool:
        game_date = self._game_date_from_id(game_id)
        return game_date is not None and game_date < self.today_provider()

    @staticmethod
    def _game_date_from_id(game_id: str) -> Optional[date_type]:
        if len(game_id) < 8:
            return None
        try:
            return date_type(
                int(game_id[:4]),
                int(game_id[4:6]),
                int(game_id[6:8]),
            )
        except ValueError:
            return None
