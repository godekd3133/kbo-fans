from typing import Optional

from fastapi import APIRouter, Header, HTTPException, Query

from kbo_fans_backend.api.runtime_services import relay_service, scoreboard_service
from kbo_fans_backend.core.config import get_settings
from kbo_fans_backend.scheduler.live_activity_sync import current_kbo_date
from kbo_fans_backend.schemas.common import ApiEnvelope
from kbo_fans_backend.schemas.push import (
    LiveActivityRegisterRequest,
    LiveActivityUnregisterRequest,
    LiveActivityUpdateRequest,
    PushBaseballInfoRequest,
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
    relay_service=relay_service,
)
diagnostics_service = PushConfigurationDiagnostics()


@router.post("/register", response_model=ApiEnvelope[dict])
def register_push(payload: PushRegisterRequest) -> ApiEnvelope[dict]:
    return ApiEnvelope.success_response(service.register(payload))


@router.post("/test", response_model=ApiEnvelope[dict])
def send_test_push(
    payload: PushTestRequest,
    x_kbo_push_sync_secret: Optional[str] = Header(default=None),
) -> ApiEnvelope[dict]:
    _ensure_sync_allowed(x_kbo_push_sync_secret)
    return ApiEnvelope.success_response(service.send_test(payload))


@router.post("/baseball-info", response_model=ApiEnvelope[dict])
def send_baseball_info_push(
    payload: PushBaseballInfoRequest,
    x_kbo_push_sync_secret: Optional[str] = Header(default=None),
) -> ApiEnvelope[dict]:
    _ensure_sync_allowed(x_kbo_push_sync_secret)
    return ApiEnvelope.success_response(
        service.send_baseball_info(
            kind=payload.kind,
            date=payload.date,
            topic=payload.topic,
            token=payload.token,
            team_id=payload.teamId,
            dry_run=payload.dryRun,
        )
    )


@router.post("/resubscribe-topics", response_model=ApiEnvelope[dict])
def resubscribe_push_topics(
    dry_run: bool = Query(default=False),
    x_kbo_push_sync_secret: Optional[str] = Header(default=None),
) -> ApiEnvelope[dict]:
    _ensure_sync_allowed(x_kbo_push_sync_secret)
    return ApiEnvelope.success_response(
        service.resubscribe_registered_topics(dry_run=dry_run)
    )


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
    target_date = date or current_kbo_date()
    return ApiEnvelope.success_response(live_activity_sync_service.sync_date(target_date))


def _ensure_sync_allowed(secret: Optional[str]) -> None:
    expected = get_settings().push_sync_secret
    if expected and secret != expected:
        raise HTTPException(status_code=401, detail="Invalid push sync secret")
