from __future__ import annotations

import json
import logging
import threading
import time
from typing import Callable, Optional

from kbo_fans_backend.services.live_game_data import LiveGameDataWarmService

logger = logging.getLogger(__name__)


class LiveGameDataWarmer:
    """Warms detailed data for LIVE games and finalizes finished games.

    The loop is deliberately single-threaded: one cycle must finish before a
    later cycle begins. Its next interval is based on the measured cycle time,
    bounded by the configured minimum and maximum, so a slow KBO response
    cannot create overlapping crawler waves.
    """

    def __init__(
        self,
        *,
        scoreboard_service,
        game_data_service: LiveGameDataWarmService,
        interval_seconds: float,
        max_interval_seconds: float,
        interval_margin: float,
        date_provider: Callable[[], str],
    ) -> None:
        if interval_seconds <= 0:
            raise ValueError("live game data warm interval must be positive")
        if max_interval_seconds < interval_seconds:
            raise ValueError("live game data warm max interval must cover the minimum")
        if interval_margin < 0:
            raise ValueError("live game data warm interval margin must not be negative")
        self._scoreboard_service = scoreboard_service
        self._game_data_service = game_data_service
        self._interval_seconds = float(interval_seconds)
        self._max_interval_seconds = float(max_interval_seconds)
        self._interval_margin = float(interval_margin)
        self._date_provider = date_provider
        self._stop_event = threading.Event()
        self._thread: Optional[threading.Thread] = None

    def start(self) -> None:
        if self._thread is not None and self._thread.is_alive():
            return
        self._stop_event.clear()
        self._thread = threading.Thread(
            target=self._run,
            name="kbo-live-game-data-warmer",
            daemon=True,
        )
        self._thread.start()

    def stop(self) -> None:
        self._stop_event.set()

    def join(self, timeout: Optional[float] = None) -> None:
        thread = self._thread
        if thread is not None:
            thread.join(timeout=timeout)

    def is_alive(self) -> bool:
        return self._thread is not None and self._thread.is_alive()

    def interval_for_cycle(self, cycle_seconds: float) -> float:
        measured_interval = max(0.0, float(cycle_seconds)) * (1.0 + self._interval_margin)
        return min(
            self._max_interval_seconds,
            max(self._interval_seconds, measured_interval),
        )

    def _run(self) -> None:
        while not self._stop_event.is_set():
            started_at = time.perf_counter()
            target_date: Optional[str] = None
            live_count = 0
            final_count = 0
            try:
                target_date = self._date_provider()
                scoreboard = self._scoreboard_service.get_home_scoreboard(target_date)
                games = scoreboard.get("games", []) if isinstance(scoreboard, dict) else []
                warmable_games = [
                    game
                    for game in games
                    if isinstance(game, dict)
                    and str(game.get("status") or "").strip().upper() in {"LIVE", "FINAL"}
                ]
                live_count = sum(
                    str(game.get("status") or "").strip().upper() == "LIVE"
                    for game in warmable_games
                )
                final_count = sum(
                    str(game.get("status") or "").strip().upper() == "FINAL"
                    for game in warmable_games
                )
                result = self._game_data_service.warm_games(warmable_games)
                cycle_seconds = time.perf_counter() - started_at
                next_interval = self.interval_for_cycle(cycle_seconds)
                logger.info(
                    "%s",
                    json.dumps(
                        {
                            "component": "live_game_data_warmer",
                            "date": target_date,
                            "cycleDurationMs": round(cycle_seconds * 1000, 1),
                            "liveGames": live_count,
                            "finalGames": final_count,
                            "finalizedGames": result.get("finalizedGames", 0),
                            "nextIntervalSeconds": round(next_interval, 1),
                            "event": "cycle_complete",
                            "results": result.get("results", []),
                        },
                        ensure_ascii=False,
                        sort_keys=True,
                    ),
                )
            except Exception as error:
                cycle_seconds = time.perf_counter() - started_at
                next_interval = self.interval_for_cycle(cycle_seconds)
                logger.warning(
                    "%s",
                    json.dumps(
                        {
                            "component": "live_game_data_warmer",
                            "date": target_date,
                            "cycleDurationMs": round(cycle_seconds * 1000, 1),
                            "nextIntervalSeconds": round(next_interval, 1),
                            "errorType": type(error).__name__,
                            "event": "cycle_failed",
                        },
                        ensure_ascii=False,
                        sort_keys=True,
                    ),
                )

            self._stop_event.wait(next_interval)
