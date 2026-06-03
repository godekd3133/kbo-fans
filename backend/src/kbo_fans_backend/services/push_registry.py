from __future__ import annotations

import json
import threading
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Optional

from kbo_fans_backend.core.config import get_settings
from kbo_fans_backend.schemas.push import (
    LiveActivityRegisterRequest,
    LiveActivityUnregisterRequest,
    PushRegisterRequest,
)


class PushRegistry:
    def __init__(self, path: Optional[str] = None) -> None:
        self.path = Path(path or get_settings().push_registry_path).expanduser()
        self._lock = threading.Lock()

    def save_device_registration(
        self,
        payload: PushRegisterRequest,
        topics: list[str],
    ) -> dict[str, Any]:
        with self._lock:
            data = self._load()
            devices = data.setdefault("devices", {})
            now = _now_iso()
            existing = devices.get(payload.deviceToken, {})
            devices[payload.deviceToken] = {
                **existing,
                "deviceToken": payload.deviceToken,
                "platform": payload.platform,
                "myTeam": payload.myTeam,
                "notifications": _model_to_dict(payload.notifications),
                "topics": topics,
                "updatedAt": now,
                "createdAt": existing.get("createdAt", now),
            }
            self._save(data)
            return devices[payload.deviceToken]

    def save_live_activity(
        self,
        payload: LiveActivityRegisterRequest,
    ) -> dict[str, Any]:
        with self._lock:
            data = self._load()
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
            self._save(data)
            return activities[payload.activityPushToken]

    def remove_live_activity(
        self,
        payload: LiveActivityUnregisterRequest,
    ) -> int:
        with self._lock:
            data = self._load()
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

            self._save(data)
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

    def replace_scoreboard_state(
        self,
        game_id: str,
        state: dict[str, Any],
    ) -> Optional[dict[str, Any]]:
        with self._lock:
            data = self._load()
            states = data.setdefault("scoreboardStates", {})
            previous = states.get(game_id)
            states[game_id] = {
                **state,
                "gameId": game_id,
                "updatedAt": _now_iso(),
            }
            self._save(data)
            return previous if isinstance(previous, dict) else None

    def record_sync_heartbeat(self, payload: dict[str, Any]) -> dict[str, Any]:
        with self._lock:
            data = self._load()
            heartbeat = {
                **payload,
                "updatedAt": _now_iso(),
            }
            data["syncHeartbeat"] = heartbeat
            self._save(data)
            return heartbeat

    def sync_heartbeat(self) -> dict[str, Any]:
        data = self._load()
        heartbeat = data.get("syncHeartbeat")
        return heartbeat if isinstance(heartbeat, dict) else {}

    def _load(self) -> dict[str, Any]:
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
        data.setdefault("syncHeartbeat", {})
        return data

    def _save(self, data: dict[str, Any]) -> None:
        self.path.parent.mkdir(parents=True, exist_ok=True)
        self.path.write_text(
            json.dumps(data, ensure_ascii=False, indent=2, sort_keys=True),
            encoding="utf-8",
        )


def _now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def _empty_registry() -> dict[str, Any]:
    return {"devices": {}, "liveActivities": {}, "scoreboardStates": {}, "syncHeartbeat": {}}


def _model_to_dict(model: Any) -> dict[str, Any]:
    if hasattr(model, "model_dump"):
        return model.model_dump()
    return model.dict()
