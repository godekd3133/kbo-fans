from __future__ import annotations

from pathlib import Path
from typing import Any

from kbo_fans_backend.core.config import get_settings
from kbo_fans_backend.schemas.push import PushTestRequest
from kbo_fans_backend.schemas.push import PushRegisterRequest


class PushService:
    def register(self, payload: PushRegisterRequest) -> dict[str, Any]:
        topics = self._build_topics(payload)
        return {
            "registered": True,
            "subscribedTopics": topics,
        }

    def send_test(self, payload: PushTestRequest) -> dict[str, Any]:
        if not payload.topic and not payload.token:
            raise ValueError("topic or token is required")

        messaging = self._get_messaging()
        notification = messaging.Notification(title=payload.title, body=payload.body)
        if payload.topic:
            message = messaging.Message(
                notification=notification,
                topic=payload.topic,
            )
            response = messaging.send(message)
            return {"sent": True, "target": f"topic:{payload.topic}", "messageId": response}

        message = messaging.Message(
            notification=notification,
            token=payload.token,
        )
        response = messaging.send(message)
        return {"sent": True, "target": "token", "messageId": response}

    def _build_topics(self, payload: PushRegisterRequest) -> list[str]:
        team_key = payload.myTeam or "ALL"
        topics: list[str] = []

        topic_flags = {
            "game_start": payload.notifications.gameStart,
            "scoring": payload.notifications.scoring,
            "homerun": payload.notifications.homerun,
            "reversal": payload.notifications.reversal,
            "game_end": payload.notifications.gameEnd,
        }

        for topic_name, enabled in topic_flags.items():
            if not enabled:
                continue

            if payload.notifications.allGames:
                topics.append(f"{topic_name}_ALL")
            else:
                topics.append(f"{topic_name}_{team_key}")

        if payload.notifications.allGames:
            topics.append("all_games_enabled")

        return topics

    def _get_messaging(self):
        settings = get_settings()
        credential_path = settings.firebase_service_account_path
        if not credential_path:
            raise ValueError("FIREBASE_SERVICE_ACCOUNT_PATH is not configured")

        try:
            import firebase_admin
            from firebase_admin import credentials
            from firebase_admin import messaging
        except ImportError as error:
            raise ValueError("firebase-admin is not installed") from error

        if not firebase_admin._apps:
            options = {}
            if settings.firebase_project_id:
                options["projectId"] = settings.firebase_project_id
            firebase_admin.initialize_app(
                credentials.Certificate(str(Path(credential_path).expanduser())),
                options or None,
            )

        return messaging
