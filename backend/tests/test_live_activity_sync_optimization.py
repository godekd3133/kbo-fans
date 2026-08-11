from __future__ import annotations

import threading
import time
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone
from pathlib import Path

from kbo_fans_backend.schemas.push import (
    LiveActivityRegisterRequest,
    NotificationSettings,
    PushRegisterRequest,
)
from kbo_fans_backend.services import push_registry as push_registry_module
from kbo_fans_backend.services.apns_live_activity import ApnsLiveActivitySendError
from kbo_fans_backend.services.live_activity_scoreboard import (
    LiveActivityScoreboardSyncService,
)
from kbo_fans_backend.services.push import PushService
from kbo_fans_backend.services.push_registry import PushRegistry


class _ScoreboardService:
    def __init__(self, game: dict) -> None:
        self.game = game

    def get_home_scoreboard(self, date: str) -> dict:
        return {"date": date, "games": [self.game]}


class _RelayService:
    def __init__(self) -> None:
        self.calls: list[dict] = []

    def get_relay(self, game_id: str, after=None) -> dict:
        self.calls.append({"gameId": game_id, "after": after})
        return {
            "gameId": game_id,
            "relayItems": [],
            "currentAtBat": {
                "inningText": "7회말",
                "batter": {"name": "장성우", "average": "0.281"},
                "pitcher": {"name": "김진성", "pitchCount": 77, "era": "3.14"},
                "ballCount": {"balls": 1, "strikes": 2, "outs": 1},
                "baseState": "주자1루",
            },
        }


class _LiveActivitySender:
    def __init__(self, *, fail_count: int = 0) -> None:
        self.calls: list[dict] = []
        self.fail_count = fail_count

    def send(self, **kwargs) -> dict:
        self.calls.append(kwargs)
        if self.fail_count > 0:
            self.fail_count -= 1
            raise RuntimeError("temporary APNs failure")
        return {"sent": True, "statusCode": 200, "apnsId": "test-apns-id"}


class _PermanentFailureSender(_LiveActivitySender):
    def send(self, **kwargs) -> dict:
        self.calls.append(kwargs)
        raise ApnsLiveActivitySendError(
            operation="send",
            status_code=410,
            reason="Unregistered",
            response_text='{"reason":"Unregistered"}',
        )


def test_sync_fetches_relay_once_for_moments_and_live_activity(tmp_path) -> None:
    registry = PushRegistry(str(tmp_path / "push_registry.json"))
    sender = _LiveActivitySender()
    push_service = PushService(registry=registry, live_activity_sender=sender)
    push_service.register(
        PushRegisterRequest(
            deviceToken="fcm-token",
            platform="ios",
            myTeam="LG",
            notifications=_notification_settings(),
        )
    )
    _register_live_activity(push_service)
    relay_service = _RelayService()
    service = _sync_service(
        registry=registry,
        sender=sender,
        game=_game(),
        relay_service=relay_service,
    )

    response = service.sync_date("2026-06-04")

    assert len(relay_service.calls) == 1
    assert relay_service.calls[0] == {"gameId": "20260604LGKT0", "after": None}
    assert response["updatedGames"][0]["sent"] is True
    assert sender.calls[0]["state"].batter == "장성우"


def test_unchanged_content_is_skipped_across_sync_service_reconstruction(tmp_path) -> None:
    registry_path = str(tmp_path / "push_registry.json")
    sender = _LiveActivitySender()
    first_registry = PushRegistry(registry_path)
    first_push_service = PushService(
        registry=first_registry,
        live_activity_sender=sender,
    )
    _register_live_activity(first_push_service)

    first = _sync_service(
        registry=first_registry,
        sender=sender,
        game=_game(),
    ).sync_date("2026-06-04")
    second = _sync_service(
        registry=PushRegistry(registry_path),
        sender=sender,
        game=_game(),
    ).sync_date("2026-06-04")
    changed = _sync_service(
        registry=PushRegistry(registry_path),
        sender=sender,
        game=_game(home_score=4),
    ).sync_date("2026-06-04")

    assert len(first["updatedGames"]) == 1
    assert second["updatedGames"] == []
    assert len(changed["updatedGames"]) == 1
    assert len(sender.calls) == 2
    assert sender.calls[1]["state"].homeScore == 4


