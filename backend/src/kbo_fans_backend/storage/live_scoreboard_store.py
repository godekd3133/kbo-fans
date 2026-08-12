from __future__ import annotations

import fcntl
import json
import tempfile
import threading
from contextlib import contextmanager
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Iterator, Optional

from kbo_fans_backend.core.config import get_settings


class LiveScoreboardStore:
    """Short-lived shared state written by the sync worker and read by API workers."""

    _thread_locks: dict[Path, threading.Lock] = {}
    _thread_locks_guard = threading.Lock()

    def __init__(
        self,
        path: Optional[str] = None,
        max_age_seconds: Optional[int] = None,
        max_entries: Optional[int] = None,
    ) -> None:
        settings = get_settings()
        self.path = Path(path or settings.live_scoreboard_state_path).expanduser()
        self.max_age_seconds = (
            max_age_seconds
            if max_age_seconds is not None
            else settings.live_scoreboard_max_age_seconds
        )
        self.max_entries = max(1, int(max_entries if max_entries is not None else 14))
        self._lock_path = self.path.with_name(f"{self.path.name}.lock")
        self._thread_lock = self._thread_lock_for_path(self._lock_path)

    @classmethod
    def _thread_lock_for_path(cls, path: Path) -> threading.Lock:
        with cls._thread_locks_guard:
            lock = cls._thread_locks.get(path)
            if lock is None:
                lock = threading.Lock()
                cls._thread_locks[path] = lock
            return lock

    def load_fresh(self, date: str) -> Optional[dict[str, Any]]:
        data = self._load()
        records = data.get("scoreboards", {})
        if not isinstance(records, dict):
            return None

        record = records.get(date)
        if not isinstance(record, dict):
            return None

        saved_at = _parse_datetime(record.get("savedAt"))
        if saved_at is None:
            return None
        age_seconds = (datetime.now(timezone.utc) - saved_at).total_seconds()
        if age_seconds < 0 or age_seconds > self.max_age_seconds:
            return None

        payload = record.get("payload")
        if not isinstance(payload, dict) or payload.get("date") != date:
            return None
        if not isinstance(payload.get("games"), list):
            return None
        return payload

    def save(self, date: str, payload: dict[str, Any]) -> None:
        with self._mutate_data() as data:
            records = data.setdefault("scoreboards", {})
            if not isinstance(records, dict):
                records = {}
                data["scoreboards"] = records
            records[date] = {
                "savedAt": datetime.now(timezone.utc).isoformat(),
                "payload": payload,
            }
            _prune_oldest_records(records, self.max_entries)

    def _load(self) -> dict[str, Any]:
        if not self.path.exists():
            return {"scoreboards": {}}
        try:
            data = json.loads(self.path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            return {"scoreboards": {}}
        if not isinstance(data, dict):
            return {"scoreboards": {}}
        data.setdefault("scoreboards", {})
        return data

    @contextmanager
    def _mutate_data(self) -> Iterator[dict[str, Any]]:
        self.path.parent.mkdir(parents=True, exist_ok=True)
        self._lock_path.parent.mkdir(parents=True, exist_ok=True)
        with self._thread_lock:
            with self._lock_path.open("a+", encoding="utf-8") as lock_file:
                fcntl.flock(lock_file.fileno(), fcntl.LOCK_EX)
                data = self._load()
                try:
                    yield data
                    self._atomic_write(
                        json.dumps(data, ensure_ascii=False, indent=2, sort_keys=True)
                    )
                finally:
                    fcntl.flock(lock_file.fileno(), fcntl.LOCK_UN)

    def _atomic_write(self, content: str) -> None:
        self.path.parent.mkdir(parents=True, exist_ok=True)
        with tempfile.NamedTemporaryFile(
            "w",
            encoding="utf-8",
            delete=False,
            dir=self.path.parent,
        ) as temp_file:
            temp_file.write(content)
            temp_name = temp_file.name
        Path(temp_name).replace(self.path)


def _parse_datetime(value: Any) -> Optional[datetime]:
    if not isinstance(value, str) or not value:
        return None
    try:
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return None
    if parsed.tzinfo is None:
        return parsed.replace(tzinfo=timezone.utc)
    return parsed.astimezone(timezone.utc)


def _prune_oldest_records(records: dict[str, Any], max_entries: int) -> None:
    if len(records) <= max_entries:
        return
    ordered = sorted(
        records.items(),
        key=lambda item: (
            str(item[1].get("savedAt") or "") if isinstance(item[1], dict) else "",
            str(item[0]),
        ),
    )
    for date, _ in ordered[: max(0, len(records) - max_entries)]:
        records.pop(date, None)
