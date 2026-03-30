from __future__ import annotations

import os
from dataclasses import dataclass
from functools import lru_cache
from pathlib import Path


def _load_local_env() -> None:
    env_path = Path(__file__).resolve().parents[3] / ".env"
    if not env_path.exists():
        return

    for raw_line in env_path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        os.environ.setdefault(key.strip(), value.strip())


_load_local_env()


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
    cors_allow_origin_regex: str
    kbo_relay_user_id: str
    kbo_relay_password: str


@lru_cache
def get_settings() -> Settings:
    return Settings(
        app_name=os.getenv("APP_NAME", "KBO Fans API"),
        app_env=os.getenv("APP_ENV", "local"),
        debug=_get_bool("APP_DEBUG", True),
        api_prefix=os.getenv("API_PREFIX", "/api"),
        request_timeout_seconds=_get_int("REQUEST_TIMEOUT_SECONDS", 10),
        kbo_base_url=os.getenv("KBO_BASE_URL", "https://www.koreabaseball.com"),
        cors_allow_origin_regex=os.getenv(
            "CORS_ALLOW_ORIGIN_REGEX",
            r"^https?://(localhost|127\.0\.0\.1)(:\d+)?$",
        ),
        kbo_relay_user_id=os.getenv("KBO_RELAY_USER_ID", ""),
        kbo_relay_password=os.getenv("KBO_RELAY_PASSWORD", ""),
    )
