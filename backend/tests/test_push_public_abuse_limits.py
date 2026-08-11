from __future__ import annotations

import hashlib
import json
from datetime import datetime, timedelta, timezone

import pytest
from fastapi.testclient import TestClient

from kbo_fans_backend.api.routes import push as push_routes
from kbo_fans_backend.main import app
from kbo_fans_backend.schemas.push import (
    LiveActivityRegisterRequest,
    LiveActivityStartTokenRegisterRequest,
    NotificationSettings,
    PushDeviceTestRequest,
    PushReceiptRequest,
    PushRegisterRequest,
)
from kbo_fans_backend.services.push import PushService
from kbo_fans_backend.services.push_registry import (
    PushRegistry,
    PushRegistryCorruptionError,
)


class _FakeNotification:
    def __init__(self, *, title: str, body: str) -> None:
        self.title = title
        self.body = body


class _FakeMessage:
    def __init__(self, **kwargs) -> None:
        self.__dict__.update(kwargs)


class _FakeMessaging:
    Notification = _FakeNotification
    Message = _FakeMessage

    class ApsAlert:
        def __init__(self, **kwargs) -> None:
            self.__dict__.update(kwargs)

    class Aps:
        def __init__(self, **kwargs) -> None:
            self.__dict__.update(kwargs)

    class APNSPayload:
        def __init__(self, **kwargs) -> None:
            self.__dict__.update(kwargs)

    class APNSConfig:
        def __init__(self, **kwargs) -> None:
            self.__dict__.update(kwargs)

    class AndroidNotification:
        def __init__(self, **kwargs) -> None:
            self.__dict__.update(kwargs)

    class AndroidConfig:
        def __init__(self, **kwargs) -> None:
            self.__dict__.update(kwargs)

    def __init__(self) -> None:
        self.sent_messages = []

    def send(self, message) -> str:
        self.sent_messages.append(message)
        return "message-1"


def _notification_settings() -> NotificationSettings:
    return NotificationSettings(
        gameStart=True,
        scoring=True,
        homerun=True,
        reversal=True,
        gameEnd=True,
        allGames=False,
    )


def test_device_self_test_requires_exact_registered_installation(tmp_path) -> None:
    registry = PushRegistry(str(tmp_path / "push_registry.json"))
    service = PushService(registry=registry)
    messaging = _FakeMessaging()
    service._get_messaging = lambda: messaging
    service.register(
        PushRegisterRequest(
            deviceToken="registered-token",
            installationId="installation-owner",
            platform="ios",
            notifications=_notification_settings(),
        )
    )

    response = service.send_device_test(
        PushDeviceTestRequest(
            deviceToken="registered-token",
            installationId="installation-attacker",
        )
    )

    assert response == {
        "sent": False,
        "registered": False,
        "reason": "device token ownership does not match",
    }
    assert messaging.sent_messages == []


def test_device_self_test_cooldown_persists_across_registry_instances(tmp_path) -> None:
    registry_path = str(tmp_path / "push_registry.json")
    first_registry = PushRegistry(
        registry_path,
        device_test_cooldown_seconds=300,
    )
    first_service = PushService(registry=first_registry)
    first_messaging = _FakeMessaging()
    first_service._get_messaging = lambda: first_messaging
    first_service.register(
        PushRegisterRequest(
            deviceToken="registered-token",
            installationId="installation-owner",
            platform="ios",
            notifications=_notification_settings(),
        )
    )

    first = first_service.send_device_test(
        PushDeviceTestRequest(
            deviceToken="registered-token",
            installationId="installation-owner",
        )
    )

    second_registry = PushRegistry(
        registry_path,
        device_test_cooldown_seconds=300,
    )
    second_service = PushService(registry=second_registry)
    second_messaging = _FakeMessaging()
    second_service._get_messaging = lambda: second_messaging
    second = second_service.send_device_test(
        PushDeviceTestRequest(
            deviceToken="registered-token",
            installationId="installation-owner",
        )
    )

    assert first["sent"] is True
    assert len(first_messaging.sent_messages) == 1
    assert second["sent"] is False
    assert second["registered"] is True
    assert second["reason"] == "device test cooldown is active"
    assert second["retryAfterSeconds"] > 0
    assert second_messaging.sent_messages == []


def test_device_self_test_global_window_persists_across_registry_instances(
    tmp_path,
) -> None:
    registry_path = str(tmp_path / "push_registry.json")
    first_registry = PushRegistry(
        registry_path,
        device_test_cooldown_seconds=1,
        device_test_global_window_seconds=300,
        device_test_global_max_attempts=1,
    )
    first_service = PushService(registry=first_registry)
    first_messaging = _FakeMessaging()
    first_service._get_messaging = lambda: first_messaging
    for suffix in ("a", "b"):
        first_service.register(
            PushRegisterRequest(
                deviceToken=f"registered-token-{suffix}",
                installationId=f"installation-{suffix}",
                platform="ios",
                notifications=_notification_settings(),
            )
        )

    first = first_service.send_device_test(
        PushDeviceTestRequest(
            deviceToken="registered-token-a",
            installationId="installation-a",
        )
    )

    second_registry = PushRegistry(
        registry_path,
        device_test_cooldown_seconds=1,
        device_test_global_window_seconds=300,
        device_test_global_max_attempts=1,
    )
    second_service = PushService(registry=second_registry)
    second_messaging = _FakeMessaging()
    second_service._get_messaging = lambda: second_messaging
    second = second_service.send_device_test(
        PushDeviceTestRequest(
            deviceToken="registered-token-b",
            installationId="installation-b",
        )
    )

    assert first["sent"] is True
    assert second["sent"] is False
    assert second["reason"] == "device test global rate limit is active"
    assert second["retryAfterSeconds"] > 0
    assert second_messaging.sent_messages == []