def test_partial_update_retry_targets_only_the_failed_activity(tmp_path) -> None:
    registry_path = str(tmp_path / "push_registry.json")
    sender = _LiveActivitySender(fail_count=1)
    first_registry = PushRegistry(registry_path)
    push_service = PushService(registry=first_registry, live_activity_sender=sender)
    _register_live_activity(push_service, token="activity-token-a", activity_id="activity-a")
    _register_live_activity(push_service, token="activity-token-b", activity_id="activity-b")

    first = _sync_service(
        registry=first_registry,
        sender=sender,
        game=_game(),
    ).sync_date("2026-06-04")
    retried = _sync_service(
        registry=PushRegistry(registry_path),
        sender=sender,
        game=_game(),
    ).sync_date("2026-06-04")

    assert first["updatedGames"][0]["sent"] is True
    assert retried["updatedGames"][0]["sent"] is True
    assert [call["activity_push_token"] for call in sender.calls] == [
        "activity-token-a",
        "activity-token-b",
        "activity-token-a",
    ]


def test_expired_batch_claim_is_fenced_before_stale_sender_call(monkeypatch, tmp_path) -> None:
    class _DelayedFirstTokenSender(_LiveActivitySender):
        def __init__(self) -> None:
            super().__init__()
            self.stale_first_call_started = threading.Event()
            self.release_stale_first_call = threading.Event()
            self._calls_lock = threading.Lock()

        def send(self, **kwargs) -> dict:
            with self._calls_lock:
                self.calls.append(kwargs)
            if (
                kwargs["activity_push_token"] == "activity-token-a"
                and kwargs["state"].homeScore == 3
            ):
                self.stale_first_call_started.set()
                assert self.release_stale_first_call.wait(timeout=5)
            return {"sent": True, "statusCode": 200, "apnsId": "test-apns-id"}

    monkeypatch.setattr(push_registry_module, "_LIVE_ACTIVITY_UPDATE_LEASE_SECONDS", 0.05)
    registry_path = str(tmp_path / "push_registry.json")
    sender = _DelayedFirstTokenSender()
    first_registry = PushRegistry(registry_path)
    first_push_service = PushService(
        registry=first_registry,
        live_activity_sender=sender,
    )
    _register_live_activity(
        first_push_service,
        token="activity-token-a",
        activity_id="activity-a",
    )
    _register_live_activity(
        first_push_service,
        token="activity-token-b",
        activity_id="activity-b",
    )

    with ThreadPoolExecutor(max_workers=2) as executor:
        stale_future = executor.submit(
            _sync_service(
                registry=first_registry,
                sender=sender,
                game=_game(home_score=3),
            ).sync_date,
            "2026-06-04",
        )
        assert sender.stale_first_call_started.wait(timeout=5)
        time.sleep(0.08)
        latest_future = executor.submit(
            _sync_service(
                registry=PushRegistry(registry_path),
                sender=sender,
                game=_game(home_score=4),
            ).sync_date,
            "2026-06-04",
        )
        latest = latest_future.result(timeout=5)
        sender.release_stale_first_call.set()
        stale = stale_future.result(timeout=5)

    assert latest["updatedGames"][0]["sent"] is True
    assert stale["updatedGames"][0]["sent"] is True
    token_b_scores = [
        call["state"].homeScore
        for call in sender.calls
        if call["activity_push_token"] == "activity-token-b"
    ]
    assert token_b_scores == [4]


