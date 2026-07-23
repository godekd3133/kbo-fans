from __future__ import annotations

import fcntl
import json
import os
import re
import tempfile
import threading
import uuid
from contextlib import contextmanager
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Iterator, Optional

from kbo_fans_backend.core.config import get_settings
from kbo_fans_backend.schemas.push import (
    LiveActivityRegisterRequest,
    LiveActivityStartTokenRegisterRequest,
    LiveActivityUnregisterRequest,
    PushReceiptRequest,
    PushRegisterRequest,
)

_PUSH_OUTBOX_COMPLETED_LIMIT = 512
_PUSH_OUTBOX_TARGET_LEASE_SECONDS = 60
_SCHEDULED_DELIVERY_LEASE_SECONDS = 60
_LIVE_ACTIVITY_END_LEASE_SECONDS = 60
_LIVE_ACTIVITY_START_LEASE_SECONDS = 60


class PushRegistry:
    _thread_locks: dict[Path, threading.Lock] = {}
    _thread_locks_guard = threading.Lock()

    def __init__(self, path: Optional[str] = None) -> None:
        self.path = Path(path or get_settings().push_registry_path).expanduser()
        self._lock_path = self.path.with_name(f"{self.path.name}.lock")
        self._thread_lock = self._thread_lock_for_path(self._lock_path)

    @classmethod
    def _thread_lock_for_path(cls, path: Path) -> threading.Lock:
        with cls._thread_locks_guard:
            lock = cls._thread_locks.get(path)
            if lock is None:
                lock = threading.Lock()
                cls._thread_locks[path] = lock
            return lock

    def save_device_registration(
        self,
        payload: PushRegisterRequest,
        topics: list[str],
    ) -> dict[str, Any]:
        with self._mutate_data() as data:
            devices = data.setdefault("devices", {})
            now = _now_iso()
            installation_id = _clean_optional_string(payload.installationId)
            if installation_id:
                stale_tokens = [
                    token
                    for token, registration in devices.items()
                    if token != payload.deviceToken
                    and isinstance(registration, dict)
                    and _clean_optional_string(registration.get("installationId"))
                    == installation_id
                ]
                for token in stale_tokens:
                    devices.pop(token, None)
            existing = devices.get(payload.deviceToken, {})
            devices[payload.deviceToken] = {
                **existing,
                "deviceToken": payload.deviceToken,
                "platform": payload.platform,
                "installationId": installation_id,
                "myTeam": payload.myTeam,
                "notifications": _model_to_dict(payload.notifications),
                "followedGameIds": _clean_string_list(payload.followedGameIds),
                "notificationsAllowed": payload.notificationsAllowed,
                "authorizationStatus": str(payload.authorizationStatus or "").strip(),
                "apnsTokenReady": payload.apnsTokenReady,
                "topics": topics,
                "updatedAt": now,
                "createdAt": existing.get("createdAt", now),
            }
            return devices[payload.deviceToken]

    def save_device_topics(
        self,
        payload: PushRegisterRequest,
        topics: list[str],
    ) -> dict[str, Any]:
        with self._mutate_data() as data:
            devices = data.setdefault("devices", {})
            now = _now_iso()
            existing = devices.get(payload.deviceToken, {})
            if not isinstance(existing, dict):
                existing = {}
            devices[payload.deviceToken] = {
                **existing,
                "deviceToken": payload.deviceToken,
                "followedGameIds": _clean_string_list(payload.followedGameIds),
                "topics": topics,
                "topicsUpdatedAt": now,
                "createdAt": existing.get("createdAt", now),
            }
            return devices[payload.deviceToken]

    def save_live_activity(
        self,
        payload: LiveActivityRegisterRequest,
    ) -> dict[str, Any]:
        with self._mutate_data() as data:
            activities = data.setdefault("liveActivities", {})
            if payload.previousActivityPushToken:
                activities.pop(payload.previousActivityPushToken, None)

            now = _now_iso()
            existing = activities.get(payload.activityPushToken, {})
            activities[payload.activityPushToken] = {
                **existing,
                "gameId": payload.gameId,
                "activityId": payload.activityId,
                "activityPushToken": payload.activityPushToken,
                "installationId": _clean_optional_string(payload.installationId),
                "platform": payload.platform,
                "updatedAt": now,
                "createdAt": existing.get("createdAt", now),
            }
            activities[payload.activityPushToken].pop("endClaimId", None)
            activities[payload.activityPushToken].pop("endClaimedAt", None)
            return activities[payload.activityPushToken]

    def save_live_activity_start_token(
        self,
        payload: LiveActivityStartTokenRegisterRequest,
    ) -> dict[str, Any]:
        with self._mutate_data() as data:
            tokens = data.setdefault("liveActivityStartTokens", {})
            if payload.previousPushToStartToken:
                tokens.pop(payload.previousPushToStartToken, None)

            now = _now_iso()
            existing = tokens.get(payload.pushToStartToken, {})
            tokens[payload.pushToStartToken] = {
                **existing,
                "pushToStartToken": payload.pushToStartToken,
                "previousPushToStartToken": _clean_optional_string(
                    payload.previousPushToStartToken
                ),
                "installationId": _clean_optional_string(payload.installationId),
                "platform": payload.platform,
                "updatedAt": now,
                "createdAt": existing.get("createdAt", now),
            }
            return tokens[payload.pushToStartToken]

    def remove_live_activity(
        self,
        payload: LiveActivityUnregisterRequest,
    ) -> int:
        with self._mutate_data() as data:
            activities = data.setdefault("liveActivities", {})
            remove_tokens = []
            for token, activity in activities.items():
                if activity.get("gameId") != payload.gameId:
                    continue
                if payload.activityPushToken and token != payload.activityPushToken:
                    continue
                if payload.activityId and activity.get("activityId") != payload.activityId:
                    continue
                remove_tokens.append(token)

            for token in remove_tokens:
                activities.pop(token, None)

            return len(remove_tokens)

    def live_activity_tokens_for_game(self, game_id: str) -> list[str]:
        data = self._load()
        activities = data.get("liveActivities", {})
        tokens = [
            token for token, activity in activities.items() if activity.get("gameId") == game_id
        ]
        tokens.sort()
        return tokens

    def claim_live_activity_end(
        self,
        *,
        game_id: str,
        activity_push_token: str,
    ) -> Optional[str]:
        now = datetime.now(timezone.utc)
        claim_id = uuid.uuid4().hex
        with self._mutate_data() as data:
            activities = data.setdefault("liveActivities", {})
            activity = activities.get(activity_push_token)
            if not isinstance(activity, dict) or activity.get("gameId") != game_id:
                return None

            claimed_at = _parse_iso_datetime(activity.get("endClaimedAt"))
            if activity.get("endClaimId") and claimed_at is not None:
                lease_age = now - claimed_at
                if lease_age.total_seconds() < _LIVE_ACTIVITY_END_LEASE_SECONDS:
                    return None

            activity["endClaimId"] = claim_id
            activity["endClaimedAt"] = now.isoformat()
            activity["updatedAt"] = now.isoformat()
            return claim_id

    def complete_live_activity_end(
        self,
        *,
        game_id: str,
        activity_push_token: str,
        claim_id: str,
    ) -> bool:
        with self._mutate_data() as data:
            activities = data.setdefault("liveActivities", {})
            activity = activities.get(activity_push_token)
            if (
                not isinstance(activity, dict)
                or activity.get("gameId") != game_id
                or activity.get("endClaimId") != claim_id
            ):
                return False
            activities.pop(activity_push_token, None)
            return True

    def release_live_activity_end(
        self,
        *,
        game_id: str,
        activity_push_token: str,
        claim_id: str,
    ) -> bool:
        with self._mutate_data() as data:
            activities = data.setdefault("liveActivities", {})
            activity = activities.get(activity_push_token)
            if (
                not isinstance(activity, dict)
                or activity.get("gameId") != game_id
                or activity.get("endClaimId") != claim_id
            ):
                return False
            activity.pop("endClaimId", None)
            activity.pop("endClaimedAt", None)
            activity["updatedAt"] = _now_iso()
            return True

    def live_activity_game_ids(self) -> list[str]:
        data = self._load()
        activities = data.get("liveActivities", {})
        game_ids = {
            str(activity.get("gameId"))
            for activity in activities.values()
            if activity.get("gameId")
        }
        return sorted(game_ids)

    def live_activity_start_token_count(self) -> int:
        data = self._load()
        tokens = data.get("liveActivityStartTokens", {})
        if not isinstance(tokens, dict):
            return 0
        return sum(1 for value in tokens.values() if isinstance(value, dict))

    def has_live_activity_start_tokens(self) -> bool:
        return self.live_activity_start_token_count() > 0

    def live_activity_start_registrations_for_game(
        self,
        *,
        game_id: str,
        away_team_id: str,
        home_team_id: str,
    ) -> list[dict[str, Any]]:
        data = self._load()
        tokens = data.get("liveActivityStartTokens", {})
        devices = data.get("devices", {})
        if not isinstance(tokens, dict) or not isinstance(devices, dict):
            return []

        active_installations = self._live_activity_installation_ids_for_game(data, game_id)
        registrations_by_installation: dict[str, list[dict[str, Any]]] = {}
        for registration in devices.values():
            if not isinstance(registration, dict):
                continue
            installation_id = _clean_optional_string(registration.get("installationId"))
            if not installation_id:
                continue
            registrations_by_installation.setdefault(installation_id, []).append(registration)

        eligible = []
        seen_tokens = set()
        for token, registration in tokens.items():
            if not isinstance(registration, dict):
                continue
            push_to_start_token = _clean_optional_string(
                registration.get("pushToStartToken") or token
            )
            if not push_to_start_token or push_to_start_token in seen_tokens:
                continue
            installation_id = _clean_optional_string(registration.get("installationId"))
            if not installation_id or installation_id in active_installations:
                continue
            if self._live_activity_start_sent(data, game_id, push_to_start_token):
                continue
            device_registrations = registrations_by_installation.get(installation_id, [])
            if not any(
                _device_allows_live_activity_auto_start(
                    device,
                    game_id=game_id,
                    away_team_id=away_team_id,
                    home_team_id=home_team_id,
                )
                for device in device_registrations
            ):
                continue
            seen_tokens.add(push_to_start_token)
            eligible.append(
                {
                    **registration,
                    "pushToStartToken": push_to_start_token,
                    "installationId": installation_id,
                }
            )
        eligible.sort(key=lambda item: str(item.get("pushToStartToken", "")))
        return eligible

    def mark_live_activity_start_sent(
        self,
        *,
        game_id: str,
        push_to_start_token: str,
    ) -> dict[str, Any]:
        token = _clean_optional_string(push_to_start_token)
        with self._mutate_data() as data:
            states = data.setdefault("liveActivityStartStates", {})
            game_state = states.setdefault(game_id, {})
            state = {
                "pushToStartTokenSuffix": token[-8:],
                "status": "sent",
                "sentAt": _now_iso(),
            }
            game_state[token] = state
            return state

    def claim_live_activity_start(
        self,
        *,
        game_id: str,
        push_to_start_token: str,
    ) -> Optional[str]:
        token = _clean_optional_string(push_to_start_token)
        if not token:
            return None
        now = datetime.now(timezone.utc)
        claim_id = uuid.uuid4().hex
        with self._mutate_data() as data:
            states = data.setdefault("liveActivityStartStates", {})
            game_state = states.setdefault(game_id, {})
            if not isinstance(game_state, dict):
                game_state = {}
                states[game_id] = game_state
            state = game_state.get(token)
            if isinstance(state, dict):
                if state.get("status") == "sent" or state.get("sentAt"):
                    return None
                claimed_at = _parse_iso_datetime(state.get("claimedAt"))
                if state.get("status") == "sending" and claimed_at is not None:
                    lease_age = now - claimed_at
                    if lease_age.total_seconds() < _LIVE_ACTIVITY_START_LEASE_SECONDS:
                        return None
            else:
                state = {}
                game_state[token] = state

            state.update(
                {
                    "pushToStartTokenSuffix": token[-8:],
                    "status": "sending",
                    "attempts": int(state.get("attempts") or 0) + 1,
                    "claimId": claim_id,
                    "claimedAt": now.isoformat(),
                    "updatedAt": now.isoformat(),
                }
            )
            state.pop("lastError", None)
            return claim_id

    def complete_live_activity_start(
        self,
        *,
        game_id: str,
        push_to_start_token: str,
        claim_id: str,
    ) -> bool:
        token = _clean_optional_string(push_to_start_token)
        with self._mutate_data() as data:
            states = data.setdefault("liveActivityStartStates", {})
            game_state = states.get(game_id)
            state = game_state.get(token) if isinstance(game_state, dict) else None
            if not isinstance(state, dict) or state.get("claimId") != claim_id:
                return False
            now = _now_iso()
            state.update(
                {
                    "pushToStartTokenSuffix": token[-8:],
                    "status": "sent",
                    "sentAt": now,
                    "updatedAt": now,
                }
            )
            state.pop("claimId", None)
            state.pop("claimedAt", None)
            state.pop("lastError", None)
            return True

    def release_live_activity_start(
        self,
        *,
        game_id: str,
        push_to_start_token: str,
        claim_id: str,
        error: str = "",
    ) -> bool:
        token = _clean_optional_string(push_to_start_token)
        with self._mutate_data() as data:
            states = data.setdefault("liveActivityStartStates", {})
            game_state = states.get(game_id)
            state = game_state.get(token) if isinstance(game_state, dict) else None
            if not isinstance(state, dict) or state.get("claimId") != claim_id:
                return False
            state.update(
                {
                    "status": "pending",
                    "lastError": str(error).strip()[:500],
                    "updatedAt": _now_iso(),
                }
            )
            state.pop("claimId", None)
            state.pop("claimedAt", None)
            return True

    @staticmethod
    def _live_activity_installation_ids_for_game(
        data: dict[str, Any],
        game_id: str,
    ) -> set[str]:
        activities = data.get("liveActivities", {})
        if not isinstance(activities, dict):
            return set()
        return {
            _clean_optional_string(activity.get("installationId"))
            for activity in activities.values()
            if isinstance(activity, dict)
            and activity.get("gameId") == game_id
            and _clean_optional_string(activity.get("installationId"))
        }

    @staticmethod
    def _live_activity_start_sent(
        data: dict[str, Any],
        game_id: str,
        push_to_start_token: str,
    ) -> bool:
        states = data.get("liveActivityStartStates", {})
        if not isinstance(states, dict):
            return False
        game_state = states.get(game_id)
        if not isinstance(game_state, dict):
            return False
        state = game_state.get(push_to_start_token)
        return isinstance(state, dict) and (
            state.get("status") == "sent" or bool(state.get("sentAt"))
        )

    def has_device_registrations(self) -> bool:
        data = self._load()
        devices = data.get("devices", {})
        return bool(devices)

    def has_device_token(self, device_token: str) -> bool:
        data = self._load()
        devices = data.get("devices", {})
        return device_token in devices

    def record_device_test_result(
        self,
        *,
        device_token: str,
        sent: bool,
        registered: bool,
        reason: str = "",
        message_id: str = "",
        error_type: str = "",
        debug_reason: str = "",
    ) -> dict[str, Any]:
        with self._mutate_data() as data:
            devices = data.setdefault("devices", {})
            registration = devices.get(device_token)
            if not isinstance(registration, dict):
                registration = {}

            results = data.setdefault("deviceTestResults", [])
            if not isinstance(results, list):
                results = []
                data["deviceTestResults"] = results

            result = {
                "sent": sent,
                "registered": registered,
                "reason": reason,
                "messageId": message_id,
                "errorType": error_type,
                "debugReason": _safe_diagnostic_text(debug_reason),
                "deviceTokenSuffix": device_token[-8:],
                "platform": str(registration.get("platform") or ""),
                "myTeam": str(registration.get("myTeam") or ""),
                "recordedAt": _now_iso(),
            }
            results.append(result)
            del results[:-20]
            return result

    def recent_device_test_results(self, *, limit: int = 5) -> list[dict[str, Any]]:
        data = self._load()
        results = data.get("deviceTestResults")
        if not isinstance(results, list):
            return []
        cleaned = [result for result in results if isinstance(result, dict)]
        return cleaned[-limit:]

    def record_push_receipt(self, payload: PushReceiptRequest) -> Optional[dict[str, Any]]:
        device_token = payload.deviceToken.strip()
        if not device_token:
            return None

        with self._mutate_data() as data:
            devices = data.setdefault("devices", {})
            registration = devices.get(device_token)
            if not isinstance(registration, dict):
                return None

            receipts = data.setdefault("pushReceipts", [])
            if not isinstance(receipts, list):
                receipts = []
                data["pushReceipts"] = receipts

            receipt = {
                "messageId": payload.messageId or "",
                "source": payload.source,
                "type": payload.type or "",
                "gameId": payload.gameId or "",
                "route": payload.route or "",
                "receivedAt": payload.receivedAt or _now_iso(),
                "recordedAt": _now_iso(),
                "data": _receipt_data(payload.data),
                "deviceTokenSuffix": device_token[-8:],
                "platform": str(registration.get("platform") or ""),
                "myTeam": str(registration.get("myTeam") or ""),
                "followedGameIds": _clean_string_list(registration.get("followedGameIds") or []),
            }
            receipts.append(receipt)
            del receipts[:-50]
            return receipt

    def recent_push_receipts(self, *, limit: int = 10) -> list[dict[str, Any]]:
        data = self._load()
        receipts = data.get("pushReceipts")
        if not isinstance(receipts, list):
            return []
        cleaned = [receipt for receipt in receipts if isinstance(receipt, dict)]
        return cleaned[-limit:]

    def device_registrations(self) -> list[dict[str, Any]]:
        data = self._load()
        devices = data.get("devices", {})
        registrations = []
        for token, registration in devices.items():
            if not isinstance(registration, dict):
                continue
            device_token = str(registration.get("deviceToken") or token)
            if not device_token:
                continue
            registrations.append(
                {
                    **registration,
                    "deviceToken": device_token,
                }
            )
        registrations.sort(key=lambda item: str(item.get("deviceToken", "")))
        return registrations

    def scoreboard_state(self, game_id: str) -> Optional[dict[str, Any]]:
        data = self._load()
        states = data.get("scoreboardStates", {})
        state = states.get(game_id)
        return state if isinstance(state, dict) else None

    def replace_scoreboard_state(
        self,
        game_id: str,
        state: dict[str, Any],
    ) -> Optional[dict[str, Any]]:
        return self.replace_scoreboard_state_and_enqueue(
            game_id,
            state,
            events=[],
        )

    def replace_scoreboard_state_and_enqueue(
        self,
        game_id: str,
        state: dict[str, Any],
        *,
        events: list[dict[str, Any]],
    ) -> Optional[dict[str, Any]]:
        with self._mutate_data() as data:
            states = data.setdefault("scoreboardStates", {})
            previous = states.get(game_id)
            states[game_id] = {
                **state,
                "gameId": game_id,
                "updatedAt": _now_iso(),
            }
            _enqueue_push_outbox_events(data, events)
            return previous if isinstance(previous, dict) else None

    def replace_scoreboard_state_and_enqueue_if_current(
        self,
        game_id: str,
        state: dict[str, Any],
        *,
        events: list[dict[str, Any]],
        expected_updated_at: Optional[str],
    ) -> bool:
        with self._mutate_data() as data:
            states = data.setdefault("scoreboardStates", {})
            previous = states.get(game_id)
            previous_updated_at = (
                str(previous.get("updatedAt") or "") if isinstance(previous, dict) else ""
            )
            if previous_updated_at != str(expected_updated_at or ""):
                return False
            if isinstance(previous, dict) and not _scoreboard_state_can_advance(
                previous,
                state,
            ):
                return False
            states[game_id] = {
                **state,
                "gameId": game_id,
                "updatedAt": _now_iso(),
            }
            _enqueue_push_outbox_events(data, events)
            return True

    def relay_state(self, game_id: str) -> Optional[dict[str, Any]]:
        data = self._load()
        states = data.get("relayStates", {})
        state = states.get(game_id)
        return state if isinstance(state, dict) else None

    def replace_relay_state(
        self,
        game_id: str,
        state: dict[str, Any],
    ) -> Optional[dict[str, Any]]:
        return self.replace_relay_state_and_enqueue(
            game_id,
            state,
            events=[],
        )

    def replace_relay_state_and_enqueue(
        self,
        game_id: str,
        state: dict[str, Any],
        *,
        events: list[dict[str, Any]],
    ) -> Optional[dict[str, Any]]:
        with self._mutate_data() as data:
            states = data.setdefault("relayStates", {})
            previous = states.get(game_id)
            states[game_id] = {
                **state,
                "gameId": game_id,
                "updatedAt": _now_iso(),
            }
            _enqueue_push_outbox_events(data, events)
            return previous if isinstance(previous, dict) else None

    def replace_relay_state_and_enqueue_if_current(
        self,
        game_id: str,
        state: dict[str, Any],
        *,
        events: list[dict[str, Any]],
        expected_updated_at: Optional[str],
    ) -> bool:
        with self._mutate_data() as data:
            states = data.setdefault("relayStates", {})
            previous = states.get(game_id)
            previous_updated_at = (
                str(previous.get("updatedAt") or "") if isinstance(previous, dict) else ""
            )
            if previous_updated_at != str(expected_updated_at or ""):
                return False
            states[game_id] = {
                **state,
                "gameId": game_id,
                "updatedAt": _now_iso(),
            }
            _enqueue_push_outbox_events(data, events)
            return True

    def enqueue_push_outbox_events(
        self,
        events: list[dict[str, Any]],
    ) -> list[dict[str, Any]]:
        with self._mutate_data() as data:
            event_ids = _enqueue_push_outbox_events(data, events)
            outbox = data.setdefault("pushOutbox", {})
            return [
                dict(outbox[event_id])
                for event_id in event_ids
                if isinstance(outbox.get(event_id), dict)
            ]

    def push_outbox_event(self, event_id: str) -> Optional[dict[str, Any]]:
        data = self._load()
        outbox = data.get("pushOutbox", {})
        event = outbox.get(event_id)
        return event if isinstance(event, dict) else None

    def pending_push_outbox_events(
        self,
        *,
        kind: Optional[str] = None,
        limit: int = 100,
    ) -> list[dict[str, Any]]:
        data = self._load()
        outbox = data.get("pushOutbox", {})
        if not isinstance(outbox, dict):
            return []

        pending = [
            event
            for event in outbox.values()
            if isinstance(event, dict)
            and not _push_outbox_event_complete(event)
            and (kind is None or str(event.get("kind") or "") == kind)
        ]
        pending.sort(
            key=lambda event: (
                str(event.get("updatedAt") or ""),
                str(event.get("createdAt") or ""),
                str(event.get("eventId") or ""),
            )
        )
        return pending[: max(0, limit)]

    def claim_push_outbox_target(self, event_id: str, target: str) -> Optional[str]:
        now = datetime.now(timezone.utc)
        claim_id = uuid.uuid4().hex
        with self._mutate_data() as data:
            event = _push_outbox_event(data, event_id)
            target_state = _push_outbox_target(event, target)
            if target_state is None or target_state.get("status") == "sent":
                return None

            claimed_at = _parse_iso_datetime(target_state.get("claimedAt"))
            if target_state.get("status") == "sending" and claimed_at is not None:
                lease_age = now - claimed_at
                if lease_age.total_seconds() < _PUSH_OUTBOX_TARGET_LEASE_SECONDS:
                    return None

            target_state.update(
                {
                    "status": "sending",
                    "attempts": int(target_state.get("attempts") or 0) + 1,
                    "claimId": claim_id,
                    "claimedAt": now.isoformat(),
                    "updatedAt": now.isoformat(),
                }
            )
            target_state.pop("lastError", None)
            event["updatedAt"] = now.isoformat()
            return claim_id

    def mark_push_outbox_target_sent(
        self,
        event_id: str,
        target: str,
        message_id: str,
        *,
        claim_id: Optional[str] = None,
    ) -> bool:
        with self._mutate_data() as data:
            event = _push_outbox_event(data, event_id)
            target_state = _push_outbox_target(event, target)
            if target_state is None:
                return False
            if claim_id is not None and target_state.get("claimId") != claim_id:
                return False

            now = _now_iso()
            target_state.update(
                {
                    "status": "sent",
                    "messageId": message_id,
                    "sentAt": now,
                    "updatedAt": now,
                }
            )
            target_state.pop("claimedAt", None)
            target_state.pop("claimId", None)
            target_state.pop("lastError", None)
            event["updatedAt"] = now
            if _push_outbox_event_complete(event):
                event["completedAt"] = now
            return True

    def mark_push_outbox_target_failed(
        self,
        event_id: str,
        target: str,
        error: str,
        *,
        claim_id: Optional[str] = None,
    ) -> bool:
        with self._mutate_data() as data:
            event = _push_outbox_event(data, event_id)
            target_state = _push_outbox_target(event, target)
            if target_state is None or target_state.get("status") == "sent":
                return False
            if claim_id is not None and target_state.get("claimId") != claim_id:
                return False

            now = _now_iso()
            target_state.update(
                {
                    "status": "pending",
                    "lastError": str(error).strip()[:500],
                    "updatedAt": now,
                }
            )
            target_state.pop("claimedAt", None)
            target_state.pop("claimId", None)
            event["updatedAt"] = now
            return True

    def mark_push_outbox_event_delivered(self, event_id: str) -> bool:
        with self._mutate_data() as data:
            event = _push_outbox_event(data, event_id)
            if event is None:
                return False

            now = _now_iso()
            targets = event.get("targets")
            if not isinstance(targets, dict):
                return False
            for target_state in targets.values():
                if not isinstance(target_state, dict):
                    continue
                target_state.update(
                    {
                        "status": "sent",
                        "updatedAt": now,
                    }
                )
                target_state.pop("claimedAt", None)
                target_state.pop("claimId", None)
                target_state.pop("lastError", None)
            event["updatedAt"] = now
            event["completedAt"] = now
            return True

    def pregame_alert_sent(self, game_id: str, alert_key: str) -> bool:
        data = self._load()
        states = data.get("pregameAlertStates", {})
        state = states.get(game_id)
        if not isinstance(state, dict):
            return False
        alert_keys = state.get("alertKeys")
        if isinstance(alert_keys, list):
            return alert_key in {str(item) for item in alert_keys}
        return str(state.get("alertKey") or "") == alert_key

    def mark_pregame_alert_sent(self, game_id: str, alert_key: str) -> dict[str, Any]:
        with self._mutate_data() as data:
            states = data.setdefault("pregameAlertStates", {})
            previous = states.get(game_id)
            previous_keys: list[str] = []
            if isinstance(previous, dict):
                alert_keys = previous.get("alertKeys")
                if isinstance(alert_keys, list):
                    previous_keys = [str(item) for item in alert_keys]
                elif previous.get("alertKey"):
                    previous_keys = [str(previous.get("alertKey"))]
            if alert_key not in previous_keys:
                previous_keys.append(alert_key)
            state = {
                "gameId": game_id,
                "alertKey": alert_key,
                "alertKeys": previous_keys,
                "updatedAt": _now_iso(),
            }
            states[game_id] = state
            return state

    def scheduled_alert_sent(self, alert_key: str) -> bool:
        data = self._load()
        states = data.get("scheduledAlertStates", {})
        if not isinstance(states, dict):
            return False
        return alert_key in states

    def scheduled_delivery_ids(self, alert_key: str) -> set[str]:
        data = self._load()
        states = data.get("scheduledDeliveryStates", {})
        if not isinstance(states, dict):
            return set()
        delivery_state = states.get(alert_key)
        if not isinstance(delivery_state, dict):
            return set()
        delivery_ids = delivery_state.get("deliveryIds")
        sent_ids = (
            {str(delivery_id) for delivery_id in delivery_ids if delivery_id}
            if isinstance(delivery_ids, list)
            else set()
        )
        deliveries = delivery_state.get("deliveries")
        if isinstance(deliveries, dict):
            sent_ids.update(
                str(delivery_id)
                for delivery_id, state in deliveries.items()
                if delivery_id and isinstance(state, dict) and state.get("status") == "sent"
            )
        return sent_ids

    def claim_scheduled_delivery(
        self,
        alert_key: str,
        delivery_id: str,
    ) -> Optional[str]:
        now = datetime.now(timezone.utc)
        claim_id = uuid.uuid4().hex
        with self._mutate_data() as data:
            completed_states = data.setdefault("scheduledAlertStates", {})
            if isinstance(completed_states, dict) and alert_key in completed_states:
                return None
            states = data.setdefault("scheduledDeliveryStates", {})
            delivery_state = states.setdefault(
                alert_key,
                {
                    "alertKey": alert_key,
                    "deliveryIds": [],
                    "deliveries": {},
                    "updatedAt": now.isoformat(),
                },
            )
            if not isinstance(delivery_state, dict):
                delivery_state = {
                    "alertKey": alert_key,
                    "deliveryIds": [],
                    "deliveries": {},
                    "updatedAt": now.isoformat(),
                }
                states[alert_key] = delivery_state

            sent_ids = delivery_state.setdefault("deliveryIds", [])
            if isinstance(sent_ids, list) and delivery_id in {str(item) for item in sent_ids}:
                return None

            deliveries = delivery_state.setdefault("deliveries", {})
            if not isinstance(deliveries, dict):
                deliveries = {}
                delivery_state["deliveries"] = deliveries
            target_state = deliveries.setdefault(
                delivery_id,
                {
                    "status": "pending",
                    "attempts": 0,
                    "updatedAt": now.isoformat(),
                },
            )
            if not isinstance(target_state, dict):
                target_state = {
                    "status": "pending",
                    "attempts": 0,
                    "updatedAt": now.isoformat(),
                }
                deliveries[delivery_id] = target_state
            if target_state.get("status") == "sent":
                return None

            claimed_at = _parse_iso_datetime(target_state.get("claimedAt"))
            if target_state.get("status") == "sending" and claimed_at is not None:
                lease_age = now - claimed_at
                if lease_age.total_seconds() < _SCHEDULED_DELIVERY_LEASE_SECONDS:
                    return None

            target_state.update(
                {
                    "status": "sending",
                    "attempts": int(target_state.get("attempts") or 0) + 1,
                    "claimId": claim_id,
                    "claimedAt": now.isoformat(),
                    "updatedAt": now.isoformat(),
                }
            )
            target_state.pop("lastError", None)
            delivery_state["updatedAt"] = now.isoformat()
            return claim_id

    def mark_scheduled_delivery_sent(
        self,
        alert_key: str,
        delivery_id: str,
        *,
        claim_id: Optional[str] = None,
    ) -> bool:
        with self._mutate_data() as data:
            states = data.setdefault("scheduledDeliveryStates", {})
            previous = states.get(alert_key)
            if not isinstance(previous, dict):
                return False
            deliveries = previous.setdefault("deliveries", {})
            target_state = deliveries.get(delivery_id) if isinstance(deliveries, dict) else None
            if not isinstance(target_state, dict):
                if claim_id is not None:
                    return False
                if not isinstance(deliveries, dict):
                    deliveries = {}
                    previous["deliveries"] = deliveries
                target_state = {}
                deliveries[delivery_id] = target_state
            if claim_id is not None and target_state.get("claimId") != claim_id:
                return False

            now = _now_iso()
            target_state.update(
                {
                    "status": "sent",
                    "sentAt": now,
                    "updatedAt": now,
                }
            )
            target_state.pop("claimId", None)
            target_state.pop("claimedAt", None)
            target_state.pop("lastError", None)
            delivery_ids = (
                [str(item) for item in previous.get("deliveryIds", [])]
                if isinstance(previous.get("deliveryIds"), list)
                else []
            )
            if delivery_id not in delivery_ids:
                delivery_ids.append(delivery_id)
            previous["deliveryIds"] = delivery_ids
            previous["updatedAt"] = now
            return True

    def mark_scheduled_delivery_failed(
        self,
        alert_key: str,
        delivery_id: str,
        error: str,
        *,
        claim_id: str,
    ) -> bool:
        with self._mutate_data() as data:
            states = data.setdefault("scheduledDeliveryStates", {})
            delivery_state = states.get(alert_key)
            if not isinstance(delivery_state, dict):
                return False
            deliveries = delivery_state.get("deliveries")
            target_state = deliveries.get(delivery_id) if isinstance(deliveries, dict) else None
            if not isinstance(target_state, dict) or target_state.get("claimId") != claim_id:
                return False
            now = _now_iso()
            target_state.update(
                {
                    "status": "pending",
                    "lastError": str(error).strip()[:500],
                    "updatedAt": now,
                }
            )
            target_state.pop("claimId", None)
            target_state.pop("claimedAt", None)
            delivery_state["updatedAt"] = now
            return True

    def mark_scheduled_alert_sent_if_deliveries_complete(
        self,
        alert_key: str,
        delivery_ids: list[str],
    ) -> bool:
        unique_delivery_ids = list(dict.fromkeys(delivery_ids))
        if not unique_delivery_ids:
            return False
        with self._mutate_data() as data:
            delivery_states = data.setdefault("scheduledDeliveryStates", {})
            delivery_state = delivery_states.get(alert_key)
            if not isinstance(delivery_state, dict):
                return False
            deliveries = delivery_state.get("deliveries")
            legacy_sent_ids = delivery_state.get("deliveryIds")
            legacy_sent = (
                {str(item) for item in legacy_sent_ids}
                if isinstance(legacy_sent_ids, list)
                else set()
            )
            complete = all(
                delivery_id in legacy_sent
                or (
                    isinstance(deliveries, dict)
                    and isinstance(deliveries.get(delivery_id), dict)
                    and deliveries[delivery_id].get("status") == "sent"
                )
                for delivery_id in unique_delivery_ids
            )
            if not complete:
                return False

            states = data.setdefault("scheduledAlertStates", {})
            states[alert_key] = {
                "alertKey": alert_key,
                "updatedAt": _now_iso(),
            }
            delivery_states.pop(alert_key, None)
            return True

    def mark_scheduled_alert_sent(self, alert_key: str) -> dict[str, Any]:
        with self._mutate_data() as data:
            states = data.setdefault("scheduledAlertStates", {})
            state = {
                "alertKey": alert_key,
                "updatedAt": _now_iso(),
            }
            states[alert_key] = state
            delivery_states = data.setdefault("scheduledDeliveryStates", {})
            if isinstance(delivery_states, dict):
                delivery_states.pop(alert_key, None)
            return state

    def record_sync_heartbeat(self, payload: dict[str, Any]) -> dict[str, Any]:
        with self._mutate_data() as data:
            heartbeat = {
                **payload,
                "updatedAt": _now_iso(),
            }
            data["syncHeartbeat"] = heartbeat
            return heartbeat

    def sync_heartbeat(self) -> dict[str, Any]:
        data = self._load()
        heartbeat = data.get("syncHeartbeat")
        return heartbeat if isinstance(heartbeat, dict) else {}

    def _load(self) -> dict[str, Any]:
        with self._thread_lock:
            with self._file_lock(exclusive=False):
                return self._load_unlocked()

    @contextmanager
    def _mutate_data(self) -> Iterator[dict[str, Any]]:
        with self._thread_lock:
            with self._file_lock(exclusive=True):
                data = self._load_unlocked()
                try:
                    yield data
                except Exception:
                    raise
                else:
                    self._save_unlocked(data)

    @contextmanager
    def _file_lock(self, *, exclusive: bool) -> Iterator[None]:
        self.path.parent.mkdir(parents=True, exist_ok=True)
        lock_mode = fcntl.LOCK_EX if exclusive else fcntl.LOCK_SH
        with self._lock_path.open("a+", encoding="utf-8") as lock_file:
            fcntl.flock(lock_file.fileno(), lock_mode)
            try:
                yield
            finally:
                fcntl.flock(lock_file.fileno(), fcntl.LOCK_UN)

    def _load_unlocked(self) -> dict[str, Any]:
        if not self.path.exists():
            return _empty_registry()

        try:
            data = json.loads(self.path.read_text(encoding="utf-8"))
        except (json.JSONDecodeError, OSError):
            return _empty_registry()

        if not isinstance(data, dict):
            return _empty_registry()
        data.setdefault("devices", {})
        data.setdefault("liveActivities", {})
        data.setdefault("scoreboardStates", {})
        data.setdefault("relayStates", {})
        data.setdefault("pushOutbox", {})
        data.setdefault("pregameAlertStates", {})
        data.setdefault("scheduledAlertStates", {})
        data.setdefault("scheduledDeliveryStates", {})
        data.setdefault("liveActivityStartTokens", {})
        data.setdefault("liveActivityStartStates", {})
        data.setdefault("pushReceipts", [])
        data.setdefault("deviceTestResults", [])
        data.setdefault("syncHeartbeat", {})
        return data

    def _save_unlocked(self, data: dict[str, Any]) -> None:
        self.path.parent.mkdir(parents=True, exist_ok=True)
        fd, temporary_path = tempfile.mkstemp(
            dir=str(self.path.parent),
            prefix=f".{self.path.name}.",
            suffix=".tmp",
        )
        temporary_file = Path(temporary_path)
        try:
            with os.fdopen(fd, "w", encoding="utf-8") as file:
                file.write(json.dumps(data, ensure_ascii=False, indent=2, sort_keys=True))
                file.write("\n")
                file.flush()
                os.fsync(file.fileno())
            os.replace(temporary_file, self.path)
            _fsync_directory(self.path.parent)
        except Exception:
            try:
                temporary_file.unlink()
            except OSError:
                pass
            raise


