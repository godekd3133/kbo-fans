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
    PushDeviceTestRequest,
    PushReceiptRequest,
    PushRegisterRequest,
    PushTestRequest,
)
from kbo_fans_backend.services.apns_live_activity import ApnsLiveActivitySender
from kbo_fans_backend.services.push_registry import PushRegistry

KBO_TEAM_IDS = ("LG", "KT", "SK", "SS", "NC", "HH", "LT", "HT", "OB", "WO")
KBO_TEAM_NAMES = {
    "LG": "LG 트윈스",
    "KT": "KT 위즈",
    "SK": "SSG 랜더스",
    "SS": "삼성 라이온즈",
    "NC": "NC 다이노스",
    "HH": "한화 이글스",
    "LT": "롯데 자이언츠",
    "HT": "KIA 타이거즈",
    "OB": "두산 베어스",
    "WO": "키움 히어로즈",
}
ANDROID_REMOTE_PUSH_CHANNEL_ID = "remote_push_foreground"
GAME_MOMENT_TOPIC_NAMES = {
    "game_start",
    "game_start_soon",
    "scoring",
    "hit",
    "homerun",
    "reversal",
    "game_end",
    "lineup_opened",
    "inning_change",
    "at_bat",
}


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
                self.registry.save_device_topics(payload, topics)

        return {
            "dryRun": dry_run,
            "resubscribed": not dry_run,
            "registeredDevices": len(registrations),
            "eligibleDevices": len(parsed),
            "skippedDevices": skipped,
            "subscriptionsAttempted": sum(len(tokens) for tokens in subscribe_groups.values()),
            "unsubscriptionsAttempted": sum(len(tokens) for tokens in unsubscribe_groups.values()),
            "subscriptionResults": subscription_results,
            "unsubscriptionResults": unsubscription_results,
        }

    def send_test(self, payload: PushTestRequest) -> dict[str, Any]:
        if not payload.topic and not payload.token:
            raise ValueError("topic or token is required")

        messaging = self._get_messaging()
        notification = messaging.Notification(title=payload.title, body=payload.body)
        visible_options = _visible_push_options(
            messaging,
            title=payload.title,
            body=payload.body,
        )
        if payload.topic:
            message_kwargs = {
                "notification": notification,
                "topic": payload.topic,
                **visible_options,
            }
            test_data = _test_push_data_for_topic(payload.topic)
            if test_data:
                message_kwargs["data"] = test_data
            message = messaging.Message(**message_kwargs)
            response = messaging.send(message)
            return {"sent": True, "target": f"topic:{payload.topic}", "messageId": response}

        message = messaging.Message(
            notification=notification,
            token=payload.token,
            **visible_options,
        )
        response = messaging.send(message)
        return {"sent": True, "target": "token", "messageId": response}

    def send_device_test(self, payload: PushDeviceTestRequest) -> dict[str, Any]:
        device_token = payload.deviceToken.strip()
        if not device_token or not self.registry.has_device_token(device_token):
            return {
                "sent": False,
                "registered": False,
                "reason": "device token is not registered",
            }

        title = "KBO Fans 원격 푸시 테스트"
        body = "이 기기로 백엔드 원격 푸시가 도착했습니다."
        messaging = self._get_messaging()
        visible_options = _visible_push_options(messaging, title=title, body=body)
        message = messaging.Message(
            notification=messaging.Notification(title=title, body=body),
            data={
                "type": "test_push",
                "route": "/diagnostics",
            },
            token=device_token,
            **visible_options,
        )
        try:
            response = messaging.send(message)
        except Exception as error:
            return {
                "sent": False,
                "registered": True,
                "reason": _push_send_error_reason(error),
                "errorType": type(error).__name__,
                "debugReason": str(error).strip(),
            }
        return {
            "sent": True,
            "registered": True,
            "target": "token",
            "messageId": response,
        }

    def record_receipt(self, payload: PushReceiptRequest) -> dict[str, Any]:
        receipt = self.registry.record_push_receipt(payload)
        if receipt is None:
            return {
                "recorded": False,
                "registered": False,
                "reason": "device token is not registered",
            }
        return {
            "recorded": True,
            "registered": True,
            "messageId": receipt.get("messageId", ""),
            "recordedAt": receipt.get("recordedAt", ""),
        }

    def send_baseball_info(
        self,
        *,
        kind: str = "weekly_check",
        date: str = "",
        topic: Optional[str] = None,
        token: Optional[str] = None,
        team_id: Optional[str] = None,
        dry_run: bool = False,
    ) -> dict[str, Any]:
        if token and topic:
            raise ValueError("only one of token or topic is allowed")

        title, body = _baseball_info_copy(kind=kind, team_id=team_id)
        data = {
            "type": "baseball_info",
            "kind": kind,
            "date": date,
            "teamId": team_id or "",
            "route": "/home",
        }
        if dry_run:
            return {
                "sent": False,
                "dryRun": True,
                "kind": kind,
                "notification": {"title": title, "body": body},
                "data": data,
                "targets": _baseball_info_target_preview(
                    topic=topic,
                    token=token,
                    team_id=team_id,
                ),
                "messages": [],
            }

        messaging = self._get_messaging()
        notification = messaging.Notification(title=title, body=body)
        visible_options = _visible_push_options(messaging, title=title, body=body)

        if token:
            message = messaging.Message(
                notification=notification,
                data=data,
                token=token,
                **visible_options,
            )
            response = messaging.send(message)
            return {
                "sent": True,
                "kind": kind,
                "target": "token",
                "messages": [{"target": "token", "messageId": response}],
            }

        targets = _baseball_info_topics(topic=topic, team_id=team_id)
        sent = []
        for target_topic in targets:
            message = messaging.Message(
                notification=notification,
                data=data,
                topic=target_topic,
                **visible_options,
            )
            message_id = messaging.send(message)
            sent.append({"topic": target_topic, "messageId": message_id})
        return {"sent": True, "kind": kind, "messages": sent}

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
        if game_id:
            targets.append(_game_topic("lineup_opened", game_id))
        visible_options = _visible_push_options(messaging, title=title, body=body)
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
        if game_id:
            targets.append(_game_topic(moment, game_id))
        visible_options = _visible_push_options(messaging, title=title, body=body)
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
        my_team = str(payload.myTeam or "").strip()
        has_my_team = my_team != ""
        followed_game_ids = _clean_followed_game_ids(payload.followedGameIds)
        topics: list[str] = []
        delivery_modes = payload.notifications.deliveryModes

        topic_flags = {
            "game_start": (
                payload.notifications.gameStart,
                delivery_modes.gameStart if delivery_modes else None,
            ),
            "game_start_soon": (
                payload.notifications.gameStart,
                delivery_modes.gameStart if delivery_modes else None,
            ),
            "scoring": (
                payload.notifications.scoring,
                delivery_modes.scoring if delivery_modes else None,
            ),
            "hit": (
                payload.notifications.hit,
                delivery_modes.hit if delivery_modes else None,
            ),
            "homerun": (
                payload.notifications.homerun,
                delivery_modes.homerun if delivery_modes else None,
            ),
            "reversal": (
                payload.notifications.reversal,
                delivery_modes.reversal if delivery_modes else None,
            ),
            "game_end": (
                payload.notifications.gameEnd,
                delivery_modes.gameEnd if delivery_modes else None,
            ),
            "lineup_opened": (
                payload.notifications.lineupOpened,
                delivery_modes.lineupOpened if delivery_modes else None,
            ),
            "inning_change": (
                payload.notifications.inningChange,
                delivery_modes.inningChange if delivery_modes else None,
            ),
            "at_bat": (
                payload.notifications.atBat,
                delivery_modes.atBat if delivery_modes else None,
            ),
            "baseball_info": (
                payload.notifications.baseballInfo,
                delivery_modes.baseballInfo if delivery_modes else None,
            ),
        }

        for topic_name, (setting_enabled, delivery) in topic_flags.items():
            if payload.notifications.allGames:
                if _sends_immediately(setting_enabled, delivery):
                    topics.append(f"{topic_name}_ALL")
                continue

            if topic_name in GAME_MOMENT_TOPIC_NAMES:
                if not _enabled_for_game_moment_topic(setting_enabled, delivery):
                    continue

                if has_my_team:
                    topics.append(f"{topic_name}_{my_team}")

                if followed_game_ids:
                    topics.extend(
                        _game_topic(topic_name, game_id)
                        for game_id in followed_game_ids
                        if not _game_id_contains_team(game_id, my_team if has_my_team else None)
                    )
                continue

            if has_my_team and _sends_immediately(setting_enabled, delivery):
                topics.append(f"{topic_name}_{my_team}")

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
    start_detail = " · ".join(part for part in [start_time.strip(), stadium.strip()] if part)
    if moment == "game_start":
        return "경기 시작", f"{matchup} 경기가 시작됐습니다."
    if moment == "game_start_soon":
        suffix = f" {start_detail}" if start_detail else ""
        return "경기 곧 시작", f"{matchup} 경기가 곧 시작됩니다.{suffix}"
    if moment == "scoring":
        if play_text:
            situation = f" · {situation_text}" if situation_text else ""
            return "득점 장면", f"{inning} {play_text}{situation} · 현재 {score}"
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
    if moment == "lineup_opened":
        return "선발 라인업 공개", f"{matchup} 라인업이 공개됐습니다."
    if moment == "inning_change":
        return "이닝 변경", f"{matchup} {inning} 진입, 현재 {score}"
    if moment == "at_bat":
        if batter_name and pitcher_name:
            return "타석 알림", f"{inning} {batter_name} 타석 · 투수 {pitcher_name}"
        if batter_name:
            return "타석 알림", f"{inning} {batter_name} 타석"
        return "타석 알림", f"{matchup} {inning} 현재 {score}"
    return "경기 알림", f"{matchup} {inning} 현재 {score}"


