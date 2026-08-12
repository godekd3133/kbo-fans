import json

from kbo_fans_backend.storage.live_scoreboard_store import LiveScoreboardStore


def test_live_scoreboard_store_prunes_oldest_dates(tmp_path) -> None:
    path = tmp_path / "live-scoreboard.json"
    store = LiveScoreboardStore(path=str(path), max_entries=2)

    for date in ("2026-08-09", "2026-08-10", "2026-08-11"):
        store.save(date, {"date": date, "games": []})

    data = json.loads(path.read_text(encoding="utf-8"))

    assert set(data["scoreboards"]) == {"2026-08-10", "2026-08-11"}
