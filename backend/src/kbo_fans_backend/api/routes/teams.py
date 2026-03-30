from fastapi import APIRouter, Query

from kbo_fans_backend.schemas.common import ApiEnvelope
from kbo_fans_backend.services.player_stats import PlayerStatsService
from kbo_fans_backend.services.team_stats import TeamStatsService

router = APIRouter(prefix="/team")
service = PlayerStatsService()
team_stats_service = TeamStatsService()


@router.get("/{team_id}/players", response_model=ApiEnvelope[dict])
def get_team_players(team_id: str, season: int = Query(...)) -> ApiEnvelope[dict]:
    return ApiEnvelope.success_response(service.get_team_players(team_id, season))


@router.get("/{team_id}/stats", response_model=ApiEnvelope[dict])
def get_team_stats(team_id: str, season: int = Query(...)) -> ApiEnvelope[dict]:
    return ApiEnvelope.success_response(team_stats_service.get_team_stats(team_id, season))
