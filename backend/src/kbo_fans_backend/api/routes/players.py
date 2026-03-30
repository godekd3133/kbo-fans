from __future__ import annotations

from typing import Optional

from fastapi import APIRouter, Query

from kbo_fans_backend.schemas.common import ApiEnvelope
from kbo_fans_backend.services.player_stats import PlayerStatsService

router = APIRouter(prefix="/player")
service = PlayerStatsService()


@router.get("/{player_id}", response_model=ApiEnvelope[dict])
def get_player_detail(
    player_id: str,
    season: int = Query(...),
    player_type: Optional[str] = Query(default=None),
) -> ApiEnvelope[dict]:
    return ApiEnvelope.success_response(
        service.get_player_detail(player_id=player_id, season=season, player_type=player_type)
    )
