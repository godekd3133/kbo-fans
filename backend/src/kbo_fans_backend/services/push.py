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

    def send_lineup_opened(
        self,
        *,
        game_id: str,
        away_team_id: str,
        away_team_name: str,
        home_team_id: str,
        home_team_name: str,
    ) -> dict[str, Any]:
        messaging = self._get_messaging()
        title = "선발 라인업 공개"
        body = f"{away_team_name} vs {home_team_name} 라인업이 공개됐습니다."

        targets = [
            f"lineup_opened_{away_team_id}",
            f"lineup_opened_{home_team_id}",
            "lineup_opened_ALL",
        ]
        sent = []
        for topic in targets:
            message = messaging.Message(
                notification=messaging.Notification(title=title, body=body),
                data={
                    "type": "lineup_opened",
                    "gameId": game_id,
                    "awayTeamId": away_team_id,
                    "homeTeamId": home_team_id,
                },
                topic=topic,
            )
            message_id = messaging.send(message)
            sent.append({"topic": topic, "messageId": message_id})
        return {"sent": True, "messages": sent}

    def _build_topics(self, payload: PushRegisterRequest) -> list[str]:
        team_key = payload.myTeam or "ALL"
        topics: list[str] = []

        topic_flags = {
            "game_start": payload.notifications.gameStart,
            "scoring": payload.notifications.scoring,
            "homerun": payload.notifications.homerun,
            "reversal": payload.notifications.reversal,
            "game_end": payload.notifications.gameEnd,
            "lineup_opened": payload.notifications.lineupOpened,
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