def _now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def _empty_registry() -> dict[str, Any]:
    return {
        "devices": {},
        "liveActivities": {},
        "scoreboardStates": {},
        "relayStates": {},
        "pushOutbox": {},
        "pregameAlertStates": {},
        "scheduledAlertStates": {},
        "scheduledDeliveryStates": {},
        "liveActivityStartTokens": {},
        "liveActivityStartStates": {},
        "pushReceipts": [],
        "deviceTestResults": [],
        "syncHeartbeat": {},
    }


def _enqueue_push_outbox_events(
    data: dict[str, Any],
    events: list[dict[str, Any]],
) -> list[str]:
    outbox = data.setdefault("pushOutbox", {})
    if not isinstance(outbox, dict):
        outbox = {}
        data["pushOutbox"] = outbox

    event_ids = []
    for candidate in events:
        event_id = str(candidate.get("eventId") or "").strip()
        kind = str(candidate.get("kind") or "").strip()
        payload = candidate.get("payload")
        target_values = candidate.get("targets")
        if (
            not event_id
            or not kind
            or not isinstance(payload, dict)
            or not isinstance(target_values, list)
        ):
            raise ValueError("push outbox event requires eventId, kind, payload, and targets")

        targets = [str(target).strip() for target in target_values if str(target).strip()]
        if not targets:
            raise ValueError("push outbox event requires at least one target")

        existing = outbox.get(event_id)
        if isinstance(existing, dict):
            event_ids.append(event_id)
            continue

        now = _now_iso()
        outbox[event_id] = {
            "eventId": event_id,
            "kind": kind,
            "payload": dict(payload),
            "targets": {
                target: {
                    "status": "pending",
                    "attempts": 0,
                    "updatedAt": now,
                }
                for target in dict.fromkeys(targets)
            },
            "createdAt": now,
            "updatedAt": now,
        }
        event_ids.append(event_id)

    _prune_completed_push_outbox(outbox)
    return event_ids


