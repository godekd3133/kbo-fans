from fastapi import APIRouter, Query

from kbo_fans_backend.api.runtime_services import schedule_service as service
from kbo_fans_backend.schemas.common import ApiEnvelope

router = APIRouter()


@router.get("/schedule", response_model=ApiEnvelope[dict])
def get_schedule(month: str = Query(...)) -> ApiEnvelope[dict]:
    return ApiEnvelope.success_response(service.get_month_schedule(month))