def test_device_self_test_cooldown_survives_token_rotation(tmp_path) -> None:
    registry = PushRegistry(
        str(tmp_path / "push_registry.json"),
        device_test_cooldown_seconds=300,
    )
    service = PushService(registry=registry)
    messaging = _FakeMessaging()
    service._get_messaging = lambda: messaging
    service.register(
        PushRegisterRequest(
            deviceToken="owner-old-token",
            installationId="installation-owner",
            platform="ios",
            notifications=_notification_settings(),
        )
    )
    first = service.send_device_test(
        PushDeviceTestRequest(
            deviceToken="owner-old-token",
            installationId="installation-owner",
        )
    )
    service.register(
        PushRegisterRequest(
            deviceToken="owner-new-token",
            installationId="installation-owner",
            platform="ios",
            notifications=_notification_settings(),
        )
    )

    second = service.send_device_test(
        PushDeviceTestRequest(
            deviceToken="owner-new-token",
            installationId="installation-owner",
        )
    )

    assert first["sent"] is True
    assert second["sent"] is False
    assert second["reason"] == "device test cooldown is active"
    assert len(messaging.sent_messages) == 1


def test_unregistered_device_self_test_is_registry_disk_noop(tmp_path) -> None:
    registry_path = tmp_path / "push_registry.json"
    registry = PushRegistry(str(registry_path))
    service = PushService(registry=registry)
    service.register(
        PushRegisterRequest(
            deviceToken="registered-token",
            installationId="installation-owner",
            platform="ios",
            notifications=_notification_settings(),
        )
    )
    before = registry_path.read_bytes()

    response = service.send_device_test(
        PushDeviceTestRequest(
            deviceToken="missing-token",
            installationId="installation-attacker",
        )
    )

    assert response["sent"] is False
    assert registry_path.read_bytes() == before


def test_global_device_self_test_denial_is_registry_disk_noop(tmp_path) -> None:
    registry_path = tmp_path / "push_registry.json"
    registry = PushRegistry(
        str(registry_path),
        device_test_cooldown_seconds=1,
        device_test_global_window_seconds=300,
        device_test_global_max_attempts=1,
    )
    service = PushService(registry=registry)
    messaging = _FakeMessaging()
    service._get_messaging = lambda: messaging
    for suffix in ("a", "b"):
        service.register(
            PushRegisterRequest(
                deviceToken=f"registered-token-{suffix}",
                installationId=f"installation-{suffix}",
                platform="ios",
                notifications=_notification_settings(),
            )
        )
    service.send_device_test(
        PushDeviceTestRequest(
            deviceToken="registered-token-a",
            installationId="installation-a",
        )
    )
    before = registry_path.read_bytes()

    denied = service.send_device_test(
        PushDeviceTestRequest(
            deviceToken="registered-token-b",
            installationId="installation-b",
        )
    )

    assert denied["reason"] == "device test global rate limit is active"
    assert registry_path.read_bytes() == before


def test_device_registry_rejects_new_owner_at_cap_but_allows_token_rotation(
    tmp_path,
) -> None:
    registry = PushRegistry(
        str(tmp_path / "push_registry.json"),
        max_devices=2,
    )
    service = PushService(registry=registry)

    def register(token: str, installation_id: str) -> None:
        service.register(
            PushRegisterRequest(
                deviceToken=token,
                installationId=installation_id,
                platform="ios",
                notifications=_notification_settings(),
            )
        )

    register("owner-a-old-token", "installation-a")
    register("owner-b-token", "installation-b")
    register("owner-a-new-token", "installation-a")

    with pytest.raises(RuntimeError, match="device registration capacity reached"):
        register("owner-c-token", "installation-c")

    assert [registration["deviceToken"] for registration in registry.device_registrations()] == [
        "owner-a-new-token",
        "owner-b-token",
    ]


def test_new_owner_admission_window_persists_but_allows_exact_owner_refresh_and_rotation(
    tmp_path,
) -> None:
    registry_path = str(tmp_path / "push_registry.json")
    registry_options = {
        "registration_new_owner_window_seconds": 300,
        "registration_new_owner_max_attempts": 2,
    }
    service = PushService(registry=PushRegistry(registry_path, **registry_options))

    def register(service: PushService, token: str, installation_id: str) -> None:
        service.register(
            PushRegisterRequest(
                deviceToken=token,
                installationId=installation_id,
                platform="ios",
                notifications=_notification_settings(),
            )
        )

    register(service, "owner-a-token", "installation-a")
    register(service, "owner-b-token", "installation-b")
    restarted = PushService(registry=PushRegistry(registry_path, **registry_options))
    register(restarted, "owner-a-token", "installation-a")
    register(restarted, "owner-a-rotated-token", "installation-a")
    before_denial = (tmp_path / "push_registry.json").read_bytes()

    with pytest.raises(RuntimeError, match="new owner registration rate limit reached"):
        register(restarted, "owner-c-token", "installation-c")

    assert (tmp_path / "push_registry.json").read_bytes() == before_denial
    assert [
        registration["deviceToken"] for registration in restarted.registry.device_registrations()
    ] == ["owner-a-rotated-token", "owner-b-token"]


def test_new_owner_admission_reopens_after_persisted_window(tmp_path) -> None:
    now = [datetime(2026, 8, 10, 12, 0, tzinfo=timezone.utc)]
    registry = PushRegistry(
        str(tmp_path / "push_registry.json"),
        registration_new_owner_window_seconds=60,
        registration_new_owner_max_attempts=1,
        registration_now_provider=lambda: now[0],
    )
    service = PushService(registry=registry)

    def register(token: str, installation_id: str) -> None:
        service.register(
            PushRegisterRequest(
                deviceToken=token,
                installationId=installation_id,
                platform="ios",
                notifications=_notification_settings(),
            )
        )

    register("owner-a-token", "installation-a")
    with pytest.raises(RuntimeError, match="new owner registration rate limit reached"):
        register("owner-b-token", "installation-b")

    now[0] += timedelta(seconds=61)
    register("owner-b-token", "installation-b")

    assert [registration["deviceToken"] for registration in registry.device_registrations()] == [
        "owner-a-token",
        "owner-b-token",
    ]