def _baseball_info_topics(
    *,
    topic: Optional[str],
    team_id: Optional[str],
) -> list[str]:
    if topic:
        return [topic]
    if team_id:
        return [f"baseball_info_{team_id}"]
    return [f"baseball_info_{team_id}" for team_id in KBO_TEAM_IDS] + ["baseball_info_ALL"]


def _baseball_info_target_preview(
    *,
    topic: Optional[str],
    token: Optional[str],
    team_id: Optional[str],
) -> list[dict[str, str]]:
    if token:
        return [{"target": "token"}]
    return [{"topic": target} for target in _baseball_info_topics(topic=topic, team_id=team_id)]


def _baseball_info_copy(*, kind: str, team_id: Optional[str] = None) -> tuple[str, str]:
    team_name = _team_display_name(team_id)
    if kind == "weekly_check":
        if team_name:
            return (
                f"{team_name} 주간 체크",
                f"이번 주 {team_name} 일정, 순위, 기록 흐름을 확인해 보세요.",
            )
        return "월요일 야구 체크", "이번 주 KBO 일정, 순위, 기록 흐름을 확인해 보세요."
    if kind == "off_day":
        if team_name:
            return (
                f"{team_name} 야구 브리프",
                "경기가 없는 날에는 순위표와 다음 일정을 가볍게 확인해 보세요.",
            )
        return "오늘의 야구 브리프", "경기가 없는 날에는 순위표와 다음 일정을 가볍게 확인해 보세요."
    if kind == "game_day":
        if team_name:
            return (
                f"{team_name} 경기일 체크",
                f"오늘 {team_name} 경기 일정, 선발 라인업, 중계 상황을 확인해 보세요.",
            )
        return "오늘 경기 체크", "오늘 KBO 일정, 선발 라인업, 중계 상황을 확인해 보세요."
    if kind == "records_check":
        if team_name:
            return f"{team_name} 기록실", f"{team_name} 타자와 투수 기록 흐름을 확인해 보세요."
        return "기록실 업데이트", "타자와 투수 기록 흐름을 확인해 보세요."
    if kind == "lineup_day":
        if team_name:
            return f"{team_name} 경기 전 체크", "선발 라인업과 예매 정보를 경기 전에 확인해 보세요."
        return "경기 전 체크", "선발 라인업과 예매 정보를 경기 전에 확인해 보세요."
    if kind == "rival_watch":
        if team_name:
            return f"{team_name} 순위 경쟁", "순위에 영향을 줄 수 있는 주요 경기를 확인해 보세요."
        return "라이벌 경기 체크", "순위에 영향을 줄 수 있는 주요 경기를 확인해 보세요."
    return "야구 브리프", "오늘의 KBO 일정, 순위, 기록 정보를 확인해 보세요."


