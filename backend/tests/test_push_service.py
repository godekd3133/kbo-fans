import fcntl
import os
from concurrent.futures import ProcessPoolExecutor, ThreadPoolExecutor

from fastapi.testclient import TestClient
from kbo_fans_backend.api.routes import push as push_routes
from kbo_fans_backend.core.config import Settings
from kbo_fans_backend.main import app
from kbo_fans_backend.schemas.push import (
    LiveActivityContentState,
    LiveActivityRegisterRequest,
    LiveActivityUnregisterRequest,
    LiveActivityUpdateRequest,
    NotificationSettings,
    PushRegisterRequest,
)
from kbo_fans_backend.services.apns_live_activity import ApnsLiveActivitySender
from kbo_fans_backend.services.live_activity_scoreboard import LiveActivityScoreboardSyncService
from kbo_fans_backend.services.push import PushService
from kbo_fans_backend.services.push_diagnostics import PushConfigurationDiagnostics
from kbo_fans_backend.services.push_registry import PushRegistry


def test_build_topics_returns_empty_without_team_when_all_games_disabled() -> None:
    service = PushService()
    payload = PushRegisterRequest(
        deviceToken="token",
        platform="flutter",
        myTeam=None,
        notifications=NotificationSettings(
            gameStart=True,
            scoring=True,
            homerun=True,
            reversal=True,
            gameEnd=True,
            lineupOpened=True,
            inningChange=False,
            allGames=False,
        ),
    )

    topics = service._build_topics(payload)

    assert topics == []


def test_build_topics_returns_all_topics_when_all_games_enabled() -> None:
    service = PushService()
    payload = PushRegisterRequest(
        deviceToken="token",
        platform="flutter",
        myTeam="LG",
        notifications=NotificationSettings(
            gameStart=True,
            scoring=True,
            homerun=True,
            reversal=True,
            gameEnd=True,
            lineupOpened=True,
            inningChange=False,
            allGames=True,
        ),
    )

    topics = service._build_topics(payload)

    assert "game_start_ALL" in topics
    assert "all_games_enabled" in topics
    assert "game_start_LG" not in topics


def test_register_persists_device_token(tmp_path) -> None:
    registry = PushRegistry(str(tmp_path / "push_registry.json"))
    service = PushService(registry=registry, live_activity_sender=FakeLiveActivitySender())
    payload = PushRegisterRequest(
        deviceToken="fcm-token",
        platform="ios",
        myTeam="LG",
        notifications=NotificationSettings(
            gameStart=True,
            scoring=True,
            homerun=True,
            reversal=True,
            gameEnd=True,
            lineupOpened=True,
            inningChange=False,
            allGames=False,
        ),
    )

    response = service.register(payload)

    assert response["registered"] is True
    assert "scoring_LG" in response["subscribedTopics"]


def test_push_registry_serializes_writes_across_processes(tmp_path) -> None:
    registry_path = str(tmp_path / "push_registry.json")
    worker_count = 4
    registrations_per_worker = 12

    with ProcessPoolExecutor(max_workers=worker_count) as executor:
        futures = [
            executor.submit(
                _register_device_token_batch,
                registry_path,
                f"worker-{worker_index}",
                registrations_per_worker,
            )
            for worker_index in range(worker_count)
        ]

        total_registrations = sum(future.result(timeout=20) for future in futures)

    registry_data = PushRegistry(registry_path)._load()

    assert total_registrations == worker_count * registrations_per_worker
    assert len(registry_data["devices"]) == total_registrations


def test_push_registry_serializes_writes_across_instances_in_process(tmp_path) -> None:
    registry_path = str(tmp_path / "push_registry.json")
    worker_count = 4
    registrations_per_worker = 12

    with ThreadPoolExecutor(max_workers=worker_count) as executor:
        futures = [
            executor.submit(
                _register_device_token_batch,
                registry_path,
                f"thread-{worker_index}",
                registrations_per_worker,
            )
            for worker_index in range(worker_count)
        ]

        total_registrations = sum(future.result(timeout=20) for future in futures)

    registry_data = PushRegistry(registry_path)._load()

    assert total_registrations == worker_count * registrations_per_worker
    assert len(registry_data["devices"]) == total_registrations


