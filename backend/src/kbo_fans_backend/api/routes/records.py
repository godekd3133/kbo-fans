from fastapi import APIRouter, Query

from kbo_fans_backend.api.runtime_services import records_overview_service as service
from kbo_fans_backend.schemas.common import ApiEnvelope

router = APIRouter(prefix="/records")


@router.get("/overview", response_model=ApiEnvelope[dict])
def get_records_overview(season: int = Query(...)) -> ApiEnvelope[dict]:
    return ApiEnvelope.success_response(service.get_overview(season))


@router.get("/leaderboard", response_model=ApiEnvelope[dict])
def get_records_leaderboard(
    season: int = Query(...), metric: str = Query(...)
) -> ApiEnvelope[dict]:
    return ApiEnvelope.success_response(service.get_leaderboard(season, metric))
