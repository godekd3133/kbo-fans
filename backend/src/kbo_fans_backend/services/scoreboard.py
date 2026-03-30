from __future__ import annotations

from typing import Any, Optional

from kbo_fans_backend.crawlers.main import MainCrawler
from kbo_fans_backend.crawlers.schedule import ScheduleCrawler
from kbo_fans_backend.crawlers.scoreboard import ScoreboardCrawler
from kbo_fans_backend.services.ticketing import TicketingService
from kbo_fans_backend.services.youtube_highlight import YoutubeHighlightService


class ScoreboardService:
    def __init__(
        self,
        main_crawler: Optional[MainCrawler] = None,
        schedule_crawler: Optional[ScheduleCrawler] = None,
        scoreboard_crawler: Optional[ScoreboardCrawler] = None,
        ticketing_service: Optional[TicketingService] = None,
        youtube_highlight_service: Optional[YoutubeHighlightService] = None,
    ) -> None:
        self.main_crawler = main_crawler or MainCrawler()
        self.schedule_crawler = schedule_crawler or ScheduleCrawler()
        self.scoreboard_crawler = scoreboard_crawler or ScoreboardCrawler()
        self.ticketing_service = ticketing_service or TicketingService()
        self.youtube_highlight_service = (
            youtube_highlight_service or YoutubeHighlightService()
        )

    def get_scoreboard(self, date: str) -> dict[str, Any]:
        games = self.schedule_crawler.get_games_by_date(date)
        game_list = {game["G_ID"]: game for game in self.main_crawler.get_kbo_game_list(date)}
        enriched_games = []
        for game in games:
            detail = self.scoreboard_crawler.get_game_scoreboard(game["gameId"])
            main_game = game_list.get(game["gameId"], {})
            enriched_games.append(
                {
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
                        "youtubeVideos": self.youtube_highlight_service.fetch_highlights(
                            game_id=game["gameId"],
                            away_name=game.get("awayName", ""),
                            home_name=game.get("homeName", ""),
                        ),
                    },
                }
            )

        return {
            "date": date,
            "games": enriched_games,
        }

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
