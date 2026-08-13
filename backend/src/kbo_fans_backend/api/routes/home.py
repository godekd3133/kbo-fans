from __future__ import annotations

from datetime import date as date_type
from typing import Optional

from fastapi import APIRouter, Query

from kbo_fans_backend.api.routes.validation import (
    ensure_supported_kbo_date,
    normalize_optional_kbo_team_id,
)
from kbo_fans_backend.api.runtime_services import home_service as service
from kbo_fans_backend.schemas.common import ApiEnvelope
from kbo_fans_backend.utils.kbo_time import current_kbo_date_string

router = APIRouter()


@router.get("/home", response_model=ApiEnvelope[dict])
def get_home(
    date: Optional[date_type] = None,
    myTeam: Optional[str] = Query(
        default=None,
        min_length=2,
        max_length=2,
        pattern=r"^[A-Za-z]{2}$",
    ),
) -> ApiEnvelope[dict]:
    if date is not None:
        ensure_supported_kbo_date(date)
    target_date = date.isoformat() if date is not None else current_kbo_date_string()
    normalized_my_team = normalize_optional_kbo_team_id(myTeam)
    return ApiEnvelope.success_response(service.get_home(target_date, normalized_my_team))
