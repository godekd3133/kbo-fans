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
from kbo_fans_backend.utils.singleflight import SingleFlight
from kbo_fans_backend.utils.ttl_cache import TtlCache

logger = logging.getLogger(__name__)


class ScoreboardService:
    _SCOREBOARD_CACHE_TTL_SECONDS = 8

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
        self._home_scoreboard_cache: TtlCache[str, dict[str, Any]] = TtlCache(
            self._SCOREBOARD_CACHE_TTL_SECONDS
        )
        self._game_cache: TtlCache[str, dict[str, Any]] = TtlCache(
            self._SCOREBOARD_CACHE_TTL_SECONDS
        )
        self._compact_scoreboard_cache: TtlCache[str, dict[str, Any]] = TtlCache(
            self._SCOREBOARD_CACHE_TTL_SECONDS
        )
        self._singleflight: SingleFlight[str] = SingleFlight()

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

        return self._singleflight.call(
            f"scoreboard:{date}",
            lambda: self._get_scoreboard_uncached(
                date,
                snapshot,
                started_at,
            ),
        )

    def _get_scoreboard_uncached(
        self,
        date: str,
        snapshot: Optional[dict[str, Any]],
        started_at: float,
    ) -> dict[str, Any]:
        cached = self._scoreboard_cache.get(date)
        if cached is not None:
            logger.info("scoreboard cache hit after wait %s", date)
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
            if self._is_historical_date(date) and stale is not None:
                logger.warning("scoreboard stale cache fallback %s", date)
                return stale
            if self._can_use_scoreboard_snapshot_after_failure(date, snapshot):
                logger.warning("scoreboard snapshot fallback %s", date)
                return snapshot
            raise

        try:
            main_started_at = time.perf_counter()
            game_list = {game["G_ID"]: game for game in self.main_crawler.get_kbo_game_list(date)}
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
                    lambda game: self._enrich_game(game, game_list.get(game.get("gameId"), {})),
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
        date = self._normalize_date(date)
        snapshot = self.snapshot_store.load_payload("scoreboard", date)
        if self._is_historical_date(date) and snapshot is not None:
            return {
                "date": snapshot["date"],
                "games": [self._strip_home_payload(game) for game in snapshot["games"]],
            }

        cached = self._home_scoreboard_cache.get(date)
        if cached is not None:
            logger.info("home scoreboard cache hit %s", date)
            return cached

        return self._singleflight.call(
            f"home_scoreboard:{date}",
            lambda: self._get_home_scoreboard_uncached(date, snapshot),
        )

    def _get_home_scoreboard_uncached(
        self,
        date: str,
        snapshot: Optional[dict[str, Any]],
    ) -> dict[str, Any]:
        cached = self._home_scoreboard_cache.get(date)
        if cached is not None:
            logger.info("home scoreboard cache hit after wait %s", date)
            return cached

        try:
            games = self.schedule_crawler.get_games_by_date(date)
        except Exception:
            stale = self._home_scoreboard_cache.get_stale(date)
            if self._is_historical_date(date) and stale is not None:
                logger.warning("home scoreboard stale cache fallback %s", date)
                return stale
            if self._can_use_scoreboard_snapshot_after_failure(date, snapshot):
                return {
                    "date": snapshot["date"],
                    "games": [self._strip_home_payload(game) for game in snapshot["games"]],
                }
            raise

        try:
            game_list = {game["G_ID"]: game for game in self.main_crawler.get_kbo_game_list(date)}
        except Exception:
            game_list = {}
            logger.warning("home scoreboard main list failed %s", date)

        payload = {
            "date": date,
            "games": [
                self._strip_home_payload(
                    self._build_lightweight_game(
                        game,
                        game_list.get(game.get("gameId"), {}),
                    )
                )
                for game in games
            ],
        }
        self._home_scoreboard_cache.set(date, payload)
        return payload

    def get_compact_scoreboard(
        self,
        date: str,
        my_team: Optional[str] = None,
    ) -> dict[str, Any]:
        date = self._normalize_date(date)
        my_team = (my_team or "").strip() or None
        cache_key = f"{date}:{my_team or '-'}"

        cached = self._compact_scoreboard_cache.get(cache_key)
        if cached is not None:
            logger.info("compact scoreboard cache hit %s", cache_key)
            return cached

        return self._singleflight.call(
            f"compact_scoreboard:{cache_key}",
            lambda: self._get_compact_scoreboard_uncached(date, my_team, cache_key),
        )

    def _get_compact_scoreboard_uncached(
        self,
        date: str,
        my_team: Optional[str],
        cache_key: str,
    ) -> dict[str, Any]:
        cached = self._compact_scoreboard_cache.get(cache_key)
        if cached is not None:
            logger.info("compact scoreboard cache hit after wait %s", cache_key)
            return cached

        snapshot = self.snapshot_store.load_payload("scoreboard", date)
        if self._is_historical_date(date) and snapshot is not None:
            payload = self._compact_from_snapshot(date, snapshot, my_team)
            self._compact_scoreboard_cache.set(cache_key, payload)
            return payload

        try:
            games = self.schedule_crawler.get_games_by_date(date)
        except Exception:
            stale = self._compact_scoreboard_cache.get_stale(cache_key)
            if self._is_historical_date(date) and stale is not None:
                logger.warning("compact scoreboard stale fallback %s", cache_key)
                return stale
            if self._can_use_scoreboard_snapshot_after_failure(date, snapshot):
                return self._compact_from_snapshot(date, snapshot, my_team)
            raise

        try:
            game_list = {game["G_ID"]: game for game in self.main_crawler.get_kbo_game_list(date)}
        except Exception:
            game_list = {}
            logger.warning("compact scoreboard main list failed %s", date)

        selected = self._select_compact_game(games, game_list, my_team)
        compact_games = []
        if selected is not None:
            game_id = selected.get("gameId")
            enriched = self._build_lightweight_game(selected, game_list.get(game_id, {}))
            compact_games = [self._strip_home_payload(enriched)]

        payload = {
            "date": date,
            "games": compact_games,
            "source": "compact",
            "scope": "widget",
        }
        self._compact_scoreboard_cache.set(cache_key, payload)
        return payload

    def _compact_from_snapshot(
        self,
        date: str,
        snapshot: dict[str, Any],
        my_team: Optional[str],
    ) -> dict[str, Any]:
        games = snapshot.get("games", [])
        selected = self._select_compact_game(games, {}, my_team)
        return {
            "date": date,
            "games": [] if selected is None else [self._strip_home_payload(selected)],
            "source": "snapshot",
            "scope": "widget",
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
        if snapshot is not None and self._should_use_game_snapshot(game_id):
            return snapshot

        cached = self._game_cache.get(game_id)
        if cached is not None:
            return cached

        return self._singleflight.call(
            f"game:{game_id}",
            lambda: self._get_game_uncached(game_id),
        )

    def _get_game_uncached(self, game_id: str) -> Optional[dict[str, Any]]:
        cached = self._game_cache.get(game_id)
        if cached is not None:
            return cached

        date = f"{game_id[:4]}-{game_id[4:6]}-{game_id[6:8]}"
        try:
            games = self.schedule_crawler.get_games_by_date(date)
        except Exception:
            return None

        schedule_game = next(
            (game for game in games if game.get("gameId") == game_id),
            None,
        )
        if schedule_game is None:
            return None

        try:
            game_list = {game["G_ID"]: game for game in self.main_crawler.get_kbo_game_list(date)}
        except Exception:
            game_list = {}
            logger.warning("game summary main list failed %s %s", date, game_id)

        game = self._enrich_game(schedule_game, game_list.get(game_id, {}))
        self._game_cache.set(game_id, game)
        if self._should_persist_snapshot(date, [game]):
            self.snapshot_store.save("games", game_id, game)
        return game

    def _enrich_game(self, game: dict[str, Any], main_game: dict[str, Any]) -> dict[str, Any]:
        game_id = game.get("gameId")
        resolved_status = str(game.get("status") or "")
        if main_game:
            resolved_status = self._map_status(main_game.get("GAME_STATE_SC"))
        status_label = self._status_label_for_game(resolved_status, game, main_game)

        used_scheduled_fallback = False
        if not game_id or resolved_status == "SCHEDULED":
            detail = self._scheduled_fallback_detail(game)
            used_scheduled_fallback = True
        else:
            try:
                detail = self.scoreboard_crawler.get_game_scoreboard(game_id)
            except Exception:
                detail = self._scheduled_fallback_detail(game)
                used_scheduled_fallback = True
        if resolved_status in {"LIVE", "FINAL"}:
            detail = self._merge_scoreboard_detail_fallback(detail, game_id)
            detail = self._merge_main_game_scores(
                detail,
                main_game,
                prefer_main=used_scheduled_fallback,
            )
        detail = self._backfill_team_identity(game, detail)
        return {
            **game,
            **detail,
            **self._merge_main_game(main_game),
            "status": resolved_status,
            "statusLabel": status_label,
            "ticketInfo": self.ticketing_service.build_ticket_info(
                home_team_id=game.get("homeId"),
                game_id=game_id,
                start_time=main_game.get("G_TM") or game.get("time"),
                status=resolved_status,
            ),
            "highlightInfo": {
                "officialUrl": self._build_official_highlight_url(game_id),
                "youtubeVideos": [],
            },
        }

    def _build_lightweight_game(
        self,
        game: dict[str, Any],
        main_game: dict[str, Any],
    ) -> dict[str, Any]:
        game_id = game.get("gameId")
        resolved_status = str(game.get("status") or "")
        if main_game:
            resolved_status = self._map_status(main_game.get("GAME_STATE_SC"))
        status_label = self._status_label_for_game(resolved_status, game, main_game)

        detail = self._scheduled_fallback_detail(game)
        if resolved_status == "LIVE" and not main_game:
            detail["inning"] = "진행중"
        elif resolved_status == "FINAL" and not main_game:
            detail["inning"] = "경기종료"
        elif resolved_status == "CANCELLED":
            detail["inning"] = status_label or "경기취소"
        elif resolved_status == "SUSPENDED":
            detail["inning"] = "서스펜디드"

        detail = self._merge_main_game_scores(detail, main_game, prefer_main=True)
        detail = self._backfill_team_identity(game, detail)
        return {
            **game,
            **detail,
            **self._merge_main_game(main_game),
            "status": resolved_status,
            "statusLabel": status_label,
            "ticketInfo": self.ticketing_service.build_ticket_info(
                home_team_id=game.get("homeId"),
                game_id=game_id,
                start_time=main_game.get("G_TM") or game.get("time"),
                status=resolved_status,
            ),
            "highlightInfo": {
                "officialUrl": self._build_official_highlight_url(game_id),
                "youtubeVideos": [],
            },
        }

    def _select_compact_game(
        self,
        games: list[dict[str, Any]],
        game_list: dict[str, dict[str, Any]],
        my_team: Optional[str],
    ) -> Optional[dict[str, Any]]:
        if not games:
            return None

        if my_team:
            live_my_team = self._find_compact_game(
                games,
                game_list,
                my_team=my_team,
                only_live=True,
            )
            if live_my_team is not None:
                return live_my_team

            my_team_game = self._find_compact_game(
                games,
                game_list,
                my_team=my_team,
            )
            if my_team_game is not None:
                return my_team_game

        return self._find_compact_game(games, game_list, only_live=True)

    def _find_compact_game(
        self,
        games: list[dict[str, Any]],
        game_list: dict[str, dict[str, Any]],
        my_team: Optional[str] = None,
        only_live: bool = False,
    ) -> Optional[dict[str, Any]]:
        for game in games:
            if my_team and game.get("awayId") != my_team and game.get("homeId") != my_team:
                continue
            game_id = game.get("gameId")
            main_game = game_list.get(game_id, {})
            status = (
                self._map_status(main_game.get("GAME_STATE_SC"))
                if main_game
                else game.get("status")
            )
            if only_live and status != "LIVE":
                continue
            return game
        return None

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

    @staticmethod
    def _backfill_team_identity(
        game: dict[str, Any],
        detail: dict[str, Any],
    ) -> dict[str, Any]:
        away = dict(detail.get("away", {}))
        home = dict(detail.get("home", {}))

        if not away.get("teamId"):
            away["teamId"] = game.get("awayId")
        if not away.get("teamName"):
            away["teamName"] = game.get("awayName")
        if not away.get("shortName"):
            away["shortName"] = game.get("awayName")

        if not home.get("teamId"):
            home["teamId"] = game.get("homeId")
        if not home.get("teamName"):
            home["teamName"] = game.get("homeName")
        if not home.get("shortName"):
            home["shortName"] = game.get("homeName")

        return {
            **detail,
            "away": away,
            "home": home,
        }

    def _merge_scoreboard_detail_fallback(
        self,
        detail: dict[str, Any],
        game_id: str,
    ) -> dict[str, Any]:
        away = dict(detail.get("away", {}))
        home = dict(detail.get("home", {}))
        needs_view1 = any(
            team.get("score") is None
            or self._scores_are_empty(team.get("scores"))
            or team.get("hits") is None
            or team.get("errors") is None
            or team.get("balls") is None
            for team in (away, home)
        )
        if not needs_view1:
            return detail

        try:
            view1 = self.scoreboard_crawler.get_view1_scoreboard_detail(game_id)
        except Exception:
            view1 = None

        if view1 is None:
            return detail

        away_scores = view1.get("awayScores")
        home_scores = view1.get("homeScores")
        away_totals = view1.get("awayTotals", {})
        home_totals = view1.get("homeTotals", {})

        away["scores"] = away_scores or away.get("scores")
        home["scores"] = home_scores or home.get("scores")
        away["score"] = self._score_from_innings(away.get("score"), away["scores"])
        home["score"] = self._score_from_innings(home.get("score"), home["scores"])
        away["hits"] = away_totals.get("hits", away.get("hits"))
        away["errors"] = away_totals.get("errors", away.get("errors"))
        away["balls"] = away_totals.get("balls", away.get("balls"))
        home["hits"] = home_totals.get("hits", home.get("hits"))
        home["errors"] = home_totals.get("errors", home.get("errors"))
        home["balls"] = home_totals.get("balls", home.get("balls"))

        return {
            **detail,
            "away": away,
            "home": home,
        }

    @staticmethod
    def _scores_are_empty(scores: Any) -> bool:
        if not isinstance(scores, list):
            return True
        return not any(score is not None for score in scores)

    @staticmethod
    def _score_from_innings(current_score: Any, scores: Any) -> Any:
        if current_score is not None:
            return current_score
        if not isinstance(scores, list):
            return current_score
        numeric_scores = [score for score in scores if isinstance(score, int)]
        if not numeric_scores:
            return current_score
        return sum(numeric_scores)

    def _merge_main_game_scores(
        self,
        detail: dict[str, Any],
        main_game: dict[str, Any],
        *,
        prefer_main: bool = False,
    ) -> dict[str, Any]:
        if not main_game:
            return detail

        away = dict(detail.get("away", {}))
        home = dict(detail.get("home", {}))
        away["score"] = self._score_from_main_or_existing(
            main_game.get("T_SCORE_CN"), away.get("score"), prefer_main=prefer_main
        )
        home["score"] = self._score_from_main_or_existing(
            main_game.get("B_SCORE_CN"), home.get("score"), prefer_main=prefer_main
        )
        return {
            **detail,
            "away": away,
            "home": home,
        }

    @staticmethod
    def _score_from_main_or_existing(
        value: Any,
        existing: Any,
        *,
        prefer_main: bool = False,
    ) -> Any:
        if value in (None, "", "-"):
            return existing
        try:
            parsed = int(str(value).replace(",", ""))
        except (TypeError, ValueError):
            return existing
        if prefer_main or existing is None:
            return parsed
        return existing

    def _merge_main_game(self, main_game: dict[str, Any]) -> dict[str, Any]:
        if not main_game:
            return {}
        status = self._map_status(main_game.get("GAME_STATE_SC"))
        inning = self._format_inning(main_game)
        return {
            "status": status,
            "statusLabel": self._status_label_for_main_game(status, main_game),
            "inning": inning,
            "startTime": main_game.get("G_TM"),
            "current": self._current_player_payload_for_main_game(main_game),
        }

    @staticmethod
    def _current_player_payload_for_main_game(main_game: dict[str, Any]) -> dict[str, Any]:
        half = str(main_game.get("GAME_TB_SC_NM") or "").strip()
        if half == "초":
            batter_name = main_game.get("T_P_NM")
            pitcher_name = main_game.get("B_P_NM")
            batter_id = main_game.get("T_P_ID")
            pitcher_id = main_game.get("B_P_ID")
        else:
            batter_name = main_game.get("B_P_NM")
            pitcher_name = main_game.get("T_P_NM")
            batter_id = main_game.get("B_P_ID")
            pitcher_id = main_game.get("T_P_ID")

        payload = {
            "balls": main_game.get("BALL_CN"),
            "strikes": main_game.get("STRIKE_CN"),
            "outs": main_game.get("OUT_CN"),
            "batterName": batter_name,
            "pitcherName": pitcher_name,
        }
        if batter_id not in (None, ""):
            payload["batterId"] = str(batter_id)
        if pitcher_id not in (None, ""):
            payload["pitcherId"] = str(pitcher_id)
        return payload

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
        if status == "CANCELLED":
            return self._status_label_for_main_game(status, main_game) or "경기취소"
        if status == "SUSPENDED":
            return "서스펜디드"
        inning_no = main_game.get("GAME_INN_NO")
        half = main_game.get("GAME_TB_SC_NM")
        if inning_no and half:
            return f"{inning_no}회{half}"
        return status

    @classmethod
    def _status_label_for_game(
        cls,
        status: str,
        game: dict[str, Any],
        main_game: dict[str, Any],
    ) -> Optional[str]:
        main_label = cls._status_label_for_main_game(status, main_game)
        if main_label is not None:
            return main_label
        if status == game.get("status"):
            label = str(game.get("statusLabel") or "").strip()
            return label or None
        return None

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

    def _should_use_game_snapshot(self, game_id: str) -> bool:
        if len(game_id) < 8:
            return False
        date = f"{game_id[:4]}-{game_id[4:6]}-{game_id[6:8]}"
        return self._is_historical_date(date)

    def _should_persist_snapshot(self, date: str, games: list[dict[str, Any]]) -> bool:
        if self._is_historical_date(date):
            return True

        terminal_statuses = {"FINAL", "CANCELLED", "SUSPENDED"}
        return bool(games) and all(game.get("status") in terminal_statuses for game in games)

    def _can_use_scoreboard_snapshot_after_failure(
        self,
        date: str,
        snapshot: Optional[dict[str, Any]],
    ) -> bool:
        if snapshot is None:
            return False
        if self._is_historical_date(date):
            return True
        return False

    @staticmethod
    def _strip_home_payload(game: dict[str, Any]) -> dict[str, Any]:
        return {
            "gameId": game.get("gameId"),
            "status": game.get("status"),
            "statusLabel": game.get("statusLabel"),
            "inning": game.get("inning"),
            "stadium": game.get("stadium"),
            "startTime": game.get("startTime"),
            "current": game.get("current"),
            "crowd": game.get("crowd"),
            "ticketInfo": game.get("ticketInfo"),
            "away": game.get("away"),
            "home": game.get("home"),
        }
