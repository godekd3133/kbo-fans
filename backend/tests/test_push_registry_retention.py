import json
from datetime import datetime, timedelta, timezone

from kbo_fans_backend.services.push_registry import PushRegistry, _empty_registry


def test_runtime_state_and_pending_outbox_are_pruned_by_age(tmp_path) -> None:
    now = datetime(2026, 8, 11, 12, tzinfo=timezone.utc)
    old = (now - timedelta(seconds=11)).isoformat()
    fresh = (now - timedelta(seconds=2)).isoformat()
    data = _empty_registry()
    data["scoreboardStates"] = {
        "old-game": {"gameId": "old-game", "status": "FINAL", "updatedAt": old},
        "fresh-game": {"gameId": "fresh-game", "status": "LIVE", "updatedAt": fresh},
    }
    data["relayStates"] = {
        "old-game": {"gameId": "old-game", "updatedAt": old},
    }
    data["pushOutbox"] = {
        "old-event": {
            "eventId": "old-event",
            "kind": "game_moment",
            "payload": {},
            "targets": {"device": {"status": "pending", "updatedAt": old}},
            "createdAt": old,
            "updatedAt": old,
        },
        "fresh-event": {
            "eventId": "fresh-event",
            "kind": "game_moment",
            "payload": {},
            "targets": {"device": {"status": "pending", "updatedAt": fresh}},
            "createdAt": fresh,
            "updatedAt": fresh,
        },
    }
    path = tmp_path / "push-registry.json"
    path.write_text(json.dumps(data), encoding="utf-8")

    registry = PushRegistry(
        path=str(path),
        runtime_state_ttl_seconds=10,
        outbox_pending_ttl_seconds=10,
        runtime_state_now_provider=lambda: now,
    )
    registry.record_sync_heartbeat({"checkedGames": 0})

    assert registry.scoreboard_state("old-game") is None
    assert registry.scoreboard_state("fresh-game") is not None
    assert registry.relay_state("old-game") is None
    assert registry.push_outbox_event("old-event") is None
    assert registry.push_outbox_event("fresh-event") is not None


def test_nested_live_activity_start_states_are_pruned_by_age(tmp_path) -> None:
    now = datetime(2026, 8, 11, 12, tzinfo=timezone.utc)
    old = (now - timedelta(seconds=11)).isoformat()
    fresh = (now - timedelta(seconds=2)).isoformat()
    data = _empty_registry()
    data["liveActivityStartStates"] = {
        "old-game": {
            "old-token": {
                "status": "sent",
                "sentAt": old,
                "updatedAt": old,
            }
        },
        "fresh-game": {
            "fresh-token": {
                "status": "sent",
                "sentAt": fresh,
                "updatedAt": fresh,
            }
        },
    }
    path = tmp_path / "push-registry.json"
    path.write_text(json.dumps(data), encoding="utf-8")

    registry = PushRegistry(
        path=str(path),
        runtime_state_ttl_seconds=10,
        runtime_state_now_provider=lambda: now,
    )
    registry.record_sync_heartbeat({"checkedGames": 0})

    persisted = json.loads(path.read_text(encoding="utf-8"))
    assert "old-game" not in persisted["liveActivityStartStates"]
    assert "fresh-game" in persisted["liveActivityStartStates"]


def test_identical_sync_heartbeat_does_not_rewrite_registry_every_tick(tmp_path) -> None:
    now = datetime(2026, 8, 11, 12, tzinfo=timezone.utc)
    path = tmp_path / "push-registry.json"
    registry = PushRegistry(
        path=str(path),
        runtime_state_now_provider=lambda: now,
    )

    first = registry.record_sync_heartbeat({"checkedGames": 1})
    first_bytes = path.read_bytes()
    second = registry.record_sync_heartbeat({"checkedGames": 1})

    assert second == first
    assert path.read_bytes() == first_bytes

    now = now + timedelta(seconds=31)
    third = registry.record_sync_heartbeat({"checkedGames": 1})
    assert third["updatedAt"] != first["updatedAt"]
