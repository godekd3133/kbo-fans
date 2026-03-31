from __future__ import annotations

import concurrent.futures
import re
from typing import Any, Optional

from kbo_fans_backend.crawlers.main import MainCrawler
from kbo_fans_backend.crawlers.schedule import ScheduleCrawler
from kbo_fans_backend.crawlers.scoreboard import ScoreboardCrawler
from kbo_fans_backend.services.ticketing import TicketingService
from kbo_fans_backend.utils.ttl_cache import TtlCache


class ScoreboardService:
    _SCOREBOARD_CACHE_TTL_SECONDS = 30

    def __init__(
        self,
        main_crawler: Optional[MainCrawler] = None,
        schedule_crawler: Optional[ScheduleCrawler] = None,
        scoreboard_crawler: Optional[ScoreboardCrawler] = None,
        ticketing_service: Optional[TicketingService] = None,
    ) -> None:
        self.main_crawler = main_crawler or MainCrawler()
        self.schedule_crawler = schedule_crawler or ScheduleCrawler()
        self.scoreboard_crawler = scoreboard_crawler or ScoreboardCrawler()
        self.ticketing_service = ticketing_service or TicketingService()
        self._scoreboard_cache: TtlCache[str, dict[str, Any]] = TtlCache(
            self._SCOREBOARD_CACHE_TTL_SECONDS
        )

    def get_scoreboard(self, date: str) -> dict[str, Any]:
        date = self._normalize_date(date)
        cached = self._scoreboard_cache.get(date)
        if cached is not None:
            return cached

        try:
            games = self.schedule_crawler.get_games_by_date(date)
        except Exception:
            stale = self._scoreboard_cache.get_stale(date)
            if stale is not None:
                return stale
            raise

        try:
            game_list = {
                game["G_ID"]: game for game in self.main_crawler.get_kbo_game_list(date)
            }
        except Exception:
            game_list = {}
        with concurrent.futures.ThreadPoolExecutor(
            max_workers=max(1, min(len(games), 5))
        ) as executor:
            enriched_games = list(
                executor.map(
                    lambda game: self._enrich_game(
                        game, game_list.get(game["gameId"], {})
                    ),
                    games,
                )
            )

        payload = {
            "date": date,
            "games": enriched_games,
        }
        self._scoreboard_cache.set(date, payload)
        return payload

    @staticmethod
    def _normalize_date(value: str) -> str:
        if re.fullmatch(r"\d{8}", value):
            return f"{value[:4]}-{value[4:6]}-{value[6:8]}"
        return value

    def get_game(self, game_id: str) -> Optional[dict[str, Any]]:
        if len(game_id) < 8:
            return None

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
        try:
            detail = self.scoreboard_crawler.get_game_scoreboard(game["gameId"])
        except Exception:
            detail = self._scheduled_fallback_detail(game)
        return {
            **game,
            **self._merge_main_game(main_game),
            **detail,
            "ticketInfo": self.ticketing_service.build_ticket_info(
                home_team_id=game.get("homeId"),
                game_id=game.get("gameId"),
                start_time=main_game.get("G_TM") or game.get("time"),
            ),
            "highlightInfo": {
                "officialUrl": self._build_official_highlight_url(game["gameId"]),
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
    def _build_official_highlight_url(game_id: str) -> str:
        game_date = game_id[:8]
        return (
            "https://www.koreabaseball.com/Schedule/GameCenter/Main.aspx"
            f"?gameDate={game_date}&gameId={game_id}&section=HIGHLIGHT"
        )