def test_a_b_a_generation_invalidates_unfenced_intermediate_delivery(tmp_path) -> None:
    class _BlockingFenceRegistry(PushRegistry):
        def __init__(self, path: str) -> None:
            super().__init__(path)
            self.fence_started = threading.Event()
            self.release_fence = threading.Event()

        def fence_live_activity_update(self, **kwargs) -> bool:
            self.fence_started.set()
            assert self.release_fence.wait(timeout=5)
            return super().fence_live_activity_update(**kwargs)

    registry_path = str(tmp_path / "push_registry.json")
    sender = _LiveActivitySender()
    first_registry = PushRegistry(registry_path)
    first_push_service = PushService(
        registry=first_registry,
        live_activity_sender=sender,
    )
    _register_live_activity(first_push_service)
    initial_game = _game()
    intermediate_game = {**_game(), "stadium": "잠실"}
    initial = _sync_service(
        registry=first_registry,
        sender=sender,
        game=initial_game,
    ).sync_date("2026-06-04")
    assert initial["updatedGames"][0]["sent"] is True

    intermediate_registry = _BlockingFenceRegistry(registry_path)
    with ThreadPoolExecutor(max_workers=1) as executor:
        intermediate_future = executor.submit(
            _sync_service(
                registry=intermediate_registry,
                sender=sender,
                game=intermediate_game,
            ).sync_date,
            "2026-06-04",
        )
        assert intermediate_registry.fence_started.wait(timeout=5)
        returned = _sync_service(
            registry=PushRegistry(registry_path),
            sender=sender,
            game=initial_game,
        ).sync_date("2026-06-04")
        intermediate_registry.release_fence.set()
        intermediate = intermediate_future.result(timeout=5)

    assert returned["updatedGames"] == []
    assert intermediate["updatedGames"][0]["sent"] is False
    assert intermediate["updatedGames"][0]["messages"][0]["reason"] == "stale_delivery_claim"
    assert [call["state"].stadium for call in sender.calls] == ["수원"]


def test_sender_fence_renews_lease_and_expired_fence_can_be_reclaimed(
    monkeypatch,
    tmp_path,
) -> None:
    monkeypatch.setattr(push_registry_module, "_LIVE_ACTIVITY_UPDATE_LEASE_SECONDS", 0.2)
    registry_path = str(tmp_path / "push_registry.json")
    registry = PushRegistry(registry_path)
    claim = registry.claim_live_activity_updates(
        game_id="20260604LGKT0",
        delivery_ids=["delivery-a"],
        content_signature="signature-a",
    )
    claim_id = claim["delivery-a"]

    time.sleep(0.12)
    assert registry.fence_live_activity_update(
        game_id="20260604LGKT0",
        delivery_id="delivery-a",
        content_signature="signature-a",
        claim_id=claim_id,
    )
    time.sleep(0.12)
    blocked = PushRegistry(registry_path).claim_live_activity_updates(
        game_id="20260604LGKT0",
        delivery_ids=["delivery-a"],
        content_signature="signature-b",
    )

    time.sleep(0.12)
    reclaimed = PushRegistry(registry_path).claim_live_activity_updates(
        game_id="20260604LGKT0",
        delivery_ids=["delivery-a"],
        content_signature="signature-b",
    )

    assert blocked == {}
    assert set(reclaimed) == {"delivery-a"}
    assert reclaimed["delivery-a"] != claim_id


def test_expired_fenced_intermediate_delivery_claims_returned_content_for_restore(
    monkeypatch,
    tmp_path,
) -> None:
    monkeypatch.setattr(push_registry_module, "_LIVE_ACTIVITY_UPDATE_LEASE_SECONDS", 0.05)
    registry = PushRegistry(str(tmp_path / "push_registry.json"))
    first_claim = registry.claim_live_activity_updates(
        game_id="20260604LGKT0",
        delivery_ids=["delivery-a"],
        content_signature="signature-a",
    )["delivery-a"]
    assert registry.fence_live_activity_update(
        game_id="20260604LGKT0",
        delivery_id="delivery-a",
        content_signature="signature-a",
        claim_id=first_claim,
    )
    assert registry.complete_live_activity_update(
        game_id="20260604LGKT0",
        delivery_id="delivery-a",
        content_signature="signature-a",
        claim_id=first_claim,
    )

    intermediate_claim = registry.claim_live_activity_updates(
        game_id="20260604LGKT0",
        delivery_ids=["delivery-a"],
        content_signature="signature-b",
    )["delivery-a"]
    assert registry.fence_live_activity_update(
        game_id="20260604LGKT0",
        delivery_id="delivery-a",
        content_signature="signature-b",
        claim_id=intermediate_claim,
    )
    time.sleep(0.08)

    restore_claims = registry.claim_live_activity_updates(
        game_id="20260604LGKT0",
        delivery_ids=["delivery-a"],
        content_signature="signature-a",
    )

    assert set(restore_claims) == {"delivery-a"}
    assert restore_claims["delivery-a"] != intermediate_claim
    assert not registry.fence_live_activity_update(
        game_id="20260604LGKT0",
        delivery_id="delivery-a",
        content_signature="signature-b",
        claim_id=intermediate_claim,
    )


