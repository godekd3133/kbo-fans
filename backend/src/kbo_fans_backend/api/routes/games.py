from __future__ import annotations

from typing import Optional

from fastapi import APIRouter, Query

from kbo_fans_backend.schemas.common import ApiEnvelope
from kbo_fans_backend.services.boxscore import BoxscoreService
from kbo_fans_backend.services.lineup import LineupService
from kbo_fans_backend.utils.errors import raise_not_implemented

router = APIRouter(prefix="/game/{game_id}")
boxscore_service = BoxscoreService()
lineup_service = LineupService()


@router.get("/relay", response_model=ApiEnvelope[dict])
def get_relay(game_id: str, after: Optional[int] = Query(default=None)) -> ApiEnvelope[dict]:
    raise_not_implemented(f"Relay endpoint for {game_id} is not implemented yet.")


@router.get("/boxscore", response_model=ApiEnvelope[dict])
def get_boxscore(game_id: str) -> ApiEnvelope[dict]:
    return ApiEnvelope.success_response(boxscore_service.get_boxscore(game_id))


@router.get("/lineup", response_model=ApiEnvelope[dict])
def get_lineup(game_id: str) -> ApiEnvelope[dict]:
    return ApiEnvelope.success_response(lineup_service.get_lineup(game_id))
