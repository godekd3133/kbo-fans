from fastapi import APIRouter, Query

from kbo_fans_backend.schemas.common import ApiEnvelope
from kbo_fans_backend.services.schedule import ScheduleService

router = APIRouter()
service = ScheduleService()


@router.get("/schedule", response_model=ApiEnvelope[dict])
def get_schedule(month: str = Query(...)) -> ApiEnvelope[dict]:
    return ApiEnvelope.success_response(service.get_month_schedule(month))
