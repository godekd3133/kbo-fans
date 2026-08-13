from __future__ import annotations

import argparse
import json
import logging
import os
import signal
import threading
import time
from datetime import datetime
from typing import Callable, Optional

from kbo_fans_backend.api.runtime_services import scoreboard_service as runtime_scoreboard_service
from kbo_fans_backend.scheduler import baseball_info
from kbo_fans_backend.scheduler.live_activity_sync import current_kbo_date, sync_once
from kbo_fans_backend.services.push import PushService
from kbo_fans_backend.services.push_registry import PushRegistry
from kbo_fans_backend.utils.kbo_time import current_kbo_datetime

_SHOULD_STOP = False
_MIN_INTERVAL_SECONDS = 5
_DEFAULT_INTERVAL_SECONDS = 5
_DEFAULT_WARM_INTERVAL_SECONDS = 5
_DEFAULT_LIVE_SCOREBOARD_MAX_AGE_SECONDS = 20
_WARMER_FRESHNESS_JITTER_SECONDS = 5
_DEFAULT_BASEBALL_INFO_SMART_DAILY_TIMES = ("09:30", "16:00", "22:30")
_BASEBALL_INFO_WINDOW_MINUTES = 10
_WARMER_JOIN_TIMEOUT_SECONDS = 5.0
_ACTIVE_WARMER: Optional["ScoreboardWarmer"] = None
logger = logging.getLogger(__name__)


