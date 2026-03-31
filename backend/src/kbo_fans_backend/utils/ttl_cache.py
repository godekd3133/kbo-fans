from __future__ import annotations

import copy
import time
from typing import Dict, Generic, Optional, Tuple, TypeVar

K = TypeVar("K")
V = TypeVar("V")


class TtlCache(Generic[K, V]):
    def __init__(self, ttl_seconds: int) -> None:
        self.ttl_seconds = ttl_seconds
        self._store: Dict[K, Tuple[float, V]] = {}

    def get(self, key: K) -> Optional[V]:
        cached = self._store.get(key)
        if cached is None:
            return None

        cached_at, value = cached
        if time.monotonic() - cached_at > self.ttl_seconds:
            self._store.pop(key, None)
            return None

        return copy.deepcopy(value)

    def set(self, key: K, value: V) -> None:
        self._store[key] = (time.monotonic(), copy.deepcopy(value))

    def get_stale(self, key: K) -> Optional[V]:
        cached = self._store.get(key)
        if cached is None:
            return None
        return copy.deepcopy(cached[1])