def test_ownerless_legacy_device_tokens_cannot_share_an_admission_exemption(tmp_path) -> None:
    registry = PushRegistry(
        str(tmp_path / "push_registry.json"),
        registration_new_owner_window_seconds=300,
        registration_new_owner_max_attempts=1,
    )
    service = PushService(registry=registry)

    def register(token: str) -> None:
        service.register(
            PushRegisterRequest(
                deviceToken=token,
                platform="ios",
                notifications=_notification_settings(),
            )
        )

    register("legacy-token-a")
    register("legacy-token-a")
    with pytest.raises(RuntimeError, match="new owner registration rate limit reached"):
        register("legacy-token-b")

    assert [registration["deviceToken"] for registration in registry.device_registrations()] == [
        "legacy-token-a"
    ]


def test_device_gc_preserves_cooldown_state_when_a_fresh_legacy_owner_token_remains(
    tmp_path,
) -> None:
    now = datetime(2026, 8, 10, 12, 0, tzinfo=timezone.utc)
    registry_path = tmp_path / "push_registry.json"
    registry = PushRegistry(
        str(registry_path),
        device_registration_ttl_seconds=60,
        registration_now_provider=lambda: now,
    )
    data = registry._load()
    data["devices"] = {
        "owner-stale-token": {
            "deviceToken": "owner-stale-token",
            "installationId": "installation-owner",
            "updatedAt": (now - timedelta(seconds=61)).isoformat(),
        },
        "owner-fresh-token": {
            "deviceToken": "owner-fresh-token",
            "installationId": "installation-owner",
            "updatedAt": now.isoformat(),
        },
    }
    owner_state_id = hashlib.sha256(b"installation-owner").hexdigest()
    data["deviceTestStates"] = {
        owner_state_id: {
            "installationId": "installation-owner",
            "attemptedAt": now.isoformat(),
        }
    }
    registry_path.write_text(json.dumps(data), encoding="utf-8")
    service = PushService(registry=registry)

    service.register(
        PushRegisterRequest(
            deviceToken="new-owner-token",
            installationId="installation-new",
            platform="ios",
            notifications=_notification_settings(),
        )
    )

    data = registry._load()
    assert set(data["devices"]) == {"owner-fresh-token", "new-owner-token"}
    assert owner_state_id in data["deviceTestStates"]


def test_device_registration_cannot_reassign_an_existing_token_owner(tmp_path) -> None:
    registry = PushRegistry(str(tmp_path / "push_registry.json"))
    service = PushService(registry=registry)
    original = PushRegisterRequest(
        deviceToken="victim-token",
        installationId="installation-owner",
        platform="ios",
        notifications=_notification_settings(),
    )
    service.register(original)

    with pytest.raises(RuntimeError, match="device token ownership conflict"):
        service.register(
            PushRegisterRequest(
                deviceToken="victim-token",
                installationId="installation-attacker",
                platform="ios",
                notifications=_notification_settings(),
            )
        )

    assert registry.device_registration_owned_by(
        device_token="victim-token",
        installation_id="installation-owner",
    )


def test_owned_device_refresh_without_installation_is_rejected(tmp_path) -> None:
    registry = PushRegistry(str(tmp_path / "push_registry.json"))
    service = PushService(registry=registry)
    service.register(
        PushRegisterRequest(
            deviceToken="existing-token",
            installationId="installation-owner",
            platform="ios",
            myTeam="LG",
            notifications=_notification_settings(),
        )
    )

    with pytest.raises(RuntimeError, match="device token ownership conflict"):
        service.register(
            PushRegisterRequest(
                deviceToken="existing-token",
                platform="ios",
                myTeam="KT",
                notifications=_notification_settings(),
            )
        )

    registration = registry.device_registrations()[0]
    assert registration["installationId"] == "installation-owner"
    assert registration["myTeam"] == "LG"


def test_start_token_registry_caps_owners_and_preserves_rotation(tmp_path) -> None:
    registry = PushRegistry(
        str(tmp_path / "push_registry.json"),
        max_live_activity_start_tokens=2,
    )
    service = PushService(registry=registry)

    service.register_live_activity_start_token(
        LiveActivityStartTokenRegisterRequest(
            pushToStartToken="owner-a-old-token",
            installationId="installation-a",
        )
    )
    service.register_live_activity_start_token(
        LiveActivityStartTokenRegisterRequest(
            pushToStartToken="owner-b-token",
            installationId="installation-b",
        )
    )
    service.register_live_activity_start_token(
        LiveActivityStartTokenRegisterRequest(
            pushToStartToken="owner-a-new-token",
            previousPushToStartToken="owner-a-old-token",
            installationId="installation-a",
        )
    )

    with pytest.raises(RuntimeError, match="start token registration capacity reached"):
        service.register_live_activity_start_token(
            LiveActivityStartTokenRegisterRequest(
                pushToStartToken="owner-c-token",
                installationId="installation-c",
            )
        )

    data = registry._load()
    assert sorted(data["liveActivityStartTokens"]) == [
        "owner-a-new-token",
        "owner-b-token",
    ]


def test_start_token_refresh_and_cas_rotation_bypass_new_owner_admission(tmp_path) -> None:
    registry_path = tmp_path / "push_registry.json"
    registry = PushRegistry(
        str(registry_path),
        registration_new_owner_window_seconds=300,
        registration_new_owner_max_attempts=1,
    )
    service = PushService(registry=registry)
    original = LiveActivityStartTokenRegisterRequest(
        pushToStartToken="owner-old-token",
        installationId="installation-owner",
    )
    rotated = LiveActivityStartTokenRegisterRequest(
        pushToStartToken="owner-new-token",
        previousPushToStartToken="owner-old-token",
        installationId="installation-owner",
    )

    service.register_live_activity_start_token(original)
    service.register_live_activity_start_token(original)
    service.register_live_activity_start_token(rotated)
    before_denial = registry_path.read_bytes()
    with pytest.raises(RuntimeError, match="new owner registration rate limit reached"):
        service.register_live_activity_start_token(
            LiveActivityStartTokenRegisterRequest(
                pushToStartToken="other-owner-token",
                installationId="installation-other",
            )
        )

    assert registry_path.read_bytes() == before_denial
    assert list(registry._load()["liveActivityStartTokens"]) == ["owner-new-token"]


