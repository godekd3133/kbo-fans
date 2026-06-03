from datetime import date as date_type
from typing import Optional

from fastapi import APIRouter, Header, HTTPException, Query

from kbo_fans_backend.api.runtime_services import scoreboard_service
from kbo_fans_backend.core.config import get_settings
from kbo_fans_backend.schemas.common import ApiEnvelope
from kbo_fans_backend.schemas.push import (
    LiveActivityRegisterRequest,
    LiveActivityUnregisterRequest,
    LiveActivityUpdateRequest,
    PushRegisterRequest,
    PushTestRequest,
)
from kbo_fans_backend.services.live_activity_scoreboard import LiveActivityScoreboardSyncService
from kbo_fans_backend.services.push import PushService
from kbo_fans_backend.services.push_diagnostics import PushConfigurationDiagnostics

router = APIRouter(prefix="/push")
service = PushService()
live_activity_sync_service = LiveActivityScoreboardSyncService(
    scoreboard_service=scoreboard_service,
    push_service=service,
)
diagnostics_service = PushConfigurationDiagnostics()


@router.post("/register", response_model=ApiEnvelope[dict])
def register_push(payload: PushRegisterRequest) -> ApiEnvelope[dict]:
    return ApiEnvelope.success_response(service.register(payload))


@router.post("/test", response_model=ApiEnvelope[dict])
def send_test_push(payload: PushTestRequest) -> ApiEnvelope[dict]:
    return ApiEnvelope.success_response(service.send_test(payload))


@router.get("/config-status", response_model=ApiEnvelope[dict])
def get_push_config_status(
    x_kbo_push_sync_secret: Optional[str] = Header(default=None),
) -> ApiEnvelope[dict]:
    _ensure_sync_allowed(x_kbo_push_sync_secret)
    return ApiEnvelope.success_response(diagnostics_service.status())


@router.post("/live-activity/register", response_model=ApiEnvelope[dict])
def register_live_activity(payload: LiveActivityRegisterRequest) -> ApiEnvelope[dict]:
    return ApiEnvelope.success_response(service.register_live_activity(payload))


@router.post("/live-activity/unregister", response_model=ApiEnvelope[dict])
def unregister_live_activity(payload: LiveActivityUnregisterRequest) -> ApiEnvelope[dict]:
    return ApiEnvelope.success_response(service.unregister_live_activity(payload))


@router.post("/live-activity/update", response_model=ApiEnvelope[dict])
def update_live_activity(payload: LiveActivityUpdateRequest) -> ApiEnvelope[dict]:
    return ApiEnvelope.success_response(service.send_live_activity_update(payload))


@router.post("/live-activity/sync-scoreboard", response_model=ApiEnvelope[dict])
def sync_live_activity_scoreboard(
    date: Optional[str] = Query(default=None),
    x_kbo_push_sync_secret: Optional[str] = Header(default=None),
) -> ApiEnvelope[dict]:
    _ensure_sync_allowed(x_kbo_push_sync_secret)
    target_date = date or date_type.today().isoformat()
    return ApiEnvelope.success_response(live_activity_sync_service.sync_date(target_date))


def _ensure_sync_allowed(secret: Optional[str]) -> None:
    expected = get_settings().push_sync_secret
    if expected and secret != expected:
        raise HTTPException(status_code=401, detail="Invalid push sync secret")
