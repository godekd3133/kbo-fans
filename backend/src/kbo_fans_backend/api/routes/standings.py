from __future__ import annotations

from fastapi import APIRouter, Query

from kbo_fans_backend.schemas.common import ApiEnvelope
from kbo_fans_backend.services.standings import StandingsService

router = APIRouter()
service = StandingsService()


@router.get("/standings", response_model=ApiEnvelope[dict])
def get_standings(season: int = Query(...)) -> ApiEnvelope[dict]:
    return ApiEnvelope.success_response(service.get_standings(season))
