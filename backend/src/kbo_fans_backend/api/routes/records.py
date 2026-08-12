from fastapi import APIRouter, Query

from kbo_fans_backend.api.runtime_services import records_overview_service as service
from kbo_fans_backend.schemas.common import ApiEnvelope

router = APIRouter(prefix="/records")


@router.get("/overview", response_model=ApiEnvelope[dict])
def get_records_overview(season: int = Query(..., ge=1900, le=2100)) -> ApiEnvelope[dict]:
    return ApiEnvelope.success_response(service.get_overview(season))


@router.get("/leaderboard", response_model=ApiEnvelope[dict])
def get_records_leaderboard(
    season: int = Query(..., ge=1900, le=2100),
    metric: str = Query(..., min_length=1, max_length=32, pattern=r"^[A-Za-z][A-Za-z0-9_-]*$"),
) -> ApiEnvelope[dict]:
    return ApiEnvelope.success_response(service.get_leaderboard(season, metric))
