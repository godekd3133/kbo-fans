from __future__ import annotations

import argparse
import json
from datetime import datetime, timedelta, timezone
from typing import Optional

from kbo_fans_backend.api.runtime_services import scoreboard_service
from kbo_fans_backend.services.live_activity_scoreboard import LiveActivityScoreboardSyncService
from kbo_fans_backend.services.push import PushService

try:
    from zoneinfo import ZoneInfo
except ImportError:  # pragma: no cover - Python 3.9+ expected
    ZoneInfo = None

_KST = timezone(timedelta(hours=9))


def current_kbo_date() -> str:
    tz = ZoneInfo("Asia/Seoul") if ZoneInfo is not None else _KST
    return datetime.now(tz).date().isoformat()


def sync_once(date: Optional[str] = None) -> dict:
    service = LiveActivityScoreboardSyncService(
        scoreboard_service=scoreboard_service,
        push_service=PushService(),
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