def _prune_completed_push_outbox(outbox: dict[str, Any]) -> None:
    completed = [
        event
        for event in outbox.values()
        if isinstance(event, dict) and _push_outbox_event_complete(event)
    ]
    completed.sort(
        key=lambda event: (
            str(event.get("completedAt") or event.get("updatedAt") or ""),
            str(event.get("eventId") or ""),
        )
    )
    for event in completed[:-_PUSH_OUTBOX_COMPLETED_LIMIT]:
        outbox.pop(str(event.get("eventId") or ""), None)


def _push_outbox_event(
    data: dict[str, Any],
    event_id: str,
) -> Optional[dict[str, Any]]:
    outbox = data.setdefault("pushOutbox", {})
    if not isinstance(outbox, dict):
        return None
    event = outbox.get(event_id)
    return event if isinstance(event, dict) else None


def _push_outbox_target(
    event: Optional[dict[str, Any]],
    target: str,
) -> Optional[dict[str, Any]]:
    if event is None:
        return None
    targets = event.get("targets")
    if not isinstance(targets, dict):
        return None
    target_state = targets.get(target)
    return target_state if isinstance(target_state, dict) else None


def _push_outbox_event_complete(event: dict[str, Any]) -> bool:
    targets = event.get("targets")
    if not isinstance(targets, dict) or not targets:
        return False
    return all(
        isinstance(target_state, dict) and target_state.get("status") == "sent"
        for target_state in targets.values()
    )


