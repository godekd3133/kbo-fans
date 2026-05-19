from __future__ import annotations

from datetime import date as date_type
from typing import Optional

from fastapi import APIRouter, Query

from kbo_fans_backend.schemas.common import ApiEnvelope
from kbo_fans_backend.services.scoreboard import ScoreboardService

router = APIRouter()
service = ScoreboardService()


@router.get("/scoreboard", response_model=ApiEnvelope[dict])
def get_scoreboard(date: Optional[str] = Query(default=None)) -> ApiEnvelope[dict]:
    target_date = date or date_type.today().isoformat()
    return ApiEnvelope.success_response(service.get_scoreboard(target_date))


@router.get("/scoreboard/home", response_model=ApiEnvelope[dict])
def get_home_scoreboard(date: Optional[str] = Query(default=None)) -> ApiEnvelope[dict]:
    target_date = date or date_type.today().isoformat()
    return ApiEnvelope.success_response(service.get_home_scoreboard(target_date))


@router.get("/scoreboard/compact", response_model=ApiEnvelope[dict])
def get_compact_scoreboard(
    date: Optional[str] = Query(default=None),
    myTeam: Optional[str] = Query(default=None),
) -> ApiEnvelope[dict]:
    target_date = date or date_type.today().isoformat()
    return ApiEnvelope.success_response(
        service.get_compact_scoreboard(target_date, my_team=myTeam)
    )
