from fastapi import APIRouter

from kbo_fans_backend.schemas.common import ApiEnvelope
from kbo_fans_backend.schemas.push import PushRegisterRequest
from kbo_fans_backend.schemas.push import PushTestRequest
from kbo_fans_backend.services.push import PushService

router = APIRouter(prefix="/push")
service = PushService()


@router.post("/register", response_model=ApiEnvelope[dict])
def register_push(payload: PushRegisterRequest) -> ApiEnvelope[dict]:
    return ApiEnvelope.success_response(service.register(payload))


@router.post("/test", response_model=ApiEnvelope[dict])
def send_test_push(payload: PushTestRequest) -> ApiEnvelope[dict]:
    return ApiEnvelope.success_response(service.send_test(payload))