class ScoreboardWarmer:
    """Keeps the shared scoreboard cache warm independently of push delivery."""

    def __init__(
        self,
        *,
        scoreboard_service,
        interval_seconds: float,
        date_provider: Callable[[], str],
    ) -> None:
        if interval_seconds <= 0:
            raise ValueError("scoreboard warm interval must be positive")
        self._scoreboard_service = scoreboard_service
        self._interval_seconds = interval_seconds
        self._date_provider = date_provider
        self._stop_event = threading.Event()
        self._thread: Optional[threading.Thread] = None

    def start(self) -> None:
        if self._thread is not None and self._thread.is_alive():
            return
        self._stop_event.clear()
        self._thread = threading.Thread(
            target=self._run,
            name="kbo-scoreboard-warmer",
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

    def _run(self) -> None:
        next_run = time.monotonic()
        while not self._stop_event.is_set():
            target_date = None
            try:
                target_date = self._date_provider()
                self._scoreboard_service.prime_home_scoreboard(target_date)
            except Exception as error:
                logger.warning(
                    "%s",
                    json.dumps(
                        {
                            "component": "live_scoreboard_warmer",
                            "date": target_date,
                            "errorType": type(error).__name__,
                            "event": "prime_failed",
                        },
                        ensure_ascii=False,
                        sort_keys=True,
                    ),
                )

            next_run += self._interval_seconds
            now = time.monotonic()
            if next_run <= now:
                missed_intervals = int((now - next_run) // self._interval_seconds) + 1
                next_run += missed_intervals * self._interval_seconds
            if self._stop_event.wait(max(0, next_run - now)):
                return


def _handle_stop(signum, frame) -> None:
    del signum, frame
    global _SHOULD_STOP
    _SHOULD_STOP = True
    warmer = _ACTIVE_WARMER
    if warmer is not None:
        warmer.stop()


def _sleep_until_next_run(interval_seconds: int) -> None:
    deadline = time.monotonic() + interval_seconds
    while not _SHOULD_STOP and time.monotonic() < deadline:
        time.sleep(min(1, max(0, deadline - time.monotonic())))


def _now_kst() -> datetime:
    return current_kbo_datetime()


def _validate_scoreboard_warm_interval(interval_seconds: int) -> None:
    if interval_seconds < _MIN_INTERVAL_SECONDS:
        raise SystemExit(
            f"scoreboard-warm-interval-seconds must be at least {_MIN_INTERVAL_SECONDS}"
        )

    try:
        max_age_seconds = int(
            os.getenv(
                "LIVE_SCOREBOARD_MAX_AGE_SECONDS",
                str(_DEFAULT_LIVE_SCOREBOARD_MAX_AGE_SECONDS),
            )
        )
    except ValueError as error:
        raise SystemExit("LIVE_SCOREBOARD_MAX_AGE_SECONDS must be an integer") from error

    required_max_age = interval_seconds + _WARMER_FRESHNESS_JITTER_SECONDS
    if max_age_seconds < required_max_age:
        raise SystemExit(
            "LIVE_SCOREBOARD_MAX_AGE_SECONDS must be at least "
            f"{required_max_age} for scoreboard warm interval {interval_seconds}"
        )


def maybe_send_smart_daily_baseball_info(
    *,
    now: datetime,
    registry: Optional[PushRegistry] = None,
    push_service: Optional[PushService] = None,
    scoreboard_service=None,
    slots: Optional[list[str]] = None,
) -> dict:
    effective_slots = slots if slots is not None else _configured_baseball_info_slots()
    slot = _due_baseball_info_slot(now, effective_slots)
    if slot is None:
        return {
            "sent": False,
            "mode": "smart_daily",
            "reason": "not_due",
        }

    target_date = now.date().isoformat()
    alert_key = f"baseball_info:smart_daily:{target_date}:{slot}"
    push = push_service or PushService()
    alert_registry = registry or getattr(push, "registry", None) or PushRegistry()
    if alert_registry.scheduled_alert_sent(alert_key):
        return {
            "sent": False,
            "mode": "smart_daily",
            "slot": slot,
            "date": target_date,
            "reason": "already_sent",
        }

    response = baseball_info.send_smart_daily(
        date=target_date,
        now_time=now.strftime("%H:%M"),
        push_service=push,
        scoreboard_service=scoreboard_service,
        delivery_registry=alert_registry,
        delivery_alert_key=alert_key,
    )
    planned = response.get("planned")
    delivery_ids = (
        [
            str(delivery.get("deliveryId") or "")
            for delivery in planned
            if isinstance(delivery, dict) and delivery.get("deliveryId")
        ]
        if isinstance(planned, list)
        else []
    )
    alert_registry.mark_scheduled_alert_sent_if_deliveries_complete(
        alert_key,
        delivery_ids,
    )
    return {**response, "slot": slot}


def _configured_baseball_info_slots() -> list[str]:
    raw_value = os.getenv(
        "PUSH_BASEBALL_INFO_SMART_DAILY_TIMES",
        ",".join(_DEFAULT_BASEBALL_INFO_SMART_DAILY_TIMES),
    )
    if raw_value.strip().lower() in {"", "0", "false", "off", "disabled"}:
        return []
    return [
        slot
        for slot in (_normalize_time_slot(value) for value in raw_value.split(","))
        if slot is not None
    ]


def _due_baseball_info_slot(now: datetime, slots: list[str]) -> Optional[str]:
    now_minutes = (now.hour * 60) + now.minute
    for slot in slots:
        slot_minutes = _slot_to_minutes(slot)
        if slot_minutes is None:
            continue
        delta = now_minutes - slot_minutes
        if 0 <= delta <= _BASEBALL_INFO_WINDOW_MINUTES:
            return slot
    return None


def _normalize_time_slot(value: str) -> Optional[str]:
    parts = value.strip().split(":")
    if len(parts) != 2:
        return None
    try:
        hour = int(parts[0])
        minute = int(parts[1])
    except ValueError:
        return None
    if hour < 0 or hour > 23 or minute < 0 or minute > 59:
        return None
    return f"{hour:02d}:{minute:02d}"


def _slot_to_minutes(value: str) -> Optional[int]:
    normalized = _normalize_time_slot(value)
    if normalized is None:
        return None
    hour, minute = normalized.split(":")
    return (int(hour) * 60) + int(minute)


def main(argv: Optional[list[str]] = None) -> int:
    global _ACTIVE_WARMER
    parser = argparse.ArgumentParser(
        description="Continuously sync registered iOS Live Activities from KBO scoreboard."
    )
    parser.add_argument("--date", default=None)
    parser.add_argument(
        "--interval-seconds",
        type=int,
        default=int(os.getenv("PUSH_SYNC_INTERVAL_SECONDS", str(_DEFAULT_INTERVAL_SECONDS))),
    )
    parser.add_argument(
        "--scoreboard-warm-interval-seconds",
        type=int,
        default=int(
            os.getenv(
                "SCOREBOARD_WARM_INTERVAL_SECONDS",
                str(_DEFAULT_WARM_INTERVAL_SECONDS),
            )
        ),
    )
    args = parser.parse_args(argv)

    if args.interval_seconds < _MIN_INTERVAL_SECONDS:
        raise SystemExit(f"interval-seconds must be at least {_MIN_INTERVAL_SECONDS}")
    _validate_scoreboard_warm_interval(args.scoreboard_warm_interval_seconds)

    signal.signal(signal.SIGTERM, _handle_stop)
    signal.signal(signal.SIGINT, _handle_stop)

    warmer = ScoreboardWarmer(
        scoreboard_service=runtime_scoreboard_service,
        interval_seconds=args.scoreboard_warm_interval_seconds,
        date_provider=lambda: args.date or current_kbo_date(),
    )
    _ACTIVE_WARMER = warmer
    try:
        warmer.start()
        while not _SHOULD_STOP:
            sync_date = args.date or current_kbo_date()
            try:
                result = sync_once(sync_date)
                if args.date is None:
                    baseball_info_result = maybe_send_smart_daily_baseball_info(
                        now=_now_kst(),
                    )
                    if baseball_info_result.get("reason") != "not_due":
                        result["baseballInfo"] = baseball_info_result
                print(json.dumps(result, ensure_ascii=False, sort_keys=True), flush=True)
            except Exception as error:
                payload = {
                    "date": sync_date,
                    "error": str(error),
                    "sent": False,
                }
                print(json.dumps(payload, ensure_ascii=False, sort_keys=True), flush=True)
            _sleep_until_next_run(args.interval_seconds)
    finally:
        warmer.stop()
        warmer.join(timeout=_WARMER_JOIN_TIMEOUT_SECONDS)
        if warmer.is_alive():
            logger.warning(
                "%s",
                json.dumps(
                    {
                        "component": "live_scoreboard_warmer",
                        "event": "join_timeout",
                    },
                    sort_keys=True,
                ),
            )
        if _ACTIVE_WARMER is warmer:
            _ACTIVE_WARMER = None

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
