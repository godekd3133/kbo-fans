import secrets
from typing import Optional

from fastapi import APIRouter, Header, HTTPException, Query

from kbo_fans_backend.api.runtime_services import (
    relay_service,
    scoreboard_service,
    standings_service,
)
from kbo_fans_backend.core.config import get_settings
from kbo_fans_backend.scheduler.live_activity_sync import current_kbo_date
from kbo_fans_backend.schemas.common import ApiEnvelope
from kbo_fans_backend.schemas.push import (
    LiveActivityRegisterRequest,
    LiveActivityStartTokenRegisterRequest,
    LiveActivityUnregisterRequest,
    LiveActivityUpdateRequest,
    PushBaseballInfoRequest,
    PushDeviceTestRequest,
    PushReceiptRequest,
    PushRegisterRequest,
    PushTestRequest,
)
from kbo_fans_backend.services.live_activity_scoreboard import LiveActivityScoreboardSyncService
from kbo_fans_backend.services.push import PushService
from kbo_fans_backend.services.push_diagnostics import PushConfigurationDiagnostics
from kbo_fans_backend.services.push_registry import (
    PushRegistryCapacityError,
    PushRegistryCorruptionError,
    PushRegistryOwnershipError,
)

router = APIRouter(prefix="/push")
service = PushService()
live_activity_sync_service = LiveActivityScoreboardSyncService(
    scoreboard_service=scoreboard_service,
    push_service=service,
    relay_service=relay_service,
    standings_service=standings_service,
)
diagnostics_service = PushConfigurationDiagnostics()


@router.post("/register", response_model=ApiEnvelope[dict])
def register_push(payload: PushRegisterRequest) -> ApiEnvelope[dict]:
    try:
        registration = service.register(payload)
    except PushRegistryCapacityError as error:
        raise HTTPException(
            status_code=429,
            detail="push registry capacity reached",
        ) from error
    except PushRegistryOwnershipError as error:
        raise HTTPException(
            status_code=409,
            detail="push registration ownership conflict",
        ) from error
    except PushRegistryCorruptionError as error:
        raise HTTPException(status_code=503, detail="push registry unavailable") from error
    return ApiEnvelope.success_response(registration)


@router.post("/test", response_model=ApiEnvelope[dict])
def send_test_push(
    payload: PushTestRequest,
    x_kbo_push_sync_secret: Optional[str] = Header(default=None),
) -> ApiEnvelope[dict]:
    _ensure_sync_allowed(x_kbo_push_sync_secret, require_configured=True)
    return ApiEnvelope.success_response(service.send_test(payload))


@router.post("/test-device", response_model=ApiEnvelope[dict])
def send_device_test_push(payload: PushDeviceTestRequest) -> ApiEnvelope[dict]:
    try:
        result = service.send_device_test(payload)
    except PushRegistryCapacityError as error:
        raise HTTPException(
            status_code=429,
            detail="push registry capacity reached",
        ) from error
    except PushRegistryCorruptionError as error:
        raise HTTPException(status_code=503, detail="push registry unavailable") from error
    return ApiEnvelope.success_response(result)


@router.post("/receipt", response_model=ApiEnvelope[dict])
def record_push_receipt(payload: PushReceiptRequest) -> ApiEnvelope[dict]:
    try:
        result = service.record_receipt(payload)
    except PushRegistryCapacityError as error:
        raise HTTPException(
            status_code=429,
            detail="push registry capacity reached",
        ) from error
    except PushRegistryCorruptionError as error:
        raise HTTPException(status_code=503, detail="push registry unavailable") from error
    return ApiEnvelope.success_response(result)


@router.post("/baseball-info", response_model=ApiEnvelope[dict])
def send_baseball_info_push(
    payload: PushBaseballInfoRequest,
    x_kbo_push_sync_secret: Optional[str] = Header(default=None),
) -> ApiEnvelope[dict]:
    _ensure_sync_allowed(x_kbo_push_sync_secret, require_configured=True)
    return ApiEnvelope.success_response(
        service.send_baseball_info(
            kind=payload.kind,
            date=payload.date,
            topic=payload.topic,
            token=payload.token,
            team_id=payload.teamId,
            game_id=payload.gameId,
            matchup=payload.matchup,
            start_time=payload.startTime,
            stadium=payload.stadium,
            dry_run=payload.dryRun,
        )
    )


