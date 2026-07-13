from __future__ import annotations

import argparse
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


def current_kbo_date() -> str:
    return current_kbo_date_string()


def sync_once(date: Optional[str] = None) -> dict:
    service = LiveActivityScoreboardSyncService(
        scoreboard_service=scoreboard_service,
        push_service=PushService(),
        relay_service=relay_service,
        standings_service=standings_service,
    )
    return service.sync_date(date or current_kbo_date())


def main(argv: Optional[list[str]] = None) -> int:
    parser = argparse.ArgumentParser(
        description="Sync registered iOS Live Activities from the current scoreboard."
    )
    parser.add_argument("--date", default=None)
    args = parser.parse_args(argv)

    result = sync_once(args.date)
    print(json.dumps(result, ensure_ascii=False, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
