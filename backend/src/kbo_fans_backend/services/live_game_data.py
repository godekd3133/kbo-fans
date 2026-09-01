from __future__ import annotations

import logging
import threading
import time
from typing import Any, Callable, Iterable

from kbo_fans_backend.services.boxscore import BoxscoreService
from kbo_fans_backend.services.lineup import LineupService
from kbo_fans_backend.services.relay import RelayService
from kbo_fans_backend.services.scoreboard import ScoreboardService

logger = logging.getLogger(__name__)


class LiveGameDataWarmService:
    """Fetches live/final game detail once in the background worker.

    The API path remains the fallback on a cache miss. This service only
    primes the same service instances used by the API and relies on their
    process-local L1 cache plus the shared runtime snapshot L2 cache.
    """

    _LIVE_STATUS = "LIVE"
    _FINAL_STATUS = "FINAL"

    def __init__(
        self,
        *,
        scoreboard_service: ScoreboardService,
        relay_service: RelayService,
        boxscore_service: BoxscoreService,
        lineup_service: LineupService,
    ) -> None:
        self.scoreboard_service = scoreboard_service
        self.relay_service = relay_service
        self.boxscore_service = boxscore_service
        self.lineup_service = lineup_service
        self._finalized_game_ids: set[str] = set()
        self._state_lock = threading.Lock()

    def warm_games(self, games: Iterable[dict[str, Any]]) -> dict[str, Any]:
        unique_games: list[dict[str, Any]] = []
        seen: set[str] = set()
        for game in games:
            if not isinstance(game, dict):
                continue
            game_id = str(game.get("gameId") or "").strip()
            if not game_id or game_id in seen:
                continue
            seen.add(game_id)
            unique_games.append(game)

        results: list[dict[str, Any]] = []
        live_count = 0
        final_count = 0
        finalized_count = 0
        for game in unique_games:
            game_id = str(game.get("gameId") or "").strip()
            status = str(game.get("status") or "").strip().upper()
            if status == self._LIVE_STATUS:
                live_count += 1
                results.append(self._warm_one(game_id, status, force_refresh=True))
                continue

            if status != self._FINAL_STATUS:
                continue
            final_count += 1
            with self._state_lock:
                already_finalized = game_id in self._finalized_game_ids
            if already_finalized:
                continue

            result = self._warm_one(game_id, status, force_refresh=True)
            if self._is_complete_finalization(result):
                with self._state_lock:
                    self._finalized_game_ids.add(game_id)
                self._prune_runtime_entries(game_id)
                result["finalized"] = True
                result["runtimeCachePruned"] = True
                finalized_count += 1
            results.append(result)

        return {
            "liveGames": live_count,
            "finalGames": final_count,
            "finalizedGames": finalized_count,
            "results": results,
        }

    def _warm_one(
        self,
        game_id: str,
        expected_status: str,
        *,
        force_refresh: bool,
    ) -> dict[str, Any]:
        started_at = time.perf_counter()
        result: dict[str, Any] = {
            "gameId": game_id,
            "expectedStatus": expected_status,
            "status": expected_status,
            "components": {},
            "errors": [],
        }

        try:
            game = self.scoreboard_service.get_game(
                game_id,
                force_refresh=force_refresh,
            )
        except Exception as error:
            self._record_error(result, "game", error)
            result["durationMs"] = round((time.perf_counter() - started_at) * 1000, 1)
            return result

        resolved_status = str((game or {}).get("status") or expected_status).strip().upper()
        result["status"] = resolved_status
        result["components"]["game"] = "ok" if game is not None else "missing"
        if game is None or resolved_status not in {self._LIVE_STATUS, self._FINAL_STATUS}:
            result["skipped"] = "game_status_not_warmable"
            result["durationMs"] = round((time.perf_counter() - started_at) * 1000, 1)
            return result

        components: list[tuple[str, Callable[[], Any]]] = [
            (
                "relay",
                lambda: self.relay_service.get_relay(
                    game_id,
                    force_refresh=force_refresh,
                ),
            ),
            (
                "boxscore",
                lambda: self.boxscore_service.get_boxscore(
                    game_id,
                    force_refresh=force_refresh,
                ),
            ),
            (
                "lineup",
                lambda: self.lineup_service.get_lineup(
                    game_id,
                    force_refresh=force_refresh,
                ),
            ),
        ]
        payloads: dict[str, Any] = {}
        for name, loader in components:
            try:
                payloads[name] = loader()
                result["components"][name] = "ok"
            except Exception as error:
                self._record_error(result, name, error)

        if resolved_status == self._FINAL_STATUS:
            self._promote_complete_final_payloads(game_id, payloads)
        result["complete"] = self._is_complete_payloads(
            game_id,
            resolved_status,
            payloads,
        )
        result["durationMs"] = round((time.perf_counter() - started_at) * 1000, 1)
        return result

    def _is_complete_finalization(self, result: dict[str, Any]) -> bool:
        return (
            result.get("status") == self._FINAL_STATUS
            and result.get("complete") is True
            and not result.get("errors")
        )

    def _prune_runtime_entries(self, game_id: str) -> None:
        snapshot_store = getattr(self.boxscore_service, "snapshot_store", None)
        delete = getattr(snapshot_store, "delete", None)
        if not callable(delete):
            return
        for namespace in (
            "runtime_games",
            "runtime_relay",
            "runtime_boxscore",
            "runtime_lineup",
        ):
            try:
                delete(namespace, game_id)
            except Exception as error:
                logger.info(
                    "Runtime cache cleanup skipped for %s (%s)",
                    game_id,
                    type(error).__name__,
                )

    def _is_complete_payloads(
        self,
        game_id: str,
        status: str,
        payloads: dict[str, Any],
    ) -> bool:
        if status != self._FINAL_STATUS:
            return False
        return (
            self.relay_service.is_complete_payload(game_id, payloads.get("relay"))
            and self.boxscore_service.is_complete_payload(game_id, payloads.get("boxscore"))
            and self.lineup_service.is_complete_payload(game_id, payloads.get("lineup"))
        )

    def _promote_complete_final_payloads(
        self,
        game_id: str,
        payloads: dict[str, Any],
    ) -> None:
        snapshot_store = getattr(self.boxscore_service, "snapshot_store", None)
        save = getattr(snapshot_store, "save", None)
        if not callable(save):
            return
        promotions = (
            (
                "relay",
                self.relay_service.is_complete_payload(game_id, payloads.get("relay")),
                payloads.get("relay"),
            ),
            (
                "boxscore",
                self.boxscore_service.is_complete_payload(game_id, payloads.get("boxscore")),
                payloads.get("boxscore"),
            ),
            (
                "lineup",
                self.lineup_service.is_complete_payload(game_id, payloads.get("lineup")),
                payloads.get("lineup"),
            ),
        )
        for namespace, complete, payload in promotions:
            if not complete:
                continue
            try:
                save(namespace, game_id, payload)
            except Exception as error:
                logger.info(
                    "Final snapshot promotion skipped for %s/%s (%s)",
                    namespace,
                    game_id,
                    type(error).__name__,
                )

    @staticmethod
    def _record_error(result: dict[str, Any], component: str, error: Exception) -> None:
        result["components"][component] = "error"
        result["errors"].append(
            {
                "component": component,
                "errorType": type(error).__name__,
            }
        )