def _scoreboard_state_can_advance(
    previous: dict[str, Any],
    current: dict[str, Any],
) -> bool:
    previous_status = str(previous.get("status") or "").upper()
    current_status = str(current.get("status") or "").upper()
    terminal_statuses = {"FINAL", "CANCELLED"}

    if previous_status in terminal_statuses and current_status != previous_status:
        return False
    if current_status in terminal_statuses:
        return True
    if previous_status in {"LIVE", "SUSPENDED"} and current_status == "SCHEDULED":
        return False
    if (
        previous_status == "SCHEDULED"
        and current_status == "SCHEDULED"
        and bool(previous.get("lineupOpened"))
        and not bool(current.get("lineupOpened"))
    ):
        return False

    previous_at_bat = str(previous.get("atBatMilestone") or "") or (
        _registry_at_bat_milestone(previous)
    )
    current_at_bat = str(current.get("atBatMilestone") or "") or (
        _registry_at_bat_milestone(current)
    )
    seen_at_bats = previous.get("seenAtBatMilestones")
    if (
        previous_status == "LIVE"
        and current_status == "LIVE"
        and current_at_bat
        and current_at_bat != previous_at_bat
        and isinstance(seen_at_bats, list)
        and current_at_bat in {str(item) for item in seen_at_bats}
    ):
        return False

    previous_score_state = _last_verified_registry_score_state(previous)
    current_away = _optional_registry_int(current.get("awayScore"))
    current_home = _optional_registry_int(current.get("homeScore"))
    if previous_score_state is not None and current_away is not None and current_home is not None:
        previous_away = _optional_registry_int(previous_score_state.get("awayScore"))
        previous_home = _optional_registry_int(previous_score_state.get("homeScore"))
        if (
            previous_away is not None
            and previous_home is not None
            and (current_away < previous_away or current_home < previous_home)
        ):
            return False

    if previous_status in {"LIVE", "SUSPENDED"} and current_status in {
        "LIVE",
        "SUSPENDED",
    }:
        previous_inning = _registry_inning_rank(previous.get("inning"))
        current_inning = _registry_inning_rank(current.get("inning"))
        if (
            previous_inning is not None
            and current_inning is not None
            and current_inning < previous_inning
        ):
            return False

    return True


