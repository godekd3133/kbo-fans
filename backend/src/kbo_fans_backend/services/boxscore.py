from __future__ import annotations

from datetime import date as date_type
from typing import Any, Optional

from kbo_fans_backend.crawlers.boxscore import BoxscoreCrawler
from kbo_fans_backend.services.schedule import ScheduleService
from kbo_fans_backend.storage import JsonSnapshotStore


class BoxscoreService:
    def __init__(
        self,
        crawler: Optional[BoxscoreCrawler] = None,
        schedule_service: Optional[ScheduleService] = None,
        snapshot_store: Optional[JsonSnapshotStore] = None,
    ) -> None:
        self.crawler = crawler or BoxscoreCrawler()
        self.schedule_service = schedule_service or ScheduleService()
        self.snapshot_store = snapshot_store or JsonSnapshotStore()

    def get_boxscore(self, game_id: str) -> dict[str, Any]:
        snapshot = self.snapshot_store.load_payload("boxscore", game_id)
        if (
            snapshot is not None
            and self._is_past_game_id(game_id)
            and not self._is_empty_payload(snapshot)
        ):
            return snapshot

        try:
            payload = self.crawler.get_boxscore(game_id)
        except Exception:
            if (
                snapshot is not None
                and self._is_past_game_id(game_id)
                and not self._is_empty_payload(snapshot)
            ):
                return snapshot
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
                        self.snapshot_store.save("boxscore", game_id, alternate_payload)
                        return alternate_payload
                except Exception:
                    pass

            if (
                snapshot is not None
                and self._is_past_game_id(game_id)
                and not self._is_empty_payload(snapshot)
            ):
                return snapshot
            return payload

        self.snapshot_store.save("boxscore", game_id, payload)
        return payload

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
        return game_date < date_type.today()
