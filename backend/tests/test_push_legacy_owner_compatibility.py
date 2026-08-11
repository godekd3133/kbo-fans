from __future__ import annotations

import pytest
from fastapi.testclient import TestClient

from kbo_fans_backend.api.routes import push as push_routes
from kbo_fans_backend.main import app
from kbo_fans_backend.schemas.push import (
    LiveActivityRegisterRequest,
    NotificationSettings,
    PushRegisterRequest,
)
from kbo_fans_backend.services.push import PushService
from kbo_fans_backend.services.push_registry import PushRegistry


def _notification_settings() -> NotificationSettings:
    return NotificationSettings(
        gameStart=True,
        scoring=True,
        homerun=True,
        reversal=True,
        gameEnd=True,
        allGames=False,
    )


def test_legacy_device_test_without_installation_is_a_safe_200_noop(
    monkeypatch,
    tmp_path,
) -> None:
    registry_path = tmp_path / "push_registry.json"
    service = PushService(registry=PushRegistry(str(registry_path)))
    service.register(
        PushRegisterRequest(
            deviceToken="owned-token",
            installationId="installation-owner",
            platform="ios",
            notifications=_notification_settings(),
        )
    )
    service._get_messaging = lambda: (_ for _ in ()).throw(
        AssertionError("legacy ownerless self-test must not send")
    )
    before = registry_path.read_bytes()
    monkeypatch.setattr(push_routes, "service", service)
    client = TestClient(app, raise_server_exceptions=False)

    response = client.post(
        "/api/push/test-device",
        json={"deviceToken": "owned-token"},
    )

    assert response.status_code == 200
    assert response.json()["data"] == {
        "sent": False,
        "registered": False,
        "reason": "device token ownership does not match",
    }
    assert registry_path.read_bytes() == before


@pytest.mark.parametrize("registered_installation_id", ["installation-owner", None])
def test_legacy_receipt_without_installation_is_a_safe_200_noop(
    monkeypatch,
    tmp_path,
    registered_installation_id,
) -> None:
    registry_path = tmp_path / "push_registry.json"
    service = PushService(registry=PushRegistry(str(registry_path)))
    service.register(
        PushRegisterRequest(
            deviceToken="owned-token",
            installationId=registered_installation_id,
            platform="ios",
            notifications=_notification_settings(),
        )
    )
    before = registry_path.read_bytes()
    monkeypatch.setattr(push_routes, "service", service)
    client = TestClient(app, raise_server_exceptions=False)

    response = client.post(
        "/api/push/receipt",
        json={
            "deviceToken": "owned-token",
            "source": "foreground",
            "messageId": "legacy-message",
        },
    )

    assert response.status_code == 200
    assert response.json()["data"] == {
        "recorded": False,
        "registered": False,
        "reason": "device token is not registered",
    }
    assert registry_path.read_bytes() == before


def test_legacy_unregister_without_installation_never_removes_owned_or_ownerless_activity(
    monkeypatch,
    tmp_path,
) -> None:
    registry_path = tmp_path / "push_registry.json"
    registry = PushRegistry(str(registry_path))
    service = PushService(registry=registry)
    for token, activity_id, installation_id in (
        ("owned-token", "owned-activity", "installation-owner"),
        ("legacy-token", "legacy-activity", None),
    ):
        service.register_live_activity(
            LiveActivityRegisterRequest(
                gameId="20260810LGKT0",
                activityPushToken=token,
                activityId=activity_id,
                installationId=installation_id,
            )
        )
    before = registry_path.read_bytes()
    monkeypatch.setattr(push_routes, "service", service)
    client = TestClient(app, raise_server_exceptions=False)

    responses = [
        client.post(
            "/api/push/live-activity/unregister",
            json={
                "gameId": "20260810LGKT0",
                "activityPushToken": token,
                "activityId": activity_id,
            },
        )
        for token, activity_id in (
            ("owned-token", "owned-activity"),
            ("legacy-token", "legacy-activity"),
        )
    ]

    assert [response.status_code for response in responses] == [200, 200]
    assert [response.json()["data"]["removed"] for response in responses] == [0, 0]
    assert registry.live_activity_tokens_for_game("20260810LGKT0") == [
        "legacy-token",
        "owned-token",
    ]
    assert registry_path.read_bytes() == before


@pytest.mark.parametrize(
    "legacy_body",
    [
        {"activityId": "owned-activity"},
        {"activityPushToken": None, "activityId": "owned-activity"},
        {"activityPushToken": "", "activityId": "owned-activity"},
        {"activityPushToken": "   ", "activityId": "owned-activity"},
        {"activityPushToken": "owned-token"},
        {"activityPushToken": "owned-token", "activityId": None},
        {"activityPushToken": "owned-token", "activityId": ""},
        {"activityPushToken": "owned-token", "activityId": "   "},
        {},
    ],
    ids=[
        "missing-token",
        "null-token",
        "empty-token",
        "blank-token",
        "missing-activity",
        "null-activity",
        "empty-activity",
        "blank-activity",
        "missing-token-and-activity",
    ],
)
def test_legacy_unregister_with_incomplete_token_or_activity_is_a_safe_200_noop(
    monkeypatch,
    tmp_path,
    legacy_body: dict,
) -> None:
    registry_path = tmp_path / "push_registry.json"
    registry = PushRegistry(str(registry_path))
    service = PushService(registry=registry)
    service.register_live_activity(
        LiveActivityRegisterRequest(
            gameId="20260810LGKT0",
            activityPushToken="owned-token",
            activityId="owned-activity",
            installationId="installation-owner",
        )
    )
    before = registry_path.read_bytes()
    monkeypatch.setattr(push_routes, "service", service)
    client = TestClient(app, raise_server_exceptions=False)

    response = client.post(
        "/api/push/live-activity/unregister",
        json={
            "gameId": "20260810LGKT0",
            "installationId": "installation-owner",
            **legacy_body,
        },
    )

    assert response.status_code == 200
    assert response.json()["data"]["removed"] == 0
    assert registry.live_activity_tokens_for_game("20260810LGKT0") == ["owned-token"]
    assert registry_path.read_bytes() == before