def test_stale_start_token_owner_and_claim_state_are_pruned_before_capacity_rejection(
    tmp_path,
) -> None:
    now = [datetime(2026, 8, 10, 12, 0, tzinfo=timezone.utc)]
    registry_path = tmp_path / "push_registry.json"
    registry = PushRegistry(
        str(registry_path),
        max_live_activity_start_tokens=1,
        live_activity_start_token_ttl_seconds=60,
        registration_now_provider=lambda: now[0],
    )
    service = PushService(registry=registry)
    service.register_live_activity_start_token(
        LiveActivityStartTokenRegisterRequest(
            pushToStartToken="stale-owner-token",
            installationId="stale-installation",
        )
    )
    data = json.loads(registry_path.read_text(encoding="utf-8"))
    data["liveActivityStartStates"] = {
        "20260810LGKT0": {
            "stale-owner-token": {
                "claimId": "stale-claim",
                "claimedAt": now[0].isoformat(),
            }
        }
    }
    registry_path.write_text(json.dumps(data), encoding="utf-8")

    now[0] += timedelta(seconds=61)
    service.register_live_activity_start_token(
        LiveActivityStartTokenRegisterRequest(
            pushToStartToken="active-owner-token",
            installationId="active-installation",
        )
    )

    data = registry._load()
    assert list(data["liveActivityStartTokens"]) == ["active-owner-token"]
    assert data["liveActivityStartStates"] == {}


def test_start_token_registration_cannot_reassign_existing_token_owner(
    tmp_path,
) -> None:
    registry = PushRegistry(str(tmp_path / "push_registry.json"))
    service = PushService(registry=registry)
    service.register_live_activity_start_token(
        LiveActivityStartTokenRegisterRequest(
            pushToStartToken="victim-start-token",
            installationId="installation-owner",
        )
    )

    with pytest.raises(RuntimeError, match="start token ownership conflict"):
        service.register_live_activity_start_token(
            LiveActivityStartTokenRegisterRequest(
                pushToStartToken="victim-start-token",
                installationId="installation-attacker",
            )
        )

    data = registry._load()
    assert (
        data["liveActivityStartTokens"]["victim-start-token"]["installationId"]
        == "installation-owner"
    )


def test_start_token_rotation_cannot_remove_another_installation(tmp_path) -> None:
    registry = PushRegistry(str(tmp_path / "push_registry.json"))
    service = PushService(registry=registry)
    service.register_live_activity_start_token(
        LiveActivityStartTokenRegisterRequest(
            pushToStartToken="victim-start-token",
            installationId="installation-owner",
        )
    )

    service.register_live_activity_start_token(
        LiveActivityStartTokenRegisterRequest(
            pushToStartToken="attacker-start-token",
            previousPushToStartToken="victim-start-token",
            installationId="installation-attacker",
        )
    )

    data = registry._load()
    assert sorted(data["liveActivityStartTokens"]) == [
        "attacker-start-token",
        "victim-start-token",
    ]


def test_live_activity_registration_auto_rotates_only_the_exact_owner(
    tmp_path,
) -> None:
    registry = PushRegistry(str(tmp_path / "push_registry.json"))
    service = PushService(registry=registry)
    for token, installation_id in (
        ("owner-old-token", "installation-owner"),
        ("other-owner-token", "installation-other"),
    ):
        service.register_live_activity(
            LiveActivityRegisterRequest(
                gameId="20260810LGKT0",
                activityPushToken=token,
                activityId="activity-1",
                installationId=installation_id,
            )
        )

    service.register_live_activity(
        LiveActivityRegisterRequest(
            gameId="20260810LGKT0",
            activityPushToken="owner-new-token",
            activityId="activity-1",
            installationId="installation-owner",
        )
    )

    assert registry.live_activity_tokens_for_game("20260810LGKT0") == [
        "other-owner-token",
        "owner-new-token",
    ]


def test_live_activity_registration_cannot_reassign_an_owned_token(tmp_path) -> None:
    registry = PushRegistry(str(tmp_path / "push_registry.json"))
    service = PushService(registry=registry)
    service.register_live_activity(
        LiveActivityRegisterRequest(
            gameId="20260810LGKT0",
            activityPushToken="victim-token",
            activityId="activity-owner",
            installationId="installation-owner",
        )
    )

    with pytest.raises(RuntimeError, match="live activity token ownership conflict"):
        service.register_live_activity(
            LiveActivityRegisterRequest(
                gameId="20260810SSOB0",
                activityPushToken="victim-token",
                activityId="activity-attacker",
                installationId="installation-attacker",
            )
        )

    data = registry._load()
    assert data["liveActivities"]["victim-token"]["installationId"] == ("installation-owner")


def test_live_activity_registry_rejects_new_owner_at_cap_but_allows_rotation(
    tmp_path,
) -> None:
    registry = PushRegistry(
        str(tmp_path / "push_registry.json"),
        max_live_activities=1,
    )
    service = PushService(registry=registry)
    service.register_live_activity(
        LiveActivityRegisterRequest(
            gameId="20260810LGKT0",
            activityPushToken="owner-old-token",
            activityId="activity-owner",
            installationId="installation-owner",
        )
    )
    service.register_live_activity(
        LiveActivityRegisterRequest(
            gameId="20260810LGKT0",
            activityPushToken="owner-new-token",
            activityId="activity-owner",
            installationId="installation-owner",
        )
    )

    with pytest.raises(RuntimeError, match="live activity registration capacity reached"):
        service.register_live_activity(
            LiveActivityRegisterRequest(
                gameId="20260810SSOB0",
                activityPushToken="other-owner-token",
                activityId="activity-other",
                installationId="installation-other",
            )
        )

    assert registry.live_activity_tokens_for_game("20260810LGKT0") == ["owner-new-token"]


