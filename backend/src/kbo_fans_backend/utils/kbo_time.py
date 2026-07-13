from __future__ import annotations

from datetime import date, datetime, timedelta, timezone, tzinfo
from typing import Optional

try:
    from zoneinfo import ZoneInfo, ZoneInfoNotFoundError
except ImportError:  # pragma: no cover - Python 3.9+ includes zoneinfo
    ZoneInfo = None  # type: ignore[assignment]
    ZoneInfoNotFoundError = KeyError  # type: ignore[misc,assignment]

_FIXED_KST = timezone(timedelta(hours=9))


def kbo_timezone() -> tzinfo:
    if ZoneInfo is None:
        return _FIXED_KST
    try:
        return ZoneInfo("Asia/Seoul")
    except ZoneInfoNotFoundError:  # pragma: no cover - tzdata-less runtime fallback
        return _FIXED_KST


def current_kbo_datetime(now: Optional[datetime] = None) -> datetime:
    instant = now or datetime.now(timezone.utc)
    if instant.tzinfo is None:
        instant = instant.replace(tzinfo=timezone.utc)
    return instant.astimezone(kbo_timezone())


def current_kbo_date(now: Optional[datetime] = None) -> date:
    return current_kbo_datetime(now).date()


def current_kbo_date_string(now: Optional[datetime] = None) -> str:
    return current_kbo_date(now).isoformat()


def current_kbo_year(now: Optional[datetime] = None) -> int:
    return current_kbo_datetime(now).year