def _team_display_name(team_id: Optional[str]) -> str:
    if not team_id:
        return ""
    return KBO_TEAM_NAMES.get(team_id, team_id)


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


def _visible_push_options(
    messaging,
    *,
    title: str,
    body: str,
) -> dict[str, Any]:
    options: dict[str, Any] = {}

    if all(hasattr(messaging, name) for name in ("APNSConfig", "APNSPayload", "Aps")):
        headers = {
            "apns-priority": "10",
            "apns-push-type": "alert",
        }
        bundle_id = get_settings().apns_bundle_id
        if bundle_id:
            headers["apns-topic"] = bundle_id
        aps_kwargs: dict[str, Any] = {
            "sound": "default",
            "content_available": True,
        }
        if hasattr(messaging, "ApsAlert"):
            aps_kwargs["alert"] = messaging.ApsAlert(title=title, body=body)
        options["apns"] = messaging.APNSConfig(
            headers=headers,
            payload=messaging.APNSPayload(
                aps=messaging.Aps(**aps_kwargs),
            ),
        )

    if all(hasattr(messaging, name) for name in ("AndroidConfig", "AndroidNotification")):
        options["android"] = messaging.AndroidConfig(
            priority="high",
            notification=messaging.AndroidNotification(
                channel_id=ANDROID_REMOTE_PUSH_CHANNEL_ID,
                sound="default",
            ),
        )

    return options