def test_live_activity_refresh_and_rotation_bypass_new_owner_admission(tmp_path) -> None:
    registry_path = tmp_path / "push_registry.json"
    registry = PushRegistry(
        str(registry_path),
        registration_new_owner_window_seconds=300,
        registration_new_owner_max_attempts=1,
    )
    service = PushService(registry=registry)
    original = LiveActivityRegisterRequest(
        gameId="20260810LGKT0",
        activityPushToken="owner-old-token",
        activityId="activity-owner",
        installationId="installation-owner",
    )
    rotated = LiveActivityRegisterRequest(
        gameId="20260810LGKT0",
        activityPushToken="owner-new-token",
        activityId="activity-owner",
        installationId="installation-owner",
    )

    service.register_live_activity(original)
    service.register_live_activity(original)
    service.register_live_activity(rotated)
    before_denial = registry_path.read_bytes()
    with pytest.raises(RuntimeError, match="new owner registration rate limit reached"):
        service.register_live_activity(
            LiveActivityRegisterRequest(
                gameId="20260810SSOB0",
                activityPushToken="other-owner-token",
                activityId="activity-other",
                installationId="installation-other",
            )
        )

    assert registry_path.read_bytes() == before_denial
    assert registry.live_activity_tokens_for_game("20260810LGKT0") == ["owner-new-token"]


def test_stale_live_activity_owner_is_pruned_before_capacity_rejection(tmp_path) -> None:
    now = [datetime(2026, 8, 10, 12, 0, tzinfo=timezone.utc)]
    registry_path = tmp_path / "push_registry.json"
    registry = PushRegistry(
        str(registry_path),
        max_live_activities=1,
        live_activity_registration_ttl_seconds=60,
        registration_now_provider=lambda: now[0],
    )
    service = PushService(registry=registry)
    service.register_live_activity(
        LiveActivityRegisterRequest(
            gameId="20260810LGKT0",
            activityPushToken="stale-owner-token",
            activityId="stale-activity",
            installationId="stale-installation",
        )
    )
    stale_delivery_id = hashlib.sha256(b"stale-owner-token").hexdigest()
    data = json.loads(registry_path.read_text(encoding="utf-8"))
    data["liveActivityUpdateStates"] = {
        "20260810LGKT0": {
            "deliveries": {
                stale_delivery_id: {
                    "claimId": "stale-claim",
                    "claimedAt": now[0].isoformat(),
                }
            }
        }
    }
    registry_path.write_text(json.dumps(data), encoding="utf-8")

    now[0] += timedelta(seconds=61)
    service.register_live_activity(
        LiveActivityRegisterRequest(
            gameId="20260810SSOB0",
            activityPushToken="active-owner-token",
            activityId="active-activity",
            installationId="active-installation",
        )
    )

    data = registry._load()
    assert list(data["liveActivities"]) == ["active-owner-token"]
    assert data["liveActivityUpdateStates"] == {}


def test_legacy_live_activity_exact_token_refresh_does_not_exempt_distinct_token(
    tmp_path,
) -> None:
    registry = PushRegistry(
        str(tmp_path / "push_registry.json"),
        registration_new_owner_window_seconds=300,
        registration_new_owner_max_attempts=1,
    )
    service = PushService(registry=registry)
    exact_request = LiveActivityRegisterRequest(
        gameId="20260810LGKT0",
        activityPushToken="legacy-token-a",
    )

    service.register_live_activity(exact_request)
    service.register_live_activity(exact_request)
    with pytest.raises(RuntimeError, match="new owner registration rate limit reached"):
        service.register_live_activity(
            LiveActivityRegisterRequest(
                gameId="20260810LGKT0",
                activityPushToken="legacy-token-b",
            )
        )

    assert registry.live_activity_tokens_for_game("20260810LGKT0") == ["legacy-token-a"]


@pytest.mark.parametrize(
    "payload_overrides",
    [
        {"deviceToken": "t" * 2049},
        {"installationId": "i" * 129},
        {"platform": "p" * 17},
        {"followedGameIds": [f"game-{index}" for index in range(17)]},
        {"followedGameIds": ["g" * 33]},
        {"deviceToken": "   "},
        {"platform": "   "},
    ],
)
def test_push_registration_schema_rejects_oversized_public_fields(
    payload_overrides,
) -> None:
    payload = {
        "deviceToken": "token",
        "installationId": "installation-owner",
        "platform": "ios",
        "notifications": _notification_settings(),
    }
    payload.update(payload_overrides)

    with pytest.raises(ValueError):
        PushRegisterRequest(**payload)


@pytest.mark.parametrize(
    "payload_overrides",
    [
        {"pushToStartToken": "t" * 513},
        {"previousPushToStartToken": "p" * 513},
        {"installationId": "i" * 129},
        {"platform": "p" * 17},
        {"pushToStartToken": "   "},
        {"installationId": "   "},
    ],
)
def test_start_token_schema_rejects_oversized_public_fields(
    payload_overrides,
) -> None:
    payload = {
        "pushToStartToken": "token",
        "installationId": "installation-owner",
        "platform": "ios",
    }
    payload.update(payload_overrides)

    with pytest.raises(ValueError):
        LiveActivityStartTokenRegisterRequest(**payload)


@pytest.mark.parametrize(
    "payload_overrides",
    [
        {"deviceToken": "t" * 2049},
        {"installationId": "i" * 129},
        {"deviceToken": ""},
        {"installationId": ""},
        {"deviceToken": "   "},
        {"installationId": "   "},
    ],
)
def test_device_self_test_schema_rejects_unbounded_or_empty_identity_fields(
    payload_overrides,
) -> None:
    payload = {
        "deviceToken": "token",
        "installationId": "installation-owner",
    }
    payload.update(payload_overrides)

    with pytest.raises(ValueError):
        PushDeviceTestRequest(**payload)