def test_push_registry_shared_lock_uses_readable_lock_fd(monkeypatch, tmp_path) -> None:
    original_flock = fcntl.flock

    def asserting_flock(fd: int, operation: int) -> None:
        if operation & fcntl.LOCK_SH:
            os.read(fd, 1)
        original_flock(fd, operation)

    monkeypatch.setattr(fcntl, "flock", asserting_flock)

    heartbeat = PushRegistry(str(tmp_path / "push_registry.json")).sync_heartbeat()

    assert heartbeat == {}


def test_register_live_activity_replaces_previous_token(tmp_path) -> None:
    registry = PushRegistry(str(tmp_path / "push_registry.json"))
    service = PushService(registry=registry, live_activity_sender=FakeLiveActivitySender())

    service.register_live_activity(
        LiveActivityRegisterRequest(
            gameId="20260604LGKT0",
            activityId="activity-1",
            activityPushToken="old-token",
        )
    )
    service.register_live_activity(
        LiveActivityRegisterRequest(
            gameId="20260604LGKT0",
            activityId="activity-1",
            activityPushToken="new-token",
            previousActivityPushToken="old-token",
        )
    )

    assert registry.live_activity_tokens_for_game("20260604LGKT0") == ["new-token"]


def test_unregister_live_activity_by_activity_id(tmp_path) -> None:
    registry = PushRegistry(str(tmp_path / "push_registry.json"))
    service = PushService(registry=registry, live_activity_sender=FakeLiveActivitySender())
    service.register_live_activity(
        LiveActivityRegisterRequest(
            gameId="20260604LGKT0",
            activityId="activity-1",
            activityPushToken="token",
        )
    )

    response = service.unregister_live_activity(
        LiveActivityUnregisterRequest(gameId="20260604LGKT0", activityId="activity-1")
    )

    assert response["removed"] == 1
    assert registry.live_activity_tokens_for_game("20260604LGKT0") == []


def test_send_live_activity_update_uses_registered_tokens(tmp_path) -> None:
    registry = PushRegistry(str(tmp_path / "push_registry.json"))
    sender = FakeLiveActivitySender()
    service = PushService(registry=registry, live_activity_sender=sender)
    service.register_live_activity(
        LiveActivityRegisterRequest(
            gameId="20260604LGKT0",
            activityId="activity-1",
            activityPushToken="token",
        )
    )

    response = service.send_live_activity_update(
        LiveActivityUpdateRequest(
            gameId="20260604LGKT0",
            state=_live_activity_state(),
        )
    )

    assert response["sent"] is True
    assert sender.calls[0]["activity_push_token"] == "token"
    assert sender.calls[0]["state"].homeScore == 3


def test_live_activity_scoreboard_sync_updates_registered_live_games(tmp_path) -> None:
    registry = PushRegistry(str(tmp_path / "push_registry.json"))
    sender = FakeLiveActivitySender()
    push_service = PushService(registry=registry, live_activity_sender=sender)
    push_service.register_live_activity(
        LiveActivityRegisterRequest(
            gameId="20260604LGKT0",
            activityId="activity-1",
            activityPushToken="token",
        )
    )
    sync_service = LiveActivityScoreboardSyncService(
        scoreboard_service=FakeScoreboardService(),
        push_service=push_service,
    )

    response = sync_service.sync_date("2026-06-04")

    assert response["checkedGames"] == 1
    assert response["updatedGames"][0]["sent"] is True
    assert sender.calls[0]["event"] == "update"
    assert sender.calls[0]["state"].inning == "7회말"
    assert registry.sync_heartbeat()["checkedGames"] == 1


