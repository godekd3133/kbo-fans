from __future__ import annotations

import json
from collections import defaultdict
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
        registration = self.registry.save_device_registration(payload, topics)
        return {
            "registered": True,
            "subscribedTopics": topics,
            "followedGameIds": registration.get("followedGameIds", []),
        }

    def resubscribe_registered_topics(self, *, dry_run: bool = False) -> dict[str, Any]:
        registrations = self.registry.device_registrations()
        parsed: list[tuple[PushRegisterRequest, list[str]]] = []
        subscribe_groups: dict[str, list[str]] = defaultdict(list)
        unsubscribe_groups: dict[str, list[str]] = defaultdict(list)
        skipped = []

        for registration in registrations:
            try:
                payload = _registration_to_payload(registration)
            except ValueError as error:
                skipped.append(
                    {
                        "deviceToken": str(registration.get("deviceToken") or ""),
                        "reason": str(error),
                    }
                )
                continue

            desired_topics = self._build_topics(payload)
            current_topics = _stored_topics(registration)
            desired_topic_set = set(desired_topics)

            parsed.append((payload, desired_topics))
            for topic in desired_topics:
                subscribe_groups[topic].append(payload.deviceToken)
            for topic in sorted(current_topics.difference(desired_topic_set)):
                unsubscribe_groups[topic].append(payload.deviceToken)

        subscription_results = _planned_topic_results(subscribe_groups)
        unsubscription_results = _planned_topic_results(unsubscribe_groups)
        if not dry_run and (subscribe_groups or unsubscribe_groups):
            messaging = self._get_messaging()
            subscription_results = _apply_topic_operation(
                messaging.subscribe_to_topic,
                subscribe_groups,
            )
            unsubscription_results = _apply_topic_operation(
                messaging.unsubscribe_from_topic,
                unsubscribe_groups,
            )

        if not dry_run:
            for payload, topics in parsed:
                self.registry.save_device_registration(payload, topics)

        return {
            "dryRun": dry_run,
            "resubscribed": not dry_run,
            "registeredDevices": len(registrations),
            "eligibleDevices": len(parsed),
            "skippedDevices": skipped,
            "subscriptionsAttempted": sum(
                len(tokens) for tokens in subscribe_groups.values()
            ),
            "unsubscriptionsAttempted": sum(
                len(tokens) for tokens in unsubscribe_groups.values()
            ),
            "subscriptionResults": subscription_results,
            "unsubscriptionResults": unsubscription_results,
        }

    def send_test(self, payload: PushTestRequest) -> dict[str, Any]:
        if not payload.topic and not payload.token:
            raise ValueError("topic or token is required")

        messaging = self._get_messaging()
        notification = messaging.Notification(title=payload.title, body=payload.body)
        visible_options = _visible_push_options(messaging)
        if payload.topic:
            message = messaging.Message(
                notification=notification,
                topic=payload.topic,
                **visible_options,
            )
            response = messaging.send(message)
            return {"sent": True, "target": f"topic:{payload.topic}", "messageId": response}

        message = messaging.Message(
            notification=notification,
            token=payload.token,
            **visible_options,
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
        visible_options = _visible_push_options(messaging)
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
                **visible_options,
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
        batter_name: str = "",
        pitcher_name: str = "",
        situation_text: str = "",
        play_text: str = "",
        start_time: str = "",
        stadium: str = "",
    ) -> dict[str, Any]:
        messaging = self._get_messaging()
        title, body = _game_moment_copy(
            moment=moment,
            away_team_name=away_team_name,
            home_team_name=home_team_name,
            away_score=away_score,
            home_score=home_score,
            inning=inning,
            batter_name=batter_name,
            pitcher_name=pitcher_name,
            situation_text=situation_text,
            play_text=play_text,
            start_time=start_time,
            stadium=stadium,
        )
        targets = [
            f"{moment}_{away_team_id}",
            f"{moment}_{home_team_id}",
            f"{moment}_ALL",
        ]
        visible_options = _visible_push_options(messaging)
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
                    "batterName": batter_name,
                    "pitcherName": pitcher_name,
                    "situationText": situation_text,
                    "playText": play_text,
                    "startTime": start_time,
                    "stadium": stadium,
                },
                topic=topic,
                **visible_options,
            )
            message_id = messaging.send(message)
            sent.append({"topic": topic, "messageId": message_id})
        return {"sent": True, "moment": moment, "messages": sent}

    def _build_topics(self, payload: PushRegisterRequest) -> list[str]:
        has_my_team = payload.myTeam is not None and payload.myTeam != ""
        topics: list[str] = []
        delivery_modes = payload.notifications.deliveryModes

        topic_flags = {
            "game_start": _sends_immediately(
                payload.notifications.gameStart,
                delivery_modes.gameStart if delivery_modes else None,
            ),
            "game_start_soon": _sends_immediately(
                payload.notifications.gameStart,
                delivery_modes.gameStart if delivery_modes else None,
            ),
            "scoring": _sends_immediately(
                payload.notifications.scoring,
                delivery_modes.scoring if delivery_modes else None,
            ),
            "hit": _sends_immediately(
                payload.notifications.hit,
                delivery_modes.hit if delivery_modes else None,
            ),
            "homerun": _sends_immediately(
                payload.notifications.homerun,
                delivery_modes.homerun if delivery_modes else None,
            ),
            "reversal": _sends_immediately(
                payload.notifications.reversal,
                delivery_modes.reversal if delivery_modes else None,
            ),
            "game_end": _sends_immediately(
                payload.notifications.gameEnd,
                delivery_modes.gameEnd if delivery_modes else None,
            ),
            "lineup_opened": _sends_immediately(
                payload.notifications.lineupOpened,
                delivery_modes.lineupOpened if delivery_modes else None,
            ),
            "inning_change": _sends_immediately(
                payload.notifications.inningChange,
                delivery_modes.inningChange if delivery_modes else None,
            ),
            "at_bat": _sends_immediately(
                payload.notifications.atBat,
                delivery_modes.atBat if delivery_modes else None,
            ),
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
    batter_name: str = "",
    pitcher_name: str = "",
    situation_text: str = "",
    play_text: str = "",
    start_time: str = "",
    stadium: str = "",
) -> tuple[str, str]:
    score = f"{away_score}:{home_score}"
    matchup = f"{away_team_name} vs {home_team_name}"
    start_detail = " · ".join(
        part for part in [start_time.strip(), stadium.strip()] if part
    )
    if moment == "game_start":
        return "경기 시작", f"{matchup} 경기가 시작됐습니다."
    if moment == "game_start_soon":
        suffix = f" {start_detail}" if start_detail else ""
        return "경기 곧 시작", f"{matchup} 경기가 곧 시작됩니다.{suffix}"
    if moment == "scoring":
        return "득점 발생", f"{inning} {matchup} 현재 스코어 {score}"
    if moment == "hit":
        actor = f"{batter_name} " if batter_name else ""
        situation = f" · {situation_text}" if situation_text else ""
        if play_text:
            return "안타", f"{inning} {play_text}{situation}"
        return "안타", f"{inning} {actor}안타{situation}"
    if moment == "homerun":
        return "홈런", f"{inning} {matchup} 홈런 발생, 현재 {score}"
    if moment == "reversal":
        return "역전", f"{inning} {matchup} 역전 상황입니다. 현재 {score}"
    if moment == "game_end":
        return "경기 종료", f"{matchup} 최종 스코어 {score}"
    if moment == "inning_change":
        return "이닝 변경", f"{matchup} {inning} 진입, 현재 {score}"
    if moment == "at_bat":
        if batter_name and pitcher_name:
            return "타석 알림", f"{inning} {batter_name} 타석 · 투수 {pitcher_name}"
        if batter_name:
            return "타석 알림", f"{inning} {batter_name} 타석"
        return "타석 알림", f"{matchup} {inning} 현재 {score}"
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


