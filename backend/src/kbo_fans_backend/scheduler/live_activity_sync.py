from __future__ import annotations

import argparse
import atexit
import json
from typing import Optional

from kbo_fans_backend.api.runtime_services import (
    relay_service,
    scoreboard_service,
    standings_service,
)
from kbo_fans_backend.services.live_activity_scoreboard import LiveActivityScoreboardSyncService
from kbo_fans_backend.services.push import PushService
from kbo_fans_backend.utils.kbo_time import current_kbo_date_string

_sync_service_instance: Optional[LiveActivityScoreboardSyncService] = None


def current_kbo_date() -> str:
    return current_kbo_date_string()


def _get_sync_service() -> LiveActivityScoreboardSyncService:
    global _sync_service_instance
    if _sync_service_instance is None:
        _sync_service_instance = LiveActivityScoreboardSyncService(
            scoreboard_service=scoreboard_service,
            push_service=PushService(),
            relay_service=relay_service,
            standings_service=standings_service,
        )
    return _sync_service_instance


def sync_once(date: Optional[str] = None) -> dict:
    return _get_sync_service().sync_date(date or current_kbo_date())


def close_sync_service() -> None:
    global _sync_service_instance
    service = _sync_service_instance
    _sync_service_instance = None
    if service is not None:
        close = getattr(service, "close", None)
        if callable(close):
            close()


atexit.register(close_sync_service)


def main(argv: Optional[list[str]] = None) -> int:
    parser = argparse.ArgumentParser(
        description="Sync registered iOS Live Activities from the current scoreboard."
    )
    parser.add_argument("--date", default=None)
    args = parser.parse_args(argv)

    try:
        result = sync_once(args.date)
        print(json.dumps(result, ensure_ascii=False, sort_keys=True))
        return 0
    finally:
        close_sync_service()


if __name__ == "__main__":
    raise SystemExit(main())
