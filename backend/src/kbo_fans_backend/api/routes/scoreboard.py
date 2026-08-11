from __future__ import annotations

import secrets
from typing import Optional

from fastapi import APIRouter, Header, Query

from kbo_fans_backend.api.runtime_services import scoreboard_service as service
from kbo_fans_backend.core.config import get_settings
from kbo_fans_backend.schemas.common import ApiEnvelope
from kbo_fans_backend.utils.kbo_time import current_kbo_date_string

router = APIRouter()


def trusted_force_refresh(requested: bool, provided_secret: Optional[str]) -> bool:
    if not requested or provided_secret is None:
        return False

    expected_secret = get_settings().push_sync_secret
    return bool(
        expected_secret
        and secrets.compare_digest(
            provided_secret.encode("utf-8"),
            expected_secret.encode("utf-8"),
        )
    )


@router.get("/scoreboard", response_model=ApiEnvelope[dict])
def get_scoreboard(
    date: Optional[str] = Query(default=None),
    forceRefresh: bool = Query(default=False),
    x_kbo_push_sync_secret: Optional[str] = Header(default=None),
) -> ApiEnvelope[dict]:
    target_date = date or current_kbo_date_string()
    return ApiEnvelope.success_response(
        service.get_scoreboard(
            target_date,
            force_refresh=trusted_force_refresh(
                forceRefresh,
                x_kbo_push_sync_secret,
            ),
        )
    )


@router.get("/scoreboard/home", response_model=ApiEnvelope[dict])
def get_home_scoreboard(
    date: Optional[str] = Query(default=None),
    forceRefresh: bool = Query(default=False),
    x_kbo_push_sync_secret: Optional[str] = Header(default=None),
) -> ApiEnvelope[dict]:
    target_date = date or current_kbo_date_string()
    return ApiEnvelope.success_response(
        service.get_home_scoreboard(
            target_date,
            force_refresh=trusted_force_refresh(
                forceRefresh,
                x_kbo_push_sync_secret,
            ),
        )
    )


@router.get("/scoreboard/compact", response_model=ApiEnvelope[dict])
def get_compact_scoreboard(
    date: Optional[str] = Query(default=None),
    myTeam: Optional[str] = Query(default=None),
) -> ApiEnvelope[dict]:
    target_date = date or current_kbo_date_string()
    return ApiEnvelope.success_response(service.get_compact_scoreboard(target_date, my_team=myTeam))
