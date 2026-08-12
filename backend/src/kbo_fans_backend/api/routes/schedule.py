from fastapi import APIRouter, Query

from kbo_fans_backend.api.routes.validation import ensure_supported_kbo_month
from kbo_fans_backend.api.runtime_services import schedule_service as service
from kbo_fans_backend.schemas.common import ApiEnvelope

router = APIRouter()


@router.get("/schedule", response_model=ApiEnvelope[dict])
def get_schedule(
    month: str = Query(..., pattern=r"^\d{4}-(0[1-9]|1[0-2])$"),
) -> ApiEnvelope[dict]:
    ensure_supported_kbo_month(month)
    return ApiEnvelope.success_response(service.get_month_schedule(month))