@router.post("/resubscribe-topics", response_model=ApiEnvelope[dict])
def resubscribe_push_topics(
    dry_run: bool = Query(default=False),
    x_kbo_push_sync_secret: Optional[str] = Header(default=None),
) -> ApiEnvelope[dict]:
    _ensure_sync_allowed(x_kbo_push_sync_secret, require_configured=True)
    return ApiEnvelope.success_response(service.resubscribe_registered_topics(dry_run=dry_run))


@router.get("/config-status", response_model=ApiEnvelope[dict])
def get_push_config_status(
    x_kbo_push_sync_secret: Optional[str] = Header(default=None),
) -> ApiEnvelope[dict]:
    _ensure_sync_allowed(x_kbo_push_sync_secret)
    return ApiEnvelope.success_response(diagnostics_service.status())


@router.post("/live-activity/register", response_model=ApiEnvelope[dict])
def register_live_activity(payload: LiveActivityRegisterRequest) -> ApiEnvelope[dict]:
    try:
        registration = service.register_live_activity(payload)
    except PushRegistryCapacityError as error:
        raise HTTPException(
            status_code=429,
            detail="push registry capacity reached",
        ) from error
    except PushRegistryOwnershipError as error:
        raise HTTPException(
            status_code=409,
            detail="push registration ownership conflict",
        ) from error
    except PushRegistryCorruptionError as error:
        raise HTTPException(status_code=503, detail="push registry unavailable") from error
    return ApiEnvelope.success_response(registration)


@router.post("/live-activity/start-token/register", response_model=ApiEnvelope[dict])
def register_live_activity_start_token(
    payload: LiveActivityStartTokenRegisterRequest,
) -> ApiEnvelope[dict]:
    try:
        registration = service.register_live_activity_start_token(payload)
    except PushRegistryCapacityError as error:
        raise HTTPException(
            status_code=429,
            detail="push registry capacity reached",
        ) from error
    except PushRegistryOwnershipError as error:
        raise HTTPException(
            status_code=409,
            detail="push registration ownership conflict",
        ) from error
    except PushRegistryCorruptionError as error:
        raise HTTPException(status_code=503, detail="push registry unavailable") from error
    return ApiEnvelope.success_response(registration)


@router.post("/live-activity/unregister", response_model=ApiEnvelope[dict])
def unregister_live_activity(payload: LiveActivityUnregisterRequest) -> ApiEnvelope[dict]:
    try:
        result = service.unregister_live_activity(payload)
    except PushRegistryCorruptionError as error:
        raise HTTPException(status_code=503, detail="push registry unavailable") from error
    return ApiEnvelope.success_response(result)


@router.post("/live-activity/update", response_model=ApiEnvelope[dict])
def update_live_activity(
    payload: LiveActivityUpdateRequest,
    x_kbo_push_sync_secret: Optional[str] = Header(default=None),
) -> ApiEnvelope[dict]:
    _ensure_sync_allowed(x_kbo_push_sync_secret, require_configured=True)
    return ApiEnvelope.success_response(service.send_live_activity_update(payload))


@router.post("/live-activity/sync-scoreboard", response_model=ApiEnvelope[dict])
def sync_live_activity_scoreboard(
    date: Optional[str] = Query(default=None),
    x_kbo_push_sync_secret: Optional[str] = Header(default=None),
) -> ApiEnvelope[dict]:
    _ensure_sync_allowed(x_kbo_push_sync_secret, require_configured=True)
    target_date = date or current_kbo_date()
    return ApiEnvelope.success_response(live_activity_sync_service.sync_date(target_date))


def _ensure_sync_allowed(
    secret: Optional[str],
    *,
    require_configured: bool = False,
) -> None:
    expected = get_settings().push_sync_secret
    if not expected and require_configured:
        raise HTTPException(status_code=503, detail="Push sync secret is not configured")
    if expected and (
        secret is None
        or not secrets.compare_digest(secret.encode("utf-8"), expected.encode("utf-8"))
    ):
        raise HTTPException(status_code=401, detail="Invalid push sync secret")
