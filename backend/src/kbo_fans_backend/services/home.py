from __future__ import annotations

import concurrent.futures
import time
from datetime import date as date_type
from datetime import timedelta
from typing import Any, Dict, List, Optional

from kbo_fans_backend.services.records_overview import RecordsOverviewService
from kbo_fans_backend.services.schedule import ScheduleService
from kbo_fans_backend.services.scoreboard import ScoreboardService
from kbo_fans_backend.services.standings import StandingsService
from kbo_fans_backend.utils.kbo_time import current_kbo_date
from kbo_fans_backend.utils.player_images import kbo_player_image_url
from kbo_fans_backend.utils.ttl_cache import TtlCache


class HomeService:
    _LIVE_CACHE_TTL_SECONDS = 8
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
    _TEAM_SHORT_LABELS = {
        "LG": "LG",
        "KT": "KT",
        "SK": "SSG",
        "SS": "삼성",
        "NC": "NC",
        "HH": "한화",
        "LT": "롯데",
        "HT": "KIA",
        "OB": "두산",
        "WO": "키움",
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
        self.records_overview_service = records_overview_service or RecordsOverviewService()
        self._live_cache: TtlCache[str, Dict[str, Any]] = TtlCache(self._LIVE_CACHE_TTL_SECONDS)
        self._stable_cache: TtlCache[str, Dict[str, Any]] = TtlCache(self._STABLE_CACHE_TTL_SECONDS)

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
        allow_partial_sections = self._is_historical_date(date)

        with concurrent.futures.ThreadPoolExecutor(max_workers=3) as executor:
            schedule_future = executor.submit(self.schedule_service.get_month_schedule, year_month)
            standings_future = executor.submit(self.standings_service.get_standings, season)
            overview_future = executor.submit(self.records_overview_service.get_overview, season)

            schedule_payload = self._section_result(
                schedule_future,
                {"month": year_month, "days": []},
                allow_fallback=allow_partial_sections,
            )
            standings_payload = self._section_result(
                standings_future,
                {"season": season, "standings": []},
                allow_fallback=allow_partial_sections,
            )
            overview_payload = self._section_result(
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
                allow_fallback=allow_partial_sections,
            )

        schedule_days = self._schedule_days_with_recent_context(
            today=date,
            my_team=my_team,
            current_schedule_payload=schedule_payload,
        )

        my_team_brief = self._build_my_team_brief(
            my_team=my_team,
            games=games,
            schedule_days=schedule_days,
            standings=standings_payload.get("standings", []),
            today=date,
        )
        kbo_brief = self._build_kbo_brief(
            today=date,
            my_team=my_team,
            games=games,
            standings=standings_payload.get("standings", []),
            overview=overview_payload,
        )
        quick_items = self._build_quick_items(
            my_team_brief=my_team_brief,
            overview=overview_payload,
            games=games,
            season=season,
        )
        standings_preview = self._build_standings_preview(
            standings=standings_payload.get("standings", []),
            my_team=my_team,
        )

        payload = {
            "date": date,
            "myTeam": my_team,
            "myTeamBrief": my_team_brief,
            "kboBrief": kbo_brief,
            "quickItems": quick_items,
            "standingsPreview": standings_preview,
            "meta": {"generatedAt": time.time()},
        }

        if any(game.get("status") == "LIVE" for game in games):
            self._live_cache.set(cache_key, payload)
        else:
            self._stable_cache.set(cache_key, payload)
        return payload

    def _schedule_days_with_recent_context(
        self,
        *,
        today: str,
        my_team: Optional[str],
        current_schedule_payload: Dict[str, Any],
    ) -> List[Dict[str, Any]]:
        schedule_days = list(current_schedule_payload.get("days", []))
        if not my_team:
            return schedule_days

        if self._recent_result_count(
            schedule_days=schedule_days,
            my_team=my_team,
            today=today,
        ) >= 5:
            return schedule_days

        previous_month = self._previous_year_month(today)
        if previous_month is None:
            return schedule_days

        try:
            previous_payload = self.schedule_service.get_month_schedule(previous_month)
        except Exception:
            return schedule_days
        return [*previous_payload.get("days", []), *schedule_days]

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
            (day.get("date", ""), game) for day in schedule_days for game in day.get("games", [])
        ]
        flat_games.sort(key=lambda item: item[0])

        recent_games = [
            (date_key, game)
            for date_key, game in flat_games
            if date_key <= today
            and (game.get("awayId") == my_team or game.get("homeId") == my_team)
            and self._is_completed_schedule_game(game)
            and game.get("awayScore") is not None
            and game.get("homeScore") is not None
        ]
        recent_games.sort(key=lambda item: item[0], reverse=True)

        recent_summaries = []
        wins = 0
        losses = 0
        draws = 0
        for _, game in recent_games[:5]:
            is_away = game.get("awayId") == my_team
            my_score = game.get("awayScore") if is_away else game.get("homeScore")
            opponent_score = game.get("homeScore") if is_away else game.get("awayScore")
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
                    "gameId": game.get("gameId"),
                    "result": result,
                    "opponentName": (game.get("homeName") if is_away else game.get("awayName")),
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

    def _recent_result_count(
        self,
        *,
        schedule_days: List[Dict[str, Any]],
        my_team: str,
        today: str,
    ) -> int:
        return sum(
            1
            for day in schedule_days
            for game in day.get("games", [])
            if day.get("date", "") <= today
            and (game.get("awayId") == my_team or game.get("homeId") == my_team)
            and self._is_completed_schedule_game(game)
            and game.get("awayScore") is not None
            and game.get("homeScore") is not None
        )

    def _build_kbo_brief(
        self,
        *,
        today: str,
        my_team: Optional[str],
        games: List[Dict[str, Any]],
        standings: List[Dict[str, Any]],
        overview: Dict[str, Any],
    ) -> Dict[str, Any]:
        live_games = [game for game in games if game.get("status") == "LIVE"]
        final_games = [game for game in games if game.get("status") == "FINAL"]
        scheduled_games = [game for game in games if game.get("status") == "SCHEDULED"]
        active_games = [
            game for game in [*live_games, *final_games] if self._game_total_score(game) > 0
        ]

        items: List[Dict[str, Any]] = []

        def add(item: Dict[str, Any]) -> None:
            duplicate = any(
                existing.get("route") == item.get("route")
                and existing.get("eyebrow") == item.get("eyebrow")
                for existing in items
            )
            if not duplicate:
                items.append(item)

        close_games = [
            game
            for game in active_games
            if abs(self._team_score(game, "away") - self._team_score(game, "home")) <= 1
        ]
        close_games.sort(
            key=lambda game: (
                0 if game.get("status") == "LIVE" else 1,
                -self._game_total_score(game),
            )
        )
        if close_games:
            game = close_games[0]
            add(
                self._kbo_brief_item(
                    item_type="game_flow",
                    eyebrow="접전 진행 중" if game.get("status") == "LIVE" else "1점 승부",
                    title=self._score_line(game),
                    subtitle=f"{self._game_time_label(game)} · {game.get('stadium') or ''}".strip(
                        " ·"
                    ),
                    route=f"/game/{game.get('gameId')}",
                    game=game,
                )
            )

        highest_score_games = sorted(
            active_games,
            key=lambda game: self._game_total_score(game),
            reverse=True,
        )
        if highest_score_games:
            game = highest_score_games[0]
            add(
                self._kbo_brief_item(
                    item_type="game_flow",
                    eyebrow=(
                        "득점전 진행 중" if game.get("status") == "LIVE" else "최다 득점 경기"
                    ),
                    title=self._score_line(game),
                    subtitle=(
                        f"양팀 {self._game_total_score(game)}득점 · "
                        f"{self._game_time_label(game)}"
                    ),
                    route=f"/game/{game.get('gameId')}",
                    game=game,
                )
            )

        high_hit_games = [game for game in active_games if self._game_total_hits(game) >= 18]
        high_hit_games.sort(
            key=lambda game: self._game_total_hits(game),
            reverse=True,
        )
        if high_hit_games:
            game = high_hit_games[0]
            add(
                self._kbo_brief_item(
                    item_type="player_performance",
                    eyebrow="안타 공방",
                    title=(
                        f"{self._team_short_name(game, 'away')}-"
                        f"{self._team_short_name(game, 'home')} 합계 "
                        f"{self._game_total_hits(game)}안타"
                    ),
                    subtitle=f"{self._score_line(game)} · 타격전 체크",
                    route=f"/game/{game.get('gameId')}",
                    game=game,
                )
            )

        high_error_games = [
            game for game in active_games if self._game_total_errors(game) >= 3
        ]
        high_error_games.sort(
            key=lambda game: self._game_total_errors(game),
            reverse=True,
        )
        if high_error_games:
            game = high_error_games[0]
            add(
                self._kbo_brief_item(
                    item_type="defense_issue",
                    eyebrow="실책 많은 경기",
                    title=(
                        f"{self._team_short_name(game, 'away')}-"
                        f"{self._team_short_name(game, 'home')} 합계 "
                        f"{self._game_total_errors(game)}실책"
                    ),
                    subtitle=(
                        f"{self._team_short_name(game, 'away')} "
                        f"{self._team_errors(game, 'away')}실책 · "
                        f"{self._team_short_name(game, 'home')} "
                        f"{self._team_errors(game, 'home')}실책"
                    ),
                    route=f"/game/{game.get('gameId')}",
                    game=game,
                )
            )

        error_rank_item = self._build_error_rank_brief_item(active_games, today)
        if error_rank_item is not None:
            add(error_rank_item)

        if len(live_games) > 1:
            add(
                {
                    "type": "league_now",
                    "eyebrow": "LIVE",
                    "title": f"지금 {len(live_games)}경기 진행 중",
                    "subtitle": "스코어보드에서 접전과 흐름 변화를 같이 확인하세요.",
                    "route": "/schedule",
                    "gameId": None,
                    "teamIds": self._team_ids_for_games(live_games),
                }
            )

        if scheduled_games:
            game = scheduled_games[0]
            add(
                self._kbo_brief_item(
                    item_type="big_match",
                    eyebrow="오늘 일정",
                    title=(
                        f"{self._team_short_name(game, 'away')} vs "
                        f"{self._team_short_name(game, 'home')}"
                    ),
                    subtitle=(
                        f"{game.get('startTime') or game.get('time') or ''} · "
                        f"{game.get('stadium') or ''} · 오늘 {len(scheduled_games)}경기 예정"
                    ).strip(" ·"),
                    route=f"/game/{game.get('gameId')}",
                    game=game,
                )
            )

        standings_item = self._build_standings_brief_item(standings)
        if standings_item is not None:
            add(standings_item)

        milestone_item = self._build_record_milestone_brief_item(
            overview,
            season=int(today[:4]),
            my_team=my_team,
        )
        if milestone_item is not None:
            add(milestone_item)

        record_item = self._build_record_brief_item(overview, int(today[:4]))
        if record_item is not None:
            add(record_item)

        avg_item = self._build_avg_brief_item(overview, int(today[:4]), today)
        if avg_item is not None:
            add(avg_item)

        if not items:
            add(
                {
                    "type": "offday",
                    "eyebrow": "리그 체크",
                    "title": "오늘은 KBO 경기가 없습니다",
                    "subtitle": "순위표와 리더보드로 다음 경기 흐름을 확인하세요.",
                    "route": "/schedule",
                    "gameId": None,
                    "teamIds": [],
                }
            )

        prioritized_items = self._prioritize_kbo_brief_items(items, my_team)[:8]
        return {
            "title": self._kbo_brief_title(
                today=today,
                has_games=bool(games),
                has_live=bool(live_games),
                has_final=bool(final_games),
            ),
            "subtitle": self._kbo_brief_subtitle(
                total_games=len(games),
                live_games=len(live_games),
                final_games=len(final_games),
                scheduled_games=len(scheduled_games),
            ),
            "items": prioritized_items,
        }

    def _build_quick_items(
        self,
        *,
        my_team_brief: Optional[Dict[str, Any]],
        overview: Dict[str, Any],
        games: List[Dict[str, Any]],
        season: int,
    ) -> List[Dict[str, Any]]:
        items: List[Dict[str, Any]] = []

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
                title = (
                    f"{self._team_short_name(today_game, 'away')} vs "
                    f"{self._team_short_name(today_game, 'home')}"
                )
            else:
                title = self._score_line(today_game)
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
            player_id = str(leader.get("playerId") or "")
            team_label = self._TEAM_LABELS.get(
                leader.get("teamId", ""),
                leader.get("teamId", ""),
            )
            items.append(
                {
                    "eyebrow": "홈런왕",
                    "title": f"{leader.get('name')} {leader.get('value')}개",
                    "subtitle": f"{team_label} · 시즌 홈런 1위",
                    "route": (
                        f"/records/player/{player_id}?season={season}" if player_id else "/records"
                    ),
                    "teamId": leader.get("teamId"),
                    "imageUrl": self._record_leader_image_url(leader, season),
                    "fallbackLabel": leader.get("name"),
                }
            )

        for featured in [
            overview.get("featured", {}).get("todayHitter", {}),
            overview.get("featured", {}).get("todayPitcher", {}),
        ]:
            if not featured.get("name"):
                continue
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

        return items[:6]

    def _build_standings_brief_item(
        self,
        standings: List[Dict[str, Any]],
    ) -> Optional[Dict[str, Any]]:
        if not standings:
            return None

        sorted_standings = sorted(
            standings,
            key=lambda item: self._as_int(item.get("rank"), fallback=999),
        )
        leader = sorted_standings[0]
        second = sorted_standings[1] if len(sorted_standings) > 1 else None
        second_gap = str((second or {}).get("gb") or "")
        subtitle = (
            f"{second.get('teamName')}와 {second_gap}G차"
            if second is not None and second_gap and second_gap != "-"
            else "선두권 흐름 확인"
        )
        second_gap_value = self._as_float(second_gap)
        title = (
            f"선두가 위태로운 {leader.get('teamName')}"
            if second_gap_value is not None and second_gap_value <= 2
            else f"선두 지키는 {leader.get('teamName')}"
        )
        return {
            "type": "standings",
            "eyebrow": "선두권",
            "title": title,
            "subtitle": subtitle,
            "route": "/standings",
            "gameId": None,
            "teamIds": [
                team_id
                for team_id in [leader.get("teamId"), (second or {}).get("teamId")]
                if isinstance(team_id, str) and team_id
            ],
        }

    def _build_standings_preview(
        self,
        *,
        standings: List[Dict[str, Any]],
        my_team: Optional[str],
    ) -> List[Dict[str, Any]]:
        if not standings:
            return []

        sorted_standings = sorted(
            standings,
            key=lambda item: self._as_int(item.get("rank"), fallback=999),
        )
        return [self._standings_preview_item(item) for item in sorted_standings]

    def _standings_preview_item(self, item: Dict[str, Any]) -> Dict[str, Any]:
        return {
            "rank": self._as_int(item.get("rank"), fallback=0),
            "teamId": str(item.get("teamId") or ""),
            "teamName": str(item.get("teamName") or item.get("teamId") or ""),
            "wins": self._as_int(item.get("wins"), fallback=0),
            "losses": self._as_int(item.get("losses"), fallback=0),
            "draws": self._as_int(item.get("draws"), fallback=0),
            "pct": str(item.get("pct") or ".000"),
            "gb": str(item.get("gb") or "-"),
            "streak": str(item.get("streak") or ""),
        }

    def _build_record_brief_item(
        self,
        overview: Dict[str, Any],
        season: int,
    ) -> Optional[Dict[str, Any]]:
        hr_leaders = overview.get("leaders", {}).get("hr", [])
        if not hr_leaders:
            return None

        leader = hr_leaders[0]
        player_id = str(leader.get("playerId") or "")
        team_id = str(leader.get("teamId") or "")
        route = f"/records/player/{player_id}?season={season}" if player_id else "/records"
        return {
            "type": "record_radar",
            "eyebrow": "기록 레이더",
            "title": f"{leader.get('name')} {leader.get('value')}홈런",
            "subtitle": f"{self._TEAM_LABELS.get(team_id, team_id)} · 시즌 홈런 1위",
            "route": route,
            "gameId": None,
            "teamIds": [team_id] if team_id else [],
            "imageUrl": self._record_leader_image_url(leader, season),
            "fallbackLabel": leader.get("name"),
        }

    def _build_record_milestone_brief_item(
        self,
        overview: Dict[str, Any],
        *,
        season: int,
        my_team: Optional[str],
    ) -> Optional[Dict[str, Any]]:
        raw_leaders = (
            (overview.get("leaders") or {}).get("milestones")
            or overview.get("milestones")
            or []
        )
        leaders = [
            leader
            for leader in raw_leaders
            if isinstance(leader, dict)
            and str(leader.get("name") or "").strip()
            and str(leader.get("value") or leader.get("milestoneLabel") or "").strip()
        ]
        if not leaders:
            return None

        leader = next(
            (
                item
                for item in leaders
                if my_team and str(item.get("teamId") or "") == my_team
            ),
            leaders[0],
        )
        player_id = str(leader.get("playerId") or "")
        team_id = str(leader.get("teamId") or "")
        milestone_label = self._record_milestone_label(leader)
        route = f"/records/player/{player_id}?season={season}" if player_id else "/records"
        subtitle_parts = [
            self._TEAM_LABELS.get(team_id, team_id),
            self._record_milestone_rank_label(leader),
        ]
        return {
            "type": "record_milestone",
            "eyebrow": "기록 달성",
            "title": f"{leader.get('name')} {milestone_label} 달성",
            "subtitle": " · ".join(part for part in subtitle_parts if part),
            "route": route,
            "gameId": None,
            "teamIds": [team_id] if team_id else [],
            "imageUrl": self._record_leader_image_url(leader, season),
            "fallbackLabel": leader.get("name"),
        }

    @staticmethod
    def _record_milestone_label(leader: Dict[str, Any]) -> str:
        explicit = str(leader.get("milestoneLabel") or "").strip()
        if explicit:
            return explicit

        value = str(leader.get("value") or "").strip()
        metric_key = str(leader.get("metricKey") or "").upper()
        unit = {
            "TB": "루타",
            "TOTAL_BASES": "루타",
            "H": "안타",
            "HIT": "안타",
            "HITS": "안타",
            "HR": "홈런",
            "RBI": "타점",
            "SB": "도루",
            "SV": "세이브",
            "W": "승",
        }.get(metric_key, "")
        return f"{value}{unit}" if unit else value

    @staticmethod
    def _record_milestone_rank_label(leader: Dict[str, Any]) -> str:
        rank = HomeService._as_int(
            leader.get("allTimeRank") or leader.get("milestoneRank"),
            fallback=0,
        )
        return f"역대 {rank}번째" if rank > 0 else ""

    def _build_error_rank_brief_item(
        self,
        games: List[Dict[str, Any]],
        today: str,
    ) -> Optional[Dict[str, Any]]:
        entries: List[Dict[str, Any]] = []
        seen: set[str] = set()
        for game in games:
            for side in ("away", "home"):
                errors = self._team_errors(game, side)
                if errors <= 0:
                    continue
                team_id = str((game.get(side) or {}).get("teamId") or "")
                key = team_id or f"{game.get('gameId')}:{side}"
                if key in seen:
                    continue
                seen.add(key)
                entries.append(
                    {
                        "teamId": team_id,
                        "label": self._team_short_name(game, side),
                        "errors": errors,
                    }
                )

        entries.sort(key=lambda item: item["errors"], reverse=True)
        if len(entries) < 2:
            return None

        leaders = entries[:3]
        title = " · ".join(f"{item['label']} {item['errors']}개" for item in leaders[:2])
        return {
            "type": "defense_rank",
            "eyebrow": "팀별 실책",
            "title": title,
            "subtitle": f"{self._month_day_label(today)} 경기 기준 · 실책 많은 팀 순",
            "route": "/schedule",
            "gameId": None,
            "teamIds": [
                item["teamId"] for item in leaders if isinstance(item.get("teamId"), str)
            ],
        }

    def _build_avg_brief_item(
        self,
        overview: Dict[str, Any],
        season: int,
        today: str,
    ) -> Optional[Dict[str, Any]]:
        avg_leaders = overview.get("leaders", {}).get("avg", [])
        if not avg_leaders:
            return None

        leader = avg_leaders[0]
        player_id = str(leader.get("playerId") or "")
        team_id = str(leader.get("teamId") or "")
        route = (
            f"/records/player/{player_id}?season={season}"
            if player_id
            else "/records"
        )
        return {
            "type": "batting_leader",
            "eyebrow": f"{self._month_label(today)} 현재 타율",
            "title": f"{leader.get('name')} 타율 {leader.get('value')}",
            "subtitle": f"{self._TEAM_LABELS.get(team_id, team_id)} · 시즌 타율 1위",
            "route": route,
            "gameId": None,
            "teamIds": [team_id] if team_id else [],
            "imageUrl": self._record_leader_image_url(leader, season),
            "fallbackLabel": leader.get("name"),
        }

    def _kbo_brief_item(
        self,
        *,
        item_type: str,
        eyebrow: str,
        title: str,
        subtitle: str,
        route: str,
        game: Dict[str, Any],
    ) -> Dict[str, Any]:
        return {
            "type": item_type,
            "eyebrow": eyebrow,
            "title": title,
            "subtitle": subtitle,
            "route": route,
            "gameId": game.get("gameId"),
            "teamIds": self._team_ids_for_games([game]),
        }

    def _prioritize_kbo_brief_items(
        self,
        items: List[Dict[str, Any]],
        my_team: Optional[str],
    ) -> List[Dict[str, Any]]:
        if not my_team:
            return items
        league_items = [item for item in items if my_team not in (item.get("teamIds") or [])]
        my_team_items = [item for item in items if my_team in (item.get("teamIds") or [])]
        return [*league_items, *my_team_items]

    @staticmethod
    def _kbo_brief_title(
        *,
        today: str,
        has_games: bool,
        has_live: bool,
        has_final: bool,
    ) -> str:
        if not has_games:
            return "이번 주 KBO 포인트"
        if has_live:
            return "지금 KBO"
        if has_final:
            return "어제의 KBO 브리프" if HomeService._is_yesterday(today) else "오늘의 KBO 요약"
        return "KBO 소식"

    @staticmethod
    def _kbo_brief_subtitle(
        *,
        total_games: int,
        live_games: int,
        final_games: int,
        scheduled_games: int,
    ) -> str:
        if total_games == 0:
            return "경기가 없는 날도 리그 흐름은 이어집니다."
        if live_games > 0:
            return f"{live_games}경기 진행 중 · 강한 흐름부터 정리"
        if final_games > 0:
            return f"{final_games}경기 종료 · 기록과 흐름을 빠르게 확인"
        return f"{scheduled_games}경기 예정 · 오늘 일정"

    @staticmethod
    def _is_yesterday(value: str) -> bool:
        try:
            target = date_type.fromisoformat(value)
        except ValueError:
            return False
        return target == current_kbo_date() - timedelta(days=1)

    @staticmethod
    def _team_ids_for_games(games: List[Dict[str, Any]]) -> List[str]:
        team_ids: List[str] = []
        for game in games:
            for side in ("away", "home"):
                team_id = (game.get(side) or {}).get("teamId")
                if isinstance(team_id, str) and team_id and team_id not in team_ids:
                    team_ids.append(team_id)
        return team_ids

    @staticmethod
    def _score_line(game: Dict[str, Any]) -> str:
        return (
            f"{HomeService._team_short_name(game, 'away')} "
            f"{HomeService._team_score(game, 'away')} : "
            f"{HomeService._team_score(game, 'home')} "
            f"{HomeService._team_short_name(game, 'home')}"
        )

    @staticmethod
    def _game_time_label(game: Dict[str, Any]) -> str:
        for key in ("inning", "startTime", "time"):
            value = game.get(key)
            if isinstance(value, str) and value:
                return value
        return "경기 정보"

    @staticmethod
    def _month_day_label(value: str) -> str:
        try:
            target = date_type.fromisoformat(value)
        except ValueError:
            return value
        return f"{target.month}월 {target.day}일"

    @staticmethod
    def _month_label(value: str) -> str:
        try:
            target = date_type.fromisoformat(value)
        except ValueError:
            return "현재"
        return f"{target.month}월"

    @staticmethod
    def _game_total_score(game: Dict[str, Any]) -> int:
        return HomeService._team_score(game, "away") + HomeService._team_score(game, "home")

    @staticmethod
    def _game_total_hits(game: Dict[str, Any]) -> int:
        return HomeService._team_hits(game, "away") + HomeService._team_hits(game, "home")

    @staticmethod
    def _game_total_errors(game: Dict[str, Any]) -> int:
        return HomeService._team_errors(game, "away") + HomeService._team_errors(game, "home")

    @staticmethod
    def _team_score(game: Dict[str, Any], side: str) -> int:
        return HomeService._as_int((game.get(side) or {}).get("score"))

    @staticmethod
    def _team_hits(game: Dict[str, Any], side: str) -> int:
        return HomeService._as_int((game.get(side) or {}).get("hits"))

    @staticmethod
    def _team_errors(game: Dict[str, Any], side: str) -> int:
        return HomeService._as_int((game.get(side) or {}).get("errors"))

    @staticmethod
    def _team_short_name(game: Dict[str, Any], side: str) -> str:
        team = game.get(side) or {}
        team_id = str(team.get("teamId") or game.get(f"{side}Id") or "").strip()
        if team_id in HomeService._TEAM_SHORT_LABELS:
            return HomeService._TEAM_SHORT_LABELS[team_id]

        short_name = str(team.get("shortName") or "").strip()
        if short_name in HomeService._TEAM_SHORT_LABELS:
            return HomeService._TEAM_SHORT_LABELS[short_name]

        team_name = str(team.get("teamName") or game.get(f"{side}Name") or "").strip()
        for known_team_id, known_team_name in HomeService._TEAM_LABELS.items():
            normalized_name = team_name.replace(" ", "")
            normalized_known_name = known_team_name.replace(" ", "")
            if team_name == known_team_name or normalized_name == normalized_known_name:
                return HomeService._TEAM_SHORT_LABELS[known_team_id]

        return short_name or team_name or team_id or "-"

    @staticmethod
    def _as_int(value: Any, fallback: int = 0) -> int:
        if isinstance(value, int):
            return value
        if value in (None, "", "-"):
            return fallback
        try:
            return int(str(value).replace(",", ""))
        except (TypeError, ValueError):
            return fallback

    @staticmethod
    def _as_float(value: Any) -> Optional[float]:
        if value in (None, "", "-"):
            return None
        try:
            return float(str(value).replace(",", ""))
        except (TypeError, ValueError):
            return None

    @staticmethod
    def _section_result(
        future: concurrent.futures.Future,
        fallback: Dict[str, Any],
        *,
        allow_fallback: bool,
    ) -> Dict[str, Any]:
        if not allow_fallback:
            return future.result()
        try:
            return future.result()
        except Exception:
            return fallback

    @staticmethod
    def _is_historical_date(value: str) -> bool:
        try:
            target = date_type.fromisoformat(value)
        except ValueError:
            return False
        return target < current_kbo_date()

    @staticmethod
    def _previous_year_month(value: str) -> Optional[str]:
        try:
            target = date_type.fromisoformat(value)
        except ValueError:
            return None
        previous_month_day = target.replace(day=1) - timedelta(days=1)
        return previous_month_day.strftime("%Y-%m")

    @staticmethod
    def _is_completed_schedule_game(game: Dict[str, Any]) -> bool:
        return str(game.get("status") or "").upper() == "FINAL"

    @staticmethod
    def _record_leader_image_url(leader: Dict[str, Any], season: int) -> Optional[str]:
        image_url = leader.get("imageUrl")
        if isinstance(image_url, str) and image_url:
            return image_url

        player_id = str(leader.get("playerId") or "")
        if not player_id:
            return None
        return kbo_player_image_url(season, player_id)
