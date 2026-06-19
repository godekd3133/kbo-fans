from __future__ import annotations

import argparse
import json
import os
import signal
import time
from typing import Optional

from kbo_fans_backend.scheduler.live_activity_sync import current_kbo_date, sync_once

_SHOULD_STOP = False
_MIN_INTERVAL_SECONDS = 5
_DEFAULT_INTERVAL_SECONDS = 5


def _handle_stop(signum, frame) -> None:
    del signum, frame
    global _SHOULD_STOP
    _SHOULD_STOP = True


def _sleep_until_next_run(interval_seconds: int) -> None:
    deadline = time.monotonic() + interval_seconds
    while not _SHOULD_STOP and time.monotonic() < deadline:
        time.sleep(min(1, max(0, deadline - time.monotonic())))


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
