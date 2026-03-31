from __future__ import annotations

import concurrent.futures
import time
from typing import Any, Dict, List, Optional

from kbo_fans_backend.services.records_overview import RecordsOverviewService
from kbo_fans_backend.services.schedule import ScheduleService
from kbo_fans_backend.services.scoreboard import ScoreboardService
from kbo_fans_backend.services.standings import StandingsService
from kbo_fans_backend.utils.ttl_cache import TtlCache


class HomeService:
    _LIVE_CACHE_TTL_SECONDS = 30
    _STABLE_CACHE_TTL_SECONDS = 300
    _TEAM_LABELS = {
        "LG": "LG 트윈스",
        "KT": "KT 위즈",
        "SK": "SSG 랜더스",
        "SS": "삼성 라이온즈",
        "NC": "NC 다이노스",
        "HH": "한화 이글스",
        "LT": "롯데 자이언츠",
        "HT": "KIA 타이거즈",
        "OB": "두산 베어스",
        "WO": "키움 히어로즈",
    }

    def __init__(
        self,
        scoreboard_service: Optional[ScoreboardService] = None,
        schedule_service: Optional[ScheduleService] = None,
        standings_service: Optional[StandingsService] = None,
        records_overview_service: Optional[RecordsOverviewService] = None,
    ) -> None:
        self.scoreboard_service = scoreboard_service or ScoreboardService()
        self.schedule_service = schedule_service or ScheduleService()
        self.standings_service = standings_service or StandingsService()
        self.records_overview_service = (
            records_overview_service or RecordsOverviewService()
        )
        self._live_cache: TtlCache[str, Dict[str, Any]] = TtlCache(
            self._LIVE_CACHE_TTL_SECONDS
        )
        self._stable_cache: TtlCache[str, Dict[str, Any]] = TtlCache(
            self._STABLE_CACHE_TTL_SECONDS
        )

    def get_home(self, date: str, my_team: Optional[str] = None) -> Dict[str, Any]:
        cache_key = f"{date}|{my_team or ''}"
        live_cached = self._live_cache.get(cache_key)
        if live_cached is not None:
            return live_cached

        stable_cached = self._stable_cache.get(cache_key)
        if stable_cached is not None:
            return stable_cached

        scoreboard_payload = self.scoreboard_service.get_home_scoreboard(date)
        games = scoreboard_payload.get("games", [])
        year_month = date[:7]
        season = int(date[:4])

        with concurrent.futures.ThreadPoolExecutor(max_workers=3) as executor:
            schedule_future = executor.submit(
                self.schedule_service.get_month_schedule, year_month
            )
            standings_future = executor.submit(
                self.standings_service.get_standings, season
            )
            overview_future = executor.submit(
                self.records_overview_service.get_overview, season
            )

            schedule_payload = self._safe_result(
                schedule_future,
                {"month": year_month, "days": []},
            )
            standings_payload = self._safe_result(
                standings_future,
                {"season": season, "standings": []},
            )
            overview_payload = self._safe_result(
                overview_future,
                {
                    "season": season,
                    "leaders": {"avg": [], "hr": [], "ops": [], "era": []},
                    "featured": {
                        "todayHitter": {"label": "오늘의 타자"},
                        "todayPitcher": {"label": "오늘의 투수"},
                        "monthHitter": {"label": "이달의 타자"},
                        "monthPitcher": {"label": "이달의 투수"},
                    },
                },
            )

        my_team_brief = self._build_my_team_brief(
            my_team=my_team,
            games=games,
            schedule_days=schedule_payload.get("days", []),
            standings=standings_payload.get("standings", []),
            today=date,
        )
        quick_items = self._build_quick_items(
            my_team_brief=my_team_brief,
            overview=overview_payload,
            games=games,
            season=season,
        )

        payload = {
            "date": date,
            "myTeam": my_team,
            "myTeamBrief": my_team_brief,
            "quickItems": quick_items,
            "meta": {"generatedAt": time.time()},
        }

        if any(game.get("status") == "LIVE" for game in games):
            self._live_cache.set(cache_key, payload)
        else:
            self._stable_cache.set(cache_key, payload)
        return payload

    def _build_my_team_brief(
        self,
        *,
        my_team: Optional[str],
        games: List[Dict[str, Any]],
        schedule_days: List[Dict[str, Any]],
        standings: List[Dict[str, Any]],
        today: str,
    ) -> Optional[Dict[str, Any]]:
        if not my_team:
            return None

        today_game = next(
            (
                game
                for game in games
                if game.get("away", {}).get("teamId") == my_team
                or game.get("home", {}).get("teamId") == my_team
            ),
            None,
        )
        standing = next(
            (item for item in standings if item.get("teamId") == my_team),
            None,
        )

        flat_games = [
            (day.get("date", ""), game)
            for day in schedule_days
            for game in day.get("games", [])
        ]
        flat_games.sort(key=lambda item: item[0])

        recent_games = [
            (date_key, game)
            for date_key, game in flat_games
            if date_key <= today
            and (game.get("awayId") == my_team or game.get("homeId") == my_team)
            and game.get("awayScore") is not None
            and game.get("homeScore") is not None
        ]
        recent_games.sort(key=lambda item: item[0], reverse=True)

        recent_summaries = []
        wins = 0
        losses = 0
        draws = 0
        for _, game in recent_games[:3]:
            is_away = game.get("awayId") == my_team
            my_score = game.get("awayScore") if is_away else game.get("homeScore")
            opponent_score = (
                game.get("homeScore") if is_away else game.get("awayScore")
            )
            if my_score is None or opponent_score is None:
                continue
            if my_score > opponent_score:
                result = "승"
                wins += 1
            elif my_score < opponent_score:
                result = "패"
                losses += 1
            else:
                result = "무"
                draws += 1
            recent_summaries.append(
                {
                    "result": result,
                    "opponentName": (
                        game.get("homeName") if is_away else game.get("awayName")
                    ),
                    "score": f"{my_score}:{opponent_score}",
                }
            )

        next_game = next(
            (
                game
                for date_key, game in flat_games
                if date_key >= today
                and (game.get("awayId") == my_team or game.get("homeId") == my_team)
                and game.get("gameId") != (today_game or {}).get("gameId")
            ),
            None,
        )

        return {
            "teamId": my_team,
            "teamLabel": self._TEAM_LABELS.get(my_team, my_team),
            "standing": standing,
            "todayGameId": (today_game or {}).get("gameId"),
            "nextGame": next_game,
            "recentWins": wins,
            "recentLosses": losses,
            "recentDraws": draws,
            "recentGamesCount": len(recent_summaries),
            "recentSummaries": recent_summaries,
        }

    def _build_quick_items(
        self,
        *,
        my_team_brief: Optional[Dict[str, Any]],
        overview: Dict[str, Any],
        games: List[Dict[str, Any]],
        season: int,
    ) -> List[Dict[str, str]]:
        items: List[Dict[str, str]] = []

        today_game_id = (my_team_brief or {}).get("todayGameId")
        today_game = next(
            (game for game in games if game.get("gameId") == today_game_id),
            None,
        )
        if today_game is not None:
            away = today_game.get("away", {})
            home = today_game.get("home", {})
            away_score = away.get("score")
            home_score = home.get("score")
            if away_score is None or home_score is None:
                title = f"{away.get('shortName')} vs {home.get('shortName')}"
            else:
                title = (
                    f"{away.get('shortName')} {away_score} : "
                    f"{home_score} {home.get('shortName')}"
                )
            items.append(
                {
                    "eyebrow": "마이팀 경기",
                    "title": title,
                    "subtitle": f"{today_game.get('inning')} · {today_game.get('stadium')}",
                    "route": f"/game/{today_game.get('gameId')}",
                    "teamId": (my_team_brief or {}).get("teamId"),
                    "fallbackLabel": (my_team_brief or {}).get("teamLabel"),
                }
            )

        next_game = (my_team_brief or {}).get("nextGame")
        ticket_info = (next_game or {}).get("ticketInfo")
        if next_game and ticket_info and ticket_info.get("openAt"):
            items.append(
                {
                    "eyebrow": "예매 오픈 임박",
                    "title": f"{next_game.get('awayName')} vs {next_game.get('homeName')}",
                    "subtitle": f"{ticket_info.get('vendorName')} · {ticket_info.get('openAt')}",
                    "route": "/schedule",
                    "teamId": my_team_brief.get("teamId") if my_team_brief else None,
                    "fallbackLabel": my_team_brief.get("teamLabel") if my_team_brief else None,
                }
            )

        standing = (my_team_brief or {}).get("standing")
        if standing:
            subtitle = (
                f"{standing.get('wins')}승 {standing.get('losses')}패 {standing.get('draws')}무"
            )
            gb = standing.get("gb")
            if gb == "0":
                subtitle = f"{subtitle} · 공동 선두권"
            elif gb:
                subtitle = f"{subtitle} · {gb}G차"
            items.append(
                {
                    "eyebrow": "마이팀 순위",
                    "title": f"{standing.get('rank')}위 · {standing.get('teamName')}",
                    "subtitle": subtitle,
                    "route": "/standings",
                    "teamId": standing.get("teamId"),
                    "fallbackLabel": standing.get("teamName"),
                }
            )

        hr_leaders = overview.get("leaders", {}).get("hr", [])
        if hr_leaders:
            leader = hr_leaders[0]
            items.append(
                {
                    "eyebrow": "홈런 리더",
                    "title": f"{leader.get('name')} {leader.get('value')}개",
                    "subtitle": f"{self._TEAM_LABELS.get(leader.get('teamId', ''), leader.get('teamId', ''))} · 시즌 홈런 선두",
                    "route": "/records",
                    "teamId": leader.get("teamId"),
                    "fallbackLabel": leader.get("name"),
                }
            )

        featured = overview.get("featured", {}).get("todayHitter", {})
        if not featured.get("name"):
            featured = overview.get("featured", {}).get("todayPitcher", {})
        if featured.get("name"):
            route = (
                f"/records/player/{featured.get('playerId')}?season={season}"
                if featured.get("playerId")
                else "/records"
            )
            items.append(
                {
                    "eyebrow": str(featured.get("label", "오늘의 플레이어")),
                    "title": str(featured.get("name")),
                    "subtitle": " · ".join(
                        part
                        for part in [
                            str(featured.get("headline", "")).strip(),
                            str(featured.get("summary", "")).strip(),
                        ]
                        if part
                    ),
                    "route": route,
                    "teamId": featured.get("teamId"),
                    "imageUrl": featured.get("imageUrl"),
                    "fallbackLabel": featured.get("name"),
                }
            )

        return items[:4]

    @staticmethod
    def _safe_result(
        future: concurrent.futures.Future, fallback: Dict[str, Any]
    ) -> Dict[str, Any]:
        try:
            return future.result()
        except Exception:
            return fallback
