from __future__ import annotations

import concurrent.futures
import logging
import threading
from contextlib import contextmanager
from copy import deepcopy
from datetime import date as date_type
from typing import Any, Iterator, Optional

from kbo_fans_backend.core.config import get_settings
from kbo_fans_backend.crawlers.boxscore import BoxscoreCrawler
from kbo_fans_backend.schemas.boxscore import (
    BoxscoreAvailability,
    official_unavailable_boxscore,
)
from kbo_fans_backend.services.player_stats import PlayerStatsService
from kbo_fans_backend.services.schedule import ScheduleService
from kbo_fans_backend.storage import JsonSnapshotStore
from kbo_fans_backend.utils.kbo_time import current_kbo_date
from kbo_fans_backend.utils.resilience import UpstreamBusyError
from kbo_fans_backend.utils.singleflight import SingleFlight
from kbo_fans_backend.utils.source_cache import KboSourceCache
from kbo_fans_backend.utils.ttl_cache import TtlCache

logger = logging.getLogger(__name__)


@contextmanager
def _boxscore_executor(
    max_workers: int,
) -> Iterator[concurrent.futures.ThreadPoolExecutor]:
    executor = concurrent.futures.ThreadPoolExecutor(max_workers=max_workers)
    try:
        yield executor
    except BaseException:
        # Current status and official boxscore are independent. If either
        # fails, do not wait for a sibling request that is still in flight.
        executor.shutdown(wait=False, cancel_futures=True)
        raise
    else:
        executor.shutdown(wait=True)


