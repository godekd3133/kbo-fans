#!/usr/bin/env python3

from __future__ import annotations

import json
import shutil
from datetime import datetime, timezone
from pathlib import Path
from typing import Optional

ROOT = Path(__file__).resolve().parents[1]
BOOTSTRAP_DIR = ROOT / "app/assets/bootstrap"
CURRENT_SEASON = datetime.now(timezone.utc).year
SEASONS = range(2001, CURRENT_SEASON + 1)
SNAPSHOT_DIR = ROOT / "backend/data/snapshots"


def main() -> None:
    BOOTSTRAP_DIR.mkdir(parents=True, exist_ok=True)
    generated_at = datetime.now(timezone.utc).isoformat()

    standings = build_standings_bootstrap(generated_at)
    records_overview = build_records_overview_bootstrap(generated_at)

    (BOOTSTRAP_DIR / "standings.json").write_text(
        json.dumps(standings, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )
    (BOOTSTRAP_DIR / "records_overview.json").write_text(
        json.dumps(records_overview, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )
    sync_snapshot_directory("team_players")
    sync_snapshot_directory("team_stats")


def build_standings_bootstrap(generated_at: str) -> dict:
    data = {
        "generatedAt": generated_at,
        "source": "backend/data/snapshots/standings_latest/{season}.json",
        "policy": "exact-season-only; current season requires freshness; unverified seasons stay empty",
        "seasons": {str(season): empty_standings(season) for season in SEASONS},
    }
    record = load_snapshot_record(
        SNAPSHOT_DIR / "standings_latest" / f"{CURRENT_SEASON}.json"
    )
    payload = (record or {}).get("payload") or {}
    if has_standings(payload):
        data["generatedAt"] = record.get("savedAt") or generated_at
        data["seasons"][str(CURRENT_SEASON)] = payload
    return data


def build_records_overview_bootstrap(generated_at: str) -> dict:
    data = {
        "generatedAt": generated_at,
        "source": "backend/data/snapshots/records_overview/{season}.json",
        "policy": "exact-season-only; current season requires freshness; unverified seasons stay empty",
        "seasons": {str(season): empty_records_overview(season) for season in SEASONS},
    }
    record = load_snapshot_record(
        SNAPSHOT_DIR / "records_overview" / f"{CURRENT_SEASON}.json"
    )
    payload = (record or {}).get("payload") or {}
    if has_records_overview(payload):
        data["generatedAt"] = record.get("savedAt") or generated_at
        data["seasons"][str(CURRENT_SEASON)] = payload
    return data


def load_snapshot_record(path: Path) -> Optional[dict]:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return None


def empty_standings(season: int) -> dict:
    return {"season": season, "standings": []}


def empty_records_overview(season: int) -> dict:
    return {
        "season": season,
        "leaders": {"avg": [], "hr": [], "ops": [], "opsPlus": [], "era": []},
        "featured": {},
    }


def has_standings(payload: dict) -> bool:
    return bool(payload.get("standings"))


def has_records_overview(payload: dict) -> bool:
    leaders = payload.get("leaders") or {}
    return any(leaders.get(key) for key in ("avg", "hr", "ops", "opsPlus", "era"))


def sync_snapshot_directory(name: str) -> None:
    source_dir = SNAPSHOT_DIR / name
    target_dir = BOOTSTRAP_DIR / name
    if not source_dir.exists():
        return

    target_dir.mkdir(parents=True, exist_ok=True)
    for path in source_dir.glob("*.json"):
        target_path = target_dir / path.name
        if name == "team_stats" and not is_complete_team_stats(path):
            target_path.unlink(missing_ok=True)
            continue
        shutil.copy2(path, target_path)


def is_complete_team_stats(path: Path) -> bool:
    try:
        payload = json.loads(path.read_text(encoding="utf-8")).get("payload") or {}
    except (OSError, json.JSONDecodeError):
        return False
    return bool(payload.get("hitting")) and bool(payload.get("pitching"))


if __name__ == "__main__":
    main()
