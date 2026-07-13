from __future__ import annotations

import copy
import threading
import time
from typing import Dict, Generic, Optional, Tuple, TypeVar

K = TypeVar("K")
V = TypeVar("V")


class TtlCache(Generic[K, V]):
    def __init__(self, ttl_seconds: int, max_entries: int = 256) -> None:
        if max_entries < 1:
            raise ValueError("max_entries must be at least 1")
        self.ttl_seconds = ttl_seconds
        self.max_entries = max_entries
        self._store: Dict[K, Tuple[float, V]] = {}
        self._lock = threading.Lock()

    def get(self, key: K) -> Optional[V]:
        now = time.monotonic()
        with self._lock:
            cached = self._store.get(key)
        if cached is None:
            return None

        cached_at, value = cached
        if now - cached_at > self.ttl_seconds:
            return None

        return copy.deepcopy(value)

    def set(self, key: K, value: V) -> None:
        cached_at = time.monotonic()
        cached_value = copy.deepcopy(value)
        with self._lock:
            if key not in self._store and len(self._store) >= self.max_entries:
                oldest_key = min(
                    self._store,
                    key=lambda stored_key: self._store[stored_key][0],
                )
                self._store.pop(oldest_key, None)
            self._store[key] = (cached_at, cached_value)

    def get_stale(self, key: K) -> Optional[V]:
        with self._lock:
            cached = self._store.get(key)
        if cached is None:
            return None
        return copy.deepcopy(cached[1])
