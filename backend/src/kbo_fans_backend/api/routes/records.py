from fastapi import APIRouter, Query

from kbo_fans_backend.schemas.common import ApiEnvelope
from kbo_fans_backend.services.records_overview import RecordsOverviewService

router = APIRouter(prefix="/records")
service = RecordsOverviewService()


@router.get("/overview", response_model=ApiEnvelope[dict])
def get_records_overview(season: int = Query(...)) -> ApiEnvelope[dict]:
    return ApiEnvelope.success_response(service.get_overview(season))
