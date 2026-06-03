from __future__ import annotations

import json
from pathlib import Path
from typing import Any, Optional, Union

from kbo_fans_backend.core.config import get_settings
from kbo_fans_backend.schemas.push import (
    LiveActivityRegisterRequest,
    LiveActivityUnregisterRequest,
    LiveActivityUpdateRequest,
    PushRegisterRequest,
    PushTestRequest,
)
from kbo_fans_backend.services.apns_live_activity import ApnsLiveActivitySender
from kbo_fans_backend.services.push_registry import PushRegistry


class PushService:
    def __init__(
        self,
        registry: Optional[PushRegistry] = None,
        live_activity_sender: Optional[ApnsLiveActivitySender] = None,
    ) -> None:
        self.registry = registry or PushRegistry()
        self.live_activity_sender = live_activity_sender or ApnsLiveActivitySender()

    def register(self, payload: PushRegisterRequest) -> dict[str, Any]:
        topics = self._build_topics(payload)
        self.registry.save_device_registration(payload, topics)
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

    def register_live_activity(self, payload: LiveActivityRegisterRequest) -> dict[str, Any]:
        registration = self.registry.save_live_activity(payload)
        return {
            "registered": True,
            "gameId": registration["gameId"],
            "activityId": registration.get("activityId"),
        }

    def unregister_live_activity(self, payload: LiveActivityUnregisterRequest) -> dict[str, Any]:
        removed = self.registry.remove_live_activity(payload)
        return {
            "registered": False,
            "gameId": payload.gameId,
            "removed": removed,
        }

    def send_live_activity_update(self, payload: LiveActivityUpdateRequest) -> dict[str, Any]:
        tokens = (
            [payload.activityPushToken]
            if payload.activityPushToken
            else self.registry.live_activity_tokens_for_game(payload.gameId)
        )
        if not tokens:
            return {"sent": False, "gameId": payload.gameId, "messages": []}

        messages = []
        for token in tokens:
            try:
                response = self.live_activity_sender.send(
                    activity_push_token=token,
                    game_id=payload.gameId,
                    state=payload.state,
                    event=payload.event,
                    stale_date=payload.staleDate,
                    dismissal_date=payload.dismissalDate,
                    relevance_score=payload.relevanceScore,
                )
                messages.append({"activityPushToken": token, **response})
            except Exception as error:
                messages.append(
                    {
                        "activityPushToken": token,
                        "sent": False,
                        "error": str(error),
                    }
                )

        return {
            "sent": any(message.get("sent") for message in messages),
            "gameId": payload.gameId,
            "messages": messages,
        }

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

    def send_game_moment(
        self,
        *,
        moment: str,
        game_id: str,
        away_team_id: str,
        away_team_name: str,
        home_team_id: str,
        home_team_name: str,
        away_score: int,
        home_score: int,
        inning: str,
    ) -> dict[str, Any]:
        messaging = self._get_messaging()
        title, body = _game_moment_copy(
            moment=moment,
            away_team_name=away_team_name,
            home_team_name=home_team_name,
            away_score=away_score,
            home_score=home_score,
            inning=inning,
        )
        targets = [
            f"{moment}_{away_team_id}",
            f"{moment}_{home_team_id}",
            f"{moment}_ALL",
        ]
        sent = []
        for topic in targets:
            message = messaging.Message(
                notification=messaging.Notification(title=title, body=body),
                data={
                    "type": moment,
                    "gameId": game_id,
                    "awayTeamId": away_team_id,
                    "homeTeamId": home_team_id,
                    "awayScore": str(away_score),
                    "homeScore": str(home_score),
                    "inning": inning,
                },
                topic=topic,
            )
            message_id = messaging.send(message)
            sent.append({"topic": topic, "messageId": message_id})
        return {"sent": True, "moment": moment, "messages": sent}

    def _build_topics(self, payload: PushRegisterRequest) -> list[str]:
        has_my_team = payload.myTeam is not None and payload.myTeam != ""
        topics: list[str] = []

        topic_flags = {
            "game_start": payload.notifications.gameStart,
            "scoring": payload.notifications.scoring,
            "homerun": payload.notifications.homerun,
            "reversal": payload.notifications.reversal,
            "game_end": payload.notifications.gameEnd,
            "lineup_opened": payload.notifications.lineupOpened,
            "inning_change": payload.notifications.inningChange,
        }

        for topic_name, enabled in topic_flags.items():
            if not enabled:
                continue

            if payload.notifications.allGames:
                topics.append(f"{topic_name}_ALL")
                continue

            if has_my_team:
                topics.append(f"{topic_name}_{payload.myTeam}")

        if payload.notifications.allGames:
            topics.append("all_games_enabled")

        return topics

    def _get_messaging(self):
        settings = get_settings()
        certificate_source = _firebase_certificate_source(
            service_account_json=settings.firebase_service_account_json,
            service_account_path=settings.firebase_service_account_path,
        )

        try:
            import firebase_admin
            from firebase_admin import credentials, messaging
        except ImportError as error:
            raise ValueError("firebase-admin is not installed") from error

        if not firebase_admin._apps:
            options = {}
            if settings.firebase_project_id:
                options["projectId"] = settings.firebase_project_id
            firebase_admin.initialize_app(
                credentials.Certificate(certificate_source),
                options or None,
            )

        return messaging


def _game_moment_copy(
    *,
    moment: str,
    away_team_name: str,
    home_team_name: str,
    away_score: int,
    home_score: int,
    inning: str,
) -> tuple[str, str]:
    score = f"{away_score}:{home_score}"
    matchup = f"{away_team_name} vs {home_team_name}"
    if moment == "game_start":
        return "경기 시작", f"{matchup} 경기가 시작됐습니다."
    if moment == "scoring":
        return "득점 발생", f"{inning} {matchup} 현재 스코어 {score}"
    if moment == "reversal":
        return "역전", f"{inning} {matchup} 역전 상황입니다. 현재 {score}"
    if moment == "game_end":
        return "경기 종료", f"{matchup} 최종 스코어 {score}"
    if moment == "inning_change":
        return "이닝 변경", f"{matchup} {inning} 진입, 현재 {score}"
    return "경기 알림", f"{matchup} {inning} 현재 {score}"


def _firebase_certificate_source(
    *,
    service_account_json: str,
    service_account_path: str,
) -> Union[str, dict[str, Any]]:
    if service_account_json:
        try:
            payload = json.loads(service_account_json)
        except json.JSONDecodeError as error:
            raise ValueError("FIREBASE_SERVICE_ACCOUNT_JSON is invalid JSON") from error
        if not isinstance(payload, dict):
            raise ValueError("FIREBASE_SERVICE_ACCOUNT_JSON must be a JSON object")
        return payload

    if service_account_path:
        return str(Path(service_account_path).expanduser())

    raise ValueError("FIREBASE_SERVICE_ACCOUNT_JSON or FIREBASE_SERVICE_ACCOUNT_PATH is required")