def test_permanent_update_failure_prunes_registration_and_is_not_retried(tmp_path) -> None:
    registry_path = str(tmp_path / "push_registry.json")
    sender = _PermanentFailureSender()
    registry = PushRegistry(registry_path)
    push_service = PushService(registry=registry, live_activity_sender=sender)
    _register_live_activity(push_service)

    failed = _sync_service(
        registry=registry,
        sender=sender,
        game=_game(),
    ).sync_date("2026-06-04")
    repeated = _sync_service(
        registry=PushRegistry(registry_path),
        sender=sender,
        game=_game(),
    ).sync_date("2026-06-04")

    assert failed["updatedGames"][0]["sent"] is False
    assert failed["updatedGames"][0]["messages"][0]["permanentTokenFailure"] is True
    assert repeated["updatedGames"] == []
    assert len(sender.calls) == 1
    data = PushRegistry(registry_path)._load()
    assert data["liveActivities"] == {}
    assert "20260604LGKT0" not in data.get("liveActivityUpdateStates", {})


def test_terminal_end_retries_after_failure_and_removes_registration(tmp_path) -> None:
    registry_path = str(tmp_path / "push_registry.json")
    sender = _LiveActivitySender(fail_count=1)
    first_registry = PushRegistry(registry_path)
    first_push_service = PushService(
        registry=first_registry,
        live_activity_sender=sender,
    )
    _register_live_activity(first_push_service)
    final_game = _game(status="FINAL", inning="경기종료")

    failed = _sync_service(
        registry=first_registry,
        sender=sender,
        game=final_game,
    ).sync_date("2026-06-04")
    retry_registry = PushRegistry(registry_path)
    retried = _sync_service(
        registry=retry_registry,
        sender=sender,
        game=final_game,
    ).sync_date("2026-06-04")

    assert failed["updatedGames"][0]["sent"] is False
    assert retried["updatedGames"][0]["sent"] is True
    assert [call["event"] for call in sender.calls] == ["end", "end"]
    assert retry_registry.live_activity_tokens_for_game("20260604LGKT0") == []


def test_permanent_terminal_end_failure_prunes_registration_without_retry(tmp_path) -> None:
    registry_path = str(tmp_path / "push_registry.json")
    sender = _PermanentFailureSender()
    registry = PushRegistry(registry_path)
    push_service = PushService(registry=registry, live_activity_sender=sender)
    _register_live_activity(push_service)
    final_game = _game(status="FINAL", inning="경기종료")

    failed = _sync_service(
        registry=registry,
        sender=sender,
        game=final_game,
    ).sync_date("2026-06-04")
    repeated = _sync_service(
        registry=PushRegistry(registry_path),
        sender=sender,
        game=final_game,
    ).sync_date("2026-06-04")

    assert failed["updatedGames"][0]["sent"] is False
    assert failed["updatedGames"][0]["messages"][0]["permanentTokenFailure"] is True
    assert repeated["updatedGames"] == []
    assert len(sender.calls) == 1
    assert PushRegistry(registry_path).live_activity_tokens_for_game("20260604LGKT0") == []


