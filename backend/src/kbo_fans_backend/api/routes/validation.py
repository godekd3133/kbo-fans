from __future__ import annotations

from datetime import date

from fastapi import HTTPException

MIN_SUPPORTED_KBO_YEAR = 1900
MAX_SUPPORTED_KBO_YEAR = 2100


def ensure_supported_kbo_date(value: date) -> date:
    if not MIN_SUPPORTED_KBO_YEAR <= value.year <= MAX_SUPPORTED_KBO_YEAR:
        raise HTTPException(status_code=422, detail="지원하지 않는 KBO 날짜입니다")
    return value


def ensure_supported_kbo_month(month: str) -> str:
    year = int(month[:4])
    if not MIN_SUPPORTED_KBO_YEAR <= year <= MAX_SUPPORTED_KBO_YEAR:
        raise HTTPException(status_code=422, detail="지원하지 않는 KBO 월입니다")
    return month
