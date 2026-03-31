from __future__ import annotations

import concurrent.futures
from typing import Any, Dict

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


@router.get("/{team_id}/records", response_model=ApiEnvelope[dict])
def get_team_records(team_id: str, season: int = Query(...)) -> ApiEnvelope[dict]:
    with concurrent.futures.ThreadPoolExecutor(max_workers=2) as executor:
        players_future = executor.submit(service.get_team_players, team_id, season)
        stats_future = executor.submit(team_stats_service.get_team_stats, team_id, season)
        players_payload = _safe_future_result(
            players_future,
            fallback={"teamId": team_id, "season": season, "players": []},
        )
        stats_payload = _safe_future_result(
            stats_future,
            fallback={
                "teamId": team_id,
                "season": season,
                "hitting": {},
                "pitching": {},
            },
        )

    return ApiEnvelope.success_response(
        {
            "teamId": team_id,
            "season": season,
            "players": players_payload.get("players", []),
            "teamStats": stats_payload,
        }
    )


def _safe_future_result(
    future: concurrent.futures.Future, fallback: Dict[str, Any]
) -> Dict[str, Any]:
    try:
        return future.result()
    except Exception:
        return fallback
