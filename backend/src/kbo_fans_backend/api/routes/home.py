from __future__ import annotations

from datetime import date as date_type
from typing import Optional

from fastapi import APIRouter, Query

from kbo_fans_backend.api.runtime_services import home_service as service
from kbo_fans_backend.schemas.common import ApiEnvelope

router = APIRouter()


@router.get("/home", response_model=ApiEnvelope[dict])
def get_home(
    date: Optional[str] = Query(default=None),
    myTeam: Optional[str] = Query(default=None),
) -> ApiEnvelope[dict]:
    target_date = date or date_type.today().isoformat()
    return ApiEnvelope.success_response(service.get_home(target_date, myTeam))
