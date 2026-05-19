from __future__ import annotations

import concurrent.futures
import threading
from typing import Callable, Generic, TypeVar

K = TypeVar("K")
V = TypeVar("V")


class SingleFlight(Generic[K]):
    """Coalesces concurrent calls for the same key inside one process."""

    def __init__(self) -> None:
        self._lock = threading.Lock()
        self._in_flight: dict[K, concurrent.futures.Future] = {}

    def call(self, key: K, fn: Callable[[], V]) -> V:
        with self._lock:
            future = self._in_flight.get(key)
            if future is None:
                future = concurrent.futures.Future()
                self._in_flight[key] = future
                leader = True
            else:
                leader = False

        if not leader:
            return future.result()

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