def _last_verified_registry_score_state(
    state: dict[str, Any],
) -> Optional[dict[str, Any]]:
    if (
        _optional_registry_int(state.get("awayScore")) is not None
        and _optional_registry_int(state.get("homeScore")) is not None
    ):
        return state
    nested = state.get("lastVerifiedScoreState")
    if (
        isinstance(nested, dict)
        and _optional_registry_int(nested.get("awayScore")) is not None
        and _optional_registry_int(nested.get("homeScore")) is not None
    ):
        return nested
    return None


def _optional_registry_int(value: Any) -> Optional[int]:
    if value is None or isinstance(value, bool):
        return None
    try:
        return int(value)
    except (TypeError, ValueError):
        return None


def _registry_inning_rank(value: Any) -> Optional[int]:
    match = re.search(r"(\d+)\s*회\s*(초|말)?", str(value or ""))
    if match is None:
        return None
    inning = int(match.group(1))
    half = match.group(2)
    return (inning * 2) + (1 if half == "말" else 0)


def _registry_at_bat_milestone(state: dict[str, Any]) -> str:
    if str(state.get("status") or "").upper() != "LIVE":
        return ""
    batter = str(state.get("batterName") or "").strip()
    if not batter:
        return ""
    return "|".join(
        (
            str(state.get("inning") or "").strip(),
            str(state.get("awayScore") if state.get("awayScore") is not None else "–"),
            str(state.get("homeScore") if state.get("homeScore") is not None else "–"),
            batter,
            str(state.get("pitcherName") or "").strip(),
        )
    )


