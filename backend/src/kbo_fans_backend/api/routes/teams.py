from fastapi import APIRouter, Query

from kbo_fans_backend.schemas.common import ApiEnvelope
from kbo_fans_backend.utils.errors import raise_not_implemented

router = APIRouter(prefix="/team")


@router.get("/{team_id}/players", response_model=ApiEnvelope[dict])
def get_team_players(team_id: str, season: int = Query(...)) -> ApiEnvelope[dict]:
    raise_not_implemented(f"Player stats endpoint for {team_id}/{season} is not implemented yet.")
