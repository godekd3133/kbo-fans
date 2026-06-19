from __future__ import annotations

import argparse
import json
from datetime import datetime, timedelta, timezone
from typing import Optional

from kbo_fans_backend.services.push import PushService

try:
    from zoneinfo import ZoneInfo
except ImportError:  # pragma: no cover - Python 3.9+ expected
    ZoneInfo = None

_KST = timezone(timedelta(hours=9))


def current_kbo_date() -> str:
    tz = ZoneInfo("Asia/Seoul") if ZoneInfo is not None else _KST
    return datetime.now(tz).date().isoformat()


def send_once(
    *,
    date: Optional[str] = None,
    kind: Optional[str] = None,
    topic: Optional[str] = None,
    token: Optional[str] = None,
    team_id: Optional[str] = None,
) -> dict:
    target_date = date or current_kbo_date()
    resolved_kind = kind or _scheduled_kind_for_date(target_date)
    if resolved_kind is None:
        return {
            "sent": False,
            "date": target_date,
            "reason": "no scheduled baseball info prompt",
        }

    response = PushService().send_baseball_info(
        kind=resolved_kind,
        date=target_date,
        topic=topic,
        token=token,
        team_id=team_id,
    )
    return {"date": target_date, **response}


def _scheduled_kind_for_date(date_text: str) -> Optional[str]:
    try:
        parsed = datetime.strptime(date_text, "%Y-%m-%d").date()
    except ValueError:
        return None
    if parsed.weekday() == 0:
        return "weekly_check"
    return None


def main(argv: Optional[list[str]] = None) -> int:
    parser = argparse.ArgumentParser(
        description="Send scheduled KBO baseball info push prompts."
    )
    parser.add_argument("--date", default=None)
    parser.add_argument(
        "--kind",
        choices=[
            "weekly_check",
            "off_day",
            "records_check",
            "lineup_day",
            "rival_watch",
        ],
        default=None,
    )
    parser.add_argument("--topic", default=None)
    parser.add_argument("--token", default=None)
    parser.add_argument("--team-id", default=None)
    args = parser.parse_args(argv)

    result = send_once(
        date=args.date,
        kind=args.kind,
        topic=args.topic,
        token=args.token,
        team_id=args.team_id,
    )
    print(json.dumps(result, ensure_ascii=False, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