class BoxscoreService:
    _UNAVAILABLE_STATUSES = {"SCHEDULED", "CANCELLED", "SUSPENDED"}
    _OPTIONAL_ENRICHMENT_INLINE_BUDGET_SECONDS = 0.75
    _BOXSCORE_CACHE_TTL_SECONDS = 15
    _UNAVAILABLE_CACHE_TTL_SECONDS = 8
    _RUNTIME_CACHE_NAMESPACE = "runtime_boxscore"
    _STALE_RUNTIME_MAX_AGE_SECONDS = 600.0

    def __init__(
        self,
        crawler: Optional[BoxscoreCrawler] = None,
        schedule_service: Optional[ScheduleService] = None,
        player_stats_service: Optional[PlayerStatsService] = None,
        snapshot_store: Optional[JsonSnapshotStore] = None,
        runtime_cache_max_age_seconds: Optional[float] = None,
        main_source: Optional[KboSourceCache[str, list[dict[str, Any]]]] = None,
    ) -> None:
        self.crawler = crawler or BoxscoreCrawler(main_source=main_source)
        if main_source is not None and isinstance(self.crawler, BoxscoreCrawler):
            self.crawler.main_source = main_source
        self.schedule_service = schedule_service or ScheduleService()
        self.player_stats_service = player_stats_service or PlayerStatsService()
        self.snapshot_store = snapshot_store or JsonSnapshotStore()
        configured_runtime_cache_age = (
            runtime_cache_max_age_seconds
            if runtime_cache_max_age_seconds is not None
            else get_settings().live_game_data_cache_max_age_seconds
        )
        self._runtime_cache_max_age_seconds = max(0.0, float(configured_runtime_cache_age))
        self._boxscore_cache: TtlCache[str, dict[str, Any]] = TtlCache(
            self._BOXSCORE_CACHE_TTL_SECONDS
        )
        self._singleflight: SingleFlight[str] = SingleFlight()
        self._enrichment_lock = threading.Lock()
        self._enrichment_in_flight: set[str] = set()
        # Same-day games already proven FINAL by a verified crawl. Marked games
        # may reuse their immutable snapshot without paying another upstream
        # crawl; live games are never marked, so the current-game snapshot
        # boundary is preserved.
        self._same_day_final_game_ids: set[str] = set()
        self._stale_refresh_in_flight: set[str] = set()
        self._stale_refresh_lock = threading.Lock()

    def _refresh_runtime_async(self, game_id: str) -> None:
        """Refresh a stale runtime snapshot through the shared singleflight.

        Coalesces with any in-flight boxscore refresh for the game; failures
        are logged and never affect the stale-served response.
        """
        with self._stale_refresh_lock:
            if game_id in self._stale_refresh_in_flight:
                return
            self._stale_refresh_in_flight.add(game_id)

        def run() -> None:
            try:
                self._singleflight.call(
                    f"boxscore:{game_id}:cached",
                    lambda: self._get_boxscore_uncached(game_id),
                )
            except Exception as error:
                logger.info(
                    "boxscore stale runtime refresh failed %s (%s)",
                    game_id,
                    type(error).__name__,
                )
            finally:
                with self._stale_refresh_lock:
                    self._stale_refresh_in_flight.discard(game_id)

        threading.Thread(
            target=run,
            name=f"stale-boxscore-refresh-{game_id}",
            daemon=True,
        ).start()

    def _busy_fallback_boxscore(self, game_id: str) -> Optional[dict[str, Any]]:
        """Best available boxscore when the upstream path is busy.

        Serving last-known official/live-context data beats a 503 during a
        slow refresh; the caller still 503s when nothing usable exists.
        """
        cached = self._boxscore_cache.get(game_id)
        if self._is_cacheable_payload(
            cached, game_id
        ) or self._is_reusable_unavailable_payload(cached, game_id):
            return cached
        snapshot = self.snapshot_store.load_recent_payload(
            self._RUNTIME_CACHE_NAMESPACE,
            game_id,
            self._STALE_RUNTIME_MAX_AGE_SECONDS,
        )
        if self._is_cacheable_payload(snapshot, game_id):
            return snapshot
        return None

    def get_boxscore(
        self,
        game_id: str,
        force_refresh: bool = False,
    ) -> dict[str, Any]:
        if not force_refresh:
            cached = self._boxscore_cache.get(game_id)
            if self._is_cacheable_payload(cached, game_id):
                logger.info("boxscore cache hit %s", game_id)
                return cached
            if self._is_reusable_unavailable_payload(cached, game_id):
                logger.info("boxscore unavailable cache hit %s", game_id)
                return cached

            runtime_snapshot = self.snapshot_store.load_recent_payload(
                self._RUNTIME_CACHE_NAMESPACE,
                game_id,
                self._runtime_cache_max_age_seconds,
            )
            if self._is_cacheable_payload(runtime_snapshot, game_id):
                self._boxscore_cache.set(game_id, runtime_snapshot)
                logger.info("boxscore runtime snapshot hit %s", game_id)
                return runtime_snapshot
            stale_snapshot = self.snapshot_store.load_recent_payload(
                self._RUNTIME_CACHE_NAMESPACE,
                game_id,
                self._STALE_RUNTIME_MAX_AGE_SECONDS,
            )
            if self._is_cacheable_payload(stale_snapshot, game_id):
                logger.info("boxscore stale runtime snapshot hit %s", game_id)
                self._refresh_runtime_async(game_id)
                return stale_snapshot

        try:
            payload = self._singleflight.call(
                f"boxscore:{game_id}:{'force' if force_refresh else 'cached'}",
                lambda: self._get_boxscore_uncached(game_id),
            )
        except UpstreamBusyError:
            fallback = self._busy_fallback_boxscore(game_id)
            if fallback is not None:
                logger.info("boxscore busy fallback %s", game_id)
                return fallback
            raise
        if self._is_cacheable_payload(payload, game_id):
            self._boxscore_cache.set(game_id, payload)
        elif self._is_reusable_unavailable_payload(payload, game_id):
            # A live/scheduled game whose official records are not yet
            # published resolves to the same unavailable answer on every
            # call. Coalescing it for a few seconds keeps rapid tab switches
            # from re-crawling upstream while recovery stays prompt.
            self._boxscore_cache.set(
                game_id,
                payload,
                ttl_seconds=self._UNAVAILABLE_CACHE_TTL_SECONDS,
            )
        return payload

    def _get_boxscore_uncached(self, game_id: str) -> dict[str, Any]:
        is_past_game = self._is_past_game_id(game_id)
        game_status = self._game_status(game_id) if is_past_game else None
        is_historical_final = self._is_historical_final(game_id, game_status)
        can_use_historical_snapshot = is_past_game and (
            is_historical_final or game_status in {None, "UNKNOWN"}
        )
        snapshot = (
            self.snapshot_store.load_payload("boxscore", game_id)
            if is_past_game
            else None
        )
        if can_use_historical_snapshot and self._is_valid_historical_snapshot(
            snapshot,
            game_id,
        ):
            if self._has_player_metadata(snapshot):
                return snapshot
            return self._enrich_with_budget(snapshot, game_id)

        if is_past_game:
            payload = self.crawler.get_boxscore(game_id)
        elif game_id in self._same_day_final_game_ids:
            # The marker is only set after a verified FINAL crawl, so the game
            # is already over; reuse the immutable snapshot instead of
            # re-crawling an unchanged boxscore on every cache expiry.
            game_status = "FINAL"
            snapshot = self.snapshot_store.load_payload("boxscore", game_id)
            if self._is_valid_historical_snapshot(snapshot, game_id):
                if self._has_player_metadata(snapshot):
                    return snapshot
                return self._enrich_with_budget(snapshot, game_id)
            self._same_day_final_game_ids.discard(game_id)
            payload = self.crawler.get_boxscore(game_id)
        else:
            game_status, payload, crawl_error = (
                self._fetch_current_status_and_boxscore(game_id)
            )
            if payload is None:
                if crawl_error is not None:
                    logger.warning(
                        "official boxscore fetch failed for %s: %s",
                        game_id,
                        crawl_error,
                    )
                payload = self._degraded_current_boxscore(game_id)

        payload = self._normalize_crawler_payload(payload, game_id)
        if self._is_verified_official_payload(payload, game_id):
            if game_status in self._UNAVAILABLE_STATUSES:
                return self._official_unavailable_payload(
                    game_id,
                    reason=f"game_status_{game_status.lower()}",
                )
            # Player IDs/images are optional presentation metadata. Save the
            # official rows before attempting any historical enrichment so a
            # slow player crawl cannot block the data response.
            if game_status == "FINAL":
                self._same_day_final_game_ids.add(game_id)
                self.snapshot_store.save("boxscore", game_id, payload)
            if not is_past_game:
                self.snapshot_store.save(self._RUNTIME_CACHE_NAMESPACE, game_id, payload)
            if is_past_game:
                enriched_payload = self._enrich_with_budget(payload, game_id)
                if enriched_payload != payload:
                    self.snapshot_store.save("boxscore", game_id, enriched_payload)
                payload = enriched_payload
            return payload

        if self._is_live_context_payload(payload, game_id):
            if game_status == "LIVE" or (
                game_status in {None, "UNKNOWN"} and not is_past_game
            ):
                # Live context rows are also useful before the official
                # boxscore is published. Keep their first response bounded by
                # the main/relay context crawl; player metadata is optional.
                if is_past_game:
                    return self._enrich_with_budget(payload, game_id)
                self.snapshot_store.save(self._RUNTIME_CACHE_NAMESPACE, game_id, payload)
                return payload
            payload = self._official_unavailable_payload(
                game_id,
                reason="live_context_not_current",
            )

        if is_historical_final:
            alternate_game_id = self._resolve_alternate_game_id(game_id)
            if alternate_game_id is not None:
                try:
                    alternate_payload = self.crawler.get_boxscore(alternate_game_id)
                    alternate_payload = self._normalize_crawler_payload(
                        alternate_payload,
                        alternate_game_id,
                    )
                    if self._is_verified_official_payload(
                        alternate_payload,
                        alternate_game_id,
                    ):
                        alternate_payload = {
                            **alternate_payload,
                            "gameId": game_id,
                            "sourceGameId": alternate_game_id,
                            "source": "adjacent_official",
                        }
                        self.snapshot_store.save("boxscore", game_id, alternate_payload)
                        enriched_payload = self._enrich_with_budget(alternate_payload, game_id)
                        if enriched_payload != alternate_payload:
                            self.snapshot_store.save("boxscore", game_id, enriched_payload)
                        alternate_payload = enriched_payload
                        return alternate_payload
                except Exception:
                    pass

        return payload

    def _degraded_current_boxscore(self, game_id: str) -> dict[str, Any]:
        """Degraded boxscore for a current game whose official fetch failed.

        Prefer the shared live context (cached main list + cached relay); fall
        back to an explicit unavailable payload so the app renders the neutral
        "not yet published" card instead of an HTTP 500 for a transient
        upstream failure. Historical games keep failing loudly in the caller.
        """
        get_live_context = getattr(self.crawler, "get_live_context_boxscore", None)
        if callable(get_live_context):
            try:
                live_context = get_live_context(game_id)
            except Exception:
                live_context = None
            if isinstance(live_context, dict):
                return live_context
        return self._official_unavailable_payload(
            game_id,
            reason="official_fetch_failed",
        )

    def _fetch_current_status_and_boxscore(
        self,
        game_id: str,
    ) -> tuple[Optional[str], Optional[dict[str, Any]], Optional[BaseException]]:
        # Both the status lookup and the official crawl start in parallel: a
        # live game must not serialize a slow status fetch before crawling.
        # Once the status resolves to a value where no official boxscore can
        # exist, the in-flight crawl cannot change the answer — return
        # immediately and let it finish detached instead of stalling the
        # response behind a pointless upstream POST.
        executor = concurrent.futures.ThreadPoolExecutor(max_workers=2)
        executor_closed = False
        try:
            status_future = executor.submit(self._game_status, game_id)
            payload_future = executor.submit(self.crawler.get_boxscore, game_id)
            status_error: Optional[BaseException] = None
            try:
                game_status = status_future.result()
            except BaseException as error:
                # A failed status lookup must not kill a request whose crawl
                # may still succeed; treat the status as unknown.
                game_status = None
                status_error = error
            if game_status in self._UNAVAILABLE_STATUSES:
                executor.shutdown(wait=False)
                executor_closed = True
                return (
                    game_status,
                    self._official_unavailable_payload(
                        game_id,
                        reason=f"game_status_{game_status.lower()}",
                    ),
                    None,
                )
            crawl_error: Optional[BaseException] = None
            try:
                payload = payload_future.result()
            except BaseException as error:
                payload = None
                crawl_error = error
            if payload is None and status_error is not None:
                # Both lookups failed — surface the error instead of
                # degrading on zero information.
                raise status_error
            return game_status, payload, crawl_error
        except BaseException:
            if not executor_closed:
                # Mirror _boxscore_executor: on failure, do not wait for a
                # sibling request that is still in flight.
                executor.shutdown(wait=False, cancel_futures=True)
                executor_closed = True
            raise
        finally:
            if not executor_closed:
                executor.shutdown(wait=True)

    @classmethod
    def _is_cacheable_payload(cls, payload: Any, game_id: str) -> bool:
        if not isinstance(payload, dict):
            return False
        return cls._is_verified_official_payload(payload, game_id) or cls._is_live_context_payload(
            payload,
            game_id,
        )

    def _is_reusable_unavailable_payload(
        self,
        payload: Any,
        game_id: str,
    ) -> bool:
        """Explicit unavailable answers may be reused briefly for live games.

        Past and already-finalized games must keep re-crawling (or failing)
        instead of serving a transient unavailable response repeatedly.
        """
        if not isinstance(payload, dict) or payload.get("gameId") != game_id:
            return False
        if self._is_past_game_id(game_id) or game_id in self._same_day_final_game_ids:
            return False
        return (
            payload.get("officialAvailable") is False
            and payload.get("liveContextAvailable") is not True
        )

    @classmethod
    def is_complete_payload(cls, game_id: str, payload: Any) -> bool:
        return isinstance(payload, dict) and cls._is_verified_official_payload(payload, game_id)

    def _enrich_with_budget(
        self,
        payload: dict[str, Any],
        game_id: str,
    ) -> dict[str, Any]:
        if self._has_player_metadata(payload):
            return payload

        with self._enrichment_lock:
            if game_id in self._enrichment_in_flight:
                return payload
            self._enrichment_in_flight.add(game_id)

        result: dict[str, Any] = {}
        completed = threading.Event()

        def enrich_and_persist() -> None:
            try:
                enriched = deepcopy(payload)
                enriched = self._enrich_player_ids_and_images(enriched, game_id)
                result["payload"] = enriched
                if enriched != payload:
                    self.snapshot_store.save("boxscore", game_id, enriched)
            except Exception as error:
                logger.info("Boxscore metadata enrichment skipped for %s: %s", game_id, error)
            finally:
                with self._enrichment_lock:
                    self._enrichment_in_flight.discard(game_id)
                completed.set()

        thread = threading.Thread(
            target=enrich_and_persist,
            name=f"boxscore-metadata-{game_id}",
            daemon=True,
        )
        thread.start()
        if completed.wait(timeout=self._OPTIONAL_ENRICHMENT_INLINE_BUDGET_SECONDS):
            return result.get("payload", payload)
        return payload

    @staticmethod
    def _has_player_metadata(payload: dict[str, Any]) -> bool:
        for side in ("away", "home"):
            team_payload = payload.get(side)
            if not isinstance(team_payload, dict):
                continue
            for key in ("batters", "pitchers"):
                rows = team_payload.get(key)
                if not isinstance(rows, list):
                    continue
                for row in rows:
                    if not isinstance(row, dict) or not str(row.get("name") or "").strip():
                        continue
                    has_player_id = bool(
                        str(row.get("playerId") or row.get("id") or "").strip()
                    )
                    has_image_url = bool(str(row.get("imageUrl") or "").strip())
                    if not has_player_id and not has_image_url:
                        return False
        return True

    def _enrich_player_ids_and_images(
        self, payload: dict[str, Any], game_id: str
    ) -> dict[str, Any]:
        season = self._season_from_game_id(game_id)
        if season is None:
            return payload

        for side, fallback_team_id in (
            ("away", game_id[8:10] if len(game_id) >= 10 else ""),
            ("home", game_id[10:12] if len(game_id) >= 12 else ""),
        ):
            team_payload = payload.get(side)
            if not isinstance(team_payload, dict):
                continue
            team_id = str(team_payload.get("teamId") or fallback_team_id).strip()
            players_by_name = self._team_players_by_name(team_id, season)
            if not players_by_name:
                continue
            for key in ("batters", "pitchers"):
                rows = team_payload.get(key)
                if not isinstance(rows, list):
                    continue
                for row in rows:
                    if not isinstance(row, dict):
                        continue
                    player = players_by_name.get(self._normalize_player_name(row.get("name")))
                    if player is None:
                        continue
                    player_id = str(player.get("id") or player.get("playerId") or "").strip()
                    image_url = str(player.get("imageUrl") or "").strip()
                    if player_id and not str(row.get("playerId") or row.get("id") or "").strip():
                        row["playerId"] = player_id
                    if image_url and not str(row.get("imageUrl") or "").strip():
                        row["imageUrl"] = image_url

        return payload

    def _team_players_by_name(self, team_id: str, season: int) -> dict[str, dict[str, Any]]:
        if not team_id:
            return {}
        try:
            payload = self.player_stats_service.get_team_players(team_id, season)
        except Exception:
            return {}
        players = payload.get("players") if isinstance(payload, dict) else None
        if not isinstance(players, list):
            return {}
        result: dict[str, dict[str, Any]] = {}
        for player in players:
            if not isinstance(player, dict):
                continue
            name = self._normalize_player_name(player.get("name"))
            if name:
                result[name] = player
        return result

    @staticmethod
    def _season_from_game_id(game_id: str) -> Optional[int]:
        if len(game_id) < 4:
            return None
        try:
            return int(game_id[:4])
        except ValueError:
            return None

    @staticmethod
    def _normalize_player_name(value: Any) -> str:
        return "".join(str(value or "").split()).replace("·", "").replace("ㆍ", "")

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
                if str(game.get("status") or "").upper() != "FINAL":
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

    def _normalize_crawler_payload(
        self,
        payload: Any,
        game_id: str,
    ) -> dict[str, Any]:
        if isinstance(payload, dict) and self._is_verified_official_payload(
            payload,
            game_id,
        ):
            normalized = {key: value for key, value in payload.items() if key != "sourceGameId"}
            return {
                **normalized,
                "availability": BoxscoreAvailability.OFFICIAL.value,
                "officialAvailable": True,
                "liveContextAvailable": False,
                "source": "official_endpoint",
            }

        if isinstance(payload, dict) and self._is_live_context_payload(
            payload,
            game_id,
        ):
            return {
                **payload,
                "availability": BoxscoreAvailability.LIVE_CONTEXT.value,
                "officialAvailable": False,
                "liveContextAvailable": True,
                "source": "live_context",
                "unavailableReason": str(
                    payload.get("unavailableReason") or "official_not_available"
                ),
            }

        reason = "official_not_available"
        if isinstance(payload, dict):
            reason = str(
                payload.get("unavailableReason")
                or (
                    "official_partial"
                    if payload.get("officialAvailable") is True
                    else "official_not_available"
                )
            )
        return self._official_unavailable_payload(game_id, reason=reason)

    def _is_valid_historical_snapshot(
        self,
        payload: Any,
        game_id: str,
    ) -> bool:
        if not isinstance(payload, dict) or not self._is_verified_official_payload(
            payload,
            game_id,
        ):
            return False

        source = str(payload.get("source") or "").strip()
        source_game_id = payload.get("sourceGameId")
        if source_game_id is None:
            return source == "official_endpoint"
        if source != "adjacent_official":
            return False
        if not isinstance(source_game_id, str) or source_game_id == game_id:
            return False
        return self._resolve_alternate_game_id(game_id) == source_game_id

    @classmethod
    def _is_verified_official_payload(
        cls,
        payload: dict[str, Any],
        game_id: str,
    ) -> bool:
        if payload.get("gameId") != game_id:
            return False
        if payload.get("availability") != BoxscoreAvailability.OFFICIAL.value:
            return False
        if payload.get("officialAvailable") is not True:
            return False
        if payload.get("liveContextAvailable") is not False:
            return False
        if len(game_id) < 12:
            return False

        for side, expected_team_id in (
            ("away", game_id[8:10]),
            ("home", game_id[10:12]),
        ):
            team = payload.get(side)
            if not isinstance(team, dict) or team.get("teamId") != expected_team_id:
                return False
            if not cls._has_official_batting_line(team.get("batters")):
                return False
            if not cls._has_official_pitching_line(team.get("pitchers")):
                return False
        return True

    @classmethod
    def _is_live_context_payload(
        cls,
        payload: dict[str, Any],
        game_id: str,
    ) -> bool:
        if payload.get("gameId") != game_id:
            return False
        if payload.get("officialAvailable") is not False:
            return False
        if payload.get("liveContextAvailable") is not True:
            return False
        if len(game_id) < 12:
            return False

        has_context_row = False
        for side, expected_team_id in (
            ("away", game_id[8:10]),
            ("home", game_id[10:12]),
        ):
            team = payload.get(side)
            if not isinstance(team, dict) or team.get("teamId") != expected_team_id:
                return False
            for key in ("batters", "pitchers"):
                rows = team.get(key)
                if not isinstance(rows, list):
                    continue
                has_context_row = has_context_row or any(
                    isinstance(row, dict)
                    and row.get("liveContext") is True
                    and bool(str(row.get("name") or "").strip())
                    for row in rows
                )
        return has_context_row

    @staticmethod
    def _has_official_batting_line(rows: Any) -> bool:
        if not isinstance(rows, list):
            return False
        for row in rows:
            if not isinstance(row, dict) or not str(row.get("name") or "").strip():
                continue
            for key in ("plateAppearances", "atBats", "runs", "hits", "rbi"):
                try:
                    if int(row.get(key) or 0) > 0:
                        return True
                except (TypeError, ValueError):
                    continue
        return False

    @staticmethod
    def _has_official_pitching_line(rows: Any) -> bool:
        if not isinstance(rows, list):
            return False
        for row in rows:
            if not isinstance(row, dict) or not str(row.get("name") or "").strip():
                continue
            innings = str(row.get("innings") or "").strip()
            decision = str(row.get("decision") or "").strip().upper()
            if innings not in {"", "0", "0.0"}:
                return True
            if decision not in {"", "-", "LIVE", "NONE"}:
                return True
            for key in ("hits", "strikeouts", "walks", "earnedRuns"):
                try:
                    if int(row.get(key) or 0) > 0:
                        return True
                except (TypeError, ValueError):
                    continue
        return False

    def _game_status(self, game_id: str) -> Optional[str]:
        try:
            game = self.schedule_service.get_schedule_game(game_id)
        except Exception:
            return None
        if not isinstance(game, dict):
            return None
        status = str(game.get("status") or "").strip().upper()
        return status or None

    @classmethod
    def _is_historical_final(
        cls,
        game_id: str,
        game_status: Optional[str],
    ) -> bool:
        return game_status == "FINAL" and cls._is_past_game_id(game_id)

    @staticmethod
    def _official_unavailable_payload(
        game_id: str,
        *,
        reason: str,
    ) -> dict[str, Any]:
        away_id = game_id[8:10] if len(game_id) >= 10 else ""
        home_id = game_id[10:12] if len(game_id) >= 12 else ""
        return official_unavailable_boxscore(
            game_id,
            away_id,
            home_id,
            reason=reason,
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
        return game_date < current_kbo_date()
