from types import SimpleNamespace

from fastapi.testclient import TestClient

from kbo_fans_backend.api.routes import scoreboard as scoreboard_routes
from kbo_fans_backend.main import app
from kbo_fans_backend.services.scoreboard import ScoreboardService


def test_normalize_date_accepts_compact_format() -> None:
    normalized = ScoreboardService._normalize_date("20260330")

    assert normalized == "2026-03-30"


def test_normalize_date_keeps_iso_format() -> None:
    normalized = ScoreboardService._normalize_date("2026-03-30")

    assert normalized == "2026-03-30"


def test_score_from_innings_fills_missing_live_total() -> None:
    score = ScoreboardService._score_from_innings(None, [1, 0, 0, 3, None])

    assert score == 4


def test_score_from_innings_keeps_existing_total() -> None:
    score = ScoreboardService._score_from_innings(7, [1, 0, 0, 3, None])

    assert score == 7


def test_cancelled_main_game_uses_cancel_label_for_inning() -> None:
    service = ScoreboardService()
    main_game = {
        "GAME_STATE_SC": "4",
        "CANCEL_SC_NM": "우천취소",
        "G_TM": "18:30",
        "GAME_INN_NO": 0,
        "GAME_TB_SC_NM": "초",
    }

    assert service._format_inning(main_game) == "우천취소"
    assert service._status_label_for_main_game("CANCELLED", main_game) == "우천취소"


def test_public_scoreboard_force_refresh_keeps_backend_ttl(monkeypatch) -> None:
    captured = {}
    monkeypatch.setattr(
        scoreboard_routes.service,
        "get_scoreboard",
        lambda date, force_refresh=False: (
            captured.update({"date": date, "forceRefresh": force_refresh})
            or {"date": date, "games": []}
        ),
    )
    client = TestClient(app)

    response = client.get("/api/scoreboard?date=2026-03-30&forceRefresh=true")

    assert response.status_code == 200
    assert captured == {
        "date": "2026-03-30",
        "forceRefresh": False,
    }


def test_trusted_scoreboard_force_refresh_bypasses_backend_ttl(monkeypatch) -> None:
    captured = {}
    monkeypatch.setattr(
        scoreboard_routes,
        "get_settings",
        lambda: SimpleNamespace(push_sync_secret="internal-secret"),
    )
    monkeypatch.setattr(
        scoreboard_routes.service,
        "get_scoreboard",
        lambda date, force_refresh=False: (
            captured.update({"date": date, "forceRefresh": force_refresh})
            or {"date": date, "games": []}
        ),
    )
    client = TestClient(app)

    response = client.get(
        "/api/scoreboard?date=2026-03-30&forceRefresh=true",
        headers={"X-KBO-Push-Sync-Secret": "internal-secret"},
    )

    assert response.status_code == 200
    assert captured == {
        "date": "2026-03-30",
        "forceRefresh": True,
    }


def test_public_home_scoreboard_force_refresh_keeps_backend_ttl(monkeypatch) -> None:
    captured = {}
    monkeypatch.setattr(
        scoreboard_routes.service,
        "get_home_scoreboard",
        lambda date, force_refresh=False: (
            captured.update({"date": date, "forceRefresh": force_refresh})
            or {"date": date, "games": []}
        ),
    )
    client = TestClient(app)

    response = client.get("/api/scoreboard/home?date=2026-03-30&forceRefresh=true")

    assert response.status_code == 200
    assert captured == {
        "date": "2026-03-30",
        "forceRefresh": False,
    }


def test_trusted_home_scoreboard_force_refresh_bypasses_backend_ttl(
    monkeypatch,
) -> None:
    captured = {}
    monkeypatch.setattr(
        scoreboard_routes,
        "get_settings",
        lambda: SimpleNamespace(push_sync_secret="internal-secret"),
    )
    monkeypatch.setattr(
        scoreboard_routes.service,
        "get_home_scoreboard",
        lambda date, force_refresh=False: (
            captured.update({"date": date, "forceRefresh": force_refresh})
            or {"date": date, "games": []}
        ),
    )
    client = TestClient(app)

    response = client.get(
        "/api/scoreboard/home?date=2026-03-30&forceRefresh=true",
        headers={"X-KBO-Push-Sync-Secret": "internal-secret"},
    )

    assert response.status_code == 200
    assert captured == {
        "date": "2026-03-30",
        "forceRefresh": True,
    }


def test_wrong_force_refresh_secret_keeps_backend_ttl(monkeypatch) -> None:
    captured = {}
    monkeypatch.setattr(
        scoreboard_routes,
        "get_settings",
        lambda: SimpleNamespace(push_sync_secret="internal-secret"),
    )
    monkeypatch.setattr(
        scoreboard_routes.service,
        "get_scoreboard",
        lambda date, force_refresh=False: (
            captured.update({"date": date, "forceRefresh": force_refresh})
            or {"date": date, "games": []}
        ),
    )
    client = TestClient(app)

    response = client.get(
        "/api/scoreboard?date=2026-03-30&forceRefresh=true",
        headers={"X-KBO-Push-Sync-Secret": "wrong-secret"},
    )

    assert response.status_code == 200
    assert captured["forceRefresh"] is False