def test_scoreboard_sync_pushes_score_moments_after_baseline(tmp_path) -> None:
    registry = PushRegistry(str(tmp_path / "push_registry.json"))
    sender = FakeLiveActivitySender()
    push_service = FakePushService(registry=registry, live_activity_sender=sender)
    push_service.register(
        PushRegisterRequest(
            deviceToken="fcm-token",
            platform="ios",
            myTeam="LG",
            notifications=NotificationSettings(
                gameStart=True,
                scoring=True,
                homerun=True,
                reversal=True,
                gameEnd=True,
                lineupOpened=True,
                inningChange=True,
                allGames=False,
            ),
        )
    )
    sync_service = LiveActivityScoreboardSyncService(
        scoreboard_service=FakeScoreboardSequenceService(
            [
                _scoreboard_game(away_score=2, home_score=3, inning="7회말"),
                _scoreboard_game(away_score=4, home_score=3, inning="8회초"),
            ]
        ),
        push_service=push_service,
    )

    first_response = sync_service.sync_date("2026-06-04")
    second_response = sync_service.sync_date("2026-06-04")

    assert first_response["pushedMoments"] == []
    assert [call["moment"] for call in push_service.moment_calls] == ["scoring", "reversal"]
    assert second_response["pushedMoments"][0]["moment"] == "scoring"
    assert push_service.moment_calls[0]["away_score"] == 4
    assert push_service.moment_calls[0]["home_score"] == 3


def test_scoreboard_sync_pushes_inning_change_when_only_inning_changes(tmp_path) -> None:
    registry = PushRegistry(str(tmp_path / "push_registry.json"))
    push_service = FakePushService(
        registry=registry,
        live_activity_sender=FakeLiveActivitySender(),
    )
    push_service.register(
        PushRegisterRequest(
            deviceToken="fcm-token",
            platform="ios",
            myTeam="LG",
            notifications=NotificationSettings(
                gameStart=True,
                scoring=True,
                homerun=True,
                reversal=True,
                gameEnd=True,
                lineupOpened=True,
                inningChange=True,
                allGames=False,
            ),
        )
    )
    sync_service = LiveActivityScoreboardSyncService(
        scoreboard_service=FakeScoreboardSequenceService(
            [
                _scoreboard_game(away_score=2, home_score=3, inning="7회말"),
                _scoreboard_game(away_score=2, home_score=3, inning="8회초"),
            ]
        ),
        push_service=push_service,
    )

    sync_service.sync_date("2026-06-04")
    response = sync_service.sync_date("2026-06-04")

    assert [call["moment"] for call in push_service.moment_calls] == ["inning_change"]
    assert response["pushedMoments"][0]["moment"] == "inning_change"


def test_push_config_status_reports_missing_release_secrets(tmp_path) -> None:
    settings = _settings(
        app_env="release",
        firebase_service_account_path=str(tmp_path / "missing-firebase.json"),
        push_registry_path=str(tmp_path / "runtime" / "push_registry.json"),
        apns_auth_key_path=str(tmp_path / "missing-apns.p8"),
        apns_use_sandbox=True,
        push_sync_secret="",
    )

    status = PushConfigurationDiagnostics(settings).status()

    assert status["ready"] is False
    assert status["readyForIphoneOnlyDemo"] is False
    assert "FIREBASE_SERVICE_ACCOUNT_PATH:file" in status["missing"]
    assert "APNS_AUTH_KEY_PATH:file" in status["missing"]
    assert "APNS_USE_SANDBOX=false" in status["missing"]
    assert "PUSH_SYNC_SECRET" in status["missing"]