@pytest.mark.parametrize(
    "payload_overrides",
    [
        {"deviceToken": "t" * 2049},
        {"installationId": "i" * 129},
        {"messageId": "m" * 257},
        {"source": "s" * 33},
        {"type": "t" * 65},
        {"gameId": "g" * 33},
        {"route": "r" * 513},
        {"receivedAt": "d" * 65},
        {"data": {f"key-{index}": "value" for index in range(9)}},
        {"data": {"topic": "한" * 4096}},
        {"installationId": "   "},
    ],
)
def test_push_receipt_schema_rejects_unbounded_public_fields(payload_overrides) -> None:
    payload = {
        "deviceToken": "registered-token",
        "installationId": "installation-owner",
        "source": "foreground",
    }
    payload.update(payload_overrides)

    with pytest.raises(ValueError):
        PushReceiptRequest(**payload)


def test_push_receipt_requires_exact_registered_installation(tmp_path) -> None:
    registry = PushRegistry(str(tmp_path / "push_registry.json"))
    service = PushService(registry=registry)
    service.register(
        PushRegisterRequest(
            deviceToken="registered-token",
            installationId="installation-owner",
            platform="ios",
            notifications=_notification_settings(),
        )
    )

    response = service.record_receipt(
        PushReceiptRequest(
            deviceToken="registered-token",
            installationId="installation-attacker",
            source="foreground",
        )
    )

    assert response == {
        "recorded": False,
        "registered": False,
        "reason": "device token is not registered",
    }
    assert registry.recent_push_receipts() == []


@pytest.mark.parametrize(
    "registry_contents",
    [
        "{not-json",
        "[]",
        '{"devices": []}',
        '{"liveActivityStartTokens": []}',
    ],
)
def test_existing_corrupt_registry_fails_closed_without_overwrite(
    tmp_path,
    registry_contents: str,
) -> None:
    registry_path = tmp_path / "push_registry.json"
    registry_path.write_text(registry_contents, encoding="utf-8")
    service = PushService(registry=PushRegistry(str(registry_path)))

    with pytest.raises(PushRegistryCorruptionError):
        service.register(
            PushRegisterRequest(
                deviceToken="new-token",
                installationId="installation-owner",
                platform="ios",
                notifications=_notification_settings(),
            )
        )

    assert registry_path.read_text(encoding="utf-8") == registry_contents


@pytest.mark.parametrize("registration_scope", ["device", "start", "live"])
def test_malformed_persisted_owner_type_fails_closed_without_reassignment(
    tmp_path,
    registration_scope: str,
) -> None:
    registry_path = tmp_path / "push_registry.json"
    registry = PushRegistry(str(registry_path))
    service = PushService(registry=registry)
    if registration_scope == "device":
        service.register(
            PushRegisterRequest(
                deviceToken="victim-token",
                installationId="installation-owner",
                platform="ios",
                notifications=_notification_settings(),
            )
        )
        section_name = "devices"
        token = "victim-token"

        def reassign() -> None:
            service.register(
                PushRegisterRequest(
                    deviceToken=token,
                    installationId="installation-attacker",
                    platform="ios",
                    notifications=_notification_settings(),
                )
            )

    elif registration_scope == "start":
        service.register_live_activity_start_token(
            LiveActivityStartTokenRegisterRequest(
                pushToStartToken="victim-token",
                installationId="installation-owner",
            )
        )
        section_name = "liveActivityStartTokens"
        token = "victim-token"

        def reassign() -> None:
            service.register_live_activity_start_token(
                LiveActivityStartTokenRegisterRequest(
                    pushToStartToken=token,
                    installationId="installation-attacker",
                )
            )

    else:
        service.register_live_activity(
            LiveActivityRegisterRequest(
                gameId="20260810LGKT0",
                activityPushToken="victim-token",
                activityId="activity-owner",
                installationId="installation-owner",
            )
        )
        section_name = "liveActivities"
        token = "victim-token"

        def reassign() -> None:
            service.register_live_activity(
                LiveActivityRegisterRequest(
                    gameId="20260810SSOB0",
                    activityPushToken=token,
                    activityId="activity-attacker",
                    installationId="installation-attacker",
                )
            )

    data = json.loads(registry_path.read_text(encoding="utf-8"))
    data[section_name][token]["installationId"] = []
    registry_path.write_text(json.dumps(data), encoding="utf-8")
    corrupted = registry_path.read_bytes()

    with pytest.raises(PushRegistryCorruptionError):
        reassign()

    assert registry_path.read_bytes() == corrupted


@pytest.mark.parametrize("registration_scope", ["device", "start", "live"])
def test_malformed_registration_last_seen_fails_closed_on_exact_owner_refresh(
    tmp_path,
    registration_scope: str,
) -> None:
    registry_path = tmp_path / "push_registry.json"
    registry = PushRegistry(str(registry_path))
    service = PushService(registry=registry)
    if registration_scope == "device":
        request = PushRegisterRequest(
            deviceToken="owner-token",
            installationId="installation-owner",
            platform="ios",
            notifications=_notification_settings(),
        )
        service.register(request)
        section_name = "devices"
        token = "owner-token"
        refresh = service.register
    elif registration_scope == "start":
        request = LiveActivityStartTokenRegisterRequest(
            pushToStartToken="owner-token",
            installationId="installation-owner",
        )
        service.register_live_activity_start_token(request)
        section_name = "liveActivityStartTokens"
        token = "owner-token"
        refresh = service.register_live_activity_start_token
    else:
        request = LiveActivityRegisterRequest(
            gameId="20260810LGKT0",
            activityPushToken="owner-token",
            activityId="activity-owner",
            installationId="installation-owner",
        )
        service.register_live_activity(request)
        section_name = "liveActivities"
        token = "owner-token"
        refresh = service.register_live_activity

    data = json.loads(registry_path.read_text(encoding="utf-8"))
    data[section_name][token]["updatedAt"] = []
    registry_path.write_text(json.dumps(data), encoding="utf-8")
    corrupted = registry_path.read_bytes()

    with pytest.raises(PushRegistryCorruptionError):
        refresh(request)

    assert registry_path.read_bytes() == corrupted


