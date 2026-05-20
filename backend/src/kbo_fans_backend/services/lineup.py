from __future__ import annotations

from datetime import date as date_type
from typing import Any, Optional

from kbo_fans_backend.crawlers.boxscore import BoxscoreCrawler
from kbo_fans_backend.crawlers.lineup import LineupCrawler
from kbo_fans_backend.crawlers.main import MainCrawler
from kbo_fans_backend.services.push import PushService
from kbo_fans_backend.storage import JsonSnapshotStore


class LineupService:
    _PLAYER_IMAGE_URL = (
        "https://6ptotvmi5753.edge.naverncp.com/KBO_IMAGE/person/middle/{season}/{player_id}.jpg"
    )

    def __init__(
        self,
        lineup_crawler: Optional[LineupCrawler] = None,
        boxscore_crawler: Optional[BoxscoreCrawler] = None,
        main_crawler: Optional[MainCrawler] = None,
        snapshot_store: Optional[JsonSnapshotStore] = None,
        push_service: Optional[PushService] = None,
    ) -> None:
        self.lineup_crawler = lineup_crawler or LineupCrawler()
        self.boxscore_crawler = boxscore_crawler or BoxscoreCrawler()
        self.main_crawler = main_crawler or MainCrawler()
        self.snapshot_store = snapshot_store or JsonSnapshotStore()
        self.push_service = push_service or PushService()

    def get_lineup(self, game_id: str) -> dict[str, Any]:
        snapshot = self.snapshot_store.load_payload("lineup", game_id)
        if (
            snapshot is not None
            and self._is_past_game_id(game_id)
            and self._has_ready_lineup(snapshot)
        ):
            return snapshot

        try:
            lineup = self.lineup_crawler.get_lineup(game_id)
            boxscore = self.boxscore_crawler.get_boxscore(game_id)
        except Exception:
            if snapshot is not None:
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

        if self._should_notify_lineup_opened(snapshot, lineup):
            try:
                self.push_service.send_lineup_opened(
                    game_id=game_id,
                    away_team_id=lineup["away"]["teamId"],
                    away_team_name=lineup["away"].get("teamName") or lineup["away"]["teamId"],
                    home_team_id=lineup["home"]["teamId"],
                    home_team_name=lineup["home"].get("teamName") or lineup["home"]["teamId"],
                )
            except Exception:
                pass

        self.snapshot_store.save("lineup", game_id, lineup)
        return lineup

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
        return self._PLAYER_IMAGE_URL.format(season=game_id[:4], player_id=starter_id)

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
        return game_date < date_type.today()
