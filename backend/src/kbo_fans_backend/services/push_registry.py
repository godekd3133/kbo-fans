from __future__ import annotations

import fcntl
import json
import os
import tempfile
import threading
from contextlib import contextmanager
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Iterator, Optional

from kbo_fans_backend.core.config import get_settings
from kbo_fans_backend.schemas.push import (
    LiveActivityRegisterRequest,
    LiveActivityUnregisterRequest,
    PushReceiptRequest,
    PushRegisterRequest,
)


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
                "platform": payload.platform,
                "updatedAt": now,
                "createdAt": existing.get("createdAt", now),
            }
            return activities[payload.activityPushToken]

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

    def live_activity_game_ids(self) -> list[str]:
        data = self._load()
        activities = data.get("liveActivities", {})
        game_ids = {
            str(activity.get("gameId"))
            for activity in activities.values()
            if activity.get("gameId")
        }
        return sorted(game_ids)

    def has_device_registrations(self) -> bool:
        data = self._load()
        devices = data.get("devices", {})
        return bool(devices)

    def has_device_token(self, device_token: str) -> bool:
        data = self._load()
        devices = data.get("devices", {})
        return device_token in devices

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

    def replace_scoreboard_state(
        self,
        game_id: str,
        state: dict[str, Any],
    ) -> Optional[dict[str, Any]]:
        with self._mutate_data() as data:
            states = data.setdefault("scoreboardStates", {})
            previous = states.get(game_id)
            states[game_id] = {
                **state,
                "gameId": game_id,
                "updatedAt": _now_iso(),
            }
            return previous if isinstance(previous, dict) else None

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
        with self._mutate_data() as data:
            states = data.setdefault("relayStates", {})
            previous = states.get(game_id)
            states[game_id] = {
                **state,
                "gameId": game_id,
                "updatedAt": _now_iso(),
            }
            return previous if isinstance(previous, dict) else None

    def pregame_alert_sent(self, game_id: str, alert_key: str) -> bool:
        data = self._load()
        states = data.get("pregameAlertStates", {})
        state = states.get(game_id)
        if not isinstance(state, dict):
            return False
        return str(state.get("alertKey") or "") == alert_key

    def mark_pregame_alert_sent(self, game_id: str, alert_key: str) -> dict[str, Any]:
        with self._mutate_data() as data:
            states = data.setdefault("pregameAlertStates", {})
            state = {
                "gameId": game_id,
                "alertKey": alert_key,
                "updatedAt": _now_iso(),
            }
            states[game_id] = state
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
        data.setdefault("pregameAlertStates", {})
        data.setdefault("pushReceipts", [])
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
        "pregameAlertStates": {},
        "pushReceipts": [],
        "syncHeartbeat": {},
    }


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


def _receipt_data(values: dict[str, Any]) -> dict[str, str]:
    allowed = {"topic", "collapseKey", "kind"}
    cleaned: dict[str, str] = {}
    for key, value in values.items():
        key_text = str(key)
        if key_text not in allowed:
            continue
        cleaned[key_text] = str(value)[:200]
    return cleaned