@pytest.mark.parametrize("legacy_activity_id", [None, "", "   "])
def test_legacy_unregister_never_matches_a_stored_ownerless_activity_id(
    monkeypatch,
    tmp_path,
    legacy_activity_id,
) -> None:
    registry_path = tmp_path / "push_registry.json"
    registry = PushRegistry(str(registry_path))
    service = PushService(registry=registry)
    service.register_live_activity(
        LiveActivityRegisterRequest(
            gameId="20260810LGKT0",
            activityPushToken="legacy-token",
            activityId=legacy_activity_id,
            installationId="installation-owner",
        )
    )
    before = registry_path.read_bytes()
    monkeypatch.setattr(push_routes, "service", service)
    client = TestClient(app, raise_server_exceptions=False)

    response = client.post(
        "/api/push/live-activity/unregister",
        json={
            "gameId": "20260810LGKT0",
            "activityPushToken": "legacy-token",
            "activityId": legacy_activity_id,
            "installationId": "installation-owner",
        },
    )

    assert response.status_code == 200
    assert response.json()["data"]["removed"] == 0
    assert registry.live_activity_tokens_for_game("20260810LGKT0") == ["legacy-token"]
    assert registry_path.read_bytes() == before


@pytest.mark.parametrize(
    "owner_override",
    [
        {"activityPushToken": "t" * 513},
        {"activityId": "a" * 129},
    ],
    ids=["oversized-token", "oversized-activity"],
)
def test_legacy_unregister_still_rejects_oversized_owner_fields(
    monkeypatch,
    tmp_path,
    owner_override: dict,
) -> None:
    registry_path = tmp_path / "push_registry.json"
    monkeypatch.setattr(
        push_routes,
        "service",
        PushService(registry=PushRegistry(str(registry_path))),
    )
    client = TestClient(app, raise_server_exceptions=False)

    response = client.post(
        "/api/push/live-activity/unregister",
        json={
            "gameId": "20260810LGKT0",
            "activityPushToken": "owned-token",
            "activityId": "owned-activity",
            "installationId": "installation-owner",
            **owner_override,
        },
    )

    assert response.status_code == 422
    assert not registry_path.exists()


def test_current_unregister_exact_tuple_removes_only_the_owned_activity(
    monkeypatch,
    tmp_path,
) -> None:
    registry = PushRegistry(str(tmp_path / "push_registry.json"))
    service = PushService(registry=registry)
    for token, activity_id, installation_id in (
        ("owned-token", "owned-activity", "installation-owner"),
        ("other-token", "other-activity", "installation-other"),
    ):
        service.register_live_activity(
            LiveActivityRegisterRequest(
                gameId="20260810LGKT0",
                activityPushToken=token,
                activityId=activity_id,
                installationId=installation_id,
            )
        )
    monkeypatch.setattr(push_routes, "service", service)
    client = TestClient(app, raise_server_exceptions=False)

    response = client.post(
        "/api/push/live-activity/unregister",
        json={
            "gameId": "20260810LGKT0",
            "activityPushToken": "owned-token",
            "activityId": "owned-activity",
            "installationId": "installation-owner",
        },
    )

    assert response.status_code == 200
    assert response.json()["data"]["removed"] == 1
    assert registry.live_activity_tokens_for_game("20260810LGKT0") == ["other-token"]


def test_incomplete_unregister_is_a_safe_noop_even_when_registry_is_corrupt(
    monkeypatch,
    tmp_path,
) -> None:
    registry_path = tmp_path / "push_registry.json"
    registry_path.write_text("{not-json", encoding="utf-8")
    monkeypatch.setattr(
        push_routes,
        "service",
        PushService(registry=PushRegistry(str(registry_path))),
    )
    client = TestClient(app, raise_server_exceptions=False)

    response = client.post(
        "/api/push/live-activity/unregister",
        json={
            "gameId": "20260810LGKT0",
            "activityId": "owned-activity",
            "installationId": "installation-owner",
        },
    )

    assert response.status_code == 200
    assert response.json()["data"]["removed"] == 0
    assert registry_path.read_text(encoding="utf-8") == "{not-json"


def test_owned_unregister_reports_corrupt_registry_as_unavailable(
    monkeypatch,
    tmp_path,
) -> None:
    registry_path = tmp_path / "push_registry.json"
    registry_path.write_text("{not-json", encoding="utf-8")
    monkeypatch.setattr(
        push_routes,
        "service",
        PushService(registry=PushRegistry(str(registry_path))),
    )
    client = TestClient(app, raise_server_exceptions=False)

    response = client.post(
        "/api/push/live-activity/unregister",
        json={
            "gameId": "20260810LGKT0",
            "activityPushToken": "owned-token",
            "activityId": "owned-activity",
            "installationId": "installation-owner",
        },
    )

    assert response.status_code == 503
    assert response.json()["detail"] == "push registry unavailable"
    assert registry_path.read_text(encoding="utf-8") == "{not-json"
