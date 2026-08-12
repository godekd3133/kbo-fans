from __future__ import annotations

from typing import Literal, Optional

from fastapi import APIRouter, Path, Query

from kbo_fans_backend.api.runtime_services import player_stats_service as service
from kbo_fans_backend.schemas.common import ApiEnvelope

router = APIRouter(prefix="/player")


@router.get("/{player_id}", response_model=ApiEnvelope[dict])
def get_player_detail(
    player_id: str = Path(..., min_length=1, max_length=32, pattern=r"^[A-Za-z0-9_-]+$"),
    season: int = Query(..., ge=1900, le=2100),
    player_type: Optional[Literal["hitter", "pitcher"]] = Query(default=None),
) -> ApiEnvelope[dict]:
    return ApiEnvelope.success_response(
        service.get_player_detail(player_id=player_id, season=season, player_type=player_type)
    )
