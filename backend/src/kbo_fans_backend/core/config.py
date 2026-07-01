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
    firebase_service_account_path: str
    firebase_service_account_json: str
    firebase_project_id: str
    push_registry_path: str
    push_sync_secret: str
    apns_key_id: str
    apns_team_id: str
    apns_bundle_id: str
    apns_auth_key_path: str
    apns_auth_key_p8: str
    apns_use_sandbox: bool
    snapshot_dir: str
    live_scoreboard_state_path: str
    live_scoreboard_max_age_seconds: int


@lru_cache
def get_settings() -> Settings:
    app_env = os.getenv("APP_ENV", "local")
    push_registry_path = os.getenv(
        "PUSH_REGISTRY_PATH",
        str(Path(__file__).resolve().parents[3] / "data" / "runtime" / "push_registry.json"),
    )
    return Settings(
        app_name=os.getenv("APP_NAME", "KBO Fans API"),
        app_env=app_env,
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
        firebase_service_account_path=os.getenv("FIREBASE_SERVICE_ACCOUNT_PATH", ""),
        firebase_service_account_json=os.getenv("FIREBASE_SERVICE_ACCOUNT_JSON", ""),
        firebase_project_id=os.getenv("FIREBASE_PROJECT_ID", ""),
        push_registry_path=push_registry_path,
        push_sync_secret=os.getenv("PUSH_SYNC_SECRET", ""),
        apns_key_id=os.getenv("APNS_KEY_ID", ""),
        apns_team_id=os.getenv("APNS_TEAM_ID", ""),
        apns_bundle_id=os.getenv("APNS_BUNDLE_ID", "com.kbofans.kboFans"),
        apns_auth_key_path=os.getenv("APNS_AUTH_KEY_PATH", ""),
        apns_auth_key_p8=os.getenv("APNS_AUTH_KEY_P8", ""),
        apns_use_sandbox=_get_bool("APNS_USE_SANDBOX", app_env != "release"),
        snapshot_dir=os.getenv(
            "SNAPSHOT_DIR",
            str(Path(__file__).resolve().parents[3] / "data" / "snapshots"),
        ),
        live_scoreboard_state_path=os.getenv(
            "LIVE_SCOREBOARD_STATE_PATH",
            str(Path(push_registry_path).expanduser().with_name("live_scoreboard.json")),
        ),
        live_scoreboard_max_age_seconds=_get_int("LIVE_SCOREBOARD_MAX_AGE_SECONDS", 8),
    )