def test_push_config_status_accepts_production_ready_paths(tmp_path) -> None:
    firebase_path = tmp_path / "firebase-service-account.json"
    apns_path = tmp_path / "AuthKey_TESTKEY.p8"
    firebase_path.write_text("{}", encoding="utf-8")
    apns_path.write_text(
        "-----BEGIN PRIVATE KEY-----\n-----END PRIVATE KEY-----\n", encoding="utf-8"
    )
    settings = _settings(
        app_env="release",
        firebase_service_account_path=str(firebase_path),
        push_registry_path=str(tmp_path / "runtime" / "push_registry.json"),
        apns_auth_key_path=str(apns_path),
        apns_use_sandbox=False,
        push_sync_secret="secret",
    )

    status = PushConfigurationDiagnostics(settings).status()

    assert status["ready"] is True
    assert status["readyForIphoneOnlyDemo"] is True
    assert status["missing"] == []
    assert status["firebase"]["serviceAccountFilename"] == "firebase-service-account.json"
    assert status["apns"]["authKeyFilename"] == "AuthKey_TESTKEY.p8"
    assert status["registry"]["parentWritable"] is True


def test_push_config_status_accepts_aws_secret_env_content(tmp_path) -> None:
    registry_path = tmp_path / "runtime" / "push_registry.json"
    PushRegistry(str(registry_path)).record_sync_heartbeat(
        {
            "date": "2026-06-04",
            "checkedGames": 1,
            "updatedGames": 1,
            "pushedMoments": 0,
        }
    )
    settings = _settings(
        app_env="release",
        firebase_service_account_path="",
        firebase_service_account_json='{"project_id":"kbo-fans"}',
        push_registry_path=str(registry_path),
        apns_auth_key_path="",
        apns_auth_key_p8="-----BEGIN PRIVATE KEY-----\n-----END PRIVATE KEY-----\n",
        apns_use_sandbox=False,
        push_sync_secret="secret",
    )

    status = PushConfigurationDiagnostics(settings).status()

    assert status["ready"] is True
    assert status["readyForIphoneOnlyDemo"] is True
    assert status["missing"] == []
    assert status["firebase"]["serviceAccountJsonConfigured"] is True
    assert status["firebase"]["serviceAccountJsonValid"] is True
    assert status["apns"]["authKeyContentConfigured"] is True
    assert status["scheduler"]["lastSyncDate"] == "2026-06-04"
    assert status["scheduler"]["lastCheckedGames"] == 1


def test_push_config_status_reports_registry_read_error(monkeypatch, tmp_path) -> None:
    def raise_permission_error(self) -> dict:
        raise PermissionError("registry unavailable")

    monkeypatch.setattr(PushRegistry, "sync_heartbeat", raise_permission_error)
    settings = _settings(
        app_env="release",
        firebase_service_account_path="",
        firebase_service_account_json='{"project_id":"kbo-fans"}',
        push_registry_path=str(tmp_path / "runtime" / "push_registry.json"),
        apns_auth_key_path="",
        apns_auth_key_p8="-----BEGIN PRIVATE KEY-----\n-----END PRIVATE KEY-----\n",
        apns_use_sandbox=False,
        push_sync_secret="secret",
    )

    status = PushConfigurationDiagnostics(settings).status()

    assert status["ready"] is False
    assert "PUSH_REGISTRY_PATH:readable" in status["missing"]
    assert status["scheduler"]["registryReadable"] is False
    assert status["scheduler"]["registryError"] == "PermissionError"


def test_push_config_status_rejects_invalid_firebase_json(tmp_path) -> None:
    settings = _settings(
        app_env="release",
        firebase_service_account_path="",
        firebase_service_account_json="{invalid-json",
        push_registry_path=str(tmp_path / "runtime" / "push_registry.json"),
        apns_auth_key_path="",
        apns_auth_key_p8="-----BEGIN PRIVATE KEY-----\n-----END PRIVATE KEY-----\n",
        apns_use_sandbox=False,
        push_sync_secret="secret",
    )

    status = PushConfigurationDiagnostics(settings).status()

    assert status["ready"] is False
    assert "FIREBASE_SERVICE_ACCOUNT_JSON:json" in status["missing"]