def test_update_claims_batch_writes_once_and_unchanged_claim_is_disk_noop(
    tmp_path,
) -> None:
    registry_path = Path(tmp_path / "push_registry.json")
    registry = _CountingPushRegistry(str(registry_path))
    delivery_ids = ["delivery-a", "delivery-b"]

    claims = registry.claim_live_activity_updates(
        game_id="20260604LGKT0",
        delivery_ids=delivery_ids,
        content_signature="signature-1",
    )
    registry.resolve_live_activity_updates(
        game_id="20260604LGKT0",
        content_signature="signature-1",
        completed_claims=claims,
        released_claims={},
    )

    assert set(claims) == set(delivery_ids)
    assert registry.save_count == 2
    unchanged_mtime = registry_path.stat().st_mtime_ns

    unchanged = registry.claim_live_activity_updates(
        game_id="20260604LGKT0",
        delivery_ids=delivery_ids,
        content_signature="signature-1",
    )

    assert unchanged == {}
    assert registry.save_count == 2
    assert registry_path.stat().st_mtime_ns == unchanged_mtime


def test_terminal_end_removes_delivery_signature_state(tmp_path) -> None:
    registry = PushRegistry(str(tmp_path / "push_registry.json"))
    push_service = PushService(registry=registry, live_activity_sender=_LiveActivitySender())
    _register_live_activity(push_service)
    delivery_id = _delivery_id("activity-token")
    claims = registry.claim_live_activity_updates(
        game_id="20260604LGKT0",
        delivery_ids=[delivery_id],
        content_signature="signature-1",
    )
    registry.resolve_live_activity_updates(
        game_id="20260604LGKT0",
        content_signature="signature-1",
        completed_claims=claims,
        released_claims={},
    )

    claim_id = registry.claim_live_activity_end(
        game_id="20260604LGKT0",
        activity_push_token="activity-token",
    )
    assert claim_id is not None
    assert registry.complete_live_activity_end(
        game_id="20260604LGKT0",
        activity_push_token="activity-token",
        claim_id=claim_id,
    )

    data = registry._load()
    assert "20260604LGKT0" not in data["liveActivityUpdateStates"]


class _CountingPushRegistry(PushRegistry):
    def __init__(self, path: str) -> None:
        super().__init__(path)
        self.save_count = 0

    def _save_unlocked(self, data: dict) -> None:
        self.save_count += 1
        super()._save_unlocked(data)


def _delivery_id(token: str) -> str:
    import hashlib

    return hashlib.sha256(token.encode("utf-8")).hexdigest()


def _sync_service(
    *,
    registry: PushRegistry,
    sender: _LiveActivitySender,
    game: dict,
    relay_service=None,
) -> LiveActivityScoreboardSyncService:
    return LiveActivityScoreboardSyncService(
        scoreboard_service=_ScoreboardService(game),
        push_service=PushService(registry=registry, live_activity_sender=sender),
        relay_service=relay_service,
        now_provider=lambda: datetime(2026, 6, 4, 12, 0, tzinfo=timezone.utc),
    )


def _register_live_activity(
    push_service: PushService,
    *,
    token: str = "activity-token",
    activity_id: str = "activity-1",
) -> None:
    push_service.register_live_activity(
        LiveActivityRegisterRequest(
            gameId="20260604LGKT0",
            activityId=activity_id,
            activityPushToken=token,
            installationId="installation-1",
        )
    )


def _notification_settings() -> NotificationSettings:
    return NotificationSettings(
        gameStart=True,
        scoring=True,
        hit=True,
        homerun=True,
        reversal=True,
        gameEnd=True,
        lineupOpened=True,
        inningChange=True,
        allGames=False,
    )


def _game(
    *,
    away_score: int = 2,
    home_score: int = 3,
    status: str = "LIVE",
    inning: str = "7회말",
) -> dict:
    return {
        "gameId": "20260604LGKT0",
        "status": status,
        "inning": inning,
        "stadium": "수원",
        "current": {
            "batterName": "장성우",
            "pitcherName": "김진성",
            "balls": 1,
            "strikes": 2,
            "outs": 1,
        },
        "away": {"teamId": "LG", "shortName": "LG", "score": away_score},
        "home": {"teamId": "KT", "shortName": "KT", "score": home_score},
    }
