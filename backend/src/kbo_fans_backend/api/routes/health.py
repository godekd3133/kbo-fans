from fastapi import APIRouter

from kbo_fans_backend.schemas.common import ApiEnvelope

router = APIRouter()


@router.get("/health", response_model=ApiEnvelope[dict])
def healthcheck() -> ApiEnvelope[dict]:
    return ApiEnvelope.success_response({"status": "ok"})