def _parse_iso_datetime(value: Any) -> Optional[datetime]:
    text = str(value or "").strip()
    if not text:
        return None
    try:
        parsed = datetime.fromisoformat(text.replace("Z", "+00:00"))
    except ValueError:
        return None
    if parsed.tzinfo is None:
        return parsed.replace(tzinfo=timezone.utc)
    return parsed.astimezone(timezone.utc)


def _fsync_directory(path: Path) -> None:
    flags = os.O_RDONLY | getattr(os, "O_DIRECTORY", 0)
    try:
        directory_fd = os.open(str(path), flags)
    except OSError:
        return

    try:
        os.fsync(directory_fd)
    finally:
        os.close(directory_fd)


def _model_to_dict(model: Any) -> dict[str, Any]:
    if hasattr(model, "model_dump"):
        return model.model_dump()
    return model.dict()


def _clean_string_list(values: list[str]) -> list[str]:
    seen = set()
    cleaned = []
    for value in values:
        text = str(value).strip()
        if not text or text in seen:
            continue
        seen.add(text)
        cleaned.append(text)
    return cleaned


def _clean_optional_string(value: Any) -> str:
    return str(value or "").strip()


def _device_allows_live_activity_auto_start(
    registration: dict[str, Any],
    *,
    game_id: str,
    away_team_id: str,
    home_team_id: str,
) -> bool:
    if str(registration.get("platform") or "").lower() != "ios":
        return False
    if registration.get("notificationsAllowed") is not True:
        return False
    notifications = registration.get("notifications")
    if not isinstance(notifications, dict):
        return False
    if notifications.get("gameStart") is not True:
        return False
    delivery_modes = notifications.get("deliveryModes")
    if isinstance(delivery_modes, dict) and delivery_modes.get("gameStart") == "off":
        return False

    team_ids = {away_team_id, home_team_id}
    my_team = _clean_optional_string(registration.get("myTeam"))
    if my_team and my_team in team_ids:
        return True

    followed_game_ids = registration.get("followedGameIds")
    if isinstance(followed_game_ids, list):
        return game_id in {_clean_optional_string(value) for value in followed_game_ids}
    return False


def _receipt_data(values: dict[str, Any]) -> dict[str, str]:
    allowed = {"topic", "collapseKey", "kind"}
    cleaned: dict[str, str] = {}
    for key, value in values.items():
        key_text = str(key)
        if key_text not in allowed:
            continue
        cleaned[key_text] = str(value)[:200]
    return cleaned


def _safe_diagnostic_text(value: str) -> str:
    text = str(value or "").strip()
    if not text:
        return ""
    return text[:500]
