from __future__ import annotations

import time
import uuid
from pathlib import Path
from typing import Any, Optional

from kbo_fans_backend.core.config import Settings, get_settings
from kbo_fans_backend.schemas.push import LiveActivityContentState


class ApnsLiveActivitySender:
    def __init__(self, settings: Optional[Settings] = None) -> None:
        self.settings = settings or get_settings()

    def send(
        self,
        *,
        activity_push_token: str,
        game_id: str,
        state: LiveActivityContentState,
        event: str = "update",
        stale_date: Optional[int] = None,
        dismissal_date: Optional[int] = None,
        relevance_score: Optional[float] = None,
    ) -> dict[str, Any]:
        if event not in {"update", "end"}:
            raise ValueError("event must be update or end")

        payload = self._build_payload(
            state=state,
            event=event,
            stale_date=stale_date,
            dismissal_date=dismissal_date,
            relevance_score=relevance_score,
        )
        headers = self._headers(game_id=game_id)
        host = (
            "api.sandbox.push.apple.com" if self.settings.apns_use_sandbox else "api.push.apple.com"
        )
        url = f"https://{host}/3/device/{activity_push_token}"

        try:
            import httpx
        except ImportError as error:
            raise ValueError("httpx is not installed") from error

        with httpx.Client(http2=True, timeout=10) as client:
            response = client.post(url, json=payload, headers=headers)
        if response.status_code >= 400:
            raise ValueError(
                f"APNs live activity send failed: {response.status_code} {response.text}"
            )

        return {
            "sent": True,
            "apnsId": response.headers.get("apns-id"),
            "statusCode": response.status_code,
        }

    def send_start(
        self,
        *,
        push_to_start_token: str,
        game_id: str,
        state: LiveActivityContentState,
        alert_title: str,
        alert_body: str,
        stale_date: Optional[int] = None,
        relevance_score: Optional[float] = None,
    ) -> dict[str, Any]:
        payload = self._build_start_payload(
            game_id=game_id,
            state=state,
            alert_title=alert_title,
            alert_body=alert_body,
            stale_date=stale_date,
            relevance_score=relevance_score,
        )
        headers = self._headers(game_id=game_id)
        host = (
            "api.sandbox.push.apple.com" if self.settings.apns_use_sandbox else "api.push.apple.com"
        )
        url = f"https://{host}/3/device/{push_to_start_token}"

        try:
            import httpx
        except ImportError as error:
            raise ValueError("httpx is not installed") from error

        with httpx.Client(http2=True, timeout=10) as client:
            response = client.post(url, json=payload, headers=headers)
        if response.status_code >= 400:
            raise ValueError(
                f"APNs live activity start failed: {response.status_code} {response.text}"
            )

        return {
            "sent": True,
            "apnsId": response.headers.get("apns-id"),
            "statusCode": response.status_code,
        }

    def _headers(self, *, game_id: str) -> dict[str, str]:
        return {
            "authorization": f"bearer {self._provider_token()}",
            "apns-topic": f"{self.settings.apns_bundle_id}.push-type.liveactivity",
            "apns-push-type": "liveactivity",
            "apns-priority": "10",
            "apns-expiration": str(int(time.time()) + 60),
            "apns-collapse-id": game_id[:64],
            "apns-id": str(uuid.uuid4()),
        }

    def _provider_token(self) -> str:
        if not self.settings.apns_key_id:
            raise ValueError("APNS_KEY_ID is not configured")
        if not self.settings.apns_team_id:
            raise ValueError("APNS_TEAM_ID is not configured")

        if self.settings.apns_auth_key_p8:
            private_key = self.settings.apns_auth_key_p8
        elif self.settings.apns_auth_key_path:
            key_path = Path(self.settings.apns_auth_key_path).expanduser()
            private_key = key_path.read_text(encoding="utf-8")
        else:
            raise ValueError("APNS_AUTH_KEY_P8 or APNS_AUTH_KEY_PATH is required")

        try:
            import jwt
        except ImportError as error:
            raise ValueError("PyJWT is not installed") from error

        return jwt.encode(
            {"iss": self.settings.apns_team_id, "iat": int(time.time())},
            private_key,
            algorithm="ES256",
            headers={"kid": self.settings.apns_key_id},
        )

    def _build_payload(
        self,
        *,
        state: LiveActivityContentState,
        event: str,
        stale_date: Optional[int],
        dismissal_date: Optional[int],
        relevance_score: Optional[float],
    ) -> dict[str, Any]:
        aps: dict[str, Any] = {
            "timestamp": int(time.time()),
            "event": event,
            "content-state": _model_to_dict(state),
        }
        if stale_date is not None:
            aps["stale-date"] = stale_date
        if dismissal_date is not None:
            aps["dismissal-date"] = dismissal_date
        if relevance_score is not None:
            aps["relevance-score"] = relevance_score
        return {"aps": aps}

    def _build_start_payload(
        self,
        *,
        game_id: str,
        state: LiveActivityContentState,
        alert_title: str,
        alert_body: str,
        stale_date: Optional[int],
        relevance_score: Optional[float],
    ) -> dict[str, Any]:
        aps: dict[str, Any] = {
            "timestamp": int(time.time()),
            "event": "start",
            "content-state": _model_to_dict(state),
            "attributes-type": "KboFansScoreAttributes",
            "attributes": {"gameId": game_id},
            "alert": {"title": alert_title, "body": alert_body},
            "input-push-token": 1,
        }
        if stale_date is not None:
            aps["stale-date"] = stale_date
        if relevance_score is not None:
            aps["relevance-score"] = relevance_score
        return {"aps": aps}


def _model_to_dict(model: Any) -> dict[str, Any]:
    if hasattr(model, "model_dump"):
        return model.model_dump()
    return model.dict()