def test_push_config_status_endpoint_uses_sync_secret(monkeypatch) -> None:
    class SecretSettings:
        push_sync_secret = "secret"

    monkeypatch.setattr(push_routes, "get_settings", lambda: SecretSettings())
    monkeypatch.setattr(push_routes.diagnostics_service, "status", lambda: {"ready": True})
    client = TestClient(app)

    denied = client.get("/api/push/config-status")
    allowed = client.get(
        "/api/push/config-status",
        headers={"X-Kbo-Push-Sync-Secret": "secret"},
    )

    assert denied.status_code == 401
    assert allowed.status_code == 200
    assert allowed.json()["data"]["ready"] is True


def test_sync_scoreboard_endpoint_defaults_to_kbo_game_day(monkeypatch) -> None:
    class SecretSettings:
        push_sync_secret = "secret"

    captured = {}

    class FakeSyncService:
        def sync_date(self, target_date: str) -> dict:
            captured["date"] = target_date
            return {"date": target_date, "checkedGames": 0}

    monkeypatch.setattr(push_routes, "get_settings", lambda: SecretSettings())
    monkeypatch.setattr(push_routes, "current_kbo_date", lambda: "2026-06-04")
    monkeypatch.setattr(push_routes, "live_activity_sync_service", FakeSyncService())
    client = TestClient(app)

    response = client.post(
        "/api/push/live-activity/sync-scoreboard",
        headers={"X-Kbo-Push-Sync-Secret": "secret"},
    )

    assert response.status_code == 200
    assert captured["date"] == "2026-06-04"
    assert response.json()["data"]["date"] == "2026-06-04"


def test_apns_live_activity_payload_matches_ios_content_state_contract(tmp_path) -> None:
    settings = _settings(
        app_env="release",
        firebase_service_account_path="",
        push_registry_path=str(tmp_path / "runtime" / "push_registry.json"),
        apns_auth_key_path="",
        apns_use_sandbox=False,
        push_sync_secret="secret",
        apns_auth_key_p8="-----BEGIN PRIVATE KEY-----\n-----END PRIVATE KEY-----\n",
    )
    sender = ApnsLiveActivitySender(settings)
    state = LiveActivityContentState(
        awayTeamId="LG",
        awayTeam="LG",
        homeTeamId="KT",
        homeTeam="KT",
        awayScore=4,
        homeScore=3,
        inning="8회초",
        batter="김현수",
        pitcher="고영표",
        pitchCount=84,
        balls=2,
        strikes=1,
        outs=1,
        stadium="수원",
        updatedAt="21:20:30",
    )

    payload = sender._build_payload(
        state=state,
        event="update",
        stale_date=1_780_000_120,
        dismissal_date=None,
        relevance_score=100,
    )

    content_state = payload["aps"]["content-state"]
    assert set(content_state) == {
        "awayTeamId",
        "awayTeam",
        "homeTeamId",
        "homeTeam",
        "awayScore",
        "homeScore",
        "inning",
        "batter",
        "pitcher",
        "pitchCount",
        "balls",
        "strikes",
        "outs",
        "stadium",
        "updatedAt",
    }
    assert content_state["awayScore"] == 4
    assert content_state["homeScore"] == 3
    assert content_state["pitchCount"] == 84
    assert content_state["updatedAt"] == "21:20:30"
    assert payload["aps"]["event"] == "update"
    assert payload["aps"]["stale-date"] == 1_780_000_120
    assert payload["aps"]["relevance-score"] == 100
    assert "dismissal-date" not in payload["aps"]


class FakeLiveActivitySender:
    def __init__(self) -> None:
        self.calls = []

    def send(self, **kwargs):
        self.calls.append(kwargs)
        return {"sent": True, "apnsId": "apns-id", "statusCode": 200}


