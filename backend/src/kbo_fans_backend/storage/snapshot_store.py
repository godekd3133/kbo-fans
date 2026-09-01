from __future__ import annotations

import json
import re
from datetime import datetime, timezone
from pathlib import Path
from tempfile import NamedTemporaryFile
from typing import Any, Optional

from kbo_fans_backend.core.config import get_settings


class JsonSnapshotStore:
    def __init__(
        self,
        base_dir: Optional[str] = None,
        *,
        seed_dir: Optional[str] = None,
    ) -> None:
        if base_dir is not None:
            self.base_dir = Path(base_dir)
            self.seed_dir = Path(seed_dir) if seed_dir else None
            return

        settings = get_settings()
        self.base_dir = Path(settings.snapshot_dir)
        configured_seed_dir = seed_dir or settings.snapshot_seed_dir
        self.seed_dir = Path(configured_seed_dir) if configured_seed_dir else None

    def load(self, namespace: str, key: str) -> Optional[dict[str, Any]]:
        path = self._path_for(namespace, key)
        record = self._read(path)
        if record is not None:
            return record

        if self.seed_dir is None:
            return None
        seed_path = self._path_for(namespace, key, base_dir=self.seed_dir)
        if seed_path == path:
            return None
        return self._read(seed_path)

    def load_payload(self, namespace: str, key: str) -> Optional[Any]:
        record = self.load(namespace, key)
        if record is None:
            return None
        return record.get("payload")

    def load_recent_payload(
        self,
        namespace: str,
        key: str,
        max_age_seconds: float,
    ) -> Optional[Any]:
        """Read a process-shared runtime cache entry only while it is fresh.

        Historical snapshots intentionally have no time-based revalidation
        policy. This helper is for the separate short-lived runtime cache
        namespaces used by live-data warmers, so an API process can reuse data
        written by a worker process without turning it into immutable history.
        """
        if max_age_seconds < 0:
            return None
        record = self.load(namespace, key)
        if record is None:
            return None
        saved_at = _parse_datetime(record.get("savedAt"))
        if saved_at is None:
            return None
        age_seconds = (datetime.now(timezone.utc) - saved_at).total_seconds()
        if age_seconds < 0 or age_seconds > max_age_seconds:
            return None
        return record.get("payload")

    def save(self, namespace: str, key: str, payload: Any) -> None:
        path = self._path_for(namespace, key)
        path.parent.mkdir(parents=True, exist_ok=True)
        record = {
            "savedAt": datetime.now(timezone.utc).isoformat(),
            "payload": payload,
        }
        self._atomic_write(path, json.dumps(record, ensure_ascii=False, indent=2))

    def delete(self, namespace: str, key: str) -> None:
        """Remove one ephemeral runtime entry identified by an exact key."""
        try:
            self._path_for(namespace, key).unlink()
        except FileNotFoundError:
            return

    def _path_for(
        self,
        namespace: str,
        key: str,
        *,
        base_dir: Optional[Path] = None,
    ) -> Path:
        safe_namespace = self._sanitize(namespace)
        safe_key = self._sanitize(key)
        return (base_dir or self.base_dir) / safe_namespace / f"{safe_key}.json"

    @staticmethod
    def _read(path: Path) -> Optional[dict[str, Any]]:
        if not path.exists():
            return None
        try:
            record = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            return None
        return record if isinstance(record, dict) else None

    @staticmethod
    def _sanitize(value: str) -> str:
        sanitized = re.sub(r"[^A-Za-z0-9._-]+", "_", value)
        return sanitized.strip("._") or "snapshot"

    @staticmethod
    def _atomic_write(path: Path, content: str) -> None:
        with NamedTemporaryFile("w", encoding="utf-8", delete=False, dir=path.parent) as temp_file:
            temp_file.write(content)
            temp_name = temp_file.name
        Path(temp_name).replace(path)


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