@pytest.mark.parametrize("corrupt_scope", ["owner", "global"])
def test_malformed_device_test_security_state_fails_closed(
    tmp_path,
    corrupt_scope: str,
) -> None:
    registry_path = tmp_path / "push_registry.json"
    registry = PushRegistry(str(registry_path))
    service = PushService(registry=registry)
    messaging = _FakeMessaging()
    service._get_messaging = lambda: messaging
    service.register(
        PushRegisterRequest(
            deviceToken="registered-token",
            installationId="installation-owner",
            platform="ios",
            notifications=_notification_settings(),
        )
    )
    service.send_device_test(
        PushDeviceTestRequest(
            deviceToken="registered-token",
            installationId="installation-owner",
        )
    )
    data = json.loads(registry_path.read_text(encoding="utf-8"))
    if corrupt_scope == "owner":
        state = next(iter(data["deviceTestStates"].values()))
        state["attemptedAt"] = "not-a-date"
        data["deviceTestRateState"]["attemptedAt"] = []
    else:
        data["deviceTestStates"] = {}
        data["deviceTestRateState"]["attemptedAt"] = ["not-a-date"]
    registry_path.write_text(json.dumps(data), encoding="utf-8")

    with pytest.raises(PushRegistryCorruptionError):
        registry.claim_device_test(
            device_token="registered-token",
            installation_id="installation-owner",
        )


def test_registry_byte_cap_rejects_growth_and_preserves_existing_data(tmp_path) -> None:
    registry = PushRegistry(
        str(tmp_path / "push_registry.json"),
        max_registry_bytes=4096,
    )
    service = PushService(registry=registry)
    service.register(
        PushRegisterRequest(
            deviceToken="owner-a-token",
            installationId="installation-a",
            platform="ios",
            notifications=_notification_settings(),
        )
    )

    with pytest.raises(RuntimeError, match="registry byte capacity reached"):
        service.register(
            PushRegisterRequest(
                deviceToken="t" * 2048,
                installationId="installation-b",
                platform="ios",
                notifications=_notification_settings(),
            )
        )

    assert [registration["deviceToken"] for registration in registry.device_registrations()] == [
        "owner-a-token"
    ]


def test_push_register_endpoint_reports_capacity_rejection(monkeypatch, tmp_path) -> None:
    registry = PushRegistry(
        str(tmp_path / "push_registry.json"),
        max_devices=1,
    )
    monkeypatch.setattr(push_routes, "service", PushService(registry=registry))
    client = TestClient(app, raise_server_exceptions=False)
    body = {
        "deviceToken": "owner-a-token",
        "installationId": "installation-a",
        "platform": "ios",
        "notifications": _notification_settings().model_dump(),
    }

    first = client.post("/api/push/register", json=body)
    second = client.post(
        "/api/push/register",
        json={
            **body,
            "deviceToken": "owner-b-token",
            "installationId": "installation-b",
        },
    )

    assert first.status_code == 200
    assert second.status_code == 429
    assert second.json()["detail"] == "push registry capacity reached"


def test_stale_fake_device_owners_cannot_exhaust_all_5000_slots_forever(
    monkeypatch,
    tmp_path,
) -> None:
    registry_path = tmp_path / "push_registry.json"
    registry = PushRegistry(str(registry_path), max_devices=5000)
    data = registry._load()
    now = datetime.now(timezone.utc).isoformat()
    data["devices"] = {
        f"fake-token-{index}": {
            "deviceToken": f"fake-token-{index}",
            "installationId": f"fake-installation-{index}",
            "platform": "ios",
            "createdAt": now,
            "updatedAt": now,
        }
        for index in range(5000)
    }
    registry_path.write_text(json.dumps(data), encoding="utf-8")
    monkeypatch.setattr(push_routes, "service", PushService(registry=registry))
    client = TestClient(app, raise_server_exceptions=False)
    body = {
        "deviceToken": "legitimate-token",
        "installationId": "legitimate-installation",
        "platform": "ios",
        "notifications": _notification_settings().model_dump(),
    }

    full = client.post("/api/push/register", json=body)
    assert full.status_code == 429

    stale_data = json.loads(registry_path.read_text(encoding="utf-8"))
    for registration in stale_data["devices"].values():
        registration["createdAt"] = "2000-01-01T00:00:00+00:00"
        registration["updatedAt"] = "2000-01-01T00:00:00+00:00"
    registry_path.write_text(json.dumps(stale_data), encoding="utf-8")

    recovered = client.post("/api/push/register", json=body)

    assert recovered.status_code == 200
    assert [item["deviceToken"] for item in registry.device_registrations()] == ["legitimate-token"]


def test_push_register_endpoint_reports_ownership_conflict(monkeypatch, tmp_path) -> None:
    registry = PushRegistry(str(tmp_path / "push_registry.json"))
    monkeypatch.setattr(push_routes, "service", PushService(registry=registry))
    client = TestClient(app, raise_server_exceptions=False)
    body = {
        "deviceToken": "victim-token",
        "installationId": "installation-owner",
        "platform": "ios",
        "notifications": _notification_settings().model_dump(),
    }

    first = client.post("/api/push/register", json=body)
    conflict = client.post(
        "/api/push/register",
        json={**body, "installationId": "installation-attacker"},
    )

    assert first.status_code == 200
    assert conflict.status_code == 409
    assert conflict.json()["detail"] == "push registration ownership conflict"


def test_start_token_endpoint_reports_capacity_rejection(monkeypatch, tmp_path) -> None:
    registry = PushRegistry(
        str(tmp_path / "push_registry.json"),
        max_live_activity_start_tokens=1,
    )
    monkeypatch.setattr(push_routes, "service", PushService(registry=registry))
    client = TestClient(app, raise_server_exceptions=False)
    body = {
        "pushToStartToken": "owner-a-token",
        "installationId": "installation-a",
        "platform": "ios",
    }

    first = client.post("/api/push/live-activity/start-token/register", json=body)
    second = client.post(
        "/api/push/live-activity/start-token/register",
        json={
            **body,
            "pushToStartToken": "owner-b-token",
            "installationId": "installation-b",
        },
    )

    assert first.status_code == 200
    assert second.status_code == 429
    assert second.json()["detail"] == "push registry capacity reached"