class FakePushService(PushService):
    def __init__(self, *, registry, live_activity_sender) -> None:
        super().__init__(registry=registry, live_activity_sender=live_activity_sender)
        self.moment_calls = []

    def send_game_moment(self, **kwargs):
        self.moment_calls.append(kwargs)
        return {
            "sent": True,
            "moment": kwargs["moment"],
            "messages": [
                {"topic": f"{kwargs['moment']}_{kwargs['away_team_id']}", "messageId": "away"},
                {"topic": f"{kwargs['moment']}_{kwargs['home_team_id']}", "messageId": "home"},
                {"topic": f"{kwargs['moment']}_ALL", "messageId": "all"},
            ],
        }


class FakeScoreboardService:
    def get_home_scoreboard(self, date: str):
        return {
            "date": date,
            "games": [_scoreboard_game(away_score=2, home_score=3, inning="7회말")],
        }


class FakeScoreboardSequenceService:
    def __init__(self, games) -> None:
        self.games = games
        self.index = 0

    def get_home_scoreboard(self, date: str):
        game = self.games[min(self.index, len(self.games) - 1)]
        self.index += 1
        return {"date": date, "games": [game]}


def _register_device_token_batch(
    registry_path: str,
    token_prefix: str,
    count: int,
) -> int:
    registry = PushRegistry(registry_path)
    service = PushService(registry=registry, live_activity_sender=FakeLiveActivitySender())
    for index in range(count):
        service.register(
            PushRegisterRequest(
                deviceToken=f"{token_prefix}-{index}",
                platform="ios",
                myTeam="LG",
                notifications=NotificationSettings(
                    gameStart=True,
                    scoring=True,
                    homerun=True,
                    reversal=True,
                    gameEnd=True,
                    lineupOpened=True,
                    inningChange=False,
                    allGames=False,
                ),
            )
        )
    return count


def _scoreboard_game(*, away_score: int, home_score: int, inning: str) -> dict:
    return {
        "gameId": "20260604LGKT0",
        "status": "LIVE",
        "inning": inning,
        "stadium": "수원",
        "away": {
            "teamId": "LG",
            "shortName": "LG",
            "score": away_score,
        },
        "home": {
            "teamId": "KT",
            "shortName": "KT",
            "score": home_score,
        },
    }


def _live_activity_state() -> LiveActivityContentState:
    return LiveActivityContentState(
        awayTeamId="LG",
        awayTeam="LG",
        homeTeamId="KT",
        homeTeam="KT",
        awayScore=2,
        homeScore=3,
        inning="7회말",
        stadium="수원",
        updatedAt="21:10:00",
    )


def _settings(
    *,
    app_env: str,
    firebase_service_account_path: str,
    push_registry_path: str,
    apns_auth_key_path: str,
    apns_use_sandbox: bool,
    push_sync_secret: str,
    firebase_service_account_json: str = "",
    apns_auth_key_p8: str = "",
) -> Settings:
    return Settings(
        app_name="KBO Fans API",
        app_env=app_env,
        debug=False,
        api_prefix="/api",
        request_timeout_seconds=10,
        kbo_base_url="https://www.koreabaseball.com",
        cors_allow_origin_regex=r"^https?://localhost$",
        kbo_relay_user_id="",
        kbo_relay_password="",
        firebase_service_account_path=firebase_service_account_path,
        firebase_service_account_json=firebase_service_account_json,
        firebase_project_id="kbo-fans",
        push_registry_path=push_registry_path,
        push_sync_secret=push_sync_secret,
        apns_key_id="TESTKEY",
        apns_team_id="TEAMID",
        apns_bundle_id="com.kbofans.kboFans",
        apns_auth_key_path=apns_auth_key_path,
        apns_auth_key_p8=apns_auth_key_p8,
        apns_use_sandbox=apns_use_sandbox,
        snapshot_dir="",
    )
