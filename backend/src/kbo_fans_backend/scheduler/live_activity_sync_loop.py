from __future__ import annotations

import argparse
import json
import os
import signal
import time
from datetime import datetime, timedelta, timezone
from typing import Optional

from kbo_fans_backend.scheduler import baseball_info
from kbo_fans_backend.scheduler.live_activity_sync import current_kbo_date, sync_once
from kbo_fans_backend.services.push import PushService
from kbo_fans_backend.services.push_registry import PushRegistry

try:
    from zoneinfo import ZoneInfo
except ImportError:  # pragma: no cover - Python 3.9+ expected
    ZoneInfo = None

_SHOULD_STOP = False
_MIN_INTERVAL_SECONDS = 5
_DEFAULT_INTERVAL_SECONDS = 5
_DEFAULT_BASEBALL_INFO_SMART_DAILY_TIMES = ("09:30", "16:00", "22:30")
_BASEBALL_INFO_WINDOW_MINUTES = 10
_KST = timezone(timedelta(hours=9))


def _handle_stop(signum, frame) -> None:
    del signum, frame
    global _SHOULD_STOP
    _SHOULD_STOP = True


def _sleep_until_next_run(interval_seconds: int) -> None:
    deadline = time.monotonic() + interval_seconds
    while not _SHOULD_STOP and time.monotonic() < deadline:
        time.sleep(min(1, max(0, deadline - time.monotonic())))


def _now_kst() -> datetime:
    tz = ZoneInfo("Asia/Seoul") if ZoneInfo is not None else _KST
    return datetime.now(tz)


def maybe_send_smart_daily_baseball_info(
    *,
    now: datetime,
    registry: Optional[PushRegistry] = None,
    push_service: Optional[PushService] = None,
    scoreboard_service=None,
    slots: Optional[list[str]] = None,
) -> dict:
    effective_slots = (
        slots if slots is not None else _configured_baseball_info_slots()
    )
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

    alert_registry.mark_scheduled_alert_sent(alert_key)
    response = baseball_info.send_smart_daily(
        date=target_date,
        now_time=now.strftime("%H:%M"),
        push_service=push,
        scoreboard_service=scoreboard_service,
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
        for slot in (
            _normalize_time_slot(value)
            for value in raw_value.split(",")
        )
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
    parser = argparse.ArgumentParser(
        description="Continuously sync registered iOS Live Activities from KBO scoreboard."
    )
    parser.add_argument("--date", default=None)
    parser.add_argument(
        "--interval-seconds",
        type=int,
        default=int(
            os.getenv("PUSH_SYNC_INTERVAL_SECONDS", str(_DEFAULT_INTERVAL_SECONDS))
        ),
    )
    args = parser.parse_args(argv)

    if args.interval_seconds < _MIN_INTERVAL_SECONDS:
        raise SystemExit(
            f"interval-seconds must be at least {_MIN_INTERVAL_SECONDS}"
        )

    signal.signal(signal.SIGTERM, _handle_stop)
    signal.signal(signal.SIGINT, _handle_stop)

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

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
