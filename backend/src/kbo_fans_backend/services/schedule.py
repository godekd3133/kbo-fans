from __future__ import annotations

from datetime import date as date_type
from typing import Any, Optional, Tuple

from kbo_fans_backend.crawlers.schedule import ScheduleCrawler
from kbo_fans_backend.services.ticketing import TicketingService
from kbo_fans_backend.storage import JsonSnapshotStore
from kbo_fans_backend.utils.ttl_cache import TtlCache


class ScheduleService:
    _CACHE_TTL_SECONDS = 300

    def __init__(
        self,
        schedule_crawler: Optional[ScheduleCrawler] = None,
        ticketing_service: Optional[TicketingService] = None,
        snapshot_store: Optional[JsonSnapshotStore] = None,
    ) -> None:
        self.schedule_crawler = schedule_crawler or ScheduleCrawler()
        self.ticketing_service = ticketing_service or TicketingService()
        self.snapshot_store = snapshot_store or JsonSnapshotStore()
        self._cache: TtlCache[str, dict[str, Any]] = TtlCache(self._CACHE_TTL_SECONDS)

    def get_month_schedule(self, month: str) -> dict[str, Any]:
        cached = self._cache.get(month)
        if cached is not None:
            return cached

        snapshot = self.snapshot_store.load_payload("schedule", month)
        if self._is_historical_month(month) and snapshot is not None:
            self._cache.set(month, snapshot)
            return snapshot

        try:
            rows = self.schedule_crawler.get_month_schedule(month)
        except Exception:
            stale = self._cache.get_stale(month)
            if stale is not None:
                return stale
            if snapshot is not None:
                return snapshot
            raise

        days_by_date: dict[str, dict[str, Any]] = {}
        for row in rows:
            date = row["date"]
            if date not in days_by_date:
                days_by_date[date] = {
                    "date": date,
                    "label": None,
                    "games": [],
                }
            days_by_date[date]["games"].append(
                {
                    "gameId": row["gameId"],
                    "time": row["time"],
                    "awayId": row["awayId"],
                    "awayName": row["awayName"],
                    "awayScore": row["awayScore"],
                    "homeId": row["homeId"],
                    "homeName": row["homeName"],
                    "homeScore": row["homeScore"],
                    "stadium": row["stadium"],
                    "status": row["status"],
                    "ticketInfo": self.ticketing_service.build_ticket_info(
                        home_team_id=row["homeId"],
                        game_id=row["gameId"],
                        start_time=row["time"],
                    ),
                }
            )

        payload = {
            "month": month,
            "days": list(days_by_date.values()),
        }
        self._cache.set(month, payload)
        if self._should_persist_month_snapshot(payload):
            self.snapshot_store.save("schedule", month, payload)
        return payload

    def get_schedule_game(self, game_id: str) -> Optional[dict[str, Any]]:
        month = f"{game_id[:4]}-{game_id[4:6]}"
        payload = self.get_month_schedule(month)
        for day in payload.get("days", []):
            for row in day.get("games", []):
                if row["gameId"] == game_id:
                    return row

        return None

    @staticmethod
    def _is_historical_month(month: str) -> bool:
        today_month = date_type.today().replace(day=1).isoformat()[:7]
        return month < today_month

    @staticmethod
    def _should_persist_month_snapshot(payload: dict[str, Any]) -> bool:
        terminal_statuses = {"FINAL", "CANCELLED", "SUSPENDED"}
        games = [
            game
            for day in payload.get("days", [])
            for game in day.get("games", [])
        ]
        return bool(games) and all(game.get("status") in terminal_statuses for game in games)
