from __future__ import annotations

import concurrent.futures

from fastapi import APIRouter, Query

from kbo_fans_backend.api.runtime_services import (
    player_stats_service as service,
)
from kbo_fans_backend.api.runtime_services import (
    team_stats_service,
)
from kbo_fans_backend.schemas.common import ApiEnvelope

router = APIRouter(prefix="/team")


@router.get("/{team_id}/players", response_model=ApiEnvelope[dict])
def get_team_players(team_id: str, season: int = Query(...)) -> ApiEnvelope[dict]:
    return ApiEnvelope.success_response(service.get_team_players(team_id, season))


@router.get("/{team_id}/stats", response_model=ApiEnvelope[dict])
def get_team_stats(team_id: str, season: int = Query(...)) -> ApiEnvelope[dict]:
    return ApiEnvelope.success_response(team_stats_service.get_team_stats(team_id, season))


@router.get("/{team_id}/records", response_model=ApiEnvelope[dict])
def get_team_records(team_id: str, season: int = Query(...)) -> ApiEnvelope[dict]:
    with concurrent.futures.ThreadPoolExecutor(max_workers=2) as executor:
        players_future = executor.submit(service.get_team_players, team_id, season)
        stats_future = executor.submit(team_stats_service.get_team_stats, team_id, season)
        players_payload = players_future.result()
        stats_payload = stats_future.result()

    return ApiEnvelope.success_response(
        {
            "teamId": team_id,
            "season": season,
            "players": players_payload.get("players", []),
            "teamStats": stats_payload,
        }
    )