def _visible_push_options(messaging) -> dict[str, Any]:
    options: dict[str, Any] = {}

    if all(hasattr(messaging, name) for name in ("APNSConfig", "APNSPayload", "Aps")):
        options["apns"] = messaging.APNSConfig(
            headers={"apns-priority": "10"},
            payload=messaging.APNSPayload(
                aps=messaging.Aps(sound="default"),
            ),
        )

    if all(
        hasattr(messaging, name) for name in ("AndroidConfig", "AndroidNotification")
    ):
        options["android"] = messaging.AndroidConfig(
            priority="high",
            notification=messaging.AndroidNotification(sound="default"),
        )

    return options


def _sends_immediately(enabled: bool, delivery: Optional[str]) -> bool:
    if not enabled:
        return False
    if delivery is None:
        return True
    return delivery == "immediate"


def _registration_to_payload(registration: dict[str, Any]) -> PushRegisterRequest:
    notifications = registration.get("notifications")
    if not isinstance(notifications, dict):
        raise ValueError("missing notifications")

    try:
        return PushRegisterRequest(
            deviceToken=str(registration["deviceToken"]),
            platform=str(registration.get("platform") or "unknown"),
            myTeam=registration.get("myTeam"),
            notifications=notifications,
            followedGameIds=_stored_followed_game_ids(registration),
        )
    except Exception as error:
        raise ValueError(f"invalid registration: {error}") from error


def _stored_topics(registration: dict[str, Any]) -> set[str]:
    topics = registration.get("topics")
    if not isinstance(topics, list):
        return set()
    return {str(topic) for topic in topics if topic}


def _stored_followed_game_ids(registration: dict[str, Any]) -> list[str]:
    followed = registration.get("followedGameIds")
    if not isinstance(followed, list):
        return []

    cleaned = []
    seen = set()
    for game_id in followed:
        text = str(game_id).strip()
        if not text or text in seen:
            continue
        seen.add(text)
        cleaned.append(text)
    return cleaned


def _planned_topic_results(groups: dict[str, list[str]]) -> list[dict[str, Any]]:
    return [
        {
            "topic": topic,
            "requestedCount": len(tokens),
            "successCount": 0,
            "failureCount": 0,
            "dryRun": True,
            "errors": [],
        }
        for topic, tokens in sorted(groups.items())
    ]


def _apply_topic_operation(operation, groups: dict[str, list[str]]) -> list[dict[str, Any]]:
    results = []
    for topic, tokens in sorted(groups.items()):
        for batch in _topic_batches(tokens):
            response = operation(batch, topic)
            results.append(
                {
                    "topic": topic,
                    "requestedCount": len(batch),
                    "successCount": getattr(response, "success_count", 0),
                    "failureCount": getattr(response, "failure_count", 0),
                    "dryRun": False,
                    "errors": _topic_response_errors(response),
                }
            )
    return results


def _topic_batches(tokens: list[str]) -> list[list[str]]:
    return [tokens[index : index + 1000] for index in range(0, len(tokens), 1000)]


def _topic_response_errors(response) -> list[dict[str, Any]]:
    errors = []
    for error in getattr(response, "errors", []) or []:
        errors.append(
            {
                "index": getattr(error, "index", None),
                "reason": str(getattr(error, "reason", error)),
            }
        )
    return errors
