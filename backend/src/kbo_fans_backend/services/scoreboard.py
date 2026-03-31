from __future__ import annotations

import concurrent.futures
import logging
import re
import time
from datetime import date as date_type
from typing import Any, Optional

from kbo_fans_backend.crawlers.main import MainCrawler
from kbo_fans_backend.crawlers.schedule import ScheduleCrawler
from kbo_fans_backend.crawlers.scoreboard import ScoreboardCrawler
from kbo_fans_backend.services.ticketing import TicketingService
from kbo_fans_backend.storage import JsonSnapshotStore
from kbo_fans_backend.utils.ttl_cache import TtlCache

logger = logging.getLogger(__name__)


class ScoreboardService:
    _SCOREBOARD_CACHE_TTL_SECONDS = 30

    def __init__(
        self,
        main_crawler: Optional[MainCrawler] = None,
        schedule_crawler: Optional[ScheduleCrawler] = None,
        scoreboard_crawler: Optional[ScoreboardCrawler] = None,
        ticketing_service: Optional[TicketingService] = None,
        snapshot_store: Optional[JsonSnapshotStore] = None,
    ) -> None:
        self.main_crawler = main_crawler or MainCrawler()
        self.schedule_crawler = schedule_crawler or ScheduleCrawler()
        self.scoreboard_crawler = scoreboard_crawler or ScoreboardCrawler()
        self.ticketing_service = ticketing_service or TicketingService()
        self.snapshot_store = snapshot_store or JsonSnapshotStore()
        self._scoreboard_cache: TtlCache[str, dict[str, Any]] = TtlCache(
            self._SCOREBOARD_CACHE_TTL_SECONDS
        )

    def get_scoreboard(self, date: str) -> dict[str, Any]:
        started_at = time.perf_counter()
        date = self._normalize_date(date)
        snapshot = self.snapshot_store.load_payload("scoreboard", date)
        if self._is_historical_date(date) and snapshot is not None:
            logger.info("scoreboard snapshot hit %s", date)
            return snapshot

        cached = self._scoreboard_cache.get(date)
        if cached is not None:
            logger.info("scoreboard cache hit %s", date)
            return cached

        try:
            schedule_started_at = time.perf_counter()
            games = self.schedule_crawler.get_games_by_date(date)
            logger.info(
                "scoreboard schedule %s %.0fms (%s games)",
                date,
                (time.perf_counter() - schedule_started_at) * 1000,
                len(games),
            )
        except Exception:
            stale = self._scoreboard_cache.get_stale(date)
            if stale is not None:
                logger.warning("scoreboard stale cache fallback %s", date)
                return stale
            if snapshot is not None:
                logger.warning("scoreboard snapshot fallback %s", date)
                return snapshot
            raise

        try:
            main_started_at = time.perf_counter()
            game_list = {
                game["G_ID"]: game for game in self.main_crawler.get_kbo_game_list(date)
            }
            logger.info(
                "scoreboard main list %s %.0fms",
                date,
                (time.perf_counter() - main_started_at) * 1000,
            )
        except Exception:
            game_list = {}
            logger.warning("scoreboard main list failed %s", date)
        with concurrent.futures.ThreadPoolExecutor(
            max_workers=max(1, min(len(games), 5))
        ) as executor:
            enrich_started_at = time.perf_counter()
            enriched_games = list(
                executor.map(
                    lambda game: self._enrich_game(
                        game, game_list.get(game.get("gameId"), {})
                    ),
                    games,
                )
            )
            logger.info(
                "scoreboard enrich %s %.0fms",
                date,
                (time.perf_counter() - enrich_started_at) * 1000,
            )

        payload = {
            "date": date,
            "games": enriched_games,
        }
        self._scoreboard_cache.set(date, payload)
        if self._should_persist_snapshot(date, enriched_games):
            self.snapshot_store.save("scoreboard", date, payload)
            for game in enriched_games:
                game_id = game.get("gameId")
                if game_id:
                    self.snapshot_store.save("games", str(game_id), game)
        logger.info(
            "scoreboard total %s %.0fms",
            date,
            (time.perf_counter() - started_at) * 1000,
        )
        return payload

    def get_home_scoreboard(self, date: str) -> dict[str, Any]:
        payload = self.get_scoreboard(date)
        return {
            "date": payload["date"],
            "games": [self._strip_home_payload(game) for game in payload["games"]],
        }

    @staticmethod
    def _normalize_date(value: str) -> str:
        if re.fullmatch(r"\d{8}", value):
            return f"{value[:4]}-{value[4:6]}-{value[6:8]}"
        return value

    def get_game(self, game_id: str) -> Optional[dict[str, Any]]:
        if len(game_id) < 8:
            return None

        snapshot = self.snapshot_store.load_payload("games", game_id)
        if snapshot is not None:
            return snapshot

        date = f"{game_id[:4]}-{game_id[4:6]}-{game_id[6:8]}"
        try:
            games = self.get_scoreboard(date)["games"]
        except Exception:
            return None

        for game in games:
            if game.get("gameId") == game_id:
                return game
        return None

    def _enrich_game(
        self, game: dict[str, Any], main_game: dict[str, Any]
    ) -> dict[str, Any]:
        game_id = game.get("gameId")
        resolved_status = str(game.get("status") or "")
        if main_game:
            resolved_status = self._map_status(main_game.get("GAME_STATE_SC"))

        if not game_id or resolved_status == "SCHEDULED":
            detail = self._scheduled_fallback_detail(game)
        else:
            try:
                detail = self.scoreboard_crawler.get_game_scoreboard(game_id)
            except Exception:
                detail = self._scheduled_fallback_detail(game)
        return {
            **game,
            **self._merge_main_game(main_game),
            **detail,
            "ticketInfo": self.ticketing_service.build_ticket_info(
                home_team_id=game.get("homeId"),
                game_id=game_id,
                start_time=main_game.get("G_TM") or game.get("time"),
            ),
            "highlightInfo": {
                "officialUrl": self._build_official_highlight_url(game_id),
                "youtubeVideos": [],
            },
        }

    @staticmethod
    def _scheduled_fallback_detail(game: dict[str, Any]) -> dict[str, Any]:
        return {
            "inning": f"{game.get('time', '')} 예정".strip() or "예정",
            "stadium": game.get("stadium"),
            "crowd": None,
            "startTime": game.get("time"),
            "away": {
                "teamId": game.get("awayId"),
                "teamName": game.get("awayName"),
                "shortName": game.get("awayName"),
                "logoUrl": None,
                "score": game.get("awayScore"),
                "scores": [None] * 9,
                "hits": None,
                "errors": None,
                "balls": None,
            },
            "home": {
                "teamId": game.get("homeId"),
                "teamName": game.get("homeName"),
                "shortName": game.get("homeName"),
                "logoUrl": None,
                "score": game.get("homeScore"),
                "scores": [None] * 9,
                "hits": None,
                "errors": None,
                "balls": None,
            },
        }

    def _merge_main_game(self, main_game: dict[str, Any]) -> dict[str, Any]:
        if not main_game:
            return {}
        inning = self._format_inning(main_game)
        return {
            "status": self._map_status(main_game.get("GAME_STATE_SC")),
            "inning": inning,
            "startTime": main_game.get("G_TM"),
            "current": {
                "balls": main_game.get("BALL_CN"),
                "strikes": main_game.get("STRIKE_CN"),
                "outs": main_game.get("OUT_CN"),
                "batterName": main_game.get("B_P_NM"),
                "pitcherName": main_game.get("T_P_NM"),
            },
        }

    @staticmethod
    def _map_status(game_state: Any) -> str:
        return {
            "1": "SCHEDULED",
            "2": "LIVE",
            "3": "FINAL",
            "4": "CANCELLED",
            "5": "SUSPENDED",
        }.get(str(game_state), "UNKNOWN")

    def _format_inning(self, main_game: dict[str, Any]) -> str:
        status = self._map_status(main_game.get("GAME_STATE_SC"))
        if status == "FINAL":
            return "경기종료"
        if status == "SCHEDULED":
            return f"{main_game.get('G_TM', '')} 예정".strip()
        inning_no = main_game.get("GAME_INN_NO")
        half = main_game.get("GAME_TB_SC_NM")
        if inning_no and half:
            return f"{inning_no}회{half}"
        return status

    @staticmethod
    def _build_official_highlight_url(game_id: Optional[str]) -> str:
        if not game_id:
            return ""
        game_date = game_id[:8]
        return (
            "https://www.koreabaseball.com/Schedule/GameCenter/Main.aspx"
            f"?gameDate={game_date}&gameId={game_id}&section=HIGHLIGHT"
        )

    @staticmethod
    def _is_historical_date(date: str) -> bool:
        try:
            return date_type.fromisoformat(date) < date_type.today()
        except ValueError:
            return False

    def _should_persist_snapshot(self, date: str, games: list[dict[str, Any]]) -> bool:
        if self._is_historical_date(date):
            return True

        terminal_statuses = {"FINAL", "CANCELLED", "SUSPENDED"}
        return bool(games) and all(game.get("status") in terminal_statuses for game in games)

    @staticmethod
    def _strip_home_payload(game: dict[str, Any]) -> dict[str, Any]:
        return {
            "gameId": game.get("gameId"),
            "status": game.get("status"),
            "inning": game.get("inning"),
            "stadium": game.get("stadium"),
            "startTime": game.get("startTime"),
            "crowd": game.get("crowd"),
            "ticketInfo": game.get("ticketInfo"),
            "away": game.get("away"),
            "home": game.get("home"),
        }
