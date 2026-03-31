from __future__ import annotations

import json
import re
from datetime import datetime, timezone
from pathlib import Path
from tempfile import NamedTemporaryFile
from typing import Any, Optional

from kbo_fans_backend.core.config import get_settings


class JsonSnapshotStore:
    def __init__(self, base_dir: Optional[str] = None) -> None:
        settings = get_settings()
        self.base_dir = Path(base_dir or settings.snapshot_dir)

    def load(self, namespace: str, key: str) -> Optional[dict[str, Any]]:
        path = self._path_for(namespace, key)
        if not path.exists():
            return None

        try:
            return json.loads(path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            return None

    def load_payload(self, namespace: str, key: str) -> Optional[Any]:
        record = self.load(namespace, key)
        if record is None:
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

    def _path_for(self, namespace: str, key: str) -> Path:
        safe_namespace = self._sanitize(namespace)
        safe_key = self._sanitize(key)
        return self.base_dir / safe_namespace / f"{safe_key}.json"

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
