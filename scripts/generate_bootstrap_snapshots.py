#!/usr/bin/env python3

from __future__ import annotations

import json
import shutil
from datetime import datetime, timezone
from pathlib import Path

import requests

ROOT = Path(__file__).resolve().parents[1]
BOOTSTRAP_DIR = ROOT / "app/assets/bootstrap"
API_BASE = "http://127.0.0.1:8000/api"
SEASONS = range(2001, datetime.now().year + 1)
SNAPSHOT_DIR = ROOT / "backend/data/snapshots"


def fetch(path: str, season: int) -> dict:
    response = requests.get(f"{API_BASE}{path}", params={"season": season}, timeout=120)
    response.raise_for_status()
    return response.json().get("data", {})


def main() -> None:
    BOOTSTRAP_DIR.mkdir(parents=True, exist_ok=True)
    generated_at = datetime.now(timezone.utc).isoformat()

    standings = {"generatedAt": generated_at, "seasons": {}}
    records_overview = {"generatedAt": generated_at, "seasons": {}}

    for season in SEASONS:
        standings["seasons"][str(season)] = fetch("/standings", season)
        records_overview["seasons"][str(season)] = fetch("/records/overview", season)

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
