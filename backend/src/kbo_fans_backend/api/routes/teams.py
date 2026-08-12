from __future__ import annotations

import concurrent.futures

from fastapi import APIRouter, HTTPException, Path, Query

from kbo_fans_backend.api.runtime_services import (
    player_stats_service as service,
)
from kbo_fans_backend.api.runtime_services import (
    team_stats_service,
)
from kbo_fans_backend.schemas.common import ApiEnvelope

router = APIRouter(prefix="/team")
_KBO_TEAM_IDS = frozenset(("LG", "KT", "SK", "SS", "NC", "HH", "LT", "HT", "OB", "WO"))


def _normalize_team_id(team_id: str) -> str:
    normalized = team_id.upper()
    if normalized not in _KBO_TEAM_IDS:
        raise HTTPException(status_code=422, detail="유효하지 않은 팀 ID입니다")
    return normalized


@router.get("/{team_id}/players", response_model=ApiEnvelope[dict])
def get_team_players(
    team_id: str = Path(..., min_length=2, max_length=2, pattern=r"^[A-Za-z]{2}$"),
    season: int = Query(..., ge=1900, le=2100),
) -> ApiEnvelope[dict]:
    return ApiEnvelope.success_response(
        service.get_team_players(_normalize_team_id(team_id), season)
    )


@router.get("/{team_id}/stats", response_model=ApiEnvelope[dict])
def get_team_stats(
    team_id: str = Path(..., min_length=2, max_length=2, pattern=r"^[A-Za-z]{2}$"),
    season: int = Query(..., ge=1900, le=2100),
) -> ApiEnvelope[dict]:
    return ApiEnvelope.success_response(
        team_stats_service.get_team_stats(_normalize_team_id(team_id), season)
    )


@router.get("/{team_id}/records", response_model=ApiEnvelope[dict])
def get_team_records(
    team_id: str = Path(..., min_length=2, max_length=2, pattern=r"^[A-Za-z]{2}$"),
    season: int = Query(..., ge=1900, le=2100),
) -> ApiEnvelope[dict]:
    team_id = _normalize_team_id(team_id)
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