def _push_send_error_reason(error: Exception) -> str:
    return "원격 푸시 발송에 실패했습니다. 앱을 다시 열고 알림 권한을 확인한 뒤 다시 시도해주세요."


def _sends_immediately(enabled: bool, delivery: Optional[str]) -> bool:
    if not enabled:
        return False
    if delivery is None:
        return True
    return delivery == "immediate"


def _enabled_for_game_moment_topic(enabled: bool, delivery: Optional[str]) -> bool:
    if not enabled:
        return False
    return delivery != "off"


def _game_topic(moment: str, game_id: str) -> str:
    return f"{moment}_GAME_{game_id}"


def _game_id_contains_team(game_id: str, team_id: Optional[str]) -> bool:
    if team_id is None or team_id == "" or len(game_id) < 12:
        return False
    return game_id[8:10] == team_id or game_id[10:12] == team_id


def _test_push_data_for_topic(topic: str) -> dict[str, str]:
    moment, separator, game_id = topic.partition("_GAME_")
    if not separator or moment not in GAME_MOMENT_TOPIC_NAMES or not game_id:
        return {}

    data = {
        "type": moment,
        "gameId": game_id,
        "topic": topic,
    }
    route = _push_route(moment, game_id)
    if route:
        data["route"] = route
    return data


def _push_route(moment: str, game_id: str) -> str:
    if moment == "lineup_opened":
        return f"/game/{game_id}?tab=lineup"
    if moment in GAME_MOMENT_TOPIC_NAMES:
        return f"/game/{game_id}?tab=relay"
    return ""


def _clean_followed_game_ids(game_ids: list[str]) -> list[str]:
    cleaned = []
    seen = set()
    for game_id in game_ids:
        text = str(game_id).strip()
        if not text or text in seen:
            continue
        seen.add(text)
        cleaned.append(text)
    return cleaned


def _registration_to_payload(registration: dict[str, Any]) -> PushRegisterRequest:
    notifications = registration.get("notifications")
    if not isinstance(notifications, dict):
        raise ValueError("missing notifications")

    try:
        return PushRegisterRequest(
            deviceToken=str(registration["deviceToken"]),
            platform=str(registration.get("platform") or "unknown"),
            installationId=str(registration.get("installationId") or ""),
            myTeam=registration.get("myTeam"),
            notifications=notifications,
            followedGameIds=_stored_followed_game_ids(registration),
            notificationsAllowed=_optional_bool(registration.get("notificationsAllowed")),
            authorizationStatus=str(registration.get("authorizationStatus") or ""),
            apnsTokenReady=_optional_bool(registration.get("apnsTokenReady")),
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


def _optional_bool(value: Any) -> Optional[bool]:
    if isinstance(value, bool):
        return value
    if value is None:
        return None
    text = str(value).strip().lower()
    if text in {"1", "true", "yes"}:
        return True
    if text in {"0", "false", "no"}:
        return False
    return None


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
