from __future__ import annotations

from typing import Any, Optional

from kbo_fans_backend.crawlers.main import MainCrawler
from kbo_fans_backend.crawlers.schedule import ScheduleCrawler
from kbo_fans_backend.services.ticketing import TicketingService
from kbo_fans_backend.storage import JsonSnapshotStore
from kbo_fans_backend.utils.kbo_time import current_kbo_date
from kbo_fans_backend.utils.singleflight import SingleFlight
from kbo_fans_backend.utils.ttl_cache import TtlCache


class ScheduleService:
    _CACHE_TTL_SECONDS = 300

    def __init__(
        self,
        schedule_crawler: Optional[ScheduleCrawler] = None,
        main_crawler: Optional[MainCrawler] = None,
        ticketing_service: Optional[TicketingService] = None,
        snapshot_store: Optional[JsonSnapshotStore] = None,
    ) -> None:
        self.schedule_crawler = schedule_crawler or ScheduleCrawler()
        self.main_crawler = main_crawler or MainCrawler()
        self.ticketing_service = ticketing_service or TicketingService()
        self.snapshot_store = snapshot_store or JsonSnapshotStore()
        self._cache: TtlCache[str, dict[str, Any]] = TtlCache(self._CACHE_TTL_SECONDS)
        self._singleflight: SingleFlight[str] = SingleFlight()

    def get_month_schedule(self, month: str) -> dict[str, Any]:
        cached = self._cache.get(month)
        if cached is not None:
            return cached

        snapshot_record = self.snapshot_store.load("schedule", month)
        snapshot = snapshot_record.get("payload") if snapshot_record is not None else None
        if self._is_reusable_historical_snapshot(month, snapshot):
            self._cache.set(month, snapshot)
            return snapshot

        return self._singleflight.call(
            f"schedule:{month}",
            lambda: self._load_month_schedule(month, snapshot),
        )

    def _load_month_schedule(
        self,
        month: str,
        snapshot: Optional[dict[str, Any]],
    ) -> dict[str, Any]:
        try:
            rows = self.schedule_crawler.get_month_schedule(month)
        except Exception:
            stale = self._cache.get_stale(month)
            if self._is_historical_month(month) and stale is not None:
                return stale
            if self._can_use_snapshot_after_failure(month, snapshot):
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
                    "statusLabel": row.get("statusLabel"),
                    "ticketInfo": self.ticketing_service.build_ticket_info(
                        home_team_id=row["homeId"],
                        game_id=row["gameId"],
                        start_time=row["time"],
                        status=row["status"],
                    ),
                }
            )

        payload = {
            "month": month,
            "days": list(days_by_date.values()),
        }
        payload = self._enrich_current_day_with_main_games(payload)
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
        today_month = current_kbo_date().replace(day=1).isoformat()[:7]
        return month < today_month

    @staticmethod
    def _should_persist_month_snapshot(payload: dict[str, Any]) -> bool:
        games = [game for day in payload.get("days", []) for game in day.get("games", [])]
        return bool(games)

    def _can_use_snapshot_after_failure(
        self,
        month: str,
        snapshot: Optional[dict[str, Any]],
    ) -> bool:
        return self._is_reusable_historical_snapshot(month, snapshot)

    def _is_reusable_historical_snapshot(
        self,
        month: str,
        snapshot: Optional[dict[str, Any]],
    ) -> bool:
        if not self._is_historical_month(month):
            return False
        if not self._is_consistent_snapshot(month, snapshot):
            return False
        games = [
            game
            for day in snapshot.get("days", [])
            for game in day.get("games", [])
        ]
        return bool(games) and all(self._is_reusable_historical_game(game) for game in games)

    @staticmethod
    def _is_reusable_historical_game(game: dict[str, Any]) -> bool:
        status = str(game.get("status") or "").upper()
        if status == "CANCELLED":
            return True
        if status != "FINAL":
            return False
        return all(
            isinstance(game.get(field), int)
            and not isinstance(game.get(field), bool)
            and game[field] >= 0
            for field in ("awayScore", "homeScore")
        )

    @staticmethod
    def _is_consistent_snapshot(month: str, snapshot: Optional[dict[str, Any]]) -> bool:
        if not isinstance(snapshot, dict) or snapshot.get("month") != month:
            return False
        days = snapshot.get("days")
        if not isinstance(days, list):
            return False
        for day in days:
            if not isinstance(day, dict):
                return False
            date = day.get("date")
            if not isinstance(date, str) or not date.startswith(f"{month}-"):
                return False
            games = day.get("games")
            if not isinstance(games, list):
                return False
            for game in games:
                if not isinstance(game, dict):
                    return False
                game_id = game.get("gameId")
                if not isinstance(game_id, str) or not game_id.startswith(
                    date.replace("-", "")
                ):
                    return False
        return True

    def _enrich_current_day_with_main_games(self, payload: dict[str, Any]) -> dict[str, Any]:
        today = current_kbo_date().isoformat()
        if not any(day.get("date") == today for day in payload.get("days", [])):
            return payload

        try:
            main_games = {
                game.get("G_ID"): game for game in self.main_crawler.get_kbo_game_list(today)
            }
        except Exception:
            return payload

        days: list[dict[str, Any]] = []
        for day in payload.get("days", []):
            if day.get("date") != today:
                days.append(day)
                continue

            games = [
                self._merge_main_game_into_schedule_game(game, main_games)
                for game in day.get("games", [])
            ]
            days.append({**day, "games": games})
        return {**payload, "days": days}

    def _merge_main_game_into_schedule_game(
        self,
        game: dict[str, Any],
        main_games: dict[Any, dict[str, Any]],
    ) -> dict[str, Any]:
        main_game = self._find_main_game(game, main_games)
        if not main_game:
            return game

        status = self._map_main_status(main_game.get("GAME_STATE_SC"))
        if status == "UNKNOWN":
            status = str(game.get("status") or "UNKNOWN")
        should_show_score = status in {"LIVE", "FINAL", "SUSPENDED"}
        status_label = self._status_label_for_main_game(status, main_game)
        if status_label is None and status == game.get("status"):
            status_label = game.get("statusLabel")

        updated = {
            **game,
            "time": main_game.get("G_TM") or game.get("time"),
            "awayScore": (
                self._main_score_or_existing(main_game.get("T_SCORE_CN"), game.get("awayScore"))
                if should_show_score
                else None
            ),
            "homeScore": (
                self._main_score_or_existing(main_game.get("B_SCORE_CN"), game.get("homeScore"))
                if should_show_score
                else None
            ),
            "stadium": main_game.get("S_NM") or game.get("stadium"),
            "status": status,
            "statusLabel": status_label,
        }
        updated["ticketInfo"] = self.ticketing_service.build_ticket_info(
            home_team_id=updated.get("homeId"),
            game_id=updated.get("gameId"),
            start_time=updated.get("time"),
            status=status,
        )
        return updated

    @staticmethod
    def _find_main_game(
        game: dict[str, Any],
        main_games: dict[Any, dict[str, Any]],
    ) -> Optional[dict[str, Any]]:
        game_id = game.get("gameId")
        by_id = main_games.get(game_id)
        if by_id is not None:
            return by_id
        for main_game in main_games.values():
            main_game_id = str(main_game.get("G_ID") or "")
            if len(main_game_id) < 12:
                continue
            if main_game_id[8:10] == game.get("awayId") and main_game_id[10:12] == game.get(
                "homeId"
            ):
                return main_game
        return None

    @staticmethod
    def _map_main_status(game_state: Any) -> str:
        return {
            "1": "SCHEDULED",
            "2": "LIVE",
            "3": "FINAL",
            "4": "CANCELLED",
            "5": "SUSPENDED",
        }.get(str(game_state), "UNKNOWN")

    @staticmethod
    def _status_label_for_main_game(
        status: str,
        main_game: dict[str, Any],
    ) -> Optional[str]:
        if status != "CANCELLED":
            return None
        label = str(main_game.get("CANCEL_SC_NM") or "").strip()
        if not label or label == "정상경기":
            return None
        return label

    @staticmethod
    def _parse_int(value: Any) -> Optional[int]:
        try:
            return int(str(value).replace(",", ""))
        except (TypeError, ValueError):
            return None

    @classmethod
    def _main_score_or_existing(cls, value: Any, existing: Any) -> Any:
        if value is None:
            return existing
        parsed = cls._parse_int(value)
        return existing if parsed is None else parsed
