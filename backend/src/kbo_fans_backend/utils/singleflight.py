from __future__ import annotations

import concurrent.futures
import threading
from typing import Callable, Generic, Optional, TypeVar

from kbo_fans_backend.utils.resilience import UpstreamBusyError

K = TypeVar("K")
V = TypeVar("V")


class SingleFlight(Generic[K]):
    """Coalesces concurrent calls for the same key inside one process."""

    def __init__(self, wait_timeout_seconds: Optional[float] = 10.0) -> None:
        self._lock = threading.Lock()
        self._in_flight: dict[K, concurrent.futures.Future] = {}
        self._wait_timeout_seconds = wait_timeout_seconds

    def call(
        self,
        key: K,
        fn: Callable[[], V],
        *,
        wait_timeout_seconds: Optional[float] = None,
    ) -> V:
        with self._lock:
            future = self._in_flight.get(key)
            if future is None:
                future = concurrent.futures.Future()
                self._in_flight[key] = future
                leader = True
            else:
                leader = False

        if not leader:
            effective_timeout = (
                wait_timeout_seconds
                if wait_timeout_seconds is not None
                else self._wait_timeout_seconds
            )
            try:
                return future.result(timeout=effective_timeout)
            except concurrent.futures.TimeoutError as error:
                raise UpstreamBusyError(f"singleflight wait timed out for {key}") from error

        try:
            result = fn()
        except BaseException as error:
            future.set_exception(error)
            raise
        else:
            future.set_result(result)
            return result
        finally:
            with self._lock:
                if self._in_flight.get(key) is future:
                    self._in_flight.pop(key, None)