def test_start_token_endpoint_reports_stale_owner_rotation_conflict(
    monkeypatch,
    tmp_path,
) -> None:
    registry = PushRegistry(str(tmp_path / "push_registry.json"))
    monkeypatch.setattr(push_routes, "service", PushService(registry=registry))
    client = TestClient(app, raise_server_exceptions=False)
    body = {
        "pushToStartToken": "start-token-a",
        "installationId": "installation-a",
        "platform": "ios",
    }

    first = client.post("/api/push/live-activity/start-token/register", json=body)
    rotated = client.post(
        "/api/push/live-activity/start-token/register",
        json={
            **body,
            "pushToStartToken": "start-token-b",
            "previousPushToStartToken": "start-token-a",
        },
    )
    stale = client.post(
        "/api/push/live-activity/start-token/register",
        json={
            **body,
            "pushToStartToken": "start-token-c",
            "previousPushToStartToken": "start-token-a",
        },
    )

    assert first.status_code == 200
    assert rotated.status_code == 200
    assert stale.status_code == 409
    assert stale.json()["detail"] == "push registration ownership conflict"
    data = registry._load()
    assert list(data["liveActivityStartTokens"]) == ["start-token-b"]


def test_live_activity_endpoint_reports_capacity_rejection(monkeypatch, tmp_path) -> None:
    registry = PushRegistry(
        str(tmp_path / "push_registry.json"),
        max_live_activities=1,
    )
    monkeypatch.setattr(push_routes, "service", PushService(registry=registry))
    client = TestClient(app, raise_server_exceptions=False)
    body = {
        "gameId": "20260810LGKT0",
        "activityPushToken": "owner-a-token",
        "activityId": "activity-a",
        "installationId": "installation-a",
        "platform": "ios",
    }

    first = client.post("/api/push/live-activity/register", json=body)
    second = client.post(
        "/api/push/live-activity/register",
        json={
            **body,
            "gameId": "20260810SSOB0",
            "activityPushToken": "owner-b-token",
            "activityId": "activity-b",
            "installationId": "installation-b",
        },
    )

    assert first.status_code == 200
    assert second.status_code == 429
    assert second.json()["detail"] == "push registry capacity reached"


def test_live_activity_endpoint_reports_token_ownership_conflict(
    monkeypatch,
    tmp_path,
) -> None:
    registry = PushRegistry(str(tmp_path / "push_registry.json"))
    monkeypatch.setattr(push_routes, "service", PushService(registry=registry))
    client = TestClient(app, raise_server_exceptions=False)
    body = {
        "gameId": "20260810LGKT0",
        "activityPushToken": "victim-token",
        "activityId": "activity-owner",
        "installationId": "installation-owner",
        "platform": "ios",
    }

    first = client.post("/api/push/live-activity/register", json=body)
    conflict = client.post(
        "/api/push/live-activity/register",
        json={
            **body,
            "gameId": "20260810SSOB0",
            "activityId": "activity-attacker",
            "installationId": "installation-attacker",
        },
    )

    assert first.status_code == 200
    assert conflict.status_code == 409
    assert conflict.json()["detail"] == "push registration ownership conflict"


@pytest.mark.parametrize(
    ("route", "body"),
    [
        (
            "/api/push/register",
            {
                "deviceToken": "device-token",
                "installationId": "installation-owner",
                "platform": "ios",
                "notifications": _notification_settings().model_dump(),
            },
        ),
        (
            "/api/push/test-device",
            {
                "deviceToken": "device-token",
                "installationId": "installation-owner",
            },
        ),
        (
            "/api/push/receipt",
            {
                "deviceToken": "device-token",
                "installationId": "installation-owner",
                "source": "foreground",
            },
        ),
        (
            "/api/push/live-activity/register",
            {
                "gameId": "20260810LGKT0",
                "activityPushToken": "activity-token",
                "activityId": "activity-owner",
                "installationId": "installation-owner",
            },
        ),
        (
            "/api/push/live-activity/start-token/register",
            {
                "pushToStartToken": "start-token",
                "installationId": "installation-owner",
            },
        ),
    ],
)
def test_public_push_routes_report_corrupt_registry_as_unavailable(
    monkeypatch,
    tmp_path,
    route: str,
    body: dict,
) -> None:
    registry_path = tmp_path / "push_registry.json"
    registry_path.write_text("{not-json", encoding="utf-8")
    monkeypatch.setattr(
        push_routes,
        "service",
        PushService(registry=PushRegistry(str(registry_path))),
    )
    client = TestClient(app, raise_server_exceptions=False)

    response = client.post(route, json=body)

    assert response.status_code == 503
    assert response.json()["detail"] == "push registry unavailable"
    assert registry_path.read_text(encoding="utf-8") == "{not-json"


def test_corrupt_registration_admission_state_blocks_exact_owner_refresh(
    monkeypatch,
    tmp_path,
) -> None:
    registry_path = tmp_path / "push_registry.json"
    registry = PushRegistry(str(registry_path))
    service = PushService(registry=registry)
    body = {
        "deviceToken": "owner-token",
        "installationId": "installation-owner",
        "platform": "ios",
        "notifications": _notification_settings().model_dump(),
    }
    service.register(PushRegisterRequest(**body))
    data = json.loads(registry_path.read_text(encoding="utf-8"))
    data["registrationAdmissionState"]["newOwnerAcceptedAt"] = ["not-a-date"]
    registry_path.write_text(json.dumps(data), encoding="utf-8")
    corrupted = registry_path.read_bytes()
    monkeypatch.setattr(push_routes, "service", service)
    client = TestClient(app, raise_server_exceptions=False)

    response = client.post("/api/push/register", json=body)

    assert response.status_code == 503
    assert response.json()["detail"] == "push registry unavailable"
    assert registry_path.read_bytes() == corrupted
