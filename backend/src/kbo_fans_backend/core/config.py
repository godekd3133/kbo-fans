from __future__ import annotations

import os
from dataclasses import dataclass
from functools import lru_cache


def _get_bool(name: str, default: bool) -> bool:
    value = os.getenv(name)
    if value is None:
        return default
    return value.lower() in {"1", "true", "yes", "on"}


def _get_int(name: str, default: int) -> int:
    value = os.getenv(name)
    return int(value) if value is not None else default


@dataclass(frozen=True)
class Settings:
    app_name: str
    app_env: str
    debug: bool
    api_prefix: str
    request_timeout_seconds: int
    kbo_base_url: str


@lru_cache
def get_settings() -> Settings:
    return Settings(
        app_name=os.getenv("APP_NAME", "KBO Fans API"),
        app_env=os.getenv("APP_ENV", "local"),
        debug=_get_bool("APP_DEBUG", True),
        api_prefix=os.getenv("API_PREFIX", "/api"),
        request_timeout_seconds=_get_int("REQUEST_TIMEOUT_SECONDS", 10),
        kbo_base_url=os.getenv("KBO_BASE_URL", "https://www.koreabaseball.com"),
    )
