from __future__ import annotations

import fcntl
import hashlib
import json
import math
import os
import re
import tempfile
import threading
import uuid
from contextlib import contextmanager
from copy import deepcopy
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any, Callable, Iterator, Optional

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
# Keep this above the APNs sender timeout so a fenced network call cannot be overtaken.
_LIVE_ACTIVITY_UPDATE_LEASE_SECONDS = 60
_SCORE_CORRECTION_CONFIRMATION_SECONDS = 8.0
_SCORE_CORRECTION_CANDIDATE_KEY = "scoreCorrectionCandidate"
_RUNTIME_STATE_TTL_SECONDS = 90 * 24 * 60 * 60
_PUSH_OUTBOX_PENDING_TTL_SECONDS = 7 * 24 * 60 * 60
_PUSH_OUTBOX_PENDING_LIMIT = 2048
_SYNC_HEARTBEAT_MIN_WRITE_INTERVAL_SECONDS = 30


class PushRegistryCapacityError(RuntimeError):
    pass


class PushRegistryOwnershipError(RuntimeError):
    pass


class PushRegistryCorruptionError(RuntimeError):
    pass


class PushRegistry:
    _thread_locks: dict[Path, threading.Lock] = {}
    _thread_locks_guard = threading.Lock()

    def __init__(
        self,
        path: Optional[str] = None,
        *,
        device_test_cooldown_seconds: Optional[int] = None,
        device_test_global_window_seconds: Optional[int] = None,
        device_test_global_max_attempts: Optional[int] = None,
        max_devices: Optional[int] = None,
        max_live_activities: Optional[int] = None,
        max_live_activity_start_tokens: Optional[int] = None,
        max_registry_bytes: Optional[int] = None,
        device_registration_ttl_seconds: Optional[int] = None,
        live_activity_registration_ttl_seconds: Optional[int] = None,
        live_activity_start_token_ttl_seconds: Optional[int] = None,
        registration_new_owner_window_seconds: Optional[int] = None,
        registration_new_owner_max_attempts: Optional[int] = None,
        registration_now_provider: Optional[Callable[[], datetime]] = None,
        score_correction_confirmation_seconds: Optional[float] = None,
        score_correction_now_provider: Optional[Callable[[], datetime]] = None,
        runtime_state_ttl_seconds: Optional[int] = None,
        outbox_pending_ttl_seconds: Optional[int] = None,
        max_pending_outbox_events: Optional[int] = None,
        runtime_state_now_provider: Optional[Callable[[], datetime]] = None,
        sync_heartbeat_min_write_interval_seconds: Optional[int] = None,
    ) -> None:
        settings = get_settings()
        self.path = Path(path or settings.push_registry_path).expanduser()
        configured_cooldown = (
            settings.push_device_test_cooldown_seconds
            if device_test_cooldown_seconds is None
            else device_test_cooldown_seconds
        )
        self._device_test_cooldown_seconds = max(1, int(configured_cooldown))
        configured_global_window = (
            settings.push_device_test_global_window_seconds
            if device_test_global_window_seconds is None
            else device_test_global_window_seconds
        )
        self._device_test_global_window_seconds = max(
            1,
            int(configured_global_window),
        )
        configured_global_max_attempts = (
            settings.push_device_test_global_max_attempts
            if device_test_global_max_attempts is None
            else device_test_global_max_attempts
        )
        self._device_test_global_max_attempts = max(
            1,
            int(configured_global_max_attempts),
        )
        configured_max_devices = (
            settings.push_registry_max_devices if max_devices is None else max_devices
        )
        self._max_devices = max(1, int(configured_max_devices))
        configured_max_live_activities = (
            settings.push_registry_max_live_activities
            if max_live_activities is None
            else max_live_activities
        )
        self._max_live_activities = max(1, int(configured_max_live_activities))
        configured_max_start_tokens = (
            settings.push_registry_max_live_activity_start_tokens
            if max_live_activity_start_tokens is None
            else max_live_activity_start_tokens
        )
        self._max_live_activity_start_tokens = max(
            1,
            int(configured_max_start_tokens),
        )
        configured_max_bytes = (
            settings.push_registry_max_bytes if max_registry_bytes is None else max_registry_bytes
        )
        self._max_registry_bytes = max(1024, int(configured_max_bytes))
        configured_device_ttl = (
            settings.push_registry_device_ttl_seconds
            if device_registration_ttl_seconds is None
            else device_registration_ttl_seconds
        )
        self._device_registration_ttl_seconds = max(1, int(configured_device_ttl))
        configured_live_activity_ttl = (
            settings.push_registry_live_activity_ttl_seconds
            if live_activity_registration_ttl_seconds is None
            else live_activity_registration_ttl_seconds
        )
        self._live_activity_registration_ttl_seconds = max(
            1,
            int(configured_live_activity_ttl),
        )
        configured_start_token_ttl = (
            settings.push_registry_live_activity_start_token_ttl_seconds
            if live_activity_start_token_ttl_seconds is None
            else live_activity_start_token_ttl_seconds
        )
        self._live_activity_start_token_ttl_seconds = max(
            1,
            int(configured_start_token_ttl),
        )
        configured_admission_window = (
            settings.push_registration_new_owner_window_seconds
            if registration_new_owner_window_seconds is None
            else registration_new_owner_window_seconds
        )
        self._registration_new_owner_window_seconds = max(
            1,
            int(configured_admission_window),
        )
        configured_admission_max = (
            settings.push_registration_new_owner_max_attempts
            if registration_new_owner_max_attempts is None
            else registration_new_owner_max_attempts
        )
        self._registration_new_owner_max_attempts = max(
            1,
            int(configured_admission_max),
        )
        self._registration_now_provider = registration_now_provider or (
            lambda: datetime.now(timezone.utc)
        )
        self._runtime_state_ttl_seconds = max(
            1,
            int(
                _RUNTIME_STATE_TTL_SECONDS
                if runtime_state_ttl_seconds is None
                else runtime_state_ttl_seconds
            ),
        )
        self._outbox_pending_ttl_seconds = max(
            1,
            int(
                _PUSH_OUTBOX_PENDING_TTL_SECONDS
                if outbox_pending_ttl_seconds is None
                else outbox_pending_ttl_seconds
            ),
        )
        self._max_pending_outbox_events = max(
            1,
            int(
                _PUSH_OUTBOX_PENDING_LIMIT
                if max_pending_outbox_events is None
                else max_pending_outbox_events
            ),
        )
        self._runtime_state_now_provider = runtime_state_now_provider or (
            self._registration_now_provider
        )
        configured_heartbeat_interval = (
            _SYNC_HEARTBEAT_MIN_WRITE_INTERVAL_SECONDS
            if sync_heartbeat_min_write_interval_seconds is None
            else sync_heartbeat_min_write_interval_seconds
        )
        self._sync_heartbeat_min_write_interval_seconds = max(
            0,
            int(configured_heartbeat_interval),
        )
        configured_confirmation_seconds = (
            _SCORE_CORRECTION_CONFIRMATION_SECONDS
            if score_correction_confirmation_seconds is None
            else float(score_correction_confirmation_seconds)
        )
        self._score_correction_confirmation_seconds = max(
            0.0,
            configured_confirmation_seconds,
        )
        self._score_correction_now_provider = score_correction_now_provider or (
            lambda: datetime.now(timezone.utc)
        )
        self._lock_path = self.path.with_name(f"{self.path.name}.lock")
        self._thread_lock = self._thread_lock_for_path(self._lock_path)

    def _scoreboard_now(self) -> datetime:
        now = self._score_correction_now_provider()
        if now.tzinfo is None:
            return now.replace(tzinfo=timezone.utc)
        return now.astimezone(timezone.utc)

    def _registration_now(self) -> datetime:
        now = self._registration_now_provider()
        if now.tzinfo is None:
            return now.replace(tzinfo=timezone.utc)
        return now.astimezone(timezone.utc)

    def _registration_is_active(
        self,
        registration: Any,
        *,
        ttl_seconds: int,
        section_name: str,
        now: Optional[datetime] = None,
    ) -> bool:
        last_seen_at = _registration_last_seen_at(
            registration,
            section_name=section_name,
        )
        if last_seen_at is None:
            return True
        reference = now or self._registration_now()
        return (reference - last_seen_at).total_seconds() < ttl_seconds

    def _runtime_state_now(self) -> datetime:
        now = self._runtime_state_now_provider()
        if now.tzinfo is None:
            return now.replace(tzinfo=timezone.utc)
        return now.astimezone(timezone.utc)

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
            if not isinstance(devices, dict):
                devices = {}
                data["devices"] = devices
            now_datetime = self._registration_now()
            now = now_datetime.isoformat()
            installation_id = _clean_optional_string(payload.installationId)
            existing = devices.get(payload.deviceToken)
            existing_installation_id = (
                _clean_optional_string(existing.get("installationId"))
                if isinstance(existing, dict)
                else None
            )
            if existing_installation_id and existing_installation_id != installation_id:
                raise PushRegistryOwnershipError("device token ownership conflict")
            if installation_id:
                owner_tokens = {
                    token
                    for token, registration in devices.items()
                    if isinstance(registration, dict)
                    and _clean_optional_string(registration.get("installationId"))
                    == installation_id
                }
            elif isinstance(existing, dict):
                owner_tokens = {payload.deviceToken}
            else:
                owner_tokens = set()
            removed_devices = _prune_stale_registrations(
                devices,
                now=now_datetime,
                ttl_seconds=self._device_registration_ttl_seconds,
                preserve_tokens=owner_tokens,
                section_name="devices",
            )
            device_test_states = data.get("deviceTestStates")
            if isinstance(device_test_states, dict):
                remaining_installation_ids = {
                    _clean_optional_string(registration.get("installationId"))
                    for registration in devices.values()
                    if isinstance(registration, dict)
                }
                for _, registration in removed_devices:
                    removed_installation_id = _clean_optional_string(
                        registration.get("installationId")
                    )
                    if (
                        removed_installation_id
                        and removed_installation_id not in remaining_installation_ids
                    ):
                        device_test_states.pop(
                            _device_test_state_id(removed_installation_id),
                            None,
                        )
            if not owner_tokens:
                self._claim_new_owner_admission(data, now=now_datetime)
            if installation_id:
                stale_tokens = sorted(
                    token
                    for token, registration in devices.items()
                    if token != payload.deviceToken
                    and isinstance(registration, dict)
                    and _clean_optional_string(registration.get("installationId"))
                    == installation_id
                )
                for token in stale_tokens:
                    devices.pop(token, None)
            if payload.deviceToken not in devices and len(devices) >= self._max_devices:
                raise PushRegistryCapacityError("device registration capacity reached")
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
                "lastSeenAt": now,
                "updatedAt": now,
                "createdAt": existing.get("createdAt", now),
            }
            return devices[payload.deviceToken]

    def _claim_new_owner_admission(
        self,
        data: dict[str, Any],
        *,
        now: datetime,
    ) -> None:
        state = data.setdefault("registrationAdmissionState", {})
        if not isinstance(state, dict):
            raise PushRegistryCorruptionError("registration admission state is invalid")
        raw_accepted_at = state.get("newOwnerAcceptedAt")
        if raw_accepted_at is None:
            raw_accepted_at = []
        if not isinstance(raw_accepted_at, list):
            raise PushRegistryCorruptionError("registration admission timestamps are invalid")

        recent = []
        for raw_timestamp in raw_accepted_at:
            if not isinstance(raw_timestamp, str):
                raise PushRegistryCorruptionError("registration admission timestamp is invalid")
            accepted_at = _parse_iso_datetime(raw_timestamp)
            if accepted_at is None:
                raise PushRegistryCorruptionError("registration admission timestamp is invalid")
            if (now - accepted_at).total_seconds() < self._registration_new_owner_window_seconds:
                recent.append(accepted_at)
        recent.sort()
        if len(recent) >= self._registration_new_owner_max_attempts:
            raise PushRegistryCapacityError("new owner registration rate limit reached")

        recent.append(now)
        state["newOwnerAcceptedAt"] = [timestamp.isoformat() for timestamp in recent]
        state["updatedAt"] = now.isoformat()

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
            now_datetime = self._registration_now()
            existing = activities.get(payload.activityPushToken)
            exact_token_owner_matches = self._live_activity_exact_owner_matches(
                existing,
                payload,
            )
            if self._live_activity_has_strong_owner(
                existing
            ) and not self._live_activity_rotation_owner_matches(existing, payload):
                raise PushRegistryOwnershipError("live activity token ownership conflict")
            owner_tokens = {
                token
                for token, activity in activities.items()
                if self._live_activity_rotation_owner_matches(activity, payload)
            }
            if exact_token_owner_matches:
                owner_tokens.add(payload.activityPushToken)
            removed_activities = _prune_stale_registrations(
                activities,
                now=now_datetime,
                ttl_seconds=self._live_activity_registration_ttl_seconds,
                preserve_tokens=owner_tokens,
                section_name="liveActivities",
            )
            for token, activity in removed_activities:
                game_id = _clean_optional_string(activity.get("gameId"))
                if game_id:
                    self._remove_live_activity_update_delivery(
                        data,
                        game_id=game_id,
                        activity_push_token=token,
                    )
            if not owner_tokens:
                self._claim_new_owner_admission(data, now=now_datetime)
            rotation_tokens = {
                token
                for token, activity in activities.items()
                if token != payload.activityPushToken
                and self._live_activity_rotation_owner_matches(activity, payload)
            }
            previous_token = payload.previousActivityPushToken
            if (
                previous_token
                and previous_token != payload.activityPushToken
                and self._live_activity_rotation_owner_matches(
                    activities.get(previous_token),
                    payload,
                )
            ):
                rotation_tokens.add(previous_token)
            for token in sorted(rotation_tokens):
                activities.pop(token, None)
                self._remove_live_activity_update_delivery(
                    data,
                    game_id=payload.gameId,
                    activity_push_token=token,
                )

            if (
                payload.activityPushToken not in activities
                and len(activities) >= self._max_live_activities
            ):
                raise PushRegistryCapacityError("live activity registration capacity reached")

            now = now_datetime.isoformat()
            existing = activities.get(payload.activityPushToken, {})
            activities[payload.activityPushToken] = {
                **existing,
                "gameId": payload.gameId,
                "activityId": payload.activityId,
                "activityPushToken": payload.activityPushToken,
                "installationId": _clean_optional_string(payload.installationId),
                "platform": payload.platform,
                "registrationGeneration": uuid.uuid4().hex,
                "lastSeenAt": now,
                "updatedAt": now,
                "createdAt": existing.get("createdAt", now),
            }
            activities[payload.activityPushToken].pop("endClaimId", None)
            activities[payload.activityPushToken].pop("endClaimedAt", None)
            return activities[payload.activityPushToken]

    @staticmethod
    def _live_activity_exact_owner_matches(
        activity: Any,
        payload: LiveActivityRegisterRequest,
    ) -> bool:
        return (
            isinstance(activity, dict)
            and activity.get("gameId") == payload.gameId
            and _clean_optional_string(activity.get("activityId"))
            == _clean_optional_string(payload.activityId)
            and _clean_optional_string(activity.get("installationId"))
            == _clean_optional_string(payload.installationId)
        )

    @staticmethod
    def _live_activity_rotation_owner_matches(
        previous: Any,
        payload: LiveActivityRegisterRequest,
    ) -> bool:
        activity_id = payload.activityId
        installation_id = payload.installationId
        return (
            isinstance(previous, dict)
            and isinstance(activity_id, str)
            and bool(activity_id.strip())
            and isinstance(installation_id, str)
            and bool(installation_id.strip())
            and previous.get("gameId") == payload.gameId
            and previous.get("activityId") == activity_id
            and previous.get("installationId") == installation_id
        )

    @staticmethod
    def _live_activity_has_strong_owner(activity: Any) -> bool:
        if not isinstance(activity, dict):
            return False
        return all(
            _clean_optional_string(activity.get(field_name))
            for field_name in ("gameId", "activityId", "installationId")
        )

    def save_live_activity_start_token(
        self,
        payload: LiveActivityStartTokenRegisterRequest,
    ) -> dict[str, Any]:
        with self._mutate_data() as data:
            tokens = data.setdefault("liveActivityStartTokens", {})
            if not isinstance(tokens, dict):
                tokens = {}
                data["liveActivityStartTokens"] = tokens

            now_datetime = self._registration_now()
            installation_id = _clean_optional_string(payload.installationId)
            existing = tokens.get(payload.pushToStartToken)
            existing_installation_id = (
                _clean_optional_string(existing.get("installationId"))
                if isinstance(existing, dict)
                else None
            )
            if existing_installation_id and existing_installation_id != installation_id:
                raise PushRegistryOwnershipError("start token ownership conflict")
            owner_tokens = {
                token
                for token, registration in tokens.items()
                if isinstance(registration, dict)
                and _clean_optional_string(registration.get("installationId")) == installation_id
            }
            removed_tokens = _prune_stale_registrations(
                tokens,
                now=now_datetime,
                ttl_seconds=self._live_activity_start_token_ttl_seconds,
                preserve_tokens=owner_tokens,
                section_name="liveActivityStartTokens",
            )
            for token, _ in removed_tokens:
                self._remove_live_activity_start_token_states(data, token)
            if existing_installation_id == installation_id:
                existing["platform"] = payload.platform
                existing["lastSeenAt"] = now_datetime.isoformat()
                existing["updatedAt"] = now_datetime.isoformat()
                return existing

            if not owner_tokens:
                self._claim_new_owner_admission(data, now=now_datetime)

            current_owner_tokens = sorted(
                token
                for token, registration in tokens.items()
                if token != payload.pushToStartToken
                and isinstance(registration, dict)
                and _clean_optional_string(registration.get("installationId")) == installation_id
            )
            previous_token = _clean_optional_string(payload.previousPushToStartToken)
            if current_owner_tokens and (
                len(current_owner_tokens) != 1 or previous_token != current_owner_tokens[0]
            ):
                raise PushRegistryOwnershipError("start token ownership conflict")
            for token in current_owner_tokens:
                tokens.pop(token, None)
                self._remove_live_activity_start_token_states(data, token)

            if (
                payload.pushToStartToken not in tokens
                and len(tokens) >= self._max_live_activity_start_tokens
            ):
                raise PushRegistryCapacityError("start token registration capacity reached")

            now = now_datetime.isoformat()
            existing = tokens.get(payload.pushToStartToken, {})
            tokens[payload.pushToStartToken] = {
                **existing,
                "pushToStartToken": payload.pushToStartToken,
                "previousPushToStartToken": previous_token,
                "installationId": installation_id,
                "platform": payload.platform,
                "lastSeenAt": now,
                "updatedAt": now,
                "createdAt": existing.get("createdAt", now),
            }
            return tokens[payload.pushToStartToken]

    @staticmethod
    def _remove_live_activity_start_token_states(
        data: dict[str, Any],
        push_to_start_token: str,
    ) -> None:
        states = data.get("liveActivityStartStates")
        if not isinstance(states, dict):
            return
        empty_game_ids = []
        for game_id, game_state in states.items():
            if not isinstance(game_state, dict):
                continue
            game_state.pop(push_to_start_token, None)
            if not game_state:
                empty_game_ids.append(game_id)
        for game_id in empty_game_ids:
            states.pop(game_id, None)

    def remove_live_activity(
        self,
        payload: LiveActivityUnregisterRequest,
    ) -> int:
        activity_push_token = _clean_optional_string(payload.activityPushToken)
        activity_id = _clean_optional_string(payload.activityId)
        installation_id = _clean_optional_string(payload.installationId)
        if not activity_push_token or not activity_id or not installation_id:
            return 0
        with self._mutate_data() as data:
            activities = data.setdefault("liveActivities", {})
            remove_tokens = []
            for token, activity in activities.items():
                if activity.get("gameId") != payload.gameId:
                    continue
                if token != activity_push_token:
                    continue
                if _clean_optional_string(activity.get("activityId")) != activity_id:
                    continue
                if _clean_optional_string(activity.get("installationId")) != installation_id:
                    continue
                remove_tokens.append(token)

            for token in remove_tokens:
                activities.pop(token, None)
                self._remove_live_activity_update_delivery(
                    data,
                    game_id=payload.gameId,
                    activity_push_token=token,
                )

            return len(remove_tokens)

    def live_activity_tokens_for_game(self, game_id: str) -> list[str]:
        data = self._load()
        activities = data.get("liveActivities", {})
        now = self._registration_now()
        tokens = [
            token
            for token, activity in activities.items()
            if activity.get("gameId") == game_id
            and self._registration_is_active(
                activity,
                ttl_seconds=self._live_activity_registration_ttl_seconds,
                section_name="liveActivities",
                now=now,
            )
        ]
        tokens.sort()
        return tokens

    def ensure_live_activity_registration_generation(
        self,
        *,
        game_id: str,
        activity_push_token: str,
    ) -> Optional[str]:
        with self._mutate_data() as data:
            activities = data.setdefault("liveActivities", {})
            activity = activities.get(activity_push_token)
            if not isinstance(activity, dict) or activity.get("gameId") != game_id:
                return None
            generation = _clean_optional_string(activity.get("registrationGeneration"))
            if generation:
                return generation
            generation = uuid.uuid4().hex
            activity["registrationGeneration"] = generation
            return generation

    def claim_live_activity_end(
        self,
        *,
        game_id: str,
        activity_push_token: str,
    ) -> Optional[str]:
        claim = self.claim_live_activity_end_with_generation(
            game_id=game_id,
            activity_push_token=activity_push_token,
        )
        return claim[0] if claim is not None else None

    def claim_live_activity_end_with_generation(
        self,
        *,
        game_id: str,
        activity_push_token: str,
    ) -> Optional[tuple[str, str]]:
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

            generation = _clean_optional_string(activity.get("registrationGeneration"))
            if not generation:
                generation = uuid.uuid4().hex
                activity["registrationGeneration"] = generation
            activity["endClaimId"] = claim_id
            activity["endClaimedAt"] = now.isoformat()
            activity["updatedAt"] = now.isoformat()
            return claim_id, generation

    def complete_live_activity_end(
        self,
        *,
        game_id: str,
        activity_push_token: str,
        claim_id: str,
        expected_registration_generation: Optional[str] = None,
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
            if (
                expected_registration_generation is not None
                and _clean_optional_string(activity.get("registrationGeneration"))
                != expected_registration_generation
            ):
                return False
            activities.pop(activity_push_token, None)
            self._remove_live_activity_update_delivery(
                data,
                game_id=game_id,
                activity_push_token=activity_push_token,
            )
            return True

    def prune_live_activity_token(
        self,
        *,
        game_id: str,
        activity_push_token: str,
        expected_registration_generation: Optional[str],
        end_claim_id: Optional[str] = None,
    ) -> bool:
        with self._mutate_data() as data:
            activities = data.setdefault("liveActivities", {})
            activity = activities.get(activity_push_token)
            if not isinstance(activity, dict) or activity.get("gameId") != game_id:
                return False
            current_generation = _clean_optional_string(activity.get("registrationGeneration"))
            if (
                not expected_registration_generation
                or current_generation != expected_registration_generation
            ):
                return False
            if end_claim_id is not None and activity.get("endClaimId") != end_claim_id:
                return False
            activities.pop(activity_push_token, None)
            self._remove_live_activity_update_delivery(
                data,
                game_id=game_id,
                activity_push_token=activity_push_token,
            )
            return True

    @staticmethod
    def _remove_live_activity_update_delivery(
        data: dict[str, Any],
        *,
        game_id: str,
        activity_push_token: str,
    ) -> None:
        states = data.get("liveActivityUpdateStates")
        if not isinstance(states, dict):
            return
        game_state = states.get(game_id)
        deliveries = game_state.get("deliveries") if isinstance(game_state, dict) else None
        if not isinstance(deliveries, dict):
            return
        deliveries.pop(_live_activity_delivery_id(activity_push_token), None)
        if not deliveries:
            states.pop(game_id, None)

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

    def claim_live_activity_update(
        self,
        *,
        game_id: str,
        delivery_id: str,
        content_signature: str,
    ) -> Optional[str]:
        claims = self.claim_live_activity_updates(
            game_id=game_id,
            delivery_ids=[delivery_id],
            content_signature=content_signature,
        )
        return claims.get(delivery_id)

    def claim_live_activity_updates(
        self,
        *,
        game_id: str,
        delivery_ids: list[str],
        content_signature: str,
    ) -> dict[str, str]:
        now = datetime.now(timezone.utc)
        claims: dict[str, str] = {}
        with self._mutate_data() as data:
            states = data.setdefault("liveActivityUpdateStates", {})
            game_state = states.get(game_id)
            if not isinstance(game_state, dict):
                game_state = {"gameId": game_id, "deliveries": {}}
                states[game_id] = game_state
            deliveries = game_state.setdefault("deliveries", {})
            if not isinstance(deliveries, dict):
                deliveries = {}
                game_state["deliveries"] = deliveries
            for delivery_id in dict.fromkeys(delivery_ids):
                state = deliveries.get(delivery_id)
                if not isinstance(state, dict):
                    state = {}
                    deliveries[delivery_id] = state

                desired_revision = _live_activity_update_revision(state)
                if state.get("desiredContentSignature") != content_signature:
                    desired_revision += 1
                    state["desiredContentSignature"] = content_signature
                    state["desiredRevision"] = desired_revision
                    state["updatedAt"] = now.isoformat()
                elif desired_revision == 0:
                    desired_revision = 1
                    state["desiredRevision"] = desired_revision

                claimed_at = _parse_iso_datetime(state.get("claimedAt"))
                claim_id = _clean_optional_string(state.get("claimId"))
                claim_active = False
                if claim_id and claimed_at is not None:
                    lease_age = now - claimed_at
                    claim_active = lease_age.total_seconds() < _LIVE_ACTIVITY_UPDATE_LEASE_SECONDS

                if state.get("contentSignature") == content_signature:
                    pending_differs = (
                        claim_id and state.get("pendingContentSignature") != content_signature
                    )
                    if not pending_differs:
                        continue
                    if state.get("fencedAt"):
                        if claim_active:
                            continue
                    else:
                        self._clear_live_activity_update_claim(state)
                        state["updatedAt"] = now.isoformat()
                        continue

                if claim_active:
                    current_claim_matches = (
                        state.get("pendingContentSignature") == content_signature
                        and state.get("claimRevision") == desired_revision
                    )
                    if current_claim_matches or state.get("fencedAt"):
                        continue

                claim_id = uuid.uuid4().hex
                state.update(
                    {
                        "pendingContentSignature": content_signature,
                        "claimId": claim_id,
                        "claimRevision": desired_revision,
                        "claimedAt": now.isoformat(),
                        "updatedAt": now.isoformat(),
                    }
                )
                state.pop("fencedAt", None)
                claims[delivery_id] = claim_id
            if claims:
                game_state["updatedAt"] = now.isoformat()
        return claims

    def fence_live_activity_update(
        self,
        *,
        game_id: str,
        delivery_id: str,
        content_signature: str,
        claim_id: str,
    ) -> bool:
        with self._mutate_data() as data:
            states = data.setdefault("liveActivityUpdateStates", {})
            game_state = states.get(game_id)
            deliveries = game_state.get("deliveries") if isinstance(game_state, dict) else None
            state = deliveries.get(delivery_id) if isinstance(deliveries, dict) else None
            if not self._matches_live_activity_update_claim(
                state,
                content_signature=content_signature,
                claim_id=claim_id,
            ) or state.get("claimRevision") != state.get("desiredRevision"):
                return False

            now = _now_iso()
            state["claimedAt"] = now
            state["fencedAt"] = now
            state["updatedAt"] = now
            game_state["updatedAt"] = now
            return True

    def resolve_live_activity_updates(
        self,
        *,
        game_id: str,
        content_signature: str,
        completed_claims: dict[str, str],
        released_claims: dict[str, str],
    ) -> int:
        resolved = 0
        with self._mutate_data() as data:
            states = data.setdefault("liveActivityUpdateStates", {})
            game_state = states.get(game_id)
            deliveries = game_state.get("deliveries") if isinstance(game_state, dict) else None
            if not isinstance(deliveries, dict):
                return 0

            now = _now_iso()
            for delivery_id, claim_id in completed_claims.items():
                state = deliveries.get(delivery_id)
                if not self._matches_live_activity_update_claim(
                    state,
                    content_signature=content_signature,
                    claim_id=claim_id,
                ):
                    continue
                state.update(
                    {
                        "contentSignature": content_signature,
                        "sentAt": now,
                        "updatedAt": now,
                    }
                )
                self._clear_live_activity_update_claim(state)
                resolved += 1

            for delivery_id, claim_id in released_claims.items():
                state = deliveries.get(delivery_id)
                if not self._matches_live_activity_update_claim(
                    state,
                    content_signature=content_signature,
                    claim_id=claim_id,
                ):
                    continue
                self._clear_live_activity_update_claim(state)
                state["updatedAt"] = now
                resolved += 1

            if resolved and isinstance(game_state, dict):
                game_state["updatedAt"] = now
        return resolved

    @staticmethod
    def _matches_live_activity_update_claim(
        state: Any,
        *,
        content_signature: str,
        claim_id: str,
    ) -> bool:
        return (
            isinstance(state, dict)
            and state.get("claimId") == claim_id
            and state.get("pendingContentSignature") == content_signature
        )

    @staticmethod
    def _clear_live_activity_update_claim(state: dict[str, Any]) -> None:
        state.pop("pendingContentSignature", None)
        state.pop("claimId", None)
        state.pop("claimRevision", None)
        state.pop("claimedAt", None)
        state.pop("fencedAt", None)

    def complete_live_activity_update(
        self,
        *,
        game_id: str,
        delivery_id: str,
        content_signature: str,
        claim_id: str,
    ) -> bool:
        return (
            self.resolve_live_activity_updates(
                game_id=game_id,
                content_signature=content_signature,
                completed_claims={delivery_id: claim_id},
                released_claims={},
            )
            == 1
        )

    def release_live_activity_update(
        self,
        *,
        game_id: str,
        delivery_id: str,
        content_signature: str,
        claim_id: str,
    ) -> bool:
        return (
            self.resolve_live_activity_updates(
                game_id=game_id,
                content_signature=content_signature,
                completed_claims={},
                released_claims={delivery_id: claim_id},
            )
            == 1
        )

    def live_activity_game_ids(self) -> list[str]:
        data = self._load()
        activities = data.get("liveActivities", {})
        now = self._registration_now()
        game_ids = {
            str(activity.get("gameId"))
            for activity in activities.values()
            if activity.get("gameId")
            and self._registration_is_active(
                activity,
                ttl_seconds=self._live_activity_registration_ttl_seconds,
                section_name="liveActivities",
                now=now,
            )
        }
        return sorted(game_ids)

    def live_activity_start_token_count(self) -> int:
        data = self._load()
        tokens = data.get("liveActivityStartTokens", {})
        if not isinstance(tokens, dict):
            return 0
        now = self._registration_now()
        return sum(
            1
            for value in tokens.values()
            if isinstance(value, dict)
            and self._registration_is_active(
                value,
                ttl_seconds=self._live_activity_start_token_ttl_seconds,
                section_name="liveActivityStartTokens",
                now=now,
            )
        )

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

        now = self._registration_now()
        active_installations = self._live_activity_installation_ids_for_game(
            data,
            game_id,
            now=now,
        )
        registrations_by_installation: dict[str, list[dict[str, Any]]] = {}
        for registration in devices.values():
            if not isinstance(registration, dict):
                continue
            if not self._registration_is_active(
                registration,
                ttl_seconds=self._device_registration_ttl_seconds,
                section_name="devices",
                now=now,
            ):
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
            if not self._registration_is_active(
                registration,
                ttl_seconds=self._live_activity_start_token_ttl_seconds,
                section_name="liveActivityStartTokens",
                now=now,
            ):
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

    def prune_live_activity_start_token(
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

            tokens = data.setdefault("liveActivityStartTokens", {})
            registration = tokens.get(token) if isinstance(tokens, dict) else None
            if not isinstance(registration, dict):
                return False
            tokens.pop(token, None)
            self._remove_live_activity_start_token_states(data, token)
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

    def _live_activity_installation_ids_for_game(
        self,
        data: dict[str, Any],
        game_id: str,
        *,
        now: Optional[datetime] = None,
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
            and self._registration_is_active(
                activity,
                ttl_seconds=self._live_activity_registration_ttl_seconds,
                section_name="liveActivities",
                now=now,
            )
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
        now = self._registration_now()
        return any(
            isinstance(registration, dict)
            and self._registration_is_active(
                registration,
                ttl_seconds=self._device_registration_ttl_seconds,
                section_name="devices",
                now=now,
            )
            for registration in devices.values()
        )

    def has_device_token(self, device_token: str) -> bool:
        data = self._load()
        devices = data.get("devices", {})
        return device_token in devices

    def device_registration_owned_by(
        self,
        *,
        device_token: str,
        installation_id: str,
    ) -> bool:
        data = self._load()
        devices = data.get("devices", {})
        registration = devices.get(device_token) if isinstance(devices, dict) else None
        return (
            isinstance(registration, dict)
            and bool(installation_id)
            and _clean_optional_string(registration.get("installationId")) == installation_id
        )

    def claim_device_test(
        self,
        *,
        device_token: str,
        installation_id: str,
    ) -> dict[str, Any]:
        now = datetime.now(timezone.utc)
        with self._mutate_data() as data:
            devices = data.setdefault("devices", {})
            registration = devices.get(device_token) if isinstance(devices, dict) else None
            if not isinstance(registration, dict):
                return {"allowed": False, "status": "unregistered"}
            if (
                not installation_id
                or _clean_optional_string(registration.get("installationId")) != installation_id
            ):
                return {"allowed": False, "status": "ownership_mismatch"}

            states = data.get("deviceTestStates")
            if states is None:
                states = {}
            if not isinstance(states, dict):
                raise PushRegistryCorruptionError("invalid device test state section")
            state_id = _device_test_state_id(installation_id)
            state = states.get(state_id)
            if state is not None and not isinstance(state, dict):
                raise PushRegistryCorruptionError("invalid device test owner state")

            if isinstance(state, dict) and "attemptedAt" in state:
                attempted_at = _parse_iso_datetime(state.get("attemptedAt"))
                if attempted_at is None:
                    raise PushRegistryCorruptionError("invalid device test cooldown timestamp")
                elapsed = max(0.0, (now - attempted_at).total_seconds())
                if elapsed < self._device_test_cooldown_seconds:
                    return {
                        "allowed": False,
                        "status": "cooldown",
                        "retryAfterSeconds": max(
                            1,
                            math.ceil(self._device_test_cooldown_seconds - elapsed),
                        ),
                    }

            global_rate = data.get("deviceTestRateState")
            if global_rate is None:
                global_rate = {}
            if not isinstance(global_rate, dict):
                raise PushRegistryCorruptionError("invalid device test global rate state")
            raw_attempts = global_rate.get("attemptedAt")
            if raw_attempts is None:
                raw_attempts = []
            if not isinstance(raw_attempts, list):
                raise PushRegistryCorruptionError("invalid device test global timestamps")
            parsed_attempts = []
            for raw_attempt in raw_attempts:
                if not isinstance(raw_attempt, str):
                    raise PushRegistryCorruptionError("invalid device test global timestamp")
                parsed_attempt = _parse_iso_datetime(raw_attempt)
                if parsed_attempt is None:
                    raise PushRegistryCorruptionError("invalid device test global timestamp")
                if (now - parsed_attempt).total_seconds() < self._device_test_global_window_seconds:
                    parsed_attempts.append(parsed_attempt)
            recent_attempts = sorted(parsed_attempts)[-self._device_test_global_max_attempts :]
            if len(recent_attempts) >= self._device_test_global_max_attempts:
                oldest = recent_attempts[0]
                elapsed = max(0.0, (now - oldest).total_seconds())
                return {
                    "allowed": False,
                    "status": "global_cooldown",
                    "retryAfterSeconds": max(
                        1,
                        math.ceil(self._device_test_global_window_seconds - elapsed),
                    ),
                }

            if not isinstance(state, dict):
                state = {}
            data["deviceTestStates"] = states
            states[state_id] = state
            data["deviceTestRateState"] = global_rate
            recent_attempts.append(now)
            global_rate["attemptedAt"] = [attempted.isoformat() for attempted in recent_attempts]
            global_rate["updatedAt"] = now.isoformat()

            claim_id = uuid.uuid4().hex
            state.update(
                {
                    "installationId": installation_id,
                    "deviceTokenSuffix": device_token[-8:],
                    "claimId": claim_id,
                    "attemptedAt": now.isoformat(),
                    "updatedAt": now.isoformat(),
                }
            )
            return {
                "allowed": True,
                "status": "claimed",
                "claimId": claim_id,
            }

    def complete_device_test(
        self,
        *,
        device_token: str,
        installation_id: str,
        claim_id: str,
    ) -> bool:
        with self._mutate_data() as data:
            states = data.setdefault("deviceTestStates", {})
            state = (
                states.get(_device_test_state_id(installation_id))
                if isinstance(states, dict)
                else None
            )
            if not isinstance(state, dict) or state.get("claimId") != claim_id:
                return False
            state.pop("claimId", None)
            state["updatedAt"] = _now_iso()
            return True

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
        installation_id = _clean_optional_string(payload.installationId)
        if not device_token or not installation_id:
            return None

        with self._mutate_data() as data:
            devices = data.setdefault("devices", {})
            registration = devices.get(device_token)
            if (
                not isinstance(registration, dict)
                or _clean_optional_string(registration.get("installationId")) != installation_id
            ):
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
        now = self._registration_now()
        registrations = []
        for token, registration in devices.items():
            if not isinstance(registration, dict):
                continue
            if not self._registration_is_active(
                registration,
                ttl_seconds=self._device_registration_ttl_seconds,
                section_name="devices",
                now=now,
            ):
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
            now = self._scoreboard_now()
            updated_at = _next_scoreboard_updated_at(previous_updated_at, now)
            score_correction_confirmed = False
            if isinstance(previous, dict):
                correction_candidate = _live_score_correction_candidate(previous, state)
                if correction_candidate is not None:
                    persisted_candidate = previous.get(_SCORE_CORRECTION_CANDIDATE_KEY)
                    first_observed_at = _matching_score_correction_first_observed_at(
                        persisted_candidate,
                        correction_candidate,
                    )
                    if first_observed_at is None:
                        states[game_id] = {
                            **previous,
                            _SCORE_CORRECTION_CANDIDATE_KEY: {
                                **correction_candidate,
                                "firstObservedAt": now.isoformat(),
                            },
                            "updatedAt": updated_at,
                        }
                        return False
                    elapsed_seconds = (now - first_observed_at).total_seconds()
                    if elapsed_seconds < self._score_correction_confirmation_seconds:
                        return False
                    if not _scoreboard_state_can_advance(
                        previous,
                        state,
                        allow_live_score_correction=True,
                    ):
                        return False
                    score_correction_confirmed = True
                elif not _scoreboard_state_can_advance(previous, state):
                    if _SCORE_CORRECTION_CANDIDATE_KEY in previous:
                        cleared_state = dict(previous)
                        cleared_state.pop(_SCORE_CORRECTION_CANDIDATE_KEY, None)
                        cleared_state["updatedAt"] = updated_at
                        states[game_id] = cleared_state
                    return False
            if score_correction_confirmed:
                events[:] = [
                    event for event in events if not _is_score_correction_duplicate_moment(event)
                ]
            states[game_id] = {
                **state,
                "gameId": game_id,
                "updatedAt": updated_at,
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
            now = self._runtime_state_now()
            previous = data.get("syncHeartbeat")
            if isinstance(previous, dict):
                previous_updated_at = _parse_iso_datetime(previous.get("updatedAt"))
                previous_payload = {
                    key: value for key, value in previous.items() if key != "updatedAt"
                }
                age_seconds = (
                    (now - previous_updated_at).total_seconds()
                    if previous_updated_at is not None
                    else None
                )
                if (
                    previous_payload == payload
                    and age_seconds is not None
                    and 0 <= age_seconds < self._sync_heartbeat_min_write_interval_seconds
                ):
                    return previous
            heartbeat = {
                **payload,
                "updatedAt": now.isoformat(),
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
                original = deepcopy(data)
                try:
                    yield data
                except Exception:
                    raise
                else:
                    self._prune_runtime_state(data)
                    if data != original:
                        serialized = _serialize_registry(data)
                        updated_size = len(serialized.encode("utf-8"))
                        if (
                            updated_size > self._max_registry_bytes
                            and updated_size > _registry_size_bytes(original)
                        ):
                            raise PushRegistryCapacityError("registry byte capacity reached")
                        self._save_unlocked(data)

    def _prune_runtime_state(self, data: dict[str, Any]) -> None:
        now = self._runtime_state_now()
        for section_name in (
            "scoreboardStates",
            "relayStates",
            "pregameAlertStates",
            "scheduledAlertStates",
            "scheduledDeliveryStates",
            "liveActivityUpdateStates",
            "deviceTestStates",
        ):
            section = data.get(section_name)
            if isinstance(section, dict):
                _prune_timestamped_mapping(
                    section,
                    now=now,
                    ttl_seconds=self._runtime_state_ttl_seconds,
                )

        start_states = data.get("liveActivityStartStates")
        if isinstance(start_states, dict):
            _prune_nested_timestamped_mapping(
                start_states,
                now=now,
                ttl_seconds=self._runtime_state_ttl_seconds,
            )

        outbox = data.get("pushOutbox")
        if isinstance(outbox, dict):
            _prune_push_outbox_retention(
                outbox,
                now=now,
                pending_ttl_seconds=self._outbox_pending_ttl_seconds,
                pending_limit=self._max_pending_outbox_events,
            )

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
        except (json.JSONDecodeError, OSError) as error:
            raise PushRegistryCorruptionError("push registry is unreadable") from error

        if not isinstance(data, dict):
            raise PushRegistryCorruptionError("push registry root is invalid")

        defaults = _empty_registry()
        for section_name, default_value in defaults.items():
            section = data.get(section_name)
            if section is None and section_name not in data:
                data[section_name] = deepcopy(default_value)
                continue
            if not isinstance(section, type(default_value)):
                raise PushRegistryCorruptionError(
                    f"push registry section is invalid: {section_name}"
                )
        _validate_registry_owner_entries(
            data,
            section_name="devices",
            owner_fields=("installationId",),
        )
        _validate_registry_owner_entries(
            data,
            section_name="liveActivities",
            owner_fields=("gameId", "activityId", "installationId"),
        )
        _validate_registry_owner_entries(
            data,
            section_name="liveActivityStartTokens",
            owner_fields=("installationId",),
        )
        _validate_registration_admission_state(data)
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
                file.write(_serialize_registry(data))
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


def _live_activity_delivery_id(activity_push_token: str) -> str:
    return hashlib.sha256(activity_push_token.encode("utf-8")).hexdigest()


def _live_activity_update_revision(state: dict[str, Any]) -> int:
    revision = state.get("desiredRevision")
    if isinstance(revision, bool) or not isinstance(revision, int) or revision < 0:
        return 0
    return revision


def _prune_stale_registrations(
    registrations: dict[str, Any],
    *,
    now: datetime,
    ttl_seconds: int,
    preserve_tokens: set[str],
    section_name: str,
) -> list[tuple[str, dict[str, Any]]]:
    removed = []
    for token, registration in list(registrations.items()):
        last_seen_at = _registration_last_seen_at(
            registration,
            section_name=section_name,
        )
        if token in preserve_tokens:
            continue
        if last_seen_at is None:
            continue
        if (now - last_seen_at).total_seconds() < ttl_seconds:
            continue
        removed.append((token, registration))
        registrations.pop(token, None)
    return removed


def _registration_last_seen_at(
    registration: Any,
    *,
    section_name: str,
) -> Optional[datetime]:
    if not isinstance(registration, dict):
        raise PushRegistryCorruptionError(f"push registry registration is invalid: {section_name}")
    parsed_timestamps = {}
    for field_name in ("lastSeenAt", "updatedAt", "createdAt"):
        if field_name not in registration:
            continue
        raw_timestamp = registration[field_name]
        if not isinstance(raw_timestamp, str) or not raw_timestamp.strip():
            raise PushRegistryCorruptionError(
                f"push registry registration timestamp is invalid: {section_name}"
            )
        parsed_timestamp = _parse_iso_datetime(raw_timestamp)
        if parsed_timestamp is None:
            raise PushRegistryCorruptionError(
                f"push registry registration timestamp is invalid: {section_name}"
            )
        parsed_timestamps[field_name] = parsed_timestamp
    for field_name in ("lastSeenAt", "updatedAt", "createdAt"):
        if field_name in parsed_timestamps:
            return parsed_timestamps[field_name]
    return None


def _device_test_state_id(installation_id: str) -> str:
    return hashlib.sha256(installation_id.encode("utf-8")).hexdigest()


def _serialize_registry(data: dict[str, Any]) -> str:
    return f"{json.dumps(data, ensure_ascii=False, indent=2, sort_keys=True)}\n"


def _registry_size_bytes(data: dict[str, Any]) -> int:
    return len(_serialize_registry(data).encode("utf-8"))


def _validate_registry_owner_entries(
    data: dict[str, Any],
    *,
    section_name: str,
    owner_fields: tuple[str, ...],
) -> None:
    section = data[section_name]
    for token, registration in section.items():
        if not isinstance(token, str) or not token:
            raise PushRegistryCorruptionError(f"push registry token key is invalid: {section_name}")
        if not isinstance(registration, dict):
            raise PushRegistryCorruptionError(
                f"push registry registration is invalid: {section_name}"
            )
        for field_name in owner_fields:
            value = registration.get(field_name)
            if value is not None and not isinstance(value, str):
                raise PushRegistryCorruptionError(
                    f"push registry owner field is invalid: {section_name}.{field_name}"
                )


def _validate_registration_admission_state(data: dict[str, Any]) -> None:
    state = data["registrationAdmissionState"]
    raw_accepted_at = state.get("newOwnerAcceptedAt")
    if raw_accepted_at is not None:
        if not isinstance(raw_accepted_at, list):
            raise PushRegistryCorruptionError("registration admission timestamps are invalid")
        for raw_timestamp in raw_accepted_at:
            if not isinstance(raw_timestamp, str) or _parse_iso_datetime(raw_timestamp) is None:
                raise PushRegistryCorruptionError("registration admission timestamp is invalid")
    if "updatedAt" in state:
        updated_at = state["updatedAt"]
        if not isinstance(updated_at, str) or _parse_iso_datetime(updated_at) is None:
            raise PushRegistryCorruptionError("registration admission timestamp is invalid")


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
        "liveActivityUpdateStates": {},
        "deviceTestStates": {},
        "deviceTestRateState": {},
        "registrationAdmissionState": {},
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


def _prune_timestamped_mapping(
    values: dict[str, Any],
    *,
    now: datetime,
    ttl_seconds: int,
) -> None:
    for key, value in list(values.items()):
        if not isinstance(value, dict):
            continue
        timestamp = _state_timestamp(value)
        if timestamp is None:
            continue
        if (now - timestamp).total_seconds() >= ttl_seconds:
            values.pop(key, None)


def _prune_nested_timestamped_mapping(
    values: dict[str, Any],
    *,
    now: datetime,
    ttl_seconds: int,
) -> None:
    """Prune token-scoped state nested below a game key."""
    for parent_key, nested in list(values.items()):
        if not isinstance(nested, dict):
            continue
        for child_key, value in list(nested.items()):
            if not isinstance(value, dict):
                continue
            timestamp = _state_timestamp(value)
            if timestamp is None:
                continue
            if (now - timestamp).total_seconds() >= ttl_seconds:
                nested.pop(child_key, None)
        if not nested:
            values.pop(parent_key, None)


def _state_timestamp(value: dict[str, Any]) -> Optional[datetime]:
    for field_name in ("updatedAt", "createdAt", "recordedAt"):
        raw_value = value.get(field_name)
        if isinstance(raw_value, str) and raw_value.strip():
            parsed = _parse_iso_datetime(raw_value)
            if parsed is not None:
                return parsed
    return None


def _push_outbox_has_active_claim(event: dict[str, Any], now: datetime) -> bool:
    targets = event.get("targets")
    if not isinstance(targets, dict):
        return False
    for target_state in targets.values():
        if not isinstance(target_state, dict) or target_state.get("status") != "sending":
            continue
        claimed_at = _parse_iso_datetime(target_state.get("claimedAt"))
        lease_age_seconds = (now - claimed_at).total_seconds() if claimed_at is not None else None
        if lease_age_seconds is not None and lease_age_seconds < _PUSH_OUTBOX_TARGET_LEASE_SECONDS:
            return True
    return False


def _prune_push_outbox_retention(
    outbox: dict[str, Any],
    *,
    now: datetime,
    pending_ttl_seconds: int,
    pending_limit: int,
) -> None:
    _prune_completed_push_outbox(outbox)

    pending: list[dict[str, Any]] = []
    for event_id, event in list(outbox.items()):
        if not isinstance(event, dict) or _push_outbox_event_complete(event):
            continue
        if _push_outbox_has_active_claim(event, now):
            pending.append(event)
            continue
        timestamp = _state_timestamp(event)
        if timestamp is not None and (now - timestamp).total_seconds() >= pending_ttl_seconds:
            outbox.pop(str(event_id), None)
            continue
        pending.append(event)

    if len(pending) <= pending_limit:
        return

    pending.sort(
        key=lambda event: (
            str(event.get("updatedAt") or event.get("createdAt") or ""),
            str(event.get("eventId") or ""),
        )
    )
    removable = [event for event in pending if not _push_outbox_has_active_claim(event, now)]
    for event in removable[: max(0, len(pending) - pending_limit)]:
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
    *,
    allow_live_score_correction: bool = False,
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
            and not allow_live_score_correction
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


def _live_score_correction_candidate(
    previous: dict[str, Any],
    current: dict[str, Any],
) -> Optional[dict[str, int]]:
    previous_status = str(previous.get("status") or "").upper()
    current_status = str(current.get("status") or "").upper()
    if previous_status not in {"LIVE", "SUSPENDED"} or current_status not in {
        "LIVE",
        "SUSPENDED",
    }:
        return None

    previous_score_state = _last_verified_registry_score_state(previous)
    if previous_score_state is None:
        return None
    previous_away = _optional_registry_int(previous_score_state.get("awayScore"))
    previous_home = _optional_registry_int(previous_score_state.get("homeScore"))
    current_away = _optional_registry_int(current.get("awayScore"))
    current_home = _optional_registry_int(current.get("homeScore"))
    if None in (previous_away, previous_home, current_away, current_home):
        return None
    if current_away >= previous_away and current_home >= previous_home:
        return None
    return {
        "awayScore": current_away,
        "homeScore": current_home,
    }


def _matching_score_correction_first_observed_at(
    persisted_candidate: Any,
    current_candidate: dict[str, int],
) -> Optional[datetime]:
    if not isinstance(persisted_candidate, dict):
        return None
    if (
        _optional_registry_int(persisted_candidate.get("awayScore"))
        != current_candidate["awayScore"]
        or _optional_registry_int(persisted_candidate.get("homeScore"))
        != current_candidate["homeScore"]
    ):
        return None
    return _parse_iso_datetime(persisted_candidate.get("firstObservedAt"))


def _next_scoreboard_updated_at(previous_updated_at: Any, now: datetime) -> str:
    previous = _parse_iso_datetime(previous_updated_at)
    if previous is not None and now <= previous:
        now = previous + timedelta(microseconds=1)
    return now.isoformat()


def _is_score_correction_duplicate_moment(event: dict[str, Any]) -> bool:
    payload = event.get("payload")
    if not isinstance(payload, dict):
        return False
    return str(payload.get("moment") or "") in {"scoring", "reversal"}


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
