from __future__ import annotations

import json
import os
from collections import Counter
from pathlib import Path
from typing import Any, Optional

from kbo_fans_backend.core.config import Settings, get_settings
from kbo_fans_backend.services.push_registry import PushRegistry


class PushConfigurationDiagnostics:
    def __init__(self, settings: Optional[Settings] = None) -> None:
        self.settings = settings or get_settings()

    def status(self) -> dict[str, Any]:
        firebase = self._firebase_status()
        apns = self._apns_status()
        registry = self._registry_status()
        scheduler = self._scheduler_status()
        missing = [
            *firebase["missing"],
            *apns["missing"],
            *registry["missing"],
            *scheduler["missing"],
        ]

        return {
            "appEnv": self.settings.app_env,
            "ready": not missing,
            "readyForIphoneOnlyDemo": not missing and not apns["sandbox"],
            "firebase": _without_missing(firebase),
            "apns": _without_missing(apns),
            "registry": _without_missing(registry),
            "scheduler": _without_missing(scheduler),
            "missing": missing,
        }

    def _firebase_status(self) -> dict[str, Any]:
        service_account = _file_status(self.settings.firebase_service_account_path)
        service_account_json = _json_object_status(self.settings.firebase_service_account_json)
        missing = []
        if service_account_json["configured"] and not service_account_json["valid"]:
            missing.append("FIREBASE_SERVICE_ACCOUNT_JSON:json")
        elif not service_account_json["configured"] and not service_account["configured"]:
            missing.append("FIREBASE_SERVICE_ACCOUNT_JSON|FIREBASE_SERVICE_ACCOUNT_PATH")
        elif service_account["configured"] and not service_account["exists"]:
            missing.append("FIREBASE_SERVICE_ACCOUNT_PATH:file")

        return {
            "serviceAccountPathConfigured": service_account["configured"],
            "serviceAccountFileExists": service_account["exists"],
            "serviceAccountFilename": service_account["filename"],
            "serviceAccountJsonConfigured": service_account_json["configured"],
            "serviceAccountJsonValid": service_account_json["valid"],
            "projectIdConfigured": bool(self.settings.firebase_project_id),
            "ready": not missing,
            "missing": missing,
        }

    def _apns_status(self) -> dict[str, Any]:
        auth_key = _file_status(self.settings.apns_auth_key_path)
        auth_key_content_configured = bool(self.settings.apns_auth_key_p8)
        fields = {
            "APNS_KEY_ID": bool(self.settings.apns_key_id),
            "APNS_TEAM_ID": bool(self.settings.apns_team_id),
            "APNS_BUNDLE_ID": bool(self.settings.apns_bundle_id),
        }
        missing = [name for name, configured in fields.items() if not configured]
        if not auth_key_content_configured and not auth_key["configured"]:
            missing.append("APNS_AUTH_KEY_P8|APNS_AUTH_KEY_PATH")
        elif auth_key["configured"] and not auth_key["exists"]:
            missing.append("APNS_AUTH_KEY_PATH:file")
        if self.settings.apns_use_sandbox:
            missing.append("APNS_USE_SANDBOX=false")

        return {
            "keyIdConfigured": fields["APNS_KEY_ID"],
            "teamIdConfigured": fields["APNS_TEAM_ID"],
            "bundleId": self.settings.apns_bundle_id,
            "authKeyPathConfigured": auth_key["configured"],
            "authKeyFileExists": auth_key["exists"],
            "authKeyFilename": auth_key["filename"],
            "authKeyContentConfigured": auth_key_content_configured,
            "sandbox": self.settings.apns_use_sandbox,
            "productionEndpoint": not self.settings.apns_use_sandbox,
            "ready": not missing,
            "missing": missing,
        }

    def _registry_status(self) -> dict[str, Any]:
        registry = _writable_path_status(self.settings.push_registry_path)
        runtime = self._registry_runtime_status()
        missing = []
        if not registry["configured"]:
            missing.append("PUSH_REGISTRY_PATH")
        elif not registry["parentWritable"]:
            missing.append("PUSH_REGISTRY_PATH:writable")

        return {
            "pathConfigured": registry["configured"],
            "fileExists": registry["exists"],
            "parentExists": registry["parentExists"],
            "parentWritable": registry["parentWritable"],
            "filename": registry["filename"],
            **runtime,
            "ready": not missing,
            "missing": missing,
        }

    def _registry_runtime_status(self) -> dict[str, Any]:
        try:
            registry = PushRegistry(self.settings.push_registry_path)
            registrations = registry.device_registrations()
            live_activity_game_ids = registry.live_activity_game_ids()
            recent_push_receipts = registry.recent_push_receipts()
        except Exception as exc:
            return {
                "readable": False,
                "readError": exc.__class__.__name__,
                "registeredDeviceCount": 0,
                "activeLiveActivityGameCount": 0,
                "followedGameCount": 0,
                "topicCounts": {},
                "myTeamCounts": {},
                "pushReceiptCount": 0,
                "recentPushReceipts": [],
            }

        topic_counts: Counter[str] = Counter()
        my_team_counts: Counter[str] = Counter()
        followed_game_ids: set[str] = set()
        for registration in registrations:
            topics = registration.get("topics")
            if isinstance(topics, list):
                for topic in topics:
                    topic_text = str(topic).strip()
                    if topic_text:
                        topic_counts[topic_text] += 1

            my_team = str(registration.get("myTeam") or "").strip()
            if my_team:
                my_team_counts[my_team] += 1

            followed = registration.get("followedGameIds")
            if isinstance(followed, list):
                for game_id in followed:
                    game_id_text = str(game_id).strip()
                    if game_id_text:
                        followed_game_ids.add(game_id_text)

        return {
            "readable": True,
            "readError": "",
            "registeredDeviceCount": len(registrations),
            "activeLiveActivityGameCount": len(live_activity_game_ids),
            "followedGameCount": len(followed_game_ids),
            "topicCounts": dict(sorted(topic_counts.items())),
            "myTeamCounts": dict(sorted(my_team_counts.items())),
            "pushReceiptCount": len(recent_push_receipts),
            "recentPushReceipts": recent_push_receipts,
        }

    def _scheduler_status(self) -> dict[str, Any]:
        missing = []
        if not self.settings.push_sync_secret:
            missing.append("PUSH_SYNC_SECRET")
        registry_error = ""
        try:
            heartbeat = PushRegistry(self.settings.push_registry_path).sync_heartbeat()
        except Exception as exc:
            heartbeat = {}
            registry_error = exc.__class__.__name__
            missing.append("PUSH_REGISTRY_PATH:readable")

        return {
            "syncSecretConfigured": bool(self.settings.push_sync_secret),
            "syncEndpointProtected": bool(self.settings.push_sync_secret),
            "registryReadable": not registry_error,
            "registryError": registry_error,
            "lastSyncAt": heartbeat.get("updatedAt"),
            "lastSyncDate": heartbeat.get("date"),
            "lastCheckedGames": heartbeat.get("checkedGames"),
            "lastUpdatedGames": heartbeat.get("updatedGames"),
            "lastPushedMoments": heartbeat.get("pushedMoments"),
            "ready": not missing,
            "missing": missing,
        }


