from __future__ import annotations

from typing import Callable, Generic, TypeVar

from kbo_fans_backend.utils.singleflight import SingleFlight
from kbo_fans_backend.utils.ttl_cache import TtlCache

K = TypeVar("K")
V = TypeVar("V")


class KboSourceCache(Generic[K, V]):
    """Share a short-lived raw KBO response across sibling services."""

    def __init__(
        self,
        loader: Callable[[K], V],
        *,
        ttl_seconds: int,
    ) -> None:
        self._loader = loader
        self._cache: TtlCache[K, V] = TtlCache(max(1, ttl_seconds))
        self._singleflight: SingleFlight[K] = SingleFlight()

    def get(self, key: K, *, force_refresh: bool = False) -> V:
        if not force_refresh:
            cached = self._cache.get(key)
            if cached is not None:
                return cached

        # Normal and forced callers intentionally share the same key. A force
        # request arriving while normal work is in flight joins that result
        # instead of creating an overlapping source request; a force request
        # arriving after a cache hit bypasses the cache and refreshes it.
        return self._singleflight.call(
            key,
            lambda: self._load(key, force_refresh=force_refresh),
        )

    def _load(self, key: K, *, force_refresh: bool) -> V:
        if not force_refresh:
            cached = self._cache.get(key)
            if cached is not None:
                return cached

        value = self._loader(key)
        self._cache.set(key, value)
        return value