def _file_status(raw_path: str) -> dict[str, Any]:
    configured = bool(raw_path)
    if not configured:
        return {"configured": False, "exists": False, "filename": ""}
    path = Path(raw_path).expanduser()
    return {
        "configured": True,
        "exists": path.is_file(),
        "filename": path.name,
    }


def _json_object_status(raw_json: str) -> dict[str, Any]:
    configured = bool(raw_json)
    if not configured:
        return {"configured": False, "valid": False}
    try:
        payload = json.loads(raw_json)
    except json.JSONDecodeError:
        return {"configured": True, "valid": False}
    return {"configured": True, "valid": isinstance(payload, dict)}


def _writable_path_status(raw_path: str) -> dict[str, Any]:
    configured = bool(raw_path)
    if not configured:
        return {
            "configured": False,
            "exists": False,
            "parentExists": False,
            "parentWritable": False,
            "filename": "",
        }

    path = Path(raw_path).expanduser()
    parent = path.parent
    nearest = _nearest_existing_parent(parent)
    return {
        "configured": True,
        "exists": path.exists(),
        "parentExists": parent.exists(),
        "parentWritable": nearest is not None and os.access(str(nearest), os.W_OK),
        "filename": path.name,
    }


def _nearest_existing_parent(path: Path) -> Optional[Path]:
    current = path
    while True:
        if current.exists():
            return current
        if current == current.parent:
            return None
        current = current.parent


def _without_missing(payload: dict[str, Any]) -> dict[str, Any]:
    return {key: value for key, value in payload.items() if key != "missing"}
